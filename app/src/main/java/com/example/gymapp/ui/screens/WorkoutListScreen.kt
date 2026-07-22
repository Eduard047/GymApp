package com.example.gymapp.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.repository.DashboardStats
import com.example.gymapp.ui.components.ActivityHeatmapCard
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.MuscleHeatmapCard
import com.example.gymapp.ui.components.SoloProgressHero
import com.example.gymapp.ui.viewmodel.MuscleMapPeriod
import com.example.gymapp.ui.viewmodel.TrainingRecommendationUiModel
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
    onMuscleMapPeriodSelected: (MuscleMapPeriod) -> Unit,
    onMuscleSelected: (String) -> Unit,
    onDeleteSession: (Long) -> Unit,
    onAddWorkout: () -> Unit,
    modifier: Modifier = Modifier
) {
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    var workoutsSelected by rememberSaveable { mutableStateOf(false) }
    var sessionPendingDelete by remember { mutableStateOf<WorkoutSessionEntity?>(null) }
    val showTopControls by remember {
        derivedStateOf {
            listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset < 24
        }
    }
    // Fixed overview item count before the workout list header.
    val workoutSectionIndex = 5

    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        AnimatedVisibility(visible = showTopControls) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .padding(top = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            text = stringResource(R.string.title_workouts),
                            style = MaterialTheme.typography.headlineLarge,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Text(
                            text = stringResource(R.string.workouts_screen_subtitle),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    Button(
                        onClick = onAddWorkout,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 52.dp),
                        shape = MaterialTheme.shapes.small
                    ) {
                        Icon(imageVector = Icons.Default.Add, contentDescription = null)
                        Text(
                            text = stringResource(R.string.action_add_workout),
                            modifier = Modifier.padding(start = 8.dp),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }

                MonthSwitcher(
                    monthLabel = uiState.monthLabel,
                    isCurrentMonth = uiState.monthOffset == 0,
                    onPreviousMonth = onPreviousMonth,
                    onCurrentMonth = onCurrentMonth,
                    onNextMonth = onNextMonth,
                    modifier = Modifier.padding(horizontal = 12.dp)
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
            }
        }

        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 12.dp,
                top = 8.dp,
                end = 12.dp,
                bottom = 16.dp
            ),
            verticalArrangement = Arrangement.spacedBy(12.dp)
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
                MuscleHeatmapCard(
                    heatmap = uiState.muscleHeatmap,
                    onPeriodSelected = onMuscleMapPeriodSelected,
                    onMuscleSelected = onMuscleSelected
                )
            }

            item {
                RecommendationsCard(recommendations = uiState.trainingRecommendations)
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
                    val displayDate = DateTimeUtils.formatDate(sessionSummary.session.date)
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
                                        displayDate
                                    ),
                                    style = MaterialTheme.typography.titleMedium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                                InfoPill(text = stringResource(R.string.stats_sets, sessionSummary.setCount))
                                IconButton(
                                    onClick = { sessionPendingDelete = sessionSummary.session }
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Delete,
                                        contentDescription = stringResource(
                                            R.string.cd_delete_workout_on,
                                            displayDate
                                        )
                                    )
                                }
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

    val deletingSession = sessionPendingDelete
    if (deletingSession != null) {
        AlertDialog(
            onDismissRequest = { sessionPendingDelete = null },
            title = { Text(text = stringResource(R.string.dialog_delete_workout_title)) },
            text = {
                Text(
                    text = stringResource(
                        R.string.dialog_delete_workout_message,
                        DateTimeUtils.formatDate(deletingSession.date)
                    )
                )
            },
            confirmButton = {
                OutlinedButton(
                    onClick = {
                        onDeleteSession(deletingSession.id)
                        sessionPendingDelete = null
                    }
                ) {
                    Text(text = stringResource(R.string.action_delete))
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { sessionPendingDelete = null }) {
                    Text(text = stringResource(R.string.action_cancel))
                }
            }
        )
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
                selected = !workoutsSelected,
                onClick = onOverviewClick,
                modifier = Modifier.weight(1f)
            )
            WorkoutSectionChip(
                title = stringResource(R.string.workout_switch_list_title, sessionCount),
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
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val darkTheme = isSystemInDarkTheme()
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        color = if (selected) {
            if (darkTheme) Color.White.copy(alpha = 0.32f) else MaterialTheme.colorScheme.surface
        } else {
            Color.Transparent
        },
        shape = MaterialTheme.shapes.large,
        border = BorderStroke(
            width = 1.dp,
            color = if (selected) {
                if (darkTheme) Color.White.copy(alpha = 0.16f) else {
                    MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.72f)
                }
            } else {
                Color.Transparent
            }
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = if (selected) {
                    if (darkTheme) Color.White else MaterialTheme.colorScheme.onSurface
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
        }
    }
}

@Composable
private fun RecommendationsCard(
    recommendations: List<TrainingRecommendationUiModel>,
    modifier: Modifier = Modifier
) {
    AppPanel(
        modifier = modifier.fillMaxWidth(),
        highlighted = recommendations.isNotEmpty()
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.recommendations_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(R.string.recommendations_supporting),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            recommendations.forEach { recommendation ->
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.surface.copy(alpha = 0.78f),
                    shape = MaterialTheme.shapes.small,
                    border = BorderStroke(
                        1.dp,
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(10.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(2.dp)
                        ) {
                            Text(
                                text = recommendation.title,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = recommendation.supporting,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        InfoPill(text = recommendation.priorityLabel)
                    }
                }
            }
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
                color = Color.White
            )
            Text(
                text = stringResource(R.string.dashboard_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.9f)
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
