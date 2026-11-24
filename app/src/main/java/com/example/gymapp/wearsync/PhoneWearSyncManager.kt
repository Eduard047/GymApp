package com.example.gymapp.wearsync

import android.os.SystemClock
import com.example.gymapp.GymApplication
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.entity.WearSyncSetRow
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.util.TrainingProfile
import com.google.android.gms.wearable.Wearable
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal fun mayExposePhoneWearAccountData(
    session: AccountSession?,
    binding: PhoneWearAccountBinding,
    trustedSource: PhoneWearTrustedSource?,
    targetNodeId: String
): Boolean {
    val trusted = trustedSource ?: return false
    return session != null &&
        !binding.signedOut &&
        trusted.nodeId == targetNodeId
}

internal class PhoneWearSyncManager(
    private val application: GymApplication
) {
    private data class ActiveBinding(
        val session: AccountSession?,
        val binding: PhoneWearAccountBinding
    )

    private val bindingManager = PhoneWearBindingManager(application)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val initialized = AtomicBoolean(false)
    private val reconnectPushRunning = AtomicBoolean(false)
    private val fullSyncMutex = Mutex()
    private val lastFullSyncCompletedAt = ConcurrentHashMap<String, Long>()

    fun initialize() {
        if (!initialized.compareAndSet(false, true)) return
        scope.launch {
            application.cloudAuthManager.authState
                .map { state ->
                    ActiveBinding(
                        session = state.session,
                        binding = bindingManager.synchronizeSession(state.session)
                    )
                }
                .distinctUntilChangedBy { it.binding }
                .collectLatest { active ->
                    // Account transitions are pushed immediately. A signed-out transition sends
                    // the owner-less binding state "unbound": the watch clears the previous
                    // account's plan, history and catalog and keeps its own unsent work on hold.
                    runCatching { pushToPinnedSource(active.session, active.binding) }
                        .onFailure { error -> if (error is CancellationException) throw error }
                }
        }
    }

    suspend fun authorizeSource(sourceNodeId: String, linkIntent: Boolean = false): Boolean {
        val connected = try {
            withTimeout(NODE_LOOKUP_TIMEOUT_MS) {
                Wearable.getNodeClient(application).connectedNodes.await()
                    .map { it.id }
                    .toSet()
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            return false
        }
        val (_, binding) = currentSessionAndBinding()
        return bindingManager.authorizeSource(
            sourceNodeId = sourceNodeId,
            connectedNodeIds = connected,
            currentBinding = binding,
            linkIntent = linkIntent
        )
    }

    fun currentSessionAndBinding(): Pair<AccountSession?, PhoneWearAccountBinding> {
        val session = application.cloudAuthManager.authState.value.session
        return session to bindingManager.synchronizeSession(session)
    }

    fun fastSourceMayBeTrusted(sourceNodeId: String): Boolean {
        return bindingManager.fastSourceMayBeTrusted(sourceNodeId)
    }

    fun isCurrent(binding: PhoneWearAccountBinding): Boolean {
        return bindingManager.isCurrent(
            binding = binding,
            session = application.cloudAuthManager.authState.value.session
        )
    }

    fun isPinnedNode(sourceNodeId: String): Boolean = bindingManager.isPinnedNode(sourceNodeId)

    /** True for the watch node the user unlinked here and that has not asked to link again. */
    fun isUnlinkedNode(sourceNodeId: String): Boolean = bindingManager.isUnlinkedNode(sourceNodeId)

    /**
     * The pinned watch became reachable: push the current state and the plan that waits for it.
     * Runs in this manager's application scope (the listener service is short-lived) and never
     * more than once at a time.
     */
    fun pushReconnectedAsync(sourceNodeId: String) {
        if (bindingManager.pinnedSourceNodeId() != sourceNodeId) return
        if (!reconnectPushRunning.compareAndSet(false, true)) return
        scope.launch {
            try {
                pushCurrentStateToReconnectedPinnedSource(sourceNodeId)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // Out of range again: the next capability event or sync request retries.
            } finally {
                reconnectPushRunning.set(false)
            }
        }
    }

    /** The linked (pinned) watch node, or null when no watch is linked. Reads local prefs only. */
    fun pinnedWatchNodeId(): String? = bindingManager.pinnedSourceNodeId()

    /** Last seen Data Layer name of the linked watch (shown while it is offline). */
    fun pinnedWatchName(): String? = bindingManager.pinnedWatchName()

    fun rememberWatchName(sourceNodeId: String, displayName: String?): Boolean =
        bindingManager.rememberWatchName(sourceNodeId, displayName)

    /** When the linked watch last proved it follows this phone's current account; null if never. */
    fun linkProofAtMillis(): Long? {
        val (session, binding) = currentSessionAndBinding()
        if (session == null) return null
        return bindingManager.linkProofAt(binding)
    }

    /** A valid command of the pinned watch stamped with the current owner and generation. */
    fun recordLinkProofIfCurrent(sourceNodeId: String, envelope: PhoneWearCommandEnvelope) {
        val (session, binding) = currentSessionAndBinding()
        if (session == null || binding.signedOut) return
        if (
            envelope.ownerId == binding.ownerId &&
            envelope.accountGeneration == binding.accountGeneration
        ) {
            bindingManager.recordLinkProof(sourceNodeId, binding, System.currentTimeMillis())
        }
    }

    private val _pinReleases = MutableStateFlow(0L)

    /**
     * Counts releases of the pinned watch in this process: the phone's "Unlink watch" and the
     * watch's own unlink message. A screen that shows the link can re-read it when this changes.
     */
    val pinReleases: StateFlow<Long> = _pinReleases.asStateFlow()

    /**
     * Unlinks the watch (Watches screen, or the watch's own "Unlink from phone" message). Deletes no workouts. The pin is removed first, so the
     * unlink holds even when the watch is out of range; the watch is told now if it is connected,
     * or the next time it speaks ([replyUnlinkedIfBlocked]). It links again only through its own
     * explicit link request.
     */
    suspend fun unlinkWatch(): Boolean {
        val nodeId = bindingManager.pinnedSourceNodeId()
        val cleared = bindingManager.clearPinnedSource()
        if (cleared) {
            lastFullSyncCompletedAt.clear()
            _pinReleases.update { it + 1 }
            if (nodeId != null) sendUnlinked(nodeId)
        }
        return cleared
    }

    /**
     * A deleted account's Wear residue: its cached plan, link proof and (local profile) per-profile
     * id are removed, and a watch pinned to that owner is unlinked exactly as by "Unlink watch",
     * so a profile re-created under the same name does not inherit the watch. The watch is told
     * in the background; when out of range it learns it the next time it speaks
     * ([replyUnlinkedIfBlocked]). Returns whether the local state was committed.
     */
    fun forgetDeletedOwner(ownerId: String, localDatabaseName: String? = null): Boolean {
        val result = bindingManager.clearOwner(ownerId, localDatabaseName)
        val nodeId = result.releasedNodeId ?: return result.committed
        lastFullSyncCompletedAt.clear()
        _pinReleases.update { it + 1 }
        scope.launch { sendDeletedOwnerUnlink(nodeId, ownerId) }
        return result.committed
    }

    /**
     * With the reason and the owner first, so a current watch drops that owner's held work even
     * when the sign-out before the deletion already unbound it; then a plain unlink for watches
     * that predate the reason (a current one has forgotten the phone by then and ignores it).
     */
    private suspend fun sendDeletedOwnerUnlink(nodeId: String, deletedOwnerId: String) {
        if (sendUnlinked(nodeId, deletedOwnerId = deletedOwnerId)) {
            bindingManager.clearPendingDeletedOwner(deletedOwnerId)
        }
        sendUnlinked(nodeId)
    }

    fun forgetDeletedLocalProfile(databaseName: String): Boolean =
        forgetDeletedOwner(PhoneWearBindingManager.localOwnerId(databaseName), databaseName)

    fun forgetDeletedCloudAccount(userId: String): Boolean =
        forgetDeletedOwner(PhoneWearBindingManager.cloudOwnerId(userId))

    /** True when [sourceNodeId] is the watch the user unlinked; it is told so again. */
    suspend fun replyUnlinkedIfBlocked(sourceNodeId: String): Boolean {
        if (!bindingManager.isUnlinkedNode(sourceNodeId)) return false
        val deletedOwnerId = bindingManager.pendingDeletedOwnerId(sourceNodeId)
        if (deletedOwnerId != null) sendDeletedOwnerUnlink(sourceNodeId, deletedOwnerId)
        else sendUnlinked(sourceNodeId)
        return true
    }

    /** Returns whether the message was handed to the watch. */
    private suspend fun sendUnlinked(nodeId: String, deletedOwnerId: String? = null): Boolean {
        return try {
            val (_, binding) = currentSessionAndBinding()
            sendMessage(
                nodeId,
                PhoneWearPaths.BINDING_STATE,
                PhoneWearProtocol.buildBindingState(binding, unlinked = true, deletedOwnerId = deletedOwnerId,
                    accountDeleted = deletedOwnerId != null)
            )
            true
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // Out of range: the watch learns it the next time it sends anything.
            false
        }
    }

    suspend fun sendCurrentFullSync(sourceNodeId: String, force: Boolean = false) {
        val (session, binding) = currentSessionAndBinding()
        sendFullSync(sourceNodeId, session, binding, force)
    }

    suspend fun pushCurrentStateToReconnectedPinnedSource(sourceNodeId: String) {
        if (bindingManager.pinnedSourceNodeId() != sourceNodeId) return
        sendCurrentFullSync(sourceNodeId, force = true)
        resendPendingPlan(sourceNodeId)
    }

    suspend fun sendMutationAck(
        sourceNodeId: String,
        binding: PhoneWearAccountBinding,
        operationId: String,
        accepted: Boolean
    ) {
        if (!isCurrent(binding)) return
        val payload = PhoneWearProtocol.buildMutationAck(
            binding = binding,
            operationId = operationId,
            accepted = accepted
        )
        sendMessage(sourceNodeId, PhoneWearPaths.MUTATION_ACK, payload)
    }

    /**
     * Sends the user's synced workout plan to the pinned, currently connected watch.
     *
     * Does nothing (returns false) when no watch is pinned or connected, when the account is
     * signed out, or when the plan is not valid for the watch; it never pins a new node, which
     * stays the job of the watch's own full-sync request. The plan shares the account binding and
     * the monotonic revision counter with full syncs, so a stale plan cannot overwrite a newer one.
     */
    suspend fun pushWorkoutPlan(
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>,
        trainingProfile: TrainingProfile,
        planSource: String = PLAN_SOURCE_SMART_COACH
    ): Boolean {
        val (session, binding) = currentSessionAndBinding()
        if (session == null || binding.signedOut) return false
        val nodeId = bindingManager.pinnedSourceNodeId() ?: return false
        val plan = PhoneWearCachedPlan(
            planId = java.util.UUID.randomUUID().toString(),
            createdAt = System.currentTimeMillis(),
            sets = sets,
            exerciseCatalog = exerciseCatalog.take(PhoneWearPaths.MAX_EXERCISE_CATALOG),
            profile = PhoneWearPlanProfile(
                split = trainingProfile.split.name.take(64),
                workoutsPerWeek = trainingProfile.workoutsPerWeek,
                goal = trainingProfile.goal.name.take(64),
                calorieMode = trainingProfile.calorieMode.name.take(64)
            ),
            planSource = planSource
        )
        // Remembered for this account's pinned watch before the send, so a watch that is out of
        // range (or a failed send) gets it on reconnect instead of never.
        bindingManager.cachePlan(binding.ownerId, plan)
        return deliverPlan(nodeId, session, binding, plan)
    }

    /** Sends the plan that is still waiting for the pinned watch of the current account, if any. */
    suspend fun resendPendingPlan(sourceNodeId: String): Boolean {
        val (session, binding) = currentSessionAndBinding()
        if (session == null || binding.signedOut) return false
        if (bindingManager.pinnedSourceNodeId() != sourceNodeId) return false
        val plan = bindingManager.cachedPlan(binding.ownerId, System.currentTimeMillis()) ?: return false
        return deliverPlan(sourceNodeId, session, binding, plan)
    }

    private suspend fun deliverPlan(
        nodeId: String,
        session: AccountSession,
        binding: PhoneWearAccountBinding,
        plan: PhoneWearCachedPlan
    ): Boolean {
        if (!authorizeSource(nodeId)) return false
        if (!mayExposePhoneWearAccountData(session, binding, bindingManager.pinnedSource(), nodeId)) {
            return false
        }
        return fullSyncMutex.withLock {
            if (!isCurrent(binding)) return@withLock false
            val payload = try {
                PhoneWearProtocol.buildWorkoutPlan(
                    binding = binding,
                    revision = bindingManager.nextFullSyncRevision(binding),
                    sets = plan.sets,
                    exerciseCatalog = plan.exerciseCatalog,
                    profile = plan.profile,
                    planSource = plan.planSource
                )
            } catch (_: IllegalArgumentException) {
                // Not valid for the watch: it never will be, so it is not kept for a resend.
                bindingManager.removeCachedPlan(binding.ownerId, plan.planId)
                return@withLock false
            }
            if (!isCurrent(binding)) return@withLock false
            sendMessage(nodeId, PhoneWearPaths.PUSH_WORKOUT_PLAN, payload)
            bindingManager.removeCachedPlan(binding.ownerId, plan.planId)
            true
        }
    }

    private suspend fun pushToPinnedSource(
        session: AccountSession?,
        binding: PhoneWearAccountBinding
    ) {
        val nodeId = bindingManager.pinnedSourceNodeId() ?: return
        if (!authorizeSource(nodeId)) return
        sendFullSync(nodeId, session, binding, force = true)
    }

    private suspend fun sendFullSync(
        sourceNodeId: String,
        session: AccountSession?,
        binding: PhoneWearAccountBinding,
        force: Boolean
    ) = fullSyncMutex.withLock {
        val elapsedNow = SystemClock.elapsedRealtime()
        val lastCompleted = lastFullSyncCompletedAt[sourceNodeId]
        if (!force && lastCompleted != null && elapsedNow - lastCompleted < FULL_SYNC_COOLDOWN_MS) {
            return@withLock
        }
        if (!isCurrent(binding)) return@withLock
        if (session == null || binding.signedOut) {
            // Signed out: there is no owner and no data to send. Only the pinned watch is told;
            // it drops the previous account's plan, history and catalog and keeps the workout it
            // recorded on hold for its owner. Nothing is sent to an unpinned node.
            if (!bindingManager.isPinnedNode(sourceNodeId)) return@withLock
            sendMessage(
                sourceNodeId,
                PhoneWearPaths.BINDING_STATE,
                PhoneWearProtocol.buildBindingState(binding, unlinked = false)
            )
            lastFullSyncCompletedAt[sourceNodeId] = SystemClock.elapsedRealtime()
            return@withLock
        }
        val mayExposeAccountData = mayExposePhoneWearAccountData(
            session = session,
            binding = binding,
            trustedSource = bindingManager.pinnedSource(),
            targetNodeId = sourceNodeId
        )
        val (sessions, catalog) = if (!mayExposeAccountData) {
            emptyList<PhoneWearOutboundSession>() to emptyList()
        } else {
            val snapshot = application.repositoryFor(session).getPhoneWearSyncSnapshot(
                maxSetRows = PhoneWearPaths.MAX_SYNC_TOTAL_SETS,
                maxExerciseNames = PhoneWearPaths.MAX_EXERCISE_CATALOG
            )
            rowsToSessions(snapshot.setRows) to snapshot.exerciseNames
        }
        if (!isCurrent(binding)) return@withLock
        val revision = bindingManager.nextFullSyncRevision(binding)
        val payload = PhoneWearProtocol.buildBoundedFullSync(
            binding = binding,
            revision = revision,
            sessions = sessions,
            exerciseCatalog = catalog
        )
        if (!isCurrent(binding)) return@withLock
        sendMessage(sourceNodeId, PhoneWearPaths.FULL_SYNC_PAYLOAD, payload)
        lastFullSyncCompletedAt[sourceNodeId] = SystemClock.elapsedRealtime()
    }

    private suspend fun sendMessage(sourceNodeId: String, path: String, payload: ByteArray) {
        require(payload.size <= PhoneWearPaths.MAX_MESSAGE_BYTES)
        withTimeout(MESSAGE_SEND_TIMEOUT_MS) {
            Wearable.getMessageClient(application)
                .sendMessage(sourceNodeId, path, payload)
                .await()
        }
    }

    private fun rowsToSessions(rows: List<WearSyncSetRow>): List<PhoneWearOutboundSession> {
        return rows.groupByTo(linkedMapOf(), WearSyncSetRow::sessionId)
            .values
            .map { sessionRows ->
                val first = sessionRows.first()
                PhoneWearOutboundSession(
                    id = first.sessionId,
                    startedAt = first.sessionDate,
                    note = first.sessionNote,
                    sets = sessionRows.mapIndexed { index, row ->
                        PhoneWearOutboundSet(
                            id = row.setId,
                            sessionId = row.sessionId,
                            exerciseName = row.exerciseName,
                            weight = row.weight,
                            reps = row.reps,
                            orderIndex = index
                        )
                    }
                )
            }
    }

    private companion object {
        const val NODE_LOOKUP_TIMEOUT_MS = 5_000L
        const val MESSAGE_SEND_TIMEOUT_MS = 10_000L
        const val FULL_SYNC_COOLDOWN_MS = 5_000L
        const val PLAN_SOURCE_SMART_COACH = "smart_coach"
    }
}
