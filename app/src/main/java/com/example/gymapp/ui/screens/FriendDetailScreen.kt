package com.example.gymapp.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.auth.SocialExerciseRecord
import com.example.gymapp.auth.SocialFriend
import com.example.gymapp.auth.SocialFriendDetails
import com.example.gymapp.auth.SocialRecentWorkout
import com.example.gymapp.auth.SocialFriendWorkout
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.GymMetric
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.MetricStrip
import com.example.gymapp.ui.components.ScreenHeader
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.SocialActionCard
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.asString
import java.text.NumberFormat
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

@Composable
internal fun FriendDetailScreen(
    friend: SocialFriend?,
    details: SocialFriendDetails?,
    friendWorkouts: List<SocialFriendWorkout>,
    friendWorkoutActivityRevision: String?,
    friendWorkoutDetailsAvailable: Boolean,
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
    var selectedWorkout by remember(friend?.profileId) {
        mutableStateOf<SocialFriendWorkout?>(null)
    }

    val authorizedSelectedWorkout = selectedWorkout?.takeIf { workout ->
        friend != null &&
            details?.sharing?.recentWorkouts == true &&
            details.activityUpdatedAt == friendWorkoutActivityRevision &&
            friendWorkoutDetailsAvailable &&
            friendWorkouts.any { it.workoutId == workout.workoutId }
    }
    LaunchedEffect(authorizedSelectedWorkout, selectedWorkout) {
        if (selectedWorkout != null && authorizedSelectedWorkout == null) {
            selectedWorkout = null
        }
    }
    authorizedSelectedWorkout?.let { workout ->
        BackHandler { selectedWorkout = null }
        FriendWorkoutDetail(
            friendName = friend?.displayName.orEmpty(),
            workout = workout,
            onBack = { selectedWorkout = null },
            modifier = modifier
        )
        return
    }

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
        } else if (friendWorkoutDetailsAvailable && friendWorkouts.isNotEmpty()) {
            items(
                friendWorkouts,
                key = { workout -> workout.workoutId }
            ) { workout ->
                FriendWorkoutCard(
                    workout = workout,
                    onOpen = { selectedWorkout = workout }
                )
            }
        } else {
            items(details.recentWorkouts) { workout ->
                FriendWorkoutSummaryCard(workout)
            }
            item {
                Text(
                    stringResource(R.string.friend_workout_sets_private),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
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
private fun FriendWorkoutCard(
    workout: SocialFriendWorkout,
    onOpen: () -> Unit
) {
    val localizedNames = workout.exercises.map { exercise ->
        localizedExerciseName(exercise.name)
    }
    AppPanel(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                localizedFriendActivityDay(workout.workoutDay),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                stringResource(
                    R.string.workout_invite_summary,
                    workout.exerciseCount,
                    workout.setCount
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                localizedNames.joinToString(" • "),
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                stringResource(R.string.friend_workout_open_action),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@Composable
private fun FriendWorkoutSummaryCard(workout: SocialRecentWorkout) {
    val localizedNames = workout.exercises.map { exercise ->
        localizedExerciseName(exercise.name)
    }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                localizedFriendActivityDay(workout.workoutDay),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                stringResource(
                    R.string.workout_invite_summary,
                    workout.exerciseCount,
                    workout.setCount
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
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

@Composable
private fun FriendWorkoutDetail(
    friendName: String,
    workout: SocialFriendWorkout,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    val numberFormat = remember {
        NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 }
    }
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = GymSpacing.ScreenHorizontal,
            vertical = GymSpacing.ScreenTop
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
    ) {
        item {
            TextButton(onClick = onBack) {
                Text(stringResource(R.string.cd_back))
            }
        }
        item {
            ScreenHeader(
                title = localizedFriendActivityDay(workout.workoutDay),
                supporting = stringResource(R.string.friend_workout_read_only, friendName)
            )
        }
        item {
            MetricStrip(
                metrics = listOf(
                    GymMetric(
                        stringResource(R.string.friend_workout_exercises_label),
                        workout.exerciseCount.toString()
                    ),
                    GymMetric(
                        stringResource(R.string.friend_workout_sets_label),
                        workout.setCount.toString()
                    )
                )
            )
        }
        if (workout.truncated) {
            item {
                Text(
                    stringResource(R.string.friend_workout_truncated),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        items(
            workout.exercises,
            key = { exercise -> "${exercise.catalogKey.orEmpty()}-${exercise.name}" }
        ) { exercise ->
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        ExerciseMediaPreview(
                            exerciseId = (
                                "${workout.workoutId}:${exercise.catalogKey.orEmpty()}:${exercise.name}"
                            ).hashCode().toLong(),
                            exerciseName = exercise.name,
                            ownerKey = "social-friend-read-only",
                            editable = false
                        )
                        Text(
                            localizedExerciseName(exercise.name),
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.titleMedium,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    exercise.sets.forEachIndexed { index, set ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Text(
                                stringResource(R.string.friend_workout_set_number, index + 1),
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Text(
                                stringResource(
                                    R.string.friend_workout_set_value,
                                    numberFormat.format(set.weightKg),
                                    set.reps
                                ),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }
                }
            }
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
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
            Text(
                stringResource(
                    R.string.friend_record_meta,
                    record.workoutCount,
                    localizedFriendActivityDay(record.lastWorkoutDay)
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

internal fun localizedFriendActivityDay(
    rawDay: String,
    locale: Locale = Locale.getDefault(),
    zoneId: ZoneId = ZoneId.systemDefault()
): String = runCatching {
    LocalDate.parse(rawDay)
        .atStartOfDay(zoneId)
        .toInstant()
        .toEpochMilli()
}.map { timestamp ->
    DateTimeUtils.formatDate(timestamp, locale, zoneId)
}.getOrElse { rawDay }

@Composable
private fun sharingLabel(shared: Boolean): String = stringResource(
    if (shared) R.string.friend_sharing_on else R.string.friend_sharing_off
)

private enum class FriendSafetyAction { Remove, Block }
