package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.repository.DashboardStats
import com.example.gymapp.ui.components.AchievementPreviewCard
import com.example.gymapp.ui.components.ActivityHeatmapCard
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.SoloProgressHero
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.launch

@Composable
fun WorkoutListScreen(
    uiState: WorkoutListUiState,
    onSessionClick: (Long) -> Unit,
    onPreviousMonth: () -> Unit,
    onCurrentMonth: () -> Unit,
    onNextMonth: () -> Unit,
    modifier: Modifier = Modifier
) {
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    var workoutsSelected by rememberSaveable { mutableStateOf(false) }
    // Fixed overview item count before the workout list header.
    val workoutSectionIndex = 4

    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        MonthSwitcher(
            monthLabel = uiState.monthLabel,
            onPreviousMonth = onPreviousMonth,
            onCurrentMonth = onCurrentMonth,
            onNextMonth = onNextMonth
        )

        WorkoutSectionSwitcher(
            sessionCount = uiState.sessions.size,
            workoutsSelected = workoutsSelected,
            onOverviewClick = {
                workoutsSelected = false
                coroutineScope.launch { listState.animateScrollToItem(0) }
            },
            onWorkoutListClick = {
                workoutsSelected = true
                coroutineScope.launch { listState.animateScrollToItem(workoutSectionIndex) }
            },
            modifier = Modifier.padding(horizontal = 12.dp)
        )

        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                horizontal = 12.dp,
                vertical = 10.dp
            ),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            item {
                SoloProgressHero(progress = uiState.soloProgress)
            }

            item {
                DashboardCard(stats = uiState.dashboardStats)
            }

            item {
                ActivityHeatmapCard(heatmap = uiState.activityHeatmap)
            }

            item {
                AchievementPreviewCard(achievements = uiState.achievements)
            }

            item {
                WorkoutSectionHeader(sessionCount = uiState.sessions.size)
            }

            if (uiState.sessions.isEmpty()) {
                item {
                    EmptyStatePanel(
                        title = stringResource(R.string.empty_workouts),
                        supporting = stringResource(R.string.dashboard_subtitle)
                    )
                }
            } else {
                items(
                    items = uiState.sessions,
                    key = { it.session.id }
                ) { sessionSummary ->
                    AppPanel(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSessionClick(sessionSummary.session.id) },
                        highlighted = true
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = stringResource(
                                        R.string.session_item_title,
                                        DateTimeUtils.formatDate(sessionSummary.session.date)
                                    ),
                                    style = MaterialTheme.typography.titleMedium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                                InfoPill(text = stringResource(R.string.stats_sets, sessionSummary.setCount))
                            }

                            Text(
                                text = sessionSummary.session.note
                                    ?.takeIf { it.isNotBlank() }
                                    ?.let { stringResource(R.string.details_note, it) }
                                    ?: stringResource(R.string.details_no_note),
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = stringResource(
                                        R.string.stats_exercises,
                                        sessionSummary.exerciseCount
                                    ),
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.bodySmall,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(
                                        R.string.stats_sets,
                                        sessionSummary.setCount
                                    ),
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.bodySmall,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(
                                        R.string.stats_volume,
                                        sessionSummary.totalVolume
                                    ),
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.bodySmall,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WorkoutSectionSwitcher(
    sessionCount: Int,
    workoutsSelected: Boolean,
    onOverviewClick: () -> Unit,
    onWorkoutListClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    AppPanel(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            WorkoutSectionChip(
                title = stringResource(R.string.workout_switch_overview_title),
                supporting = stringResource(R.string.workout_switch_overview_supporting),
                selected = !workoutsSelected,
                onClick = onOverviewClick,
                modifier = Modifier.weight(1f)
            )
            WorkoutSectionChip(
                title = stringResource(R.string.workout_switch_list_title),
                supporting = if (sessionCount == 1) {
                    stringResource(R.string.workout_switch_list_supporting_one)
                } else {
                    stringResource(R.string.workout_switch_list_supporting_many, sessionCount)
                },
                selected = workoutsSelected,
                onClick = onWorkoutListClick,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun WorkoutSectionChip(
    title: String,
    supporting: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        color = if (selected) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
        } else {
            MaterialTheme.colorScheme.surface.copy(alpha = 0.86f)
        },
        shape = MaterialTheme.shapes.large,
        border = BorderStroke(
            width = 1.dp,
            color = if (selected) {
                MaterialTheme.colorScheme.primary.copy(alpha = 0.24f)
            } else {
                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.72f)
            }
        )
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                color = if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurface
                }
            )
            Text(
                text = supporting,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun WorkoutSectionHeader(
    sessionCount: Int,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text(
                    text = stringResource(R.string.workout_section_header_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = if (sessionCount == 0) {
                        stringResource(R.string.workout_section_header_empty)
                    } else {
                        stringResource(R.string.workout_section_header_hint)
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            InfoPill(
                text = if (sessionCount == 1) {
                    stringResource(R.string.workout_section_header_count_one)
                } else {
                    stringResource(R.string.workout_section_header_count_many, sessionCount)
                }
            )
        }
    }
}

@Composable
private fun DashboardCard(
    stats: DashboardStats,
    modifier: Modifier = Modifier
) {
    HeroPanel(modifier = modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = stringResource(R.string.dashboard_title),
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onPrimary
            )
            Text(
                text = stringResource(R.string.dashboard_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.kpi_workouts),
                    value = stats.workoutCount.toString(),
                    modifier = Modifier.weight(1f),
                    emphasized = true,
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.kpi_streak),
                    value = stringResource(
                        R.string.kpi_streak_weekly_value,
                        stats.weeklyStreakWeeks
                    ),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.kpi_total_volume),
                    value = stringResource(R.string.kpi_volume_value, stats.totalVolume),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
                MetricTile(
                    label = stringResource(R.string.kpi_avg_intensity),
                    value = stringResource(R.string.kpi_avg_intensity_value, stats.averageIntensity),
                    modifier = Modifier.weight(1f),
                    onHero = true
                )
            }
        }
    }
}
