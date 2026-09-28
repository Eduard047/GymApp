package com.example.gymapp.ui.viewmodel

/** A friend offered in the "С другом" picker. */
data class TodayFriendChoice(
    val profileId: String,
    val displayName: String
)

/**
 * Decision logic for the "С другом" pill in the Today hero, the same as iOS (variant B).
 * A live workout in progress hides the pill; a pending invitation wins over every other state.
 */
sealed interface TodayFriendEntryState {
    data object NeedsCloudAccount : TodayFriendEntryState
    data object NeedsFriends : TodayFriendEntryState
    data object PickFriend : TodayFriendEntryState
    data class PendingInvite(val count: Int) : TodayFriendEntryState
    data object Hidden : TodayFriendEntryState

    companion object {
        fun from(
            isCloudAccount: Boolean,
            friendCount: Int,
            pendingInvitationCount: Int,
            hasBlockingLiveWorkout: Boolean
        ): TodayFriendEntryState = when {
            hasBlockingLiveWorkout -> Hidden
            pendingInvitationCount > 0 -> PendingInvite(pendingInvitationCount)
            !isCloudAccount -> NeedsCloudAccount
            friendCount <= 0 -> NeedsFriends
            else -> PickFriend
        }
    }
}

/** The effect of a tap on the "С другом" pill. */
enum class TodayFriendTapAction {
    OpenAccount,
    OpenFriends,
    PickFriend,
    OpenInvites,
    BlockedBySoloWorkout,
    None
}

/**
 * `forcedVisible` means a solo workout is already running: the pill still shows, but a tap only
 * explains that the current workout must be finished first, unless an invitation is waiting, which
 * still opens the invitations.
 */
fun TodayFriendEntryState.tapAction(forcedVisible: Boolean): TodayFriendTapAction {
    if (forcedVisible) {
        return if (this is TodayFriendEntryState.PendingInvite) {
            TodayFriendTapAction.OpenInvites
        } else {
            TodayFriendTapAction.BlockedBySoloWorkout
        }
    }
    return when (this) {
        TodayFriendEntryState.NeedsCloudAccount -> TodayFriendTapAction.OpenAccount
        TodayFriendEntryState.NeedsFriends -> TodayFriendTapAction.OpenFriends
        TodayFriendEntryState.PickFriend -> TodayFriendTapAction.PickFriend
        is TodayFriendEntryState.PendingInvite -> TodayFriendTapAction.OpenInvites
        TodayFriendEntryState.Hidden -> TodayFriendTapAction.None
    }
}
