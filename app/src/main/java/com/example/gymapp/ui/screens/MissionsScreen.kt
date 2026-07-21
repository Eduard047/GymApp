package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.AchievementPreviewCard
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.theme.GymCompactShape
import com.example.gymapp.ui.viewmodel.MissionProgressUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState

@Composable
fun MissionsScreen(
    uiState: WorkoutListUiState,
    onOpenRanks: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    var selectedPeriodIndex by rememberSaveable { mutableIntStateOf(0) }
    val selectedPeriod = MissionPeriod.entries.getOrElse(selectedPeriodIndex) {
        MissionPeriod.Daily
    }
    val selectedMissions = when (selectedPeriod) {
        MissionPeriod.Daily -> uiState.dailyMissions
        MissionPeriod.Weekly -> uiState.weeklyMissions
        MissionPeriod.Monthly -> uiState.monthlyMissions
    }
    val levelProgress = uiState.soloProgress.progressFraction
        .takeIf(Float::isFinite)
        ?.coerceIn(0f, 1f)
        ?: 0f

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = 16.dp,
            vertical = 12.dp
        ),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.Top,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                text = uiState.soloProgress.title,
                                style = MaterialTheme.typography.headlineSmall,
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = stringResource(
                                    R.string.post_workout_level,
                                    uiState.soloProgress.level
                                ),
                                style = MaterialTheme.typography.bodyMedium,
                                color = Color.White.copy(alpha = 0.78f)
                            )
                        }

                        Surface(
                            onClick = onOpenRanks,
                            modifier = Modifier.size(48.dp),
                            shape = CircleShape,
                            color = Color.White.copy(alpha = 0.12f),
                            contentColor = Color.White,
                            border = BorderStroke(1.dp, Color.White.copy(alpha = 0.18f))
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = Icons.Default.EmojiEvents,
                                    contentDescription = stringResource(R.string.action_view_ranks),
                                    modifier = Modifier.size(23.dp)
                                )
                            }
                        }
                    }

                    LinearProgressIndicator(
                        progress = { levelProgress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(7.dp),
                        color = Color.White,
                        trackColor = Color.White.copy(alpha = 0.18f)
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        MetricTile(
                            label = stringResource(R.string.solo_total_xp),
                            value = uiState.soloProgress.totalXp.toString(),
                            modifier = Modifier.weight(1f),
                            emphasized = true,
                            onHero = true
                        )
                        MetricTile(
                            label = stringResource(R.string.kpi_streak),
                            value = stringResource(
                                R.string.kpi_streak_value,
                                uiState.soloProgress.streakDays
                            ),
                            modifier = Modifier.weight(1f),
                            onHero = true
                        )
                    }
                }
            }
        }

        item {
            MissionPeriodSelector(
                selectedPeriod = selectedPeriod,
                onPeriodSelected = { selectedPeriodIndex = it.ordinal }
            )
        }

        if (selectedMissions.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.missions_empty_title),
                    supporting = stringResource(R.string.missions_empty_supporting)
                )
            }
        } else {
            items(
                items = selectedMissions,
                key = { "${selectedPeriod.name}-${it.id}" }
            ) { mission ->
                MissionCard(mission = mission)
            }
        }

        item {
            AchievementPreviewCard(achievements = uiState.achievements)
        }
    }
}

@Composable
private fun MissionPeriodSelector(
    selectedPeriod: MissionPeriod,
    onPeriodSelected: (MissionPeriod) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(GymCompactShape)
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.58f))
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.66f),
                shape = GymCompactShape
            )
            .padding(3.dp)
            .selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        MissionPeriod.entries.forEach { period ->
            val selected = period == selectedPeriod
            Surface(
                modifier = Modifier
                    .weight(1f)
                    .selectable(
                        selected = selected,
                        onClick = { onPeriodSelected(period) },
                        role = Role.Tab
                    ),
                shape = GymCompactShape,
                color = if (selected) {
                    MaterialTheme.colorScheme.surface
                } else {
                    Color.Transparent
                },
                contentColor = if (selected) {
                    MaterialTheme.colorScheme.onSurface
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                tonalElevation = if (selected) 2.dp else 0.dp
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 48.dp)
                        .padding(horizontal = 4.dp, vertical = 10.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = stringResource(period.titleRes),
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

@Composable
private fun MissionCard(
    mission: MissionProgressUiModel,
    modifier: Modifier = Modifier
) {
    val accentColor = if (mission.isComplete) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.secondary
    }
    val statusText = if (mission.isComplete) {
        stringResource(R.string.missions_status_completed)
    } else {
        stringResource(R.string.missions_status_in_progress)
    }
    val progressValue = mission.progressFraction
        .takeIf(Float::isFinite)
        ?.coerceIn(0f, 1f)
        ?: 0f
    val accessibilityState = "${mission.cadenceLabel}. $statusText"

    AppPanel(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                stateDescription = accessibilityState
                progressBarRangeInfo = ProgressBarRangeInfo(progressValue, 0f..1f)
            },
        highlighted = mission.isComplete
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(11.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    modifier = Modifier.size(28.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (mission.isComplete) {
                            Icons.Default.CheckCircle
                        } else {
                            Icons.Default.TrackChanges
                        },
                        contentDescription = null,
                        modifier = Modifier.size(24.dp),
                        tint = accentColor
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = mission.title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = mission.summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                InfoPill(
                    text = stringResource(R.string.post_workout_xp_gain, mission.xpReward),
                    accent = accentColor
                )
            }

            LinearProgressIndicator(
                progress = { progressValue },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(7.dp),
                color = accentColor,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )

            Text(
                text = mission.progressLabel,
                style = MaterialTheme.typography.labelMedium,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

private enum class MissionPeriod(val titleRes: Int) {
    Daily(R.string.missions_daily_short),
    Weekly(R.string.missions_weekly_short),
    Monthly(R.string.missions_monthly_short)
}
