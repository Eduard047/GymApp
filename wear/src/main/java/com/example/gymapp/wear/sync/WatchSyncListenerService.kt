package com.example.gymapp.wear.sync

import com.example.gymapp.wear.WearGymApplication
import com.example.gymapp.wear.health.RestEndAlarm
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
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
        // every protocol stream is revisioned or explicitly retryable. Besides the pinned phone
        // only a node this watch itself just asked for a sync (relink candidate) is heard.
        val binding = WatchSyncBindingStorage.load(applicationContext) ?: return
        if (
            binding.sourceNodeId != messageEvent.sourceNodeId &&
            WatchRelinkCandidate.current() != messageEvent.sourceNodeId
        ) {
            return
        }
        inboundMessages.trySend(
            QueuedMessage(
                sourceNodeId = messageEvent.sourceNodeId,
                path = messageEvent.path,
                data = messageEvent.data.copyOf()
            )
        )
    }

    /** The phone came back in range: send the queued workout without waiting for the app to open. */
    override fun onPeerConnected(peer: Node) {
        super.onPeerConnected(peer)
        (applicationContext as WearGymApplication).outbox.flushAsync()
    }

    override fun onCapabilityChanged(capabilityInfo: CapabilityInfo) {
        super.onCapabilityChanged(capabilityInfo)
        // Delivered through the CAPABILITY_CHANGED manifest filter when the phone app becomes
        // reachable. Only the pinned phone with a bound owner triggers the send; the outbox runs
        // in the application scope, so it outlives this short-lived service.
        val reachable = capabilityInfo.nodes.mapTo(HashSet()) { it.id }
        if (
            WatchBindingRules.pinnedPhoneReachable(
                binding = WatchSyncBindingStorage.load(applicationContext),
                capabilityName = capabilityInfo.name,
                reachableNodeIds = reachable
            )
        ) {
            (applicationContext as WearGymApplication).outbox.flushAsync()
        }
    }

    private suspend fun processMessage(message: QueuedMessage) {
        val rawPayload = message.data.toString(Charsets.UTF_8)
        when (message.path) {
            SyncPaths.FULL_SYNC_PAYLOAD -> handleFullSync(message.sourceNodeId, rawPayload)
            SyncPaths.PUSH_WORKOUT_PLAN -> handleWorkoutPlan(message.sourceNodeId, rawPayload)
            SyncPaths.MUTATION_ACK -> handleMutationAck(message.sourceNodeId, rawPayload)
            SyncPaths.BINDING_STATE -> handleBindingState(message.sourceNodeId, rawPayload)
        }
    }

    private suspend fun handleFullSync(sourceNodeId: String, rawPayload: String) {
        val parsed = WatchSyncJson.parseFullSyncPayload(rawPayload)
        if (parsed !is WatchSyncParseResult.Valid) return

        val payload = parsed.value
        val envelope = payload.envelope
        val binding = WatchSyncBindingStorage.load(applicationContext) ?: return
        val decision = WatchBindingRules.decideFullSync(
            binding = binding,
            sourceNodeId = sourceNodeId,
            envelope = envelope,
            relinkCandidateNodeId = WatchRelinkCandidate.current(),
            heldOwnerId = heldWorkOwnerId()
        )
        when (decision) {
            FullSyncDecision.Reject -> return
            FullSyncDecision.Duplicate -> {
                WatchSyncStageStorage.clearFullSyncIfMatches(applicationContext, envelope)
                return
            }
            is FullSyncDecision.Accept -> Unit
        }
        if (
            !decision.rebased &&
            !stageAllows(WatchSyncStageStorage.loadFullSync(applicationContext), envelope)
        ) {
            return
        }

        // This durable stage is written before Room/preferences. After any crash, a delayed
        // lower revision is rejected until this exact message (or a newer one) completes.
        WatchSyncStageStorage.stageFullSync(applicationContext, envelope)
        val app = applicationContext as WearGymApplication
        if (decision.resetAccountData) {
            // Clear the previous account before changing the binding. A crash can leave an
            // empty watch, but never expose the previous account's data under the new owner.
            // The draft and the queued workout are not account data of the phone: they stay,
            // stamped with their own owner, and are sent only to that owner.
            clearAccountData(app)
            WatchSyncBindingStorage.acceptFullSync(
                context = applicationContext,
                sourceNodeId = sourceNodeId,
                ownerId = envelope.ownerId,
                accountGeneration = envelope.accountGeneration,
                revision = 0L,
                authorityEpoch = envelope.authorityEpoch,
                sentAt = envelope.sentAt
            )
        }
        app.repository.replaceSessionsFromSync(payload.sessions)
        WatchExerciseCatalogStorage.save(applicationContext, payload.exerciseCatalog)
        WatchSyncBindingStorage.acceptFullSync(
            context = applicationContext,
            sourceNodeId = sourceNodeId,
            ownerId = envelope.ownerId,
            accountGeneration = envelope.accountGeneration,
            revision = envelope.revision,
            authorityEpoch = envelope.authorityEpoch,
            sentAt = envelope.sentAt
        )
        WatchSyncStageStorage.clearFullSyncIfMatches(applicationContext, envelope)
        WatchRelinkCandidate.clear()
        // The bound owner is reachable right now: send what was waiting for exactly this owner.
        app.outbox.flushAsync()
    }

    private fun handleWorkoutPlan(sourceNodeId: String, rawPayload: String) {
        val parsed = WatchSyncJson.parseWorkoutPlanPayload(rawPayload)
        if (parsed !is WatchSyncParseResult.Valid) return

        val payload = parsed.value
        val envelope = payload.envelope
        val binding = WatchSyncBindingStorage.load(applicationContext) ?: return
        if (!WatchBindingRules.planAllowed(binding, sourceNodeId, envelope)) return
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
            binding.authorityEpoch != acknowledgement.authorityEpoch ||
            binding.accountGeneration != acknowledgement.accountGeneration
        ) {
            return
        }
        WatchSyncAckRegistry.complete(acknowledgement.operationId, acknowledgement.accepted)
    }

    /** The phone signed out ("unbound") or the user unlinked this watch on the phone ("unlinked"). */
    private suspend fun handleBindingState(sourceNodeId: String, rawPayload: String) {
        val parsed = WatchSyncJson.parseBindingState(rawPayload)
        if (parsed !is WatchSyncParseResult.Valid) return
        val state = parsed.value
        val binding = WatchSyncBindingStorage.load(applicationContext) ?: return
        val app = applicationContext as WearGymApplication
        when (WatchBindingRules.decideBindingState(binding, sourceNodeId, state)) {
            BindingStateDecision.Reject -> return
            BindingStateDecision.Unbind -> {
                // Account data first, binding last: a crash in between leaves an empty watch that
                // is still bound and gets the same message again, never old data without an owner.
                clearAccountData(app)
                WatchSyncBindingStorage.unbind(
                    context = applicationContext,
                    accountGeneration = state.accountGeneration,
                    authorityEpoch = state.authorityEpoch,
                    sentAt = state.sentAt
                )
            }
            BindingStateDecision.Unlink -> {
                // The owner was deleted on the phone: its held work has nowhere to go. Only this
                // owner's work is dropped; work held for another owner stays.
                if (state.accountDeleted && binding.ownerId != null && heldWorkOwnerId() == binding.ownerId) {
                    RestEndAlarm.cancel(applicationContext)
                    WatchWorkoutDraftStorage.clear(applicationContext)
                    WatchPendingWorkoutStorage.clear(applicationContext)
                }
                clearAccountData(app)
                WatchRelinkCandidate.clear()
                // The phone already knows: do not echo an unlink back to it.
                WatchSyncBindingStorage.clearForUnlink(applicationContext, notifyPhone = false)
            }
        }
    }

    /** Plan, history and catalog belong to the phone account. Held work is deliberately kept. */
    private suspend fun clearAccountData(app: WearGymApplication) {
        app.repository.replaceSessionsFromSync(emptyList())
        WatchPlanStorage.clear(applicationContext)
        WatchExerciseCatalogStorage.save(applicationContext, emptyList())
        WatchSyncStageStorage.clearPlan(applicationContext)
    }

    private fun heldWorkOwnerId(): String? {
        return WatchWorkoutDraftStorage.heldOwnerId(applicationContext)
            ?: WatchPendingWorkoutStorage.heldOwnerId(applicationContext)
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
            SyncPaths.MUTATION_ACK,
            SyncPaths.BINDING_STATE
        )
    }
}
