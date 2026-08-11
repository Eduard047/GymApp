package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.SocialExerciseRecord
import com.example.gymapp.auth.SocialDashboard
import com.example.gymapp.auth.SocialFriendDetailProfile
import com.example.gymapp.auth.SocialFriendDetails
import com.example.gymapp.auth.SocialMyFriendCode
import com.example.gymapp.auth.SocialPrivacy
import com.example.gymapp.auth.SocialSelfProfile
import com.example.gymapp.auth.SocialSharing
import com.example.gymapp.auth.SocialWorkoutInbox
import com.example.gymapp.data.repository.SharedWorkoutExercise
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.SharedWorkoutSet
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendsViewModelStateTest {
    @Test
    fun shortFriendCodeUsesTheSeparateRpcWithLegacyDashboardFallback() {
        val dashboard = checkNotNull(loadedSocialState().dashboard)

        assertEquals(
            "g_a1b2c3d4e5f6",
            resolvedSocialFriendCode(
                dashboard,
                SocialMyFriendCode(version = 1, friendCode = "g_a1b2c3d4e5f6")
            )
        )
        assertEquals(dashboard.self.friendCode, resolvedSocialFriendCode(dashboard, null))
    }

    @Test
    fun dashboardRefreshRejectsAccountSwitchesAndLateResults() {
        val expected = cloudSession(userId = "user-a", generation = "generation-a")

        assertTrue(
            shouldApplySocialDashboardRefresh(
                expected,
                cloudSession(userId = "user-a", generation = "generation-a"),
                requestVersion = 4,
                latestRequestVersion = 4
            )
        )
        assertFalse(
            shouldApplySocialDashboardRefresh(
                expected,
                cloudSession(userId = "user-a", generation = "generation-b"),
                requestVersion = 4,
                latestRequestVersion = 4
            )
        )
        assertFalse(
            shouldApplySocialDashboardRefresh(
                expected,
                cloudSession(userId = "user-b", generation = "generation-a"),
                requestVersion = 4,
                latestRequestVersion = 4
            )
        )
        assertFalse(
            shouldApplySocialDashboardRefresh(
                expected,
                cloudSession(userId = "user-a", generation = "generation-a"),
                requestVersion = 3,
                latestRequestVersion = 4
            )
        )
        assertFalse(
            shouldApplySocialDashboardRefresh(
                expected,
                AccountSession.Local("Local"),
                requestVersion = 4,
                latestRequestVersion = 4
            )
        )
    }

    @Test
    fun foregroundRefreshDropsPreviouslySharedDetailsBeforePrivacyCanTurnFalse() {
        val profileId = "p_${"a".repeat(32)}"
        val previouslyShared = SocialFriendDetails(
            friend = SocialFriendDetailProfile(
                profileId = profileId,
                displayName = "Training Friend",
                xp = 800,
                level = 4,
                workouts = 12,
                progressShared = true,
                statsAvailable = true,
                progressUpdatedAt = "2026-08-09T10:00:00Z"
            ),
            sharing = SocialSharing(progress = true, recentWorkouts = true, records = true),
            activityUpdatedAt = "2026-08-09T10:00:00Z",
            recentWorkouts = emptyList(),
            exerciseRecords = listOf(
                SocialExerciseRecord(
                    catalogKey = "bench_press",
                    name = "Bench Press",
                    bestWeightKg = 100.0,
                    bestReps = 8,
                    workoutCount = 3,
                    lastWorkoutDay = "2026-08-09"
                )
            ),
            integrity = "self_reported"
        )

        val refreshed = invalidateSelectedFriendDetailsForRefresh(
            FriendsUiState(
                isCloudAccount = true,
                selectedProfileId = profileId,
                selectedFriendDetails = previouslyShared
            )
        )

        assertNull(refreshed.selectedFriendDetails)
        assertTrue(refreshed.isDetailsLoading)
    }

    @Test
    fun removeFriendCommitWithLostResponseCannotRestorePrivateSocialData() {
        assertCommitResponseLossFailsClosed(SocialRevocationKind.RemoveFriend)
    }

    @Test
    fun blockProfileCommitWithLostResponseCannotRestorePrivateSocialData() {
        assertCommitResponseLossFailsClosed(SocialRevocationKind.BlockProfile)
    }

    private fun assertCommitResponseLossFailsClosed(kind: SocialRevocationKind) {
        val retainedRequestIds = mutableMapOf(
            "p_${"b".repeat(32)}:payload-digest" to
                "123e4567-e89b-42d3-a456-426614174000"
        )
        var state = loadedSocialState()
        val events = mutableListOf<String>()

        state = invalidateSocialAccessAfterRevocation(state, kind)
        events += "invalidated"
        val response = runCatching {
            events += "server-committed"
            throw IOException("response lost after commit")
        }

        assertTrue(response.isFailure)
        assertEquals(listOf("invalidated", "server-committed"), events)
        assertNull(state.dashboard)
        assertNull(state.myFriendCode)
        assertNull(state.workoutInbox)
        assertNull(state.selectedProfileId)
        assertNull(state.selectedFriendDetails)
        assertNull(state.acceptedWorkout)
        assertEquals(1, retainedRequestIds.size)
    }

    private fun loadedSocialState(): FriendsUiState {
        val profileId = "p_${"a".repeat(32)}"
        val details = sharedDetails(profileId)
        return FriendsUiState(
            isCloudAccount = true,
            dashboard = SocialDashboard(
                self = SocialSelfProfile(
                    profileId = "p_${"0".repeat(32)}",
                    friendCode = "p_${"0".repeat(32)}",
                    displayName = "Current User",
                    xp = 100,
                    level = 2,
                    workouts = 3,
                    statsAvailable = true,
                    progressUpdatedAt = "2026-08-09T10:00:00Z",
                    privacy = SocialPrivacy(true, true, true, true),
                    settingsRevision = 1
                ),
                friends = emptyList(),
                incoming = emptyList(),
                outgoing = emptyList(),
                blocked = emptyList(),
                pendingWorkoutInviteCount = 0
            ),
            myFriendCode = "g_a1b2c3d4e5f6",
            workoutInbox = SocialWorkoutInbox(0, emptyList(), emptyList()),
            selectedProfileId = profileId,
            selectedFriendDetails = details,
            acceptedWorkout = AcceptedSocialWorkout(
                inviteId = "wi_${"c".repeat(32)}",
                plan = SharedWorkoutPlan(
                    listOf(
                        SharedWorkoutExercise(
                            catalogKey = "bench_press",
                            name = "Bench Press",
                            sets = listOf(SharedWorkoutSet(80.0, 8))
                        )
                    )
                )
            )
        )
    }

    private fun sharedDetails(profileId: String): SocialFriendDetails = SocialFriendDetails(
        friend = SocialFriendDetailProfile(
            profileId = profileId,
            displayName = "Training Friend",
            xp = 800,
            level = 4,
            workouts = 12,
            progressShared = true,
            statsAvailable = true,
            progressUpdatedAt = "2026-08-09T10:00:00Z"
        ),
        sharing = SocialSharing(progress = true, recentWorkouts = true, records = true),
        activityUpdatedAt = "2026-08-09T10:00:00Z",
        recentWorkouts = emptyList(),
        exerciseRecords = listOf(
            SocialExerciseRecord(
                catalogKey = "bench_press",
                name = "Bench Press",
                bestWeightKg = 100.0,
                bestReps = 8,
                workoutCount = 3,
                lastWorkoutDay = "2026-08-09"
            )
        ),
        integrity = "self_reported"
    )

    private fun cloudSession(userId: String, generation: String) = AccountSession.Cloud(
        userId = userId,
        email = "$userId@example.test",
        displayName = "Synthetic",
        accessToken = "synthetic-access-token",
        refreshToken = null,
        sessionGeneration = generation
    )
}
