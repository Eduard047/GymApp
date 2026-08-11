package com.example.gymapp.navigation

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.push.PushNavigationTarget
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
            pushNavigationDestination(PushNavigationTarget.Social)
        )
        assertEquals(
            AppDestination.Profile,
            pushNavigationDestination(
                PushNavigationTarget.Live("lr_${"a".repeat(32)}")
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
    fun acceptedInviteStaysRecoverableUntilExplicitDraftReplacementSucceeds() {
        assertEquals(false, shouldConsumeAcceptedSocialWorkout(appliedToDraft = false))
        assertEquals(true, shouldConsumeAcceptedSocialWorkout(appliedToDraft = true))
    }

    @Test
    fun friendWorkoutPickerBindingFailsClosedAcrossAccountAndFriendshipChanges() {
        val profileId = "p_${"a".repeat(32)}"
        val binding = FriendWorkoutPickerBinding(
            userId = "user-a",
            sessionGeneration = "generation-a",
            profileId = profileId,
            friendshipRevision = 7
        )

        assertTrue(
            isFriendWorkoutPickerBindingCurrent(
                binding,
                cloudSession(userId = "user-a", generation = "generation-a"),
                profileId,
                7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding,
                cloudSession(userId = "user-a", generation = "generation-b"),
                profileId,
                7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding,
                cloudSession(userId = "user-b", generation = "generation-a"),
                profileId,
                7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding,
                cloudSession(userId = "user-a", generation = "generation-a"),
                "p_${"b".repeat(32)}",
                7
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding,
                cloudSession(userId = "user-a", generation = "generation-a"),
                profileId,
                8
            )
        )
        assertFalse(
            isFriendWorkoutPickerBindingCurrent(
                binding,
                AccountSession.Local("Local"),
                profileId,
                7
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
}
