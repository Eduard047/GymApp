package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import com.example.gymapp.ui.components.AppPanel
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.*
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Row
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import androidx.compose.ui.res.stringResource
import com.example.gymapp.ui.components.ActivityHeatmapCard
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.LifetimeProgressCard
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.MuscleHeatmapCard
import com.example.gymapp.ui.components.ProgressLevelRow
import com.example.gymapp.ui.components.GroupedRow
import com.example.gymapp.ui.components.GroupedSection
import com.example.gymapp.data.repository.StrengthTrend
import com.example.gymapp.data.repository.buildStrengthTrends
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.util.formattedStringResource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.graphics.Color
import com.example.gymapp.ui.theme.RecoveryGreen
import com.example.gymapp.ui.theme.RecoveryGreenNight
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.viewmodel.ExerciseProgressUiState
import com.example.gymapp.ui.viewmodel.MuscleMapPeriod
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.asString

internal enum class ProgressHubSection {
    Overview,
    Exercises,
    Goals,
    Program
}

/**
 * Training programs are paused on every client (Android, iOS, PWA) until the
 * redesigned scheduling ships everywhere. Stored programs stay intact and are
 * still removed with the account.
 */
internal const val TRAINING_PROGRAM_ENABLED = false

internal val visibleProgressHubSections: List<ProgressHubSection>
    get() = ProgressHubSection.entries.filter {
        it != ProgressHubSection.Program || TRAINING_PROGRAM_ENABLED
    }

@Composable
internal fun ProgressHubScreen(
    overviewState: WorkoutListUiState,
    exerciseState: ExerciseProgressUiState,
    exerciseMediaOwnerKey: String,
    onSelectExercise: (Long) -> Unit,
    onPreviousExerciseMonth: () -> Unit,
    onCurrentExerciseMonth: () -> Unit,
    onNextExerciseMonth: () -> Unit,
    onPreviousOverviewMonth: () -> Unit,
    onCurrentOverviewMonth: () -> Unit,
    onNextOverviewMonth: () -> Unit,
    onMuscleMapPeriodSelected: (MuscleMapPeriod) -> Unit,
    onMuscleSelected: (String) -> Unit,
    onOpenRanks: () -> Unit,
    weeklyHistory: List<com.example.gymapp.data.entity.ExerciseHistoryEntry> = emptyList(),
    weeklyTarget: Int = 4,
    onOpenWorkout: (Long) -> Unit = {},
    trainingProfile: com.example.gymapp.util.TrainingProfile = com.example.gymapp.util.TrainingProfile(),
    onTrainingProfileChange: (com.example.gymapp.util.TrainingProfile) -> Unit = {},
    programOwnerKey: String = "preview",
    programSessions: List<com.example.gymapp.data.entity.WorkoutSessionSummary> = emptyList(),
    programProfile: com.example.gymapp.util.TrainingProfile = com.example.gymapp.util.TrainingProfile(),
    onPrepareProgramWorkout: () -> Unit = {},
    onRetryOverviewLoad: () -> Unit = {},
    onStartWorkout: () -> Unit = {},
    initialSection: ProgressHubSection = ProgressHubSection.Overview,
    modifier: Modifier = Modifier
) {
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var selectedIndex by rememberSaveable { mutableIntStateOf(initialSection.ordinal) }
    val selected = ProgressHubSection.entries.getOrNull(selectedIndex)
        ?.takeIf { it in visibleProgressHubSections }
        ?: ProgressHubSection.Overview
    val strengthTrends = remember(weeklyHistory) { buildStrengthTrends(weeklyHistory) }

    Column(modifier = modifier.fillMaxSize()) {
        GymSegmentedControl(
            items = listOfNotNull(
                GymSegmentItem(
                    ProgressHubSection.Overview,
                    stringResource(R.string.progress_section_overview)
                ),
                GymSegmentItem(
                    ProgressHubSection.Exercises,
                    stringResource(R.string.progress_section_exercises)
                ),
                GymSegmentItem(ProgressHubSection.Goals, stringResource(R.string.progress_section_goals)),
                if (TRAINING_PROGRAM_ENABLED) {
                    GymSegmentItem(ProgressHubSection.Program, stringResource(R.string.training_program_tab))
                } else {
                    null
                }
            ),
            selected = selected,
            onSelected = { selectedIndex = it.ordinal },
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    start = screenHorizontalPadding,
                    top = GymSpacing.Small,
                    end = screenHorizontalPadding,
                    bottom = GymSpacing.XSmall
                )
        )

        when (selected) {
            ProgressHubSection.Overview -> when {
                overviewState.isLoading -> Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = screenHorizontalPadding),
                    contentAlignment = Alignment.Center
                ) {
                    LoadingStatePanel(label = stringResource(R.string.workouts_loading))
                }
                overviewState.loadError != null -> Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = screenHorizontalPadding),
                    contentAlignment = Alignment.Center
                ) {
                    EmptyStatePanel(
                        title = overviewState.loadError.asString(),
                        actionLabel = stringResource(R.string.action_retry),
                        onAction = onRetryOverviewLoad
                    )
                }
                else -> LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        start = screenHorizontalPadding,
                        top = GymSpacing.Small,
                        end = screenHorizontalPadding,
                        bottom = GymSpacing.ScreenBottom
                    ),
                    verticalArrangement = Arrangement.spacedBy(GymSpacing.XXLarge)
                ) {
                    if (overviewState.todayHeroMetrics.totalWorkouts == 0) {
                        // Nothing is saved yet: one message and one action instead of a wall of zeros.
                        item {
                            EmptyStatePanel(
                                title = stringResource(R.string.progress_empty_title),
                                supporting = stringResource(R.string.progress_empty_text),
                                actionLabel = stringResource(R.string.action_start_workout),
                                onAction = onStartWorkout
                            )
                        }
                        return@LazyColumn
                    }
                    item {
                        com.example.gymapp.ui.components.WeeklyReviewCard(
                            history = weeklyHistory,
                            target = weeklyTarget,
                            onOpenWorkout = onOpenWorkout,
                            trainingProfile = trainingProfile,
                            onTrainingProfileChange = onTrainingProfileChange
                        )
                    }
                    if (strengthTrends.isNotEmpty()) {
                        item {
                            StrengthProgressSection(
                                trends = strengthTrends,
                                onOpenExercise = { exerciseId ->
                                    onSelectExercise(exerciseId)
                                    selectedIndex = ProgressHubSection.Exercises.ordinal
                                }
                            )
                        }
                    }
                    item {
                        ActivityHeatmapCard(
                            heatmap = overviewState.activityHeatmap,
                            isCurrentMonth = overviewState.monthOffset == 0,
                            onPreviousMonth = onPreviousOverviewMonth,
                            onCurrentMonth = onCurrentOverviewMonth,
                            onNextMonth = onNextOverviewMonth
                        )
                    }
                    item {
                        MuscleHeatmapCard(
                            heatmap = overviewState.muscleHeatmap,
                            onPeriodSelected = onMuscleMapPeriodSelected,
                            onMuscleSelected = onMuscleSelected
                        )
                    }
                    item { LifetimeProgressCard(metrics = overviewState.todayHeroMetrics) }
                    if (overviewState.trainingRecommendations.isNotEmpty()) {
                        item {
                            RecommendationsCard(
                                recommendations = overviewState.trainingRecommendations
                            )
                        }
                    }
                    // Level, XP and title are demoted to one row at the very bottom.
                    item {
                        ProgressLevelRow(
                            progress = overviewState.soloProgress,
                            onOpenRanks = onOpenRanks
                        )
                    }
                }
            }

            ProgressHubSection.Exercises -> ExerciseProgressScreen(
                uiState = exerciseState,
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                onSelectExercise = onSelectExercise,
                onPreviousMonth = onPreviousExerciseMonth,
                onCurrentMonth = onCurrentExerciseMonth,
                onNextMonth = onNextExerciseMonth,
                onStartWorkout = onStartWorkout,
                modifier = Modifier.fillMaxSize()
            )

            ProgressHubSection.Program -> TrainingProgramCard(programOwnerKey, programSessions, programProfile, onPrepareProgramWorkout)

            ProgressHubSection.Goals -> MissionsScreen(
                uiState = overviewState,
                onOpenRanks = onOpenRanks,
                onRetryLoad = onRetryOverviewLoad,
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}

/** Best recent sets of the most trained exercises; each row opens that exercise's progress. */
@Composable
private fun StrengthProgressSection(
    trends: List<StrengthTrend>,
    onOpenExercise: (Long) -> Unit
) {
    GroupedSection(header = stringResource(R.string.progress_strength_title)) {
        trends.forEach { trend ->
            val delta = trend.deltaKg?.let { Math.round(it * 10.0) / 10.0 }?.takeIf { it != 0.0 }
            row {
                val best = formattedStringResource(
                    R.string.progress_strength_best,
                    formattedStringResource(
                        R.string.progress_pr_history_set_value,
                        formattedStringResource(R.string.progress_weight_value, formatProgressWeight(trend.bestWeight)),
                        trend.bestReps
                    )
                )
                val gain = (delta ?: 0.0) > 0.0
                GroupedRow(
                    title = localizedExerciseName(trend.exerciseName),
                    subtitle = best,
                    value = delta?.let {
                        formattedStringResource(
                            if (it > 0) R.string.progress_strength_gain else R.string.progress_strength_loss,
                            formatProgressWeight(kotlin.math.abs(it))
                        )
                    },
                    valueColor = if (gain) {
                        if (isSystemInDarkTheme()) RecoveryGreenNight else RecoveryGreen
                    } else {
                        Color.Unspecified
                    },
                    chevron = true,
                    onClick = { onOpenExercise(trend.exerciseId) }
                )
            }
        }
    }
}
