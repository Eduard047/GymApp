package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import com.example.gymapp.R
import androidx.compose.ui.res.stringResource
import com.example.gymapp.ui.components.ActivityHeatmapCard
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.MuscleHeatmapCard
import com.example.gymapp.ui.components.SoloProgressHero
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.viewmodel.ExerciseProgressUiState
import com.example.gymapp.ui.viewmodel.MuscleMapPeriod
import com.example.gymapp.ui.viewmodel.WorkoutListUiState
import com.example.gymapp.util.asString

internal enum class ProgressHubSection {
    Overview,
    Exercises,
    Goals
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
    onRetryOverviewLoad: () -> Unit = {},
    initialSection: ProgressHubSection = ProgressHubSection.Overview,
    modifier: Modifier = Modifier
) {
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var selectedIndex by rememberSaveable { mutableIntStateOf(initialSection.ordinal) }
    val selected = ProgressHubSection.entries.getOrElse(selectedIndex) {
        ProgressHubSection.Overview
    }

    Column(modifier = modifier.fillMaxSize()) {
        GymSegmentedControl(
            items = listOf(
                GymSegmentItem(
                    ProgressHubSection.Overview,
                    stringResource(R.string.progress_section_overview)
                ),
                GymSegmentItem(
                    ProgressHubSection.Exercises,
                    stringResource(R.string.progress_section_exercises)
                ),
                GymSegmentItem(
                    ProgressHubSection.Goals,
                    stringResource(R.string.progress_section_goals)
                )
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
                    verticalArrangement = Arrangement.spacedBy(GymSpacing.Medium)
                ) {
                    item {
                        MonthSwitcher(
                            monthLabel = overviewState.monthLabel,
                            isCurrentMonth = overviewState.monthOffset == 0,
                            onPreviousMonth = onPreviousOverviewMonth,
                            onCurrentMonth = onCurrentOverviewMonth,
                            onNextMonth = onNextOverviewMonth
                        )
                    }
                    item { SoloProgressHero(progress = overviewState.soloProgress) }
                    item { ActivityHeatmapCard(heatmap = overviewState.activityHeatmap) }
                    item {
                        MuscleHeatmapCard(
                            heatmap = overviewState.muscleHeatmap,
                            onPeriodSelected = onMuscleMapPeriodSelected,
                            onMuscleSelected = onMuscleSelected
                        )
                    }
                    item {
                        RecommendationsCard(
                            recommendations = overviewState.trainingRecommendations
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
                modifier = Modifier.fillMaxSize()
            )

            ProgressHubSection.Goals -> MissionsScreen(
                uiState = overviewState,
                onOpenRanks = onOpenRanks,
                onRetryLoad = onRetryOverviewLoad,
                modifier = Modifier.fillMaxSize()
            )
        }
    }
}
