package com.example.gymapp.ui.screens

/*
THESIS: Focus Lens puts today's workout in one fluid focal form and refuses the stacked-dashboard default.
OWN-WORLD: Airy canvas, aquatic contextual color, continuous curves, solid content rows, and one expressive Material control layer.
STORY: See the next useful action, understand its size and weekly rhythm, start it, then review recent work without changing modes.
FIRST VIEWPORT: A large asymmetric lens leads; core facts live inside it and the start action stays near thumb reach, followed by progressive analytics.
FORM: User-selected Focus Lens from Fluid Focus; seed af1a1dee. Android structure remains Material 3 with native back, insets, semantics, and motion.
*/

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape
import com.example.gymapp.R
import com.example.gymapp.data.repository.DashboardStats
import com.example.gymapp.ui.components.ActivityHeatmapCard
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.MuscleHeatmapCard
import com.example.gymapp.ui.components.ScreenHeader
import com.example.gymapp.ui.components.SoloProgressHero
import com.example.gymapp.ui.theme.GymSpacing
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
    onAddWorkout: () -> Unit,
    activeWorkoutProgress: Pair<Int, Int>? = null,
    onDiscardActiveWorkout: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    var workoutsSelected by rememberSaveable { mutableStateOf(false) }
    var showActiveWorkoutDiscardConfirmation by rememberSaveable { mutableStateOf(false) }
    val showTopControls by remember {
        derivedStateOf {
            listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset < 24
        }
    }
    // Fixed overview item count before the workout list header.
    val workoutSectionIndex = 7

    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (showTopControls) {
            ScreenHeader(
                title = stringResource(R.string.title_workouts),
                supporting = stringResource(R.string.workouts_screen_subtitle),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = GymSpacing.ScreenHorizontal)
                    .padding(top = GymSpacing.Small)
            )
        }

        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = GymSpacing.ScreenHorizontal,
                top = GymSpacing.Small,
                end = GymSpacing.ScreenHorizontal,
                bottom = GymSpacing.ScreenBottom
            ),
            verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
        ) {
            item {
                FocusLens(
                    stats = uiState.dashboardStats,
                    hasActiveWorkout = activeWorkoutProgress != null,
                    onStartWorkout = onAddWorkout
                )
            }

            activeWorkoutProgress?.let { progress ->
                item {
                    ActiveWorkoutDraftCard(
                        completedSetCount = progress.first,
                        totalSetCount = progress.second,
                        onContinue = onAddWorkout,
                        onDiscard = { showActiveWorkoutDiscardConfirmation = true }
                    )
                }
            }

            item {
                MonthSwitcher(
                    monthLabel = uiState.monthLabel,
                    isCurrentMonth = uiState.monthOffset == 0,
                    onPreviousMonth = onPreviousMonth,
                    onCurrentMonth = onCurrentMonth,
                    onNextMonth = onNextMonth
                )
            }

            item {
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
                    }
                )
            }

            item {
                SoloProgressHero(progress = uiState.soloProgress)
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
                        supporting = stringResource(R.string.dashboard_subtitle),
                        actionLabel = stringResource(R.string.action_add_workout),
                        onAction = onAddWorkout
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

    if (showActiveWorkoutDiscardConfirmation) {
        AlertDialog(
            onDismissRequest = { showActiveWorkoutDiscardConfirmation = false },
            title = { Text(stringResource(R.string.active_workout_discard_title)) },
            text = { Text(stringResource(R.string.active_workout_discard_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showActiveWorkoutDiscardConfirmation = false
                        onDiscardActiveWorkout()
                    }
                ) {
                    Text(stringResource(R.string.active_workout_discard_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { showActiveWorkoutDiscardConfirmation = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

@Composable
private fun ActiveWorkoutDraftCard(
    completedSetCount: Int,
    totalSetCount: Int,
    onContinue: () -> Unit,
    onDiscard: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(
                text = stringResource(R.string.active_workout_draft_title),
                style = MaterialTheme.typography.titleMedium
            )
            Text(
                text = stringResource(
                    R.string.active_workout_draft_progress,
                    completedSetCount,
                    totalSetCount
                ),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Button(
                onClick = onContinue,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) {
                Text(stringResource(R.string.action_continue_workout))
            }
            OutlinedButton(
                onClick = onDiscard,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) {
                Text(stringResource(R.string.active_workout_discard_action))
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
    GymSegmentedControl(
        items = listOf(
            GymSegmentItem(
                value = false,
                label = stringResource(R.string.workout_switch_overview_title)
            ),
            GymSegmentItem(
                value = true,
                label = stringResource(R.string.workout_switch_list_title, sessionCount)
            )
        ),
        selected = workoutsSelected,
        onSelected = { selected ->
            if (selected) onWorkoutListClick() else onOverviewClick()
        },
        modifier = modifier
    )
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
private fun FocusLens(
    stats: DashboardStats,
    hasActiveWorkout: Boolean,
    onStartWorkout: () -> Unit,
    modifier: Modifier = Modifier
) {
    val darkTheme = isSystemInDarkTheme()
    val lensShape = RoundedCornerShape(
        topStart = 44.dp,
        topEnd = 76.dp,
        bottomEnd = 60.dp,
        bottomStart = 32.dp
    )
    val lensBrush = if (darkTheme) {
        Brush.linearGradient(
            listOf(Color(0xFF124A96), Color(0xFF176FC5), Color(0xFF164F9B))
        )
    } else {
        Brush.linearGradient(
            listOf(Color(0xFF1B71D8), Color(0xFF3295F1), Color(0xFF2467CD))
        )
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = if (hasActiveWorkout) 250.dp else 330.dp)
            .clip(lensShape)
            .background(lensBrush)
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = stringResource(R.string.focus_lens_eyebrow),
                style = MaterialTheme.typography.labelMedium,
                color = Color.White.copy(alpha = 0.74f),
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(R.string.focus_lens_title),
                style = MaterialTheme.typography.headlineLarge,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(
                    if (hasActiveWorkout) {
                        R.string.focus_lens_active_workout_supporting
                    } else {
                        R.string.focus_lens_supporting
                    }
                ),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.84f)
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            FocusLensMetric(
                label = stringResource(R.string.focus_lens_month_workouts),
                value = stats.workoutCount.toString(),
                modifier = Modifier.weight(1f)
            )
            FocusLensMetric(
                label = stringResource(R.string.focus_lens_week_streak),
                value = stats.weeklyStreakWeeks.toString(),
                modifier = Modifier.weight(1f)
            )
            FocusLensMetric(
                label = stringResource(R.string.focus_lens_volume),
                value = stringResource(R.string.kpi_volume_value, stats.totalVolume),
                modifier = Modifier.weight(1f)
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        if (!hasActiveWorkout) {
            Button(
                onClick = onStartWorkout,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 54.dp),
                shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White.copy(alpha = 0.2f),
                    contentColor = Color.White
                ),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.34f))
            ) {
                Icon(imageVector = Icons.Default.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = stringResource(R.string.action_start_workout),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun FocusLensMetric(
    label: String,
    value: String,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleLarge,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.72f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
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
