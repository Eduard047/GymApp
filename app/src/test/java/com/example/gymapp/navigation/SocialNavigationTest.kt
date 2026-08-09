package com.example.gymapp.navigation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
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
}
