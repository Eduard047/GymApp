package com.example.gymapp.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.focusable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.SocialBlockedProfile
import com.example.gymapp.auth.SocialDashboard
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.SocialFriendRequest
import com.example.gymapp.auth.SocialIncomingWorkoutInvite
import com.example.gymapp.auth.SocialOutgoingWorkoutInvite
import com.example.gymapp.auth.SocialPrivacy
import com.example.gymapp.auth.LiveInvitation
import com.example.gymapp.auth.LiveInboxRoom
import com.example.gymapp.auth.LiveWorkoutSnapshot
import com.example.gymapp.auth.formatSocialFriendCode
import com.example.gymapp.auth.hasAnotherBoundedPage
import com.example.gymapp.auth.rankedSocialFriends
import com.example.gymapp.push.PushNavigationTarget
import com.example.gymapp.push.SocialPushType
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.FriendsUiState
import com.example.gymapp.ui.viewmodel.LiveConnectionMode
import com.example.gymapp.ui.viewmodel.LiveWorkoutUiState
import com.example.gymapp.util.asString
import com.example.gymapp.util.DateTimeUtils
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

@Composable
internal fun FinishedLiveWorkoutDialog(
    snapshot: LiveWorkoutSnapshot,
    onRefresh: () -> Unit,
    onDismiss: () -> Unit
) {
    var showsPeer by remember(snapshot.room.roomId) { mutableStateOf(false) }
    val participant = if (showsPeer) snapshot.peer else snapshot.self
    val completed = participant.progress?.completedSets.orEmpty().associateBy { it.setId }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.live_workout_peer_read_only)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                TabRow(selectedTabIndex = if (showsPeer) 1 else 0) {
                    Tab(selected = !showsPeer, onClick = { showsPeer = false },
                        text = { Text(snapshot.self.profile.displayName) })
                    Tab(selected = showsPeer, onClick = { showsPeer = true },
                        text = { Text(snapshot.peer.profile.displayName) })
                }
                if (participant.state == "finished") {
                    Text(stringResource(R.string.live_workout_member_finished))
                }
                LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(snapshot.plan.exercises, key = { it.exerciseId }) { exercise ->
                        AppPanel(modifier = Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(localizedExerciseName(exercise.name), style = MaterialTheme.typography.titleSmall)
                                exercise.sets.forEachIndexed { index, planned ->
                                    val actual = completed[planned.setId]
                                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                        Text(stringResource(R.string.label_set, index + 1))
                                        Text(if (actual != null) stringResource(
                                            R.string.live_workout_peer_set_completed,
                                            actual.weight.toString(), actual.reps
                                        ) else stringResource(R.string.live_workout_set_not_recorded))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onRefresh) { Text(stringResource(R.string.action_refresh)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) } }
    )
}

@Composable
internal fun FriendsScreen(
    uiState: FriendsUiState,
    liveUiState: LiveWorkoutUiState,
    onRefresh: () -> Unit,
    onSendFriendRequest: (String) -> Unit,
    onAcceptFriendRequest: (SocialFriendRequest) -> Unit,
    onDeclineFriendRequest: (SocialFriendRequest) -> Unit,
    onCancelFriendRequest: (SocialFriendRequest) -> Unit,
    onOpenFriend: (SocialFriend) -> Unit,
    onBlockProfile: (String) -> Unit,
    onUnblockProfile: (SocialBlockedProfile) -> Unit,
    onUpdatePrivacy: (SocialPrivacy, Boolean?) -> Unit,
    onAcceptWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onDeclineWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onReuseWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onCancelWorkoutInvite: (SocialOutgoingWorkoutInvite) -> Unit,
    onLoadMoreWorkoutInvites: () -> Unit,
    onClearMessages: () -> Unit,
    onAcceptLiveInvitation: (LiveInvitation) -> Unit,
    onDeclineLiveInvitation: (LiveInvitation) -> Unit,
    onCloseLiveRoom: (LiveInboxRoom) -> Unit,
    onOpenLiveRoom: (LiveInboxRoom) -> Unit,
    onClearLiveMessages: () -> Unit,
    onOpenAccountSettings: () -> Unit,
    focusedSocialPush: PushNavigationTarget.Social? = null,
    focusedLiveRoomId: String? = null,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    val languageTag = currentAppLanguageTag()
    val locale = remember(languageTag) { Locale.forLanguageTag(languageTag) }
    var friendCode by rememberSaveable { mutableStateOf("") }
    var copiedCode by rememberSaveable { mutableStateOf(false) }
    var showAddFriendDialog by rememberSaveable { mutableStateOf(false) }
    var inviteToAccept by remember { mutableStateOf<SocialIncomingWorkoutInvite?>(null) }
    var requestToBlock by remember { mutableStateOf<SocialFriendRequest?>(null) }
    val listState = rememberLazyListState()
    val focusedObjectRequester = remember { FocusRequester() }
    val dashboard = uiState.dashboard
    val displayedFriendCode = dashboard?.let {
        formatSocialFriendCode(uiState.myFriendCode ?: it.self.friendCode)
    }.orEmpty()
    val focusedObjectIndex = friendsFocusedObjectIndex(
        uiState = uiState,
        liveUiState = liveUiState,
        focusedSocialPush = focusedSocialPush,
        focusedLiveRoomId = focusedLiveRoomId
    )
    val focusedObjectKey = focusedLiveRoomId
        ?: focusedSocialPush?.let { "${it.type.wireValue}:${it.objectId}" }

    LaunchedEffect(focusedObjectKey, focusedObjectIndex) {
        if (focusedObjectKey != null && focusedObjectIndex != null) {
            // A direct jump avoids non-essential motion while still placing an exact push target
            // in the viewport for keyboard, switch-control, and screen-reader users.
            listState.scrollToItem(focusedObjectIndex)
            androidx.compose.runtime.withFrameNanos { }
            runCatching { focusedObjectRequester.requestFocus() }
        }
    }

    fun focusedObjectModifier(isFocused: Boolean): Modifier = if (isFocused) {
        Modifier
            .focusRequester(focusedObjectRequester)
            .focusable()
    } else {
        Modifier
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        state = listState,
        contentPadding = PaddingValues(
            start = screenHorizontalPadding,
            top = GymSpacing.ScreenTop,
            end = screenHorizontalPadding,
            bottom = GymSpacing.ScreenBottom
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
    ) {
        uiState.error?.let { error ->
            item {
                MessagePanel(
                    message = error.asString(),
                    isError = true,
                    onDismiss = onClearMessages,
                    actionLabel = stringResource(R.string.action_retry),
                    onAction = onRefresh
                )
            }
        }
        uiState.notice?.let { notice ->
            item {
                MessagePanel(
                    message = notice.asString(),
                    isError = false,
                    onDismiss = onClearMessages
                )
            }
        }
        liveUiState.error?.let { error ->
            item {
                MessagePanel(error.asString(), true, onClearLiveMessages)
            }
        }
        liveUiState.notice?.let { notice ->
            item {
                MessagePanel(notice.asString(), false, onClearLiveMessages)
            }
        }

        if (!uiState.isCloudAccount) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friends_cloud_required_title),
                    supporting = stringResource(R.string.friends_cloud_required_supporting),
                    actionLabel = stringResource(R.string.profile_section_settings),
                    onAction = onOpenAccountSettings,
                    modifier = Modifier.fillMaxWidth()
                )
            }
            return@LazyColumn
        }

        liveWorkoutLobby(
            state = liveUiState,
            onAccept = onAcceptLiveInvitation,
            onDecline = onDeclineLiveInvitation,
            onClose = onCloseLiveRoom,
            onOpen = onOpenLiveRoom,
            focusedRoomId = focusedLiveRoomId,
            focusedModifier = focusedObjectModifier(focusedLiveRoomId != null)
        )

        val incomingInvites = uiState.workoutInbox?.incoming.orEmpty()
        if (incomingInvites.isNotEmpty()) {
            item {
                SectionTitle(
                    eyebrow = stringResource(R.string.workout_invites_eyebrow),
                    title = stringResource(R.string.workout_invites_incoming_title),
                    supporting = stringResource(R.string.workout_invites_independent_copy)
                )
            }
            items(incomingInvites, key = { "incoming-workout-${it.inviteId}" }) { invite ->
                val highlighted = socialPushTargetsWorkoutInvite(
                    focusedSocialPush,
                    invite.inviteId
                )
                IncomingWorkoutInviteCard(
                    invite = invite,
                    highlighted = highlighted,
                    isLoading = "invite-${invite.inviteId}" in uiState.actionsInFlight,
                    onAccept = { inviteToAccept = invite },
                    onDecline = { onDeclineWorkoutInvite(invite) },
                    onReuse = { inviteToAccept = invite },
                    modifier = focusedObjectModifier(highlighted)
                )
            }
        }
        if (uiState.workoutInbox?.hasAnotherBoundedPage() == true) {
            item {
                OutlinedButton(
                    onClick = onLoadMoreWorkoutInvites,
                    enabled = !uiState.isInboxLoading,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.workout_invites_load_more))
                }
            }
        }

        val incomingFriendRequests = dashboard?.incoming.orEmpty()
        if (incomingFriendRequests.isNotEmpty()) {
            item {
                SectionTitle(
                    eyebrow = stringResource(R.string.friends_requests_eyebrow),
                    title = stringResource(R.string.friends_incoming_title)
                )
            }
            items(incomingFriendRequests, key = { "incoming-${it.friendshipId}" }) { request ->
                val highlighted = socialPushTargetsFriendRequest(
                    focusedSocialPush,
                    request.friendshipId
                )
                IncomingFriendRequestCard(
                    request = request,
                    locale = locale,
                    highlighted = highlighted,
                    isLoading = "friend-${request.friendshipId}" in uiState.actionsInFlight ||
                        "profile-${request.profileId}" in uiState.actionsInFlight,
                    onAccept = { onAcceptFriendRequest(request) },
                    onDecline = { onDeclineFriendRequest(request) },
                    onBlock = { requestToBlock = request },
                    modifier = focusedObjectModifier(highlighted)
                )
            }
        }

        if (dashboard == null) {
            item {
                RefreshSocialCard(
                    isLoading = uiState.isDashboardLoading || uiState.isInboxLoading,
                    pendingInvites = 0,
                    onRefresh = onRefresh
                )
            }
            if (uiState.isDashboardLoading) {
                item { LoadingStatePanel() }
            }
            return@LazyColumn
        }

        val rankedFriends = rankedSocialFriends(dashboard.friends)
        item {
            TrainingCircleCard(
                dashboard = dashboard,
                rankedFriends = rankedFriends,
                isLoading = uiState.isDashboardLoading || uiState.isInboxLoading,
                onRefresh = onRefresh,
                onOpenFriend = onOpenFriend
            )
        }

        item {
            FriendConnectionCard(
                friendCode = displayedFriendCode,
                copied = copiedCode,
                onCopy = {
                    copiedCode = copyFriendCode(context, displayedFriendCode)
                },
                onShare = { shareFriendCode(context, displayedFriendCode) },
                onAddFriend = { showAddFriendDialog = true }
            )
        }

        item {
            PrivacyCard(
                saved = dashboard.self.privacy,
                revision = dashboard.self.settingsRevision,
                shareWorkoutDetails = uiState.workoutDetailPrivacy?.shareWorkoutDetails,
                isLoading = "privacy" in uiState.actionsInFlight,
                isWorkoutDetailsLoading = uiState.isWorkoutDetailPrivacyLoading ||
                    "privacy-details" in uiState.actionsInFlight,
                onSave = onUpdatePrivacy
            )
        }

        if (dashboard.outgoing.isNotEmpty()) {
            item {
                SectionTitle(
                    eyebrow = stringResource(R.string.friends_requests_eyebrow),
                    title = stringResource(R.string.friends_outgoing_title)
                )
            }
            items(dashboard.outgoing, key = { "outgoing-${it.friendshipId}" }) { request ->
                val highlighted = socialPushTargetsFriendRequest(
                    focusedSocialPush,
                    request.friendshipId
                )
                OutgoingFriendRequestCard(
                    request = request,
                    highlighted = highlighted,
                    isLoading = "friend-${request.friendshipId}" in uiState.actionsInFlight,
                    onCancel = { onCancelFriendRequest(request) },
                    modifier = focusedObjectModifier(highlighted)
                )
            }
        }

        val outgoingInvites = uiState.workoutInbox?.outgoing.orEmpty()
        if (outgoingInvites.isNotEmpty()) {
            item {
                SectionTitle(
                    eyebrow = stringResource(R.string.workout_invites_eyebrow),
                    title = stringResource(R.string.workout_invites_outgoing_title)
                )
            }
            items(outgoingInvites, key = { "outgoing-workout-${it.inviteId}" }) { invite ->
                val highlighted = socialPushTargetsWorkoutInvite(
                    focusedSocialPush,
                    invite.inviteId
                )
                OutgoingWorkoutInviteCard(
                    invite = invite,
                    highlighted = highlighted,
                    isLoading = "invite-${invite.inviteId}" in uiState.actionsInFlight,
                    onCancel = { onCancelWorkoutInvite(invite) },
                    modifier = focusedObjectModifier(highlighted)
                )
            }
        }

        if (dashboard.blocked.isNotEmpty()) {
            item {
                SectionTitle(
                    eyebrow = stringResource(R.string.friends_safety_eyebrow),
                    title = stringResource(R.string.friends_blocked_title)
                )
            }
            items(dashboard.blocked, key = { "blocked-${it.profileId}" }) { profile ->
                BlockedProfileCard(
                    profile = profile,
                    isLoading = "profile-${profile.profileId}" in uiState.actionsInFlight,
                    onUnblock = { onUnblockProfile(profile) }
                )
            }
        }
    }

    inviteToAccept?.let { invite ->
        AlertDialog(
            onDismissRequest = { inviteToAccept = null },
            title = { Text(stringResource(R.string.workout_invite_accept_title)) },
            text = {
                Text(
                    stringResource(
                        R.string.workout_invite_accept_description,
                        invite.displayName
                    )
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        inviteToAccept = null
                        if (invite.status == "pending") {
                            onAcceptWorkoutInvite(invite)
                        } else {
                            onReuseWorkoutInvite(invite)
                        }
                    }
                ) {
                    Text(stringResource(R.string.workout_invite_accept_action))
                }
            },
            dismissButton = {
                TextButton(onClick = { inviteToAccept = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }

    requestToBlock?.let { request ->
        AlertDialog(
            onDismissRequest = { requestToBlock = null },
            title = { Text(stringResource(R.string.friend_block_confirm_title)) },
            text = {
                Text(
                    stringResource(
                        R.string.friend_block_confirm_supporting,
                        request.displayName
                    )
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        requestToBlock = null
                        onBlockProfile(incomingFriendRequestBlockTarget(request))
                    }
                ) {
                    Text(stringResource(R.string.friend_block_action))
                }
            },
            dismissButton = {
                TextButton(onClick = { requestToBlock = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }

    if (showAddFriendDialog) {
        AddFriendDialog(
            friendCode = friendCode,
            onFriendCodeChange = {
                friendCode = it.take(64)
                copiedCode = false
            },
            isLoading = "send-friend" in uiState.actionsInFlight,
            onDismiss = { showAddFriendDialog = false },
            onSend = {
                onSendFriendRequest(friendCode)
                showAddFriendDialog = false
            }
        )
    }
}

internal fun socialPushTargetsFriendRequest(
    target: PushNavigationTarget.Social?,
    friendshipId: String
): Boolean = target?.type == SocialPushType.FriendRequestReceived &&
    target.objectId == friendshipId

internal fun socialPushTargetsWorkoutInvite(
    target: PushNavigationTarget.Social?,
    inviteId: String
): Boolean = target?.type in setOf(
    SocialPushType.WorkoutInviteReceived,
    SocialPushType.WorkoutInviteAccepted
) && target?.objectId == inviteId

/** Returns the exact lazy-list slot only after the authoritative object is present. */
internal fun friendsFocusedObjectIndex(
    uiState: FriendsUiState,
    liveUiState: LiveWorkoutUiState,
    focusedSocialPush: PushNavigationTarget.Social?,
    focusedLiveRoomId: String?
): Int? {
    if (!uiState.isCloudAccount ||
        focusedSocialPush == null && focusedLiveRoomId == null
    ) return null
    var index = listOf(
        uiState.error,
        uiState.notice,
        liveUiState.error,
        liveUiState.notice
    ).count { it != null }

    val liveInvitations = liveUiState.inbox?.invitations.orEmpty()
    val liveRooms = liveUiState.inbox?.rooms.orEmpty()
    if (liveInvitations.isNotEmpty() || liveRooms.isNotEmpty()) {
        index += 1 // Lobby heading.
        liveInvitations.indexOfFirst { it.roomId == focusedLiveRoomId }
            .takeIf { it >= 0 }
            ?.let { return index + it }
        index += liveInvitations.size
        liveRooms.indexOfFirst { it.roomId == focusedLiveRoomId }
            .takeIf { it >= 0 }
            ?.let { return index + it }
        index += liveRooms.size
    }

    val incomingWorkoutInvites = uiState.workoutInbox?.incoming.orEmpty()
    if (incomingWorkoutInvites.isNotEmpty()) {
        index += 1 // Incoming workout heading.
        incomingWorkoutInvites.indexOfFirst {
            socialPushTargetsWorkoutInvite(focusedSocialPush, it.inviteId)
        }.takeIf { it >= 0 }?.let { return index + it }
        index += incomingWorkoutInvites.size
    }
    if (uiState.workoutInbox?.hasAnotherBoundedPage() == true) index += 1

    val incomingFriendRequests = uiState.dashboard?.incoming.orEmpty()
    if (incomingFriendRequests.isNotEmpty()) {
        index += 1 // Incoming friend heading.
        incomingFriendRequests.indexOfFirst {
            socialPushTargetsFriendRequest(focusedSocialPush, it.friendshipId)
        }.takeIf { it >= 0 }?.let { return index + it }
        index += incomingFriendRequests.size
    }

    val dashboard = uiState.dashboard ?: return null
    index += 3 // Training circle, friend connection, and privacy.

    if (dashboard.outgoing.isNotEmpty()) {
        index += 1 // Outgoing friend heading.
        dashboard.outgoing.indexOfFirst {
            socialPushTargetsFriendRequest(focusedSocialPush, it.friendshipId)
        }.takeIf { it >= 0 }?.let { return index + it }
        index += dashboard.outgoing.size
    }

    val outgoingWorkoutInvites = uiState.workoutInbox?.outgoing.orEmpty()
    if (outgoingWorkoutInvites.isNotEmpty()) {
        index += 1 // Outgoing workout heading.
        outgoingWorkoutInvites.indexOfFirst {
            socialPushTargetsWorkoutInvite(focusedSocialPush, it.inviteId)
        }.takeIf { it >= 0 }?.let { return index + it }
    }
    return null
}

internal enum class LiveLobbyPrimaryAction {
    OpenActiveWorkout
}

internal fun liveLobbyPrimaryAction(roomStatus: String): LiveLobbyPrimaryAction? =
    if (roomStatus == "active") LiveLobbyPrimaryAction.OpenActiveWorkout else null

private fun LazyListScope.liveWorkoutLobby(
    state: LiveWorkoutUiState,
    onAccept: (LiveInvitation) -> Unit,
    onDecline: (LiveInvitation) -> Unit,
    onClose: (LiveInboxRoom) -> Unit,
    onOpen: (LiveInboxRoom) -> Unit,
    focusedRoomId: String?,
    focusedModifier: Modifier
) {
    val invitations = state.inbox?.invitations.orEmpty()
    val rooms = state.inbox?.rooms.orEmpty()
    if (invitations.isEmpty() && rooms.isEmpty()) return

    item {
        SectionTitle(
            eyebrow = stringResource(R.string.live_workout_lobby_eyebrow),
            title = stringResource(R.string.live_workout_lobby_title),
            supporting = stringResource(
                when (state.connectionMode) {
                    LiveConnectionMode.Realtime -> R.string.live_workout_connection_realtime
                    LiveConnectionMode.Polling -> R.string.live_workout_connection_polling
                    LiveConnectionMode.Offline -> R.string.live_workout_connection_offline
                }
            )
        )
    }
    items(invitations, key = { "live-invite-${it.roomId}" }) { invitation ->
        AppPanel(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    if (invitation.roomId == focusedRoomId) {
                        focusedModifier.testTag("focused_live_push_object")
                    } else {
                        Modifier
                    }
                ),
            highlighted = true
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    stringResource(R.string.live_workout_invited_by, invitation.owner.displayName),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    stringResource(
                        R.string.live_workout_plan_summary,
                        invitation.summary.exerciseCount,
                        invitation.summary.setCount
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { onAccept(invitation) },
                        enabled = "respond-${invitation.roomId}" !in state.actionsInFlight &&
                            state.confirmedRestoringRoomId != invitation.roomId,
                        modifier = Modifier.weight(1f)
                    ) { Text(stringResource(R.string.live_workout_accept_action)) }
                    OutlinedButton(
                        onClick = { onDecline(invitation) },
                        enabled = "respond-${invitation.roomId}" !in state.actionsInFlight &&
                            state.confirmedRestoringRoomId != invitation.roomId,
                        modifier = Modifier.weight(1f)
                    ) { Text(stringResource(R.string.action_decline)) }
                }
            }
        }
    }
    items(rooms, key = { "live-room-${it.roomId}" }) { room ->
        AppPanel(
            modifier = Modifier
                .fillMaxWidth()
                .then(
                    if (room.roomId == focusedRoomId) {
                        focusedModifier.testTag("focused_live_push_object")
                    } else {
                        Modifier
                    }
                ),
            highlighted = room.roomId == focusedRoomId
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    stringResource(R.string.live_workout_with_friend, room.peer.displayName),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    stringResource(
                        when (room.status) {
                            "waiting" -> R.string.live_workout_status_waiting
                            "ready" -> R.string.live_workout_status_ready
                            else -> R.string.live_workout_status_active
                        }
                    ),
                    style = MaterialTheme.typography.bodyMedium
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    when (liveLobbyPrimaryAction(room.status)) {
                        LiveLobbyPrimaryAction.OpenActiveWorkout -> {
                            Button(
                                onClick = { onOpen(room) },
                                modifier = Modifier.weight(1f)
                            ) { Text(stringResource(R.string.live_workout_open_action)) }
                        }
                        null -> Unit
                    }
                    OutlinedButton(
                        onClick = { onClose(room) },
                        enabled = "close-${room.roomId}" !in state.actionsInFlight,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            stringResource(
                                if (room.role == "owner") {
                                    R.string.live_workout_cancel_action
                                } else {
                                    R.string.live_workout_leave_action
                                }
                            )
                        )
                    }
                }
            }
        }
    }
}

internal fun incomingFriendRequestBlockTarget(request: SocialFriendRequest): String =
    request.profileId

@Composable
private fun RefreshSocialCard(isLoading: Boolean, pendingInvites: Int, onRefresh: () -> Unit) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = pendingInvites > 0) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = stringResource(R.string.friends_synced_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = if (pendingInvites > 0) {
                        stringResource(R.string.workout_invites_pending_count, pendingInvites)
                    } else {
                        stringResource(R.string.friends_synced_supporting)
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Button(onClick = onRefresh, enabled = !isLoading) {
                if (isLoading) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Text(stringResource(R.string.action_refresh))
                }
            }
        }
    }
}

@Composable
private fun TrainingCircleCard(
    dashboard: SocialDashboard,
    rankedFriends: List<SocialFriend>,
    isLoading: Boolean,
    onRefresh: () -> Unit,
    onOpenFriend: (SocialFriend) -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.friends_hero_title),
                        style = MaterialTheme.typography.titleLarge
                    )
                    Text(
                        text = stringResource(R.string.friends_confirmed_count, dashboard.friends.size),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                OutlinedButton(onClick = onRefresh, enabled = !isLoading) {
                    if (isLoading) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        Text(stringResource(R.string.action_refresh))
                    }
                }
            }

            Text(dashboard.self.displayName, style = MaterialTheme.typography.titleMedium)
            Text(
                text = if (dashboard.self.statsAvailable) {
                    stringResource(
                        R.string.friend_stats_summary,
                        dashboard.self.xp ?: 0,
                        dashboard.self.level ?: 1,
                        dashboard.self.workouts ?: 0
                    )
                } else {
                    stringResource(R.string.friend_stats_private)
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            if (rankedFriends.isEmpty()) {
                Text(
                    text = stringResource(R.string.friends_empty_supporting),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                rankedFriends.forEachIndexed { index, friend ->
                    if (index > 0) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                    TextButton(
                        onClick = { onOpenFriend(friend) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Text(
                                text = "#${index + 1}",
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.primary
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = friend.displayName,
                                    style = MaterialTheme.typography.titleSmall,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = if (friend.statsAvailable) {
                                        stringResource(
                                            R.string.friend_stats_summary,
                                            friend.xp ?: 0,
                                            friend.level ?: 1,
                                            friend.workouts ?: 0
                                        )
                                    } else {
                                        stringResource(R.string.friend_stats_private)
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                            Text(
                                text = stringResource(R.string.friend_open_short),
                                style = MaterialTheme.typography.labelMedium
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FriendConnectionCard(
    friendCode: String,
    copied: Boolean,
    onCopy: () -> Unit,
    onShare: () -> Unit,
    onAddFriend: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.friends_add_eyebrow),
                title = stringResource(R.string.friends_connect_title),
                supporting = stringResource(R.string.friends_connect_supporting)
            )
            Text(
                text = friendCode,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onCopy, modifier = Modifier.weight(1f)) {
                    Text(
                        if (copied) stringResource(R.string.friend_code_copied)
                        else stringResource(R.string.friend_code_copy)
                    )
                }
                OutlinedButton(onClick = onShare, modifier = Modifier.weight(1f)) {
                    Text(stringResource(R.string.friend_code_share))
                }
            }
            Button(onClick = onAddFriend, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.friends_add_action))
            }
        }
    }
}

@Composable
private fun AddFriendDialog(
    friendCode: String,
    onFriendCodeChange: (String) -> Unit,
    isLoading: Boolean,
    onDismiss: () -> Unit,
    onSend: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.friends_add_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = stringResource(R.string.friends_add_supporting),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                OutlinedTextField(
                    value = friendCode,
                    onValueChange = onFriendCodeChange,
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    label = { Text(stringResource(R.string.friend_code_label)) }
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = onSend,
                enabled = friendCode.isNotBlank() && !isLoading
            ) {
                Text(
                    if (isLoading) stringResource(R.string.friend_request_sending)
                    else stringResource(R.string.friend_request_send)
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isLoading) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    )
}

@Composable
private fun IncomingFriendRequestCard(
    request: SocialFriendRequest,
    locale: Locale,
    highlighted: Boolean,
    isLoading: Boolean,
    onAccept: () -> Unit,
    onDecline: () -> Unit,
    onBlock: () -> Unit,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .then(if (highlighted) Modifier.testTag("focused_social_push_object") else Modifier),
        highlighted = highlighted
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(request.displayName, style = MaterialTheme.typography.titleMedium)
            Text(
                localizedSocialRequestDate(request.requestedAt, locale),
                style = MaterialTheme.typography.bodySmall
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onAccept, enabled = !isLoading) {
                    Text(stringResource(R.string.action_accept))
                }
                OutlinedButton(onClick = onDecline, enabled = !isLoading) {
                    Text(stringResource(R.string.action_decline))
                }
            }
            TextButton(onClick = onBlock, enabled = !isLoading) {
                Text(stringResource(R.string.friend_block_action))
            }
        }
    }
}

@Composable
private fun OutgoingFriendRequestCard(
    request: SocialFriendRequest,
    highlighted: Boolean,
    isLoading: Boolean,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .then(if (highlighted) Modifier.testTag("focused_social_push_object") else Modifier),
        highlighted = highlighted
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(request.displayName, style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.friend_request_pending), style = MaterialTheme.typography.bodySmall)
            }
            OutlinedButton(onClick = onCancel, enabled = !isLoading) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    }
}

@Composable
private fun FriendRankingCard(place: Int, friend: SocialFriend, onOpen: () -> Unit) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "#$place",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        friend.displayName,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = if (friend.statsAvailable) {
                            stringResource(
                                R.string.friend_stats_summary,
                                friend.xp ?: 0,
                                friend.level ?: 1,
                                friend.workouts ?: 0
                            )
                        } else {
                            stringResource(R.string.friend_stats_private)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            OutlinedButton(onClick = onOpen, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.friend_open_details))
            }
        }
    }
}

internal fun isWorkoutDetailPrivacyToggleEnabled(
    savedValue: Boolean?,
    isLoading: Boolean,
    isSaving: Boolean
): Boolean = savedValue != null && !isLoading && !isSaving

@Composable
private fun PrivacyCard(
    saved: SocialPrivacy,
    revision: Int,
    shareWorkoutDetails: Boolean?,
    isLoading: Boolean,
    isWorkoutDetailsLoading: Boolean,
    onSave: (SocialPrivacy, Boolean?) -> Unit
) {
    var draft by remember(revision) { mutableStateOf(saved) }
    var workoutDetailsDraft by remember(shareWorkoutDetails) {
        mutableStateOf(shareWorkoutDetails ?: false)
    }
    var expanded by rememberSaveable { mutableStateOf(false) }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.friends_privacy_title),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = stringResource(R.string.friends_privacy_summary),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                TextButton(onClick = { expanded = !expanded }) {
                    Text(
                        stringResource(
                            if (expanded) R.string.action_hide_details
                            else R.string.action_show_details
                        )
                    )
                }
            }
            if (expanded) {
                PrivacySwitchRow(
                    label = stringResource(R.string.friends_privacy_allow_requests),
                    checked = draft.allowRequests,
                    onCheckedChange = { draft = draft.copy(allowRequests = it) }
                )
                PrivacySwitchRow(
                    label = stringResource(R.string.friends_privacy_share_progress),
                    checked = draft.shareProgress,
                    onCheckedChange = { draft = draft.copy(shareProgress = it) }
                )
                PrivacySwitchRow(
                    label = stringResource(R.string.friends_privacy_share_workouts),
                    checked = draft.shareRecentWorkouts,
                    onCheckedChange = { draft = draft.copy(shareRecentWorkouts = it) }
                )
                PrivacySwitchRow(
                    label = stringResource(R.string.friends_privacy_share_records),
                    checked = draft.shareRecords,
                    onCheckedChange = { draft = draft.copy(shareRecords = it) }
                )
                PrivacySwitchRow(
                    label = stringResource(R.string.friends_privacy_share_workout_details),
                    checked = workoutDetailsDraft,
                    onCheckedChange = { workoutDetailsDraft = it },
                    enabled = isWorkoutDetailPrivacyToggleEnabled(
                        savedValue = shareWorkoutDetails,
                        isLoading = isWorkoutDetailsLoading,
                        isSaving = isLoading
                    )
                )
                Text(
                    stringResource(R.string.friends_privacy_share_workout_details_supporting),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Button(
                    onClick = {
                        onSave(draft, shareWorkoutDetails?.let { workoutDetailsDraft })
                    },
                    enabled = (draft != saved ||
                        shareWorkoutDetails != null && workoutDetailsDraft != shareWorkoutDetails) &&
                        !isLoading && !isWorkoutDetailsLoading,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.action_save))
                }
            }
        }
    }
}

@Composable
private fun PrivacySwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    enabled: Boolean = true
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(
                value = checked,
                enabled = enabled,
                role = Role.Switch,
                onValueChange = onCheckedChange
            )
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

@Composable
private fun IncomingWorkoutInviteCard(
    invite: SocialIncomingWorkoutInvite,
    highlighted: Boolean,
    isLoading: Boolean,
    onAccept: () -> Unit,
    onDecline: () -> Unit,
    onReuse: () -> Unit,
    modifier: Modifier = Modifier
) {
    val localizedNames = invite.summary.exerciseNames.map { rawName: String ->
        localizedExerciseName(rawName)
    }
    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .then(if (highlighted) Modifier.testTag("focused_social_push_object") else Modifier),
        highlighted = highlighted || invite.status == "pending"
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(invite.displayName, style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(
                    R.string.workout_invite_summary,
                    invite.summary.exerciseCount,
                    invite.summary.setCount
                ),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                localizedNames.joinToString(" • "),
                style = MaterialTheme.typography.bodySmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                socialInviteStatusLabel(invite.status),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            when (invite.status) {
                "pending" -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = onAccept, enabled = !isLoading) {
                        Text(stringResource(R.string.action_accept))
                    }
                    OutlinedButton(onClick = onDecline, enabled = !isLoading) {
                        Text(stringResource(R.string.action_decline))
                    }
                }
                "accepted" -> OutlinedButton(onClick = onReuse, enabled = !isLoading) {
                    Text(stringResource(R.string.workout_invite_use_copy))
                }
            }
        }
    }
}

@Composable
private fun OutgoingWorkoutInviteCard(
    invite: SocialOutgoingWorkoutInvite,
    highlighted: Boolean,
    isLoading: Boolean,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .then(if (highlighted) Modifier.testTag("focused_social_push_object") else Modifier),
        highlighted = highlighted
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(invite.displayName, style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(
                    R.string.workout_invite_summary,
                    invite.summary.exerciseCount,
                    invite.summary.setCount
                ),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(socialInviteStatusLabel(invite.status), style = MaterialTheme.typography.bodySmall)
            if (invite.status == "pending") {
                OutlinedButton(onClick = onCancel, enabled = !isLoading) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        }
    }
}

@Composable
private fun BlockedProfileCard(
    profile: SocialBlockedProfile,
    isLoading: Boolean,
    onUnblock: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(profile.displayName, modifier = Modifier.weight(1f))
            OutlinedButton(onClick = onUnblock, enabled = !isLoading) {
                Text(stringResource(R.string.friend_unblock_action))
            }
        }
    }
}

@Composable
private fun MessagePanel(
    message: String,
    isError: Boolean,
    onDismiss: () -> Unit,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = !isError) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = if (isError) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurface
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (actionLabel != null && onAction != null) {
                    Button(onClick = onAction) {
                        Text(actionLabel)
                    }
                }
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.action_dismiss))
                }
            }
        }
    }
}

@Composable
private fun socialInviteStatusLabel(status: String): String = stringResource(
    when (status) {
        "pending" -> R.string.workout_invite_status_pending
        "accepted" -> R.string.workout_invite_status_accepted
        "declined" -> R.string.workout_invite_status_declined
        "cancelled" -> R.string.workout_invite_status_cancelled
        else -> R.string.workout_invite_status_expired
    }
)

private fun copyFriendCode(context: Context, value: String): Boolean {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return false
    return runCatching {
        clipboard.setPrimaryClip(
            ClipData.newPlainText(
                context.getString(R.string.friend_code_clipboard_label),
                value
            )
        )
    }.isSuccess
}

internal fun localizedSocialRequestDate(
    requestedAt: String,
    locale: Locale,
    zoneId: ZoneId = ZoneId.systemDefault()
): String = runCatching {
    DateTimeUtils.formatDate(
        timestamp = Instant.parse(requestedAt).toEpochMilli(),
        locale = locale,
        zoneId = zoneId
    )
}.getOrElse { requestedAt }

private fun shareFriendCode(context: Context, value: String) {
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.friend_code_share_subject))
        putExtra(Intent.EXTRA_TEXT, context.getString(R.string.friend_code_share_message, value))
    }
    context.startActivity(
        Intent.createChooser(sendIntent, context.getString(R.string.friend_code_share))
    )
}
