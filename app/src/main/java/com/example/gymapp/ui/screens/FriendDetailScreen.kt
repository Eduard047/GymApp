package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.SocialExerciseRecord
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.SocialFriendDetails
import com.example.gymapp.auth.SocialRecentWorkout
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.GymMetric
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.MetricStrip
import com.example.gymapp.ui.components.ScreenHeader
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.SocialActionCard
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.asString
import java.text.NumberFormat

@Composable
internal fun FriendDetailScreen(
    friend: SocialFriend?,
    details: SocialFriendDetails?,
    isLoading: Boolean,
    error: LocalizedText?,
    actionInFlight: Boolean,
    onRetry: () -> Unit,
    onChooseWorkout: (SocialFriend) -> Unit,
    onBuildLiveWorkout: (SocialFriend) -> Unit,
    onRemove: (SocialFriend) -> Unit,
    onBlock: (SocialFriend) -> Unit,
    modifier: Modifier = Modifier
) {
    var confirmAction by remember { mutableStateOf<FriendSafetyAction?>(null) }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = GymSpacing.ScreenHorizontal,
            vertical = GymSpacing.ScreenTop
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
    ) {
        if (friend == null) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friend_unavailable_title),
                    supporting = stringResource(R.string.friend_unavailable_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
            return@LazyColumn
        }

        item {
            Column(verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)) {
                ScreenHeader(
                    title = friend.displayName
                )
                if (friend.statsAvailable) {
                    MetricStrip(
                        metrics = listOf(
                            GymMetric(
                                stringResource(R.string.ranks_current_level_label),
                                (friend.level ?: 1).toString()
                            ),
                            GymMetric(
                                stringResource(R.string.solo_total_xp),
                                (friend.xp ?: 0).toString(),
                                emphasized = true
                            ),
                            GymMetric(
                                stringResource(R.string.kpi_workouts),
                                (friend.workouts ?: 0).toString()
                            )
                        )
                    )
                } else {
                    Text(
                        stringResource(R.string.friend_stats_private),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        item {
            SocialActionCard(
                eyebrow = stringResource(R.string.friend_train_eyebrow),
                title = stringResource(R.string.friend_train_title),
                supporting = stringResource(R.string.friend_train_supporting),
                primaryLabel = stringResource(R.string.friend_choose_workout_action),
                onPrimary = { onChooseWorkout(friend) },
                secondaryLabel = stringResource(R.string.friend_build_live_action),
                onSecondary = { onBuildLiveWorkout(friend) },
                enabled = !actionInFlight
            )
        }

        error?.let { message ->
            item {
                AppPanel(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(message.asString(), color = MaterialTheme.colorScheme.error)
                        Button(onClick = onRetry, enabled = !isLoading) {
                            Text(stringResource(R.string.action_retry))
                        }
                    }
                }
            }
        }

        if (isLoading && details == null) {
            item {
                LoadingStatePanel()
            }
            return@LazyColumn
        }

        if (details == null) return@LazyColumn

        item {
            SharingCard(details)
        }

        item {
            SectionTitle(
                eyebrow = stringResource(R.string.friend_recent_eyebrow),
                title = stringResource(R.string.friend_recent_title)
            )
        }
        if (!details.sharing.recentWorkouts) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friend_section_private_title),
                    supporting = stringResource(R.string.friend_recent_private_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        } else if (details.activityUpdatedAt == null) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friend_activity_unavailable_title),
                    supporting = stringResource(R.string.friend_activity_unavailable_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        } else if (details.recentWorkouts.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friend_recent_empty_title),
                    supporting = stringResource(R.string.friend_recent_empty_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        } else {
            itemsIndexed(
                details.recentWorkouts,
                key = { index, workout -> "workout-$index-${workout.workoutDay}" }
            ) { _, workout ->
                RecentWorkoutCard(workout)
            }
        }

        item {
            SectionTitle(
                eyebrow = stringResource(R.string.friend_records_eyebrow),
                title = stringResource(R.string.friend_records_title),
                supporting = stringResource(R.string.friend_records_supporting)
            )
        }
        if (!details.sharing.records) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friend_section_private_title),
                    supporting = stringResource(R.string.friend_records_private_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        } else if (details.activityUpdatedAt == null) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friend_activity_unavailable_title),
                    supporting = stringResource(R.string.friend_activity_unavailable_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        } else if (details.exerciseRecords.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.friend_records_empty_title),
                    supporting = stringResource(R.string.friend_records_empty_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        } else {
            items(
                details.exerciseRecords,
                key = { "record-${it.catalogKey.orEmpty()}-${it.name}" }
            ) { record ->
                ExerciseRecordCard(record)
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    SectionTitle(
                        eyebrow = stringResource(R.string.friends_safety_eyebrow),
                        title = stringResource(R.string.friend_manage_title),
                        supporting = stringResource(R.string.friend_manage_supporting)
                    )
                    OutlinedButton(
                        onClick = { confirmAction = FriendSafetyAction.Remove },
                        enabled = !actionInFlight,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.friend_remove_action))
                    }
                    OutlinedButton(
                        onClick = { confirmAction = FriendSafetyAction.Block },
                        enabled = !actionInFlight,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.friend_block_action))
                    }
                }
            }
        }
    }

    val action = confirmAction
    if (action != null && friend != null) {
        AlertDialog(
            onDismissRequest = { confirmAction = null },
            title = {
                Text(
                    stringResource(
                        if (action == FriendSafetyAction.Remove) R.string.friend_remove_confirm_title
                        else R.string.friend_block_confirm_title
                    )
                )
            },
            text = {
                Text(
                    stringResource(
                        if (action == FriendSafetyAction.Remove) {
                            R.string.friend_remove_confirm_supporting
                        } else {
                            R.string.friend_block_confirm_supporting
                        },
                        friend.displayName
                    )
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmAction = null
                        if (action == FriendSafetyAction.Remove) onRemove(friend) else onBlock(friend)
                    }
                ) {
                    Text(
                        stringResource(
                            if (action == FriendSafetyAction.Remove) R.string.friend_remove_action
                            else R.string.friend_block_action
                        )
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmAction = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

@Composable
private fun SharingCard(details: SocialFriendDetails) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(stringResource(R.string.friend_sharing_title), style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(
                    R.string.friend_sharing_summary,
                    sharingLabel(details.sharing.progress),
                    sharingLabel(details.sharing.recentWorkouts),
                    sharingLabel(details.sharing.records)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun RecentWorkoutCard(workout: SocialRecentWorkout) {
    val localizedNames = workout.exercises.map { exercise ->
        localizedExerciseName(exercise.name)
    }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(workout.workoutDay, style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(
                    R.string.workout_invite_summary,
                    workout.exerciseCount,
                    workout.setCount
                ),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                localizedNames.joinToString(" • "),
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

internal sealed interface FriendRecordMetric {
    data class BestWeight(val kilograms: Double) : FriendRecordMetric
    data class BestRepetitions(val repetitions: Int) : FriendRecordMetric
}

internal fun friendRecordMetrics(record: SocialExerciseRecord): List<FriendRecordMetric> = listOf(
    FriendRecordMetric.BestWeight(record.bestWeightKg),
    FriendRecordMetric.BestRepetitions(record.bestReps)
)

@Composable
private fun ExerciseRecordCard(record: SocialExerciseRecord) {
    val numberFormat = remember { NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 } }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Text(
                localizedExerciseName(record.name),
                style = MaterialTheme.typography.titleMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            friendRecordMetrics(record).forEach { metric ->
                Text(
                    text = when (metric) {
                        is FriendRecordMetric.BestWeight -> stringResource(
                            R.string.friend_record_best_weight,
                            numberFormat.format(metric.kilograms)
                        )
                        is FriendRecordMetric.BestRepetitions -> stringResource(
                            R.string.friend_record_best_repetitions,
                            metric.repetitions
                        )
                    },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Text(
                stringResource(
                    R.string.friend_record_meta,
                    record.workoutCount,
                    record.lastWorkoutDay
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun sharingLabel(shared: Boolean): String = stringResource(
    if (shared) R.string.friend_sharing_on else R.string.friend_sharing_off
)

private enum class FriendSafetyAction { Remove, Block }
