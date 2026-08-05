package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.viewmodel.ActiveWorkoutExerciseUiState
import com.example.gymapp.ui.viewmodel.ActiveWorkoutSetUiState
import com.example.gymapp.ui.viewmodel.ActiveWorkoutUiState
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.asString
import java.util.Locale

@Composable
fun ActiveWorkoutScreen(
    uiState: ActiveWorkoutUiState,
    onSetWeightChanged: (String, String) -> Unit,
    onSetRepsChanged: (String, String) -> Unit,
    onRecordSet: (String) -> Unit,
    onUndoLatestSet: (String) -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    onFinishWorkout: () -> Unit,
    onDiscardWorkout: () -> Unit,
    onDismissMessage: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showDiscardConfirmation by rememberSaveable { mutableStateOf(false) }

    when {
        uiState.isLoading -> {
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            return
        }
        uiState.isMissing -> {
            Box(
                modifier = modifier
                    .fillMaxSize()
                    .padding(16.dp),
                contentAlignment = Alignment.Center
            ) {
                EmptyStatePanel(
                    title = stringResource(R.string.active_workout_missing_title),
                    supporting = stringResource(R.string.active_workout_missing)
                )
            }
            return
        }
    }

    val operationInProgress = uiState.isFinishing || uiState.isDiscarding ||
        uiState.setRecordingsInFlight.isNotEmpty() || uiState.undoingSetId != null

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(start = 14.dp, top = 12.dp, end = 14.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            HeroPanel(modifier = Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        text = stringResource(R.string.active_workout_title),
                        style = MaterialTheme.typography.headlineSmall,
                        color = Color.White
                    )
                    Text(
                        text = stringResource(R.string.active_workout_supporting),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White.copy(alpha = 0.9f)
                    )
                    val progressDescription = stringResource(
                        R.string.active_workout_progress,
                        uiState.completedSetCount,
                        uiState.totalSetCount
                    )
                    Row(
                        modifier = Modifier.semantics {
                            stateDescription = progressDescription
                            progressBarRangeInfo = ProgressBarRangeInfo(
                                current = uiState.completedSetCount.toFloat(),
                                range = 0f..uiState.totalSetCount.coerceAtLeast(1).toFloat(),
                                steps = (uiState.totalSetCount - 1).coerceAtLeast(0)
                            )
                        },
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        InfoPill(
                            text = progressDescription
                        )
                        InfoPill(text = DateTimeUtils.formatDate(uiState.date))
                    }
                    if (uiState.restSecondsRemaining > 0) {
                        Text(
                            text = stringResource(
                                R.string.label_exercise_rest_remaining,
                                formatRestTime(uiState.restSecondsRemaining)
                            ),
                            style = MaterialTheme.typography.titleMedium,
                            color = Color.White
                        )
                    }
                }
            }
        }

        uiState.note?.takeIf(String::isNotBlank)?.let { note ->
            item {
                AppPanel(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.label_note),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Text(text = note, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }

        uiState.message?.takeIf { uiState.messageSetId == null }?.let { message ->
            item {
                AppPanel(
                    modifier = Modifier.fillMaxWidth(),
                    containerColor = MaterialTheme.colorScheme.error.copy(alpha = 0.16f),
                    highlighted = true
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = message.asString(),
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error
                        )
                        TextButton(onClick = onDismissMessage) {
                            Text(text = stringResource(R.string.action_close))
                        }
                    }
                }
            }
        }

        items(
            items = uiState.exercises,
            key = ActiveWorkoutExerciseUiState::id
        ) { exercise ->
            ActiveWorkoutExerciseCard(
                exercise = exercise,
                operationInProgress = operationInProgress,
                inFlightSetIds = uiState.setRecordingsInFlight,
                latestCompletedSetId = uiState.latestCompletedSetId,
                undoingSetId = uiState.undoingSetId,
                restSecondsRemaining = uiState.restSecondsRemaining,
                inlineMessage = uiState.message,
                inlineMessageSetId = uiState.messageSetId,
                onSetWeightChanged = onSetWeightChanged,
                onSetRepsChanged = onSetRepsChanged,
                onRecordSet = onRecordSet,
                onUndoLatestSet = onUndoLatestSet,
                onAdjustRestTimer = onAdjustRestTimer,
                onStopRestTimer = onStopRestTimer,
                onDismissMessage = onDismissMessage
            )
        }

        item {
            AppPanel(modifier = Modifier.fillMaxWidth(), highlighted = true) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    SectionTitle(
                        eyebrow = stringResource(R.string.active_workout_finish_eyebrow),
                        title = stringResource(R.string.action_finish_workout),
                        supporting = stringResource(R.string.active_workout_finish_supporting)
                    )
                    Button(
                        onClick = onFinishWorkout,
                        enabled = uiState.completedSetCount > 0 && !operationInProgress,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (uiState.isFinishing) {
                            CircularProgressIndicator(
                                modifier = Modifier
                                    .padding(end = 8.dp)
                                    .size(18.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                        } else {
                            Icon(imageVector = Icons.Default.CheckCircle, contentDescription = null)
                        }
                        Text(
                            text = stringResource(R.string.action_finish_workout),
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                    OutlinedButton(
                        onClick = { showDiscardConfirmation = true },
                        enabled = !operationInProgress,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(imageVector = Icons.Default.Delete, contentDescription = null)
                        Text(
                            text = stringResource(R.string.active_workout_discard_action),
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                    Text(
                        text = stringResource(R.string.active_workout_back_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }

    if (showDiscardConfirmation) {
        AlertDialog(
            onDismissRequest = { if (!uiState.isDiscarding) showDiscardConfirmation = false },
            title = { Text(text = stringResource(R.string.active_workout_discard_title)) },
            text = { Text(text = stringResource(R.string.active_workout_discard_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDiscardConfirmation = false
                        onDiscardWorkout()
                    },
                    enabled = !uiState.isDiscarding
                ) {
                    Text(text = stringResource(R.string.active_workout_discard_confirm))
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showDiscardConfirmation = false },
                    enabled = !uiState.isDiscarding
                ) {
                    Text(text = stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

@Composable
private fun ActiveWorkoutExerciseCard(
    exercise: ActiveWorkoutExerciseUiState,
    operationInProgress: Boolean,
    inFlightSetIds: Set<String>,
    latestCompletedSetId: String?,
    undoingSetId: String?,
    restSecondsRemaining: Int,
    inlineMessage: com.example.gymapp.util.LocalizedText?,
    inlineMessageSetId: String?,
    onSetWeightChanged: (String, String) -> Unit,
    onSetRepsChanged: (String, String) -> Unit,
    onRecordSet: (String) -> Unit,
    onUndoLatestSet: (String) -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    onDismissMessage: () -> Unit
) {
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SectionTitle(
                eyebrow = stringResource(
                    R.string.active_workout_exercise_number,
                    exercise.orderIndex + 1
                ),
                title = exercise.exerciseName,
                supporting = stringResource(
                    R.string.active_workout_exercise_progress,
                    exercise.sets.count(ActiveWorkoutSetUiState::isCompleted),
                    exercise.sets.size
                )
            )
            exercise.sets.forEach { set ->
                ActiveWorkoutSetRow(
                    set = set,
                    operationInProgress = operationInProgress,
                    isRecording = set.id in inFlightSetIds,
                    isLatestCompleted = set.id == latestCompletedSetId,
                    isUndoing = set.id == undoingSetId,
                    restDurationSeconds = exercise.restDurationSeconds,
                    restSecondsRemaining = if (set.id == latestCompletedSetId) {
                        restSecondsRemaining
                    } else {
                        0
                    },
                    inlineMessage = inlineMessage.takeIf { inlineMessageSetId == set.id },
                    onWeightChanged = { value -> onSetWeightChanged(set.id, value) },
                    onRepsChanged = { value -> onSetRepsChanged(set.id, value) },
                    onRecord = { onRecordSet(set.id) },
                    onUndo = { onUndoLatestSet(set.id) },
                    onAdjustRestTimer = onAdjustRestTimer,
                    onStopRestTimer = onStopRestTimer,
                    onDismissMessage = onDismissMessage
                )
            }
        }
    }
}

@Composable
private fun ActiveWorkoutSetRow(
    set: ActiveWorkoutSetUiState,
    operationInProgress: Boolean,
    isRecording: Boolean,
    isLatestCompleted: Boolean,
    isUndoing: Boolean,
    restDurationSeconds: Int,
    restSecondsRemaining: Int,
    inlineMessage: com.example.gymapp.util.LocalizedText?,
    onWeightChanged: (String) -> Unit,
    onRepsChanged: (String) -> Unit,
    onRecord: () -> Unit,
    onUndo: () -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    onDismissMessage: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.label_set, set.orderIndex + 1),
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.weight(1f)
            )
            if (set.isCompleted) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = stringResource(R.string.active_workout_set_completed),
                    tint = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = stringResource(R.string.active_workout_set_completed),
                    color = MaterialTheme.colorScheme.primary,
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedTextField(
                value = set.weightInput,
                onValueChange = onWeightChanged,
                label = { Text(text = stringResource(R.string.label_weight_kg)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                enabled = !set.isCompleted && !operationInProgress,
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = set.repsInput,
                onValueChange = onRepsChanged,
                label = { Text(text = stringResource(R.string.label_reps)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                enabled = !set.isCompleted && !operationInProgress,
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
        }
        if (!set.isCompleted) {
            Button(
                onClick = onRecord,
                enabled = !operationInProgress,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
            ) {
                if (isRecording) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .padding(end = 8.dp)
                            .size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Text(text = stringResource(R.string.action_log_set_and_rest, restDurationSeconds))
            }
        }
        if (isLatestCompleted) {
            if (restSecondsRemaining > 0) {
                AppPanel(
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics {
                            stateDescription = formatRestTime(restSecondsRemaining)
                        },
                    highlighted = true
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.active_workout_rest_saved),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Text(
                            text = formatRestTime(restSecondsRemaining),
                            style = MaterialTheme.typography.headlineSmall
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            val subtractDescription = stringResource(
                                R.string.active_workout_rest_subtract
                            )
                            val addDescription = stringResource(R.string.active_workout_rest_add)
                            OutlinedButton(
                                onClick = { onAdjustRestTimer(-15) },
                                modifier = Modifier
                                    .weight(1f)
                                    .heightIn(min = 48.dp)
                                    .semantics {
                                        contentDescription = subtractDescription
                                    }
                            ) { Text("−15") }
                            OutlinedButton(
                                onClick = { onAdjustRestTimer(15) },
                                modifier = Modifier
                                    .weight(1f)
                                    .heightIn(min = 48.dp)
                                    .semantics {
                                        contentDescription = addDescription
                                    }
                            ) { Text("+15") }
                            TextButton(
                                onClick = onStopRestTimer,
                                modifier = Modifier
                                    .weight(1f)
                                    .heightIn(min = 48.dp)
                            ) {
                                Text(stringResource(R.string.active_workout_rest_stop))
                            }
                        }
                    }
                }
            }
            OutlinedButton(
                onClick = onUndo,
                enabled = !operationInProgress,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
            ) {
                if (isUndoing) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .padding(end = 8.dp)
                            .size(18.dp),
                        strokeWidth = 2.dp
                    )
                }
                Text(stringResource(R.string.active_workout_undo_action))
            }
        }
        inlineMessage?.let { message ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = message.asString(),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
                TextButton(
                    onClick = onDismissMessage,
                    modifier = Modifier.heightIn(min = 48.dp)
                ) {
                    Text(stringResource(R.string.action_close))
                }
            }
        }
    }
}

private fun formatRestTime(totalSeconds: Int): String = String.format(
    Locale.getDefault(),
    "%02d:%02d",
    totalSeconds / 60,
    totalSeconds % 60
)
