package com.example.gymapp.navigation

import com.example.gymapp.R
import com.example.gymapp.auth.SocialDashboard
import com.example.gymapp.auth.SocialFriendRequest
import com.example.gymapp.auth.SocialPrivacy
import com.example.gymapp.auth.SocialSelfProfile
import com.example.gymapp.auth.SocialIncomingWorkoutInvite
import com.example.gymapp.auth.SocialWorkoutInbox
import com.example.gymapp.auth.SocialWorkoutInboxCursor
import com.example.gymapp.auth.SocialWorkoutInviteSummary
import com.example.gymapp.push.PushNavigationTarget
import com.example.gymapp.push.SocialPushType
import com.example.gymapp.ui.viewmodel.FriendsUiState
import com.example.gymapp.util.LocalizedText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PushTargetResolverTest {
    private val friendshipId = "f_${"a".repeat(32)}"

    @Test
    fun resolverWaitsForAuthoritativeGenerationThenFocusesExactRevision() {
        val target = PushNavigationTarget.Social(
            SocialPushType.FriendRequestReceived,
            friendshipId,
            7
        )
        val stale = state(refreshGeneration = 4L, requestRevision = 7)

        assertEquals(
            SocialPushTargetResolution.AwaitingAuthoritativeRefresh,
            resolveSocialPushTarget(target, stale, minimumDashboardGeneration = 5L)
        )
        assertTrue(
            resolveSocialPushTarget(
                target,
                state(refreshGeneration = 5L, requestRevision = 7),
                minimumDashboardGeneration = 5L
            ) is SocialPushTargetResolution.FocusSocialObject
        )
        assertEquals(
            SocialPushTargetResolution.GenericSocialFallback,
            resolveSocialPushTarget(
                target.copy(objectRevision = 8),
                state(refreshGeneration = 5L, requestRevision = 7),
                minimumDashboardGeneration = 5L
            )
        )
    }

    @Test
    fun failedAuthoritativeRefreshFallsBackWithoutAnExistenceOracle() {
        val target = PushNavigationTarget.Social(
            SocialPushType.FriendRequestReceived,
            friendshipId,
            7
        )
        val failed = state(refreshGeneration = 4L, requestRevision = 7).copy(
            error = LocalizedText(R.string.friends_load_failed)
        )

        assertEquals(
            SocialPushTargetResolution.GenericSocialFallback,
            resolveSocialPushTarget(target, failed, minimumDashboardGeneration = 5L)
        )
    }

    @Test
    fun workoutInvitePushKeepsSearchingShortPagesUntilTheBoundedWindowEnds() {
        val target = PushNavigationTarget.Social(
            SocialPushType.WorkoutInviteReceived,
            workoutInviteId(7),
            4
        )
        val firstPage = SocialWorkoutInbox(
            pendingIncomingCount = 14,
            incoming = (20 downTo 15).map(::workoutInvite),
            outgoing = emptyList(),
            nextCursor = SocialWorkoutInboxCursor(
                createdAt = "2026-08-13T10:00:00Z",
                inviteId = workoutInviteId(15),
                pending = true
            )
        )

        assertEquals(
            SocialPushTargetResolution.AwaitingAuthoritativeRefresh,
            resolveSocialPushTarget(
                target,
                FriendsUiState(workoutInbox = firstPage, inboxRefreshGeneration = 1)
            )
        )

        val shortSecondPage = firstPage.copy(
            incoming = (20 downTo 8).map(::workoutInvite),
            nextCursor = SocialWorkoutInboxCursor(
                createdAt = "2026-08-13T10:00:00Z",
                inviteId = workoutInviteId(8),
                pending = true
            ),
            loadedPageCount = 2
        )
        assertEquals(
            SocialPushTargetResolution.AwaitingAuthoritativeRefresh,
            resolveSocialPushTarget(
                target,
                FriendsUiState(workoutInbox = shortSecondPage, inboxRefreshGeneration = 2)
            )
        )

        val exactThirdPage = shortSecondPage.copy(
            incoming = shortSecondPage.incoming + workoutInvite(7, revision = 4),
            nextCursor = null,
            loadedPageCount = 3
        )
        assertTrue(
            resolveSocialPushTarget(
                target,
                FriendsUiState(workoutInbox = exactThirdPage, inboxRefreshGeneration = 3)
            ) is SocialPushTargetResolution.FocusSocialObject
        )

        val missingTarget = target.copy(objectId = workoutInviteId(6))
        assertEquals(
            SocialPushTargetResolution.GenericSocialFallback,
            resolveSocialPushTarget(
                missingTarget,
                FriendsUiState(workoutInbox = exactThirdPage, inboxRefreshGeneration = 3)
            )
        )

        val requestBoundReached = firstPage.copy(loadedPageCount = 20)
        assertEquals(
            SocialPushTargetResolution.GenericSocialFallback,
            resolveSocialPushTarget(
                missingTarget,
                FriendsUiState(workoutInbox = requestBoundReached, inboxRefreshGeneration = 20)
            )
        )
    }

    private fun state(refreshGeneration: Long, requestRevision: Int): FriendsUiState =
        FriendsUiState(
            dashboard = SocialDashboard(
                self = SocialSelfProfile(
                    profileId = "p_${"b".repeat(32)}",
                    friendCode = "g_${"c".repeat(12)}",
                    displayName = "Self",
                    xp = null,
                    level = null,
                    workouts = null,
                    statsAvailable = false,
                    progressUpdatedAt = null,
                    privacy = SocialPrivacy(false, false, false, false),
                    settingsRevision = 1
                ),
                friends = emptyList(),
                incoming = listOf(
                    SocialFriendRequest(
                        friendshipId = friendshipId,
                        profileId = "p_${"d".repeat(32)}",
                        displayName = "Peer",
                        requestedAt = "2026-08-13T00:00:00Z",
                        friendshipRevision = requestRevision
                    )
                ),
                outgoing = emptyList(),
                blocked = emptyList(),
                pendingWorkoutInviteCount = 0
            ),
            dashboardRefreshGeneration = refreshGeneration
        )

    private fun workoutInvite(index: Int, revision: Int = 1) = SocialIncomingWorkoutInvite(
        inviteId = workoutInviteId(index),
        profileId = "p_${index.toString(16).padStart(32, '0')}",
        displayName = "Peer $index",
        status = "pending",
        inviteRevision = revision,
        createdAt = "2026-08-13T10:00:00Z",
        expiresAt = "2026-08-20T10:00:00Z",
        respondedAt = null,
        summary = SocialWorkoutInviteSummary(1, 1, listOf("Bench Press"))
    )

    private fun workoutInviteId(index: Int) =
        "wi_${index.toString(16).padStart(32, '0')}"
}
