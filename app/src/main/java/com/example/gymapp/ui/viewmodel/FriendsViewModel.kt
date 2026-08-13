package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.auth.SocialBlockedProfile
import com.example.gymapp.auth.SocialDashboard
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.SocialFriendDetails
import com.example.gymapp.auth.SocialFriendRequest
import com.example.gymapp.auth.SocialFriendWorkout
import com.example.gymapp.auth.SocialIncomingWorkoutInvite
import com.example.gymapp.auth.SocialMyFriendCode
import com.example.gymapp.auth.SocialPrivacy
import com.example.gymapp.auth.SocialWorkoutInbox
import com.example.gymapp.auth.SocialWorkoutDetailPrivacy
import com.example.gymapp.auth.SocialRealtimeClient
import com.example.gymapp.auth.authErrorText
import com.example.gymapp.auth.normalizeSocialFriendCode
import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.util.LocalizedText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

internal data class AcceptedSocialWorkout(
    val inviteId: String,
    val plan: SharedWorkoutPlan
)

internal fun acceptedSocialWorkoutForReuse(
    invite: SocialIncomingWorkoutInvite
): AcceptedSocialWorkout? = invite.takeIf { it.status == "accepted" }?.let {
    AcceptedSocialWorkout(inviteId = it.inviteId, plan = it.workout)
}

internal data class FriendsUiState(
    val isCloudAccount: Boolean = false,
    val dashboard: SocialDashboard? = null,
    val myFriendCode: String? = null,
    val workoutInbox: SocialWorkoutInbox? = null,
    val selectedProfileId: String? = null,
    val selectedFriendDetails: SocialFriendDetails? = null,
    val friendWorkouts: List<SocialFriendWorkout> = emptyList(),
    val friendWorkoutActivityRevision: String? = null,
    val workoutDetailPrivacy: SocialWorkoutDetailPrivacy? = null,
    val friendWorkoutDetailsAvailable: Boolean = false,
    val acceptedWorkout: AcceptedSocialWorkout? = null,
    val isDashboardLoading: Boolean = false,
    val isInboxLoading: Boolean = false,
    val isDetailsLoading: Boolean = false,
    val isFriendWorkoutsLoading: Boolean = false,
    val isWorkoutDetailPrivacyLoading: Boolean = false,
    val actionsInFlight: Set<String> = emptySet(),
    val error: LocalizedText? = null,
    val notice: LocalizedText? = null
)

internal fun invalidateSelectedFriendDetailsForRefresh(state: FriendsUiState): FriendsUiState =
    if (state.selectedProfileId == null) {
        state
    } else {
        state.copy(
            selectedFriendDetails = null,
            friendWorkouts = emptyList(),
            friendWorkoutActivityRevision = null,
            friendWorkoutDetailsAvailable = false,
            isDetailsLoading = true,
            isFriendWorkoutsLoading = false
        )
    }

internal fun friendSummaryFallbackState(
    state: FriendsUiState,
    profileId: String,
    details: SocialFriendDetails,
    isExactDetailLoading: Boolean
): FriendsUiState = state.copy(
    selectedProfileId = profileId,
    selectedFriendDetails = details,
    friendWorkouts = emptyList(),
    friendWorkoutActivityRevision = null,
    friendWorkoutDetailsAvailable = false,
    isDetailsLoading = false,
    isFriendWorkoutsLoading = isExactDetailLoading,
    error = null
)

internal fun resolvedSocialFriendCode(
    dashboard: SocialDashboard,
    discovered: SocialMyFriendCode?
): String = discovered?.friendCode ?: dashboard.self.friendCode

internal fun shouldApplySocialDashboardRefresh(
    expectedSession: AccountSession.Cloud,
    activeSession: AccountSession?,
    requestVersion: Long,
    latestRequestVersion: Long
): Boolean = requestVersion == latestRequestVersion &&
    activeSession is AccountSession.Cloud &&
    activeSession.userId == expectedSession.userId &&
    activeSession.sessionGeneration == expectedSession.sessionGeneration

internal enum class SocialRevocationKind {
    RemoveFriend,
    BlockProfile
}

internal fun invalidateSocialAccessAfterRevocation(
    state: FriendsUiState,
    kind: SocialRevocationKind
): FriendsUiState = when (kind) {
    SocialRevocationKind.RemoveFriend,
    SocialRevocationKind.BlockProfile -> state.copy(
        dashboard = null,
        myFriendCode = null,
        workoutInbox = null,
        selectedProfileId = null,
        selectedFriendDetails = null,
        friendWorkouts = emptyList(),
        friendWorkoutActivityRevision = null,
        friendWorkoutDetailsAvailable = false,
        acceptedWorkout = null,
        isDashboardLoading = false,
        isInboxLoading = false,
        isDetailsLoading = false,
        isFriendWorkoutsLoading = false,
        isWorkoutDetailPrivacyLoading = false
    )
}

internal class FriendsViewModel(
    private val authManager: CloudAuthManager,
    private val session: AccountSession.Cloud?
) : ViewModel() {
    private val mutationMutex = Mutex()
    private var dashboardRequestVersion = 0L
    private var inboxRequestVersion = 0L
    private var detailRequestVersion = 0L
    private var privacyRequestVersion = 0L
    private val retainedWorkoutRequestIds = mutableMapOf<String, String>()
    private val mutationJobsLock = Any()
    private val mutationJobs = mutableSetOf<Job>()

    private val _uiState = MutableStateFlow(
        FriendsUiState(isCloudAccount = session != null)
    )
    val uiState: StateFlow<FriendsUiState> = _uiState.asStateFlow()

    init {
        if (session != null) {
            refreshAll()
            viewModelScope.launch {
                while (true) {
                    try {
                        SocialRealtimeClient(authManager, session).events().collectLatest {
                            detailRequestVersion += 1
                            _uiState.update(::invalidateSelectedFriendDetailsForRefresh)
                            refreshDashboard()
                        }
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        kotlinx.coroutines.delay(8_000L)
                    }
                }
            }
        }
    }

    fun refreshAll() {
        refreshDashboard()
        refreshWorkoutInbox()
        refreshWorkoutDetailPrivacy()
    }

    fun refreshWorkoutDetailPrivacy() {
        val cloudSession = session ?: return
        val requestVersion = ++privacyRequestVersion
        _uiState.update { it.copy(isWorkoutDetailPrivacyLoading = true) }
        viewModelScope.launch {
            try {
                val privacy = authManager.loadSocialWorkoutDetailPrivacy(cloudSession)
                if (requestVersion == privacyRequestVersion) {
                    _uiState.update {
                        it.copy(
                            workoutDetailPrivacy = privacy,
                            isWorkoutDetailPrivacyLoading = false
                        )
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                if (requestVersion == privacyRequestVersion) {
                    _uiState.update {
                        it.copy(workoutDetailPrivacy = null, isWorkoutDetailPrivacyLoading = false)
                    }
                }
            }
        }
    }

    fun refreshDashboard() {
        val cloudSession = session ?: return
        val requestVersion = ++dashboardRequestVersion
        val detailInvalidationVersion = if (_uiState.value.selectedProfileId != null) {
            ++detailRequestVersion
        } else {
            null
        }
        viewModelScope.launch {
            if (!shouldApplySocialDashboardRefresh(
                    expectedSession = cloudSession,
                    activeSession = authManager.authState.value.session,
                    requestVersion = requestVersion,
                    latestRequestVersion = dashboardRequestVersion
                )
            ) {
                return@launch
            }
            _uiState.update {
                invalidateSelectedFriendDetailsForRefresh(it).copy(
                    isDashboardLoading = true,
                    error = null
                )
            }
            try {
                val dashboard = authManager.loadSocialDashboard(cloudSession)
                val discoveredFriendCode = authManager.loadSocialMyFriendCode(cloudSession)
                if (shouldApplySocialDashboardRefresh(
                        expectedSession = cloudSession,
                        activeSession = authManager.authState.value.session,
                        requestVersion = requestVersion,
                        latestRequestVersion = dashboardRequestVersion
                    )
                ) {
                    var selectedProfileToReload: String? = null
                    _uiState.update { state ->
                        selectedProfileToReload = state.selectedProfileId?.takeIf { profileId ->
                            dashboard.friends.any { it.profileId == profileId }
                        }
                        state.copy(
                            dashboard = dashboard,
                            myFriendCode = resolvedSocialFriendCode(
                                dashboard,
                                discoveredFriendCode
                            ),
                            isDashboardLoading = false,
                            selectedProfileId = selectedProfileToReload,
                            selectedFriendDetails = null,
                            friendWorkouts = emptyList(),
                            friendWorkoutActivityRevision = null,
                            friendWorkoutDetailsAvailable = false,
                            isDetailsLoading = selectedProfileToReload != null
                        )
                    }
                    selectedProfileToReload?.let(::openFriend)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (shouldApplySocialDashboardRefresh(
                        expectedSession = cloudSession,
                        activeSession = authManager.authState.value.session,
                        requestVersion = requestVersion,
                        latestRequestVersion = dashboardRequestVersion
                    )
                ) {
                    _uiState.update { state ->
                        state.copy(
                            isDashboardLoading = false,
                            isDetailsLoading = if (
                                detailInvalidationVersion == detailRequestVersion
                            ) {
                                false
                            } else {
                                state.isDetailsLoading
                            },
                            error = authErrorText(error, R.string.friends_load_failed)
                        )
                    }
                }
            }
        }
    }

    fun refreshWorkoutInbox() {
        val cloudSession = session ?: return
        val requestVersion = ++inboxRequestVersion
        viewModelScope.launch {
            _uiState.update { it.copy(isInboxLoading = true, error = null) }
            try {
                val inbox = authManager.loadSocialWorkoutInbox(cloudSession)
                if (requestVersion == inboxRequestVersion) {
                    _uiState.update { state ->
                        state.copy(workoutInbox = inbox, isInboxLoading = false)
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (requestVersion == inboxRequestVersion) {
                    _uiState.update { state ->
                        state.copy(
                            isInboxLoading = false,
                            error = authErrorText(error, R.string.workout_invites_load_failed)
                        )
                    }
                }
            }
        }
    }

    fun openFriend(profileId: String) {
        val cloudSession = session ?: return
        val dashboard = _uiState.value.dashboard ?: return
        if (dashboard.friends.none { it.profileId == profileId }) return
        val requestVersion = ++detailRequestVersion
        _uiState.update {
            it.copy(
                selectedProfileId = profileId,
                selectedFriendDetails = null,
                friendWorkouts = emptyList(),
                friendWorkoutActivityRevision = null,
                friendWorkoutDetailsAvailable = false,
                isDetailsLoading = true,
                isFriendWorkoutsLoading = false,
                error = null
            )
        }
        viewModelScope.launch {
            val details = try {
                authManager.loadSocialFriendDetails(cloudSession, profileId)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                if (requestVersion == detailRequestVersion) {
                    _uiState.update {
                        it.copy(
                            selectedFriendDetails = null,
                            friendWorkouts = emptyList(),
                            friendWorkoutActivityRevision = null,
                            friendWorkoutDetailsAvailable = false,
                            isDetailsLoading = false,
                            isFriendWorkoutsLoading = false,
                            error = authErrorText(error, R.string.friend_details_load_failed)
                        )
                    }
                }
                return@launch
            }
            fun requestIsCurrent(): Boolean = requestVersion == detailRequestVersion &&
                _uiState.value.dashboard?.friends?.any { it.profileId == profileId } == true
            if (!requestIsCurrent()) return@launch

            val canTryExact = details.sharing.recentWorkouts && details.activityUpdatedAt != null
            _uiState.update {
                friendSummaryFallbackState(it, profileId, details, canTryExact)
            }
            if (!canTryExact) return@launch

            val workoutPage = try {
                val capability = authManager.loadSocialFriendWorkoutDetailCapability(
                    cloudSession,
                    profileId
                )
                if (capability.available) {
                    authManager.loadSocialFriendWorkoutPage(
                        cloudSession,
                        profileId,
                        expectedActivityRevision = details.activityUpdatedAt
                    )
                } else {
                    null
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                if (requestIsCurrent()) {
                    _uiState.update {
                        friendSummaryFallbackState(it, profileId, details, false)
                    }
                }
                return@launch
            }
            if (requestIsCurrent()) {
                _uiState.update {
                    if (workoutPage == null) {
                        friendSummaryFallbackState(it, profileId, details, false)
                    } else {
                        it.copy(
                            selectedFriendDetails = details,
                            friendWorkouts = workoutPage.items,
                            friendWorkoutActivityRevision = workoutPage.activityRevision,
                            friendWorkoutDetailsAvailable = true,
                            isDetailsLoading = false,
                            isFriendWorkoutsLoading = false,
                            error = null
                        )
                    }
                }
            }
        }
    }

    fun closeFriend() {
        detailRequestVersion += 1
        _uiState.update {
            it.copy(
                selectedProfileId = null,
                selectedFriendDetails = null,
                friendWorkouts = emptyList(),
                friendWorkoutActivityRevision = null,
                friendWorkoutDetailsAvailable = false,
                isDetailsLoading = false,
                isFriendWorkoutsLoading = false
            )
        }
    }

    fun sendFriendRequest(rawFriendCode: String) {
        val friendCode = normalizeSocialFriendCode(rawFriendCode)
        if (friendCode == null) {
            _uiState.update { it.copy(error = LocalizedText(R.string.friend_code_invalid)) }
            return
        }
        launchMutation("send-friend", R.string.friend_request_failed) { cloudSession ->
            authManager.sendSocialFriendRequest(cloudSession, friendCode)
            _uiState.update {
                it.copy(notice = LocalizedText(R.string.friend_request_submitted))
            }
            refreshDashboard()
        }
    }

    fun acceptFriendRequest(request: SocialFriendRequest) {
        respondFriendRequest(request, "accept")
    }

    fun declineFriendRequest(request: SocialFriendRequest) {
        respondFriendRequest(request, "decline")
    }

    private fun respondFriendRequest(request: SocialFriendRequest, decision: String) {
        launchMutation("friend-${request.friendshipId}", R.string.friend_request_action_failed) {
                cloudSession ->
            authManager.respondSocialFriendRequest(
                session = cloudSession,
                friendshipId = request.friendshipId,
                decision = decision,
                expectedRevision = request.friendshipRevision
            )
            refreshDashboard()
        }
    }

    fun cancelFriendRequest(request: SocialFriendRequest) {
        launchMutation("friend-${request.friendshipId}", R.string.friend_request_action_failed) {
                cloudSession ->
            authManager.cancelSocialFriendRequest(
                cloudSession,
                request.friendshipId,
                request.friendshipRevision
            )
            refreshDashboard()
        }
    }

    fun removeFriend(friend: SocialFriend) {
        launchMutation(
            actionKey = "friend-${friend.friendshipId}",
            fallbackErrorResource = R.string.friend_remove_failed,
            beforeLaunch = {
                invalidateRevokedSocialAccess(SocialRevocationKind.RemoveFriend)
            }
        ) { cloudSession ->
            authManager.removeSocialFriend(
                cloudSession,
                friend.friendshipId,
                friend.friendshipRevision
            )
            refreshDashboard()
            refreshWorkoutInbox()
        }
    }

    fun blockProfile(profileId: String) {
        launchMutation(
            actionKey = "profile-$profileId",
            fallbackErrorResource = R.string.friend_block_failed,
            beforeLaunch = {
                invalidateRevokedSocialAccess(SocialRevocationKind.BlockProfile)
            }
        ) { cloudSession ->
            authManager.blockSocialProfile(cloudSession, profileId)
            refreshDashboard()
            refreshWorkoutInbox()
        }
    }

    fun unblockProfile(profile: SocialBlockedProfile) {
        launchMutation("profile-${profile.profileId}", R.string.friend_unblock_failed) {
                cloudSession ->
            authManager.unblockSocialProfile(cloudSession, profile.profileId)
            refreshDashboard()
        }
    }

    fun updatePrivacy(privacy: SocialPrivacy, shareWorkoutDetails: Boolean?) {
        val current = _uiState.value
        val dashboard = current.dashboard ?: return
        val savedPrivacy = dashboard.self.privacy
        var expectedRevision = dashboard.self.settingsRevision
        val savedDetails = current.workoutDetailPrivacy
        launchMutation("privacy", R.string.friends_privacy_save_failed) { cloudSession ->
            if (privacy != savedPrivacy) {
                expectedRevision = authManager.updateSocialPrivacy(
                    cloudSession,
                    privacy,
                    expectedRevision
                ).settingsRevision
            }
            if (shareWorkoutDetails != null &&
                savedDetails != null &&
                shareWorkoutDetails != savedDetails.shareWorkoutDetails
            ) {
                val detailPrivacy = authManager.updateSocialWorkoutDetailPrivacy(
                    cloudSession,
                    shareWorkoutDetails,
                    expectedRevision
                )
                _uiState.update { it.copy(workoutDetailPrivacy = detailPrivacy) }
            }
            _uiState.update { state ->
                state.copy(notice = LocalizedText(R.string.friends_privacy_saved))
            }
            refreshDashboard()
            refreshWorkoutDetailPrivacy()
        }
    }

    fun sendWorkoutInvite(profileId: String, plan: SharedWorkoutPlan) {
        val canonicalPlan = runCatching { SharedWorkoutLink.normalize(plan.exercises) }
            .getOrElse {
                _uiState.update { state ->
                    state.copy(error = LocalizedText(R.string.message_share_workout_failed))
                }
                return
            }
        val fingerprint = "$profileId:${SharedWorkoutLink.encode(canonicalPlan.exercises)}"
        if (fingerprint !in retainedWorkoutRequestIds &&
            retainedWorkoutRequestIds.size >= MAX_RETAINED_WORKOUT_REQUEST_IDS
        ) {
            _uiState.update {
                it.copy(error = LocalizedText(R.string.workout_invite_send_failed))
            }
            return
        }
        val requestId = retainedWorkoutRequestIds.getOrPut(fingerprint) {
            UUID.randomUUID().toString()
        }
        launchMutation("send-workout-$profileId", R.string.workout_invite_send_failed) {
                cloudSession ->
            authManager.sendSocialWorkoutInvite(
                session = cloudSession,
                profileId = profileId,
                clientRequestId = requestId,
                workout = canonicalPlan
            )
            retainedWorkoutRequestIds.remove(fingerprint)
            _uiState.update { it.copy(notice = LocalizedText(R.string.workout_invite_sent)) }
            refreshDashboard()
            refreshWorkoutInbox()
        }
    }

    fun acceptWorkoutInvite(invite: SocialIncomingWorkoutInvite) {
        launchMutation("invite-${invite.inviteId}", R.string.workout_invite_action_failed) {
                cloudSession ->
            val mutation = authManager.respondSocialWorkoutInvite(
                session = cloudSession,
                inviteId = invite.inviteId,
                decision = "accept",
                expectedRevision = invite.inviteRevision
            )
            val plan = checkNotNull(mutation.workout) { "Accepted workout was unavailable." }
            _uiState.update {
                it.copy(acceptedWorkout = AcceptedSocialWorkout(invite.inviteId, plan))
            }
            refreshDashboard()
            refreshWorkoutInbox()
        }
    }

    fun declineWorkoutInvite(invite: SocialIncomingWorkoutInvite) {
        launchMutation("invite-${invite.inviteId}", R.string.workout_invite_action_failed) {
                cloudSession ->
            authManager.respondSocialWorkoutInvite(
                session = cloudSession,
                inviteId = invite.inviteId,
                decision = "decline",
                expectedRevision = invite.inviteRevision
            )
            refreshDashboard()
            refreshWorkoutInbox()
        }
    }

    fun reuseAcceptedWorkoutInvite(invite: SocialIncomingWorkoutInvite) {
        val recovered = acceptedSocialWorkoutForReuse(invite) ?: return
        _uiState.update { it.copy(acceptedWorkout = recovered) }
    }

    fun cancelWorkoutInvite(inviteId: String, inviteRevision: Int) {
        launchMutation("invite-$inviteId", R.string.workout_invite_action_failed) {
                cloudSession ->
            authManager.cancelSocialWorkoutInvite(cloudSession, inviteId, inviteRevision)
            refreshDashboard()
            refreshWorkoutInbox()
        }
    }

    fun consumeAcceptedWorkout(inviteId: String) {
        _uiState.update { state ->
            if (state.acceptedWorkout?.inviteId == inviteId) {
                state.copy(acceptedWorkout = null)
            } else {
                state
            }
        }
    }

    fun clearMessages() {
        _uiState.update { it.copy(error = null, notice = null) }
    }

    override fun onCleared() {
        retainedWorkoutRequestIds.clear()
        _uiState.value = FriendsUiState()
        super.onCleared()
    }

    private fun clearSelectedDetail(profileId: String) {
        if (_uiState.value.selectedProfileId != profileId) return
        detailRequestVersion += 1
        _uiState.update {
            it.copy(
                selectedProfileId = null,
                selectedFriendDetails = null,
                friendWorkouts = emptyList(),
                friendWorkoutActivityRevision = null,
                friendWorkoutDetailsAvailable = false,
                isDetailsLoading = false,
                isFriendWorkoutsLoading = false
            )
        }
    }

    private fun invalidateRevokedSocialAccess(kind: SocialRevocationKind) {
        val pendingMutations = synchronized(mutationJobsLock) { mutationJobs.toList() }
        pendingMutations.forEach { it.cancel() }
        dashboardRequestVersion += 1
        inboxRequestVersion += 1
        detailRequestVersion += 1
        _uiState.update { invalidateSocialAccessAfterRevocation(it, kind) }
        // Intentionally keep retainedWorkoutRequestIds: an unresolved send retry must reuse its UUID.
    }

    private fun launchMutation(
        actionKey: String,
        fallbackErrorResource: Int,
        beforeLaunch: (() -> Unit)? = null,
        action: suspend (AccountSession.Cloud) -> Unit
    ) {
        val cloudSession = session
        if (cloudSession == null || actionKey in _uiState.value.actionsInFlight) return
        beforeLaunch?.invoke()
        _uiState.update {
            it.copy(
                actionsInFlight = it.actionsInFlight + actionKey,
                error = null,
                notice = null
            )
        }
        val mutationJob = viewModelScope.launch(start = CoroutineStart.LAZY) {
            try {
                mutationMutex.withLock { action(cloudSession) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                _uiState.update {
                    it.copy(error = authErrorText(error, fallbackErrorResource))
                }
            } finally {
                _uiState.update {
                    it.copy(actionsInFlight = it.actionsInFlight - actionKey)
                }
            }
        }
        synchronized(mutationJobsLock) { mutationJobs += mutationJob }
        mutationJob.invokeOnCompletion {
            synchronized(mutationJobsLock) { mutationJobs -= mutationJob }
        }
        mutationJob.start()
    }

    companion object {
        private const val MAX_RETAINED_WORKOUT_REQUEST_IDS = 25

        fun factory(
            authManager: CloudAuthManager,
            session: AccountSession.Cloud?
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                FriendsViewModel(authManager = authManager, session = session)
            }
        }
    }
}
