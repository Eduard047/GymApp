package com.example.gymapp.ui.screens

import com.example.gymapp.auth.SocialDashboard
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.SocialOutgoingWorkoutInvite
import com.example.gymapp.auth.SocialPrivacy
import com.example.gymapp.auth.SocialSelfProfile
import com.example.gymapp.auth.SocialWorkoutInbox
import com.example.gymapp.auth.SocialWorkoutInviteSummary
import com.example.gymapp.push.PushNavigationTarget
import com.example.gymapp.push.SocialPushType
import com.example.gymapp.ui.viewmodel.FriendsUiState
import com.example.gymapp.ui.viewmodel.LiveWorkoutUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FriendsPushViewportTest {
    @Test
    fun exactOutgoingWorkoutTargetResolvesToItsLowerLazyListSlot() {
        val outgoing = (1..3).map(::outgoingInvite)
        val state = FriendsUiState(
            isCloudAccount = true,
            dashboard = dashboard(friendCount = 12),
            workoutInbox = SocialWorkoutInbox(
                pendingIncomingCount = 0,
                incoming = emptyList(),
                outgoing = outgoing
            )
        )
        val target = PushNavigationTarget.Social(
            type = SocialPushType.WorkoutInviteAccepted,
            objectId = outgoing.last().inviteId,
            objectRevision = outgoing.last().inviteRevision
        )

        assertEquals(
            21,
            friendsFocusedObjectIndex(state, LiveWorkoutUiState(), target, null)
        )
        assertNull(
            friendsFocusedObjectIndex(
                state,
                LiveWorkoutUiState(),
                target.copy(objectId = "wi_${"f".repeat(32)}"),
                null
            )
        )
    }

    private fun dashboard(friendCount: Int) = SocialDashboard(
        self = SocialSelfProfile(
            profileId = "p_${"a".repeat(32)}",
            friendCode = "g_${"b".repeat(12)}",
            displayName = "Self",
            xp = null,
            level = null,
            workouts = null,
            statsAvailable = false,
            progressUpdatedAt = null,
            privacy = SocialPrivacy(false, false, false, false),
            settingsRevision = 1
        ),
        friends = (1..friendCount).map { index ->
            SocialFriend(
                friendshipId = "f_${index.toString(16).padStart(32, '0')}",
                profileId = "p_${index.toString(16).padStart(32, '0')}",
                displayName = "Friend $index",
                xp = null,
                level = null,
                workouts = null,
                progressShared = false,
                statsAvailable = false,
                progressUpdatedAt = null,
                friendshipRevision = 1
            )
        },
        incoming = emptyList(),
        outgoing = emptyList(),
        blocked = emptyList(),
        pendingWorkoutInviteCount = 0
    )

    private fun outgoingInvite(index: Int) = SocialOutgoingWorkoutInvite(
        inviteId = "wi_${index.toString(16).padStart(32, '0')}",
        profileId = "p_${(index + 20).toString(16).padStart(32, '0')}",
        displayName = "Peer $index",
        status = "accepted",
        inviteRevision = 2,
        createdAt = "2026-08-13T10:00:00Z",
        expiresAt = "2026-08-20T10:00:00Z",
        respondedAt = "2026-08-13T11:00:00Z",
        summary = SocialWorkoutInviteSummary(1, 1, listOf("Bench Press"))
    )
}
