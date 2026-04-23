package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.viewmodel.AddWorkoutUiState
import com.example.gymapp.ui.viewmodel.ExerciseInputState
import com.example.gymapp.util.DateTimeUtils

@Composable
fun AddWorkoutScreen(
    uiState: AddWorkoutUiState,
    onNoteChange: (String) -> Unit,
    onAddExerciseDraft: () -> Unit,
    onRemoveExerciseDraft: (Long) -> Unit,
    onExerciseSelected: (Long, Long) -> Unit,
    onAddSet: (Long) -> Unit,
    onAddSetFromPrevious: (Long, Double) -> Unit,
    onRemoveSet: (Long, Int) -> Unit,
    onSetWeightChanged: (Long, Int, String) -> Unit,
    onSetRepsChanged: (Long, Int, String) -> Unit,
    onApplyLastWeight: (Long) -> Unit,
    onRepeatLastWorkout: () -> Unit,
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
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(imageVector = Icons.Default.Replay, contentDescription = null)
                        Text(
                            text = stringResource(R.string.action_repeat_last_workout),
                            modifier = Modifier.padding(start = 8.dp)
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
    onExerciseSelected: (Long) -> Unit,
    onAddSet: () -> Unit,
    onAddSetFromPrevious: (Double) -> Unit,
    onRemoveSet: (Int) -> Unit,
    onWeightChanged: (Int, String) -> Unit,
    onRepsChanged: (Int, String) -> Unit,
    onApplyLastWeight: () -> Unit,
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
