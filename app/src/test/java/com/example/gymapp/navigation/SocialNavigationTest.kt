package com.example.gymapp.navigation

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.LiveInboxRoom
import com.example.gymapp.auth.LiveProfile
import com.example.gymapp.auth.LiveWorkoutInbox
import com.example.gymapp.auth.LiveWorkoutSummary
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.data.repository.LiveWorkoutDraftSendReceipt
import com.example.gymapp.push.PushNavigationTarget
import com.example.gymapp.push.LivePushKind
import com.example.gymapp.push.SocialPushType
import com.example.gymapp.ui.viewmodel.AddWorkoutUiState
import com.example.gymapp.ui.viewmodel.retainedWorkoutDraftFingerprint
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SocialNavigationTest {
    @Test
    fun profileKeepsLegacyRouteWhileFriendDetailsRequireOpaqueProfileId() {
        val profileId = "p_${"a".repeat(32)}"

        assertEquals("leaderboard", AppDestination.Profile.route)
        assertEquals("friend/$profileId", AppDestination.friendDetailRoute(profileId))
        assertThrows(IllegalArgumentException::class.java) {
            AppDestination.friendDetailRoute("user@example.com")
        }
    }

    @Test
    fun ordinaryProfileToWorkoutsDoesNotRestoreThePoppedProfileEntry() {
        assertTrue(shouldPreserveBottomTabState(AppDestination.Profile))
        assertFalse(shouldPreserveBottomTabState(AppDestination.Workouts))
    }

    @Test
    fun pushOpenedProfileThenWorkoutsUsesTheSameNonRestoringRootPolicy() {
        assertEquals(
            AppDestination.Profile,
            pushNavigationDestination(
                PushNavigationTarget.Social(
                    SocialPushType.FriendRequestReceived,
                    "f_${"b".repeat(32)}",
                    1
                )
            )
        )
        assertEquals(
            AppDestination.Profile,
            pushNavigationDestination(
                PushNavigationTarget.Live(
                    LivePushKind.Started,
                    "lr_${"a".repeat(32)}",
                    2
                )
            )
        )
        assertFalse(shouldPreserveBottomTabState(AppDestination.Workouts))
    }

    @Test
    fun activeWorkoutBlocksInviteAcceptanceBeforeAnyRpcCanRun() {
        assertEquals(false, canAcceptSocialWorkoutInvite(activeWorkoutExists = true))
        assertEquals(true, canAcceptSocialWorkoutInvite(activeWorkoutExists = false))
    }

    @Test
    fun automaticTutorialRunsOnlyOnTheStableUnblockedWorkoutsRoot() {
        fun eligible(
            externalTarget: Boolean = false,
            activeWorkout: Boolean = false,
            liveReservation: Boolean = false,
            blockingDialog: Boolean = false,
            accountTransition: Boolean = false
        ) = canPresentAutomaticTutorial(
            shouldRunForAccount = true,
            hasSession = true,
            isStableWorkoutsRoot = true,
            authenticationInProgress = false,
            introVisible = false,
            hasPendingExternalTarget = externalTarget,
            hasActiveWorkout = activeWorkout,
            hasLiveReservationOrRoom = liveReservation,
            hasBlockingDialog = blockingDialog,
            accountTransitionInProgress = accountTransition
        )

        assertTrue(eligible())
        assertFalse(eligible(externalTarget = true))
        assertFalse(eligible(activeWorkout = true))
        assertFalse(eligible(liveReservation = true))
        assertFalse(eligible(blockingDialog = true))
        assertFalse(eligible(accountTransition = true))
        assertFalse(
            canPresentAutomaticTutorial(
                shouldRunForAccount = true,
                hasSession = true,
                isStableWorkoutsRoot = false,
                authenticationInProgress = false,
                introVisible = false,
                hasPendingExternalTarget = false,
                hasActiveWorkout = false,
                hasLiveReservationOrRoom = false,
                hasBlockingDialog = false,
                accountTransitionInProgress = false
            )
        )
    }

    @Test
    fun acceptedInviteStaysRecoverableUntilExplicitDraftReplacementSucceeds() {
        assertEquals(false, shouldConsumeAcceptedSocialWorkout(appliedToDraft = false))
        assertEquals(true, shouldConsumeAcceptedSocialWorkout(appliedToDraft = true))
    }

    @Test
    fun friendWorkoutPickerBindingFailsClosedAcrossAccountAndFriendshipChanges() {
        val profileId = "p_${"a".repeat(32)}"
        val friendshipId = "f_${"c".repeat(32)}"
        val binding = FriendWorkoutPickerBinding(
            userId = "user-a",
            sessionGeneration = "generation-a",
            profileId = profileId,
            friendshipId = friendshipId,
            friendshipRevision = 7
        )

        assertTrue(
            isFriendWorkoutPickerBindingCurrent(
                binding = binding,
                activeSession = cloudSession(userId = "user-a", generation = "generation-a"),
                currentProfileId = profileId,
                currentFriendshipId = friendshipId,
                currentFriendshipRevision = 7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding = binding,
                activeSession = cloudSession(userId = "user-a", generation = "generation-b"),
                currentProfileId = profileId,
                currentFriendshipId = friendshipId,
                currentFriendshipRevision = 7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding = binding,
                activeSession = cloudSession(userId = "user-b", generation = "generation-a"),
                currentProfileId = profileId,
                currentFriendshipId = friendshipId,
                currentFriendshipRevision = 7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding = binding,
                activeSession = cloudSession(userId = "user-a", generation = "generation-a"),
                currentProfileId = "p_${"b".repeat(32)}",
                currentFriendshipId = friendshipId,
                currentFriendshipRevision = 7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding = binding,
                activeSession = cloudSession(userId = "user-a", generation = "generation-a"),
                currentProfileId = profileId,
                currentFriendshipId = "f_${"d".repeat(32)}",
                currentFriendshipRevision = 7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding = binding,
                activeSession = cloudSession(userId = "user-a", generation = "generation-a"),
                currentProfileId = profileId,
                currentFriendshipId = friendshipId,
                currentFriendshipRevision = 8
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding = binding,
                activeSession = AccountSession.Local("Local"),
                currentProfileId = profileId,
                currentFriendshipId = friendshipId,
                currentFriendshipRevision = 7
            )
        )
    }

    @Test
    fun savedLiveWorkoutTargetRestoresExactBindingAndFailsClosedWhenIncomplete() {
        val target = LiveWorkoutDraftTarget(
            binding = FriendWorkoutPickerBinding(
                userId = "user-a",
                sessionGeneration = "generation-a",
                profileId = "p_${"a".repeat(32)}",
                friendshipId = "f_${"c".repeat(32)}",
                friendshipRevision = 7
            ),
            displayName = "Synthetic friend",
            draftBindingId = "62345678-1234-4123-8123-123456789abc"
        )

        assertEquals(
            target,
            restoreLiveWorkoutDraftTarget(
                hasTarget = true,
                draftBindingId = target.draftBindingId,
                userId = target.binding.userId,
                sessionGeneration = target.binding.sessionGeneration,
                profileId = target.binding.profileId,
                friendshipId = target.binding.friendshipId,
                friendshipRevision = target.binding.friendshipRevision,
                displayName = target.displayName
            )
        )
        assertEquals(
            null,
            restoreLiveWorkoutDraftTarget(
                hasTarget = true,
                draftBindingId = target.draftBindingId,
                userId = target.binding.userId,
                sessionGeneration = target.binding.sessionGeneration,
                profileId = target.binding.profileId,
                friendshipId = null,
                friendshipRevision = target.binding.friendshipRevision,
                displayName = target.displayName
            )
        )
    }

    @Test
    fun cachedFriendCannotAuthorizeLiveSendWhenFreshDashboardBindingChanged() {
        val target = liveTarget()
        val session = cloudSession(userId = "user-a", generation = "generation-a")
        val cachedFriend = socialFriend(
            profileId = target.binding.profileId,
            friendshipId = target.binding.friendshipId,
            friendshipRevision = target.binding.friendshipRevision
        )
        val freshChangedFriend = cachedFriend.copy(
            friendshipId = "f_${"d".repeat(32)}",
            friendshipRevision = target.binding.friendshipRevision + 1
        )

        assertEquals(
            cachedFriend,
            resolveLiveWorkoutFriendFromFreshDashboard(
                target = target,
                activeSession = session,
                freshFriends = listOf(cachedFriend)
            )
        )
        assertEquals(
            null,
            resolveLiveWorkoutFriendFromFreshDashboard(
                target = target,
                activeSession = session,
                freshFriends = listOf(freshChangedFriend)
            )
        )
    }

    @Test
    fun liveSendCompletionRequiresTheSameTargetAndUneditedDraftSnapshot() {
        val target = liveTarget()
        val fingerprint = retainedWorkoutDraftFingerprint(
            AddWorkoutUiState(note = "Original", isDirty = true)
        )
        val snapshot = LiveWorkoutDraftSendSnapshot(target, fingerprint)

        assertTrue(
            liveWorkoutDraftSendStillMatches(
                snapshot = snapshot,
                currentTarget = target,
                currentDraftFingerprint = fingerprint
            )
        )
        assertFalse(
            liveWorkoutDraftSendStillMatches(
                snapshot = snapshot,
                currentTarget = target,
                currentDraftFingerprint = fingerprint.copy(note = "Late edit")
            )
        )
        assertTrue(
            liveWorkoutDraftSendStillMatches(
                snapshot = snapshot,
                currentTarget = target.copy(displayName = "Changed friend"),
                currentDraftFingerprint = fingerprint
            )
        )
        assertTrue(
            shouldClearSuccessfulLiveWorkoutDraftTarget(
                snapshot = snapshot,
                currentTarget = target
            )
        )
        assertTrue(
            shouldClearSuccessfulLiveWorkoutDraftTarget(
                snapshot = snapshot,
                currentTarget = target.copy(displayName = "Changed friend")
            )
        )
        assertFalse(
            shouldClearSuccessfulLiveWorkoutDraftTarget(
                snapshot = snapshot,
                currentTarget = target.copy(
                    binding = target.binding.copy(friendshipRevision = 8)
                )
            )
        )
        assertFalse(
            shouldClearSuccessfulLiveWorkoutDraftTarget(
                snapshot = snapshot,
                currentTarget = target.copy(
                    draftBindingId = "72345678-1234-4123-8123-123456789abc"
                )
            )
        )
    }

    @Test
    fun confirmedLiveDraftReceiptConsumesOnlyExactUnchangedRestartState() {
        val receipt = confirmedDraftSendReceipt()
        val target = confirmedDraftTarget()
        val inbox = LiveWorkoutInbox(
            invitations = emptyList(),
            rooms = listOf(confirmedDraftRoom())
        )

        assertEquals(
            LiveWorkoutDraftReceiptAction.ConsumeUnchangedDraft,
            confirmedLiveWorkoutDraftReceiptAction(
                receipt,
                inbox,
                hasSavedTarget = true,
                target = target,
                currentDraftDigest = receipt.draftFingerprint
            )
        )
        assertEquals(
            LiveWorkoutDraftReceiptAction.UnbindAndPreserveChangedDraft,
            confirmedLiveWorkoutDraftReceiptAction(
                receipt,
                inbox,
                hasSavedTarget = true,
                target = target,
                currentDraftDigest = "b".repeat(64)
            )
        )
        assertEquals(
            LiveWorkoutDraftReceiptAction.AwaitAuthoritativeRoom,
            confirmedLiveWorkoutDraftReceiptAction(
                receipt.copy(roomId = null),
                inbox,
                hasSavedTarget = true,
                target = target,
                currentDraftDigest = receipt.draftFingerprint
            )
        )
        assertEquals(
            LiveWorkoutDraftReceiptAction.AwaitAuthoritativeRoom,
            confirmedLiveWorkoutDraftReceiptAction(
                receipt,
                inbox,
                hasSavedTarget = true,
                target = null,
                currentDraftDigest = receipt.draftFingerprint
            )
        )
    }

    @Test
    fun confirmedOldReceiptNeverConsumesAChangedOrNewerLiveBinding() {
        val receipt = confirmedDraftSendReceipt()
        val inbox = LiveWorkoutInbox(emptyList(), listOf(confirmedDraftRoom()))

        assertEquals(
            LiveWorkoutDraftReceiptAction.ClearReceiptOnly,
            confirmedLiveWorkoutDraftReceiptAction(
                receipt,
                inbox,
                hasSavedTarget = true,
                target = confirmedDraftTarget().copy(
                    draftBindingId = "72345678-1234-4123-8123-123456789abc"
                ),
                currentDraftDigest = receipt.draftFingerprint
            )
        )
        assertEquals(
            LiveWorkoutDraftReceiptAction.ClearReceiptOnly,
            confirmedLiveWorkoutDraftReceiptAction(
                receipt,
                inbox,
                hasSavedTarget = false,
                target = null,
                currentDraftDigest = receipt.draftFingerprint
            )
        )
        assertEquals(
            LiveWorkoutDraftReceiptAction.AwaitAuthoritativeRoom,
            confirmedLiveWorkoutDraftReceiptAction(
                receipt,
                LiveWorkoutInbox(emptyList(), emptyList()),
                hasSavedTarget = true,
                target = confirmedDraftTarget(),
                currentDraftDigest = receipt.draftFingerprint
            )
        )
    }

    @Test
    fun todayStartAndEditReentryResumeExistingEditorAndPreserveExactLiveTarget() {
        assertFalse(
            shouldResumeRetainedWorkoutDraft(
                hasEditorDraft = false,
                hasLiveTarget = false
            )
        )
        assertTrue(
            shouldResumeRetainedWorkoutDraft(
                hasEditorDraft = true,
                hasLiveTarget = false
            )
        )
        assertTrue(
            shouldResumeRetainedWorkoutDraft(
                hasEditorDraft = false,
                hasLiveTarget = true
            )
        )
    }

    @Test
    fun workoutInviteBadgeUsesFreshInboxCountWithDashboardFallback() {
        assertEquals(3, pendingSocialWorkoutInviteBadgeCount(inboxCount = 3, dashboardCount = 5))
        assertEquals(5, pendingSocialWorkoutInviteBadgeCount(inboxCount = null, dashboardCount = 5))
        assertEquals(0, pendingSocialWorkoutInviteBadgeCount(inboxCount = null, dashboardCount = null))
    }

    @Test
    fun addWorkoutShareWaitsForRpcOutcomeBeforeClosingOrReportingSuccess() {
        val profileId = "p_${"a".repeat(32)}"

        assertEquals(
            WorkoutInviteSendFeedback.Sending,
            workoutInviteSendFeedback(
                trackedProfileId = profileId,
                actionsInFlight = setOf("send-workout-$profileId"),
                hasNotice = false,
                hasError = false
            )
        )
        assertEquals(
            WorkoutInviteSendFeedback.Succeeded,
            workoutInviteSendFeedback(profileId, emptySet(), hasNotice = true, hasError = false)
        )
        assertEquals(
            WorkoutInviteSendFeedback.Failed,
            workoutInviteSendFeedback(profileId, emptySet(), hasNotice = false, hasError = true)
        )
        assertEquals(
            WorkoutInviteSendFeedback.Idle,
            workoutInviteSendFeedback(null, emptySet(), hasNotice = true, hasError = true)
        )
    }

    private fun cloudSession(userId: String, generation: String) = AccountSession.Cloud(
        userId = userId,
        email = "$userId@example.test",
        displayName = "Synthetic",
        accessToken = "synthetic-access-token",
        refreshToken = null,
        sessionGeneration = generation
    )

    private fun liveTarget() = LiveWorkoutDraftTarget(
        binding = FriendWorkoutPickerBinding(
            userId = "user-a",
            sessionGeneration = "generation-a",
            profileId = "p_${"a".repeat(32)}",
            friendshipId = "f_${"c".repeat(32)}",
            friendshipRevision = 7
        ),
        displayName = "Synthetic friend",
        draftBindingId = "62345678-1234-4123-8123-123456789abc"
    )

    private fun confirmedDraftTarget() = LiveWorkoutDraftTarget(
        binding = FriendWorkoutPickerBinding(
            userId = "42345678-1234-4123-8123-123456789abc",
            sessionGeneration = "52345678-1234-4123-8123-123456789abc",
            profileId = "p_0123456789abcdef0123456789abcdef",
            friendshipId = "f_0123456789abcdef0123456789abcdef",
            friendshipRevision = 7
        ),
        displayName = "Synthetic friend",
        draftBindingId = "62345678-1234-4123-8123-123456789abc"
    )

    private fun confirmedDraftSendReceipt() = LiveWorkoutDraftSendReceipt(
        userId = "42345678-1234-4123-8123-123456789abc",
        sessionGeneration = "52345678-1234-4123-8123-123456789abc",
        draftBindingId = "62345678-1234-4123-8123-123456789abc",
        recipientProfileId = "p_0123456789abcdef0123456789abcdef",
        recipientFriendshipId = "f_0123456789abcdef0123456789abcdef",
        recipientFriendshipRevision = 7,
        operationId = "12345678-1234-4123-8123-123456789abc",
        roomId = "lr_0123456789abcdef0123456789abcdef",
        draftFingerprint = "a".repeat(64),
        createdAt = 1_786_330_800_000L,
        expiresAt = 1_786_417_200_000L
    )

    private fun confirmedDraftRoom() = LiveInboxRoom(
        roomId = "lr_0123456789abcdef0123456789abcdef",
        status = "waiting",
        roomRevision = 2,
        role = "owner",
        memberState = "joined",
        membershipRevision = 1,
        createdAt = "2026-08-15T10:00:00Z",
        startedAt = null,
        activeExpiresAt = "2026-08-22T10:00:00Z",
        summary = LiveWorkoutSummary(1, 1, listOf("Bench press")),
        peer = LiveProfile("p_0123456789abcdef0123456789abcdef", "Synthetic friend")
    )

    private fun socialFriend(
        profileId: String,
        friendshipId: String,
        friendshipRevision: Int
    ) = SocialFriend(
        friendshipId = friendshipId,
        profileId = profileId,
        displayName = "Synthetic friend",
        xp = null,
        level = null,
        workouts = null,
        progressShared = false,
        statsAvailable = false,
        progressUpdatedAt = null,
        friendshipRevision = friendshipRevision
    )
}
