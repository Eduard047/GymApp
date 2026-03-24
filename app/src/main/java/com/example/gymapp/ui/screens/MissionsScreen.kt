package com.example.gymapp.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.viewmodel.MissionProgressUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState

@Composable
fun MissionsScreen(
    uiState: WorkoutListUiState,
    onOpenRanks: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val dailyMissions = uiState.dailyMissions
    val weeklyMissions = uiState.weeklyMissions
    val monthlyMissions = uiState.monthlyMissions
    val allMissions = dailyMissions + weeklyMissions + monthlyMissions
    val completedCount = allMissions.count { it.isComplete }
    val openCount = allMissions.size - completedCount
    val completedMissionXp = allMissions.filter { it.isComplete }.sumOf { it.xpReward }
    val dailyCompletedCount = dailyMissions.count { it.isComplete }
    val weeklyCompletedCount = weeklyMissions.count { it.isComplete }
    val monthlyCompletedCount = monthlyMissions.count { it.isComplete }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            horizontal = 12.dp,
            vertical = 10.dp
        ),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            text = stringResource(R.string.title_missions),
                            style = MaterialTheme.typography.headlineMedium,
                            color = MaterialTheme.colorScheme.onPrimary
                        )
                        Text(
                            text = stringResource(R.string.missions_board_supporting),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.88f)
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        MetricTile(
                            label = stringResource(R.string.missions_total_label),
                            value = allMissions.size.toString(),
                            modifier = Modifier.weight(1f),
                            emphasized = true,
                            onHero = true
                        )
                        MetricTile(
                            label = stringResource(R.string.missions_completed_label),
                            value = completedCount.toString(),
                            modifier = Modifier.weight(1f),
                            onHero = true
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        MetricTile(
                            label = stringResource(R.string.missions_open_label),
                            value = openCount.toString(),
                            modifier = Modifier.weight(1f),
                            onHero = true
                        )
                        MetricTile(
                            label = stringResource(R.string.missions_progress_label),
                            value = stringResource(
                                R.string.missions_progress_value,
                                completedCount,
                                allMissions.size
                            ),
                            modifier = Modifier.weight(1f),
                            onHero = true
                        )
                    }

                    Text(
                        text = stringResource(
                            R.string.missions_overall_progress,
                            dailyCompletedCount,
                            dailyMissions.size,
                            weeklyCompletedCount,
                            weeklyMissions.size,
                            monthlyCompletedCount,
                            monthlyMissions.size
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.82f)
                    )
                    Text(
                        text = stringResource(
                            R.string.missions_xp_progress,
                            completedMissionXp
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.82f)
                    )
                }
            }
        }

        item {
            AppPanel(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClickLabel = stringResource(R.string.action_view_ranks)) {
                        onOpenRanks()
                    },
                highlighted = true
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                text = stringResource(R.string.missions_ranks_card_title),
                                style = MaterialTheme.typography.titleMedium
                            )
                            Text(
                                text = stringResource(R.string.missions_ranks_card_supporting),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }

                        InfoPill(text = stringResource(R.string.action_view_ranks))
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        MetricTile(
                            label = stringResource(R.string.ranks_current_level_label),
                            value = uiState.soloProgress.level.toString(),
                            modifier = Modifier.weight(1f)
                        )
                        MetricTile(
                            label = stringResource(R.string.post_workout_metric_current_title),
                            value = uiState.soloProgress.title,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }

        if (allMissions.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.missions_empty_title),
                    supporting = stringResource(R.string.missions_empty_supporting)
                )
            }
        } else {
            item {
                MissionSectionHeader(
                    title = stringResource(R.string.missions_daily_title),
                    supporting = stringResource(R.string.missions_daily_supporting),
                    completedCount = dailyCompletedCount,
                    totalCount = dailyMissions.size
                )
            }

            items(
                items = dailyMissions,
                key = { "daily-${it.id}" }
            ) { mission ->
                MissionCard(mission = mission)
            }

            item {
                MissionSectionHeader(
                    title = stringResource(R.string.missions_weekly_title),
                    supporting = stringResource(R.string.missions_weekly_supporting),
                    completedCount = weeklyCompletedCount,
                    totalCount = weeklyMissions.size
                )
            }

            items(
                items = weeklyMissions,
                key = { "weekly-${it.id}" }
            ) { mission ->
                MissionCard(mission = mission)
            }

            item {
                MissionSectionHeader(
                    title = stringResource(R.string.missions_monthly_title),
                    supporting = stringResource(R.string.missions_monthly_supporting),
                    completedCount = monthlyCompletedCount,
                    totalCount = monthlyMissions.size
                )
            }

            items(
                items = monthlyMissions,
                key = { "monthly-${it.id}" }
            ) { mission ->
                MissionCard(mission = mission)
            }
        }
    }
}

@Composable
private fun MissionSectionHeader(
    title: String,
    supporting: String,
    completedCount: Int,
    totalCount: Int,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = supporting,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            InfoPill(
                text = stringResource(
                    R.string.missions_section_progress,
                    completedCount,
                    totalCount
                )
            )
        }
    }
}

@Composable
private fun MissionCard(
    mission: MissionProgressUiModel,
    modifier: Modifier = Modifier
) {
    val accentColor = if (mission.isComplete) {
        MaterialTheme.colorScheme.tertiary
    } else {
        MaterialTheme.colorScheme.primary
    }
    val statusText = if (mission.isComplete) {
        stringResource(R.string.missions_status_completed)
    } else {
        stringResource(R.string.missions_status_in_progress)
    }

    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = mission.isComplete
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = mission.title,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = mission.summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                InfoPill(
                    text = statusText,
                    accent = accentColor
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                InfoPill(
                    text = mission.cadenceLabel,
                    accent = accentColor
                )
                InfoPill(
                    text = stringResource(R.string.missions_xp_reward, mission.xpReward),
                    accent = accentColor
                )
                Text(
                    text = mission.progressLabel,
                    modifier = Modifier.padding(top = 4.dp),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            LinearProgressIndicator(
                progress = { mission.progressFraction },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp),
                color = accentColor,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )
        }
    }
}
