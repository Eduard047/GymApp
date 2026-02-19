package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
    onRemoveSet: (Long, Int) -> Unit,
    onSetWeightChanged: (Long, Int, String) -> Unit,
    onSetRepsChanged: (Long, Int, String) -> Unit,
    onApplyLastWeight: (Long) -> Unit,
    onRepeatLastWorkout: () -> Unit,
    onSaveWorkout: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = stringResource(R.string.label_workout_date),
                    style = MaterialTheme.typography.labelLarge
                )
                Text(
                    text = DateTimeUtils.formatDate(uiState.workoutDate),
                    style = MaterialTheme.typography.titleMedium
                )
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

        OutlinedTextField(
            value = uiState.note,
            onValueChange = onNoteChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text(stringResource(R.string.label_note)) },
            placeholder = { Text(stringResource(R.string.hint_note)) },
            minLines = 2,
            maxLines = 4
        )

        if (uiState.hasValidationError) {
            Text(
                text = stringResource(R.string.message_validation_error),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error
            )
        }

        uiState.exerciseDrafts.forEachIndexed { index, draft ->
            ExerciseDraftCard(
                index = index,
                draft = draft,
                exercises = uiState.exercises,
                lastWeight = draft.exerciseId?.let { uiState.lastWeights[it] },
                onExerciseSelected = { selectedExerciseId ->
                    onExerciseSelected(draft.draftId, selectedExerciseId)
                },
                onAddSet = { onAddSet(draft.draftId) },
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

        Button(
            onClick = onSaveWorkout,
            modifier = Modifier.fillMaxWidth(),
            enabled = !uiState.isSaving
        ) {
            Text(text = stringResource(R.string.action_save_workout))
        }
    }
}

@Composable
private fun ExerciseDraftCard(
    index: Int,
    draft: ExerciseInputState,
    exercises: List<ExerciseEntity>,
    lastWeight: Double?,
    onExerciseSelected: (Long) -> Unit,
    onAddSet: () -> Unit,
    onRemoveSet: (Int) -> Unit,
    onWeightChanged: (Int, String) -> Unit,
    onRepsChanged: (Int, String) -> Unit,
    onApplyLastWeight: () -> Unit,
    onRemoveExerciseDraft: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(R.string.exercise_block_title, index + 1),
                style = MaterialTheme.typography.titleSmall
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ExerciseSelector(
                    selectedExerciseId = draft.exerciseId,
                    exercises = exercises,
                    onExerciseSelected = onExerciseSelected,
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = onRemoveExerciseDraft) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = stringResource(R.string.cd_remove_exercise)
                    )
                }
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

            draft.sets.forEachIndexed { index, set ->
                Text(
                    text = stringResource(R.string.label_set, index + 1),
                    style = MaterialTheme.typography.labelLarge
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = set.weight,
                        onValueChange = { onWeightChanged(index, it) },
                        modifier = Modifier.weight(1f),
                        label = { Text(stringResource(R.string.label_weight_kg)) },
                        placeholder = { Text(stringResource(R.string.hint_optional)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = set.reps,
                        onValueChange = { onRepsChanged(index, it) },
                        modifier = Modifier.weight(1f),
                        label = { Text(stringResource(R.string.label_reps)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true
                    )
                    IconButton(onClick = { onRemoveSet(index) }) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = stringResource(R.string.cd_remove_set)
                        )
                    }
                }
            }

            OutlinedButton(
                onClick = onAddSet,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = stringResource(R.string.action_add_set),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
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
