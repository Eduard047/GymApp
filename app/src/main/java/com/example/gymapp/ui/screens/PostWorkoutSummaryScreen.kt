package com.example.gymapp.ui.screens

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
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
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.viewmodel.CompletedMissionUiState
import com.example.gymapp.ui.viewmodel.NewBadgeUiState
import com.example.gymapp.ui.viewmodel.PostWorkoutSummaryUiState
import com.example.gymapp.util.DateTimeUtils
import java.util.Locale

@Composable
fun PostWorkoutSummaryScreen(
    uiState: PostWorkoutSummaryUiState,
    onViewWorkout: () -> Unit,
    onDone: () -> Unit,
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
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    HeroCard(uiState = uiState)
                }

                item {
                    SummaryMetrics(uiState = uiState)
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
                        title = stringResource(R.string.post_workout_rewards_title),
                        supporting = stringResource(R.string.post_workout_rewards_supporting)
                    )
                }

                if (uiState.completedMissions.isEmpty() && uiState.newBadges.isEmpty()) {
                    item {
                        EmptyStatePanel(
                            title = stringResource(R.string.post_workout_no_unlocks_title),
                            supporting = stringResource(R.string.post_workout_no_unlocks_supporting)
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
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Button(
                            onClick = onViewWorkout,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(text = stringResource(R.string.post_workout_view_workout))
                        }
                        OutlinedButton(
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
private fun HeroCard(uiState: PostWorkoutSummaryUiState) {
    HeroPanel(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                text = stringResource(R.string.post_workout_complete_title),
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onPrimary,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = DateTimeUtils.formatDate(uiState.sessionDate),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.92f)
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                InfoPill(
                    text = stringResource(R.string.post_workout_xp_gain, uiState.xpGained),
                    accent = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.weight(1f)
                )
                InfoPill(
                    text = stringResource(R.string.post_workout_level, uiState.currentLevel),
                    accent = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.weight(1f)
                )
            }
            if (uiState.leveledUp) {
                Text(
                    text = stringResource(
                        R.string.post_workout_level_up,
                        uiState.previousLevel,
                        uiState.currentLevel
                    ),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimary,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}

@Composable
private fun SummaryMetrics(uiState: PostWorkoutSummaryUiState) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            MetricTile(
                label = stringResource(R.string.post_workout_metric_xp_gained),
                value = stringResource(R.string.post_workout_xp_gain, uiState.xpGained),
                modifier = Modifier.weight(1f),
                emphasized = true
            )
            MetricTile(
                label = stringResource(R.string.post_workout_metric_current_title),
                value = uiState.levelTitle,
                modifier = Modifier.weight(1f)
            )
            MetricTile(
                label = stringResource(R.string.post_workout_metric_streak),
                value = stringResource(
                    R.string.post_workout_metric_streak_value,
                    uiState.streakDays
                ),
                modifier = Modifier.weight(1f)
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
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
            MetricTile(
                label = stringResource(R.string.post_workout_metric_volume),
                value = String.format(Locale.getDefault(), "%.0f", uiState.volume),
                modifier = Modifier.weight(1f)
            )
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
            Text(
                text = stringResource(R.string.post_workout_level_progress_title),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
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
            Text(
                text = stringResource(R.string.post_workout_momentum_title),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = streakMessage(uiState, context),
                style = MaterialTheme.typography.bodyLarge
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
                        uiState.comebackGapDays ?: 0,
                        String.format(Locale.getDefault(), "%.2f", uiState.comebackMultiplier),
                        uiState.comebackBonusXp
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
                Column(
                    horizontalAlignment = Alignment.End,
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    InfoPill(text = mission.cadence)
                    Text(
                        text = stringResource(R.string.post_workout_xp_gain, mission.rewardXp),
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold
                    )
                }
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
                        text = stringResource(R.string.post_workout_xp_gain, badge.rewardXp),
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
