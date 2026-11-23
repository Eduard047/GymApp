package com.example.gymapp.wear.sync

import com.example.gymapp.wear.WearGymApplication
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch

class WatchSyncListenerService : WearableListenerService() {
    private data class QueuedMessage(
        val sourceNodeId: String,
        val path: String,
        val data: ByteArray
    )

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val inboundMessages = Channel<QueuedMessage>(capacity = MAX_PENDING_MESSAGES)

    init {
        serviceScope.launch {
            for (message in inboundMessages) {
                // One consumer gives deterministic storage ordering. A malformed message or
                // transient write failure must not terminate the consumer.
                runCatching { processMessage(message) }
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)
        if (
            messageEvent.path !in SUPPORTED_PATHS ||
            messageEvent.data.isEmpty() ||
            messageEvent.data.size > SyncPaths.MAX_MESSAGE_BYTES
        ) {
            return
        }
        // Reject an unexpected node before copying/parsing up to 100 KiB. Overflow is dropped;
        // every protocol stream is revisioned or explicitly retryable.
        val binding = WatchSyncBindingStorage.load(applicationContext) ?: return
        if (binding.sourceNodeId != messageEvent.sourceNodeId) return
        inboundMessages.trySend(
            QueuedMessage(
                sourceNodeId = messageEvent.sourceNodeId,
                path = messageEvent.path,
                data = messageEvent.data.copyOf()
            )
        )
    }

    private suspend fun processMessage(message: QueuedMessage) {
        val rawPayload = message.data.toString(Charsets.UTF_8)
        when (message.path) {
            SyncPaths.FULL_SYNC_PAYLOAD -> handleFullSync(message.sourceNodeId, rawPayload)
            SyncPaths.PUSH_WORKOUT_PLAN -> handleWorkoutPlan(message.sourceNodeId, rawPayload)
            SyncPaths.MUTATION_ACK -> handleMutationAck(message.sourceNodeId, rawPayload)
        }
    }

    private suspend fun handleFullSync(sourceNodeId: String, rawPayload: String) {
        val parsed = WatchSyncJson.parseFullSyncPayload(rawPayload)
        if (parsed !is WatchSyncParseResult.Valid) return

        val payload = parsed.value
        val envelope = payload.envelope
        val binding = WatchSyncBindingStorage.load(applicationContext) ?: return
        if (binding.sourceNodeId != sourceNodeId) return

        val ownerChanged = binding.ownerId != null && binding.ownerId != envelope.ownerId
        val ownerUnbound = binding.ownerId == null
        val minimumGeneration = binding.accountGeneration
        if (ownerChanged && envelope.accountGeneration <= minimumGeneration) return
        if (!ownerChanged && !ownerUnbound && envelope.accountGeneration < minimumGeneration) return
        val generationChanged = !ownerChanged &&
            !ownerUnbound &&
            envelope.accountGeneration > minimumGeneration
        val previousRevision = if (
            binding.ownerId == envelope.ownerId &&
            binding.accountGeneration == envelope.accountGeneration
        ) {
            binding.fullSyncRevision
        } else {
            0L
        }
        if (envelope.revision < previousRevision) return
        if (envelope.revision == previousRevision) {
            WatchSyncStageStorage.clearFullSyncIfMatches(applicationContext, envelope)
            return
        }
        if (!stageAllows(WatchSyncStageStorage.loadFullSync(applicationContext), envelope)) return

        // This durable stage is written before Room/preferences. After any crash, a delayed
        // lower revision is rejected until this exact message (or a newer one) completes.
        WatchSyncStageStorage.stageFullSync(applicationContext, envelope)
        val app = applicationContext as WearGymApplication
        if (ownerChanged || ownerUnbound || generationChanged) {
            // Clear the previous account before changing the binding. A crash can leave an
            // empty watch, but never expose the previous account's data under the new owner.
            app.repository.replaceSessionsFromSync(emptyList())
            WatchPlanStorage.clear(applicationContext)
            WatchExerciseCatalogStorage.save(applicationContext, emptyList())
            WatchSyncStageStorage.clearPlan(applicationContext)
            WatchSyncBindingStorage.acceptFullSync(
                context = applicationContext,
                sourceNodeId = sourceNodeId,
                ownerId = envelope.ownerId,
                accountGeneration = envelope.accountGeneration,
                revision = 0L
            )
        }
        app.repository.replaceSessionsFromSync(payload.sessions)
        WatchExerciseCatalogStorage.save(applicationContext, payload.exerciseCatalog)
        WatchSyncBindingStorage.acceptFullSync(
            context = applicationContext,
            sourceNodeId = sourceNodeId,
            ownerId = envelope.ownerId,
            accountGeneration = envelope.accountGeneration,
            revision = envelope.revision
        )
        WatchSyncStageStorage.clearFullSyncIfMatches(applicationContext, envelope)
    }

    private fun handleWorkoutPlan(sourceNodeId: String, rawPayload: String) {
        val parsed = WatchSyncJson.parseWorkoutPlanPayload(rawPayload)
        if (parsed !is WatchSyncParseResult.Valid) return

        val payload = parsed.value
        val envelope = payload.envelope
        val binding = WatchSyncBindingStorage.load(applicationContext) ?: return
        if (
            binding.sourceNodeId != sourceNodeId ||
            binding.ownerId != envelope.ownerId ||
            binding.accountGeneration != envelope.accountGeneration ||
            envelope.revision < binding.planRevision
        ) {
            return
        }
        if (envelope.revision == binding.planRevision) {
            WatchSyncStageStorage.clearPlanIfMatches(applicationContext, envelope)
            return
        }
        if (!stageAllows(WatchSyncStageStorage.loadPlan(applicationContext), envelope)) return

        WatchSyncStageStorage.stagePlan(applicationContext, envelope)
        WatchPlanStorage.save(applicationContext, rawPayload)
        WatchExerciseCatalogStorage.save(applicationContext, payload.exerciseCatalog)
        WatchSyncBindingStorage.acceptPlan(applicationContext, envelope.revision)
        WatchSyncStageStorage.clearPlanIfMatches(applicationContext, envelope)
    }

    private fun handleMutationAck(sourceNodeId: String, rawPayload: String) {
        val parsed = WatchSyncJson.parseMutationAck(rawPayload)
        if (parsed !is WatchSyncParseResult.Valid) return
        val acknowledgement = parsed.value
        val binding = WatchSyncBindingStorage.load(applicationContext) ?: return
        if (
            binding.sourceNodeId != sourceNodeId ||
            binding.ownerId != acknowledgement.ownerId ||
            binding.accountGeneration != acknowledgement.accountGeneration
        ) {
            return
        }
        WatchSyncAckRegistry.complete(acknowledgement.operationId, acknowledgement.accepted)
    }

    private fun stageAllows(stage: WatchSyncStage?, envelope: WatchSyncEnvelope): Boolean {
        if (
            stage == null ||
            stage.ownerId != envelope.ownerId ||
            stage.accountGeneration != envelope.accountGeneration
        ) {
            return true
        }
        return envelope.revision > stage.revision ||
            (envelope.revision == stage.revision && envelope.messageId == stage.messageId)
    }

    override fun onDestroy() {
        inboundMessages.close()
        serviceScope.cancel()
        super.onDestroy()
    }

    private companion object {
        const val MAX_PENDING_MESSAGES = 8
        val SUPPORTED_PATHS = setOf(
            SyncPaths.FULL_SYNC_PAYLOAD,
            SyncPaths.PUSH_WORKOUT_PLAN,
            SyncPaths.MUTATION_ACK
        )
    }
}
