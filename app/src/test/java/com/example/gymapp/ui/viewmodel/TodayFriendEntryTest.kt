package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Test

class TodayFriendEntryTest {
    private fun state(cloud: Boolean = true, friends: Int = 2, invites: Int = 0, live: Boolean = false) =
        TodayFriendEntryState.from(cloud, friends, invites, live)

    @Test
    fun localAccountsOpenTheAccountToSignIn() {
        assertEquals(TodayFriendEntryState.NeedsCloudAccount, state(cloud = false, friends = 0))
        assertEquals(TodayFriendTapAction.OpenAccount, state(cloud = false).tapAction(forcedVisible = false))
    }

    @Test
    fun cloudAccountsWithoutFriendsOpenFriends() {
        assertEquals(TodayFriendTapAction.OpenFriends, state(friends = 0).tapAction(false))
    }

    @Test
    fun friendsOpenThePicker() {
        assertEquals(TodayFriendTapAction.PickFriend, state().tapAction(false))
    }

    @Test
    fun aPendingInviteWinsAndOpensInvites() {
        assertEquals(TodayFriendEntryState.PendingInvite(2), state(invites = 2))
        assertEquals(TodayFriendTapAction.OpenInvites, state(invites = 1).tapAction(false))
        assertEquals(TodayFriendTapAction.OpenInvites, state(invites = 1, cloud = false).tapAction(false))
    }

    @Test
    fun aLiveWorkoutHidesThePill() {
        assertEquals(TodayFriendEntryState.Hidden, state(live = true, invites = 3))
        assertEquals(TodayFriendTapAction.None, state(live = true).tapAction(false))
    }

    @Test
    fun aSoloWorkoutBlocksEverythingButAnInvite() {
        assertEquals(TodayFriendTapAction.BlockedBySoloWorkout, state().tapAction(forcedVisible = true))
        assertEquals(TodayFriendTapAction.BlockedBySoloWorkout, state(cloud = false).tapAction(true))
        assertEquals(TodayFriendTapAction.OpenInvites, state(invites = 1).tapAction(true))
    }
}
