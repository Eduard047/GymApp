package com.example.gymapp.ui.viewmodel

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.auth.LiveApplyResult
import com.example.gymapp.auth.LiveCanonicalPlan
import com.example.gymapp.auth.LiveFinishResult
import com.example.gymapp.auth.LiveInboxRoom
import com.example.gymapp.auth.LiveInvitation
import com.example.gymapp.auth.LiveRealtimeEvent
import com.example.gymapp.auth.LiveRespondInviteResult
import com.example.gymapp.auth.LiveStartResult
import com.example.gymapp.auth.LiveWorkoutGatewayException
import com.example.gymapp.auth.LiveWorkoutInbox
import com.example.gymapp.auth.LiveWorkoutRealtimeClient
import com.example.gymapp.auth.LiveWorkoutSnapshot
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.authErrorText
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.ActiveWorkoutSetUpdate
import com.example.gymapp.data.repository.LivePendingOperation
import com.example.gymapp.data.repository.LivePendingOperationKind
import com.example.gymapp.data.repository.LivePreparedMutation
import com.example.gymapp.data.repository.LivePreparedMutationKind
import com.example.gymapp.data.repository.LiveWorkoutBinding
import com.example.gymapp.data.repository.LiveWorkoutSidecarStore
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.StartLiveCanonicalWorkoutResult
import com.example.gymapp.util.LocalizedText
import java.time.OffsetDateTime
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class LiveConnectionMode {
    Realtime,
    Polling,
    Offline
}

internal data class LivePeerProgressUiState(
    val displayName: String,
    val completedSetCount: Int,
    val totalSetCount: Int,
    val isFinished: Boolean
)

internal data class LiveWorkoutUiState(
    val isCloudAccount: Boolean = false,
    val isLoading: Boolean = false,
    val inbox: LiveWorkoutInbox? = null,
    val snapshot: LiveWorkoutSnapshot? = null,
    val connectionMode: LiveConnectionMode = LiveConnectionMode.Offline,
    val actionsInFlight: Set<String> = emptySet(),
    val activeRoomId: String? = null,
    val peerProgress: LivePeerProgressUiState? = null,
    val pendingOperationCount: Int = 0,
    val shouldOpenActiveWorkout: Boolean = false,
    val error: LocalizedText? = null,
    val notice: LocalizedText? = null
)

data class ActiveLiveWorkoutUiState(
    val activeRoomId: String? = null,
    val peerProgress: LivePeerProgressSummary? = null,
    val exerciseLanes: List<LiveExerciseLaneSummary> = emptyList(),
    val connectionMode: LiveConnectionMode = LiveConnectionMode.Offline,
    val pendingOperationCount: Int = 0
)

data class LivePeerProgressSummary(
    val displayName: String,
    val completedSetCount: Int,
    val totalSetCount: Int,
    val isFinished: Boolean
)

data class LiveExerciseLaneSummary(
    val exerciseName: String,
    val selfCompletedSets: List<Boolean>,
    val peerCompletedSets: List<Boolean>
) {
    val selfCompletedSetCount: Int get() = selfCompletedSets.count { it }
    val peerCompletedSetCount: Int get() = peerCompletedSets.count { it }
    val totalSetCount: Int get() = selfCompletedSets.size
}

internal fun liveExerciseLaneSummaries(
    snapshot: LiveWorkoutSnapshot?
): List<LiveExerciseLaneSummary> {
    if (snapshot == null || snapshot.room.status != "active") return emptyList()
    val selfCompleted = snapshot.self.progress?.completedSets
        .orEmpty()
        .mapTo(hashSetOf()) { it.setId }
    val peerCompleted = snapshot.peer.progress?.completedSets
        .orEmpty()
        .mapTo(hashSetOf()) { it.setId }
    return snapshot.plan.exercises.map { exercise ->
        val setIds = exercise.sets.map { it.setId }
        LiveExerciseLaneSummary(
            exerciseName = exercise.name,
            selfCompletedSets = setIds.map(selfCompleted::contains),
            peerCompletedSets = setIds.map(peerCompleted::contains)
        )
    }
}

sealed interface LiveLocalMutationPreparation {
    data object Standalone : LiveLocalMutationPreparation
    data object Rejected : LiveLocalMutationPreparation
    data class Prepared(val localMutationId: String) : LiveLocalMutationPreparation
}

interface ActiveLiveWorkoutSync {
    val activeLiveUiState: StateFlow<ActiveLiveWorkoutUiState>

    suspend fun prepareLocalSetCompleted(
        localSetId: String,
        expectedLocalRevision: Long,
        weight: Double,
        reps: Int
    ): LiveLocalMutationPreparation

    suspend fun prepareLocalSetsCompleted(
        updates: List<ActiveWorkoutSetUpdate>,
        expectedLocalRevision: Long
    ): LiveLocalMutationPreparation

    suspend fun prepareLocalSetUndone(
        localSetId: String,
        expectedLocalRevision: Long
    ): LiveLocalMutationPreparation

    suspend fun prepareLocalWorkoutFinished(
        expectedLocalRevision: Long
    ): LiveLocalMutationPreparation

    suspend fun commitPreparedLocalMutation(preparation: LiveLocalMutationPreparation.Prepared)
    suspend fun cancelPreparedLocalMutation(preparation: LiveLocalMutationPreparation.Prepared)
    suspend fun afterLocalWorkoutDiscarded(): Boolean
}

internal data class LiveLocalSetState(
    val localSetId: String,
    val weight: Double,
    val reps: Int,
    val isCompleted: Boolean
)

internal data class LiveLocalWorkoutState(
    val startedAt: Long,
    val revision: Long,
    val undoableSetId: String?,
    val sets: Map<String, LiveLocalSetState>
)

internal enum class LivePreparedMutationResolution {
    Cancel,
    Promote,
    Unsafe
}

internal fun resolvePreparedLiveMutation(
    binding: LiveWorkoutBinding,
    local: LiveLocalWorkoutState?
): LivePreparedMutationResolution {
    val prepared = binding.preparedMutation ?: return LivePreparedMutationResolution.Unsafe
    if (prepared.kind == LivePreparedMutationKind.Finish) {
        if (local == null) {
            // Room writes history and deletes the active row in one transaction. Missing means
            // that transaction committed; a rollback leaves the exact pre-finish active row.
            return LivePreparedMutationResolution.Promote
        }
        return if (local.startedAt == binding.workoutStartedAt &&
            local.revision == prepared.expectedLocalRevision
        ) {
            LivePreparedMutationResolution.Cancel
        } else {
            LivePreparedMutationResolution.Unsafe
        }
    }
    if (local == null || local.startedAt != binding.workoutStartedAt ||
        local.sets.keys != binding.serverToLocalSetIds.values.toSet()
    ) {
        return LivePreparedMutationResolution.Unsafe
    }
    val targets = prepared.operations.map { operation ->
        val serverSetId = operation.serverSetId
            ?: return LivePreparedMutationResolution.Unsafe
        val localSetId = binding.serverToLocalSetIds[serverSetId]
            ?: return LivePreparedMutationResolution.Unsafe
        operation to (local.sets[localSetId]
            ?: return LivePreparedMutationResolution.Unsafe)
    }
    if (local.revision == prepared.expectedLocalRevision) {
        val stillBeforeCommit = when (prepared.kind) {
            LivePreparedMutationKind.CompleteSet,
            LivePreparedMutationKind.CompleteBatch -> targets.all { !it.second.isCompleted }
            LivePreparedMutationKind.UndoSet -> {
                val target = targets.singleOrNull()?.second
                target?.isCompleted == true && local.undoableSetId == target.localSetId
            }
            LivePreparedMutationKind.Finish -> false
        }
        return if (stillBeforeCommit) {
            LivePreparedMutationResolution.Cancel
        } else {
            LivePreparedMutationResolution.Unsafe
        }
    }
    if (local.revision != prepared.expectedLocalRevision + 1L) {
        return LivePreparedMutationResolution.Unsafe
    }
    val committed = when (prepared.kind) {
        LivePreparedMutationKind.CompleteSet -> {
            val (operation, target) = targets.singleOrNull()
                ?: return LivePreparedMutationResolution.Unsafe
            target.isCompleted && target.weight == operation.weight && target.reps == operation.reps &&
                local.undoableSetId == target.localSetId
        }
        LivePreparedMutationKind.CompleteBatch -> targets.all { (operation, target) ->
            target.isCompleted && target.weight == operation.weight && target.reps == operation.reps
        } && local.undoableSetId == null
        LivePreparedMutationKind.UndoSet -> {
            val target = targets.singleOrNull()?.second
            target?.isCompleted == false && local.undoableSetId == null
        }
        LivePreparedMutationKind.Finish -> false
    }
    return if (committed) {
        LivePreparedMutationResolution.Promote
    } else {
        LivePreparedMutationResolution.Unsafe
    }
}

internal fun promotePreparedLiveMutation(binding: LiveWorkoutBinding): LiveWorkoutBinding {
    val prepared = checkNotNull(binding.preparedMutation) {
        "Live workout has no prepared local mutation."
    }
    return binding.copy(
        localFinished = binding.localFinished || prepared.kind == LivePreparedMutationKind.Finish,
        pendingOperations = binding.pendingOperations + prepared.operations,
        preparedMutation = null
    )
}

internal sealed interface LiveQueueReconcileResult {
    data class Reconciled(val binding: LiveWorkoutBinding) : LiveQueueReconcileResult
    data object Unsafe : LiveQueueReconcileResult
}

internal suspend fun acceptLiveInvitationAfterPreflight(
    invitation: LiveInvitation,
    ensureCanJoin: suspend () -> Unit,
    loadSnapshot: suspend (roomId: String) -> LiveWorkoutSnapshot,
    validatePlan: suspend (LiveCanonicalPlan) -> Unit,
    respond: suspend (expectedRoomRevision: Int, clientOperationId: String) ->
        LiveRespondInviteResult,
    newOperationId: () -> String = { UUID.randomUUID().toString() }
): LiveRespondInviteResult {
    ensureCanJoin()
    val snapshot = loadSnapshot(invitation.roomId)
    require(snapshot.room.roomId == invitation.roomId &&
        snapshot.room.status == "waiting" &&
        snapshot.room.roomRevision == invitation.roomRevision &&
        snapshot.self.role == "participant" &&
        snapshot.self.state == "invited") {
        "Live workout invitation is no longer available."
    }
    validatePlan(snapshot.plan)
    return respond(invitation.roomRevision, newOperationId())
}

internal fun resolveLiveInboxRoom(
    boundRoomId: String?,
    inbox: LiveWorkoutInbox,
    isSessionGenerationActive: () -> Boolean,
    detachBoundRoom: (String) -> Unit
): LiveInboxRoom? {
    if (boundRoomId == null) {
        return inbox.rooms.firstOrNull { it.status == "active" }
    }
    inbox.rooms.firstOrNull { it.roomId == boundRoomId }?.let { return it }
    if (!isSessionGenerationActive()) return null
    // Only the account-scoped live sidecar/UI is detached. Room keeps the local workout standalone.
    detachBoundRoom(boundRoomId)
    return null
}

/**
 * Resolves an unknown/stale outcome against a trusted snapshot. Any request retained after the
 * rebase receives a fresh operation ID because its expected revision (and therefore body) changed.
 */
internal fun reconcileLiveQueueWithSnapshot(
    binding: LiveWorkoutBinding,
    snapshot: LiveWorkoutSnapshot,
    newOperationId: () -> String = { UUID.randomUUID().toString() }
): LiveQueueReconcileResult {
    if (binding.roomId != snapshot.room.roomId) return LiveQueueReconcileResult.Unsafe
    val self = snapshot.self
    val progress = self.progress ?: return LiveQueueReconcileResult.Unsafe
    val appliedCountLong = progress.revision.toLong() - binding.progressRevision.toLong()
    if (appliedCountLong !in 0L..binding.pendingOperations.size.toLong()) {
        return LiveQueueReconcileResult.Unsafe
    }
    val appliedCount = appliedCountLong.toInt()
    val applied = binding.pendingOperations.take(appliedCount)
    val remoteCompleted = progress.completedSets.associateBy { it.setId }
    val expectedTouchedSets = mutableMapOf<String, Pair<Double, Int>?>()
    var expectedFinished = binding.localFinished &&
        binding.pendingOperations.none { it.kind == LivePendingOperationKind.Finish }
    applied.forEach { operation ->
        when (operation.kind) {
            LivePendingOperationKind.CompleteSet -> {
                expectedTouchedSets[checkNotNull(operation.serverSetId)] =
                    checkNotNull(operation.weight) to checkNotNull(operation.reps)
            }
            LivePendingOperationKind.UndoSet -> {
                expectedTouchedSets[checkNotNull(operation.serverSetId)] = null
            }
            LivePendingOperationKind.Finish -> expectedFinished = true
        }
    }
    expectedTouchedSets.forEach { (setId, expected) ->
        val remote = remoteCompleted[setId]
        if (expected == null) {
            if (remote != null) return LiveQueueReconcileResult.Unsafe
        } else if (remote == null || remote.weight != expected.first ||
            remote.reps != expected.second
        ) {
            return LiveQueueReconcileResult.Unsafe
        }
    }
    val isRemotelyFinished = self.state == "finished" || progress.finishedAt != null
    if (expectedFinished != isRemotelyFinished && (expectedFinished || isRemotelyFinished)) {
        return LiveQueueReconcileResult.Unsafe
    }

    val retained = binding.pendingOperations.drop(appliedCount)
    val simulatedCompleted = progress.completedSets.map { it.setId }.toMutableList()
    var simulatedUndoable = progress.undoableSetId
    retained.forEach { operation ->
        when (operation.kind) {
            LivePendingOperationKind.CompleteSet -> {
                val setId = checkNotNull(operation.serverSetId)
                if (setId in simulatedCompleted || isRemotelyFinished) {
                    return LiveQueueReconcileResult.Unsafe
                }
                simulatedCompleted += setId
                simulatedUndoable = setId
            }
            LivePendingOperationKind.UndoSet -> {
                val setId = checkNotNull(operation.serverSetId)
                if (isRemotelyFinished || simulatedUndoable != setId ||
                    simulatedCompleted.lastOrNull() != setId
                ) {
                    return LiveQueueReconcileResult.Unsafe
                }
                simulatedCompleted.removeAt(simulatedCompleted.lastIndex)
                simulatedUndoable = simulatedCompleted.lastOrNull()
            }
            LivePendingOperationKind.Finish -> {
                if (isRemotelyFinished) return LiveQueueReconcileResult.Unsafe
            }
        }
    }
    if (retained.size.toLong() > Int.MAX_VALUE.toLong() - progress.revision.toLong()) {
        return LiveQueueReconcileResult.Unsafe
    }
    val rebased = retained.mapIndexed { index, operation ->
        val expectedRevision = progress.revision + index
        if (operation.expectedProgressRevision == expectedRevision) {
            operation
        } else {
            operation.copy(
                clientOperationId = newOperationId(),
                expectedProgressRevision = expectedRevision
            )
        }
    }
    return LiveQueueReconcileResult.Reconciled(
        binding.copy(
            roomRevision = snapshot.room.roomRevision,
            membershipRevision = self.membershipRevision,
            progressRevision = progress.revision,
            localFinished = binding.localFinished ||
                self.state == "finished" || progress.finishedAt != null,
            pendingOperations = rebased
        )
    )
}

internal class LiveWorkoutViewModel(
    private val applicationContext: Context,
    private val repository: GymRepository,
    private val authManager: CloudAuthManager,
    private val session: AccountSession.Cloud?
) : ViewModel(), ActiveLiveWorkoutSync {
    private val sidecarStore = LiveWorkoutSidecarStore(applicationContext)
    private val refreshMutex = Mutex()
    private val queueMutex = Mutex()
    private val inProcessPreparedMutationIds = mutableSetOf<String>()
    private var realtimeConnected = false
    private var drainJob: Job? = null

    private val _uiState = MutableStateFlow(
        LiveWorkoutUiState(isCloudAccount = session != null)
    )
    val liveUiState: StateFlow<LiveWorkoutUiState> = _uiState.asStateFlow()
    override val activeLiveUiState: StateFlow<ActiveLiveWorkoutUiState> =
        liveUiState
            .map { state ->
                ActiveLiveWorkoutUiState(
                    activeRoomId = state.activeRoomId,
                    peerProgress = state.peerProgress?.let { peer ->
                        LivePeerProgressSummary(
                            displayName = peer.displayName,
                            completedSetCount = peer.completedSetCount,
                            totalSetCount = peer.totalSetCount,
                            isFinished = peer.isFinished
                        )
                    },
                    exerciseLanes = liveExerciseLaneSummaries(state.snapshot),
                    connectionMode = state.connectionMode,
                    pendingOperationCount = state.pendingOperationCount
                )
            }
            .stateIn(
                scope = viewModelScope,
                started = kotlinx.coroutines.flow.SharingStarted.Eagerly,
                initialValue = ActiveLiveWorkoutUiState()
            )

    init {
        if (session == null) {
            sidecarStore.clearAll()
        } else {
            restoreBinding()
            refresh()
            startPolling()
            startRealtime()
            drainQueue()
        }
    }

    fun refresh() {
        val cloudSession = session ?: return
        viewModelScope.launch {
            refreshMutex.withLock {
                if (!authManager.isLiveSessionActive(cloudSession)) {
                    failClosedForInactiveSession()
                    return@withLock
                }
                _uiState.update { it.copy(isLoading = true, error = null) }
                try {
                    val inbox = authManager.loadLiveWorkoutInbox(cloudSession)
                    check(authManager.isLiveSessionActive(cloudSession)) {
                        "Cloud session is no longer active."
                    }
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            inbox = inbox,
                            connectionMode = if (realtimeConnected) {
                                LiveConnectionMode.Realtime
                            } else {
                                LiveConnectionMode.Polling
                            }
                        )
                    }
                    val boundRoom = sidecarStore.load(cloudSession)?.roomId
                    val activeRoom = resolveLiveInboxRoom(
                        boundRoomId = boundRoom,
                        inbox = inbox,
                        isSessionGenerationActive = {
                            authManager.isLiveSessionActive(cloudSession)
                        },
                        detachBoundRoom = ::detachLiveWorkout
                    )
                    if (activeRoom != null) refreshSnapshotLocked(activeRoom.roomId)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    if (!authManager.isLiveSessionActive(cloudSession)) {
                        failClosedForInactiveSession()
                    } else {
                        _uiState.update {
                            it.copy(
                                isLoading = false,
                                connectionMode = if (realtimeConnected) {
                                    LiveConnectionMode.Realtime
                                } else {
                                    LiveConnectionMode.Offline
                                },
                                error = authErrorText(error, R.string.live_workout_load_failed)
                            )
                        }
                    }
                }
            }
        }
    }

    fun refreshRoom(roomId: String) {
        val cloudSession = session ?: return
        viewModelScope.launch {
            refreshMutex.withLock {
                if (!authManager.isLiveSessionActive(cloudSession)) {
                    failClosedForInactiveSession()
                    return@withLock
                }
                try {
                    refreshSnapshotLocked(roomId)
                    if (!realtimeConnected) {
                        _uiState.update { it.copy(connectionMode = LiveConnectionMode.Polling) }
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Throwable) {
                    handleRefreshError(error)
                }
            }
        }
    }

    fun sendInvite(friend: SocialFriend, workout: SharedWorkoutPlan) {
        launchAction("send-${friend.profileId}", R.string.live_workout_send_failed) { cloudSession ->
            val result = authManager.sendLiveWorkoutInvite(
                session = cloudSession,
                profileId = friend.profileId,
                clientRequestId = UUID.randomUUID().toString(),
                workout = workout
            )
            _uiState.update {
                it.copy(
                    notice = LocalizedText(
                        if (result.roomId == null) {
                            R.string.live_workout_invite_unavailable
                        } else {
                            R.string.live_workout_invite_sent
                        }
                    )
                )
            }
            refresh()
        }
    }

    fun acceptInvitation(invitation: LiveInvitation) = respondInvitation(invitation, "accept")

    fun declineInvitation(invitation: LiveInvitation) = respondInvitation(invitation, "decline")

    private fun respondInvitation(invitation: LiveInvitation, decision: String) {
        launchAction("respond-${invitation.roomId}", R.string.live_workout_action_failed) {
                cloudSession ->
            val result = if (decision == "accept") {
                acceptLiveInvitationAfterPreflight(
                    invitation = invitation,
                    ensureCanJoin = {
                        check(repository.getActiveWorkoutSnapshot() == null) {
                            applicationContext.getString(R.string.live_workout_active_blocked)
                        }
                    },
                    loadSnapshot = { roomId ->
                        authManager.loadLiveWorkoutSnapshot(cloudSession, roomId)
                    },
                    validatePlan = repository::preflightLiveCanonicalWorkout,
                    respond = { expectedRoomRevision, clientOperationId ->
                        authManager.respondLiveWorkoutInvite(
                            session = cloudSession,
                            roomId = invitation.roomId,
                            decision = decision,
                            expectedRoomRevision = expectedRoomRevision,
                            clientOperationId = clientOperationId
                        )
                    }
                )
            } else {
                authManager.respondLiveWorkoutInvite(
                    session = cloudSession,
                    roomId = invitation.roomId,
                    decision = decision,
                    expectedRoomRevision = invitation.roomRevision,
                    clientOperationId = UUID.randomUUID().toString()
                )
            }
            require(
                (decision == "accept" && result.result == "joined") ||
                    (decision == "decline" && result.result == "declined")
            ) { "Live workout response is invalid." }
            _uiState.update {
                it.copy(
                    notice = LocalizedText(
                        if (decision == "accept") {
                            R.string.live_workout_ready_waiting_owner
                        } else {
                            R.string.live_workout_invite_declined
                        }
                    )
                )
            }
            refresh()
        }
    }

    fun startRoom(room: LiveInboxRoom) {
        if (room.role != "owner" || room.status != "ready") return
        launchAction("start-${room.roomId}", R.string.live_workout_start_failed) { cloudSession ->
            check(repository.getActiveWorkoutSnapshot() == null) {
                applicationContext.getString(R.string.live_workout_active_blocked)
            }
            when (
                authManager.startLiveWorkout(
                    session = cloudSession,
                    roomId = room.roomId,
                    expectedRoomRevision = room.roomRevision,
                    clientOperationId = UUID.randomUUID().toString()
                )
            ) {
                is LiveStartResult.Started -> refreshSnapshotNow(room.roomId)
                is LiveStartResult.Closed -> detachLiveWorkout(room.roomId)
            }
        }
    }

    fun cancelOrLeaveRoom(room: LiveInboxRoom) {
        launchAction("close-${room.roomId}", R.string.live_workout_action_failed) { cloudSession ->
            if (room.role == "owner") {
                authManager.cancelLiveWorkout(
                    cloudSession,
                    room.roomId,
                    UUID.randomUUID().toString(),
                    room.roomRevision
                )
            } else {
                authManager.leaveLiveWorkout(
                    cloudSession,
                    room.roomId,
                    UUID.randomUUID().toString(),
                    room.membershipRevision
                )
            }
            detachLiveWorkout(room.roomId)
            refresh()
        }
    }

    fun clearMessages() {
        _uiState.update { it.copy(error = null, notice = null) }
    }

    fun consumeActiveWorkoutNavigation() {
        _uiState.update { it.copy(shouldOpenActiveWorkout = false) }
    }

    override suspend fun prepareLocalSetCompleted(
        localSetId: String,
        expectedLocalRevision: Long,
        weight: Double,
        reps: Int
    ): LiveLocalMutationPreparation = prepareLocalMutation(
        kind = LivePreparedMutationKind.CompleteSet,
        expectedLocalRevision = expectedLocalRevision,
        updates = listOf(ActiveWorkoutSetUpdate(localSetId, weight, reps))
    )

    override suspend fun prepareLocalSetUndone(
        localSetId: String,
        expectedLocalRevision: Long
    ): LiveLocalMutationPreparation = prepareLocalMutation(
        kind = LivePreparedMutationKind.UndoSet,
        expectedLocalRevision = expectedLocalRevision,
        localSetId = localSetId
    )

    override suspend fun prepareLocalSetsCompleted(
        updates: List<ActiveWorkoutSetUpdate>,
        expectedLocalRevision: Long
    ): LiveLocalMutationPreparation = prepareLocalMutation(
        kind = LivePreparedMutationKind.CompleteBatch,
        expectedLocalRevision = expectedLocalRevision,
        updates = updates
    )

    override suspend fun prepareLocalWorkoutFinished(
        expectedLocalRevision: Long
    ): LiveLocalMutationPreparation = prepareLocalMutation(
        kind = LivePreparedMutationKind.Finish,
        expectedLocalRevision = expectedLocalRevision
    )

    override suspend fun commitPreparedLocalMutation(
        preparation: LiveLocalMutationPreparation.Prepared
    ) {
        val shouldDrain = queueMutex.withLock {
            inProcessPreparedMutationIds.remove(preparation.localMutationId)
            val cloudSession = session ?: return@withLock false
            if (!authManager.isLiveSessionActive(cloudSession)) return@withLock false
            val binding = sidecarStore.load(cloudSession) ?: return@withLock false
            if (binding.preparedMutation?.localMutationId != preparation.localMutationId) {
                return@withLock false
            }
            val updated = promotePreparedLiveMutation(binding)
            if (!sidecarStore.save(cloudSession, updated)) {
                _uiState.update {
                    it.copy(error = LocalizedText(R.string.live_workout_queue_save_failed))
                }
                return@withLock false
            }
            updateBindingUi(updated)
            true
        }
        if (shouldDrain) drainQueue()
    }

    override suspend fun cancelPreparedLocalMutation(
        preparation: LiveLocalMutationPreparation.Prepared
    ) {
        val recovery = queueMutex.withLock {
            inProcessPreparedMutationIds.remove(preparation.localMutationId)
            val cloudSession = session ?: return@withLock null
            val binding = sidecarStore.load(cloudSession) ?: return@withLock null
            if (binding.preparedMutation?.localMutationId != preparation.localMutationId) {
                return@withLock null
            }
            cloudSession to binding
        } ?: return
        // A suspend call can commit Room and still resume with CancellationException. Resolve from
        // the atomic local state instead of blindly deleting the prepared operation in that gap.
        recoverPreparedLocalMutation(recovery.first, recovery.second)
    }

    private suspend fun prepareLocalMutation(
        kind: LivePreparedMutationKind,
        expectedLocalRevision: Long,
        updates: List<ActiveWorkoutSetUpdate> = emptyList(),
        localSetId: String? = null
    ): LiveLocalMutationPreparation = queueMutex.withLock {
        require(expectedLocalRevision in 0 until Long.MAX_VALUE) {
            "Local workout revision is invalid."
        }
        when (kind) {
            LivePreparedMutationKind.CompleteSet -> require(
                updates.size == 1 && localSetId == null
            ) { "Local live set mutation is invalid." }
            LivePreparedMutationKind.CompleteBatch -> require(
                updates.isNotEmpty() &&
                    updates.size <= com.example.gymapp.data.repository.SharedWorkoutLink.MAX_TOTAL_SETS &&
                    updates.map { it.setId }.toSet().size == updates.size && localSetId == null
            ) { "Local live set batch is invalid." }
            LivePreparedMutationKind.UndoSet -> require(
                updates.isEmpty() && localSetId != null
            ) { "Local live undo mutation is invalid." }
            LivePreparedMutationKind.Finish -> require(
                updates.isEmpty() && localSetId == null
            ) { "Local live finish mutation is invalid." }
        }
        val cloudSession = session ?: return@withLock LiveLocalMutationPreparation.Standalone
        if (!authManager.isLiveSessionActive(cloudSession)) {
            failClosedForInactiveSession()
            return@withLock LiveLocalMutationPreparation.Rejected
        }
        val binding = sidecarStore.load(cloudSession) ?: return@withLock if (
            _uiState.value.activeRoomId == null
        ) {
            LiveLocalMutationPreparation.Standalone
        } else {
            handleMissingBinding()
            LiveLocalMutationPreparation.Rejected
        }
        val operationCount = when (kind) {
            LivePreparedMutationKind.CompleteSet,
            LivePreparedMutationKind.CompleteBatch -> updates.size
            LivePreparedMutationKind.UndoSet,
            LivePreparedMutationKind.Finish -> 1
        }
        if (binding.preparedMutation != null) {
            _uiState.update {
                it.copy(error = LocalizedText(R.string.live_workout_queue_save_failed))
            }
            return@withLock LiveLocalMutationPreparation.Rejected
        }
        if (!canAppendPendingOperations(binding, operationCount)) {
            detachLiveWorkout(binding.roomId)
            _uiState.update { it.copy(error = LocalizedText(R.string.live_workout_queue_full)) }
            return@withLock LiveLocalMutationPreparation.Rejected
        }
        val firstProgressRevision = binding.progressRevision + binding.pendingOperations.size
        val operations = when (kind) {
            LivePreparedMutationKind.CompleteSet,
            LivePreparedMutationKind.CompleteBatch -> updates.mapIndexed { index, update ->
                val serverSetId = binding.localToServerSetIds[update.setId]
                    ?: return@withLock rejectPreparedMutationMapping(binding.roomId)
                LivePendingOperation(
                    clientOperationId = UUID.randomUUID().toString(),
                    kind = LivePendingOperationKind.CompleteSet,
                    expectedProgressRevision = firstProgressRevision + index,
                    serverSetId = serverSetId,
                    weight = update.weight,
                    reps = update.reps
                )
            }
            LivePreparedMutationKind.UndoSet -> {
                val serverSetId = localSetId?.let(binding.localToServerSetIds::get)
                    ?: return@withLock rejectPreparedMutationMapping(binding.roomId)
                listOf(
                    LivePendingOperation(
                        clientOperationId = UUID.randomUUID().toString(),
                        kind = LivePendingOperationKind.UndoSet,
                        expectedProgressRevision = firstProgressRevision,
                        serverSetId = serverSetId,
                        weight = null,
                        reps = null
                    )
                )
            }
            LivePreparedMutationKind.Finish -> listOf(
                LivePendingOperation(
                    clientOperationId = UUID.randomUUID().toString(),
                    kind = LivePendingOperationKind.Finish,
                    expectedProgressRevision = firstProgressRevision,
                    serverSetId = null,
                    weight = null,
                    reps = null
                )
            )
        }
        val updated = binding.copy(
            preparedMutation = LivePreparedMutation(
                localMutationId = UUID.randomUUID().toString(),
                kind = kind,
                expectedLocalRevision = expectedLocalRevision,
                operations = operations
            )
        )
        if (!sidecarStore.save(cloudSession, updated)) {
            _uiState.update {
                it.copy(error = LocalizedText(R.string.live_workout_queue_save_failed))
            }
            return@withLock LiveLocalMutationPreparation.Rejected
        }
        updateBindingUi(updated)
        val preparedId = checkNotNull(updated.preparedMutation).localMutationId
        inProcessPreparedMutationIds += preparedId
        LiveLocalMutationPreparation.Prepared(preparedId)
    }

    private fun rejectPreparedMutationMapping(roomId: String): LiveLocalMutationPreparation {
        detachLiveWorkout(roomId)
        _uiState.update { it.copy(error = LocalizedText(R.string.live_workout_mapping_failed)) }
        return LiveLocalMutationPreparation.Rejected
    }

    override suspend fun afterLocalWorkoutDiscarded(): Boolean {
        val cloudSession = session ?: return false
        val binding = sidecarStore.load(cloudSession) ?: return true
        // Local discard is already durable. Detach synchronously so navigation never waits for
        // the network and an old session cannot resume this workout; close the room best-effort.
        detachLiveWorkout(binding.roomId)
        viewModelScope.launch {
            runCatching {
                if (binding.role == "owner") {
                    authManager.cancelLiveWorkout(
                        cloudSession,
                        binding.roomId,
                        UUID.randomUUID().toString(),
                        binding.roomRevision
                    )
                } else {
                    authManager.leaveLiveWorkout(
                        cloudSession,
                        binding.roomId,
                        UUID.randomUUID().toString(),
                        binding.membershipRevision
                    )
                }
            }
        }
        return true
    }


    private fun drainQueue() {
        if (drainJob?.isActive == true) return
        drainJob = viewModelScope.launch {
            val cloudSession = session ?: return@launch
            while (authManager.isLiveSessionActive(cloudSession)) {
                val queued = queueMutex.withLock {
                    val binding = sidecarStore.load(cloudSession) ?: return@withLock null
                    val operation = binding.pendingOperations.firstOrNull()
                        ?: return@withLock null
                    binding to operation
                } ?: break
                val binding = queued.first
                val operation = queued.second
                try {
                    when (operation.kind) {
                        LivePendingOperationKind.CompleteSet,
                        LivePendingOperationKind.UndoSet -> {
                            when (
                                val result = authManager.applyLiveWorkoutSet(
                                    session = cloudSession,
                                    roomId = binding.roomId,
                                    clientOperationId = operation.clientOperationId,
                                    expectedProgressRevision = operation.expectedProgressRevision,
                                    kind = operation.kind.wireValue,
                                    setId = checkNotNull(operation.serverSetId),
                                    weight = operation.weight,
                                    reps = operation.reps
                                )
                            ) {
                                is LiveApplyResult.Applied -> {
                                    val applied = result.value
                                    queueMutex.withLock {
                                        saveQueueSuccess(
                                            cloudSession,
                                            binding,
                                            operation,
                                            applied.progressRevision,
                                            applied.roomRevision
                                        )
                                    }
                                }
                                is LiveApplyResult.Closed -> {
                                    queueMutex.withLock { detachLiveWorkout(binding.roomId) }
                                    break
                                }
                            }
                        }
                        LivePendingOperationKind.Finish -> {
                            when (
                                val result = authManager.finishLiveWorkout(
                                    cloudSession,
                                    binding.roomId,
                                    operation.clientOperationId,
                                    operation.expectedProgressRevision
                                )
                            ) {
                                is LiveFinishResult.Finished -> {
                                    val finished = result.value
                                    queueMutex.withLock {
                                        saveQueueSuccess(
                                            cloudSession,
                                            binding,
                                            operation,
                                            finished.progressRevision,
                                            finished.roomRevision,
                                            finished.membershipRevision
                                        )
                                        if (finished.status == "completed") {
                                            detachLiveWorkout(binding.roomId)
                                        }
                                    }
                                    if (finished.status == "completed") break
                                }
                                is LiveFinishResult.Closed -> {
                                    queueMutex.withLock { detachLiveWorkout(binding.roomId) }
                                    break
                                }
                            }
                        }
                    }
                } catch (error: LiveWorkoutGatewayException) {
                    when {
                        error.isConflict -> {
                            if (!recoverQueueFromSnapshot(cloudSession, binding.roomId)) break
                        }
                        error.isResourceUnavailable -> {
                            queueMutex.withLock { detachLiveWorkout(binding.roomId) }
                            break
                        }
                        else -> break // Unknown outcome: retry the exact stored request later.
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    break // Unknown outcome: retry the exact stored request later.
                }
            }
        }
    }

    private fun saveQueueSuccess(
        cloudSession: AccountSession.Cloud,
        binding: LiveWorkoutBinding,
        operation: LivePendingOperation,
        progressRevision: Int,
        roomRevision: Int,
        membershipRevision: Int = binding.membershipRevision
    ) {
        val current = sidecarStore.load(cloudSession) ?: return
        if (current.pendingOperations.firstOrNull()?.clientOperationId != operation.clientOperationId) {
            return
        }
        val updated = current.copy(
            roomRevision = roomRevision,
            membershipRevision = membershipRevision,
            progressRevision = progressRevision,
            pendingOperations = current.pendingOperations.drop(1)
        )
        check(sidecarStore.save(cloudSession, updated)) {
            "Live workout receipt could not be persisted."
        }
        updateBindingUi(updated)
    }

    private suspend fun recoverQueueFromSnapshot(
        cloudSession: AccountSession.Cloud,
        roomId: String
    ): Boolean {
        val snapshot = authManager.loadLiveWorkoutSnapshot(cloudSession, roomId)
        _uiState.update { it.copy(snapshot = snapshot, peerProgress = peerProgress(snapshot)) }
        return queueMutex.withLock {
            val current = sidecarStore.load(cloudSession)
                ?.takeIf { it.roomId == roomId }
                ?: return@withLock false
            when (val result = reconcileLiveQueueWithSnapshot(current, snapshot)) {
                is LiveQueueReconcileResult.Reconciled -> {
                    if (!sidecarStore.save(cloudSession, result.binding)) {
                        detachLiveWorkout(roomId)
                        false
                    } else {
                        updateBindingUi(result.binding)
                        true
                    }
                }
                LiveQueueReconcileResult.Unsafe -> {
                    detachLiveWorkout(roomId)
                    _uiState.update {
                        it.copy(error = LocalizedText(R.string.live_workout_conflict_detached))
                    }
                    false
                }
            }
        }
    }

    private suspend fun refreshSnapshotNow(roomId: String) {
        refreshMutex.withLock { refreshSnapshotLocked(roomId) }
    }

    private suspend fun refreshSnapshotLocked(roomId: String) {
        val cloudSession = session ?: return
        val snapshot = authManager.loadLiveWorkoutSnapshot(cloudSession, roomId)
        check(authManager.isLiveSessionActive(cloudSession)) { "Cloud session is no longer active." }
        _uiState.update { it.copy(snapshot = snapshot, peerProgress = peerProgress(snapshot)) }
        if (snapshot.room.status in setOf("completed", "cancelled", "expired")) {
            detachLiveWorkout(roomId)
            return
        }
        if (snapshot.room.status != "active") return

        var existingBinding = sidecarStore.load(cloudSession)
        if (existingBinding?.preparedMutation != null) {
            existingBinding = recoverPreparedLocalMutation(cloudSession, existingBinding)
                ?: return
        }
        if (existingBinding != null && !bindingMatchesLocalWorkout(existingBinding, snapshot)) {
            detachLiveWorkout(existingBinding.roomId)
            existingBinding = null
        }
        if (existingBinding == null) {
            val selfProgress = checkNotNull(snapshot.self.progress)
            if (snapshot.self.state == "finished" || selfProgress.finishedAt != null) {
                return
            }
            if (repository.getActiveWorkoutSnapshot() != null) {
                _uiState.update { it.copy(error = LocalizedText(R.string.live_workout_active_blocked)) }
                return
            }
            val startedAt = checkNotNull(snapshot.room.startedAt)
                .let(OffsetDateTime::parse)
                .toInstant()
                .toEpochMilli()
            var committedBinding: LiveWorkoutBinding? = null
            val imported = try {
                repository.startLiveCanonicalWorkout(
                    plan = snapshot.plan,
                    startedAt = startedAt,
                    initialProgress = selfProgress
                ) { prepared ->
                    val self = snapshot.self
                    val binding = LiveWorkoutBinding(
                        userId = cloudSession.userId,
                        sessionGeneration = cloudSession.sessionGeneration,
                        roomId = roomId,
                        role = self.role,
                        peerProfileId = snapshot.peer.profile.profileId,
                        peerDisplayName = snapshot.peer.profile.displayName,
                        roomRevision = snapshot.room.roomRevision,
                        membershipRevision = self.membershipRevision,
                        progressRevision = selfProgress.revision,
                        workoutStartedAt = prepared.startedAt,
                        serverToLocalSetIds = prepared.serverToLocalSetIds
                    )
                    sidecarStore.save(cloudSession, binding).also { saved ->
                        if (saved) committedBinding = binding
                    }
                }
            } catch (error: Throwable) {
                sidecarStore.load(cloudSession)
                    ?.takeIf { it.roomId == roomId }
                    ?.let { sidecarStore.clear(cloudSession) }
                throw error
            }
            when (imported) {
                is StartLiveCanonicalWorkoutResult.Started -> {
                    val binding = checkNotNull(committedBinding) {
                        "Live workout binding was not committed."
                    }
                    updateBindingUi(binding, shouldNavigate = true)
                }
                StartLiveCanonicalWorkoutResult.AlreadyActive -> {
                    _uiState.update { it.copy(error = LocalizedText(R.string.live_workout_active_blocked)) }
                }
            }
        } else if (existingBinding.roomId == roomId) {
            queueMutex.withLock {
                val latestBinding = sidecarStore.load(cloudSession)
                    ?.takeIf { it.roomId == roomId }
                    ?: return@withLock
                val reconciled = reconcileLiveQueueWithSnapshot(latestBinding, snapshot)
                if (reconciled is LiveQueueReconcileResult.Reconciled &&
                    sidecarStore.save(cloudSession, reconciled.binding)
                ) {
                    updateBindingUi(reconciled.binding)
                    drainQueue()
                } else if (reconciled is LiveQueueReconcileResult.Unsafe) {
                    detachLiveWorkout(roomId)
                    _uiState.update {
                        it.copy(error = LocalizedText(R.string.live_workout_conflict_detached))
                    }
                }
            }
        }
    }

    private suspend fun bindingMatchesLocalWorkout(
        binding: LiveWorkoutBinding,
        snapshot: LiveWorkoutSnapshot
    ): Boolean {
        val active = repository.getActiveWorkoutSnapshot()
            ?: return binding.localFinished || snapshot.self.state == "finished" ||
                snapshot.self.progress?.finishedAt != null
        if (binding.localFinished) return false
        val localSetIds = active.exercises
            .flatMap { exercise -> exercise.sets }
            .map { set -> set.id }
            .toSet()
        return active.activeWorkout.startedAt == binding.workoutStartedAt &&
            localSetIds == binding.serverToLocalSetIds.values.toSet()
    }

    private suspend fun recoverPreparedLocalMutation(
        cloudSession: AccountSession.Cloud,
        observedBinding: LiveWorkoutBinding
    ): LiveWorkoutBinding? {
        val observedPrepared = observedBinding.preparedMutation ?: return observedBinding
        val active = repository.getActiveWorkoutSnapshot()?.let { details ->
            LiveLocalWorkoutState(
                startedAt = details.activeWorkout.startedAt,
                revision = details.activeWorkout.revision,
                undoableSetId = details.activeWorkout.undoableSetId,
                sets = details.exercises
                    .flatMap { exercise -> exercise.sets }
                    .associate { set ->
                        set.id to LiveLocalSetState(
                            localSetId = set.id,
                            weight = set.weight,
                            reps = set.reps,
                            isCompleted = set.completedAt != null
                        )
                    }
            )
        }
        var shouldDrain = false
        val recovered = queueMutex.withLock {
            if (!authManager.isLiveSessionActive(cloudSession)) return@withLock null
            val current = sidecarStore.load(cloudSession) ?: return@withLock null
            if (current.preparedMutation?.localMutationId != observedPrepared.localMutationId) {
                return@withLock current
            }
            if (observedPrepared.localMutationId in inProcessPreparedMutationIds) {
                return@withLock current
            }
            val updated = when (resolvePreparedLiveMutation(current, active)) {
                LivePreparedMutationResolution.Cancel -> current.copy(preparedMutation = null)
                LivePreparedMutationResolution.Promote -> {
                    shouldDrain = true
                    promotePreparedLiveMutation(current)
                }
                LivePreparedMutationResolution.Unsafe -> {
                    detachLiveWorkout(current.roomId)
                    _uiState.update {
                        it.copy(error = LocalizedText(R.string.live_workout_conflict_detached))
                    }
                    return@withLock null
                }
            }
            if (!sidecarStore.save(cloudSession, updated)) {
                _uiState.update {
                    it.copy(error = LocalizedText(R.string.live_workout_queue_save_failed))
                }
                return@withLock null
            }
            updateBindingUi(updated)
            updated
        }
        if (shouldDrain && recovered != null) drainQueue()
        return recovered
    }

    private fun canAppendPendingOperations(binding: LiveWorkoutBinding, count: Int): Boolean {
        if (count < 0 || binding.localFinished || binding.preparedMutation != null ||
            binding.pendingOperations.any { it.kind == LivePendingOperationKind.Finish }
        ) return false
        val resultingSize = binding.pendingOperations.size.toLong() + count.toLong()
        return resultingSize <= com.example.gymapp.data.repository.LIVE_MAX_PENDING_OPERATIONS &&
            resultingSize <= Int.MAX_VALUE.toLong() - binding.progressRevision.toLong()
    }

    private fun handleMissingBinding(): Boolean {
        val roomId = _uiState.value.activeRoomId ?: return true
        detachLiveWorkout(roomId)
        _uiState.update {
            it.copy(error = LocalizedText(R.string.live_workout_queue_save_failed))
        }
        return false
    }

    private fun peerProgress(snapshot: LiveWorkoutSnapshot): LivePeerProgressUiState {
        val peer = snapshot.peer
        return LivePeerProgressUiState(
            displayName = peer.profile.displayName,
            completedSetCount = peer.progress?.completedSets?.size ?: 0,
            totalSetCount = snapshot.plan.setIds.size,
            isFinished = peer.state == "finished" || peer.progress?.finishedAt != null
        )
    }

    private fun restoreBinding() {
        val cloudSession = session ?: return
        val binding = sidecarStore.load(cloudSession) ?: return
        updateBindingUi(binding)
        if (binding.preparedMutation != null) {
            viewModelScope.launch {
                recoverPreparedLocalMutation(cloudSession, binding)
            }
        }
    }

    private fun updateBindingUi(binding: LiveWorkoutBinding, shouldNavigate: Boolean = false) {
        _uiState.update {
            it.copy(
                activeRoomId = binding.roomId,
                peerProgress = it.peerProgress ?: LivePeerProgressUiState(
                    displayName = binding.peerDisplayName,
                    completedSetCount = 0,
                    totalSetCount = binding.serverToLocalSetIds.size,
                    isFinished = false
                ),
                pendingOperationCount = binding.pendingOperations.size +
                    binding.preparedMutation?.operations.orEmpty().size,
                shouldOpenActiveWorkout = it.shouldOpenActiveWorkout || shouldNavigate
            )
        }
    }

    private fun detachLiveWorkout(roomId: String) {
        val cloudSession = session
        if (cloudSession != null) {
            sidecarStore.load(cloudSession)?.takeIf { it.roomId == roomId }?.let {
                sidecarStore.clear(cloudSession)
            }
        }
        _uiState.update {
            it.copy(
                activeRoomId = null,
                snapshot = null,
                peerProgress = null,
                pendingOperationCount = 0,
                shouldOpenActiveWorkout = false
            )
        }
    }

    private fun failClosedForInactiveSession() {
        sidecarStore.clearAll()
        realtimeConnected = false
        _uiState.value = LiveWorkoutUiState(
            isCloudAccount = false,
            connectionMode = LiveConnectionMode.Offline,
            error = LocalizedText(R.string.auth_error_session_inactive)
        )
    }

    private fun handleRefreshError(error: Throwable) {
        val cloudSession = session
        if (cloudSession == null || !authManager.isLiveSessionActive(cloudSession)) {
            failClosedForInactiveSession()
            return
        }
        if (error is LiveWorkoutGatewayException && error.isResourceUnavailable) {
            _uiState.value.activeRoomId?.let(::detachLiveWorkout)
        }
        _uiState.update {
            it.copy(
                connectionMode = if (realtimeConnected) {
                    LiveConnectionMode.Realtime
                } else {
                    LiveConnectionMode.Offline
                },
                error = authErrorText(error, R.string.live_workout_load_failed)
            )
        }
    }

    private fun startPolling() {
        viewModelScope.launch {
            while (isActive) {
                delay(12_000L)
                refresh()
                drainQueue()
            }
        }
    }

    private fun startRealtime() {
        val cloudSession = session ?: return
        viewModelScope.launch {
            while (isActive && authManager.isLiveSessionActive(cloudSession)) {
                try {
                    LiveWorkoutRealtimeClient(authManager, cloudSession).events().collectLatest { event ->
                        when (event) {
                            is LiveRealtimeEvent.Connection -> {
                                realtimeConnected = event.connected
                                _uiState.update {
                                    it.copy(
                                        connectionMode = if (event.connected) {
                                            LiveConnectionMode.Realtime
                                        } else if (it.connectionMode != LiveConnectionMode.Offline) {
                                            LiveConnectionMode.Polling
                                        } else {
                                            LiveConnectionMode.Offline
                                        }
                                    )
                                }
                            }
                            is LiveRealtimeEvent.Signal -> {
                                // A private broadcast never mutates local state. It only causes an
                                // authenticated canonical refetch for this still-active generation.
                                if (event.value.roomId == _uiState.value.activeRoomId) {
                                    refreshRoom(event.value.roomId)
                                } else {
                                    refresh()
                                }
                            }
                        }
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Throwable) {
                    realtimeConnected = false
                    _uiState.update {
                        it.copy(
                            connectionMode = if (it.connectionMode == LiveConnectionMode.Offline) {
                                LiveConnectionMode.Offline
                            } else {
                                LiveConnectionMode.Polling
                            }
                        )
                    }
                    delay(30_000L)
                }
            }
        }
    }

    private fun launchAction(
        key: String,
        fallbackErrorResource: Int,
        block: suspend (AccountSession.Cloud) -> Unit
    ) {
        val cloudSession = session ?: return
        if (key in _uiState.value.actionsInFlight) return
        _uiState.update {
            it.copy(actionsInFlight = it.actionsInFlight + key, error = null, notice = null)
        }
        viewModelScope.launch {
            try {
                check(authManager.isLiveSessionActive(cloudSession)) {
                    "Cloud session is no longer active."
                }
                block(cloudSession)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (!authManager.isLiveSessionActive(cloudSession)) {
                    failClosedForInactiveSession()
                } else {
                    _uiState.update {
                        it.copy(error = authErrorText(error, fallbackErrorResource))
                    }
                }
            } finally {
                _uiState.update { it.copy(actionsInFlight = it.actionsInFlight - key) }
            }
        }
    }

    companion object {
        fun factory(
            context: Context,
            repository: GymRepository,
            authManager: CloudAuthManager,
            session: AccountSession.Cloud?
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                LiveWorkoutViewModel(context.applicationContext, repository, authManager, session)
            }
        }
    }
}
