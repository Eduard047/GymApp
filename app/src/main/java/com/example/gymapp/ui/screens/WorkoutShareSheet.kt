package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ExperimentalMaterial3Api
import com.example.gymapp.ui.theme.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import com.example.gymapp.ui.components.GymModalBottomSheet
import com.example.gymapp.ui.components.GymSheetCloseRow
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.ui.Alignment
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.rankedSocialFriends
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.HeroTone
import com.example.gymapp.ui.components.heroSecondaryOutlinedColors
import com.example.gymapp.util.formattedStringResource

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WorkoutShareSheet(
    friends: List<SocialFriend>,
    preferredFriendProfileId: String? = null,
    isCloudAccount: Boolean,
    actionsInFlight: Set<String>,
    liveActionsInFlight: Set<String>,
    onShareLink: () -> Unit,
    onSendToFriend: (SocialFriend) -> Unit,
    onStartLiveWithFriend: (SocialFriend) -> Unit,
    onDismiss: () -> Unit
) {
    val isWorkoutInviteSending = actionsInFlight.any { it.startsWith("send-workout-") }
    val isLiveInviteSending = liveActionsInFlight.any { it.startsWith("send-") }
    GymModalBottomSheet(
        onDismissRequest = onDismiss
    ) {
        // Same structure and order as the iPhone chooser: title, hero, "Use another app",
        // "Copy or live", then the privacy caption. The list scrolls so nothing is clipped.
        LazyColumn(
            modifier = Modifier.fillMaxWidth().navigationBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                GymSheetCloseRow(onClose = onDismiss)
            }
            item {
                Text(
                    stringResource(R.string.workout_share_sheet_title),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
                    textAlign = TextAlign.Center
                )
            }
            item {
                AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            Icons.Default.Groups,
                            contentDescription = null,
                            tint = HeroTone.title
                        )
                        Text(
                            stringResource(R.string.workout_share_hero_supporting),
                            style = MaterialTheme.typography.bodyMedium,
                            color = HeroTone.supporting
                        )
                    }
                }
            }
            item {
                AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            stringResource(R.string.workout_share_other_app_title),
                            style = MaterialTheme.typography.titleMedium,
                            color = HeroTone.title
                        )
                        Text(
                            stringResource(R.string.workout_share_other_app_supporting),
                            style = MaterialTheme.typography.bodyMedium,
                            color = HeroTone.supporting
                        )
                        OutlinedButton(
                            onClick = onShareLink,
                            colors = heroSecondaryOutlinedColors(),
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        ) {
                            Icon(
                                Icons.Default.Link,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.workout_share_link_title))
                        }
                    }
                }
            }
            item {
                AppPanel(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            stringResource(R.string.workout_share_copy_or_live_title),
                            style = MaterialTheme.typography.titleMedium
                        )
                        Text(
                            stringResource(R.string.workout_share_copy_or_live_supporting),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (!isCloudAccount) {
                            Text(
                                stringResource(R.string.workout_share_friend_login_required),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        } else if (friends.isEmpty()) {
                            Text(
                                stringResource(R.string.workout_share_friend_empty),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        } else {
                            workoutShareFriends(friends, preferredFriendProfileId).forEach { friend ->
                                WorkoutShareFriendRow(
                                    friend = friend,
                                    sendCopyEnabled = !isWorkoutInviteSending,
                                    inviteLiveEnabled = !isLiveInviteSending,
                                    onSendCopy = { onSendToFriend(friend) },
                                    onInviteLive = { onStartLiveWithFriend(friend) }
                                )
                            }
                        }
                    }
                }
            }
            item {
                Text(
                    stringResource(R.string.workout_share_privacy_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun WorkoutShareFriendRow(
    friend: SocialFriend,
    sendCopyEnabled: Boolean,
    inviteLiveEnabled: Boolean,
    onSendCopy: () -> Unit,
    onInviteLive: () -> Unit
) {
    val sendCopyDescription = formattedStringResource(
        R.string.workout_share_copy_friend_action,
        friend.displayName
    )
    val inviteLiveDescription = formattedStringResource(
        R.string.workout_share_live_friend_action,
        friend.displayName
    )
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f)
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(Icons.Default.AccountCircle, contentDescription = null)
                Text(
                    friend.displayName,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = onSendCopy,
                    enabled = sendCopyEnabled,
                    contentPadding = PaddingValues(horizontal = 8.dp),
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp)
                        .semantics { contentDescription = sendCopyDescription }
                ) {
                    Icon(
                        Icons.Default.ContentCopy,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        stringResource(R.string.workout_share_send_copy_action),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                Button(
                    onClick = onInviteLive,
                    enabled = inviteLiveEnabled,
                    contentPadding = PaddingValues(horizontal = 8.dp),
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(min = 48.dp)
                        .semantics { contentDescription = inviteLiveDescription }
                ) {
                    Icon(
                        Icons.Default.Sensors,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        stringResource(R.string.workout_share_invite_live_action),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

internal fun workoutShareFriends(
    friends: List<SocialFriend>,
    preferredFriendProfileId: String?
): List<SocialFriend> {
    val ranked = rankedSocialFriends(friends)
    if (preferredFriendProfileId == null) return ranked
    return ranked.sortedBy { if (it.profileId == preferredFriendProfileId) 0 else 1 }
}
