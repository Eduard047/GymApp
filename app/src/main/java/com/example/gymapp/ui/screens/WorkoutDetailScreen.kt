package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.ui.viewmodel.WorkoutDetailEvent
import com.example.gymapp.ui.viewmodel.WorkoutDetailUiState
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.flow.Flow
import java.util.Locale

@Composable
fun WorkoutDetailScreen(
    uiState: WorkoutDetailUiState,
    events: Flow<WorkoutDetailEvent>,
    onAddSet: (Long) -> Unit,
    onAddSetFromLastWeight: (Long, Long) -> Unit,
    onDeleteSet: (SetEntryEntity) -> Unit,
    onUpdateSet: (SetEntryEntity, String, String) -> Unit,
    onUndoDelete: () -> Unit,
    onStartRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    modifier: Modifier = Modifier
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var editingSet by remember { mutableStateOf<SetEntryEntity?>(null) }
    var editWeight by remember { mutableStateOf("") }
    var editReps by remember { mutableStateOf("") }

    LaunchedEffect(events, context) {
        events.collect { event ->
            when (event) {
                WorkoutDetailEvent.SetDeleted -> {
                    val result = snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_set_deleted),
                        actionLabel = context.getString(R.string.action_undo),
                        duration = SnackbarDuration.Short
                    )
                    if (result == SnackbarResult.ActionPerformed) {
                        onUndoDelete()
                    }
                }

                WorkoutDetailEvent.InvalidInput -> {
                    snackbarHostState.showSnackbar(
                        message = context.getString(R.string.message_invalid_set_input),
                        duration = SnackbarDuration.Short
                    )
                }
            }
        }
    }

    Box(
        modifier = modifier.fillMaxSize()
    ) {
        val details = uiState.sessionDetails
        if (details == null) {
            Text(
                text = stringResource(R.string.empty_detail),
                modifier = Modifier.padding(16.dp)
            )
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    horizontal = 12.dp,
                    vertical = 10.dp
                ),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                item {
                    RestTimerCard(
                        restSecondsRemaining = uiState.restSecondsRemaining,
                        onStartRestTimer = onStartRestTimer,
                        onStopRestTimer = onStopRestTimer
                    )
                }
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                text = DateTimeUtils.formatDate(details.session.date),
                                style = MaterialTheme.typography.titleMedium
                            )
                            Text(
                                text = details.session.note
                                    ?.takeIf { it.isNotBlank() }
                                    ?.let { stringResource(R.string.details_note, it) }
                                    ?: stringResource(R.string.details_no_note),
                                style = MaterialTheme.typography.bodyLarge
                            )
                        }
                    }
                }

                items(
                    items = details.workoutExercises,
                    key = { it.workoutExercise.id }
                ) { exerciseDetails ->
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(
                            modifier = Modifier.padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = exerciseDetails.exercise.name,
                                    style = MaterialTheme.typography.titleMedium,
                                    modifier = Modifier.weight(1f),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                if (uiState.personalRecordFlags[exerciseDetails.workoutExercise.id] == true) {
                                    AssistChip(
                                        onClick = {},
                                        label = { Text(stringResource(R.string.label_personal_record)) },
                                        leadingIcon = {
                                            Icon(
                                                imageVector = Icons.Default.EmojiEvents,
                                                contentDescription = null
                                            )
                                        }
                                    )
                                }
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = stringResource(R.string.label_set_short),
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(R.string.label_weight_kg),
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(R.string.label_reps),
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            exerciseDetails.sets.forEachIndexed { index, setEntry ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Text(
                                        text = stringResource(R.string.label_set, index + 1),
                                        modifier = Modifier.weight(1f),
                                        maxLines = 1
                                    )
                                    Text(
                                        text = String.format(Locale.getDefault(), "%.1f", setEntry.weight),
                                        modifier = Modifier.weight(1f),
                                        maxLines = 1
                                    )
                                    Text(
                                        text = setEntry.reps.toString(),
                                        modifier = Modifier.weight(1f),
                                        maxLines = 1
                                    )
                                    IconButton(
                                        onClick = {
                                            editingSet = setEntry
                                            editWeight = if (setEntry.weight == 0.0) {
                                                ""
                                            } else {
                                                String.format(
                                                    Locale.getDefault(),
                                                    "%.1f",
                                                    setEntry.weight
                                                )
                                            }
                                            editReps = setEntry.reps.toString()
                                        }
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Edit,
                                            contentDescription = stringResource(R.string.cd_edit)
                                        )
                                    }
                                    IconButton(onClick = { onDeleteSet(setEntry) }) {
                                        Icon(
                                            imageVector = Icons.Default.Delete,
                                            contentDescription = stringResource(R.string.cd_delete)
                                        )
                                    }
                                }
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                OutlinedButton(
                                    onClick = { onAddSet(exerciseDetails.workoutExercise.id) },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Text(
                                        text = stringResource(R.string.action_add_set),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                                OutlinedButton(
                                    onClick = {
                                        onAddSetFromLastWeight(
                                            exerciseDetails.workoutExercise.id,
                                            exerciseDetails.workoutExercise.exerciseId
                                        )
                                    },
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Text(
                                        text = stringResource(R.string.action_add_set_last_weight),
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

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(12.dp)
        )
    }

    if (editingSet != null) {
        AlertDialog(
            onDismissRequest = { editingSet = null },
            title = { Text(text = stringResource(R.string.dialog_edit_set_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = editWeight,
                        onValueChange = { editWeight = it },
                        label = { Text(stringResource(R.string.label_weight_kg)) },
                        placeholder = { Text(stringResource(R.string.hint_optional)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = editReps,
                        onValueChange = { editReps = it },
                        label = { Text(stringResource(R.string.label_reps)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                OutlinedButton(
                    onClick = {
                        val setEntry = editingSet
                        if (setEntry != null) {
                            onUpdateSet(setEntry, editWeight, editReps)
                        }
                        editingSet = null
                    }
                ) {
                    Text(text = stringResource(R.string.action_save))
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { editingSet = null }) {
                    Text(text = stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

@Composable
private fun RestTimerCard(
    restSecondsRemaining: Int,
    onStartRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.label_rest_timer),
                style = MaterialTheme.typography.titleSmall
            )
            val timerText = if (restSecondsRemaining > 0) {
                String.format(
                    Locale.getDefault(),
                    "%02d:%02d",
                    restSecondsRemaining / 60,
                    restSecondsRemaining % 60
                )
            } else {
                stringResource(R.string.label_timer_ready)
            }
            Text(
                text = timerText,
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.primary
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = { onStartRestTimer(90) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(text = stringResource(R.string.action_timer_90))
                }
                OutlinedButton(
                    onClick = { onStartRestTimer(180) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(text = stringResource(R.string.action_timer_180))
                }
                OutlinedButton(
                    onClick = onStopRestTimer,
                    modifier = Modifier.weight(1f)
                ) {
                    Text(text = stringResource(R.string.action_timer_stop))
                }
            }
        }
    }
}
