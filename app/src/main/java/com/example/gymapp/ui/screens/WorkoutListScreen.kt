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
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import com.example.gymapp.R
import com.example.gymapp.data.repository.DashboardStats
import com.example.gymapp.data.repository.FirstWorkoutEffort
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.SmartWorkoutEffortAdjustment
import com.example.gymapp.data.repository.WeeklyTrainingDecision
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
import com.example.gymapp.ui.components.TutorialAnchorRegistry
import com.example.gymapp.ui.components.TutorialTarget
import com.example.gymapp.ui.components.tutorialAnchor
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.viewmodel.MuscleMapPeriod
import com.example.gymapp.ui.viewmodel.TrainingRecommendationUiModel
import com.example.gymapp.ui.viewmodel.TodayPlanUiModel
import com.example.gymapp.ui.viewmodel.TodayHeroMetricsUiModel
import com.example.gymapp.ui.viewmodel.WeeklyTrainingSummaryUiModel
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.TrainingGoal
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.format.TextStyle
import java.util.Locale

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
    onStartPlan: (String) -> Unit,
    onOpenPlan: (String) -> Unit,
    onStartFirstWorkout: (TrainingGoal, Int, FirstWorkoutEffort) -> Unit,
    onEditFirstWorkout: (TrainingGoal, Int, FirstWorkoutEffort) -> Unit,
    onSkipFirstWorkout: () -> Unit,
    hasRetainedWorkoutDraft: Boolean = false,
    activeWorkoutProgress: Pair<Int, Int>? = null,
    onDiscardActiveWorkout: () -> Unit = {},
    tutorialAnchors: TutorialAnchorRegistry? = null,
    modifier: Modifier = Modifier
) {
    val listState = rememberLazyListState()
    var showActiveWorkoutDiscardConfirmation by rememberSaveable { mutableStateOf(false) }
    val showTopControls by remember {
        derivedStateOf {
            listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset < 24
        }
    }
    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (showTopControls) {
            ScreenHeader(
                title = stringResource(R.string.today_title),
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
            if (uiState.showFirstWorkoutActivation && activeWorkoutProgress == null) {
                item {
                    FirstWorkoutActivationCard(
                        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft,
                        onContinuePlan = onAddWorkout,
                        onStart = onStartFirstWorkout,
                        onEdit = onEditFirstWorkout,
                        onCreateManually = onSkipFirstWorkout,
                        tutorialAnchors = tutorialAnchors
                    )
                }
            } else {
                item {
                    FocusLens(
                        todayPlan = uiState.todayPlan,
                        hasCompletedWorkoutToday = uiState.hasCompletedWorkoutToday,
                        weeklyTrainingSummary = uiState.weeklyTrainingSummary,
                        todayHeroMetrics = uiState.todayHeroMetrics,
                        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft,
                        activeWorkoutProgress = activeWorkoutProgress,
                        onStartWorkout = onAddWorkout,
                        onStartPlan = onStartPlan,
                        onOpenPlan = onOpenPlan,
                        onDiscardWorkout = {
                            showActiveWorkoutDiscardConfirmation = true
                        },
                        tutorialAnchors = tutorialAnchors
                    )
                }
            }

            if (uiState.hasAnyWorkout) {
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
                WorkoutSectionHeader(sessionCount = uiState.sessions.size)
            }

                if (uiState.sessions.isEmpty()) {
                item {
                    EmptyStatePanel(
                        title = stringResource(R.string.empty_workouts),
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
                    val isActivityOnly = sessionSummary.exerciseCount == 0 &&
                        sessionSummary.setCount == 0 &&
                        sessionSummary.session.durationSeconds?.let { it > 0L } == true
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
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f)
                                )
                                InfoPill(
                                    text = if (isActivityOnly) {
                                        formatWorkoutDuration(
                                            checkNotNull(sessionSummary.session.durationSeconds)
                                        )
                                    } else {
                                        stringResource(R.string.stats_sets, sessionSummary.setCount)
                                    }
                                )
                            }

                            Text(
                                text = if (isActivityOnly) {
                                    stringResource(R.string.garmin_free_workout_title)
                                } else {
                                    sessionSummary.session.note
                                        ?.takeIf { it.isNotBlank() }
                                        ?.let { stringResource(R.string.details_note, it) }
                                        ?: stringResource(R.string.details_no_note)
                                },
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )

                            if (isActivityOnly) {
                                Text(
                                    text = stringResource(R.string.garmin_free_workout_summary),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                            } else {
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
internal fun RecommendationsCard(
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
    todayPlan: TodayPlanUiModel?,
    hasCompletedWorkoutToday: Boolean,
    weeklyTrainingSummary: WeeklyTrainingSummaryUiModel,
    todayHeroMetrics: TodayHeroMetricsUiModel,
    hasRetainedWorkoutDraft: Boolean,
    activeWorkoutProgress: Pair<Int, Int>?,
    onStartWorkout: () -> Unit,
    onStartPlan: (String) -> Unit,
    onOpenPlan: (String) -> Unit,
    onDiscardWorkout: () -> Unit,
    tutorialAnchors: TutorialAnchorRegistry?,
    modifier: Modifier = Modifier
) {
    var showPlanDetails by rememberSaveable { mutableStateOf(false) }
    var showActiveOptions by rememberSaveable { mutableStateOf(false) }
    val hasActiveWorkout = activeWorkoutProgress != null
    val shouldContinueRetainedPlan = shouldShowRetainedWorkoutDraftAction(
        hasRetainedWorkoutDraft = hasRetainedWorkoutDraft,
        hasActiveWorkout = hasActiveWorkout
    )
    val hasCompletedToday = hasCompletedWorkoutToday && !hasActiveWorkout
    val darkTheme = isSystemInDarkTheme()
    val lensShape = RoundedCornerShape(28.dp)
    val lensBrush = if (darkTheme) {
        Brush.linearGradient(
            listOf(Color(0xFF124A96), Color(0xFF176FC5), Color(0xFF164F9B))
        )
    } else {
        Brush.linearGradient(
            listOf(Color(0xFF1B71D8), Color(0xFF3295F1), Color(0xFF2467CD))
        )
    }

    val focusModifier = if (tutorialAnchors == null) {
        modifier
    } else {
        modifier.tutorialAnchor(tutorialAnchors, TutorialTarget.TodayFocus)
    }
    fun Modifier.primaryTutorialAnchor(): Modifier = if (tutorialAnchors == null) {
        this
    } else {
        tutorialAnchor(tutorialAnchors, TutorialTarget.TodayPrimaryAction)
    }

    Column(
        modifier = focusModifier
            .fillMaxWidth()
            .clip(lensShape)
            .background(lensBrush)
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = when {
                    hasActiveWorkout -> stringResource(R.string.action_continue_workout)
                    hasCompletedToday -> stringResource(R.string.today_workout_completed)
                    todayPlan?.rhythm?.decision == WeeklyTrainingDecision.Rest ->
                        stringResource(R.string.today_rest)
                    todayPlan?.rhythm?.decision == WeeklyTrainingDecision.Recovery ->
                        stringResource(R.string.smart_effort_recovery)
                    todayPlan != null -> stringResource(todayPlan.focus.labelResource())
                    shouldContinueRetainedPlan -> stringResource(R.string.title_workout_plan)
                    else -> stringResource(R.string.action_start_workout)
                },
                style = MaterialTheme.typography.headlineLarge,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
        }

        if (activeWorkoutProgress != null) {
            FocusLensMetric(
                label = stringResource(R.string.active_workout_draft_title),
                value = stringResource(
                    R.string.active_workout_draft_progress,
                    activeWorkoutProgress.first,
                    activeWorkoutProgress.second
                )
            )
        } else if (hasCompletedToday) {
            Text(
                text = stringResource(R.string.today_workout_completed_supporting),
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White
            )
        } else if (todayPlan != null && todayPlan.rhythm.decision in setOf(
                WeeklyTrainingDecision.Rest,
                WeeklyTrainingDecision.Recovery
            )
        ) {
            Text(
                text = if (todayPlan.rhythm.decision == WeeklyTrainingDecision.Rest) {
                    stringResource(
                        R.string.today_recovery_reason_target,
                        todayPlan.rhythm.completedTrainingDays,
                        todayPlan.rhythm.targetTrainingDays
                    )
                } else {
                    stringResource(todayPlan.effortAdjustment.recoveryReasonResource())
                },
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White
            )
            todayPlan.rhythm.nextRecommendedDayMillis?.let { nextDay ->
                val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
                Text(
                    text = stringResource(
                        R.string.today_next_recommended_day,
                        DateTimeUtils.formatLongDate(nextDay, locale)
                    ),
                    style = MaterialTheme.typography.titleMedium,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold
                )
            }
        } else if (todayPlan != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                FocusLensMetric(
                    label = stringResource(
                        R.string.today_plan_duration,
                        todayPlan.estimatedDurationMinutes
                    ),
                    value = stringResource(
                        R.string.today_plan_size,
                        todayPlan.exerciseCount,
                        todayPlan.setCount
                    ),
                    modifier = Modifier.weight(1f)
                )
            }
            FocusLensMetric(
                label = stringResource(R.string.today_weekly_rhythm),
                value = stringResource(
                    R.string.today_weekly_value,
                    todayPlan.rhythm.completedTrainingDays,
                    todayPlan.rhythm.targetTrainingDays
                )
            )
        }

        OutlinedButton(
            onClick = { showPlanDetails = !showPlanDetails },
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
            border = BorderStroke(1.dp, Color.White.copy(alpha = 0.34f))
        ) {
            Icon(
                imageVector = if (showPlanDetails) Icons.Default.ExpandLess
                else Icons.Default.ExpandMore,
                contentDescription = null
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(stringResource(R.string.focus_lens_details))
        }
        if (showPlanDetails) {
            WeeklyTrainingCard(summary = weeklyTrainingSummary)
            TodayHeroMetricsRow(metrics = todayHeroMetrics)
            if (!hasActiveWorkout && !hasCompletedToday) {
                TextButton(
                    onClick = onStartWorkout,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                ) {
                    Text(
                        stringResource(R.string.activation_build_manually),
                        color = Color.White
                    )
                }
            }
        }

        if (hasActiveWorkout) {
            Button(
                onClick = onStartWorkout,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 54.dp)
                    .primaryTutorialAnchor(),
                shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color(0xFF123560)
                ),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.34f))
            ) {
                Icon(imageVector = Icons.Default.PlayArrow, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(stringResource(R.string.action_continue_workout), fontWeight = FontWeight.Bold)
            }
            TextButton(
                onClick = { showActiveOptions = !showActiveOptions },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) {
                Icon(
                    imageVector = if (showActiveOptions) Icons.Default.ExpandLess
                    else Icons.Default.ExpandMore,
                    contentDescription = null,
                    tint = Color.White
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(stringResource(R.string.workout_plan_more_options), color = Color.White)
            }
            if (showActiveOptions) {
                OutlinedButton(
                    onClick = onDiscardWorkout,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.46f))
                ) {
                    Text(stringResource(R.string.active_workout_discard_action))
                }
            }
        } else if (shouldContinueRetainedPlan) {
            Button(
                onClick = onStartWorkout,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 54.dp)
                    .primaryTutorialAnchor(),
                shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color(0xFF123560)
                ),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.34f))
            ) {
                Icon(imageVector = Icons.Default.Edit, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    stringResource(R.string.today_continue_plan),
                    fontWeight = FontWeight.Bold
                )
            }
        } else if (hasCompletedToday) {
            OutlinedButton(
                onClick = onStartWorkout,
                modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.46f))
            ) {
                Icon(imageVector = Icons.Default.Add, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(stringResource(R.string.today_add_another_workout))
            }
        } else if (todayPlan != null && todayPlan.rhythm.decision in setOf(
                WeeklyTrainingDecision.Rest,
                WeeklyTrainingDecision.Recovery
            )
        ) {
            val token = todayPlan.trainAnywayLaunchToken ?: todayPlan.recommendedLaunchToken
            Button(
                onClick = {
                    if (token != null) onStartPlan(token) else onStartWorkout()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 54.dp)
                    .primaryTutorialAnchor(),
                shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color(0xFF123560)
                ),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.34f))
            ) {
                Icon(imageVector = Icons.Default.PlayArrow, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(stringResource(R.string.today_train_anyway))
            }
            token?.let { launchToken ->
                OutlinedButton(
                    onClick = { onOpenPlan(launchToken) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.46f))
                ) {
                    Icon(imageVector = Icons.Default.Edit, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(stringResource(R.string.today_edit_plan))
                }
            }
        } else {
            val launchToken = todayPlan?.recommendedLaunchToken
            Button(
                onClick = {
                    if (launchToken != null) onStartPlan(launchToken) else onStartWorkout()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 54.dp)
                    .primaryTutorialAnchor(),
                shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color(0xFF123560)
                ),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.34f))
            ) {
                Icon(
                    imageVector = if (launchToken == null) Icons.Default.Add else Icons.Default.PlayArrow,
                    contentDescription = null
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = stringResource(
                        if (launchToken == null) {
                            R.string.action_start_workout
                        } else {
                            R.string.today_start_plan
                        }
                    ),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    fontWeight = FontWeight.Bold
                )
            }
            launchToken?.let { token ->
                OutlinedButton(
                    onClick = { onOpenPlan(token) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.46f))
                ) {
                    Icon(imageVector = Icons.Default.Edit, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(stringResource(R.string.today_edit_plan))
                }
            }
        }
    }
}

internal fun shouldShowRetainedWorkoutDraftAction(
    hasRetainedWorkoutDraft: Boolean,
    hasActiveWorkout: Boolean
): Boolean = hasRetainedWorkoutDraft && !hasActiveWorkout

@Composable
private fun WeeklyTrainingCard(
    summary: WeeklyTrainingSummaryUiModel,
    modifier: Modifier = Modifier
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val volume = remember(summary.totalVolume, locale) {
        formatTodayHeroVolume(summary.totalVolume, locale)
    }
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = Color.White.copy(alpha = 0.12f),
        contentColor = Color.White,
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.18f)),
        tonalElevation = 0.dp,
        shadowElevation = 0.dp
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.weekly_training_summary_title),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f)
                )
                InfoPill(
                    text = stringResource(
                        R.string.today_weekly_value,
                        summary.completedTrainingDays,
                        summary.targetTrainingDays
                    ),
                    accent = Color.White
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                summary.days.forEach { day ->
                    val weekday = day.date.dayOfWeek.getDisplayName(TextStyle.FULL, locale)
                    val status = stringResource(
                        if (day.isCompleted) {
                            R.string.weekly_training_day_completed
                        } else {
                            R.string.weekly_training_day_not_completed
                        }
                    )
                    val todayStatus = if (day.isToday) {
                        stringResource(R.string.weekly_training_day_today)
                    } else {
                        ""
                    }
                    val description = listOf(
                        "$weekday ${day.date.dayOfMonth}",
                        status,
                        todayStatus
                    ).filter { it.isNotBlank() }.joinToString(", ")
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clearAndSetSemantics { contentDescription = description },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = day.date.dayOfWeek
                                .getDisplayName(TextStyle.NARROW, locale)
                                .uppercase(locale),
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White.copy(alpha = 0.72f)
                        )
                        Box(
                            modifier = Modifier
                                .size(22.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(12.dp)
                                    .clip(CircleShape)
                                    .background(
                                        if (day.isCompleted) {
                                            Color(0xFF7DEFC7)
                                        } else {
                                            Color.White.copy(alpha = 0.24f)
                                        }
                                    )
                            )
                            if (day.isToday) {
                                Box(
                                    modifier = Modifier
                                        .size(18.dp)
                                        .border(
                                            width = 1.dp,
                                            color = Color.White.copy(alpha = 0.92f),
                                            shape = CircleShape
                                        )
                                )
                            }
                        }
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                WeeklyTrainingMetric(
                    value = formatTodayHeroCount(summary.completedWorkoutCount, locale),
                    label = stringResource(R.string.weekly_training_workouts_label),
                    modifier = Modifier.weight(1f)
                )
                WeeklyTrainingMetric(
                    value = stringResource(
                        R.string.weekly_training_minutes_value,
                        summary.estimatedMinutes
                    ),
                    label = stringResource(R.string.weekly_training_minutes_label),
                    modifier = Modifier.weight(1f)
                )
                WeeklyTrainingMetric(
                    value = volume,
                    label = stringResource(R.string.weekly_training_volume_label),
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun WeeklyTrainingMetric(
    value: String,
    label: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .widthIn(min = 0.dp)
            .clearAndSetSemantics { contentDescription = "$label, $value" },
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
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
private fun TodayHeroMetricsRow(
    metrics: TodayHeroMetricsUiModel,
    modifier: Modifier = Modifier
) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val volume = remember(metrics.totalVolume, locale) {
        formatTodayHeroVolume(metrics.totalVolume, locale)
    }
    val totalWorkouts = remember(metrics.totalWorkouts, locale) {
        formatTodayHeroCount(metrics.totalWorkouts, locale)
    }
    val totalWorkoutsAccessibilityValue = remember(metrics.totalWorkouts, locale) {
        NumberFormat.getIntegerInstance(locale).format(metrics.totalWorkouts.coerceAtLeast(0))
    }
    val volumeAccessibilityValue = remember(metrics.totalVolume, locale) {
        NumberFormat.getNumberInstance(locale).apply {
            maximumFractionDigits = 1
            isGroupingUsed = true
        }.format(metrics.totalVolume.takeIf { it.isFinite() && it >= 0.0 }
            ?.coerceAtMost(1_000_000_000_000_000.0) ?: 0.0)
    }
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        TodayHeroMetric(
            value = totalWorkouts,
            label = stringResource(R.string.focus_lens_total_workouts),
            accessibilityValue = totalWorkoutsAccessibilityValue,
            modifier = Modifier.weight(1f)
        )
        TodayHeroMetric(
            value = stringResource(
                R.string.focus_lens_week_streak_value,
                metrics.weeklyStreakWeeks
            ),
            label = stringResource(R.string.focus_lens_week_streak),
            accessibilityValue = stringResource(
                R.string.focus_lens_week_streak_value,
                metrics.weeklyStreakWeeks
            ),
            modifier = Modifier.weight(1f)
        )
        TodayHeroMetric(
            value = volume,
            label = stringResource(R.string.focus_lens_total_volume),
            accessibilityValue = volumeAccessibilityValue,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun TodayHeroMetric(
    value: String,
    label: String,
    accessibilityValue: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .widthIn(min = 0.dp)
            .clearAndSetSemantics { contentDescription = "$label, $accessibilityValue" },
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = value,
            style = MaterialTheme.typography.titleMedium,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = Color.White.copy(alpha = 0.76f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}

internal fun formatTodayHeroCount(value: Int, locale: Locale): String {
    val safeValue = value.coerceAtLeast(0).toDouble()
    return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
        android.icu.text.CompactDecimalFormat.getInstance(
            locale,
            android.icu.text.CompactDecimalFormat.CompactStyle.SHORT
        ).apply { maximumFractionDigits = 1 }.format(safeValue)
    } else {
        NumberFormat.getIntegerInstance(locale).format(safeValue)
    }
}

internal fun formatTodayHeroVolume(value: Double, locale: Locale): String {
    val safeValue = value
        .takeIf { it.isFinite() && it >= 0.0 }
        ?.coerceAtMost(1_000_000_000_000_000.0)
        ?: 0.0
    return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
        android.icu.text.CompactDecimalFormat.getInstance(
            locale,
            android.icu.text.CompactDecimalFormat.CompactStyle.SHORT
        ).apply { maximumFractionDigits = 1 }.format(safeValue)
    } else {
        NumberFormat.getNumberInstance(locale).apply {
            maximumFractionDigits = 1
            isGroupingUsed = true
        }.format(safeValue)
    }
}

@Composable
private fun FirstWorkoutActivationCard(
    hasRetainedWorkoutDraft: Boolean,
    onContinuePlan: () -> Unit,
    onStart: (TrainingGoal, Int, FirstWorkoutEffort) -> Unit,
    onEdit: (TrainingGoal, Int, FirstWorkoutEffort) -> Unit,
    onCreateManually: () -> Unit,
    tutorialAnchors: TutorialAnchorRegistry?,
    modifier: Modifier = Modifier
) {
    var goal by rememberSaveable { mutableStateOf(TrainingGoal.AestheticFatLoss) }
    var days by rememberSaveable { mutableStateOf(4) }
    var effort by rememberSaveable { mutableStateOf(FirstWorkoutEffort.Standard) }
    var showRecommendationOptions by rememberSaveable { mutableStateOf(false) }
    val darkTheme = isSystemInDarkTheme()
    val brush = if (darkTheme) {
        Brush.linearGradient(listOf(Color(0xFF124A96), Color(0xFF176FC5), Color(0xFF164F9B)))
    } else {
        Brush.linearGradient(listOf(Color(0xFF1B71D8), Color(0xFF3295F1), Color(0xFF2467CD)))
    }
    val focusModifier = if (tutorialAnchors == null) {
        modifier
    } else {
        modifier.tutorialAnchor(tutorialAnchors, TutorialTarget.TodayFocus)
    }
    val primaryModifier = if (tutorialAnchors == null) {
        Modifier
    } else {
        Modifier.tutorialAnchor(tutorialAnchors, TutorialTarget.TodayPrimaryAction)
    }
    Column(
        modifier = focusModifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(brush)
            .padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        if (hasRetainedWorkoutDraft) {
            Text(
                text = stringResource(R.string.title_workout_plan),
                style = MaterialTheme.typography.headlineLarge,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
            Button(
                onClick = onContinuePlan,
                modifier = primaryModifier.fillMaxWidth().heightIn(min = 54.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color(0xFF123560)
                ),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.34f))
            ) {
                Icon(imageVector = Icons.Default.Edit, contentDescription = null)
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    stringResource(R.string.today_continue_plan),
                    fontWeight = FontWeight.Bold
                )
            }
        } else {
            Text(
                text = stringResource(R.string.activation_first_plan_title),
                style = MaterialTheme.typography.headlineLarge,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = stringResource(R.string.activation_first_plan_supporting),
                style = MaterialTheme.typography.bodyLarge,
                color = Color.White.copy(alpha = 0.86f)
            )
            Button(
                onClick = { onStart(goal, days, effort) },
                modifier = primaryModifier.fillMaxWidth().heightIn(min = 54.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color(0xFF123560)
                )
            ) {
                Text(
                    stringResource(R.string.activation_start_plan),
                    fontWeight = FontWeight.Bold
                )
            }
            OutlinedButton(
                onClick = onCreateManually,
                modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.46f))
            ) {
                Text(stringResource(R.string.activation_build_manually))
            }
            OutlinedButton(
                onClick = { showRecommendationOptions = !showRecommendationOptions },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = Color.White),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.28f))
            ) {
                Icon(
                    imageVector = if (showRecommendationOptions) Icons.Default.ExpandLess
                    else Icons.Default.ExpandMore,
                    contentDescription = null
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(stringResource(R.string.activation_adjust_recommendation))
            }
            if (showRecommendationOptions) {
                ActivationChoiceRow(
                    label = stringResource(R.string.activation_goal),
                    options = TrainingGoal.entries.map { value ->
                        value to stringResource(value.labelResource())
                    },
                    selected = goal,
                    onSelected = { goal = it },
                    columns = 2
                )
                ActivationChoiceRow(
                    label = stringResource(R.string.activation_days),
                    options = (2..6).map { value -> value to value.toString() },
                    selected = days,
                    onSelected = { days = it }
                )
                ActivationChoiceRow(
                    label = stringResource(R.string.activation_effort),
                    options = listOf(
                        FirstWorkoutEffort.Recovery to
                            stringResource(R.string.smart_effort_recovery),
                        FirstWorkoutEffort.Standard to
                            stringResource(R.string.smart_effort_standard),
                        FirstWorkoutEffort.Hard to stringResource(R.string.smart_effort_hard)
                    ),
                    selected = effort,
                    onSelected = { effort = it }
                )
                TextButton(
                    onClick = { onEdit(goal, days, effort) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                ) {
                    Icon(imageVector = Icons.Default.Edit, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(stringResource(R.string.activation_edit_plan), color = Color.White)
                }
            }
        }
    }
}

@Composable
private fun <T> ActivationChoiceRow(
    label: String,
    options: List<Pair<T, String>>,
    selected: T,
    onSelected: (T) -> Unit,
    columns: Int = options.size
) {
    require(columns > 0)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = Color.White.copy(alpha = 0.84f)
        )
        if (columns == 2) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                options.chunked(columns).forEach { optionRow ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        optionRow.forEach { (value, optionLabel) ->
                            val isSelected = value == selected
                            Surface(
                                onClick = { onSelected(value) },
                                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                                color = if (isSelected) Color(0xFFE2FAF4) else Color.Transparent,
                                contentColor = if (isSelected) Color(0xFF102849) else Color.White,
                                shape = RoundedCornerShape(50),
                                border = BorderStroke(
                                    1.dp,
                                    if (isSelected) Color.Transparent else {
                                        Color.White.copy(alpha = 0.46f)
                                    }
                                )
                            ) {
                                Box(
                                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = optionLabel,
                                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                                        maxLines = 2,
                                        style = MaterialTheme.typography.labelMedium,
                                        textAlign = TextAlign.Center
                                    )
                                }
                            }
                        }
                        repeat(columns - optionRow.size) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(options.size) { index ->
                    val (value, optionLabel) = options[index]
                    FilterChip(
                        selected = value == selected,
                        onClick = { onSelected(value) },
                        colors = FilterChipDefaults.filterChipColors(
                            containerColor = Color.Transparent,
                            labelColor = Color.White,
                            selectedContainerColor = Color(0xFFE2FAF4),
                            selectedLabelColor = Color(0xFF102849)
                        ),
                        label = {
                            Text(
                                text = optionLabel,
                                maxLines = 1,
                                style = MaterialTheme.typography.labelMedium
                            )
                        }
                    )
                }
            }
        }
    }
}

private fun SmartWorkoutFocus.labelResource(): Int = when (this) {
    SmartWorkoutFocus.Upper -> R.string.smart_focus_upper
    SmartWorkoutFocus.Lower -> R.string.smart_focus_lower
    SmartWorkoutFocus.Push -> R.string.smart_focus_push
    SmartWorkoutFocus.Pull -> R.string.smart_focus_pull
    SmartWorkoutFocus.Legs -> R.string.smart_focus_legs
    SmartWorkoutFocus.FullBody -> R.string.smart_focus_full_body
}

private fun SmartWorkoutEffortAdjustment?.recoveryReasonResource(): Int = when (this) {
    SmartWorkoutEffortAdjustment.AutoRecovery -> R.string.smart_effort_adjustment_auto_recovery
    SmartWorkoutEffortAdjustment.FeedbackHardRecovery ->
        R.string.smart_effort_adjustment_feedback_hard
    SmartWorkoutEffortAdjustment.ReadinessLowRecovery ->
        R.string.smart_effort_adjustment_readiness_low
    else -> R.string.smart_reason_recovery_effort
}

private fun TrainingGoal.labelResource(): Int = when (this) {
    TrainingGoal.AestheticFatLoss -> R.string.training_goal_aesthetic_fat_loss
    TrainingGoal.MuscleGain -> R.string.training_goal_muscle_gain
    TrainingGoal.Strength -> R.string.training_goal_strength
    TrainingGoal.Balanced -> R.string.training_goal_balanced
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
