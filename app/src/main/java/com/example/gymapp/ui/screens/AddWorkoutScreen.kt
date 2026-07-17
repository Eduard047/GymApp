package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.WorkoutRecommendation
import com.example.gymapp.data.repository.WorkoutRecommendationKind
import com.example.gymapp.data.repository.WorkoutRecommendationReason
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMuscleBreakdownCard
import com.example.gymapp.ui.components.ExerciseMuscleMap
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.ui.viewmodel.AddWorkoutUiState
import com.example.gymapp.ui.viewmodel.ExerciseInputState
import com.example.gymapp.ui.viewmodel.WorkoutTemplatePreviewUiModel
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingSplit
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddWorkoutScreen(
    uiState: AddWorkoutUiState,
    onNoteChange: (String) -> Unit,
    onTrainingSplitSelected: (TrainingSplit) -> Unit,
    onWorkoutsPerWeekSelected: (Int) -> Unit,
    onTrainingGoalSelected: (TrainingGoal) -> Unit,
    onCalorieModeSelected: (CalorieMode) -> Unit,
    onGenerateSmartWorkout: () -> Unit,
    onAddExerciseDraft: () -> Unit,
    onRemoveExerciseDraft: (Long) -> Unit,
    onExerciseSelected: (Long, Long) -> Unit,
    onAddSet: (Long) -> Unit,
    onAddSetFromPrevious: (Long, Double) -> Unit,
    onRemoveSet: (Long, Int) -> Unit,
    onSetWeightChanged: (Long, Int, String) -> Unit,
    onSetRepsChanged: (Long, Int, String) -> Unit,
    onApplyLastWeight: (Long) -> Unit,
    onApplyWorkoutRecommendation: (Long) -> Unit,
    onRepeatLastWorkout: () -> Unit,
    onOpenTemplatePicker: () -> Unit,
    onCloseTemplatePicker: () -> Unit,
    onCopyWorkoutTemplate: (Long) -> Unit,
    onSyncPlanToWatch: () -> Unit,
    onSaveWorkout: () -> Unit,
    modifier: Modifier = Modifier
) {
    val selectedExerciseCount = uiState.exerciseDrafts.count { it.exerciseId != null }
    val totalSetCount = uiState.exerciseDrafts.sumOf { it.sets.size }
    val noteTemplates = listOf(
        stringResource(R.string.note_template_push),
        stringResource(R.string.note_template_pull),
        stringResource(R.string.note_template_legs),
        stringResource(R.string.note_template_upper),
        stringResource(R.string.note_template_lower),
        stringResource(R.string.note_template_deload)
    )

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 14.dp, top = 12.dp, end = 14.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        text = stringResource(R.string.add_workout_intro_title),
                        style = MaterialTheme.typography.headlineSmall,
                        color = Color.White
                    )
                    Text(
                        text = stringResource(R.string.add_workout_intro_supporting),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.9f)
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        InfoPill(
                            text = stringResource(R.string.add_workout_active_exercises, selectedExerciseCount),
                            accent = Color.White,
                            modifier = Modifier.weight(1f)
                        )
                        InfoPill(
                            text = stringResource(R.string.add_workout_total_sets, totalSetCount),
                            accent = Color.White,
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    SectionTitle(
                        eyebrow = stringResource(R.string.label_workout_date),
                        title = stringResource(R.string.label_note)
                    )
                    InfoPill(
                        text = DateTimeUtils.formatDate(uiState.workoutDate),
                        accent = MaterialTheme.colorScheme.secondary
                    )
                    OutlinedTextField(
                        value = uiState.note,
                        onValueChange = onNoteChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.label_note)) },
                        placeholder = { Text(stringResource(R.string.hint_note)) },
                        minLines = 2,
                        maxLines = 4
                    )
                    Text(
                        text = stringResource(R.string.add_workout_plan_templates),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(noteTemplates) { template ->
                            SuggestionChip(
                                onClick = {
                                    onNoteChange(
                                        appendTemplateToNote(
                                            currentNote = uiState.note,
                                            template = template
                                        )
                                    )
                                },
                                label = { Text(template) }
                            )
                        }
                    }
                }
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    SectionTitle(
                        eyebrow = stringResource(R.string.add_workout_plan_templates),
                        title = stringResource(R.string.template_picker_title)
                    )
                    OutlinedButton(
                        onClick = onRepeatLastWorkout,
                        enabled = uiState.canRepeatFromLast && !uiState.isTemplateLoading,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(imageVector = Icons.Default.Replay, contentDescription = null)
                        Text(
                            text = stringResource(R.string.action_repeat_last_workout),
                            modifier = Modifier.padding(start = 8.dp),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = onOpenTemplatePicker,
                        enabled = uiState.workoutTemplates.isNotEmpty() && !uiState.isTemplateLoading,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(imageVector = Icons.Default.Replay, contentDescription = null)
                        Text(
                            text = stringResource(R.string.action_copy_workout_day),
                            modifier = Modifier.padding(start = 8.dp),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        item {
            TrainingProfilePanel(
                profile = uiState.trainingProfile,
                onTrainingSplitSelected = onTrainingSplitSelected,
                onWorkoutsPerWeekSelected = onWorkoutsPerWeekSelected,
                onTrainingGoalSelected = onTrainingGoalSelected,
                onCalorieModeSelected = onCalorieModeSelected
            )
        }

        item {
            SmartCoachPanel(onGenerateSmartWorkout = onGenerateSmartWorkout)
        }

        if (uiState.hasValidationError) {
            item {
                AppPanel(
                    modifier = Modifier.fillMaxWidth(),
                    containerColor = MaterialTheme.colorScheme.error.copy(alpha = 0.20f),
                    highlighted = true
                ) {
                    Text(
                        text = stringResource(R.string.message_validation_error),
                        modifier = Modifier.padding(14.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }

        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                SectionTitle(
                    eyebrow = stringResource(R.string.title_add_workout),
                    title = stringResource(R.string.title_add_exercise_to_workout_section),
                    supporting = if (uiState.hasValidationError) {
                        stringResource(R.string.message_validation_error)
                    } else {
                        stringResource(R.string.add_workout_intro_supporting)
                    },
                    modifier = Modifier.weight(1f)
                )
                Button(onClick = onAddExerciseDraft) {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = stringResource(R.string.action_add_exercise)
                    )
                }
            }
        }

        itemsIndexed(
            items = uiState.exerciseDrafts,
            key = { _, draft -> draft.draftId }
        ) { index, draft ->
            ExerciseDraftCard(
                index = index,
                draft = draft,
                exercises = uiState.exercises,
                frequentExerciseIds = uiState.frequentExerciseIds,
                lastWeight = draft.exerciseId?.let { uiState.lastWeights[it] },
                recommendation = draft.exerciseId?.let { uiState.workoutRecommendations[it] },
                onExerciseSelected = { selectedExerciseId ->
                    onExerciseSelected(draft.draftId, selectedExerciseId)
                },
                onAddSet = { onAddSet(draft.draftId) },
                onAddSetFromPrevious = { increment ->
                    onAddSetFromPrevious(draft.draftId, increment)
                },
                onRemoveSet = { setIndex -> onRemoveSet(draft.draftId, setIndex) },
                onWeightChanged = { setIndex, value ->
                    onSetWeightChanged(draft.draftId, setIndex, value)
                },
                onRepsChanged = { setIndex, value ->
                    onSetRepsChanged(draft.draftId, setIndex, value)
                },
                onApplyLastWeight = { onApplyLastWeight(draft.draftId) },
                onApplyWorkoutRecommendation = { onApplyWorkoutRecommendation(draft.draftId) },
                onRemoveExerciseDraft = { onRemoveExerciseDraft(draft.draftId) }
            )
        }

        if (uiState.exerciseDrafts.isEmpty()) {
            item {
                EmptyStatePanel(
                    title = stringResource(R.string.action_add_exercise),
                    supporting = stringResource(R.string.add_workout_intro_supporting),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    SectionTitle(
                        eyebrow = stringResource(R.string.title_add_workout),
                        title = stringResource(R.string.action_sync_plan_to_watch),
                        supporting = stringResource(R.string.add_workout_save_hint)
                    )
                    OutlinedButton(
                        onClick = onSyncPlanToWatch,
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !uiState.isSyncingPlanToWatch
                    ) {
                        if (uiState.isSyncingPlanToWatch) {
                            CircularProgressIndicator(
                                modifier = Modifier
                                    .padding(end = 8.dp)
                                    .size(18.dp),
                                strokeWidth = 2.dp
                            )
                        }
                        Text(
                            text = if (uiState.isSyncingPlanToWatch) {
                                stringResource(R.string.action_sync_plan_to_watch_in_progress)
                            } else {
                                stringResource(R.string.action_sync_plan_to_watch)
                            }
                        )
                    }
                    when (uiState.didSyncPlanToWatch) {
                        true -> Text(
                            text = stringResource(R.string.message_plan_sync_success),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                        false -> Text(
                            text = uiState.watchPlanSyncError
                                ?: stringResource(R.string.message_plan_sync_failed),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                        null -> Unit
                    }
                }
            }
        }

        item {
            Button(
                onClick = onSaveWorkout,
                modifier = Modifier.fillMaxWidth(),
                enabled = !uiState.isSaving
            ) {
                if (uiState.isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .padding(end = 8.dp)
                            .size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Text(text = stringResource(R.string.action_save_workout))
            }
        }
    }

    if (uiState.isTemplatePickerOpen) {
        ModalBottomSheet(
            onDismissRequest = onCloseTemplatePicker,
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            WorkoutTemplatePickerContent(
                templates = uiState.workoutTemplates,
                onCopyWorkoutTemplate = onCopyWorkoutTemplate,
                onDismiss = onCloseTemplatePicker
            )
        }
    }
}

@Composable
private fun TrainingProfilePanel(
    profile: TrainingProfile,
    onTrainingSplitSelected: (TrainingSplit) -> Unit,
    onWorkoutsPerWeekSelected: (Int) -> Unit,
    onTrainingGoalSelected: (TrainingGoal) -> Unit,
    onCalorieModeSelected: (CalorieMode) -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(R.string.title_add_workout),
                title = stringResource(R.string.training_profile_title),
                supporting = stringResource(R.string.training_profile_supporting)
            )

            Text(
                text = stringResource(R.string.training_profile_split),
                style = MaterialTheme.typography.labelLarge
            )
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(TrainingSplit.entries) { split ->
                    FilterChip(
                        selected = profile.split == split,
                        onClick = { onTrainingSplitSelected(split) },
                        label = { Text(split.label()) }
                    )
                }
            }

            Text(
                text = stringResource(R.string.training_profile_frequency),
                style = MaterialTheme.typography.labelLarge
            )
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items((2..6).toList()) { value ->
                    FilterChip(
                        selected = profile.workoutsPerWeek == value,
                        onClick = { onWorkoutsPerWeekSelected(value) },
                        label = { Text(stringResource(R.string.training_profile_days_value, value)) }
                    )
                }
            }

            Text(
                text = stringResource(R.string.training_profile_goal),
                style = MaterialTheme.typography.labelLarge
            )
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(TrainingGoal.entries) { goal ->
                    FilterChip(
                        selected = profile.goal == goal,
                        onClick = { onTrainingGoalSelected(goal) },
                        label = { Text(goal.label()) }
                    )
                }
            }

            Text(
                text = stringResource(R.string.training_profile_calories),
                style = MaterialTheme.typography.labelLarge
            )
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(CalorieMode.entries) { mode ->
                    FilterChip(
                        selected = profile.calorieMode == mode,
                        onClick = { onCalorieModeSelected(mode) },
                        label = { Text(mode.label()) }
                    )
                }
            }

        }
    }
}

@Composable
private fun SmartCoachPanel(onGenerateSmartWorkout: () -> Unit) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                SectionTitle(
                    eyebrow = stringResource(R.string.smart_coach_title),
                    title = stringResource(R.string.action_generate_smart_workout),
                    supporting = stringResource(R.string.training_profile_supporting),
                    modifier = Modifier.weight(1f)
                )
            }
            Button(
                onClick = onGenerateSmartWorkout,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(imageVector = Icons.Default.AutoAwesome, contentDescription = null)
                Text(
                    text = stringResource(R.string.action_generate_smart_workout),
                    modifier = Modifier.padding(start = 8.dp),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun TrainingSplit.label(): String {
    return when (this) {
        TrainingSplit.UpperLower -> stringResource(R.string.training_split_upper_lower)
        TrainingSplit.FullBody -> stringResource(R.string.training_split_full_body)
        TrainingSplit.PushPullLegs -> stringResource(R.string.training_split_push_pull_legs)
        TrainingSplit.Custom -> stringResource(R.string.training_split_custom)
    }
}

@Composable
private fun TrainingGoal.label(): String {
    return when (this) {
        TrainingGoal.AestheticFatLoss -> stringResource(R.string.training_goal_aesthetic_fat_loss)
        TrainingGoal.MuscleGain -> stringResource(R.string.training_goal_muscle_gain)
        TrainingGoal.Strength -> stringResource(R.string.training_goal_strength)
        TrainingGoal.Balanced -> stringResource(R.string.training_goal_balanced)
    }
}

@Composable
private fun CalorieMode.label(): String {
    return when (this) {
        CalorieMode.Deficit -> stringResource(R.string.calorie_mode_deficit)
        CalorieMode.Maintenance -> stringResource(R.string.calorie_mode_maintenance)
        CalorieMode.Surplus -> stringResource(R.string.calorie_mode_surplus)
    }
}

@Composable
private fun WorkoutTemplatePickerContent(
    templates: List<WorkoutTemplatePreviewUiModel>,
    onCopyWorkoutTemplate: (Long) -> Unit,
    onDismiss: () -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        item {
            Text(
                text = stringResource(R.string.template_picker_title),
                style = MaterialTheme.typography.headlineSmall
            )
        }

        if (templates.isEmpty()) {
            item {
                Text(
                    text = stringResource(R.string.template_picker_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        } else {
            items(
                items = templates,
                key = { it.sessionId }
            ) { template ->
                AppPanel(
                    modifier = Modifier.fillMaxWidth(),
                    highlighted = true
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(
                            text = DateTimeUtils.formatDate(template.date),
                            style = MaterialTheme.typography.titleSmall
                        )
                        Text(
                            text = stringResource(
                                R.string.template_picker_summary,
                                template.exerciseCount,
                                template.setCount,
                                String.format(Locale.getDefault(), "%.0f", template.totalVolume)
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Button(
                            onClick = { onCopyWorkoutTemplate(template.sessionId) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(stringResource(R.string.action_copy_workout_day))
                        }
                    }
                }
            }
        }

        item {
            HorizontalDivider()
            OutlinedButton(
                onClick = onDismiss,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp)
            ) {
                Text(stringResource(R.string.action_cancel))
            }
        }
    }
}

private fun appendTemplateToNote(
    currentNote: String,
    template: String
): String {
    val trimmed = currentNote.trim()
    if (trimmed.isBlank()) {
        return template
    }
    if (trimmed.contains(template, ignoreCase = true)) {
        return trimmed
    }
    return "$trimmed | $template"
}

@Composable
private fun ExerciseDraftCard(
    index: Int,
    draft: ExerciseInputState,
    exercises: List<ExerciseEntity>,
    frequentExerciseIds: List<Long>,
    lastWeight: Double?,
    recommendation: WorkoutRecommendation?,
    onExerciseSelected: (Long) -> Unit,
    onAddSet: () -> Unit,
    onAddSetFromPrevious: (Double) -> Unit,
    onRemoveSet: (Int) -> Unit,
    onWeightChanged: (Int, String) -> Unit,
    onRepsChanged: (Int, String) -> Unit,
    onApplyLastWeight: () -> Unit,
    onApplyWorkoutRecommendation: () -> Unit,
    onRemoveExerciseDraft: () -> Unit
) {
    var isExpanded by rememberSaveable(draft.draftId) { mutableStateOf(true) }
    val selectedExercise = exercises.firstOrNull { it.id == draft.exerciseId }
    val muscleIntensities = remember(selectedExercise?.name) {
        selectedExercise
            ?.let { defaultContributionsForExercise(it.name) }
            .orEmpty()
            .associate { contribution -> contribution.muscleId to contribution.weight.toFloat() }
    }
    val setCountLabel = stringResource(R.string.exercise_set_count_compact, draft.sets.size)
    val setSummary = remember(draft.sets, setCountLabel) {
        val details = draft.sets.joinToString(separator = " · ") { set ->
            val weight = set.weight.ifBlank { "—" }
            val reps = set.reps.ifBlank { "—" }
            "$weight kg × $reps"
        }
        if (details.isBlank()) setCountLabel else "$setCountLabel · $details"
    }

    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = selectedExercise?.let { localizedExerciseName(it.name) }
                            ?: stringResource(R.string.exercise_block_title, index + 1),
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = lastWeight?.let { stringResource(R.string.label_last_weight, it) }
                            ?: setCountLabel,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                IconButton(onClick = { isExpanded = !isExpanded }) {
                    Icon(
                        imageVector = if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        contentDescription = stringResource(
                            if (isExpanded) R.string.cd_collapse_exercise else R.string.cd_expand_exercise
                        )
                    )
                }
                IconButton(onClick = onRemoveExerciseDraft) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = stringResource(R.string.cd_remove_exercise),
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            }

            if (!isExpanded) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = setSummary,
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (muscleIntensities.isNotEmpty()) {
                        ExerciseMuscleMap(
                            muscleIntensities = muscleIntensities,
                            modifier = Modifier.size(width = 96.dp, height = 72.dp)
                        )
                    }
                }
            }

            if (isExpanded) {
            ExerciseSelector(
                selectedExerciseId = draft.exerciseId,
                exercises = exercises,
                frequentExerciseIds = frequentExerciseIds,
                onExerciseSelected = onExerciseSelected,
                modifier = Modifier.fillMaxWidth()
            )

            if (muscleIntensities.isNotEmpty()) {
                ExerciseMuscleBreakdownCard(
                    exerciseName = selectedExercise?.name.orEmpty(),
                    muscleIntensities = muscleIntensities,
                    framed = false
                )
            }

            if (lastWeight != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = stringResource(R.string.label_last_weight, lastWeight),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    OutlinedButton(onClick = onApplyLastWeight) {
                        Text(text = stringResource(R.string.action_apply_last_weight))
                    }
                }
            }

            if (recommendation != null) {
                SmartRecommendationPanel(
                    recommendation = recommendation,
                    onApplyWorkoutRecommendation = onApplyWorkoutRecommendation
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = onAddSet,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(text = stringResource(R.string.action_add_set))
                }
                OutlinedButton(
                    onClick = { onAddSetFromPrevious(0.0) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(text = stringResource(R.string.action_copy_last_set))
                }
            }

            OutlinedButton(
                onClick = { onAddSetFromPrevious(2.5) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.action_copy_last_plus))
            }

            draft.sets.forEachIndexed { setIndex, set ->
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = GymControlShape,
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.48f)
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = stringResource(R.string.label_set, setIndex + 1),
                                style = MaterialTheme.typography.labelLarge,
                                modifier = Modifier.weight(1f)
                            )
                            IconButton(onClick = { onRemoveSet(setIndex) }) {
                                Icon(
                                    imageVector = Icons.Default.Delete,
                                    contentDescription = stringResource(R.string.cd_remove_set),
                                    tint = MaterialTheme.colorScheme.error
                                )
                            }
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            OutlinedTextField(
                                value = set.weight,
                                onValueChange = { onWeightChanged(setIndex, it) },
                                modifier = Modifier.weight(1f),
                                label = { Text(stringResource(R.string.label_weight_kg)) },
                                placeholder = { Text(stringResource(R.string.hint_optional)) },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                singleLine = true
                            )
                            OutlinedTextField(
                                value = set.reps,
                                onValueChange = { onRepsChanged(setIndex, it) },
                                modifier = Modifier.weight(1f),
                                label = { Text(stringResource(R.string.label_reps)) },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                singleLine = true
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
private fun SmartRecommendationPanel(
    recommendation: WorkoutRecommendation,
    onApplyWorkoutRecommendation: () -> Unit
) {
    val lightWeightLabel = stringResource(R.string.smart_coach_light_weight)

    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = false
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = stringResource(R.string.smart_coach_title),
                        style = MaterialTheme.typography.titleSmall
                    )
                    Text(
                        text = recommendation.kind.smartCoachLabel(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Text(
                text = recommendation.sets.joinToString(separator = "  |  ") { set ->
                    val weight = set.weight?.let { String.format(Locale.getDefault(), "%.1f kg", it) }
                        ?: lightWeightLabel
                    "$weight x ${set.reps}"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface
            )

            LinearProgressIndicator(
                progress = { recommendation.confidence },
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )

            Text(
                text = stringResource(
                    R.string.smart_coach_confidence,
                    (recommendation.confidence * 100).toInt()
                ),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            recommendation.reasons.take(3).forEach { reason ->
                Text(
                    text = reason.smartCoachLabel(recommendation.daysSinceLastSession),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Button(
                onClick = onApplyWorkoutRecommendation,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(imageVector = Icons.Default.AutoAwesome, contentDescription = null)
                Text(
                    text = stringResource(R.string.action_apply_smart_plan),
                    modifier = Modifier.padding(start = 8.dp)
                )
            }
        }
    }
}

@Composable
private fun WorkoutRecommendationKind.smartCoachLabel(): String {
    return when (this) {
        WorkoutRecommendationKind.NewExercise -> stringResource(R.string.smart_kind_new_exercise)
        WorkoutRecommendationKind.ProgressiveOverload -> stringResource(R.string.smart_kind_progressive_overload)
        WorkoutRecommendationKind.HoldAndBuild -> stringResource(R.string.smart_kind_hold_and_build)
        WorkoutRecommendationKind.Deload -> stringResource(R.string.smart_kind_deload)
        WorkoutRecommendationKind.Comeback -> stringResource(R.string.smart_kind_comeback)
        WorkoutRecommendationKind.PlateauBreak -> stringResource(R.string.smart_kind_plateau_break)
    }
}

@Composable
private fun WorkoutRecommendationReason.smartCoachLabel(daysSinceLastSession: Int?): String {
    return when (this) {
        WorkoutRecommendationReason.NoHistory -> stringResource(R.string.smart_reason_no_history)
        WorkoutRecommendationReason.LastSessionStrong -> stringResource(R.string.smart_reason_last_strong)
        WorkoutRecommendationReason.LastSessionUnstable -> stringResource(R.string.smart_reason_last_unstable)
        WorkoutRecommendationReason.RecentBreak -> stringResource(
            R.string.smart_reason_recent_break,
            daysSinceLastSession ?: 0
        )
        WorkoutRecommendationReason.VolumeTrendingUp -> stringResource(R.string.smart_reason_volume_up)
        WorkoutRecommendationReason.VolumeDropped -> stringResource(R.string.smart_reason_volume_dropped)
        WorkoutRecommendationReason.PlateauDetected -> stringResource(R.string.smart_reason_plateau)
        WorkoutRecommendationReason.NearPersonalBest -> stringResource(R.string.smart_reason_near_best)
        WorkoutRecommendationReason.ConservativeIncrease -> stringResource(R.string.smart_reason_conservative)
        WorkoutRecommendationReason.AestheticGoal -> stringResource(R.string.smart_reason_aesthetic_goal)
        WorkoutRecommendationReason.CalorieDeficit -> stringResource(R.string.smart_reason_calorie_deficit)
        WorkoutRecommendationReason.FourDayUpperLower -> stringResource(R.string.smart_reason_upper_lower)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExerciseSelector(
    selectedExerciseId: Long?,
    exercises: List<ExerciseEntity>,
    frequentExerciseIds: List<Long>,
    onExerciseSelected: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    var frequentOnly by rememberSaveable { mutableStateOf(false) }
    val languageTag = currentAppLanguageTag()
    val selectedLabel = exercises
        .firstOrNull { it.id == selectedExerciseId }
        ?.let { BuiltInExerciseCatalog.displayName(it.name, languageTag) }
        ?: stringResource(R.string.label_select_exercise)
    val frequentRank = remember(frequentExerciseIds) {
        frequentExerciseIds.withIndex().associate { (index, id) -> id to index }
    }
    val normalizedQuery = query.trim().lowercase(Locale.ROOT)
    val visibleExercises = remember(
        exercises,
        frequentRank,
        frequentOnly,
        normalizedQuery,
        languageTag
    ) {
        exercises
            .filter { exercise ->
                val definition = BuiltInExerciseCatalog.definitionForName(exercise.name)
                val matchesSearch = normalizedQuery.isEmpty() || buildList {
                    add(exercise.name)
                    add(BuiltInExerciseCatalog.displayName(exercise.name, languageTag))
                    definition?.let {
                        add(it.nameEn)
                        add(it.nameUk)
                        addAll(it.legacyAliases)
                    }
                }.any { it.lowercase(Locale.ROOT).contains(normalizedQuery) }
                matchesSearch && (!frequentOnly || exercise.id in frequentRank)
            }
            .sortedWith { left, right ->
                if (frequentOnly) {
                    (frequentRank[left.id] ?: Int.MAX_VALUE)
                        .compareTo(frequentRank[right.id] ?: Int.MAX_VALUE)
                } else {
                    BuiltInExerciseCatalog.displayName(left.name, languageTag).compareTo(
                        BuiltInExerciseCatalog.displayName(right.name, languageTag),
                        ignoreCase = true
                    )
                }
            }
    }

    OutlinedButton(
        onClick = { expanded = true },
        modifier = modifier.fillMaxWidth()
    ) {
        Icon(imageVector = Icons.Default.Search, contentDescription = null)
        Text(
            text = selectedLabel,
            modifier = Modifier.padding(start = 8.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }

    if (expanded) {
        ModalBottomSheet(
            onDismissRequest = { expanded = false },
            containerColor = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = stringResource(R.string.label_select_exercise),
                    style = MaterialTheme.typography.headlineSmall
                )
                OutlinedTextField(
                    value = query,
                    onValueChange = { query = it },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    label = { Text(stringResource(R.string.exercise_search_label)) },
                    placeholder = { Text(stringResource(R.string.exercise_search_placeholder)) },
                    leadingIcon = {
                        Icon(imageVector = Icons.Default.Search, contentDescription = null)
                    }
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = !frequentOnly,
                        onClick = { frequentOnly = false },
                        label = { Text(stringResource(R.string.exercise_picker_all)) }
                    )
                    FilterChip(
                        selected = frequentOnly,
                        onClick = { frequentOnly = true },
                        label = { Text(stringResource(R.string.exercise_picker_frequent)) },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Star,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    )
                }
                Text(
                    text = stringResource(R.string.exercise_search_result_count, visibleExercises.size),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                LazyColumn(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 480.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (visibleExercises.isEmpty()) {
                        item {
                            Text(
                                text = if (frequentOnly && frequentExerciseIds.isEmpty()) {
                                    stringResource(R.string.exercise_picker_frequent_empty)
                                } else {
                                    stringResource(R.string.exercise_search_no_results)
                                },
                                modifier = Modifier.padding(vertical = 20.dp),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    } else {
                        items(visibleExercises, key = { it.id }) { exercise ->
                            OutlinedButton(
                                onClick = {
                                    onExerciseSelected(exercise.id)
                                    expanded = false
                                },
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Text(
                                    text = BuiltInExerciseCatalog.displayName(
                                        exercise.name,
                                        languageTag
                                    ),
                                    modifier = Modifier.weight(1f),
                                    maxLines = 2,
                                    overflow = TextOverflow.Ellipsis
                                )
                                if (exercise.id == selectedExerciseId) {
                                    Spacer(modifier = Modifier.size(8.dp))
                                    Icon(
                                        imageVector = Icons.Default.CheckCircle,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary
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
