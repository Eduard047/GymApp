package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Shield
import androidx.compose.ui.Alignment
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.rankedSocialFriends
import com.example.gymapp.ui.components.AppPanel

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
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.background,
        contentColor = MaterialTheme.colorScheme.onBackground
    ) {
        LazyColumn(
            modifier = Modifier.fillMaxWidth().navigationBarsPadding(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        stringResource(R.string.workout_share_choose_title),
                        style = MaterialTheme.typography.headlineSmall
                    )
                }
            }
            item {
                AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            stringResource(R.string.workout_share_live_friend_title),
                            style = MaterialTheme.typography.titleMedium
                        )
                        Text(
                            stringResource(R.string.workout_share_live_friend_supporting_short),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (!isCloudAccount) {
                            Text(
                                stringResource(R.string.workout_share_friend_login_required),
                                style = MaterialTheme.typography.bodySmall
                            )
                        } else if (friends.isEmpty()) {
                            Text(
                                stringResource(R.string.workout_share_friend_empty),
                                style = MaterialTheme.typography.bodySmall
                            )
                        } else {
                            workoutShareFriends(friends, preferredFriendProfileId).forEach { friend ->
                                Button(
                                    onClick = { onStartLiveWithFriend(friend) },
                                    enabled = !isLiveInviteSending,
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text(
                                        stringResource(
                                            R.string.workout_share_live_friend_action,
                                            friend.displayName
                                        ),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                }
            }
            item {
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            }
            item {
                AppPanel(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            stringResource(R.string.workout_share_copy_friend_title),
                            style = MaterialTheme.typography.titleMedium
                        )
                        if (isCloudAccount && friends.isNotEmpty()) {
                            workoutShareFriends(friends, preferredFriendProfileId).forEach { friend ->
                                OutlinedButton(
                                    onClick = { onSendToFriend(friend) },
                                    enabled = !isWorkoutInviteSending,
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text(
                                        stringResource(
                                            R.string.workout_share_copy_friend_action,
                                            friend.displayName
                                        ),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                        OutlinedButton(onClick = onShareLink, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.workout_share_link_title))
                        }
                    }
                }
            }
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Default.Shield, contentDescription = null)
                    Text(
                        stringResource(R.string.workout_share_privacy_footer),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
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
