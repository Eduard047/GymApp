package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.WorkoutRecommendation
import com.example.gymapp.data.repository.WorkoutRecommendationKind
import com.example.gymapp.data.repository.WorkoutRecommendationReason
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.viewmodel.AddWorkoutUiState
import com.example.gymapp.ui.viewmodel.ExerciseInputState
import com.example.gymapp.ui.viewmodel.WorkoutTemplatePreviewUiModel
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
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        text = stringResource(R.string.add_workout_intro_title),
                        style = MaterialTheme.typography.titleLarge,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                    Text(
                        text = stringResource(R.string.add_workout_intro_supporting),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.9f)
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        InfoPill(
                            text = stringResource(R.string.label_workout_date),
                            accent = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.weight(1f)
                        )
                        InfoPill(
                            text = DateTimeUtils.formatDate(uiState.workoutDate),
                            accent = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.weight(2f)
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        InfoPill(
                            text = stringResource(R.string.add_workout_active_exercises, selectedExerciseCount),
                            accent = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.weight(1f)
                        )
                        InfoPill(
                            text = stringResource(R.string.add_workout_total_sets, totalSetCount),
                            accent = MaterialTheme.colorScheme.onPrimary,
                            modifier = Modifier.weight(1f)
                        )
                    }
                    OutlinedButton(
                        onClick = onRepeatLastWorkout,
                        enabled = uiState.canRepeatFromLast && !uiState.isTemplateLoading,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            disabledContentColor = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.55f)
                        ),
                        border = BorderStroke(
                            1.dp,
                            MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.64f)
                        )
                    ) {
                        Icon(imageVector = Icons.Default.Replay, contentDescription = null)
                        Text(
                            text = stringResource(R.string.action_repeat_last_workout),
                            modifier = Modifier.padding(start = 8.dp),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = onOpenTemplatePicker,
                        enabled = uiState.workoutTemplates.isNotEmpty() && !uiState.isTemplateLoading,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            disabledContentColor = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.55f)
                        ),
                        border = BorderStroke(
                            1.dp,
                            MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.64f)
                        )
                    ) {
                        Icon(imageVector = Icons.Default.Replay, contentDescription = null)
                        Text(
                            text = stringResource(R.string.action_copy_workout_day),
                            modifier = Modifier.padding(start = 8.dp),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = stringResource(R.string.label_note),
                        style = MaterialTheme.typography.titleSmall
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
            TrainingProfilePanel(
                profile = uiState.trainingProfile,
                onTrainingSplitSelected = onTrainingSplitSelected,
                onWorkoutsPerWeekSelected = onWorkoutsPerWeekSelected,
                onTrainingGoalSelected = onTrainingGoalSelected,
                onCalorieModeSelected = onCalorieModeSelected,
                onGenerateSmartWorkout = onGenerateSmartWorkout
            )
        }

        if (uiState.hasValidationError) {
            item {
                Text(
                    text = stringResource(R.string.message_validation_error),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error
                )
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

        item {
            OutlinedButton(
                onClick = onAddExerciseDraft,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(imageVector = Icons.Default.Add, contentDescription = null)
                Text(
                    text = stringResource(R.string.action_add_exercise),
                    modifier = Modifier.padding(start = 8.dp)
                )
            }
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Text(
                        text = stringResource(R.string.add_workout_save_hint),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedButton(
                        onClick = onSyncPlanToWatch,
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !uiState.isSyncingPlanToWatch
                    ) {
                        Text(text = stringResource(R.string.action_sync_plan_to_watch))
                    }
                    when (uiState.didSyncPlanToWatch) {
                        true -> Text(
                            text = stringResource(R.string.message_plan_sync_success),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                        false -> Text(
                            text = stringResource(R.string.message_plan_sync_failed),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                        null -> Unit
                    }
                    Button(
                        onClick = onSaveWorkout,
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !uiState.isSaving
                    ) {
                        Text(text = stringResource(R.string.action_save_workout))
                    }
                }
            }
        }
    }

    if (uiState.isTemplatePickerOpen) {
        ModalBottomSheet(onDismissRequest = onCloseTemplatePicker) {
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
    onCalorieModeSelected: (CalorieMode) -> Unit,
    onGenerateSmartWorkout: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
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
                        text = stringResource(R.string.training_profile_title),
                        style = MaterialTheme.typography.titleSmall
                    )
                    Text(
                        text = stringResource(R.string.training_profile_supporting),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

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
    AppPanel(
        modifier = Modifier.fillMaxWidth(),
        highlighted = true
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.exercise_block_title, index + 1),
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = onRemoveExerciseDraft) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = stringResource(R.string.cd_remove_exercise)
                    )
                }
            }

            ExerciseSelector(
                selectedExerciseId = draft.exerciseId,
                exercises = exercises,
                onExerciseSelected = onExerciseSelected,
                modifier = Modifier.fillMaxWidth()
            )

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
                Text(
                    text = stringResource(R.string.label_set, setIndex + 1),
                    style = MaterialTheme.typography.labelLarge
                )
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
                    IconButton(onClick = { onRemoveSet(setIndex) }) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = stringResource(R.string.cd_remove_set)
                        )
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

@Composable
private fun ExerciseSelector(
    selectedExerciseId: Long?,
    exercises: List<ExerciseEntity>,
    onExerciseSelected: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    var expanded by remember(selectedExerciseId, exercises) { mutableStateOf(false) }
    val selectedLabel = exercises
        .firstOrNull { it.id == selectedExerciseId }
        ?.name
        ?: stringResource(R.string.label_select_exercise)

    Box(modifier = modifier) {
        OutlinedButton(
            onClick = { expanded = true },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                text = selectedLabel,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            exercises.forEach { exercise ->
                DropdownMenuItem(
                    text = { Text(exercise.name) },
                    onClick = {
                        onExerciseSelected(exercise.id)
                        expanded = false
                    }
                )
            }
        }
    }
}
