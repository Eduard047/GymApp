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
    Goals,
    Program
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
    programOwnerKey: String = "preview",
    programSessions: List<com.example.gymapp.data.entity.WorkoutSessionSummary> = emptyList(),
    programProfile: com.example.gymapp.util.TrainingProfile = com.example.gymapp.util.TrainingProfile(),
    onPrepareProgramWorkout: () -> Unit = {},
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
                GymSegmentItem(ProgressHubSection.Goals, stringResource(R.string.progress_section_goals)),
                GymSegmentItem(ProgressHubSection.Program, stringResource(R.string.training_program_tab))
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
                    item { com.example.gymapp.ui.components.WeeklyReviewCard(weeklyHistory, weeklyTarget, onOpenWorkout) }
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


@Composable
private fun TrainingProgramCard(owner: String, sessions: List<com.example.gymapp.data.entity.WorkoutSessionSummary>, profile: com.example.gymapp.util.TrainingProfile, onPrepare: () -> Unit) {
    val context = LocalContext.current
    val store = remember(owner, context) { com.example.gymapp.util.TrainingProgramStore(context, owner) }
    var generation by rememberSaveable(owner) { mutableIntStateOf(0) }
    val program = remember(owner, generation, sessions) { store.load() }
    fun refresh(ok: Boolean) { if (ok) generation++ }
    if (program == null) {
        Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
            EmptyStatePanel(title = stringResource(R.string.training_four_week_program), supporting = stringResource(R.string.training_program_intro),
                actionLabel = stringResource(R.string.training_program_create), onAction = { refresh(store.create(profile.workoutsPerWeek, profile.goal.name)) })
        }
        return
    }
    val next = store.next(program); val linked = program.slots.count { it.sessionId != null }; val match = next?.let { store.matchingSession(program, it, sessions) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { AppPanel(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.training_four_week_program), style = MaterialTheme.typography.titleLarge)
            val goalLabel = when(program.goal) {
                "AestheticFatLoss" -> R.string.training_goal_aesthetic_fat_loss
                "MuscleGain" -> R.string.training_goal_muscle_gain
                "Strength" -> R.string.training_goal_strength
                else -> R.string.training_goal_balanced
            }
            Text("${stringResource(goalLabel)} · $linked/${program.slots.size}")
            LinearProgressIndicator(progress = { linked.toFloat() / program.slots.size }, Modifier.fillMaxWidth())
            Text(when(program.status){"paused"->stringResource(R.string.training_program_paused);"completed"->stringResource(R.string.training_program_finished);else->next?.let{stringResource(R.string.training_program_next,com.example.gymapp.util.DateTimeUtils.formatDate(it.date))}?:stringResource(R.string.training_program_all_linked)})
            if(program.status=="active"&&next!=null){Button(onClick=onPrepare,Modifier.fillMaxWidth().heightIn(min=48.dp)){Text(stringResource(R.string.training_program_prepare))};Text(stringResource(R.string.training_program_recalculate),style=MaterialTheme.typography.bodySmall);OutlinedButton(onClick={refresh(store.rescheduleNext())},Modifier.fillMaxWidth()){Text(stringResource(R.string.training_program_move))};match?.let{session->OutlinedButton(onClick={refresh(store.link(session.session.id,sessions))},Modifier.fillMaxWidth()){Text(stringResource(R.string.training_program_link))}}}
            Row { when(program.status){"active"->TextButton(onClick={refresh(store.updateStatus("paused"))}){Text(stringResource(R.string.training_program_pause))};"paused"->TextButton(onClick={refresh(store.updateStatus("active"))}){Text(stringResource(R.string.training_program_resume))}};if(program.status!="completed")TextButton(onClick={refresh(store.updateStatus("completed"))}){Text(stringResource(R.string.training_program_finish))} }
        } } }
        items(program.slots.size) { i -> val slot=program.slots[i]; Text("${i+1}. ${com.example.gymapp.util.DateTimeUtils.formatDate(slot.date)} · ${if(slot.sessionId!=null)"✓" else "—"}",Modifier.padding(horizontal=16.dp,vertical=6.dp)) }
    }
}
