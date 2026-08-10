package com.example.gymapp.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.SocialBlockedProfile
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.SocialFriendRequest
import com.example.gymapp.auth.SocialIncomingWorkoutInvite
import com.example.gymapp.auth.SocialOutgoingWorkoutInvite
import com.example.gymapp.auth.SocialPrivacy
import com.example.gymapp.auth.LiveInvitation
import com.example.gymapp.auth.LiveInboxRoom
import com.example.gymapp.auth.rankedSocialFriends
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.FriendsUiState
import com.example.gymapp.ui.viewmodel.LiveConnectionMode
import com.example.gymapp.ui.viewmodel.LiveWorkoutUiState
import com.example.gymapp.util.asString

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
    onUpdatePrivacy: (SocialPrivacy) -> Unit,
    onAcceptWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onDeclineWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onReuseWorkoutInvite: (SocialIncomingWorkoutInvite) -> Unit,
    onCancelWorkoutInvite: (SocialOutgoingWorkoutInvite) -> Unit,
    onClearMessages: () -> Unit,
    onAcceptLiveInvitation: (LiveInvitation) -> Unit,
    onDeclineLiveInvitation: (LiveInvitation) -> Unit,
    onStartLiveRoom: (LiveInboxRoom) -> Unit,
    onCloseLiveRoom: (LiveInboxRoom) -> Unit,
    onOpenLiveRoom: (LiveInboxRoom) -> Unit,
    onClearLiveMessages: () -> Unit,
    modifier: Modifier = Modifier,
    headerContent: LazyListScope.() -> Unit = {}
) {
    val context = LocalContext.current
    var friendCode by rememberSaveable { mutableStateOf("") }
    var copiedCode by rememberSaveable { mutableStateOf(false) }
    var inviteToAccept by remember { mutableStateOf<SocialIncomingWorkoutInvite?>(null) }
    var requestToBlock by remember { mutableStateOf<SocialFriendRequest?>(null) }
    val dashboard = uiState.dashboard

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 16.dp, top = 10.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        headerContent()

        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = stringResource(R.string.friends_hero_title),
                        style = MaterialTheme.typography.headlineMedium
                    )
                    Text(
                        text = stringResource(R.string.friends_hero_supporting),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = stringResource(R.string.friends_integrity_notice),
                        style = MaterialTheme.typography.labelMedium
                    )
                }
            }
        }

        uiState.error?.let { error ->
            item {
                MessagePanel(
                    message = error.asString(),
                    isError = true,
                    onDismiss = onClearMessages
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
                    modifier = Modifier.fillMaxWidth()
                )
            }
            return@LazyColumn
        }

        item {
            RefreshSocialCard(
                isLoading = uiState.isDashboardLoading || uiState.isInboxLoading,
                pendingInvites = dashboard?.pendingWorkoutInviteCount ?: 0,
                onRefresh = onRefresh
            )
        }

        liveWorkoutLobby(
            state = liveUiState,
            onAccept = onAcceptLiveInvitation,
            onDecline = onDeclineLiveInvitation,
            onStart = onStartLiveRoom,
            onClose = onCloseLiveRoom,
            onOpen = onOpenLiveRoom
        )

        if (dashboard == null) {
            if (uiState.isDashboardLoading) {
                item { CenteredLoader() }
            }
            return@LazyColumn
        }

        item {
            FriendCodeCard(
                displayName = dashboard.self.displayName,
                friendCode = dashboard.self.friendCode,
                xp = dashboard.self.xp,
                level = dashboard.self.level,
                workouts = dashboard.self.workouts,
                statsAvailable = dashboard.self.statsAvailable,
                copied = copiedCode,
                onCopy = {
                    copiedCode = copyFriendCode(context, dashboard.self.friendCode)
                }
            )
        }

        item {
            AddFriendCard(
                friendCode = friendCode,
                onFriendCodeChange = {
                    friendCode = it.take(64)
                    copiedCode = false
                },
                isLoading = "send-friend" in uiState.actionsInFlight,
                onSend = { onSendFriendRequest(friendCode) }
            )
        }

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
                IncomingWorkoutInviteCard(
                    invite = invite,
                    isLoading = "invite-${invite.inviteId}" in uiState.actionsInFlight,
                    onAccept = { inviteToAccept = invite },
                    onDecline = { onDeclineWorkoutInvite(invite) },
                    onReuse = { inviteToAccept = invite }
                )
            }
        }

        if (dashboard.incoming.isNotEmpty()) {
            item {
                SectionTitle(
                    eyebrow = stringResource(R.string.friends_requests_eyebrow),
                    title = stringResource(R.string.friends_incoming_title)
                )
            }
            items(dashboard.incoming, key = { "incoming-${it.friendshipId}" }) { request ->
                IncomingFriendRequestCard(
                    request = request,
                    isLoading = "friend-${request.friendshipId}" in uiState.actionsInFlight ||
                        "profile-${request.profileId}" in uiState.actionsInFlight,
                    onAccept = { onAcceptFriendRequest(request) },
                    onDecline = { onDeclineFriendRequest(request) },
                    onBlock = { requestToBlock = request }
                )
            }
        }

        item {
            SectionTitle(
                eyebrow = stringResource(R.string.friends_ranking_eyebrow),
                title = stringResource(R.string.friends_ranking_title),
                supporting = stringResource(R.string.friends_ranking_supporting)
            )
        }
        val rankedFriends = rankedSocialFriends(dashboard.friends)
        if (rankedFriends.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friends_empty_title),
                    supporting = stringResource(R.string.friends_empty_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        } else {
            items(rankedFriends, key = { it.friendshipId }) { friend ->
                FriendRankingCard(
                    place = rankedFriends.indexOf(friend) + 1,
                    friend = friend,
                    onOpen = { onOpenFriend(friend) }
                )
            }
        }

        item {
            PrivacyCard(
                saved = dashboard.self.privacy,
                revision = dashboard.self.settingsRevision,
                isLoading = "privacy" in uiState.actionsInFlight,
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
                OutgoingFriendRequestCard(
                    request = request,
                    isLoading = "friend-${request.friendshipId}" in uiState.actionsInFlight,
                    onCancel = { onCancelFriendRequest(request) }
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
                OutgoingWorkoutInviteCard(
                    invite = invite,
                    isLoading = "invite-${invite.inviteId}" in uiState.actionsInFlight,
                    onCancel = { onCancelWorkoutInvite(invite) }
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
}

private fun LazyListScope.liveWorkoutLobby(
    state: LiveWorkoutUiState,
    onAccept: (LiveInvitation) -> Unit,
    onDecline: (LiveInvitation) -> Unit,
    onStart: (LiveInboxRoom) -> Unit,
    onClose: (LiveInboxRoom) -> Unit,
    onOpen: (LiveInboxRoom) -> Unit
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
        AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
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
                        enabled = "respond-${invitation.roomId}" !in state.actionsInFlight,
                        modifier = Modifier.weight(1f)
                    ) { Text(stringResource(R.string.action_accept)) }
                    OutlinedButton(
                        onClick = { onDecline(invitation) },
                        enabled = "respond-${invitation.roomId}" !in state.actionsInFlight,
                        modifier = Modifier.weight(1f)
                    ) { Text(stringResource(R.string.action_decline)) }
                }
            }
        }
    }
    items(rooms, key = { "live-room-${it.roomId}" }) { room ->
        AppPanel(modifier = Modifier.fillMaxWidth()) {
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
                    if (room.role == "owner" && room.status == "ready") {
                        Button(
                            onClick = { onStart(room) },
                            enabled = "start-${room.roomId}" !in state.actionsInFlight,
                            modifier = Modifier.weight(1f)
                        ) { Text(stringResource(R.string.live_workout_start_action)) }
                    } else if (room.status == "active") {
                        Button(
                            onClick = { onOpen(room) },
                            modifier = Modifier.weight(1f)
                        ) { Text(stringResource(R.string.live_workout_open_action)) }
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
private fun FriendCodeCard(
    displayName: String,
    friendCode: String,
    xp: Int?,
    level: Int?,
    workouts: Int?,
    statsAvailable: Boolean,
    copied: Boolean,
    onCopy: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(displayName, style = MaterialTheme.typography.titleLarge)
            Text(
                text = if (statsAvailable) {
                    stringResource(
                        R.string.friend_stats_summary,
                        xp ?: 0,
                        level ?: 1,
                        workouts ?: 0
                    )
                } else {
                    stringResource(R.string.friend_stats_private)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = stringResource(R.string.friend_code_label),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = friendCode,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold
            )
            OutlinedButton(onClick = onCopy) {
                Text(
                    if (copied) stringResource(R.string.friend_code_copied)
                    else stringResource(R.string.friend_code_copy)
                )
            }
        }
    }
}

@Composable
private fun AddFriendCard(
    friendCode: String,
    onFriendCodeChange: (String) -> Unit,
    isLoading: Boolean,
    onSend: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.friends_add_eyebrow),
                title = stringResource(R.string.friends_add_title),
                supporting = stringResource(R.string.friends_add_supporting)
            )
            OutlinedTextField(
                value = friendCode,
                onValueChange = onFriendCodeChange,
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
                label = { Text(stringResource(R.string.friend_code_label)) }
            )
            Button(
                onClick = onSend,
                enabled = friendCode.isNotBlank() && !isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    if (isLoading) stringResource(R.string.friend_request_sending)
                    else stringResource(R.string.friend_request_send)
                )
            }
        }
    }
}

@Composable
private fun IncomingFriendRequestCard(
    request: SocialFriendRequest,
    isLoading: Boolean,
    onAccept: () -> Unit,
    onDecline: () -> Unit,
    onBlock: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(request.displayName, style = MaterialTheme.typography.titleMedium)
            Text(request.requestedAt.take(10), style = MaterialTheme.typography.bodySmall)
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
    isLoading: Boolean,
    onCancel: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
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

@Composable
private fun PrivacyCard(
    saved: SocialPrivacy,
    revision: Int,
    isLoading: Boolean,
    onSave: (SocialPrivacy) -> Unit
) {
    var draft by remember(revision) { mutableStateOf(saved) }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.friends_privacy_eyebrow),
                title = stringResource(R.string.friends_privacy_title),
                supporting = stringResource(R.string.friends_privacy_supporting)
            )
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
            Button(
                onClick = { onSave(draft) },
                enabled = draft != saved && !isLoading,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_save))
            }
        }
    }
}

@Composable
private fun PrivacySwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun IncomingWorkoutInviteCard(
    invite: SocialIncomingWorkoutInvite,
    isLoading: Boolean,
    onAccept: () -> Unit,
    onDecline: () -> Unit,
    onReuse: () -> Unit
) {
    val localizedNames = invite.workout.exercises.map { exercise ->
        localizedExerciseName(exercise.name)
    }
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = invite.status == "pending") {
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
    isLoading: Boolean,
    onCancel: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
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
private fun MessagePanel(message: String, isError: Boolean, onDismiss: () -> Unit) {
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
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.action_dismiss))
            }
        }
    }
}

@Composable
private fun CenteredLoader() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center
    ) {
        CircularProgressIndicator()
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
        clipboard.setPrimaryClip(ClipData.newPlainText("GymApp friend code", value))
    }.isSuccess
}
