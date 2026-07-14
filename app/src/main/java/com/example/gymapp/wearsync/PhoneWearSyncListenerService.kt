package com.example.gymapp.wearsync

import android.os.SystemClock
import com.example.gymapp.GymApplication
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.data.repository.WearMutationApplyResult
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.WearableListenerService
import java.util.LinkedHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch

internal const val PHONE_WEAR_MUTATION_QUEUE_CAPACITY = 8
internal const val PHONE_WEAR_FULL_REQUEST_QUEUE_CAPACITY = 2

internal fun <T> boundedPhoneWearChannel(capacity: Int): Channel<T> {
    require(capacity in 1..32)
    return Channel(capacity = capacity)
}

internal suspend fun runPhoneWearConsumerItem(block: suspend () -> Unit) {
    try {
        block()
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        // A transient transport/database failure rejects only this message. The fixed consumer
        // must remain alive for retries; no payload or account data is logged.
    }
}

class PhoneWearSyncListenerService : WearableListenerService() {
    private data class InboundMessage(
        val sourceNodeId: String,
        val path: String,
        val payload: ByteArray
    )

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutationQueue = boundedPhoneWearChannel<InboundMessage>(
        PHONE_WEAR_MUTATION_QUEUE_CAPACITY
    )
    private val fullSyncRequestQueue = boundedPhoneWearChannel<InboundMessage>(
        PHONE_WEAR_FULL_REQUEST_QUEUE_CAPACITY
    )
    private val reconnectQueue = Channel<String>(capacity = Channel.CONFLATED)
    private val recentFullSyncRequests = LinkedHashMap<String, Unit>()
    private val enqueueRateLock = Any()
    private var lastFullSyncRequestEnqueuedAt = Long.MIN_VALUE

    override fun onCreate() {
        super.onCreate()
        serviceScope.launch {
            for (message in mutationQueue) {
                runPhoneWearConsumerItem {
                    handleMessage(message.sourceNodeId, message.path, message.payload)
                }
            }
        }
        serviceScope.launch {
            for (message in fullSyncRequestQueue) {
                runPhoneWearConsumerItem {
                    handleMessage(message.sourceNodeId, message.path, message.payload)
                }
            }
        }
        serviceScope.launch {
            for (sourceNodeId in reconnectQueue) {
                runPhoneWearConsumerItem {
                    val application = applicationContext as GymApplication
                    application.phoneWearSyncManager
                        .pushCurrentStateToReconnectedPinnedSource(sourceNodeId)
                }
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)
        if (
            messageEvent.path !in PhoneWearPaths.inboundPaths ||
            messageEvent.data.isEmpty() ||
            messageEvent.data.size > PhoneWearPaths.MAX_MESSAGE_BYTES
        ) {
            return
        }
        val application = applicationContext as GymApplication
        if (!application.phoneWearSyncManager.fastSourceMayBeTrusted(messageEvent.sourceNodeId)) return
        if (
            messageEvent.path == PhoneWearPaths.REQUEST_FULL_SYNC &&
            !allowFullSyncRequestEnqueue()
        ) {
            return
        }
        val message = InboundMessage(
            sourceNodeId = messageEvent.sourceNodeId,
            path = messageEvent.path,
            payload = messageEvent.data.copyOf()
        )
        if (message.path == PhoneWearPaths.REQUEST_FULL_SYNC) {
            fullSyncRequestQueue.trySend(message)
        } else {
            mutationQueue.trySend(message)
        }
    }

    private suspend fun handleMessage(sourceNodeId: String, path: String, payload: ByteArray) {
        val application = applicationContext as GymApplication
        val syncManager = application.phoneWearSyncManager
        if (!syncManager.authorizeSource(sourceNodeId)) return
        val parsed = PhoneWearProtocol.parse(path, payload)
        if (parsed !is PhoneWearParseResult.Valid) return

        when (val command = parsed.command) {
            is PhoneWearCommand.RequestFull -> {
                if (!acceptFullSyncRequest(sourceNodeId, command.envelope.operationId)) return
                syncManager.sendCurrentFullSync(sourceNodeId)
            }
            is PhoneWearCommand.CreateWorkout,
            is PhoneWearCommand.UpdateSet,
            is PhoneWearCommand.DeleteSet -> handleMutation(
                sourceNodeId = sourceNodeId,
                command = command,
                payloadDigest = parsed.canonicalPayloadDigest,
                application = application,
                syncManager = syncManager
            )
        }
    }

    private suspend fun handleMutation(
        sourceNodeId: String,
        command: PhoneWearCommand,
        payloadDigest: String,
        application: GymApplication,
        syncManager: PhoneWearSyncManager
    ) {
        val (session, binding) = syncManager.currentSessionAndBinding()
        val envelope = command.envelope
        if (
            session == null ||
            binding.signedOut ||
            !syncManager.isPinnedToCurrentOwner(sourceNodeId, binding) ||
            envelope.ownerId != binding.ownerId ||
            envelope.accountGeneration != binding.accountGeneration
        ) {
            syncManager.sendMutationAck(
                sourceNodeId = sourceNodeId,
                binding = binding,
                operationId = envelope.operationId,
                accepted = false
            )
            return
        }

        val repository = application.repositoryFor(session)
        if (!syncManager.isCurrent(binding)) return
        val result = runCatching {
            when (command) {
                is PhoneWearCommand.CreateWorkout -> repository.applyWearCreateWorkout(
                    ownerId = binding.ownerId,
                    accountGeneration = binding.accountGeneration,
                    operationId = envelope.operationId,
                    sourceNodeId = sourceNodeId,
                    payloadDigest = payloadDigest,
                    date = command.startedAt,
                    note = command.note,
                    sets = command.sets.map { set ->
                        NamedWorkoutSetDraft(
                            exerciseName = set.exerciseName,
                            weight = set.weight,
                            reps = set.reps
                        )
                    }
                )

                is PhoneWearCommand.UpdateSet -> repository.applyWearUpdateSet(
                    ownerId = binding.ownerId,
                    accountGeneration = binding.accountGeneration,
                    operationId = envelope.operationId,
                    sourceNodeId = sourceNodeId,
                    payloadDigest = payloadDigest,
                    setId = command.setId,
                    weight = command.weight,
                    reps = command.reps
                )

                is PhoneWearCommand.DeleteSet -> repository.applyWearDeleteSet(
                    ownerId = binding.ownerId,
                    accountGeneration = binding.accountGeneration,
                    operationId = envelope.operationId,
                    sourceNodeId = sourceNodeId,
                    payloadDigest = payloadDigest,
                    setId = command.setId
                )

                is PhoneWearCommand.RequestFull -> error("Not a mutation")
            }
        }.getOrElse { error ->
            if (error is CancellationException) throw error
            WearMutationApplyResult.Rejected
        }

        // The receipt and database mutation committed in the same Room transaction. Re-check the
        // phone authority after commit so an account transition can never receive an old accepted
        // acknowledgement.
        if (!syncManager.isCurrent(binding)) return
        syncManager.sendMutationAck(
            sourceNodeId = sourceNodeId,
            binding = binding,
            operationId = envelope.operationId,
            accepted = result != WearMutationApplyResult.Rejected
        )
        if (result != WearMutationApplyResult.Rejected) {
            syncManager.sendCurrentFullSync(sourceNodeId, force = true)
        }
    }

    override fun onPeerConnected(peer: Node) {
        super.onPeerConnected(peer)
        reconnectQueue.trySend(peer.id)
    }

    private fun acceptFullSyncRequest(sourceNodeId: String, operationId: String): Boolean {
        val key = "$sourceNodeId:$operationId"
        if (recentFullSyncRequests.containsKey(key)) return false
        recentFullSyncRequests[key] = Unit
        while (recentFullSyncRequests.size > MAX_RECENT_FULL_SYNC_REQUESTS) {
            val eldest = recentFullSyncRequests.entries.iterator()
            if (!eldest.hasNext()) break
            eldest.next()
            eldest.remove()
        }
        return true
    }

    private fun allowFullSyncRequestEnqueue(): Boolean = synchronized(enqueueRateLock) {
        val now = SystemClock.elapsedRealtime()
        if (
            lastFullSyncRequestEnqueuedAt != Long.MIN_VALUE &&
            now - lastFullSyncRequestEnqueuedAt < FULL_SYNC_ENQUEUE_COOLDOWN_MS
        ) {
            return false
        }
        lastFullSyncRequestEnqueuedAt = now
        true
    }

    override fun onDestroy() {
        mutationQueue.close()
        fullSyncRequestQueue.close()
        reconnectQueue.close()
        serviceScope.cancel()
        super.onDestroy()
    }

    private companion object {
        const val MAX_RECENT_FULL_SYNC_REQUESTS = 256
        const val FULL_SYNC_ENQUEUE_COOLDOWN_MS = 1_000L
    }
}
