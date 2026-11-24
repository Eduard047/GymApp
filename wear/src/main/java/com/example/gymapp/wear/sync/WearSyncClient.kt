package com.example.gymapp.wear.sync

import android.content.Context
import android.os.SystemClock
import com.example.gymapp.wear.data.WearWorkoutSetDraft
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.Wearable
import java.util.UUID
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

/**
 * A phone node this watch asked for a sync while its pinned phone was not connected. Memory only
 * and short-lived: after a process death the answer is dropped and the next request asks again.
 * Only a full sync is ever accepted from it (WatchBindingRules.decideFullSync); no workout is
 * sent to it before it became the pinned phone.
 */
object WatchRelinkCandidate {
    private const val LIFETIME_MS = 120_000L
    private val lock = Any()
    private var nodeId: String? = null
    private var setAt = 0L

    fun set(candidateNodeId: String) = synchronized(lock) {
        nodeId = candidateNodeId
        setAt = SystemClock.elapsedRealtime()
    }

    fun current(): String? = synchronized(lock) {
        val candidate = nodeId ?: return null
        if (SystemClock.elapsedRealtime() - setAt > LIFETIME_MS) {
            nodeId = null
            return null
        }
        candidate
    }

    fun clear() = synchronized(lock) { nodeId = null }
}

class WearSyncClient(
    context: Context
) {
    private val appContext = context.applicationContext

    /**
     * Asks the phone for a full sync. After an explicit unlink nothing is sent until the user asks
     * to link again ([linkIntent]); the request then carries `link: true`, which is the only thing
     * that lets the phone pin a watch its user unlinked.
     */
    suspend fun requestFullSync(linkIntent: Boolean = false) {
        if (linkIntent) {
            WatchSyncBindingStorage.markLinkRequested(appContext)
        } else if (WatchSyncBindingStorage.isUnlinked(appContext)) {
            throw IllegalStateException("Watch is unlinked")
        }
        val binding = WatchSyncBindingStorage.load(appContext)
        val payload = WatchSyncJson.buildFullSyncRequestPayload(newOperationId(), binding, linkIntent)
        sendToPhone(
            path = SyncPaths.REQUEST_FULL_SYNC,
            payload = payload.toByteArray(Charsets.UTF_8),
            expectedBinding = binding,
            allowRelinkCandidate = true
        )
    }

    suspend fun createWorkout(
        binding: WatchSyncBinding,
        draftId: String,
        startedAt: Long,
        note: String?,
        sets: List<WearWorkoutSetDraft>,
        sourcePlanRaw: String?,
        durationSeconds: Long? = null,
        averageHeartRate: Int? = null,
        maxHeartRate: Int? = null
    ): PendingWorkoutMutation {
        requireAccountBinding(binding)
        val pending = WatchPendingWorkoutStorage.getOrCreate(
            context = appContext,
            binding = binding,
            draftId = draftId,
            startedAt = startedAt,
            note = note,
            sets = sets,
            sourcePlanRaw = sourcePlanRaw,
            durationSeconds = durationSeconds,
            averageHeartRate = averageHeartRate,
            maxHeartRate = maxHeartRate
        )
        val operationId = pending.operationId
        val payload = WatchSyncJson.buildCreateWorkoutPayload(
            operationId = operationId,
            binding = binding,
            startedAt = pending.startedAt,
            note = pending.note,
            sets = pending.sets,
            durationSeconds = pending.durationSeconds,
            averageHeartRate = pending.averageHeartRate,
            maxHeartRate = pending.maxHeartRate
        ).toByteArray(Charsets.UTF_8)
        try {
            sendMutation(SyncPaths.CREATE_WORKOUT, payload, operationId, binding)
            return pending
        } catch (rejected: MutationRejectedException) {
            WatchPendingWorkoutStorage.clearIfMatches(appContext, pending)
            throw rejected
        }
    }

    suspend fun updateSet(binding: WatchSyncBinding, setId: Long, weight: Double, reps: Int) {
        requireAccountBinding(binding)
        val operationId = newOperationId()
        val payload = WatchSyncJson.buildUpdateSetPayload(
            operationId = operationId,
            binding = binding,
            setId = setId,
            weight = weight,
            reps = reps
        ).toByteArray(Charsets.UTF_8)
        sendMutation(SyncPaths.UPDATE_SET, payload, operationId, binding)
    }

    suspend fun deleteSet(binding: WatchSyncBinding, setId: Long) {
        requireAccountBinding(binding)
        val operationId = newOperationId()
        val payload = WatchSyncJson.buildDeleteSetPayload(
            operationId = operationId,
            binding = binding,
            setId = setId
        ).toByteArray(Charsets.UTF_8)
        sendMutation(SyncPaths.DELETE_SET, payload, operationId, binding)
    }

    private fun requireAccountBinding(binding: WatchSyncBinding) {
        if (binding.ownerId == null || binding.accountGeneration <= 0L) {
            throw IllegalStateException("Watch is not bound to an account")
        }
    }

    private suspend fun sendToPhone(
        path: String,
        payload: ByteArray,
        expectedBinding: WatchSyncBinding?,
        allowRelinkCandidate: Boolean = false
    ) {
        require(payload.size <= SyncPaths.MAX_MESSAGE_BYTES) { "Sync payload is too large" }
        val node = resolveTrustedNode(expectedBinding, allowRelinkCandidate)
        Wearable.getMessageClient(appContext)
            .sendMessage(node.id, path, payload)
            .await()
    }

    private suspend fun sendMutation(
        path: String,
        payload: ByteArray,
        operationId: String,
        binding: WatchSyncBinding
    ) {
        val acknowledgement = WatchSyncAckRegistry.register(operationId)
        try {
            sendToPhone(path, payload, binding)
            val accepted = withTimeout(30_000L) { acknowledgement.await() }
            if (!accepted) throw MutationRejectedException()
        } finally {
            WatchSyncAckRegistry.cancel(operationId)
        }
    }

    private suspend fun resolveTrustedNode(
        expectedBinding: WatchSyncBinding?,
        allowRelinkCandidate: Boolean
    ): Node {
        val nodes = Wearable.getNodeClient(appContext).connectedNodes.await()
        if (nodes.isEmpty()) throw IllegalStateException("Phone not connected")

        if (expectedBinding != null) {
            // Node, owner and generation must be unchanged; a sync revision that moved in the
            // meantime does not make the prepared message wrong.
            check(
                WatchBindingRules.sameSendIdentity(
                    expectedBinding,
                    WatchSyncBindingStorage.load(appContext)
                )
            ) { "Watch binding changed before transmission" }
            nodes.firstOrNull { it.id == expectedBinding.sourceNodeId }?.let { return it }
            // The pinned phone is gone. A sync REQUEST (never a workout) may go to the only other
            // node; its answer moves the pin only under WatchBindingRules.decideFullSync.
            if (allowRelinkCandidate && nodes.size == 1) {
                val candidate = nodes.single()
                WatchRelinkCandidate.set(candidate.id)
                return candidate
            }
            throw IllegalStateException("Bound phone not connected")
        }

        val binding = WatchSyncBindingStorage.load(appContext)
        if (binding != null) throw IllegalStateException("Watch binding changed before transmission")

        if (nodes.size != 1) {
            throw IllegalStateException("Cannot select a trusted phone")
        }
        val selected = nodes.single()
        WatchSyncBindingStorage.pinSourceNode(appContext, selected.id)
        return selected
    }

    private fun newOperationId(): String = UUID.randomUUID().toString()

    /** The phone answered and refused the operation (as opposed to: no answer at all). */
    class MutationRejectedException internal constructor() :
        IllegalStateException("Phone rejected the operation")
}
