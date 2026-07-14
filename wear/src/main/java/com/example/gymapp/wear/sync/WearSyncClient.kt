package com.example.gymapp.wear.sync

import android.content.Context
import com.example.gymapp.wear.data.WearWorkoutSetDraft
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.Wearable
import java.util.UUID
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

class WearSyncClient(
    context: Context
) {
    private val appContext = context.applicationContext

    suspend fun requestFullSync() {
        val binding = WatchSyncBindingStorage.load(appContext)
        val payload = WatchSyncJson.buildFullSyncRequestPayload(newOperationId(), binding)
        sendToPhone(SyncPaths.REQUEST_FULL_SYNC, payload.toByteArray(Charsets.UTF_8), binding)
    }

    suspend fun createWorkout(
        binding: WatchSyncBinding,
        draftId: String,
        startedAt: Long,
        note: String?,
        sets: List<WearWorkoutSetDraft>,
        sourcePlanRaw: String?
    ): PendingWorkoutMutation {
        requireAccountBinding(binding)
        val pending = WatchPendingWorkoutStorage.getOrCreate(
            context = appContext,
            binding = binding,
            draftId = draftId,
            startedAt = startedAt,
            note = note,
            sets = sets,
            sourcePlanRaw = sourcePlanRaw
        )
        val operationId = pending.operationId
        val payload = WatchSyncJson.buildCreateWorkoutPayload(
            operationId = operationId,
            binding = binding,
            startedAt = pending.startedAt,
            note = pending.note,
            sets = pending.sets
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
        expectedBinding: WatchSyncBinding?
    ) {
        require(payload.size <= SyncPaths.MAX_MESSAGE_BYTES) { "Sync payload is too large" }
        val node = resolveTrustedNode(expectedBinding)
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

    private suspend fun resolveTrustedNode(expectedBinding: WatchSyncBinding?): Node {
        val nodes = Wearable.getNodeClient(appContext).connectedNodes.await()
        if (nodes.isEmpty()) throw IllegalStateException("Phone not connected")

        if (expectedBinding != null) {
            check(WatchSyncBindingStorage.load(appContext) == expectedBinding) {
                "Watch binding changed before transmission"
            }
            return nodes.firstOrNull { it.id == expectedBinding.sourceNodeId }
                ?: throw IllegalStateException("Bound phone not connected")
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

    private class MutationRejectedException : IllegalStateException("Phone rejected the operation")
}
