package com.example.gymapp.ui.screens

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.repository.BadgeRarity
import com.example.gymapp.data.repository.WorkoutFeedback
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.WorkoutComparisonCard
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.CompletedMissionUiState
import com.example.gymapp.ui.viewmodel.NewBadgeUiState
import com.example.gymapp.ui.viewmodel.PostWorkoutMuscleUiState
import com.example.gymapp.ui.viewmodel.PostWorkoutPrUiState
import com.example.gymapp.ui.viewmodel.PostWorkoutSummaryUiState
import com.example.gymapp.util.DateTimeUtils
import java.util.Locale

@Composable
fun PostWorkoutSummaryScreen(
    uiState: PostWorkoutSummaryUiState,
    exerciseMediaOwnerKey: String,
    onViewWorkout: () -> Unit,
    onDone: () -> Unit,
    onFeedbackSelected: (WorkoutFeedback) -> Unit,
    modifier: Modifier = Modifier
) {
    when {
        uiState.isLoading -> {
            Column(
                modifier = modifier.fillMaxSize(),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator()
            }
        }

        !uiState.isSessionFound -> {
            Column(
                modifier = modifier
                    .fillMaxSize()
                    .padding(12.dp),
                verticalArrangement = Arrangement.Center
            ) {
                EmptyStatePanel(
                    title = stringResource(R.string.post_workout_unavailable_title),
                    supporting = stringResource(R.string.post_workout_unavailable_supporting)
                )
            }
        }

        else -> {
            LazyColumn(
                modifier = modifier.fillMaxSize(),
                contentPadding = PaddingValues(start = 14.dp, top = 12.dp, end = 14.dp, bottom = 30.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                item {
                    HeroCard(uiState = uiState)
                }

                item {
                    SummaryMetrics(uiState = uiState)
                }

                item {
                    WorkoutFeedbackCard(
                        selected = uiState.feedback,
                        onSelected = onFeedbackSelected
                    )
                }

                uiState.workoutComparison?.let { comparison ->
                    item {
                        WorkoutComparisonCard(comparison = comparison)
                    }
                }

                item {
                    WorkoutImpactCard(uiState = uiState)
                }

                if (uiState.personalRecords.isNotEmpty()) {
                    item {
                        PersonalRecordsCard(
                            records = uiState.personalRecords,
                            exerciseMediaOwnerKey = exerciseMediaOwnerKey
                        )
                    }
                }

                item {
                    LevelProgressCard(uiState = uiState)
                }

                item {
                    MomentumCard(uiState = uiState)
                }

                item {
                    SectionTitle(
                        eyebrow = stringResource(R.string.post_workout_rewards_eyebrow),
                        title = stringResource(R.string.post_workout_rewards_title)
                    )
                }

                if (uiState.completedMissions.isEmpty() && uiState.newBadges.isEmpty()) {
                    item {
                        EmptyStatePanel(
                            title = stringResource(R.string.post_workout_no_unlocks_title)
                        )
                    }
                }

                if (uiState.completedMissions.isNotEmpty()) {
                    items(
                        items = uiState.completedMissions,
                        key = { mission -> mission.cadence + mission.title }
                    ) { mission ->
                        MissionCard(mission = mission)
                    }
                }

                if (uiState.newBadges.isNotEmpty()) {
                    items(
                        items = uiState.newBadges,
                        key = { badge -> badge.name + badge.title }
                    ) { badge ->
                        BadgeCard(badge = badge)
                    }
                }

                item {
                    Column(
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        OutlinedButton(
                            onClick = onViewWorkout,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(text = stringResource(R.string.post_workout_view_workout))
                        }
                        Button(
                            onClick = onDone,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(text = stringResource(R.string.post_workout_back_to_workouts))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WorkoutFeedbackCard(
    selected: WorkoutFeedback?,
    onSelected: (WorkoutFeedback) -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = selected != null) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.workout_feedback_title),
                style = MaterialTheme.typography.titleMedium
            )
            GymSegmentedControl(
                items = listOf(
                    GymSegmentItem<WorkoutFeedback?>(
                        WorkoutFeedback.Easy,
                        stringResource(R.string.workout_feedback_easy)
                    ),
                    GymSegmentItem<WorkoutFeedback?>(
                        WorkoutFeedback.Normal,
                        stringResource(R.string.workout_feedback_normal)
                    ),
                    GymSegmentItem<WorkoutFeedback?>(
                        WorkoutFeedback.Hard,
                        stringResource(R.string.workout_feedback_hard)
                    )
                ),
                selected = selected,
                onSelected = { value -> value?.let(onSelected) }
            )
        }
    }
}

@Composable
private fun HeroCard(uiState: PostWorkoutSummaryUiState) {
    HeroPanel(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(38.dp)
                )
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        text = stringResource(R.string.post_workout_complete_title),
                        style = MaterialTheme.typography.headlineMedium,
                        color = Color.White,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = DateTimeUtils.formatLongDate(uiState.sessionDate),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.82f)
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_xp_gained),
                    value = stringResource(R.string.post_workout_xp_gain, uiState.xpGained),
                    modifier = Modifier.weight(1f),
                    emphasized = true,
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.post_workout_level_progress_title),
                    value = stringResource(R.string.post_workout_level, uiState.currentLevel),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_current_title),
                    value = uiState.levelTitle,
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.solo_streak_label),
                    value = stringResource(
                        R.string.solo_streak_weekly_value,
                        uiState.weeklyStreakWeeks
                    ),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }
            if (uiState.leveledUp) {
                InfoPill(
                    text = stringResource(
                        R.string.post_workout_level_up,
                        uiState.previousLevel,
                        uiState.currentLevel
                    ),
                    accent = Color.White
                )
            }
        }
    }
}

@Composable
private fun SummaryMetrics(uiState: PostWorkoutSummaryUiState) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.title_post_workout_summary),
                title = stringResource(R.string.progress_summary_title),
                supporting = uiState.topMuscleLabel?.let {
                    stringResource(R.string.post_workout_top_muscle, it)
                } ?: stringResource(R.string.post_workout_no_muscle_impact)
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_exercises),
                    value = uiState.exerciseCount.toString(),
                    modifier = Modifier.weight(1f)
                )
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_sets),
                    value = uiState.setCount.toString(),
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.post_workout_metric_volume),
                    value = String.format(Locale.getDefault(), "%.0f", uiState.volume),
                    modifier = Modifier.weight(1f),
                    emphasized = true
                )
                MetricTile(
                    label = stringResource(R.string.muscle_heatmap_title),
                    value = uiState.topMuscleLabel ?: "—",
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun WorkoutImpactCard(uiState: PostWorkoutSummaryUiState) {
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = uiState.muscles.isNotEmpty()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.muscle_heatmap_title),
                title = stringResource(R.string.post_workout_impact_title),
                supporting = uiState.topMuscleLabel?.let {
                    stringResource(R.string.post_workout_top_muscle, it)
                } ?: stringResource(R.string.post_workout_no_muscle_impact)
            )
            uiState.muscles.take(5).forEach { muscle ->
                MuscleImpactRow(muscle = muscle)
            }
        }
    }
}

@Composable
private fun MuscleImpactRow(muscle: PostWorkoutMuscleUiState) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = muscle.label,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
                maxLines = 1
            )
            Text(
                text = stringResource(R.string.post_workout_muscle_load, muscle.load, muscle.sets),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary
            )
        }
        LinearProgressIndicator(
            progress = { muscle.intensity.coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth()
        )
    }
}

@Composable
private fun PersonalRecordsCard(
    records: List<PostWorkoutPrUiState>,
    exerciseMediaOwnerKey: String
) {
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.post_workout_rewards_eyebrow),
                title = stringResource(R.string.post_workout_pr_title)
            )
            records.take(5).forEach { record ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ExerciseMediaPreview(
                        exerciseId = record.exerciseId,
                        exerciseName = record.exerciseName,
                        ownerKey = exerciseMediaOwnerKey,
                        width = 64.dp,
                        height = 54.dp
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp)
                    ) {
                        Text(
                            text = localizedExerciseName(record.exerciseName),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1
                        )
                        Text(
                            text = record.previousBest?.let {
                                stringResource(R.string.post_workout_pr_previous, it)
                            } ?: stringResource(R.string.post_workout_pr_first),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    InfoPill(
                        text = stringResource(R.string.progress_weight_value, record.weight),
                        accent = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }
    }
}

@Composable
private fun LevelProgressCard(uiState: PostWorkoutSummaryUiState) {
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = uiState.leveledUp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.progress_summary_title),
                title = stringResource(R.string.post_workout_level_progress_title),
                supporting = stringResource(
                    R.string.post_workout_xp_to_next,
                    uiState.xpToNextLevel
                )
            )
            Text(
                text = stringResource(
                    R.string.post_workout_level_progress_value,
                    uiState.currentLevel,
                    uiState.levelTitle
                ),
                style = MaterialTheme.typography.bodyLarge
            )
            LinearProgressIndicator(
                progress = { uiState.levelProgress.coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth()
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(
                        R.string.post_workout_xp_into_level,
                        uiState.xpIntoLevel
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = stringResource(
                        R.string.post_workout_xp_to_next,
                        uiState.xpToNextLevel
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Medium
                )
            }
            if (uiState.nextTitle != null) {
                Text(
                    text = stringResource(R.string.post_workout_next_title, uiState.nextTitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun MomentumCard(uiState: PostWorkoutSummaryUiState) {
    val context = LocalContext.current

    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.post_workout_metric_streak),
                title = stringResource(R.string.post_workout_momentum_title),
                supporting = streakMessage(uiState, context)
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                InfoPill(
                    text = stringResource(
                        if (uiState.activeToday) {
                            R.string.post_workout_logged_today
                        } else {
                            R.string.post_workout_logged_recently
                        }
                    ),
                    modifier = Modifier.weight(1f)
                )
                InfoPill(
                    text = stringResource(
                        R.string.post_workout_best_streak,
                        uiState.longestStreakDays
                    ),
                    modifier = Modifier.weight(1f),
                    accent = MaterialTheme.colorScheme.secondary
                )
            }
            if (uiState.isComeback) {
                Text(
                    text = stringResource(
                        R.string.post_workout_comeback,
                        uiState.comebackGapDays ?: 0
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

@Composable
private fun MissionCard(mission: CompletedMissionUiState) {
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = mission.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = mission.description,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                InfoPill(text = mission.cadence)
            }
        }
    }
}

@Composable
private fun BadgeCard(badge: NewBadgeUiState) {
    val context = LocalContext.current

    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true,
        containerColor = badge.rarity.color().copy(alpha = 0.12f)
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = badge.name,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = badge.title,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    InfoPill(
                        text = badge.rarity.label(context),
                        accent = badge.rarity.color()
                    )
                    Text(
                        text = stringResource(R.string.post_workout_reward_points, badge.rewardXp),
                        style = MaterialTheme.typography.titleSmall,
                        color = badge.rarity.color(),
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

private fun streakMessage(uiState: PostWorkoutSummaryUiState, context: Context): String {
    return when {
        uiState.streakExtended && uiState.streakDays > 1 -> context.getString(
            R.string.post_workout_streak_extended,
            uiState.streakDays
        )
        uiState.streakDays == 1 -> context.getString(R.string.post_workout_streak_fresh)
        uiState.streakDays > 1 -> context.getString(
            R.string.post_workout_streak_current,
            uiState.streakDays
        )
        else -> context.getString(R.string.post_workout_streak_return)
    }
}

private fun BadgeRarity.label(context: Context): String {
    return when (this) {
        BadgeRarity.COMMON -> context.getString(R.string.badge_rarity_common)
        BadgeRarity.UNCOMMON -> context.getString(R.string.badge_rarity_uncommon)
        BadgeRarity.RARE -> context.getString(R.string.badge_rarity_rare)
        BadgeRarity.EPIC -> context.getString(R.string.badge_rarity_epic)
        BadgeRarity.LEGENDARY -> context.getString(R.string.badge_rarity_legendary)
    }
}

@Composable
private fun BadgeRarity.color(): Color {
    return when (this) {
        BadgeRarity.COMMON -> MaterialTheme.colorScheme.secondary
        BadgeRarity.UNCOMMON -> MaterialTheme.colorScheme.primary
        BadgeRarity.RARE -> MaterialTheme.colorScheme.tertiary
        BadgeRarity.EPIC -> MaterialTheme.colorScheme.primary
        BadgeRarity.LEGENDARY -> MaterialTheme.colorScheme.error
    }
}
