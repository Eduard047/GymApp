package com.example.gymapp.navigation

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAccountDeletionSessionDisposition
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.auth.PasswordReauthenticationRequiredException
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.activeCloudSessionFor
import com.example.gymapp.auth.authErrorText
import com.example.gymapp.auth.databaseName
import com.example.gymapp.auth.hasAnotherBoundedPage
import com.example.gymapp.auth.requiresEmailConfirmation
import com.example.gymapp.auth.shouldRetireCloudAccountDeletionJournal
import com.example.gymapp.data.repository.BackupOwner
import com.example.gymapp.data.repository.canonicalWorkoutPayloadDigest
import com.example.gymapp.gymApplication
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.LiveWorkoutDraftSendReceipt
import com.example.gymapp.data.repository.LiveWorkoutSidecarStore
import com.example.gymapp.data.repository.SharedWorkoutInbox
import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.handOffFirstWorkoutNavigation
import com.example.gymapp.data.repository.handOffSkippedFirstWorkoutNavigation
import com.example.gymapp.push.AndroidPushManager
import com.example.gymapp.push.PushNavigationInbox
import com.example.gymapp.push.PushNavigationTarget
import com.example.gymapp.push.SocialPushType
import com.example.gymapp.push.matchesSession
import com.example.gymapp.ui.components.FIRST_RUN_TUTORIAL_STEPS
import com.example.gymapp.ui.components.FIRST_RUN_TUTORIAL_VERSION
import com.example.gymapp.ui.components.FirstRunTutorialOverlay
import com.example.gymapp.ui.components.TutorialAnchorRegistry
import com.example.gymapp.ui.components.TutorialTarget
import com.example.gymapp.ui.components.tutorialAnchor
import com.example.gymapp.ui.screens.AddWorkoutScreen
import com.example.gymapp.ui.screens.ActiveWorkoutScreen
import com.example.gymapp.ui.screens.AppIntroSplash
import com.example.gymapp.ui.screens.AuthScreen
import com.example.gymapp.ui.screens.CloudSyncConflictDialog
import com.example.gymapp.ui.screens.clearPrivateBackupShareArtifacts
import com.example.gymapp.ui.screens.ExerciseListScreen
import com.example.gymapp.ui.screens.FriendDetailScreen
import com.example.gymapp.ui.screens.FriendWorkoutPickerSheet
import com.example.gymapp.ui.screens.ExerciseProgressScreen
import com.example.gymapp.ui.screens.GymBackground
import com.example.gymapp.ui.screens.MissionsScreen
import com.example.gymapp.ui.screens.ProfileScreen
import com.example.gymapp.ui.screens.ProgressHubScreen
import com.example.gymapp.ui.screens.RanksScreen
import com.example.gymapp.ui.screens.PostWorkoutSummaryScreen
import com.example.gymapp.ui.screens.PasswordUpdateScreen
import com.example.gymapp.ui.screens.WorkoutDetailScreen
import com.example.gymapp.ui.screens.WorkoutListScreen
import com.example.gymapp.ui.screens.WorkoutShareSheet
import com.example.gymapp.ui.screens.shareWorkoutUrl
import com.example.gymapp.ui.viewmodel.AddWorkoutViewModel
import com.example.gymapp.ui.viewmodel.ActiveWorkoutViewModel
import com.example.gymapp.ui.viewmodel.ExerciseListViewModel
import com.example.gymapp.ui.viewmodel.ExerciseProgressViewModel
import com.example.gymapp.ui.viewmodel.FriendsViewModel
import com.example.gymapp.ui.viewmodel.FriendsUiState
import com.example.gymapp.ui.viewmodel.LiveWorkoutUiState
import com.example.gymapp.ui.viewmodel.LiveWorkoutDraftSendRequest
import com.example.gymapp.ui.viewmodel.LiveWorkoutViewModel
import com.example.gymapp.ui.viewmodel.PostWorkoutSummaryViewModel
import com.example.gymapp.ui.viewmodel.RetainedWorkoutDraftFingerprint
import com.example.gymapp.ui.viewmodel.durableDigest
import com.example.gymapp.ui.viewmodel.WorkoutDetailViewModel
import com.example.gymapp.ui.viewmodel.WorkoutListViewModel
import com.example.gymapp.ui.media.ExerciseMediaStore
import com.example.gymapp.sync.PhoneSyncClient
import com.example.gymapp.sync.CloudSnapshotApplyDecision
import com.example.gymapp.sync.CloudSyncConflictSnapshot
import com.example.gymapp.sync.CloudSyncBaselineStore
import com.example.gymapp.sync.CloudSyncPhase
import com.example.gymapp.sync.CloudSyncStatusStore
import com.example.gymapp.sync.CloudSyncUiStatus
import com.example.gymapp.sync.attachSharedCloudExtensions
import com.example.gymapp.sync.cloudSnapshotApplyDecision
import com.example.gymapp.sync.isCanonicalSharedCloudEnvelope
import com.example.gymapp.sync.isSharedCloudStateCandidate
import com.example.gymapp.sync.prepareSharedCloudState
import com.example.gymapp.sync.workoutDurationSyncItems
import com.example.gymapp.sync.runCurrentCloudSyncConflictAction
import com.example.gymapp.util.AppLanguage
import com.example.gymapp.util.LanguageManager
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.FirstRunTutorialCompletion
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.restTimerAccountKey
import com.example.gymapp.util.asString
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID

internal fun shouldEnableCloudAutosave(
    pullSucceeded: Boolean,
    canonicalRoundTripSafe: Boolean,
    pulledSession: AccountSession.Cloud,
    activeSession: AccountSession?
): Boolean = pullSucceeded &&
    canonicalRoundTripSafe &&
    isSameCloudSessionGeneration(pulledSession, activeSession)

internal fun isSameCloudSessionGeneration(
    expected: AccountSession.Cloud,
    active: AccountSession?
): Boolean = active is AccountSession.Cloud &&
    active.userId == expected.userId &&
    active.sessionGeneration == expected.sessionGeneration

internal suspend fun runConfirmedAccountDeletionLocalCleanup(
    clearRoom: suspend () -> Unit,
    clearBaseline: () -> Boolean,
    clearTrainingProfile: () -> Boolean,
    clearTrainingGuidance: () -> Boolean = { true },
    clearSyncStatus: () -> Boolean = { true },
    clearCustomMedia: () -> Boolean = { true },
    clearBackupShares: () -> Boolean = { true },
    clearRestTimers: () -> Boolean = { true },
    clearLiveState: () -> Boolean = { true },
    clearGarminState: () -> Boolean = { true }
): Int {
    var failures = 0
    if (runCatching { clearRoom() }.isFailure) failures += 1
    if (runCatching { check(clearBaseline()) }.isFailure) failures += 1
    if (runCatching { check(clearTrainingProfile()) }.isFailure) failures += 1
    if (runCatching { check(clearTrainingGuidance()) }.isFailure) failures += 1
    if (runCatching { check(clearSyncStatus()) }.isFailure) failures += 1
    if (runCatching { check(clearCustomMedia()) }.isFailure) failures += 1
    if (runCatching { check(clearBackupShares()) }.isFailure) failures += 1
    if (runCatching { check(clearRestTimers()) }.isFailure) failures += 1
    if (runCatching { check(clearLiveState()) }.isFailure) failures += 1
    if (runCatching { check(clearGarminState()) }.isFailure) failures += 1
    return failures
}

internal fun accountActionsEnabled(
    authLoading: Boolean,
    deletionInProgress: Boolean
): Boolean = !authLoading && !deletionInProgress

internal fun shouldInitializeMissingRemoteState(localProjectionEmpty: Boolean): Boolean =
    localProjectionEmpty

internal fun shouldSeedCatalogAfterCloudPull(canonicalRoundTripSafe: Boolean): Boolean =
    canonicalRoundTripSafe

internal fun canAcceptSocialWorkoutInvite(activeWorkoutExists: Boolean): Boolean =
    !activeWorkoutExists

internal fun shouldConsumeAcceptedSocialWorkout(appliedToDraft: Boolean): Boolean =
    appliedToDraft

internal fun shouldPreserveBottomTabState(destination: AppDestination): Boolean =
    destination != AppDestination.Workouts

internal data class FriendWorkoutPickerBinding(
    val userId: String,
    val sessionGeneration: String,
    val profileId: String,
    val friendshipId: String,
    val friendshipRevision: Int
)

internal data class LiveWorkoutDraftTarget(
    val binding: FriendWorkoutPickerBinding,
    val displayName: String,
    val draftBindingId: String
)

internal data class LiveWorkoutDraftSendSnapshot(
    val target: LiveWorkoutDraftTarget,
    val draftFingerprint: RetainedWorkoutDraftFingerprint
)

internal fun liveWorkoutDraftSendStillMatches(
    snapshot: LiveWorkoutDraftSendSnapshot,
    currentTarget: LiveWorkoutDraftTarget?,
    currentDraftFingerprint: RetainedWorkoutDraftFingerprint
): Boolean = shouldClearSuccessfulLiveWorkoutDraftTarget(snapshot, currentTarget) &&
    snapshot.draftFingerprint == currentDraftFingerprint

internal fun shouldClearSuccessfulLiveWorkoutDraftTarget(
    snapshot: LiveWorkoutDraftSendSnapshot,
    currentTarget: LiveWorkoutDraftTarget?
): Boolean = currentTarget != null &&
    snapshot.target.binding == currentTarget.binding &&
    snapshot.target.draftBindingId == currentTarget.draftBindingId

internal fun isFriendWorkoutPickerBindingCurrent(
    binding: FriendWorkoutPickerBinding,
    activeSession: AccountSession?,
    currentProfileId: String?,
    currentFriendshipId: String?,
    currentFriendshipRevision: Int?
): Boolean = activeSession is AccountSession.Cloud &&
    activeSession.userId == binding.userId &&
    activeSession.sessionGeneration == binding.sessionGeneration &&
    currentProfileId == binding.profileId &&
    currentFriendshipId == binding.friendshipId &&
    currentFriendshipRevision == binding.friendshipRevision

internal fun resolveLiveWorkoutFriendFromFreshDashboard(
    target: LiveWorkoutDraftTarget,
    activeSession: AccountSession?,
    freshFriends: List<SocialFriend>
): SocialFriend? = freshFriends.singleOrNull { friend ->
    isFriendWorkoutPickerBindingCurrent(
        binding = target.binding,
        activeSession = activeSession,
        currentProfileId = friend.profileId,
        currentFriendshipId = friend.friendshipId,
        currentFriendshipRevision = friend.friendshipRevision
    )
}

internal fun shouldResumeRetainedWorkoutDraft(
    hasEditorDraft: Boolean,
    hasLiveTarget: Boolean
): Boolean = hasEditorDraft || hasLiveTarget

internal fun restoreLiveWorkoutDraftTarget(
    hasTarget: Boolean,
    draftBindingId: String?,
    userId: String?,
    sessionGeneration: String?,
    profileId: String?,
    friendshipId: String?,
    friendshipRevision: Int?,
    displayName: String?
): LiveWorkoutDraftTarget? {
    if (!hasTarget) return null
    val restoredDraftBindingId = draftBindingId?.takeIf { candidate ->
        runCatching { UUID.fromString(candidate).toString() == candidate }.getOrDefault(false)
    } ?: return null
    val restoredUserId = userId?.takeIf { it.isNotBlank() } ?: return null
    val restoredSessionGeneration = sessionGeneration?.takeIf { it.isNotBlank() } ?: return null
    val restoredProfileId = profileId?.takeIf { it.isNotBlank() } ?: return null
    val restoredFriendshipId = friendshipId?.takeIf { it.isNotBlank() } ?: return null
    val restoredFriendshipRevision = friendshipRevision?.takeIf { it >= 1 } ?: return null
    val restoredDisplayName = displayName?.takeIf { it.isNotBlank() } ?: return null
    return LiveWorkoutDraftTarget(
        binding = FriendWorkoutPickerBinding(
            userId = restoredUserId,
            sessionGeneration = restoredSessionGeneration,
            profileId = restoredProfileId,
            friendshipId = restoredFriendshipId,
            friendshipRevision = restoredFriendshipRevision
        ),
        displayName = restoredDisplayName,
        draftBindingId = restoredDraftBindingId
    )
}

internal enum class LiveWorkoutDraftReceiptAction {
    AwaitAuthoritativeRoom,
    ConsumeUnchangedDraft,
    UnbindAndPreserveChangedDraft,
    ClearReceiptOnly
}

internal fun confirmedLiveWorkoutDraftReceiptAction(
    receipt: LiveWorkoutDraftSendReceipt,
    inbox: com.example.gymapp.auth.LiveWorkoutInbox,
    hasSavedTarget: Boolean,
    target: LiveWorkoutDraftTarget?,
    currentDraftDigest: String
): LiveWorkoutDraftReceiptAction {
    val roomId = receipt.roomId
        ?: return LiveWorkoutDraftReceiptAction.AwaitAuthoritativeRoom
    val authoritativeRoom = inbox.rooms.singleOrNull { room ->
        room.roomId == roomId &&
            room.role == "owner" &&
            room.status in setOf("waiting", "ready", "active") &&
            room.memberState in setOf("joined", "finished") &&
            room.peer.profileId == receipt.recipientProfileId
    } ?: return LiveWorkoutDraftReceiptAction.AwaitAuthoritativeRoom
    check(authoritativeRoom.roomId == roomId)
    if (hasSavedTarget && target == null) {
        return LiveWorkoutDraftReceiptAction.AwaitAuthoritativeRoom
    }
    if (target == null) return LiveWorkoutDraftReceiptAction.ClearReceiptOnly
    val exactTarget = target.draftBindingId == receipt.draftBindingId &&
        target.binding.userId == receipt.userId &&
        target.binding.sessionGeneration == receipt.sessionGeneration &&
        target.binding.profileId == receipt.recipientProfileId &&
        target.binding.friendshipId == receipt.recipientFriendshipId &&
        target.binding.friendshipRevision == receipt.recipientFriendshipRevision
    if (!exactTarget) return LiveWorkoutDraftReceiptAction.ClearReceiptOnly
    return if (currentDraftDigest == receipt.draftFingerprint) {
        LiveWorkoutDraftReceiptAction.ConsumeUnchangedDraft
    } else {
        LiveWorkoutDraftReceiptAction.UnbindAndPreserveChangedDraft
    }
}

internal fun pushNavigationDestination(target: PushNavigationTarget): AppDestination = when (target) {
    is PushNavigationTarget.Social,
    is PushNavigationTarget.Live -> AppDestination.Profile
}

internal sealed interface SocialPushTargetResolution {
    data object AwaitingAuthoritativeRefresh : SocialPushTargetResolution
    data object GenericSocialFallback : SocialPushTargetResolution
    data class FocusSocialObject(
        val target: PushNavigationTarget.Social
    ) : SocialPushTargetResolution
    data class OpenFriend(val profileId: String) : SocialPushTargetResolution
}

internal data class PendingSocialPushResolution(
    val inboxEntryId: Long,
    val target: PushNavigationTarget.Social,
    val minimumDashboardGeneration: Long,
    val minimumInboxGeneration: Long
)

internal data class PendingLivePushResolution(
    val inboxEntryId: Long,
    val target: PushNavigationTarget.Live,
    val minimumInboxGeneration: Long
)

internal sealed interface LivePushTargetResolution {
    data object AwaitingAuthoritativeRefresh : LivePushTargetResolution
    data object GenericSocialFallback : LivePushTargetResolution
    data class FocusLiveRoom(val roomId: String) : LivePushTargetResolution
}

internal fun resolveLivePushTarget(
    target: PushNavigationTarget.Live,
    state: LiveWorkoutUiState,
    minimumInboxGeneration: Long = 0L
): LivePushTargetResolution {
    if (state.isLoading || (
            state.inboxRefreshGeneration < minimumInboxGeneration && state.error == null
            )
    ) {
        return LivePushTargetResolution.AwaitingAuthoritativeRefresh
    }
    if (state.inboxRefreshGeneration < minimumInboxGeneration) {
        return LivePushTargetResolution.GenericSocialFallback
    }
    val inbox = state.inbox ?: return LivePushTargetResolution.GenericSocialFallback
    val exactInvitation = inbox.invitations.any {
        it.roomId == target.roomId && it.roomRevision >= target.roomRevision
    }
    val exactRoom = inbox.rooms.any {
        it.roomId == target.roomId && it.roomRevision >= target.roomRevision
    }
    return if (exactInvitation || exactRoom) {
        LivePushTargetResolution.FocusLiveRoom(target.roomId)
    } else {
        LivePushTargetResolution.GenericSocialFallback
    }
}

internal fun resolveSocialPushTarget(
    target: PushNavigationTarget.Social,
    state: FriendsUiState,
    minimumDashboardGeneration: Long = 0L,
    minimumInboxGeneration: Long = 0L
): SocialPushTargetResolution = when (target.type) {
    SocialPushType.FriendRequestReceived -> {
        val dashboard = state.dashboard
        if (state.isDashboardLoading || (
                state.dashboardRefreshGeneration < minimumDashboardGeneration &&
                    state.error == null
                )
        ) {
            SocialPushTargetResolution.AwaitingAuthoritativeRefresh
        } else if (state.dashboardRefreshGeneration < minimumDashboardGeneration) {
            SocialPushTargetResolution.GenericSocialFallback
        } else if (dashboard == null) {
            SocialPushTargetResolution.GenericSocialFallback
        } else if (dashboard.incoming.any {
                it.friendshipId == target.objectId &&
                    it.friendshipRevision >= target.objectRevision
            }
        ) {
            SocialPushTargetResolution.FocusSocialObject(target)
        } else {
            SocialPushTargetResolution.GenericSocialFallback
        }
    }

    SocialPushType.FriendRequestAccepted -> {
        val dashboard = state.dashboard
        if (state.isDashboardLoading || (
                state.dashboardRefreshGeneration < minimumDashboardGeneration &&
                    state.error == null
                )
        ) {
            SocialPushTargetResolution.AwaitingAuthoritativeRefresh
        } else if (state.dashboardRefreshGeneration < minimumDashboardGeneration) {
            SocialPushTargetResolution.GenericSocialFallback
        } else if (dashboard == null) {
            SocialPushTargetResolution.GenericSocialFallback
        } else {
            dashboard.friends.firstOrNull {
                it.friendshipId == target.objectId &&
                    it.friendshipRevision >= target.objectRevision
            }
                ?.let { SocialPushTargetResolution.OpenFriend(it.profileId) }
                ?: SocialPushTargetResolution.GenericSocialFallback
        }
    }

    SocialPushType.WorkoutInviteReceived,
    SocialPushType.WorkoutInviteAccepted -> {
        val inbox = state.workoutInbox
        if (state.isInboxLoading || (
                state.inboxRefreshGeneration < minimumInboxGeneration && state.error == null
                )
        ) {
            SocialPushTargetResolution.AwaitingAuthoritativeRefresh
        } else if (state.inboxRefreshGeneration < minimumInboxGeneration) {
            SocialPushTargetResolution.GenericSocialFallback
        } else if (inbox == null) {
            SocialPushTargetResolution.GenericSocialFallback
        } else if (inbox.incoming.any {
                it.inviteId == target.objectId && it.inviteRevision >= target.objectRevision
            } || inbox.outgoing.any {
                it.inviteId == target.objectId && it.inviteRevision >= target.objectRevision
            }
        ) {
            SocialPushTargetResolution.FocusSocialObject(target)
        } else if (inbox.hasAnotherBoundedPage()) {
            SocialPushTargetResolution.AwaitingAuthoritativeRefresh
        } else {
            SocialPushTargetResolution.GenericSocialFallback
        }
    }
}

internal enum class FirstRunTutorialMode {
    Automatic,
    Replay
}

internal fun tutorialDestinationForStep(stepIndex: Int): AppDestination = when (
    FIRST_RUN_TUTORIAL_STEPS.getOrNull(stepIndex)?.target
) {
    TutorialTarget.TodayFocus,
    TutorialTarget.TodayPrimaryAction -> AppDestination.Workouts
    TutorialTarget.NavigationExercises -> AppDestination.Exercises
    TutorialTarget.NavigationProgress -> AppDestination.Progress
    TutorialTarget.NavigationProfile -> AppDestination.Profile
    null -> AppDestination.Workouts
}

internal fun tutorialDestinationAfterDismissal(
    completion: FirstRunTutorialCompletion
): AppDestination? = when (completion) {
    FirstRunTutorialCompletion.Completed,
    FirstRunTutorialCompletion.Skipped -> null
}

internal fun canPresentAutomaticTutorial(
    shouldRunForAccount: Boolean,
    hasSession: Boolean,
    isStableWorkoutsRoot: Boolean,
    authenticationInProgress: Boolean,
    introVisible: Boolean,
    hasPendingExternalTarget: Boolean,
    hasActiveWorkout: Boolean,
    hasLiveReservationOrRoom: Boolean,
    hasBlockingDialog: Boolean,
    accountTransitionInProgress: Boolean
): Boolean = shouldRunForAccount &&
    hasSession &&
    isStableWorkoutsRoot &&
    !authenticationInProgress &&
    !introVisible &&
    !hasPendingExternalTarget &&
    !hasActiveWorkout &&
    !hasLiveReservationOrRoom &&
    !hasBlockingDialog &&
    !accountTransitionInProgress

internal fun canRequestTutorialReplay(
    authenticationInProgress: Boolean,
    hasPendingExternalTarget: Boolean,
    hasActiveWorkout: Boolean,
    hasLiveReservationOrRoom: Boolean,
    hasBlockingDialog: Boolean,
    accountTransitionInProgress: Boolean
): Boolean = !authenticationInProgress &&
    !hasPendingExternalTarget &&
    !hasActiveWorkout &&
    !hasLiveReservationOrRoom &&
    !hasBlockingDialog &&
    !accountTransitionInProgress

internal fun pendingSocialWorkoutInviteBadgeCount(
    inboxCount: Int?,
    dashboardCount: Int?
): Int = inboxCount ?: dashboardCount ?: 0

internal enum class WorkoutInviteSendFeedback {
    Idle,
    Sending,
    Succeeded,
    Failed
}

internal fun workoutInviteSendFeedback(
    trackedProfileId: String?,
    actionsInFlight: Set<String>,
    hasNotice: Boolean,
    hasError: Boolean
): WorkoutInviteSendFeedback {
    val profileId = trackedProfileId ?: return WorkoutInviteSendFeedback.Idle
    if ("send-workout-$profileId" in actionsInFlight) return WorkoutInviteSendFeedback.Sending
    return when {
        hasError -> WorkoutInviteSendFeedback.Failed
        hasNotice -> WorkoutInviteSendFeedback.Succeeded
        else -> WorkoutInviteSendFeedback.Idle
    }
}

internal enum class CloudSyncRetryMode {
    Pull,
    ResumeAutosave
}

internal fun isRetryableCloudSyncMessage(message: LocalizedText?): Boolean =
    message?.resourceId in setOf(
        R.string.auth_error_connection,
        R.string.auth_error_cloud_unavailable,
        R.string.cloud_sync_load_failed,
        R.string.cloud_sync_conflict,
        R.string.cloud_sync_save_failed,
        R.string.cloud_sync_account_changed,
        R.string.cloud_sync_baseline_failed,
        R.string.cloud_sync_round_trip_failed,
        R.string.cloud_sync_resolution_failed
    )

internal fun cloudSyncRetryModeForSaveFailure(message: LocalizedText): CloudSyncRetryMode =
    if (message.resourceId == R.string.cloud_sync_conflict) {
        CloudSyncRetryMode.Pull
    } else {
        CloudSyncRetryMode.ResumeAutosave
    }

internal fun accountUiIsolationKey(
    session: AccountSession?,
    needsPasswordUpdate: Boolean
): String {
    val identity = when (session) {
        null -> "signed-out"
        is AccountSession.Cloud -> "cloud:${session.userId}:${session.sessionGeneration}"
        is AccountSession.Local -> "local:${session.databaseName()}"
    } + ":password-update=$needsPasswordUpdate"
    return MessageDigest.getInstance("SHA-256")
        .digest(identity.toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
}

internal fun isCanonicalAndroidCloudEnvelope(root: JSONObject, activeUserId: String): Boolean =
    isCanonicalSharedCloudEnvelope(root, activeUserId)

@OptIn(ExperimentalMaterial3Api::class, FlowPreview::class)
@Composable
internal fun GymAppRoot(
    repositoryProvider: (AccountSession?) -> GymRepository,
    authManager: CloudAuthManager,
    languageManager: LanguageManager,
    restTimerController: RestTimerController,
    sharedWorkoutInbox: SharedWorkoutInbox,
    pushManager: AndroidPushManager,
    pushNavigationInbox: PushNavigationInbox
) {
    val useCompactBottomNavigationLabels =
        LocalConfiguration.current.screenWidthDp <= 360
    val authState by authManager.authState.collectAsState()
    val uiIsolationKey = accountUiIsolationKey(
        session = authState.session,
        needsPasswordUpdate = authState.needsPasswordUpdate
    )
    val selectedLanguage by languageManager.selectedLanguage.collectAsState()
    // A new account generation gets a new controller and graph identity. Navigation Compose can
    // otherwise retain equal-route back-stack entries and their repository-bound ViewModelStores.
    // Language is part of the identity too: retained ViewModels can contain already-formatted
    // labels, so keeping them across a locale switch produces a mixed-language screen.
    val navController = key(uiIsolationKey, selectedLanguage) { rememberNavController() }
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val repository = remember(uiIsolationKey) { repositoryProvider(authState.session) }
    val activeWorkout by repository.observeActiveWorkout().collectAsState(initial = null)
    val pendingSharedWorkout by sharedWorkoutInbox.pending.collectAsState()
    val pendingPushNavigation by pushNavigationInbox.pending.collectAsState()
    val pushUiState by pushManager.uiState.collectAsState()
    val coroutineScope = key(uiIsolationKey) { rememberCoroutineScope() }
    val accountDeletionScope = rememberCoroutineScope()
    val applicationContext = LocalContext.current.applicationContext
    val gymApplication = remember(applicationContext) { applicationContext.gymApplication }
    val trainingGuidanceManager = gymApplication.trainingGuidanceManager
    val tutorialProgress by trainingGuidanceManager.tutorialProgress.collectAsState()
    val tutorialAnchors = remember(uiIsolationKey) { TutorialAnchorRegistry() }
    var tutorialMode by remember(uiIsolationKey) {
        mutableStateOf<FirstRunTutorialMode?>(null)
    }
    var tutorialStepIndex by remember(uiIsolationKey) { mutableStateOf(0) }
    var pendingTutorialStepIndex by remember(uiIsolationKey) { mutableStateOf<Int?>(null) }
    var tutorialAccountBinding by remember(uiIsolationKey) { mutableStateOf<String?>(null) }
    var tutorialReplayRequested by remember(uiIsolationKey) { mutableStateOf(false) }
    var tutorialCompletionSaveFailed by remember(uiIsolationKey) { mutableStateOf(false) }
    var pendingExactSocialPush by remember(uiIsolationKey) {
        mutableStateOf<PendingSocialPushResolution?>(null)
    }
    var focusedSocialPush by remember(uiIsolationKey) {
        mutableStateOf<PushNavigationTarget.Social?>(null)
    }
    var pendingExactLivePush by remember(uiIsolationKey) {
        mutableStateOf<PendingLivePushResolution?>(null)
    }
    var focusedLivePushRoomId by remember(uiIsolationKey) { mutableStateOf<String?>(null) }
    val cloudSyncBaselineStore = remember(applicationContext) {
        CloudSyncBaselineStore(applicationContext)
    }
    val cloudSyncStatusStore = remember(applicationContext) {
        CloudSyncStatusStore(applicationContext)
    }
    var cloudSyncStatus by key(uiIsolationKey) {
        val userId = (authState.session as? AccountSession.Cloud)?.userId
        remember {
            mutableStateOf(
                userId?.let {
                    CloudSyncUiStatus(
                        phase = CloudSyncPhase.Checking,
                        lastSuccessAt = cloudSyncStatusStore.readLastSuccess(it)
                    )
                }
            )
        }
    }
    var sharedCloudExtensions by key(uiIsolationKey) {
        // Extensions are populated only by a successfully validated pull. Automatic upload is
        // never enabled before that pull, so a process restart cannot drop another client's
        // namespace: the current remote row is fetched and its CAS revision is rebound first.
        remember { mutableStateOf<JSONObject?>(null) }
    }
    var showIntro by rememberSaveable { mutableStateOf(true) }
    var accountDeletionInProgress by remember { mutableStateOf(false) }
    var passwordReauthenticationRequired by key(uiIsolationKey) {
        remember { mutableStateOf(false) }
    }
    var passwordChangeSuccessVersion by key(uiIsolationKey) {
        remember { mutableStateOf(0L) }
    }
    var cloudPullGeneration by key(uiIsolationKey) {
        remember { mutableStateOf<String?>(null) }
    }
    var cloudSyncRetryVersion by key(uiIsolationKey) {
        remember { mutableStateOf(0) }
    }
    var cloudSyncRetryMode by key(uiIsolationKey) {
        remember { mutableStateOf<CloudSyncRetryMode?>(null) }
    }
    var cloudSyncConflict by key(uiIsolationKey) {
        remember { mutableStateOf<CloudSyncConflictSnapshot?>(null) }
    }
    var showCloudSyncConflictDialog by key(uiIsolationKey) {
        remember { mutableStateOf(false) }
    }
    var cloudConflictResolutionInProgress by key(uiIsolationKey) {
        remember { mutableStateOf(false) }
    }
    var cloudSyncConflictNoticeVersion by key(uiIsolationKey) {
        remember { mutableStateOf(0) }
    }
    var approvedSharedWorkoutId by key(uiIsolationKey) {
        // Consent must never survive process death: SharedWorkoutInbox is process-local and its
        // generation counter restarts, so restoring an old numeric id could approve a new link.
        remember { mutableStateOf<Long?>(null) }
    }
    var preferredShareFriendProfileId by key(uiIsolationKey) {
        remember { mutableStateOf<String?>(null) }
    }
    var addWorkoutEditorInteractionLocked by key(uiIsolationKey) {
        remember { mutableStateOf(false) }
    }
    var hasSavedLiveWorkoutDraftTarget by key(uiIsolationKey) {
        rememberSaveable { mutableStateOf(false) }
    }
    var savedLiveWorkoutDraftBindingId by key(uiIsolationKey) {
        rememberSaveable { mutableStateOf<String?>(null) }
    }
    var savedLiveWorkoutDraftUserId by key(uiIsolationKey) {
        rememberSaveable { mutableStateOf<String?>(null) }
    }
    var savedLiveWorkoutDraftSessionGeneration by key(uiIsolationKey) {
        rememberSaveable { mutableStateOf<String?>(null) }
    }
    var savedLiveWorkoutDraftProfileId by key(uiIsolationKey) {
        rememberSaveable { mutableStateOf<String?>(null) }
    }
    var savedLiveWorkoutDraftFriendshipId by key(uiIsolationKey) {
        rememberSaveable { mutableStateOf<String?>(null) }
    }
    var savedLiveWorkoutDraftFriendshipRevision by key(uiIsolationKey) {
        rememberSaveable { mutableStateOf<Int?>(null) }
    }
    var savedLiveWorkoutDraftDisplayName by key(uiIsolationKey) {
        rememberSaveable { mutableStateOf<String?>(null) }
    }
    val liveWorkoutDraftTarget = restoreLiveWorkoutDraftTarget(
        hasTarget = hasSavedLiveWorkoutDraftTarget,
        draftBindingId = savedLiveWorkoutDraftBindingId,
        userId = savedLiveWorkoutDraftUserId,
        sessionGeneration = savedLiveWorkoutDraftSessionGeneration,
        profileId = savedLiveWorkoutDraftProfileId,
        friendshipId = savedLiveWorkoutDraftFriendshipId,
        friendshipRevision = savedLiveWorkoutDraftFriendshipRevision,
        displayName = savedLiveWorkoutDraftDisplayName
    )
    val setLiveWorkoutDraftTarget: (LiveWorkoutDraftTarget?) -> Unit = { target ->
        if (target == null) {
            // Clear the marker first so a partially saved clear can never expose a LIVE draft as
            // an ordinary solo workout after recreation.
            hasSavedLiveWorkoutDraftTarget = false
            savedLiveWorkoutDraftBindingId = null
            savedLiveWorkoutDraftUserId = null
            savedLiveWorkoutDraftSessionGeneration = null
            savedLiveWorkoutDraftProfileId = null
            savedLiveWorkoutDraftFriendshipId = null
            savedLiveWorkoutDraftFriendshipRevision = null
            savedLiveWorkoutDraftDisplayName = null
        } else {
            // Populate every exact account/friendship field before publishing the marker. If a
            // restore is incomplete, the editor remains in disabled LIVE mode and fails closed.
            savedLiveWorkoutDraftBindingId = target.draftBindingId
            savedLiveWorkoutDraftUserId = target.binding.userId
            savedLiveWorkoutDraftSessionGeneration = target.binding.sessionGeneration
            savedLiveWorkoutDraftProfileId = target.binding.profileId
            savedLiveWorkoutDraftFriendshipId = target.binding.friendshipId
            savedLiveWorkoutDraftFriendshipRevision = target.binding.friendshipRevision
            savedLiveWorkoutDraftDisplayName = target.displayName
            hasSavedLiveWorkoutDraftTarget = true
        }
    }
    val snackbarHostState = key(uiIsolationKey) { remember { SnackbarHostState() } }

    LaunchedEffect(Unit) {
        delay(1400)
        showIntro = false
    }

    val activeWorkoutBlocksSharedImport = stringResource(
        R.string.message_shared_workout_active_workout
    )
    val discardSharedLinkLabel = stringResource(R.string.action_discard_shared_link)
    LaunchedEffect(
        uiIsolationKey,
        pendingSharedWorkout?.id,
        activeWorkout != null,
        authState.session != null
    ) {
        val pending = pendingSharedWorkout ?: return@LaunchedEffect
        if (authState.session == null || activeWorkout == null) return@LaunchedEffect
        val result = snackbarHostState.showSnackbar(
            message = activeWorkoutBlocksSharedImport,
            actionLabel = discardSharedLinkLabel,
            duration = SnackbarDuration.Indefinite
        )
        if (result == SnackbarResult.ActionPerformed) {
            sharedWorkoutInbox.consume(pending.id)
        }
    }

    val isBottomTabRoute = AppDestination.bottomTabs.any { it.route == currentRoute }
    val hasInContentRootHeader = currentRoute == AppDestination.Workouts.route ||
        currentRoute == AppDestination.Exercises.route
    val cloudSession = (authState.session as? AccountSession.Cloud)
        ?.takeUnless { authState.needsPasswordUpdate }
    val rootGraphRoute = remember(uiIsolationKey) { "gym-root-$uiIsolationKey" }
    val rootGraphEntry = remember(navBackStackEntry, rootGraphRoute) {
        runCatching { navController.getBackStackEntry(rootGraphRoute) }.getOrNull()
    }
    val friendsViewModel = rootGraphEntry?.let { owner ->
        viewModel<FriendsViewModel>(
            viewModelStoreOwner = owner,
            key = "friends",
            factory = FriendsViewModel.factory(authManager, cloudSession)
        )
    }
    val friendsState = friendsViewModel?.uiState?.collectAsState()?.value
    val liveWorkoutViewModel = rootGraphEntry?.let { owner ->
        viewModel<LiveWorkoutViewModel>(
            viewModelStoreOwner = owner,
            key = "live-workout",
            factory = LiveWorkoutViewModel.factory(
                context = applicationContext,
                repository = repository,
                authManager = authManager,
                session = cloudSession
            )
        )
    }
    val rootDraftSyncClient = remember(applicationContext) {
        PhoneSyncClient(applicationContext)
    }
    val rootAddWorkoutViewModel = rootGraphEntry?.let { owner ->
        viewModel<AddWorkoutViewModel>(
            viewModelStoreOwner = owner,
            key = "add_workout_draft",
            factory = AddWorkoutViewModel.factory(
                repository = repository,
                syncClient = rootDraftSyncClient,
                trainingProfileManager = gymApplication.trainingProfileManager
            )
        )
    }
    val liveWorkoutSidecarStore = remember(applicationContext) {
        LiveWorkoutSidecarStore(applicationContext)
    }
    val liveWorkoutState = liveWorkoutViewModel?.liveUiState?.collectAsState()?.value
        ?: LiveWorkoutUiState(isCloudAccount = cloudSession != null)

    LaunchedEffect(
        uiIsolationKey,
        cloudSession?.sessionGeneration,
        liveWorkoutState.inboxRefreshGeneration,
        hasSavedLiveWorkoutDraftTarget,
        savedLiveWorkoutDraftBindingId,
        savedLiveWorkoutDraftUserId,
        savedLiveWorkoutDraftSessionGeneration,
        savedLiveWorkoutDraftProfileId,
        savedLiveWorkoutDraftFriendshipId,
        savedLiveWorkoutDraftFriendshipRevision,
        rootAddWorkoutViewModel
    ) {
        val session = cloudSession ?: return@LaunchedEffect
        val draftViewModel = rootAddWorkoutViewModel ?: return@LaunchedEffect
        if (liveWorkoutState.inboxRefreshGeneration <= 0L) return@LaunchedEffect
        val inbox = liveWorkoutState.inbox ?: return@LaunchedEffect
        val receipt = runCatching { liveWorkoutSidecarStore.draftSend(session) }
            .getOrNull()
            ?: return@LaunchedEffect
        when (confirmedLiveWorkoutDraftReceiptAction(
            receipt = receipt,
            inbox = inbox,
            hasSavedTarget = hasSavedLiveWorkoutDraftTarget,
            target = liveWorkoutDraftTarget,
            currentDraftDigest = draftViewModel.retainedDraftDurableDigest()
        )) {
            LiveWorkoutDraftReceiptAction.AwaitAuthoritativeRoom -> Unit
            LiveWorkoutDraftReceiptAction.ConsumeUnchangedDraft -> {
                draftViewModel.discardDraftIfDigestMatches(receipt.draftFingerprint)
                setLiveWorkoutDraftTarget(null)
            }
            LiveWorkoutDraftReceiptAction.UnbindAndPreserveChangedDraft -> {
                setLiveWorkoutDraftTarget(null)
            }
            LiveWorkoutDraftReceiptAction.ClearReceiptOnly -> {
                liveWorkoutSidecarStore.clearDraftSend(
                    session = session,
                    expectedDraftBindingId = receipt.draftBindingId,
                    expectedOperationId = receipt.operationId,
                    expectedRoomId = receipt.roomId
                )
            }
        }
    }

    LaunchedEffect(
        uiIsolationKey,
        pendingPushNavigation?.id,
        cloudSession?.sessionGeneration,
        friendsViewModel,
        liveWorkoutViewModel
    ) {
        val pending = pendingPushNavigation ?: return@LaunchedEffect
        val navigation = pending.navigation
        if (cloudSession == null ||
            !navigation.matchesSession(cloudSession) ||
            !pushManager.isNavigationBoundToCurrentSession(navigation)
        ) {
            pushNavigationInbox.consume(pending.id)
            return@LaunchedEffect
        }
        when (val target = navigation.target) {
            is PushNavigationTarget.Social -> {
                val social = friendsViewModel ?: return@LaunchedEffect
                val state = social.uiState.value
                pendingExactSocialPush = PendingSocialPushResolution(
                    inboxEntryId = pending.id,
                    target = target,
                    minimumDashboardGeneration = state.dashboardRefreshGeneration + 1L,
                    minimumInboxGeneration = state.inboxRefreshGeneration + 1L
                )
                pendingExactLivePush = null
                focusedSocialPush = null
                focusedLivePushRoomId = null
                social.refreshAll()
                liveWorkoutViewModel?.refresh()
            }
            is PushNavigationTarget.Live -> {
                val live = liveWorkoutViewModel ?: return@LaunchedEffect
                val state = live.liveUiState.value
                pendingExactLivePush = PendingLivePushResolution(
                    inboxEntryId = pending.id,
                    target = target,
                    minimumInboxGeneration = state.inboxRefreshGeneration + 1L
                )
                pendingExactSocialPush = null
                focusedSocialPush = null
                focusedLivePushRoomId = null
                friendsViewModel?.refreshAll()
                live.refresh()
            }
        }
        navController.navigate(pushNavigationDestination(navigation.target).route) {
            launchSingleTop = true
        }
    }
    LaunchedEffect(pendingExactSocialPush, friendsState) {
        val pending = pendingExactSocialPush ?: return@LaunchedEffect
        val state = friendsState ?: return@LaunchedEffect
        when (
            val resolution = resolveSocialPushTarget(
                target = pending.target,
                state = state,
                minimumDashboardGeneration = pending.minimumDashboardGeneration,
                minimumInboxGeneration = pending.minimumInboxGeneration
            )
        ) {
            SocialPushTargetResolution.AwaitingAuthoritativeRefresh -> {
                if (pending.target.type in setOf(
                        SocialPushType.WorkoutInviteReceived,
                        SocialPushType.WorkoutInviteAccepted
                    ) && state.workoutInbox?.hasAnotherBoundedPage() == true &&
                    !state.isInboxLoading
                ) {
                    friendsViewModel?.loadMoreWorkoutInvites()
                }
            }
            SocialPushTargetResolution.GenericSocialFallback -> {
                focusedSocialPush = null
                navController.navigate(AppDestination.Profile.route) { launchSingleTop = true }
                pushNavigationInbox.consume(pending.inboxEntryId)
                pendingExactSocialPush = null
            }
            is SocialPushTargetResolution.FocusSocialObject -> {
                focusedSocialPush = resolution.target
                navController.navigate(AppDestination.Profile.route) { launchSingleTop = true }
                pushNavigationInbox.consume(pending.inboxEntryId)
                pendingExactSocialPush = null
            }
            is SocialPushTargetResolution.OpenFriend -> {
                focusedSocialPush = null
                navController.navigate(AppDestination.friendDetailRoute(resolution.profileId)) {
                    launchSingleTop = true
                }
                pushNavigationInbox.consume(pending.inboxEntryId)
                pendingExactSocialPush = null
            }
        }
    }
    LaunchedEffect(pendingExactLivePush, liveWorkoutState) {
        val pending = pendingExactLivePush ?: return@LaunchedEffect
        when (
            val resolution = resolveLivePushTarget(
                target = pending.target,
                state = liveWorkoutState,
                minimumInboxGeneration = pending.minimumInboxGeneration
            )
        ) {
            LivePushTargetResolution.AwaitingAuthoritativeRefresh -> Unit
            LivePushTargetResolution.GenericSocialFallback -> {
                focusedLivePushRoomId = null
                navController.navigate(AppDestination.Profile.route) { launchSingleTop = true }
                pushNavigationInbox.consume(pending.inboxEntryId)
                pendingExactLivePush = null
            }
            is LivePushTargetResolution.FocusLiveRoom -> {
                focusedLivePushRoomId = resolution.roomId
                navController.navigate(AppDestination.Profile.route) { launchSingleTop = true }
                pushNavigationInbox.consume(pending.inboxEntryId)
                pendingExactLivePush = null
            }
        }
    }
    val expectedTutorialBinding = authState.session?.let(trainingGuidanceManager::accountBinding)
    val tutorialAccountTransitionInProgress = expectedTutorialBinding == null ||
        trainingGuidanceManager.activeBinding != expectedTutorialBinding
    val tutorialHasLiveReservationOrRoom =
        liveWorkoutState.activeRoomId != null ||
            liveWorkoutState.inbox?.rooms.orEmpty().isNotEmpty() ||
            liveWorkoutState.actionsInFlight.isNotEmpty()
    val tutorialHasPendingExternalTarget = pendingSharedWorkout != null ||
        pendingPushNavigation != null ||
        pendingExactSocialPush != null ||
        pendingExactLivePush != null
    val tutorialHasBlockingDialog = showCloudSyncConflictDialog ||
        cloudConflictResolutionInProgress || accountDeletionInProgress
    val tutorialRootIsSafe = canPresentAutomaticTutorial(
        shouldRunForAccount = true,
        hasSession = authState.session != null,
        isStableWorkoutsRoot = currentRoute == AppDestination.Workouts.route,
        authenticationInProgress = authState.isLoading || authState.needsPasswordUpdate,
        introVisible = showIntro,
        hasPendingExternalTarget = tutorialHasPendingExternalTarget,
        hasActiveWorkout = activeWorkout != null,
        hasLiveReservationOrRoom = tutorialHasLiveReservationOrRoom,
        hasBlockingDialog = tutorialHasBlockingDialog,
        accountTransitionInProgress = tutorialAccountTransitionInProgress
    )
    LaunchedEffect(
        uiIsolationKey,
        tutorialProgress,
        tutorialRootIsSafe,
        tutorialMode,
        expectedTutorialBinding
    ) {
        val binding = expectedTutorialBinding ?: return@LaunchedEffect
        if (tutorialMode != null || tutorialReplayRequested || !tutorialRootIsSafe ||
            !trainingGuidanceManager.shouldRunAutomaticTutorial(
                FIRST_RUN_TUTORIAL_VERSION,
                binding
            )
        ) {
            return@LaunchedEffect
        }
        // Let the first Workouts layout and its anchors settle before moving accessibility focus.
        delay(300)
        if (trainingGuidanceManager.activeBinding == binding &&
            trainingGuidanceManager.shouldRunAutomaticTutorial(
                FIRST_RUN_TUTORIAL_VERSION,
                binding
            )
        ) {
            tutorialAccountBinding = binding
            tutorialStepIndex = 0
            pendingTutorialStepIndex = null
            tutorialCompletionSaveFailed = false
            tutorialMode = FirstRunTutorialMode.Automatic
        }
    }
    LaunchedEffect(
        uiIsolationKey,
        tutorialReplayRequested,
        tutorialRootIsSafe,
        expectedTutorialBinding
    ) {
        if (!tutorialReplayRequested || !tutorialRootIsSafe) return@LaunchedEffect
        val binding = expectedTutorialBinding ?: return@LaunchedEffect
        delay(300)
        if (trainingGuidanceManager.activeBinding == binding) {
            tutorialAccountBinding = binding
            tutorialStepIndex = 0
            pendingTutorialStepIndex = null
            tutorialCompletionSaveFailed = false
            tutorialMode = FirstRunTutorialMode.Replay
            tutorialReplayRequested = false
        }
    }
    LaunchedEffect(
        tutorialMode,
        tutorialHasPendingExternalTarget,
        activeWorkout != null,
        tutorialHasLiveReservationOrRoom,
        tutorialHasBlockingDialog,
        tutorialAccountTransitionInProgress
    ) {
        if (tutorialMode != null && (
                tutorialHasPendingExternalTarget || activeWorkout != null ||
                    tutorialHasLiveReservationOrRoom || tutorialHasBlockingDialog ||
                    tutorialAccountTransitionInProgress
                )
        ) {
            tutorialMode = null
            tutorialAccountBinding = null
            pendingTutorialStepIndex = null
            tutorialCompletionSaveFailed = false
        }
    }
    fun showTutorialStep(stepIndex: Int) {
        tutorialCompletionSaveFailed = false
        val safeIndex = stepIndex.coerceIn(FIRST_RUN_TUTORIAL_STEPS.indices)
        val destination = tutorialDestinationForStep(safeIndex)
        if (currentRoute == destination.route) {
            pendingTutorialStepIndex = null
            tutorialStepIndex = safeIndex
        } else {
            pendingTutorialStepIndex = safeIndex
            val preserveState = shouldPreserveBottomTabState(destination)
            navController.navigate(destination.route) {
                popUpTo(navController.graph.startDestinationId) {
                    saveState = preserveState
                }
                launchSingleTop = true
                restoreState = preserveState
            }
        }
    }
    LaunchedEffect(currentRoute, pendingTutorialStepIndex, tutorialMode) {
        val pendingStep = pendingTutorialStepIndex ?: return@LaunchedEffect
        if (tutorialMode == null ||
            currentRoute != tutorialDestinationForStep(pendingStep).route
        ) {
            return@LaunchedEffect
        }
        // Wait for the destination to place its target before moving the dialog focus/halo.
        delay(32)
        tutorialStepIndex = pendingStep
        pendingTutorialStepIndex = null
    }
    BackHandler(enabled = tutorialMode != null) {
        if (tutorialStepIndex > 0) showTutorialStep(tutorialStepIndex - 1)
    }
    val finishTutorial: (FirstRunTutorialCompletion) -> Unit = { completion ->
        when (tutorialMode) {
            FirstRunTutorialMode.Replay -> {
                tutorialMode = null
                tutorialAccountBinding = null
                pendingTutorialStepIndex = null
                tutorialCompletionSaveFailed = false
            }
            FirstRunTutorialMode.Automatic -> {
                val binding = tutorialAccountBinding
                if (binding != null && trainingGuidanceManager.recordTutorialCompletion(
                        version = FIRST_RUN_TUTORIAL_VERSION,
                        completion = completion,
                        expectedAccountBinding = binding
                    )
                ) {
                    tutorialMode = null
                    tutorialAccountBinding = null
                    pendingTutorialStepIndex = null
                    tutorialCompletionSaveFailed = false
                } else {
                    tutorialCompletionSaveFailed = true
                }
            }
            null -> Unit
        }
    }
    val dismissTutorial: (FirstRunTutorialCompletion) -> Unit = { completion ->
        tutorialDestinationAfterDismissal(completion)?.let { destination ->
            navController.navigate(destination.route) { launchSingleTop = true }
        }
        finishTutorial(completion)
    }
    val workoutInviteBadgeCount = (pendingSocialWorkoutInviteBadgeCount(
        inboxCount = friendsState?.workoutInbox?.pendingIncomingCount,
        dashboardCount = friendsState?.dashboard?.pendingWorkoutInviteCount
    ) + liveWorkoutState.inbox?.invitations.orEmpty().size).coerceAtMost(99)
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, friendsViewModel, liveWorkoutViewModel) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                friendsViewModel?.refreshAll()
                liveWorkoutViewModel?.refresh()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(friendsState?.acceptedWorkout?.inviteId, activeWorkout != null) {
        if (friendsState?.acceptedWorkout != null && activeWorkout == null) {
            setLiveWorkoutDraftTarget(null)
            navController.navigate(AppDestination.AddWorkout.route) {
                launchSingleTop = true
            }
        }
    }
    LaunchedEffect(liveWorkoutState.shouldOpenActiveWorkout, activeWorkout != null) {
        if (liveWorkoutState.shouldOpenActiveWorkout && activeWorkout != null) {
            navController.navigate(AppDestination.ActiveWorkout.route) {
                launchSingleTop = true
            }
            liveWorkoutViewModel?.consumeActiveWorkoutNavigation()
        }
    }

    fun updateCloudSyncPhase(session: AccountSession.Cloud, phase: CloudSyncPhase) {
        if (isSameCloudSessionGeneration(session, authManager.authState.value.session)) {
            cloudSyncStatus = CloudSyncUiStatus(
                phase = phase,
                lastSuccessAt = cloudSyncStatusStore.readLastSuccess(session.userId)
            )
        }
    }

    fun recordCloudSyncSuccess(session: AccountSession.Cloud) {
        check(isSameCloudSessionGeneration(session, authManager.authState.value.session)) {
            "Cloud account changed while recording synchronization status."
        }
        val timestamp = System.currentTimeMillis()
        check(cloudSyncStatusStore.writeLastSuccess(session.userId, timestamp)) {
            "Could not persist the last successful synchronization time."
        }
        cloudSyncStatus = CloudSyncUiStatus(CloudSyncPhase.Synced, timestamp)
    }

    LaunchedEffect(uiIsolationKey) {
        if (authState.session is AccountSession.Local) {
            repository.seedBuiltInExercises()
            repository.seedDefaultExerciseMuscleMappings()
        }
    }

    LaunchedEffect(cloudSession?.sessionGeneration, cloudSyncRetryVersion) {
        val session = cloudSession ?: return@LaunchedEffect
        updateCloudSyncPhase(session, CloudSyncPhase.Checking)
        cloudPullGeneration = null
        cloudSyncRetryMode = null
        val pullResult = runCatching {
            val remoteState = authManager.loadRemoteState(session)
            if (remoteState != null && remoteState.length() > 0) {
                val preparedSharedState = if (isSharedCloudStateCandidate(remoteState)) {
                    withContext(Dispatchers.Default) {
                        prepareSharedCloudState(remoteState, session.userId)
                    }
                } else {
                    null
                }
                if (preparedSharedState == null) {
                    // Legacy cross-client rows remain readable, but they never arm an automatic
                    // write-back. Import them into the reviewed device snapshot, then require an
                    // explicit choice before publishing the canonical replacement.
                    repository.importBackupJsonObject(
                        remoteState,
                        activeUserId = session.userId,
                        activeRemote = true
                    )
                    val importedLocalState = repository.getCloudWorkoutProjectionState()
                    cloudSyncConflict = CloudSyncConflictSnapshot(
                        userId = session.userId,
                        sessionGeneration = session.sessionGeneration,
                        localDigest = importedLocalState.digest,
                        remoteDigest = null,
                        remoteExists = true
                    )
                    updateCloudSyncPhase(session, CloudSyncPhase.Conflict)
                    showCloudSyncConflictDialog = true
                    false
                } else {
                    sharedCloudExtensions = preparedSharedState.extensions
                    val remoteDigest = preparedSharedState.workoutDigest
                    val localState = repository.getCloudWorkoutProjectionState()
                    when (cloudSnapshotApplyDecision(
                        localDigest = localState.digest,
                        remoteDigest = remoteDigest,
                        lastSyncedDigest = cloudSyncBaselineStore.read(session.userId),
                        localProjectionEmpty = localState.isEmpty
                    )) {
                        CloudSnapshotApplyDecision.Conflict -> {
                            cloudSyncConflict = CloudSyncConflictSnapshot(
                                userId = session.userId,
                                sessionGeneration = session.sessionGeneration,
                                localDigest = localState.digest,
                                remoteDigest = remoteDigest,
                                remoteExists = true
                            )
                            updateCloudSyncPhase(session, CloudSyncPhase.Conflict)
                            showCloudSyncConflictDialog = true
                            false
                        }

                        CloudSnapshotApplyDecision.AlreadyCurrent -> {
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while confirming the sync baseline." }
                            check(cloudSyncBaselineStore.write(session.userId, checkNotNull(remoteDigest))) {
                                "Could not persist the cloud sync baseline. Automatic upload is paused."
                            }
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while confirming the sync baseline." }
                            recordCloudSyncSuccess(session)
                            true
                        }

                        CloudSnapshotApplyDecision.ReplaceAuthoritatively -> {
                            repository.replaceWithBackupJsonObject(
                                root = remoteState,
                                expectedLocalState = localState,
                                activeUserId = session.userId,
                                activeRemote = true
                            )
                            val replacedState = repository.getCloudWorkoutProjectionState()
                            check(replacedState.digest == remoteDigest) {
                                "Cloud state did not round-trip safely. Automatic upload is paused."
                            }
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while confirming the sync baseline." }
                            check(cloudSyncBaselineStore.write(session.userId, replacedState.digest)) {
                                "Could not persist the cloud sync baseline. Automatic upload is paused."
                            }
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while confirming the sync baseline." }
                            recordCloudSyncSuccess(session)
                            true
                        }

                        CloudSnapshotApplyDecision.UploadLocal -> {
                            check(isSameCloudSessionGeneration(
                                session,
                                authManager.authState.value.session
                            )) { "Cloud account changed while resuming local upload." }
                            // The remote digest is still the last confirmed baseline, so the
                            // account-specific Room state is the only changed side. The revision
                            // cached by loadRemoteState keeps the resumed upload compare-and-swap
                            // protected if another device writes before it reaches the server.
                            true
                        }
                    }
                }
            } else {
                sharedCloudExtensions = null
                // Missing remote state may initialize only a genuinely empty account database.
                // A non-empty projection could be stale data from a deleted remote row.
                val localState = repository.getCloudWorkoutProjectionState()
                shouldInitializeMissingRemoteState(localState.isEmpty).also { safeToInitialize ->
                    if (!safeToInitialize) {
                        cloudSyncConflict = CloudSyncConflictSnapshot(
                            userId = session.userId,
                            sessionGeneration = session.sessionGeneration,
                            localDigest = localState.digest,
                            remoteDigest = null,
                            remoteExists = false
                        )
                        updateCloudSyncPhase(session, CloudSyncPhase.Conflict)
                        showCloudSyncConflictDialog = true
                    }
                }
            }
        }
        pullResult.onFailure { throwable ->
            if (throwable is CancellationException) throw throwable
            if (isSameCloudSessionGeneration(session, authManager.authState.value.session)) {
                updateCloudSyncPhase(session, CloudSyncPhase.Error)
                cloudSyncRetryMode = CloudSyncRetryMode.Pull
                authManager.setMessage(
                    authErrorText(throwable, R.string.cloud_sync_load_failed)
                )
            }
        }
        pullResult.onSuccess { canonicalRoundTripSafe ->
            if (shouldSeedCatalogAfterCloudPull(canonicalRoundTripSafe) &&
                isSameCloudSessionGeneration(session, authManager.authState.value.session)
            ) {
                // A conflict must not mutate the reviewed local snapshot. Seed only after a safe
                // pull or after the user explicitly resolves the conflict below.
                repository.seedBuiltInExercises()
                repository.seedDefaultExerciseMuscleMappings()
                cloudSyncConflict = null
                showCloudSyncConflictDialog = false
                if (authManager.authState.value.message?.resourceId == R.string.cloud_sync_conflict) {
                    authManager.setMessage(null, isError = false)
                }
            }
            if (!canonicalRoundTripSafe &&
                isSameCloudSessionGeneration(session, authManager.authState.value.session)
            ) {
                cloudSyncRetryMode = if (cloudSyncConflict == null) {
                    CloudSyncRetryMode.Pull
                } else {
                    null
                }
                authManager.setMessage(
                    LocalizedText(R.string.cloud_sync_conflict)
                )
                updateCloudSyncPhase(
                    session,
                    if (cloudSyncConflict == null) CloudSyncPhase.Error else CloudSyncPhase.Conflict
                )
            }
        }
        val activeSession = authManager.authState.value.session as? AccountSession.Cloud
        if (shouldEnableCloudAutosave(
                pullSucceeded = pullResult.isSuccess,
                canonicalRoundTripSafe = pullResult.getOrDefault(false),
                pulledSession = session,
                activeSession = activeSession
            )
        ) {
            cloudPullGeneration = session.sessionGeneration
        }
    }

    LaunchedEffect(cloudSession?.sessionGeneration, cloudPullGeneration) {
        val session = cloudSession ?: return@LaunchedEffect
        if (cloudPullGeneration != session.sessionGeneration) return@LaunchedEffect
        combine(
            repository.observeSessions(),
            repository.observeExercises(),
            repository.observeExerciseMuscleMappings()
        ) { sessions, exercises, mappings ->
            listOf(sessions.size, exercises.size, mappings.size)
        }
            .onEach { updateCloudSyncPhase(session, CloudSyncPhase.Pending) }
            .debounce(1_500)
            .collect {
                if (authManager.authState.value.isLoading) return@collect
                runCatching {
                    val owner = BackupOwner(
                        accountId = session.userId,
                        userId = session.userId,
                        email = session.email,
                        remote = true
                    )
                    val canonicalState = repository.buildCloudBackupJson(owner = owner)
                    val state = attachSharedCloudExtensions(
                        canonicalCore = canonicalState,
                        extensions = sharedCloudExtensions
                    )
                    val stateDigest = withContext(Dispatchers.Default) {
                        checkNotNull(canonicalWorkoutPayloadDigest(state))
                    }
                    val stats = repository.getSyncProfileStats()
                    authManager.saveRemoteState(
                        session = session,
                        state = state,
                        xp = stats.xp,
                        level = stats.level,
                        workouts = stats.workouts,
                        workoutDurations = workoutDurationSyncItems(canonicalState)
                    )
                    check(isSameCloudSessionGeneration(
                        session,
                        authManager.authState.value.session
                    )) { "Cloud account changed while confirming the sync baseline." }
                    check(cloudSyncBaselineStore.write(session.userId, stateDigest)) {
                        "Could not persist the cloud sync baseline. Automatic upload is paused."
                    }
                    check(isSameCloudSessionGeneration(
                        session,
                        authManager.authState.value.session
                    )) { "Cloud account changed while confirming the sync baseline." }
                    recordCloudSyncSuccess(session)
                }.onFailure { throwable ->
                    if (throwable is CancellationException) throw throwable
                    cloudPullGeneration = null
                    if (isSameCloudSessionGeneration(
                            session,
                            authManager.authState.value.session
                        )
                    ) {
                        val message = authErrorText(throwable, R.string.cloud_sync_save_failed)
                        cloudSyncRetryMode = cloudSyncRetryModeForSaveFailure(message)
                        updateCloudSyncPhase(
                            session,
                            if (message.resourceId == R.string.cloud_sync_conflict) {
                                CloudSyncPhase.Conflict
                            } else {
                                CloudSyncPhase.Error
                            }
                        )
                        authManager.setMessage(message)
                    }
                }
            }
    }

    val resolveCloudSyncConflict: (Boolean) -> Unit = resolve@{ useCloudVersion ->
        if (cloudConflictResolutionInProgress) return@resolve
        val conflict = cloudSyncConflict ?: return@resolve
        val session = cloudSession ?: return@resolve
        if (conflict.userId != session.userId ||
            conflict.sessionGeneration != session.sessionGeneration
        ) return@resolve

        cloudConflictResolutionInProgress = true
        coroutineScope.launch {
            val result = runCatching {
                check(isSameCloudSessionGeneration(
                    session,
                    authManager.authState.value.session
                )) { "Cloud account changed while confirming the sync baseline." }

                // Reload immediately before the choice so the cached server revision can protect
                // a local upload and both reviewed digests can be checked again.
                val remoteState = authManager.loadRemoteState(session)
                    ?.takeIf { it.length() > 0 }
                val preparedRemote = remoteState?.let { candidate ->
                    if (isSharedCloudStateCandidate(candidate)) {
                        withContext(Dispatchers.Default) {
                            prepareSharedCloudState(candidate, session.userId)
                        }
                    } else {
                        null
                    }
                }
                sharedCloudExtensions = preparedRemote?.extensions
                val remoteDigest = preparedRemote?.workoutDigest
                val localState = repository.getCloudWorkoutProjectionState()

                runCurrentCloudSyncConflictAction(
                    conflict = conflict,
                    userId = session.userId,
                    sessionGeneration = session.sessionGeneration,
                    localDigest = localState.digest,
                    remoteDigest = remoteDigest,
                    remoteExists = remoteState != null
                ) {
                    if (useCloudVersion) {
                        val acceptedRemote = checkNotNull(remoteState) {
                            "Cloud data changed on another device. Reload it before syncing again."
                        }
                        val acceptedPrepared = checkNotNull(preparedRemote) {
                            "Cloud state did not round-trip safely. Automatic upload is paused."
                        }
                        val acceptedDigest = acceptedPrepared.workoutDigest
                        repository.replaceWithBackupJsonObject(
                            root = acceptedRemote,
                            expectedLocalState = localState,
                            activeUserId = session.userId,
                            activeRemote = true
                        )
                        val replacedState = repository.getCloudWorkoutProjectionState()
                        check(replacedState.digest == acceptedDigest) {
                            "Cloud state did not round-trip safely. Automatic upload is paused."
                        }
                        check(isSameCloudSessionGeneration(
                            session,
                            authManager.authState.value.session
                        )) { "Cloud account changed while confirming the sync baseline." }
                        check(cloudSyncBaselineStore.write(session.userId, acceptedDigest)) {
                            "Could not persist the cloud sync baseline. Automatic upload is paused."
                        }
                    } else {
                        val owner = BackupOwner(
                            accountId = session.userId,
                            userId = session.userId,
                            email = session.email,
                            remote = true
                        )
                        val canonicalLocalBackup = repository.buildCloudBackupJson(owner = owner)
                        val localBackup = attachSharedCloudExtensions(
                            canonicalCore = canonicalLocalBackup,
                            extensions = sharedCloudExtensions
                        )
                        val localDigest = withContext(Dispatchers.Default) {
                            checkNotNull(canonicalWorkoutPayloadDigest(localBackup))
                        }
                        check(localDigest == localState.digest) {
                            "Local workout data changed while cloud state was loading. Automatic replacement is paused."
                        }
                        val stats = repository.getSyncProfileStats()
                        check(isSameCloudSessionGeneration(
                            session,
                            authManager.authState.value.session
                        )) { "Cloud account changed while confirming the sync baseline." }
                        authManager.saveRemoteState(
                            session = session,
                            state = localBackup,
                            xp = stats.xp,
                            level = stats.level,
                            workouts = stats.workouts,
                            workoutDurations = workoutDurationSyncItems(canonicalLocalBackup)
                        )
                        check(isSameCloudSessionGeneration(
                            session,
                            authManager.authState.value.session
                        )) { "Cloud account changed while confirming the sync baseline." }
                        check(cloudSyncBaselineStore.write(session.userId, localDigest)) {
                            "Could not persist the cloud sync baseline. Automatic upload is paused."
                        }
                    }
                    // Apply additive public-catalog migrations only after the selected version is
                    // safely accepted; autosave will then publish the additive change if needed.
                    repository.seedBuiltInExercises()
                    repository.seedDefaultExerciseMuscleMappings()
                    recordCloudSyncSuccess(session)
                }
            }

            result.exceptionOrNull()?.let { throwable ->
                if (throwable is CancellationException) throw throwable
            }
            cloudConflictResolutionInProgress = false
            result.onSuccess {
                if (isSameCloudSessionGeneration(
                        session,
                        authManager.authState.value.session
                    )
                ) {
                    cloudSyncConflict = null
                    showCloudSyncConflictDialog = false
                    cloudSyncRetryMode = null
                    cloudPullGeneration = session.sessionGeneration
                    authManager.setMessage(
                        LocalizedText(
                            if (useCloudVersion) R.string.cloud_sync_used_cloud
                            else R.string.cloud_sync_kept_device
                        ),
                        isError = false
                    )
                }
            }.onFailure { throwable ->
                if (isSameCloudSessionGeneration(
                        session,
                        authManager.authState.value.session
                    )
                ) {
                    cloudSyncConflict = null
                    showCloudSyncConflictDialog = false
                    cloudPullGeneration = null
                    cloudSyncRetryMode = CloudSyncRetryMode.Pull
                    updateCloudSyncPhase(session, CloudSyncPhase.Error)
                    authManager.setMessage(
                        authErrorText(throwable, R.string.cloud_sync_resolution_failed)
                    )
                }
            }
        }
    }

    val titleRes = when {
        currentRoute == AppDestination.Workouts.route -> R.string.title_workouts
        currentRoute == AppDestination.Missions.route -> R.string.title_missions
        currentRoute == AppDestination.Exercises.route -> R.string.title_exercises
        currentRoute == AppDestination.Progress.route -> R.string.title_progress
        currentRoute == AppDestination.Profile.route -> R.string.title_profile
        currentRoute?.startsWith("friend/") == true -> R.string.friend_details_title
        currentRoute == AppDestination.Ranks.route -> R.string.title_ranks
        currentRoute?.startsWith(AppDestination.AddWorkout.route) == true -> R.string.title_workout_plan
        currentRoute == AppDestination.ActiveWorkout.route -> R.string.active_workout_title
        currentRoute?.startsWith("workout_detail/") == true -> R.string.title_workout_detail
        currentRoute?.startsWith("post_workout_summary/") == true -> R.string.title_post_workout_summary
        else -> R.string.app_name
    }
    val topAppBarScrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()

    key(uiIsolationKey, selectedLanguage) {
        GymBackground {
            Box(modifier = Modifier.fillMaxSize()) {
            if (authState.needsPasswordUpdate) {
                PasswordUpdateScreen(
                    uiState = authState,
                    onUpdatePassword = { password ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                authManager.updatePassword(password)
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(
                                        throwable,
                                        R.string.auth_password_update_failed
                                    )
                                )
                            }
                        }
                    },
                    onCancel = authManager::logout,
                    modifier = Modifier.fillMaxSize()
                )
                return@Box
            }

            if (authState.session == null) {
                AuthScreen(
                    uiState = authState,
                    selectedLanguage = selectedLanguage,
                    onLanguageSelected = languageManager::setLanguage,
                    onLogin = { email, password ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                authManager.login(email, password)
                                authManager.setMessage(null)
                            }.onFailure { throwable ->
                                if (requiresEmailConfirmation(throwable)) {
                                    authManager.showEmailConfirmation(email)
                                } else {
                                    authManager.setMessage(
                                        authErrorText(throwable, R.string.auth_message_login_failed)
                                    )
                                }
                            }
                        }
                    },
                    onSignUp = { email, password, displayName ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                val session = authManager.signUp(email, password, displayName)
                                if (session == null) {
                                    authManager.showEmailConfirmation(email)
                                    return@runCatching
                                }
                                authManager.setMessage(null)
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(throwable, R.string.auth_message_signup_failed)
                                )
                            }
                        }
                    },
                    onResendConfirmation = { email ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                authManager.resendSignUpConfirmation(email)
                                authManager.setMessage(
                                    LocalizedText(R.string.auth_message_confirmation_sent),
                                    isError = false
                                )
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(
                                        throwable,
                                        R.string.auth_message_confirmation_failed
                                    )
                                )
                            }
                        }
                    },
                    onDismissEmailConfirmation = authManager::dismissEmailConfirmation,
                    onPasswordReset = { email ->
                        coroutineScope.launch {
                            authManager.setLoading(true)
                            runCatching {
                                authManager.requestPasswordReset(email)
                                authManager.setMessage(
                                    LocalizedText(R.string.auth_message_password_reset_sent),
                                    isError = false
                                )
                            }.onFailure { throwable ->
                                authManager.setMessage(
                                    authErrorText(
                                        throwable,
                                        R.string.auth_message_password_reset_failed
                                    )
                                )
                            }
                        }
                    },
                    savedLocalProfiles = authManager.savedLocalProfiles(),
                    onContinueLocal = { displayName, resumeExisting ->
                        authManager.setLoading(true)
                        runCatching {
                            authManager.setLocal(displayName, resumeExisting)
                        }.onFailure { throwable ->
                            authManager.setMessage(
                                authErrorText(
                                    throwable,
                                    R.string.auth_message_local_profile_failed
                                )
                            )
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )
                AnimatedVisibility(
                    visible = showIntro,
                    enter = fadeIn() + slideInVertically(initialOffsetY = { it / 8 }),
                    exit = fadeOut() + scaleOut(targetScale = 1.03f)
                ) {
                    AppIntroSplash()
                }
                return@Box
            }

            val signedInMessage = authState.message?.asString()
            val retryLabel = stringResource(R.string.action_retry)
            val resolveLabel = stringResource(R.string.cloud_sync_resolve_action)
            val closeLabel = stringResource(R.string.action_close)
            LaunchedEffect(
                signedInMessage,
                authState.messageIsError,
                authState.message?.resourceId,
                cloudSyncConflict,
                cloudSyncConflictNoticeVersion,
                currentRoute
            ) {
                if (signedInMessage == null) {
                    cloudSyncRetryMode = null
                    snackbarHostState.currentSnackbarData?.dismiss()
                    return@LaunchedEffect
                }
                val retryMode = cloudSyncRetryMode
                val conflictShownInProfile =
                    currentRoute == AppDestination.Profile.route &&
                        authState.message?.resourceId == R.string.cloud_sync_conflict
                if (conflictShownInProfile) {
                    snackbarHostState.currentSnackbarData?.dismiss()
                    return@LaunchedEffect
                }
                val resolvableConflict =
                    authState.message?.resourceId == R.string.cloud_sync_conflict &&
                        cloudSyncConflict != null
                val retryable = retryMode != null &&
                    isRetryableCloudSyncMessage(authState.message)
                val result = snackbarHostState.showSnackbar(
                    message = signedInMessage,
                    actionLabel = when {
                        resolvableConflict -> resolveLabel
                        retryable -> retryLabel
                        authState.messageIsError -> closeLabel
                        else -> null
                    },
                    duration = if (authState.messageIsError) {
                        SnackbarDuration.Indefinite
                    } else {
                        SnackbarDuration.Short
                    }
                )
                if (result == SnackbarResult.ActionPerformed) {
                    if (resolvableConflict) {
                        showCloudSyncConflictDialog = true
                        return@LaunchedEffect
                    }
                    if (retryable) {
                        when (retryMode) {
                            CloudSyncRetryMode.Pull -> cloudSyncRetryVersion += 1
                            CloudSyncRetryMode.ResumeAutosave -> {
                                cloudPullGeneration =
                                    (authManager.authState.value.session as? AccountSession.Cloud)
                                        ?.sessionGeneration
                            }
                        }
                    }
                    cloudSyncRetryMode = null
                    authManager.setMessage(null, isError = false)
                } else if (!authState.messageIsError) {
                    cloudSyncRetryMode = null
                    authManager.setMessage(null, isError = false)
                }
            }

            Scaffold(
                modifier = Modifier
                    .fillMaxSize()
                    .nestedScroll(topAppBarScrollBehavior.nestedScrollConnection)
                    .semantics {
                        if (tutorialMode != null) hideFromAccessibility()
                    },
                containerColor = Color.Transparent,
                contentColor = MaterialTheme.colorScheme.onBackground,
                snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
                topBar = {
                    AppTopBar(
                        titleRes = titleRes,
                        isRootDestination = isBottomTabRoute,
                        showRootTitle = !hasInContentRootHeader,
                        selectedLanguage = selectedLanguage,
                        interactionsEnabled = currentRoute?.startsWith(
                            AppDestination.AddWorkout.route
                        ) != true || !addWorkoutEditorInteractionLocked,
                        onBack = {
                            if (currentRoute?.startsWith(AppDestination.AddWorkout.route) != true ||
                                !addWorkoutEditorInteractionLocked
                            ) {
                                navController.navigateUp()
                            }
                        },
                        onLanguageSelected = { languageManager.setLanguage(it) },
                        scrollBehavior = topAppBarScrollBehavior
                    )
                },
                bottomBar = {
                    if (isBottomTabRoute) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .navigationBarsPadding()
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            contentAlignment = Alignment.BottomCenter
                        ) {
                            Surface(
                                color = MaterialTheme.colorScheme.surface,
                                shape = MaterialTheme.shapes.extraLarge,
                                tonalElevation = 0.dp,
                                shadowElevation = 4.dp,
                                border = BorderStroke(
                                    1.dp,
                                    MaterialTheme.colorScheme.outlineVariant.copy(
                                        alpha = 1f
                                    )
                                )
                            ) {
                                NavigationBar(
                                    modifier = Modifier
                                        .height(76.dp)
                                        .padding(horizontal = 8.dp),
                                    containerColor = Color.Transparent,
                                    tonalElevation = 0.dp
                                ) {
                                    AppDestination.bottomTabs.forEach { tab ->
                                        val tabWorkoutInviteCount = if (
                                            tab == AppDestination.Profile
                                        ) {
                                            workoutInviteBadgeCount
                                        } else {
                                            0
                                        }
                                        val tutorialTarget = when (tab) {
                                            AppDestination.Exercises ->
                                                TutorialTarget.NavigationExercises
                                            AppDestination.Progress ->
                                                TutorialTarget.NavigationProgress
                                            AppDestination.Profile ->
                                                TutorialTarget.NavigationProfile
                                            else -> null
                                        }
                                        NavigationBarItem(
                                            modifier = tutorialTarget?.let { target ->
                                                Modifier.tutorialAnchor(tutorialAnchors, target)
                                            } ?: Modifier,
                                            selected = currentRoute == tab.route,
                                            onClick = {
                                                // Workouts is the retained start destination. Saving
                                                // Profile while popping to it maps that saved entry to
                                                // Workouts; restoring in the same navigate call then puts
                                                // Profile straight back on top and makes Home look inert.
                                                val preserveState = shouldPreserveBottomTabState(tab)
                                                navController.navigate(tab.route) {
                                                    popUpTo(navController.graph.startDestinationId) {
                                                        saveState = preserveState
                                                    }
                                                    launchSingleTop = true
                                                    restoreState = preserveState
                                                }
                                            },
                                            colors = NavigationBarItemDefaults.colors(
                                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                                indicatorColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.18f),
                                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                                            ),
                                            icon = {
                                                BadgedBox(
                                                    badge = {
                                                        if (tabWorkoutInviteCount > 0) {
                                                            Badge {
                                                                Text(tabWorkoutInviteCount.toString())
                                                            }
                                                        }
                                                    }
                                                ) {
                                                    Box(
                                                        modifier = Modifier.size(24.dp),
                                                        contentAlignment = Alignment.Center
                                                    ) {
                                                        Icon(
                                                            imageVector = tab.icon,
                                                            contentDescription = if (
                                                                tabWorkoutInviteCount > 0
                                                            ) {
                                                                stringResource(
                                                                    R.string.workout_invites_pending_count,
                                                                    tabWorkoutInviteCount
                                                                )
                                                            } else {
                                                                stringResource(tab.labelRes)
                                                            },
                                                            modifier = Modifier.size(20.dp)
                                                        )
                                                    }
                                                }
                                            },
                                            label = {
                                                Text(
                                                    text = stringResource(tab.labelRes),
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontSize = if (
                                                            useCompactBottomNavigationLabels
                                                        ) {
                                                            8.5.sp
                                                        } else {
                                                            9.sp
                                                        },
                                                        letterSpacing = if (
                                                            useCompactBottomNavigationLabels
                                                        ) {
                                                            (-0.2).sp
                                                        } else {
                                                            0.sp
                                                        }
                                                    ),
                                                    modifier = if (
                                                        useCompactBottomNavigationLabels
                                                    ) {
                                                        Modifier.wrapContentWidth(unbounded = true)
                                                    } else {
                                                        Modifier.fillMaxWidth()
                                                    },
                                                    textAlign = TextAlign.Center,
                                                    maxLines = 1,
                                                    softWrap = false,
                                                    overflow = TextOverflow.Ellipsis
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                },
                floatingActionButton = {
                    when {
                        currentRoute?.startsWith("workout_detail/") == true -> {
                            val sessionId = navBackStackEntry?.arguments?.getLong("sessionId")
                            if (sessionId != null) {
                                ExtendedFloatingActionButton(
                                    modifier = Modifier.navigationBarsPadding(),
                                    onClick = {
                                        navController.navigate(AppDestination.postWorkoutSummaryRoute(sessionId)) {
                                            launchSingleTop = true
                                        }
                                    },
                                    containerColor = MaterialTheme.colorScheme.tertiary,
                                    contentColor = MaterialTheme.colorScheme.onTertiary,
                                    expanded = true,
                                    text = { Text(text = stringResource(R.string.action_finish_workout)) },
                                    icon = {
                                        Icon(
                                            imageVector = Icons.Default.CheckCircle,
                                            contentDescription = stringResource(R.string.action_finish_workout)
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
            ) { innerPadding ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                ) {
                    NavHost(
                        navController = navController,
                        startDestination = AppDestination.Workouts.route,
                        route = rootGraphRoute,
                        modifier = Modifier.fillMaxSize()
                    ) {
                        composable(route = AppDestination.Workouts.route) { backStackEntry ->
                            val application = applicationContext.gymApplication
                            val viewModel: WorkoutListViewModel = viewModel(
                                factory = WorkoutListViewModel.factory(
                                    repository = repository,
                                    trainingProfileManager = application.trainingProfileManager,
                                    trainingGuidanceManager = application.trainingGuidanceManager
                                )
                            )
                            val draftSyncClient = remember(applicationContext) {
                                PhoneSyncClient(applicationContext)
                            }
                            val addWorkoutDraftViewModelOwner = remember(
                                backStackEntry,
                                rootGraphRoute
                            ) {
                                navController.getBackStackEntry(rootGraphRoute)
                            }
                            val addWorkoutDraftViewModel: AddWorkoutViewModel = viewModel(
                                viewModelStoreOwner = addWorkoutDraftViewModelOwner,
                                key = "add_workout_draft",
                                factory = AddWorkoutViewModel.factory(
                                    repository = repository,
                                    syncClient = draftSyncClient,
                                    trainingProfileManager = application.trainingProfileManager
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()
                            val activeWorkoutSets = activeWorkout?.exercises
                                .orEmpty()
                                .flatMap { it.sets }
                            val activeWorkoutProgress = activeWorkout?.let {
                                activeWorkoutSets.count { set -> set.completedAt != null } to
                                    activeWorkoutSets.size
                            }
                            val discardActiveWorkoutFailed = stringResource(
                                R.string.active_workout_discard_failed
                            )
                            val hasRetainedWorkoutDraft = shouldResumeRetainedWorkoutDraft(
                                hasEditorDraft = addWorkoutDraftViewModel.hasRetainedDraft(),
                                hasLiveTarget = hasSavedLiveWorkoutDraftTarget
                            )
                            val resumeRetainedWorkoutEditor: () -> Boolean = {
                                val shouldResume = activeWorkout == null &&
                                    hasRetainedWorkoutDraft
                                if (shouldResume) {
                                    navController.navigate(AppDestination.AddWorkout.route) {
                                        launchSingleTop = true
                                    }
                                }
                                shouldResume
                            }

                            WorkoutListScreen(
                                uiState = uiState,
                                onSessionClick = { sessionId ->
                                    navController.navigate(AppDestination.workoutDetailRoute(sessionId))
                                },
                                onPreviousMonth = viewModel::previousMonth,
                                onCurrentMonth = viewModel::currentMonth,
                                onNextMonth = viewModel::nextMonth,
                                onMuscleMapPeriodSelected = viewModel::selectMuscleMapPeriod,
                                onMuscleSelected = viewModel::selectMuscle,
                                onAddWorkout = {
                                    navController.navigate(
                                        if (activeWorkout == null) {
                                            AppDestination.AddWorkout.route
                                        } else {
                                            AppDestination.ActiveWorkout.route
                                        }
                                    )
                                },
                                onStartPlan = { launchToken ->
                                    if (!resumeRetainedWorkoutEditor()) {
                                        coroutineScope.launch {
                                            if (viewModel.startRecommendedPlan(launchToken)) {
                                                navController.navigate(
                                                    AppDestination.ActiveWorkout.route
                                                ) {
                                                    launchSingleTop = true
                                                }
                                            } else {
                                                viewModel.refreshTodayPlan()
                                            }
                                        }
                                    }
                                },
                                onOpenPlan = { launchToken ->
                                    if (!resumeRetainedWorkoutEditor()) {
                                        coroutineScope.launch {
                                            val plan = viewModel.resolveLaunchPlan(launchToken)
                                            if (plan != null) {
                                                setLiveWorkoutDraftTarget(null)
                                                navController.navigate(
                                                    AppDestination.addWorkoutRoute(launchToken)
                                                )
                                            } else {
                                                viewModel.refreshTodayPlan()
                                            }
                                        }
                                    }
                                },
                                onStartFirstWorkout = { goal, days, effort ->
                                    if (!resumeRetainedWorkoutEditor()) {
                                        val token = viewModel.buildFirstWorkoutLaunch(
                                            goal,
                                            days,
                                            effort
                                        )
                                        if (token != null) {
                                            coroutineScope.launch {
                                                if (viewModel.startFirstWorkoutPlan(token)) {
                                                    navController.navigate(
                                                        AppDestination.ActiveWorkout.route
                                                    ) {
                                                        launchSingleTop = true
                                                    }
                                                } else {
                                                    viewModel.cancelFirstWorkoutLaunch(token)
                                                    viewModel.refreshTodayPlan()
                                                }
                                            }
                                        }
                                    }
                                },
                                onEditFirstWorkout = { goal, days, effort ->
                                    if (!resumeRetainedWorkoutEditor()) {
                                        val token = viewModel.buildFirstWorkoutLaunch(
                                            goal,
                                            days,
                                            effort
                                        )
                                        handOffFirstWorkoutNavigation(
                                            token = token,
                                            open = { launchToken ->
                                                setLiveWorkoutDraftTarget(null)
                                                navController.navigate(
                                                    AppDestination.addWorkoutRoute(launchToken)
                                                )
                                            },
                                            cancel = viewModel::cancelFirstWorkoutLaunch
                                        )
                                    }
                                },
                                onSkipFirstWorkout = {
                                    val previousDismissed =
                                        viewModel.isFirstWorkoutActivationDismissed()
                                    handOffSkippedFirstWorkoutNavigation(
                                        previousDismissed = previousDismissed,
                                        persistDismissed = { dismissed ->
                                            if (dismissed) {
                                                viewModel.dismissFirstWorkoutActivation()
                                            } else {
                                                viewModel.restoreFirstWorkoutActivationDismissal(
                                                    dismissed
                                                )
                                            }
                                        },
                                        open = {
                                            if (!resumeRetainedWorkoutEditor()) {
                                                setLiveWorkoutDraftTarget(null)
                                                navController.navigate(
                                                    AppDestination.AddWorkout.route
                                                )
                                            }
                                        }
                                    )
                                },
                                hasRetainedWorkoutDraft = hasRetainedWorkoutDraft,
                                activeWorkoutProgress = activeWorkoutProgress,
                                onDiscardActiveWorkout = {
                                    activeWorkout?.activeWorkout?.revision?.let { activeRevision ->
                                        coroutineScope.launch {
                                            val discarded = runCatching {
                                                repository.discardActiveWorkout(activeRevision)
                                            }.getOrNull() == com.example.gymapp.data.repository.DiscardActiveWorkoutResult.Discarded
                                            if (discarded) {
                                                runCatching { restTimerController.stop() }
                                            } else {
                                                snackbarHostState.showSnackbar(discardActiveWorkoutFailed)
                                            }
                                        }
                                    }
                                },
                                tutorialAnchors = tutorialAnchors,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Missions.route) {
                            val application = applicationContext.gymApplication
                            val viewModel: WorkoutListViewModel = viewModel(
                                factory = WorkoutListViewModel.factory(
                                    repository,
                                    application.trainingProfileManager,
                                    application.trainingGuidanceManager
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            MissionsScreen(
                                uiState = uiState,
                                onOpenRanks = {
                                    navController.navigate(AppDestination.Ranks.route) {
                                        launchSingleTop = true
                                    }
                                },
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Ranks.route) {
                            val application = applicationContext.gymApplication
                            val viewModel: WorkoutListViewModel = viewModel(
                                factory = WorkoutListViewModel.factory(
                                    repository,
                                    application.trainingProfileManager,
                                    application.trainingGuidanceManager
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            RanksScreen(
                                uiState = uiState,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(
                            route = AppDestination.ADD_WORKOUT_ROUTE_PATTERN,
                            arguments = listOf(
                                navArgument(AppDestination.ADD_WORKOUT_LAUNCH_ARGUMENT) {
                                    type = NavType.StringType
                                    defaultValue = ""
                                }
                            )
                        ) { backStackEntry ->
                            val context = LocalContext.current
                            val syncClient = remember(context) { PhoneSyncClient(context) }
                            val application = context.gymApplication
                            val launchToken = remember(backStackEntry, uiIsolationKey) {
                                val encoded = backStackEntry.arguments
                                    ?.getString(AppDestination.ADD_WORKOUT_LAUNCH_ARGUMENT)
                                    .orEmpty()
                                backStackEntry.arguments?.remove(
                                    AppDestination.ADD_WORKOUT_LAUNCH_ARGUMENT
                                )
                                encoded.takeIf(String::isNotEmpty)
                            }
                            val launchPlanHandoff: suspend (
                                String,
                                (com.example.gymapp.data.repository.SmartWorkoutLaunchPlan) -> Boolean,
                                (com.example.gymapp.data.repository.SmartWorkoutLaunchPlan) -> Boolean
                            ) -> Boolean =
                                remember(backStackEntry, uiIsolationKey) {
                                    val workoutsEntry = runCatching {
                                        navController.getBackStackEntry(AppDestination.Workouts.route)
                                    }.getOrNull()
                                    if (workoutsEntry == null) {
                                        { _, _, _ -> false }
                                    } else {
                                        val sourceViewModel: WorkoutListViewModel =
                                            androidx.lifecycle.ViewModelProvider(
                                                workoutsEntry,
                                                WorkoutListViewModel.factory(
                                                    repository,
                                                    application.trainingProfileManager,
                                                    application.trainingGuidanceManager
                                                )
                                            )[WorkoutListViewModel::class.java]
                                        sourceViewModel::handOffLaunchPlan
                                    }
                            }
                            val addWorkoutViewModelOwner = remember(
                                backStackEntry,
                                rootGraphRoute
                            ) {
                                navController.getBackStackEntry(rootGraphRoute)
                            }
                            val viewModel: AddWorkoutViewModel = viewModel(
                                viewModelStoreOwner = addWorkoutViewModelOwner,
                                key = "add_workout_draft",
                                factory = AddWorkoutViewModel.factory(
                                    repository = repository,
                                    syncClient = syncClient,
                                    trainingProfileManager = application.trainingProfileManager
                                )
                            )
                            LaunchedEffect(launchToken) {
                                launchToken?.let { token ->
                                    viewModel.openLaunchPlan(token, launchPlanHandoff)
                                }
                            }
                            val uiState by viewModel.uiState.collectAsState()
                            val smartCoachPlanNote = stringResource(R.string.smart_coach_plan_note)
                            val sharedWorkoutImported = stringResource(
                                R.string.message_shared_workout_imported
                            )
                            val sharedWorkoutImportFailed = stringResource(
                                R.string.message_shared_workout_import_failed
                            )
                            val shareWorkoutChooserTitle = stringResource(
                                R.string.action_share_workout
                            )
                            val shareWorkoutFailed = stringResource(
                                R.string.message_share_workout_failed
                            )
                            val workoutInviteSent = stringResource(R.string.workout_invite_sent)
                            val workoutInviteSendFailed = stringResource(
                                R.string.workout_invite_send_failed
                            )
                            val liveWorkoutInviteSendFailed = stringResource(
                                R.string.live_workout_send_failed
                            )
                            var workoutPlanToShare by remember {
                                mutableStateOf<SharedWorkoutPlan?>(null)
                            }
                            var workoutInviteSendProfileId by remember {
                                mutableStateOf<String?>(null)
                            }
                            var liveWorkoutInviteSendProfileId by remember {
                                mutableStateOf<String?>(null)
                            }
                            var liveWorkoutDraftSendSnapshot by remember {
                                mutableStateOf<LiveWorkoutDraftSendSnapshot?>(null)
                            }
                            var liveWorkoutInviteValidationProfileId by remember {
                                mutableStateOf<String?>(null)
                            }
                            val liveWorkoutNoticeText = liveWorkoutState.notice?.asString()
                            val liveWorkoutErrorText = liveWorkoutState.error?.asString()
                            val approvedSharedWorkout = pendingSharedWorkout?.takeIf {
                                it.id == approvedSharedWorkoutId
                            }
                            val acceptedSocialWorkout = friendsState?.acceptedWorkout
                            val selectedLiveWorkoutFriend = liveWorkoutDraftTarget?.let { target ->
                                friendsState?.dashboard?.friends
                                    ?.firstOrNull { friend ->
                                        friend.profileId == target.binding.profileId &&
                                            isFriendWorkoutPickerBindingCurrent(
                                                binding = target.binding,
                                                activeSession = cloudSession,
                                                currentProfileId = friend.profileId,
                                                currentFriendshipId = friend.friendshipId,
                                                currentFriendshipRevision =
                                                    friend.friendshipRevision
                                            )
                                    }
                            }

                            LaunchedEffect(Unit) {
                                friendsViewModel?.refreshAll()
                                liveWorkoutViewModel?.refresh()
                            }

                            val workoutInviteNotice = friendsState?.notice?.asString()
                            val workoutInviteError = friendsState?.error?.asString()
                            val workoutInviteFeedback = workoutInviteSendFeedback(
                                trackedProfileId = workoutInviteSendProfileId,
                                actionsInFlight = friendsState?.actionsInFlight.orEmpty(),
                                hasNotice = workoutInviteNotice != null,
                                hasError = workoutInviteError != null
                            )
                            LaunchedEffect(
                                workoutInviteFeedback,
                                workoutInviteNotice,
                                workoutInviteError
                            ) {
                                when (workoutInviteFeedback) {
                                    WorkoutInviteSendFeedback.Succeeded -> {
                                        workoutPlanToShare = null
                                        workoutInviteSendProfileId = null
                                        preferredShareFriendProfileId = null
                                        friendsViewModel?.clearMessages()
                                        snackbarHostState.showSnackbar(
                                            workoutInviteNotice ?: workoutInviteSent
                                        )
                                    }
                                    WorkoutInviteSendFeedback.Failed -> {
                                        workoutInviteSendProfileId = null
                                        friendsViewModel?.clearMessages()
                                        snackbarHostState.showSnackbar(
                                            workoutInviteError ?: workoutInviteSendFailed
                                        )
                                    }
                                    WorkoutInviteSendFeedback.Idle,
                                    WorkoutInviteSendFeedback.Sending -> Unit
                                }
                            }

                            LaunchedEffect(
                                liveWorkoutInviteSendProfileId,
                                liveWorkoutState.actionsInFlight,
                                liveWorkoutNoticeText,
                                liveWorkoutErrorText
                            ) {
                                val profileId = liveWorkoutInviteSendProfileId
                                    ?: return@LaunchedEffect
                                if ("send-$profileId" in liveWorkoutState.actionsInFlight) {
                                    return@LaunchedEffect
                                }
                                val message = liveWorkoutNoticeText ?: liveWorkoutErrorText
                                    ?: return@LaunchedEffect
                                if (liveWorkoutState.notice?.resourceId ==
                                    R.string.live_workout_invite_sent
                                ) {
                                    val sendSnapshot = liveWorkoutDraftSendSnapshot
                                    val successfulTargetStillBound = sendSnapshot != null &&
                                        shouldClearSuccessfulLiveWorkoutDraftTarget(
                                            snapshot = sendSnapshot,
                                            currentTarget = liveWorkoutDraftTarget
                                        )
                                    if (sendSnapshot != null &&
                                        liveWorkoutDraftSendStillMatches(
                                            snapshot = sendSnapshot,
                                            currentTarget = liveWorkoutDraftTarget,
                                            currentDraftFingerprint =
                                                viewModel.retainedDraftFingerprint()
                                        )
                                    ) {
                                        viewModel.discardDraftIfUnchanged(
                                            sendSnapshot.draftFingerprint
                                        )
                                    }
                                    workoutPlanToShare = null
                                    preferredShareFriendProfileId = null
                                    if (successfulTargetStillBound) {
                                        setLiveWorkoutDraftTarget(null)
                                    }
                                    liveWorkoutDraftSendSnapshot = null
                                    liveWorkoutInviteSendProfileId = null
                                    liveWorkoutViewModel?.clearMessages()
                                    navController.navigate(AppDestination.Profile.route) {
                                        popUpTo(backStackEntry.destination.id) {
                                            inclusive = true
                                        }
                                        launchSingleTop = true
                                    }
                                    coroutineScope.launch {
                                        snackbarHostState.showSnackbar(message)
                                    }
                                    return@LaunchedEffect
                                }
                                liveWorkoutInviteSendProfileId = null
                                liveWorkoutDraftSendSnapshot = null
                                snackbarHostState.showSnackbar(message)
                                liveWorkoutViewModel?.clearMessages()
                            }

                            LaunchedEffect(approvedSharedWorkout?.id) {
                                val pending = approvedSharedWorkout ?: return@LaunchedEffect
                                val applied = viewModel.applySharedWorkoutPlan(pending.plan)
                                sharedWorkoutInbox.consume(pending.id)
                                approvedSharedWorkoutId = null
                                snackbarHostState.showSnackbar(
                                    if (applied) {
                                        sharedWorkoutImported
                                    } else {
                                        sharedWorkoutImportFailed
                                    }
                                )
                            }

                            LaunchedEffect(acceptedSocialWorkout?.inviteId, activeWorkout != null) {
                                val accepted = acceptedSocialWorkout ?: return@LaunchedEffect
                                if (activeWorkout != null) return@LaunchedEffect
                                val applied = viewModel.applySharedWorkoutPlan(accepted.plan)
                                if (shouldConsumeAcceptedSocialWorkout(applied)) {
                                    friendsViewModel?.consumeAcceptedWorkout(accepted.inviteId)
                                }
                                snackbarHostState.showSnackbar(
                                    if (applied) sharedWorkoutImported else sharedWorkoutImportFailed
                                )
                            }

                            LaunchedEffect(uiState.activeWorkoutStarted) {
                                if (uiState.activeWorkoutStarted) {
                                    navController.navigate(AppDestination.ActiveWorkout.route) {
                                        popUpTo(backStackEntry.destination.id) {
                                            inclusive = true
                                        }
                                    }
                                    viewModel.consumeActiveWorkoutStarted()
                                }
                            }

                            AddWorkoutScreen(
                                uiState = uiState,
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                onWorkoutDateSelected = viewModel::updateWorkoutDate,
                                onNoteChange = viewModel::updateNote,
                                onTrainingSplitSelected = viewModel::updateTrainingSplit,
                                onWorkoutsPerWeekSelected = viewModel::updateWorkoutsPerWeek,
                                onTrainingGoalSelected = viewModel::updateTrainingGoal,
                                onCalorieModeSelected = viewModel::updateCalorieMode,
                                onSmartWorkoutEffortSelected = viewModel::updateSmartWorkoutEffort,
                                onGenerateSmartWorkout = {
                                    viewModel.generateSmartWorkout(smartCoachPlanNote)
                                },
                                onOpenSmartAlternatives = viewModel::openSmartWorkoutAlternatives,
                                onCloseSmartAlternatives = viewModel::closeSmartWorkoutAlternatives,
                                onApplySmartAlternative = viewModel::applySmartWorkoutAlternative,
                                onAddExerciseDraft = viewModel::addExerciseDraft,
                                onClearPlan = { viewModel.clearWorkoutPlan() },
                                onRemoveExerciseDraft = viewModel::removeExerciseDraft,
                                onExerciseSelected = viewModel::updateExerciseSelection,
                                onAddSet = viewModel::addSet,
                                onAddSetFromPrevious = viewModel::addSetFromPrevious,
                                onRemoveSet = viewModel::removeSet,
                                onSetWeightChanged = viewModel::updateSetWeight,
                                onSetRepsChanged = viewModel::updateSetReps,
                                onApplyLastWeight = viewModel::applyLastWeight,
                                onApplyWorkoutRecommendation = viewModel::applyWorkoutRecommendation,
                                onRepeatLastWorkout = viewModel::repeatLastWorkout,
                                onOpenTemplatePicker = viewModel::openWorkoutTemplatePicker,
                                onCloseTemplatePicker = viewModel::closeWorkoutTemplatePicker,
                                onCopyWorkoutTemplate = viewModel::copyWorkoutTemplate,
                                onSyncPlanToWatch = viewModel::syncPlanToWatch,
                                onShareWorkout = {
                                    val plan = viewModel.prepareSharedWorkoutPlan()
                                    if (plan == null) {
                                        coroutineScope.launch {
                                            snackbarHostState.showSnackbar(shareWorkoutFailed)
                                        }
                                    } else {
                                        workoutPlanToShare = plan
                                    }
                                },
                                liveInviteTargetName = liveWorkoutDraftTarget?.displayName,
                                hasLiveInviteTarget = hasSavedLiveWorkoutDraftTarget,
                                isLiveInviteAvailable = selectedLiveWorkoutFriend != null &&
                                    activeWorkout == null &&
                                    liveWorkoutViewModel != null,
                                isLiveInviteSending =
                                    liveWorkoutInviteValidationProfileId != null ||
                                        liveWorkoutInviteSendProfileId != null ||
                                        selectedLiveWorkoutFriend?.let { friend ->
                                            "send-${friend.profileId}" in
                                                liveWorkoutState.actionsInFlight
                                        } == true,
                                onSendLiveInvite = sendLiveInvite@ {
                                    val target = liveWorkoutDraftTarget
                                        ?: return@sendLiveInvite
                                    val liveViewModel = liveWorkoutViewModel
                                    val expectedSession = cloudSession
                                    when {
                                        liveWorkoutInviteValidationProfileId != null ||
                                            liveWorkoutInviteSendProfileId != null -> Unit
                                        activeWorkout != null -> coroutineScope.launch {
                                            snackbarHostState.showSnackbar(
                                                applicationContext.getString(
                                                    R.string.live_workout_active_blocked
                                                )
                                            )
                                        }
                                        liveViewModel == null || expectedSession == null ->
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(
                                                    liveWorkoutInviteSendFailed
                                                )
                                            }
                                        else -> {
                                            liveWorkoutDraftSendSnapshot = null
                                            liveWorkoutInviteValidationProfileId =
                                                target.binding.profileId
                                            addWorkoutEditorInteractionLocked = true
                                            coroutineScope.launch {
                                                try {
                                                    val freshDashboard =
                                                        authManager.loadSocialDashboard(
                                                            expectedSession
                                                        )
                                                    val currentTarget =
                                                        restoreLiveWorkoutDraftTarget(
                                                            hasTarget =
                                                                hasSavedLiveWorkoutDraftTarget,
                                                            draftBindingId =
                                                                savedLiveWorkoutDraftBindingId,
                                                            userId = savedLiveWorkoutDraftUserId,
                                                            sessionGeneration =
                                                                savedLiveWorkoutDraftSessionGeneration,
                                                            profileId =
                                                                savedLiveWorkoutDraftProfileId,
                                                            friendshipId =
                                                                savedLiveWorkoutDraftFriendshipId,
                                                            friendshipRevision =
                                                                savedLiveWorkoutDraftFriendshipRevision,
                                                            displayName =
                                                                savedLiveWorkoutDraftDisplayName
                                                        )
                                                    val authoritativeFriend =
                                                        resolveLiveWorkoutFriendFromFreshDashboard(
                                                            target = target,
                                                            activeSession = authManager
                                                                .authState
                                                                .value
                                                                .session,
                                                            freshFriends = freshDashboard.friends
                                                        )
                                                    if (currentTarget != target ||
                                                        activeWorkout != null ||
                                                        authoritativeFriend == null
                                                    ) {
                                                        snackbarHostState.showSnackbar(
                                                            liveWorkoutInviteSendFailed
                                                        )
                                                        return@launch
                                                    }
                                                    val plan = viewModel
                                                        .prepareSharedWorkoutPlan()
                                                    if (plan == null) {
                                                        snackbarHostState.showSnackbar(
                                                            shareWorkoutFailed
                                                        )
                                                        return@launch
                                                    }
                                                    liveViewModel.clearMessages()
                                                    val draftFingerprint = viewModel
                                                        .retainedDraftFingerprint()
                                                    liveWorkoutDraftSendSnapshot =
                                                        LiveWorkoutDraftSendSnapshot(
                                                            target = target,
                                                            draftFingerprint = draftFingerprint
                                                        )
                                                    liveWorkoutInviteSendProfileId =
                                                        authoritativeFriend.profileId
                                                    liveViewModel.sendInvite(
                                                        authoritativeFriend,
                                                        plan,
                                                        LiveWorkoutDraftSendRequest(
                                                            draftBindingId = target.draftBindingId,
                                                            draftFingerprint = draftFingerprint
                                                                .durableDigest()
                                                        )
                                                    )
                                                } catch (cancelled: CancellationException) {
                                                    throw cancelled
                                                } catch (_: Throwable) {
                                                    liveWorkoutDraftSendSnapshot = null
                                                    liveWorkoutInviteSendProfileId = null
                                                    snackbarHostState.showSnackbar(
                                                        liveWorkoutInviteSendFailed
                                                    )
                                                } finally {
                                                    if (liveWorkoutInviteValidationProfileId ==
                                                        target.binding.profileId
                                                    ) {
                                                        liveWorkoutInviteValidationProfileId = null
                                                    }
                                                }
                                            }
                                        }
                                    }
                                },
                                onStartWorkout = viewModel::startWorkout,
                                onNavigateToHistory = {
                                    navController.navigateUp()
                                },
                                onDiscardPlan = {
                                    viewModel.discardDraft()
                                    setLiveWorkoutDraftTarget(null)
                                    navController.navigateUp()
                                },
                                externalCloseRequestVersion = 0L,
                                onExternalCloseRequestHandled = {},
                                onDirtyStateChanged = {},
                                onInteractionLockChanged = { locked ->
                                    addWorkoutEditorInteractionLocked = locked
                                },
                                modifier = Modifier.fillMaxSize()
                            )

                            workoutPlanToShare?.let { plan ->
                                WorkoutShareSheet(
                                    friends = friendsState?.dashboard?.friends.orEmpty(),
                                    preferredFriendProfileId = preferredShareFriendProfileId,
                                    isCloudAccount = cloudSession != null,
                                    actionsInFlight = friendsState?.actionsInFlight.orEmpty(),
                                    liveActionsInFlight = liveWorkoutState.actionsInFlight,
                                    onShareLink = {
                                        val didOpenShareSheet = runCatching {
                                            shareWorkoutUrl(
                                                context = context,
                                                url = SharedWorkoutLink.buildUrl(plan.exercises),
                                                chooserTitle = shareWorkoutChooserTitle
                                            )
                                        }.isSuccess
                                        if (didOpenShareSheet) {
                                            workoutPlanToShare = null
                                        } else {
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(shareWorkoutFailed)
                                            }
                                        }
                                    },
                                    onSendToFriend = { friend ->
                                        val socialViewModel = friendsViewModel
                                        if (socialViewModel == null) {
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(
                                                    workoutInviteSendFailed
                                                )
                                            }
                                        } else {
                                            socialViewModel.clearMessages()
                                            workoutInviteSendProfileId = friend.profileId
                                            socialViewModel.sendWorkoutInvite(friend.profileId, plan)
                                        }
                                    },
                                    onStartLiveWithFriend = { friend ->
                                        val liveViewModel = liveWorkoutViewModel
                                        if (liveViewModel == null) {
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(
                                                    workoutInviteSendFailed
                                                )
                                            }
                                        } else {
                                            liveViewModel.clearMessages()
                                            liveWorkoutInviteSendProfileId = friend.profileId
                                            liveViewModel.sendInvite(friend, plan)
                                        }
                                    },
                                    onDismiss = { workoutPlanToShare = null }
                                )
                            }
                        }

                        composable(route = AppDestination.ActiveWorkout.route) {
                            val viewModel: ActiveWorkoutViewModel = viewModel(
                                factory = ActiveWorkoutViewModel.factory(
                                    repository = repository,
                                    restTimerController = restTimerController,
                                    timerAccountKey = checkNotNull(
                                        restTimerAccountKey(authState.session)
                                    ),
                                    liveSync = liveWorkoutViewModel
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            LaunchedEffect(
                                uiState.finishedSessionId,
                                uiState.wasDiscarded,
                                uiState.isMissing
                            ) {
                                val finishedSessionId = uiState.finishedSessionId
                                when {
                                    finishedSessionId != null -> {
                                        navController.navigate(
                                            AppDestination.postWorkoutSummaryRoute(finishedSessionId)
                                        ) {
                                            popUpTo(AppDestination.ActiveWorkout.route) {
                                                inclusive = true
                                            }
                                        }
                                        viewModel.consumeNavigation()
                                    }
                                    uiState.wasDiscarded || uiState.isMissing -> {
                                        navController.navigate(AppDestination.Workouts.route) {
                                            popUpTo(AppDestination.ActiveWorkout.route) {
                                                inclusive = true
                                            }
                                            launchSingleTop = true
                                        }
                                        viewModel.consumeNavigation()
                                    }
                                }
                            }

                            ActiveWorkoutScreen(
                                uiState = uiState,
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                onSetWeightChanged = viewModel::updateSetWeight,
                                onSetRepsChanged = viewModel::updateSetReps,
                                onSaveExercise = viewModel::saveExercise,
                                onAddSet = viewModel::addSet,
                                onRecordAllPendingSets = viewModel::recordAllPendingSets,
                                onFinishWorkout = viewModel::finishWorkout,
                                onDiscardWorkout = viewModel::discardWorkout,
                                onDismissMessage = viewModel::dismissMessage,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(
                            route = AppDestination.PostWorkoutSummary.route,
                            arguments = listOf(
                                navArgument("sessionId") { type = NavType.LongType }
                            )
                        ) { backStackEntry ->
                            val sessionId = backStackEntry.arguments?.getLong("sessionId") ?: return@composable
                            val viewModel: PostWorkoutSummaryViewModel = viewModel(
                                key = "post_workout_summary_$sessionId",
                                factory = PostWorkoutSummaryViewModel.factory(
                                    repository = repository,
                                    sessionId = sessionId,
                                    trainingGuidanceManager = applicationContext.gymApplication
                                        .trainingGuidanceManager,
                                    trainingProfileManager = applicationContext.gymApplication
                                        .trainingProfileManager
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            PostWorkoutSummaryScreen(
                                uiState = uiState,
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                onViewWorkout = {
                                    navController.navigate(AppDestination.workoutDetailRoute(sessionId)) {
                                        popUpTo(AppDestination.PostWorkoutSummary.route) {
                                            inclusive = true
                                        }
                                    }
                                },
                                onDone = {
                                    val returnedToWorkouts = navController.popBackStack(
                                        AppDestination.Workouts.route,
                                        inclusive = false
                                    )
                                    if (!returnedToWorkouts) {
                                        navController.navigate(AppDestination.Workouts.route) {
                                            popUpTo(navController.graph.startDestinationId) {
                                                saveState = true
                                            }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    }
                                },
                                onFeedbackSelected = viewModel::selectFeedback,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(
                            route = AppDestination.WorkoutDetail.route,
                            arguments = listOf(
                                navArgument("sessionId") { type = NavType.LongType }
                            )
                        ) { backStackEntry ->
                            val sessionId = backStackEntry.arguments?.getLong("sessionId") ?: return@composable
                            val context = LocalContext.current
                            val viewModel: WorkoutDetailViewModel = viewModel(
                                key = "workout_detail_$sessionId",
                                factory = WorkoutDetailViewModel.factory(
                                    repository = repository,
                                    sessionId = sessionId
                                )
                            )
                            val uiState by viewModel.uiState.collectAsState()
                            var workoutPlanToShare by remember {
                                mutableStateOf<SharedWorkoutPlan?>(null)
                            }
                            var workoutInviteSendProfileId by remember {
                                mutableStateOf<String?>(null)
                            }
                            var liveWorkoutInviteSendProfileId by remember {
                                mutableStateOf<String?>(null)
                            }
                            val shareWorkoutChooserTitle = stringResource(
                                R.string.action_share_workout
                            )
                            val shareWorkoutFailed = stringResource(
                                R.string.message_share_workout_failed
                            )
                            val workoutInviteSent = stringResource(R.string.workout_invite_sent)
                            val workoutInviteSendFailed = stringResource(
                                R.string.workout_invite_send_failed
                            )
                            val workoutInviteNotice = friendsState?.notice?.asString()
                            val workoutInviteError = friendsState?.error?.asString()
                            val workoutInviteFeedback = workoutInviteSendFeedback(
                                trackedProfileId = workoutInviteSendProfileId,
                                actionsInFlight = friendsState?.actionsInFlight.orEmpty(),
                                hasNotice = workoutInviteNotice != null,
                                hasError = workoutInviteError != null
                            )
                            val liveWorkoutNoticeText = liveWorkoutState.notice?.asString()
                            val liveWorkoutErrorText = liveWorkoutState.error?.asString()

                            LaunchedEffect(Unit) {
                                friendsViewModel?.refreshAll()
                                liveWorkoutViewModel?.refresh()
                            }
                            LaunchedEffect(
                                workoutInviteFeedback,
                                workoutInviteNotice,
                                workoutInviteError
                            ) {
                                when (workoutInviteFeedback) {
                                    WorkoutInviteSendFeedback.Succeeded -> {
                                        workoutPlanToShare = null
                                        workoutInviteSendProfileId = null
                                        preferredShareFriendProfileId = null
                                        friendsViewModel?.clearMessages()
                                        snackbarHostState.showSnackbar(
                                            workoutInviteNotice ?: workoutInviteSent
                                        )
                                    }
                                    WorkoutInviteSendFeedback.Failed -> {
                                        workoutInviteSendProfileId = null
                                        friendsViewModel?.clearMessages()
                                        snackbarHostState.showSnackbar(
                                            workoutInviteError ?: workoutInviteSendFailed
                                        )
                                    }
                                    WorkoutInviteSendFeedback.Idle,
                                    WorkoutInviteSendFeedback.Sending -> Unit
                                }
                            }
                            LaunchedEffect(
                                liveWorkoutInviteSendProfileId,
                                liveWorkoutState.actionsInFlight,
                                liveWorkoutNoticeText,
                                liveWorkoutErrorText
                            ) {
                                val profileId = liveWorkoutInviteSendProfileId
                                    ?: return@LaunchedEffect
                                if ("send-$profileId" in liveWorkoutState.actionsInFlight) {
                                    return@LaunchedEffect
                                }
                                val message = liveWorkoutNoticeText ?: liveWorkoutErrorText
                                    ?: return@LaunchedEffect
                                if (liveWorkoutNoticeText != null) {
                                    workoutPlanToShare = null
                                    preferredShareFriendProfileId = null
                                }
                                liveWorkoutInviteSendProfileId = null
                                snackbarHostState.showSnackbar(message)
                                liveWorkoutViewModel?.clearMessages()
                            }

                            WorkoutDetailScreen(
                                uiState = uiState,
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                events = viewModel.events,
                                onAddExerciseToWorkout = viewModel::addExerciseToWorkout,
                                onAddSet = viewModel::addSet,
                                onDeleteSet = viewModel::requestDeleteSet,
                                onConfirmDeleteSet = viewModel::confirmSetDeletion,
                                onDismissDeleteSet = viewModel::dismissSetDeletion,
                                onDeleteSession = viewModel::deleteSession,
                                onSessionDeleted = { navController.popBackStack() },
                                onUpdateSet = viewModel::updateSet,
                                onShareWorkout = { workoutPlanToShare = it },
                                modifier = Modifier.fillMaxSize()
                            )

                            workoutPlanToShare?.let { plan ->
                                WorkoutShareSheet(
                                    friends = friendsState?.dashboard?.friends.orEmpty(),
                                    preferredFriendProfileId = preferredShareFriendProfileId,
                                    isCloudAccount = cloudSession != null,
                                    actionsInFlight = friendsState?.actionsInFlight.orEmpty(),
                                    liveActionsInFlight = liveWorkoutState.actionsInFlight,
                                    onShareLink = {
                                        val didOpenShareSheet = runCatching {
                                            shareWorkoutUrl(
                                                context = context,
                                                url = SharedWorkoutLink.buildUrl(plan.exercises),
                                                chooserTitle = shareWorkoutChooserTitle
                                            )
                                        }.isSuccess
                                        if (didOpenShareSheet) {
                                            workoutPlanToShare = null
                                        } else {
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(shareWorkoutFailed)
                                            }
                                        }
                                    },
                                    onSendToFriend = { friend ->
                                        val socialViewModel = friendsViewModel
                                        if (socialViewModel == null) {
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(
                                                    workoutInviteSendFailed
                                                )
                                            }
                                        } else {
                                            socialViewModel.clearMessages()
                                            workoutInviteSendProfileId = friend.profileId
                                            socialViewModel.sendWorkoutInvite(friend.profileId, plan)
                                        }
                                    },
                                    onStartLiveWithFriend = { friend ->
                                        val liveViewModel = liveWorkoutViewModel
                                        if (liveViewModel == null) {
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(
                                                    workoutInviteSendFailed
                                                )
                                            }
                                        } else {
                                            liveViewModel.clearMessages()
                                            liveWorkoutInviteSendProfileId = friend.profileId
                                            liveViewModel.sendInvite(friend, plan)
                                        }
                                    },
                                    onDismiss = { workoutPlanToShare = null }
                                )
                            }
                        }

                        composable(route = AppDestination.Exercises.route) {
                            val viewModel: ExerciseListViewModel = viewModel(
                                factory = ExerciseListViewModel.factory(repository, authManager)
                            )
                            val uiState by viewModel.uiState.collectAsState()

                            ExerciseListScreen(
                                uiState = uiState,
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                onNameChange = viewModel::updateNewExerciseName,
                                onAddExercise = viewModel::addExercise,
                                onExerciseClick = viewModel::openExerciseHistory,
                                onStartRenameExercise = viewModel::startRenameExercise,
                                onRenameExerciseNameChange = viewModel::updateEditingExerciseName,
                                onSaveRenameExercise = viewModel::saveRenameExercise,
                                onDismissRenameExercise = viewModel::closeRenameExercise,
                                onDeleteExercise = viewModel::requestDeleteExercise,
                                onConfirmDeleteExercise = viewModel::confirmExerciseDeletion,
                                onDismissDeleteExercise = viewModel::dismissExerciseDeletion,
                                onEditExerciseMapping = viewModel::openExerciseMapping,
                                onToggleExerciseMappingMuscle = viewModel::toggleExerciseMappingMuscle,
                                onSaveExerciseMapping = viewModel::saveExerciseMapping,
                                onDismissExerciseMapping = viewModel::closeExerciseMapping,
                                onEditExerciseLoadProfile = viewModel::openExerciseLoadProfile,
                                onExerciseLoadDirectionChange = viewModel::updateExerciseLoadDirection,
                                onExerciseLoadWeightsChange = viewModel::updateExerciseLoadWeights,
                                onApplyExerciseLoadPreset = viewModel::applyExerciseLoadPreset,
                                onSaveExerciseLoadProfile = viewModel::saveExerciseLoadProfile,
                                onClearExerciseLoadProfile = viewModel::clearExerciseLoadProfile,
                                onDismissExerciseLoadProfile = viewModel::closeExerciseLoadProfile,
                                onDismissHistory = viewModel::closeExerciseHistory,
                                onToggleFavorite = viewModel::toggleFavorite,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Progress.route) {
                            val progressViewModel: ExerciseProgressViewModel = viewModel(
                                key = "progress_exercises",
                                factory = ExerciseProgressViewModel.factory(repository)
                            )
                            val exerciseProgressState by
                                progressViewModel.uiState.collectAsState()
                            val overviewViewModel: WorkoutListViewModel = viewModel(
                                key = "progress_overview",
                                factory = WorkoutListViewModel.factory(
                                    repository = repository,
                                    trainingProfileManager = gymApplication.trainingProfileManager,
                                    trainingGuidanceManager = trainingGuidanceManager
                                )
                            )
                            val overviewState by overviewViewModel.uiState.collectAsState()

                            ProgressHubScreen(
                                overviewState = overviewState,
                                exerciseState = exerciseProgressState,
                                exerciseMediaOwnerKey = checkNotNull(authState.session).databaseName(),
                                onSelectExercise = progressViewModel::selectExercise,
                                onPreviousExerciseMonth = progressViewModel::previousMonth,
                                onCurrentExerciseMonth = progressViewModel::currentMonth,
                                onNextExerciseMonth = progressViewModel::nextMonth,
                                onPreviousOverviewMonth = overviewViewModel::previousMonth,
                                onCurrentOverviewMonth = overviewViewModel::currentMonth,
                                onNextOverviewMonth = overviewViewModel::nextMonth,
                                onMuscleMapPeriodSelected =
                                    overviewViewModel::selectMuscleMapPeriod,
                                onMuscleSelected = overviewViewModel::selectMuscle,
                                onOpenRanks = {
                                    navController.navigate(AppDestination.Ranks.route)
                                },
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(route = AppDestination.Profile.route) {
                            val profileViewModel: ExerciseListViewModel = viewModel(
                                key = "profile_account_tools",
                                factory = ExerciseListViewModel.factory(repository, authManager)
                            )
                            val profileState by profileViewModel.uiState.collectAsState()
                            val socialState = friendsState ?: FriendsUiState(
                                isCloudAccount = cloudSession != null
                            )
                            LaunchedEffect(Unit) {
                                friendsViewModel?.refreshAll()
                                liveWorkoutViewModel?.refresh()
                            }

                            ProfileScreen(
                                accountState = profileState,
                                backupShareOwnerKey = checkNotNull(authState.session).databaseName(),
                                pushUiState = pushUiState,
                                onEnablePush = pushManager::enable,
                                onDisablePush = pushManager::disable,
                                onOpenPushSettings = pushManager::openNotificationSettings,
                                friendsState = socialState,
                                liveWorkoutState = liveWorkoutState,
                                onRefreshFriends = {
                                    friendsViewModel?.refreshAll()
                                    liveWorkoutViewModel?.refresh()
                                },
                                onSendFriendRequest = { code ->
                                    friendsViewModel?.sendFriendRequest(code)
                                },
                                onAcceptFriendRequest = { request ->
                                    friendsViewModel?.acceptFriendRequest(request)
                                },
                                onDeclineFriendRequest = { request ->
                                    friendsViewModel?.declineFriendRequest(request)
                                },
                                onCancelFriendRequest = { request ->
                                    friendsViewModel?.cancelFriendRequest(request)
                                },
                                onOpenFriend = { friend ->
                                    navController.navigate(
                                        AppDestination.friendDetailRoute(friend.profileId)
                                    )
                                },
                                onBlockProfile = { profileId ->
                                    friendsViewModel?.blockProfile(profileId)
                                },
                                onUnblockProfile = { profile ->
                                    friendsViewModel?.unblockProfile(profile)
                                },
                                onUpdatePrivacy = { privacy, shareWorkoutDetails ->
                                    friendsViewModel?.updatePrivacy(
                                        privacy,
                                        shareWorkoutDetails
                                    )
                                },
                                onAcceptWorkoutInvite = { invite ->
                                    if (!canAcceptSocialWorkoutInvite(activeWorkout != null)) {
                                        coroutineScope.launch {
                                            snackbarHostState.showSnackbar(
                                                applicationContext.getString(
                                                    R.string.workout_invite_active_blocked
                                                )
                                            )
                                        }
                                    } else {
                                        friendsViewModel?.acceptWorkoutInvite(invite)
                                    }
                                },
                                onDeclineWorkoutInvite = { invite ->
                                    friendsViewModel?.declineWorkoutInvite(invite)
                                },
                                onReuseWorkoutInvite = { invite ->
                                    if (!canAcceptSocialWorkoutInvite(activeWorkout != null)) {
                                        coroutineScope.launch {
                                            snackbarHostState.showSnackbar(
                                                applicationContext.getString(
                                                    R.string.workout_invite_active_blocked
                                                )
                                            )
                                        }
                                    } else {
                                        friendsViewModel?.reuseAcceptedWorkoutInvite(invite)
                                    }
                                },
                                onCancelWorkoutInvite = { invite ->
                                    friendsViewModel?.cancelWorkoutInvite(
                                        invite.inviteId,
                                        invite.inviteRevision
                                    )
                                },
                                onLoadMoreWorkoutInvites = {
                                    friendsViewModel?.loadMoreWorkoutInvites()
                                },
                                onClearFriendsMessages = {
                                    friendsViewModel?.clearMessages()
                                },
                                onAcceptLiveInvitation = { invitation ->
                                    if (activeWorkout == null) {
                                        liveWorkoutViewModel?.acceptInvitation(invitation)
                                    } else {
                                        coroutineScope.launch {
                                            snackbarHostState.showSnackbar(
                                                applicationContext.getString(
                                                    R.string.live_workout_active_blocked
                                                )
                                            )
                                        }
                                    }
                                },
                                onDeclineLiveInvitation = { invitation ->
                                    liveWorkoutViewModel?.declineInvitation(invitation)
                                },
                                onCloseLiveRoom = { room ->
                                    liveWorkoutViewModel?.cancelOrLeaveRoom(room)
                                },
                                onOpenLiveRoom = { room ->
                                    if (activeWorkout != null) {
                                        navController.navigate(AppDestination.ActiveWorkout.route) {
                                            launchSingleTop = true
                                        }
                                    } else {
                                        liveWorkoutViewModel?.refreshRoom(room.roomId)
                                    }
                                },
                                onClearLiveMessages = {
                                    liveWorkoutViewModel?.clearMessages()
                                },
                                focusedSocialPush = focusedSocialPush,
                                focusedLiveRoomId = focusedLivePushRoomId,
                                cloudSyncStatus = cloudSyncStatus,
                                onSyncNow = {
                                    cloudSession?.let { session ->
                                        updateCloudSyncPhase(session, CloudSyncPhase.Checking)
                                        cloudSyncRetryMode = CloudSyncRetryMode.Pull
                                        cloudSyncRetryVersion += 1
                                    }
                                },
                                cloudSyncChoiceRequired =
                                    cloudSyncConflict != null ||
                                        authState.message?.resourceId ==
                                            R.string.cloud_sync_conflict,
                                cloudSyncChoiceReady = cloudSyncConflict != null,
                                onReviewCloudSync = {
                                    if (cloudSyncConflict != null) {
                                        showCloudSyncConflictDialog = true
                                    } else {
                                        cloudSyncRetryMode = CloudSyncRetryMode.Pull
                                        cloudSyncRetryVersion += 1
                                    }
                                },
                                onExportBackup = profileViewModel::exportBackup,
                                onExportDiagnostics = profileViewModel::exportDiagnostics,
                                onClearBackup = profileViewModel::clearBackupJson,
                                onOpenImport = profileViewModel::openImport,
                                onShowTutorial = {
                                    if (canRequestTutorialReplay(
                                            authenticationInProgress = authState.isLoading ||
                                                authState.needsPasswordUpdate,
                                            hasPendingExternalTarget =
                                                tutorialHasPendingExternalTarget,
                                            hasActiveWorkout = activeWorkout != null,
                                            hasLiveReservationOrRoom =
                                                tutorialHasLiveReservationOrRoom,
                                            hasBlockingDialog = tutorialHasBlockingDialog,
                                            accountTransitionInProgress =
                                                tutorialAccountTransitionInProgress
                                        )
                                    ) {
                                        tutorialMode = null
                                        tutorialAccountBinding = null
                                        tutorialReplayRequested = true
                                        navController.navigate(AppDestination.Workouts.route) {
                                            popUpTo(navController.graph.startDestinationId) {
                                                saveState = false
                                            }
                                            launchSingleTop = true
                                            restoreState = false
                                        }
                                    } else {
                                        coroutineScope.launch {
                                            snackbarHostState.showSnackbar(
                                                applicationContext.getString(
                                                    R.string.tutorial_replay_unavailable
                                                )
                                            )
                                        }
                                    }
                                },
                                onCloseImport = profileViewModel::closeImport,
                                onImportJsonChange = profileViewModel::updateImportJson,
                                onImportBackup = profileViewModel::importBackup,
                                onLogout = {
                                    if (accountActionsEnabled(
                                            authLoading = authState.isLoading,
                                            deletionInProgress = accountDeletionInProgress
                                        )
                                    ) {
                                        profileViewModel.logout()
                                    }
                                },
                                isAccountActionLoading = !accountActionsEnabled(
                                    authLoading = authState.isLoading,
                                    deletionInProgress = accountDeletionInProgress
                                ),
                                passwordReauthenticationRequired =
                                    passwordReauthenticationRequired,
                                passwordChangeSuccessVersion =
                                    passwordChangeSuccessVersion,
                                onChangePassword = changePassword@ {
                                        currentPassword,
                                        newPassword,
                                        nonce ->
                                    if (!accountActionsEnabled(
                                            authLoading = authState.isLoading,
                                            deletionInProgress = accountDeletionInProgress
                                        )
                                    ) {
                                        return@changePassword
                                    }
                                    val capturedSession = authManager.authState.value.session
                                        as? AccountSession.Cloud ?: return@changePassword
                                    coroutineScope.launch {
                                        authManager.setLoading(true)
                                        runCatching {
                                            authManager.changePassword(
                                                currentPassword = currentPassword,
                                                newPassword = newPassword,
                                                nonce = nonce
                                            )
                                            passwordReauthenticationRequired = false
                                            passwordChangeSuccessVersion += 1L
                                        }.onFailure { throwable ->
                                            if (activeCloudSessionFor(
                                                    authManager.authState.value.session,
                                                    capturedSession
                                                ) != null
                                            ) {
                                                if (throwable is
                                                    PasswordReauthenticationRequiredException
                                                ) {
                                                    passwordReauthenticationRequired = true
                                                    authManager.setMessage(
                                                        LocalizedText(
                                                            R.string
                                                                .account_password_verification_code_sent
                                                        ),
                                                        isError = false
                                                    )
                                                } else {
                                                    authManager.setMessage(
                                                        authErrorText(
                                                            throwable,
                                                            R.string
                                                                .account_change_password_failed
                                                        )
                                                    )
                                                }
                                            }
                                        }
                                    }
                                },
                                onDeleteCloudAccount = deleteAccount@ {
                                    if (!accountActionsEnabled(
                                            authLoading = authState.isLoading,
                                            deletionInProgress = accountDeletionInProgress
                                        )
                                    ) {
                                        return@deleteAccount
                                    }
                                    val capturedSession = authManager.authState.value.session
                                        as? AccountSession.Cloud ?: return@deleteAccount
                                    val capturedRepository = repository
                                    accountDeletionInProgress = true
                                    authManager.setLoading(true)
                                    accountDeletionScope.launch {
                                        runCatching {
                                            withContext(NonCancellable) {
                                                val deletedSession = authManager.deleteCloudAccount(
                                                    capturedSession
                                                )
                                                var cleanupFailures =
                                                    runConfirmedAccountDeletionLocalCleanup(
                                                        clearRoom = {
                                                            capturedRepository.clearAllAccountData()
                                                        },
                                                        clearBaseline = {
                                                            cloudSyncBaselineStore.clear(
                                                                deletedSession.userId
                                                            )
                                                        },
                                                        clearTrainingProfile = {
                                                            applicationContext.gymApplication
                                                                .trainingProfileManager
                                                                .clearAccount(deletedSession)
                                                        },
                                                        clearTrainingGuidance = {
                                                            applicationContext.gymApplication
                                                                .trainingGuidanceManager
                                                                .clearAccount(deletedSession)
                                                        },
                                                        clearSyncStatus = {
                                                            cloudSyncStatusStore.clear(
                                                                deletedSession.userId
                                                            )
                                                        },
                                                        clearCustomMedia = {
                                                            ExerciseMediaStore.clearOwner(
                                                                applicationContext,
                                                                deletedSession.databaseName()
                                                            )
                                                        },
                                                        clearBackupShares = {
                                                            clearPrivateBackupShareArtifacts(
                                                                File(
                                                                    applicationContext.cacheDir,
                                                                    "backup-share"
                                                                ),
                                                                deletedSession.databaseName()
                                                            )
                                                        },
                                                        clearRestTimers = {
                                                            applicationContext.gymApplication
                                                                .restTimerController
                                                                .clearAccount(deletedSession)
                                                        },
                                                        clearLiveState = {
                                                            applicationContext.gymApplication
                                                                .clearCloudAccountLiveState(
                                                                    deletedSession.userId
                                                                )
                                                        },
                                                        clearGarminState = {
                                                            applicationContext.gymApplication
                                                                .garminSyncManager
                                                                .clearCloudAccountLocalState(
                                                                    deletedSession.userId,
                                                                    deletedSession
                                                                        .sessionGeneration
                                                                )
                                                        }
                                                    )
                                                val completion = authManager
                                                    .completeCloudAccountDeletion(deletedSession)
                                                if (shouldRetireCloudAccountDeletionJournal(
                                                        completion,
                                                        cleanupFailures
                                                    )
                                                ) {
                                                    if (!authManager
                                                            .clearPendingCloudAccountDeletion(
                                                                deletedSession
                                                            )
                                                    ) {
                                                        cleanupFailures += 1
                                                    }
                                                } else if (cleanupFailures == 0 &&
                                                    completion.disposition !=
                                                    CloudAccountDeletionSessionDisposition
                                                        .PreserveDifferentSession
                                                ) {
                                                    cleanupFailures += 1
                                                }
                                                if (cleanupFailures > 0 &&
                                                    completion.disposition !=
                                                    CloudAccountDeletionSessionDisposition
                                                        .PreserveDifferentSession
                                                ) {
                                                    authManager.setMessage(
                                                        LocalizedText(
                                                            R.string
                                                                .account_delete_local_cleanup_failed
                                                        )
                                                    )
                                                }
                                            }
                                        }.onFailure { throwable ->
                                            if (activeCloudSessionFor(
                                                    authManager.authState.value.session,
                                                    capturedSession
                                                ) != null
                                            ) {
                                                authManager.setMessage(
                                                    authErrorText(
                                                        throwable,
                                                        R.string.account_delete_failed
                                                    )
                                                )
                                            }
                                        }
                                        accountDeletionInProgress = false
                                    }
                                },
                                localProfileName = (authState.session as? AccountSession.Local)
                                    ?.displayName,
                                onDeleteLocalProfile = deleteLocalProfile@ {
                                    if (!accountActionsEnabled(
                                            authLoading = authState.isLoading,
                                            deletionInProgress = accountDeletionInProgress
                                        )
                                    ) {
                                        return@deleteLocalProfile
                                    }
                                    val capturedSession = authManager.authState.value.session
                                        as? AccountSession.Local ?: return@deleteLocalProfile
                                    accountDeletionInProgress = true
                                    accountDeletionScope.launch {
                                        runCatching {
                                            withContext(NonCancellable) {
                                                applicationContext.gymApplication
                                                    .deleteCurrentLocalProfile(capturedSession)
                                            }
                                        }.onSuccess { completed ->
                                            if (!completed &&
                                                authManager.authState.value.session == null
                                            ) {
                                                authManager.setMessage(
                                                    LocalizedText(
                                                        R.string.local_profile_delete_cleanup_pending
                                                    )
                                                )
                                            }
                                        }.onFailure { throwable ->
                                            val current = authManager.authState.value.session
                                            if (current == capturedSession || current == null) {
                                                authManager.setMessage(
                                                    authErrorText(
                                                        throwable,
                                                        R.string.local_profile_delete_failed
                                                    )
                                                )
                                            }
                                        }
                                        accountDeletionInProgress = false
                                    }
                                },
                                garminDeviceState = applicationContext.gymApplication
                                    .garminSyncManager.deviceUiState.collectAsState().value,
                                onRefreshGarminDevices = {
                                    applicationContext.gymApplication.garminSyncManager
                                        .refreshGarminDevices()
                                },
                                onResetGarminPairing = {
                                    coroutineScope.launch {
                                        applicationContext.gymApplication.garminSyncManager
                                            .resetSecureGarminPairing()
                                    }
                                },
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        composable(
                            route = AppDestination.FriendDetail.route,
                            arguments = listOf(
                                navArgument("profileId") { type = NavType.StringType }
                            )
                        ) { backStackEntry ->
                            val profileId = backStackEntry.arguments?.getString("profileId")
                                .orEmpty()
                            val context = LocalContext.current
                            val socialState = friendsState ?: FriendsUiState(
                                isCloudAccount = cloudSession != null
                            )
                            val friend = socialState.dashboard?.friends
                                ?.firstOrNull { it.profileId == profileId }
                            val savedWorkoutSessions by remember(repository) {
                                repository.observeSessions()
                            }.collectAsState(initial = emptyList())
                            var friendShareBinding by remember(uiIsolationKey, profileId) {
                                mutableStateOf<FriendWorkoutPickerBinding?>(null)
                            }
                            var selectedFriendWorkoutId by remember(uiIsolationKey, profileId) {
                                mutableStateOf<Long?>(null)
                            }
                            var workoutPlanToShare by remember(uiIsolationKey, profileId) {
                                mutableStateOf<SharedWorkoutPlan?>(null)
                            }
                            var workoutInviteSendProfileId by remember(uiIsolationKey, profileId) {
                                mutableStateOf<String?>(null)
                            }
                            var liveWorkoutInviteSendProfileId by remember(
                                uiIsolationKey,
                                profileId
                            ) {
                                mutableStateOf<String?>(null)
                            }
                            val shareWorkoutChooserTitle = stringResource(
                                R.string.action_share_workout
                            )
                            val shareWorkoutFailed = stringResource(
                                R.string.message_share_workout_failed
                            )
                            val workoutInviteSent = stringResource(R.string.workout_invite_sent)
                            val workoutInviteSendFailed = stringResource(
                                R.string.workout_invite_send_failed
                            )
                            val currentFriendShareBinding = if (cloudSession != null && friend != null) {
                                FriendWorkoutPickerBinding(
                                    userId = cloudSession.userId,
                                    sessionGeneration = cloudSession.sessionGeneration,
                                    profileId = friend.profileId,
                                    friendshipId = friend.friendshipId,
                                    friendshipRevision = friend.friendshipRevision
                                )
                            } else {
                                null
                            }
                            val workoutInviteNotice = friendsState?.notice?.asString()
                            val workoutInviteError = friendsState?.error?.asString()
                            val workoutInviteFeedback = workoutInviteSendFeedback(
                                trackedProfileId = workoutInviteSendProfileId,
                                actionsInFlight = friendsState?.actionsInFlight.orEmpty(),
                                hasNotice = workoutInviteNotice != null,
                                hasError = workoutInviteError != null
                            )
                            val liveWorkoutNoticeText = liveWorkoutState.notice?.asString()
                            val liveWorkoutErrorText = liveWorkoutState.error?.asString()

                            LaunchedEffect(profileId, friend?.friendshipRevision) {
                                if (friend != null) friendsViewModel?.openFriend(profileId)
                            }
                            LaunchedEffect(currentFriendShareBinding, friendShareBinding) {
                                if (friendShareBinding != null &&
                                    friendShareBinding != currentFriendShareBinding
                                ) {
                                    friendShareBinding = null
                                    selectedFriendWorkoutId = null
                                    workoutPlanToShare = null
                                    workoutInviteSendProfileId = null
                                    liveWorkoutInviteSendProfileId = null
                                }
                            }
                            LaunchedEffect(
                                workoutInviteFeedback,
                                workoutInviteNotice,
                                workoutInviteError
                            ) {
                                when (workoutInviteFeedback) {
                                    WorkoutInviteSendFeedback.Succeeded -> {
                                        friendShareBinding = null
                                        workoutPlanToShare = null
                                        workoutInviteSendProfileId = null
                                        friendsViewModel?.clearMessages()
                                        snackbarHostState.showSnackbar(
                                            workoutInviteNotice ?: workoutInviteSent
                                        )
                                    }
                                    WorkoutInviteSendFeedback.Failed -> {
                                        workoutInviteSendProfileId = null
                                        friendsViewModel?.clearMessages()
                                        snackbarHostState.showSnackbar(
                                            workoutInviteError ?: workoutInviteSendFailed
                                        )
                                    }
                                    WorkoutInviteSendFeedback.Idle,
                                    WorkoutInviteSendFeedback.Sending -> Unit
                                }
                            }
                            LaunchedEffect(
                                liveWorkoutInviteSendProfileId,
                                liveWorkoutState.actionsInFlight,
                                liveWorkoutNoticeText,
                                liveWorkoutErrorText
                            ) {
                                val trackedProfileId = liveWorkoutInviteSendProfileId
                                    ?: return@LaunchedEffect
                                if ("send-$trackedProfileId" in liveWorkoutState.actionsInFlight) {
                                    return@LaunchedEffect
                                }
                                val message = liveWorkoutNoticeText ?: liveWorkoutErrorText
                                    ?: return@LaunchedEffect
                                if (liveWorkoutNoticeText != null) {
                                    friendShareBinding = null
                                    workoutPlanToShare = null
                                }
                                liveWorkoutInviteSendProfileId = null
                                snackbarHostState.showSnackbar(message)
                                liveWorkoutViewModel?.clearMessages()
                            }
                            DisposableEffect(profileId) {
                                onDispose { friendsViewModel?.closeFriend() }
                            }

                            FriendDetailScreen(
                                friend = friend,
                                details = socialState.selectedFriendDetails.takeIf {
                                    socialState.selectedProfileId == profileId
                                },
                                friendWorkouts = socialState.friendWorkouts.takeIf {
                                    socialState.selectedProfileId == profileId
                                }.orEmpty(),
                                friendWorkoutActivityRevision =
                                    socialState.friendWorkoutActivityRevision.takeIf {
                                        socialState.selectedProfileId == profileId
                                    },
                                friendWorkoutDetailsAvailable =
                                    socialState.selectedProfileId == profileId &&
                                        socialState.friendWorkoutDetailsAvailable,
                                isLoading = socialState.isDetailsLoading,
                                error = socialState.error,
                                actionInFlight = friend?.let {
                                    "friend-${it.friendshipId}" in socialState.actionsInFlight ||
                                        "profile-${it.profileId}" in socialState.actionsInFlight
                                } == true,
                                onRetry = { friendsViewModel?.openFriend(profileId) },
                                onChooseWorkout = { target ->
                                    val binding = currentFriendShareBinding
                                    if (binding != null &&
                                        target.profileId == binding.profileId &&
                                        target.friendshipId == binding.friendshipId &&
                                        target.friendshipRevision == binding.friendshipRevision &&
                                        cloudSession != null &&
                                        authManager.isLiveSessionActive(cloudSession)
                                    ) {
                                        friendShareBinding = binding
                                        selectedFriendWorkoutId = null
                                        workoutPlanToShare = null
                                    } else {
                                        coroutineScope.launch {
                                            snackbarHostState.showSnackbar(shareWorkoutFailed)
                                        }
                                    }
                                },
                                onBuildLiveWorkout = {
                                    when {
                                        activeWorkout != null -> coroutineScope.launch {
                                            snackbarHostState.showSnackbar(
                                                applicationContext.getString(
                                                    R.string.live_workout_active_blocked
                                                )
                                            )
                                        }
                                        currentFriendShareBinding == null || friend == null ->
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(shareWorkoutFailed)
                                            }
                                        else -> {
                                            setLiveWorkoutDraftTarget(LiveWorkoutDraftTarget(
                                                binding = currentFriendShareBinding,
                                                displayName = friend.displayName,
                                                draftBindingId = UUID.randomUUID().toString()
                                            ))
                                            preferredShareFriendProfileId = profileId
                                            navController.navigate(AppDestination.AddWorkout.route) {
                                                launchSingleTop = true
                                            }
                                        }
                                    }
                                },
                                onRemove = { target ->
                                    friendsViewModel?.removeFriend(target)
                                    navController.popBackStack()
                                },
                                onBlock = { target ->
                                    friendsViewModel?.blockProfile(target.profileId)
                                    navController.popBackStack()
                                },
                                modifier = Modifier.fillMaxSize()
                            )

                            friendShareBinding
                                ?.takeIf { workoutPlanToShare == null }
                                ?.let { binding ->
                                    FriendWorkoutPickerSheet(
                                        friendName = friend?.displayName.orEmpty(),
                                        sessions = savedWorkoutSessions,
                                        inFlightSessionId = selectedFriendWorkoutId,
                                        onSelect = pickerSelect@ { sessionSummary ->
                                            if (selectedFriendWorkoutId != null) {
                                                return@pickerSelect
                                            }
                                            val expectedSession = cloudSession
                                            val socialViewModel = friendsViewModel
                                            val currentFriend = socialViewModel
                                                ?.uiState
                                                ?.value
                                                ?.dashboard
                                                ?.friends
                                                ?.firstOrNull {
                                                    it.profileId == binding.profileId
                                                }
                                            if (expectedSession == null ||
                                                socialViewModel == null ||
                                                !authManager.isLiveSessionActive(expectedSession) ||
                                                !isFriendWorkoutPickerBindingCurrent(
                                                    binding = binding,
                                                    activeSession = authManager.authState.value.session,
                                                    currentProfileId = currentFriend?.profileId,
                                                    currentFriendshipId = currentFriend
                                                        ?.friendshipId,
                                                    currentFriendshipRevision = currentFriend
                                                        ?.friendshipRevision
                                                )
                                            ) {
                                                friendShareBinding = null
                                                workoutPlanToShare = null
                                                coroutineScope.launch {
                                                    snackbarHostState.showSnackbar(
                                                        shareWorkoutFailed
                                                    )
                                                }
                                                return@pickerSelect
                                            }
                                            selectedFriendWorkoutId = sessionSummary.session.id
                                            coroutineScope.launch {
                                                try {
                                                    val details = repository.getWorkoutTemplate(
                                                        sessionSummary.session.id
                                                    ) ?: error("Saved workout is unavailable.")
                                                    val plan = SharedWorkoutLink.planFromSession(
                                                        details
                                                    )
                                                    val latestFriend = socialViewModel
                                                        .uiState
                                                        .value
                                                        .dashboard
                                                        ?.friends
                                                        ?.firstOrNull {
                                                            it.profileId == binding.profileId
                                                        }
                                                    check(
                                                        authManager.isLiveSessionActive(
                                                            expectedSession
                                                        )
                                                    )
                                                    check(
                                                        isFriendWorkoutPickerBindingCurrent(
                                                            binding = binding,
                                                            activeSession = authManager
                                                                .authState
                                                                .value
                                                                .session,
                                                            currentProfileId = latestFriend
                                                                ?.profileId,
                                                            currentFriendshipId = latestFriend
                                                                ?.friendshipId,
                                                            currentFriendshipRevision = latestFriend
                                                                ?.friendshipRevision
                                                        )
                                                    )
                                                    if (friendShareBinding == binding) {
                                                        workoutPlanToShare = plan
                                                    }
                                                } catch (cancelled: CancellationException) {
                                                    throw cancelled
                                                } catch (_: Throwable) {
                                                    if (friendShareBinding == binding) {
                                                        friendShareBinding = null
                                                        workoutPlanToShare = null
                                                    }
                                                    if (isSameCloudSessionGeneration(
                                                            expectedSession,
                                                            authManager.authState.value.session
                                                        )
                                                    ) {
                                                        snackbarHostState.showSnackbar(
                                                            shareWorkoutFailed
                                                        )
                                                    }
                                                } finally {
                                                    if (friendShareBinding == binding) {
                                                        selectedFriendWorkoutId = null
                                                    }
                                                }
                                            }
                                        },
                                        onDismiss = {
                                            friendShareBinding = null
                                            selectedFriendWorkoutId = null
                                        }
                                    )
                                }

                            workoutPlanToShare?.let { plan ->
                                val binding = friendShareBinding ?: return@let
                                WorkoutShareSheet(
                                    friends = listOfNotNull(friend),
                                    preferredFriendProfileId = binding.profileId,
                                    isCloudAccount = cloudSession != null,
                                    actionsInFlight = friendsState?.actionsInFlight.orEmpty(),
                                    liveActionsInFlight = liveWorkoutState.actionsInFlight,
                                    onShareLink = {
                                        val didOpenShareSheet = runCatching {
                                            shareWorkoutUrl(
                                                context = context,
                                                url = SharedWorkoutLink.buildUrl(plan.exercises),
                                                chooserTitle = shareWorkoutChooserTitle
                                            )
                                        }.isSuccess
                                        if (didOpenShareSheet) {
                                            friendShareBinding = null
                                            workoutPlanToShare = null
                                        } else {
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(
                                                    shareWorkoutFailed
                                                )
                                            }
                                        }
                                    },
                                    onSendToFriend = sendCopy@ { target ->
                                        val expectedSession = cloudSession
                                        val socialViewModel = friendsViewModel
                                        val latestFriend = socialViewModel
                                            ?.uiState
                                            ?.value
                                            ?.dashboard
                                            ?.friends
                                            ?.firstOrNull { it.profileId == binding.profileId }
                                        if (expectedSession == null ||
                                            socialViewModel == null ||
                                            target.profileId != binding.profileId ||
                                            target.friendshipId != binding.friendshipId ||
                                            target.friendshipRevision != binding.friendshipRevision ||
                                            !authManager.isLiveSessionActive(expectedSession) ||
                                            !isFriendWorkoutPickerBindingCurrent(
                                                binding,
                                                authManager.authState.value.session,
                                                latestFriend?.profileId,
                                                latestFriend?.friendshipId,
                                                latestFriend?.friendshipRevision
                                            )
                                        ) {
                                            friendShareBinding = null
                                            workoutPlanToShare = null
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(
                                                    shareWorkoutFailed
                                                )
                                            }
                                            return@sendCopy
                                        }
                                        socialViewModel.clearMessages()
                                        workoutInviteSendProfileId = target.profileId
                                        socialViewModel.sendWorkoutInvite(
                                            target.profileId,
                                            plan
                                        )
                                    },
                                    onStartLiveWithFriend = sendLive@ { target ->
                                        val expectedSession = cloudSession
                                        val liveViewModel = liveWorkoutViewModel
                                        val latestFriend = friendsViewModel
                                            ?.uiState
                                            ?.value
                                            ?.dashboard
                                            ?.friends
                                            ?.firstOrNull { it.profileId == binding.profileId }
                                        if (expectedSession == null ||
                                            liveViewModel == null ||
                                            target.profileId != binding.profileId ||
                                            target.friendshipId != binding.friendshipId ||
                                            target.friendshipRevision != binding.friendshipRevision ||
                                            !authManager.isLiveSessionActive(expectedSession) ||
                                            !isFriendWorkoutPickerBindingCurrent(
                                                binding,
                                                authManager.authState.value.session,
                                                latestFriend?.profileId,
                                                latestFriend?.friendshipId,
                                                latestFriend?.friendshipRevision
                                            )
                                        ) {
                                            friendShareBinding = null
                                            workoutPlanToShare = null
                                            coroutineScope.launch {
                                                snackbarHostState.showSnackbar(
                                                    shareWorkoutFailed
                                                )
                                            }
                                            return@sendLive
                                        }
                                        liveViewModel.clearMessages()
                                        liveWorkoutInviteSendProfileId = target.profileId
                                        liveViewModel.sendInvite(target, plan)
                                    },
                                    onDismiss = {
                                        friendShareBinding = null
                                        workoutPlanToShare = null
                                    }
                                )
                            }
                        }
                    }
                }
            }

            val conflict = cloudSyncConflict
            if (showCloudSyncConflictDialog && conflict != null) {
                CloudSyncConflictDialog(
                    cloudVersionAvailable = conflict.remoteDigest != null,
                    cloudVersionNeedsRepair =
                        conflict.remoteExists && conflict.remoteDigest == null,
                    resolving = cloudConflictResolutionInProgress,
                    onKeepDeviceVersion = { resolveCloudSyncConflict(false) },
                    onUseCloudVersion = { resolveCloudSyncConflict(true) },
                    onDismiss = {
                        showCloudSyncConflictDialog = false
                        cloudSyncConflictNoticeVersion += 1
                    }
                )
            }

            pendingSharedWorkout
                ?.takeIf {
                    authState.session != null &&
                        !authState.needsPasswordUpdate &&
                        activeWorkout == null &&
                        approvedSharedWorkoutId != it.id
                }
                ?.let { pending ->
                    SharedWorkoutPreviewDialog(
                        exerciseNames = pending.plan.exercises.map { it.name },
                        exerciseCount = pending.plan.exerciseCount,
                        setCount = pending.plan.setCount,
                        onOpenInApp = {
                            approvedSharedWorkoutId = pending.id
                            setLiveWorkoutDraftTarget(null)
                            navController.navigate(AppDestination.AddWorkout.route) {
                                launchSingleTop = true
                            }
                        },
                        onOpenOnWeb = {
                            val webUrl = SharedWorkoutLink.buildWebFallbackUrl(pending.plan)
                            val opened = runCatching {
                                applicationContext.startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse(webUrl)).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                )
                            }.isSuccess
                            if (opened) {
                                sharedWorkoutInbox.consume(pending.id)
                            } else {
                                coroutineScope.launch {
                                    snackbarHostState.showSnackbar(
                                        message = applicationContext.getString(
                                            R.string.message_shared_workout_open_web_failed
                                        )
                                    )
                                }
                            }
                        },
                        onDismiss = {
                            sharedWorkoutInbox.consume(pending.id)
                        }
                    )
                }

            AnimatedVisibility(
                visible = showIntro,
                enter = fadeIn() + slideInVertically(initialOffsetY = { it / 8 }),
                exit = fadeOut() + scaleOut(targetScale = 1.03f)
            ) {
                AppIntroSplash()
            }
            if (tutorialMode != null) {
                FirstRunTutorialOverlay(
                    stepIndex = tutorialStepIndex,
                    registry = tutorialAnchors,
                    showCompletionSaveError = tutorialCompletionSaveFailed,
                    onBack = {
                        if (tutorialStepIndex > 0) showTutorialStep(tutorialStepIndex - 1)
                    },
                    onNext = {
                        showTutorialStep(tutorialStepIndex + 1)
                    },
                    onSkip = {
                        dismissTutorial(FirstRunTutorialCompletion.Skipped)
                    },
                    onDone = { dismissTutorial(FirstRunTutorialCompletion.Completed) },
                    modifier = Modifier.fillMaxSize()
                )
            }
            }
        }
    }
}

@Composable
private fun SharedWorkoutPreviewDialog(
    exerciseNames: List<String>,
    exerciseCount: Int,
    setCount: Int,
    onOpenInApp: () -> Unit,
    onOpenOnWeb: () -> Unit,
    onDismiss: () -> Unit
) {
    val visibleNames = exerciseNames.take(6).joinToString(separator = " • ")
    val hiddenCount = (exerciseNames.size - 6).coerceAtLeast(0)
    val extra = if (hiddenCount > 0) {
        "\n" + stringResource(R.string.shared_workout_more_exercises, hiddenCount)
    } else {
        ""
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = stringResource(R.string.shared_workout_preview_title)) },
        text = {
            Text(
                text = stringResource(
                    R.string.shared_workout_preview_summary,
                    exerciseCount,
                    setCount
                ) + "\n\n" + visibleNames + extra
            )
        },
        confirmButton = {
            TextButton(onClick = onOpenInApp) {
                Text(text = stringResource(R.string.action_open_shared_workout_in_app))
            }
        },
        dismissButton = {
            TextButton(onClick = onOpenOnWeb) {
                Text(text = stringResource(R.string.action_open_shared_workout_on_web))
            }
        }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppTopBar(
    titleRes: Int,
    isRootDestination: Boolean,
    showRootTitle: Boolean,
    selectedLanguage: AppLanguage,
    interactionsEnabled: Boolean,
    onBack: () -> Unit,
    onLanguageSelected: (AppLanguage) -> Unit,
    scrollBehavior: TopAppBarScrollBehavior
) {
    if (isRootDestination) {
        TopAppBar(
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = Color.Transparent,
                scrolledContainerColor = Color.Transparent,
                titleContentColor = MaterialTheme.colorScheme.onBackground
            ),
            title = {
                if (showRootTitle) {
                    Text(
                        text = stringResource(titleRes),
                        style = MaterialTheme.typography.headlineLarge
                    )
                }
            },
            actions = {
                LanguageSelector(
                    selectedLanguage = selectedLanguage,
                    onLanguageSelected = onLanguageSelected,
                    enabled = interactionsEnabled
                )
            },
            scrollBehavior = scrollBehavior
        )
    } else {
        CenterAlignedTopAppBar(
            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                containerColor = Color.Transparent,
                scrolledContainerColor = Color.Transparent,
                titleContentColor = MaterialTheme.colorScheme.onBackground
            ),
            title = {
                Text(
                    text = stringResource(titleRes),
                    style = MaterialTheme.typography.titleLarge
                )
            },
            navigationIcon = {
                Surface(
                    modifier = Modifier.padding(start = 12.dp),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.84f),
                    shape = MaterialTheme.shapes.small,
                    border = BorderStroke(
                        1.dp,
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.9f)
                    )
                ) {
                    IconButton(onClick = onBack, enabled = interactionsEnabled) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_back)
                        )
                    }
                }
            },
            actions = {
                LanguageSelector(
                    selectedLanguage = selectedLanguage,
                    onLanguageSelected = onLanguageSelected,
                    enabled = interactionsEnabled
                )
            },
            scrollBehavior = scrollBehavior
        )
    }
}

@Composable
private fun LanguageSelector(
    selectedLanguage: AppLanguage,
    onLanguageSelected: (AppLanguage) -> Unit,
    enabled: Boolean = true
) {
    var expanded by remember { mutableStateOf(false) }
    LaunchedEffect(enabled) {
        if (!enabled) expanded = false
    }

    Box(modifier = Modifier.padding(end = 12.dp)) {
        Surface(
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.84f),
            shape = MaterialTheme.shapes.small,
            border = BorderStroke(
                1.dp,
                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.9f)
            )
        ) {
            TextButton(onClick = { expanded = true }, enabled = enabled) {
                Icon(
                    imageVector = Icons.Default.Language,
                    contentDescription = stringResource(R.string.cd_language)
                )
                Text(
                    text = selectedLanguage.name,
                    modifier = Modifier.padding(start = 6.dp)
                )
            }
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.language_english),
                        color = if (selectedLanguage == AppLanguage.EN) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                },
                onClick = {
                    onLanguageSelected(AppLanguage.EN)
                    expanded = false
                }
            )
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.language_ukrainian),
                        color = if (selectedLanguage == AppLanguage.UK) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                },
                onClick = {
                    onLanguageSelected(AppLanguage.UK)
                    expanded = false
                }
            )
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.language_russian),
                        color = if (selectedLanguage == AppLanguage.RU) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        }
                    )
                },
                onClick = {
                    onLanguageSelected(AppLanguage.RU)
                    expanded = false
                }
            )
        }
    }
}
