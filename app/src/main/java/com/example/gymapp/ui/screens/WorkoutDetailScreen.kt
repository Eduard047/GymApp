package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
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
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.ui.viewmodel.WorkoutDetailEvent
import com.example.gymapp.ui.viewmodel.WorkoutDetailUiState
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import java.util.Locale

private const val SETS_TABLE_SET_WEIGHT = 0.95f
private const val SETS_TABLE_WEIGHT_WEIGHT = 1.1f
private const val SETS_TABLE_REPS_WEIGHT = 0.9f
private val SETS_TABLE_ACTIONS_WIDTH = 104.dp

@Composable
fun WorkoutDetailScreen(
    uiState: WorkoutDetailUiState,
    events: Flow<WorkoutDetailEvent>,
    onAddExerciseToWorkout: (Long) -> Unit,
    onAddSet: (Long) -> Unit,
    onDeleteSet: (SetEntryEntity) -> Unit,
    onUpdateSet: (SetEntryEntity, String, String) -> Unit,
    onUndoDelete: () -> Unit,
    modifier: Modifier = Modifier
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var editingSet by remember { mutableStateOf<SetEntryEntity?>(null) }
    var editWeight by remember { mutableStateOf("") }
    var editReps by remember { mutableStateOf("") }

    val exerciseTimerTargets = remember { mutableStateMapOf<Long, Long>() }
    var exerciseTimerNowMillis by remember { mutableLongStateOf(System.currentTimeMillis()) }

    LaunchedEffect(exerciseTimerTargets.keys.toList(), exerciseTimerTargets.values.toList()) {
        if (exerciseTimerTargets.isEmpty()) return@LaunchedEffect

        while (exerciseTimerTargets.isNotEmpty()) {
            val now = System.currentTimeMillis()
            exerciseTimerNowMillis = now
            val expiredIds = exerciseTimerTargets
                .filterValues { it <= now }
                .keys
                .toList()
            expiredIds.forEach { exerciseTimerTargets.remove(it) }
            if (exerciseTimerTargets.isEmpty()) break
            delay(500)
        }
    }

    fun startExerciseTimer(workoutExerciseId: Long, seconds: Int) {
        if (seconds <= 0) return
        exerciseTimerNowMillis = System.currentTimeMillis()
        exerciseTimerTargets[workoutExerciseId] = exerciseTimerNowMillis + seconds * 1_000L
    }

    fun stopExerciseTimer(workoutExerciseId: Long) {
        exerciseTimerTargets.remove(workoutExerciseId)
    }

    fun remainingExerciseTimerSeconds(workoutExerciseId: Long): Int {
        val target = exerciseTimerTargets[workoutExerciseId] ?: return 0
        val remainingMillis = (target - exerciseTimerNowMillis).coerceAtLeast(0L)
        return ((remainingMillis + 999L) / 1_000L).toInt()
    }

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

                item {
                    WorkoutExerciseQuickAddCard(
                        availableExercises = uiState.availableExercisesToAdd,
                        onAddExerciseToWorkout = onAddExerciseToWorkout
                    )
                }

                items(
                    items = details.workoutExercises,
                    key = { it.workoutExercise.id }
                ) { exerciseDetails ->
                    val workoutExerciseId = exerciseDetails.workoutExercise.id
                    val localRestSecondsRemaining = remainingExerciseTimerSeconds(workoutExerciseId)

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
                                if (localRestSecondsRemaining > 0) {
                                    AssistChip(
                                        onClick = { },
                                        label = {
                                            Text(
                                                text = stringResource(
                                                    R.string.label_exercise_rest_remaining,
                                                    formatTimerLabel(localRestSecondsRemaining)
                                                )
                                            )
                                        }
                                    )
                                }
                                if (uiState.personalRecordFlags[workoutExerciseId] == true) {
                                    AssistChip(
                                        onClick = { },
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

                            ExerciseRestTimerRow(
                                restSecondsRemaining = localRestSecondsRemaining,
                                onStart60 = { startExerciseTimer(workoutExerciseId, 60) },
                                onStart90 = { startExerciseTimer(workoutExerciseId, 90) },
                                onStart180 = { startExerciseTimer(workoutExerciseId, 180) },
                                onStop = { stopExerciseTimer(workoutExerciseId) }
                            )

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Text(
                                    text = stringResource(R.string.label_set_short),
                                    modifier = Modifier.weight(SETS_TABLE_SET_WEIGHT),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(R.string.label_weight_kg),
                                    modifier = Modifier.weight(SETS_TABLE_WEIGHT_WEIGHT),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    text = stringResource(R.string.label_reps),
                                    modifier = Modifier.weight(SETS_TABLE_REPS_WEIGHT),
                                    style = MaterialTheme.typography.labelLarge,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Box(
                                    modifier = Modifier.width(SETS_TABLE_ACTIONS_WIDTH)
                                )
                            }

                            exerciseDetails.sets.forEachIndexed { setIndex, setEntry ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    Text(
                                        text = stringResource(R.string.label_set, setIndex + 1),
                                        modifier = Modifier.weight(SETS_TABLE_SET_WEIGHT),
                                        maxLines = 1
                                    )
                                    Text(
                                        text = String.format(Locale.getDefault(), "%.1f", setEntry.weight),
                                        modifier = Modifier.weight(SETS_TABLE_WEIGHT_WEIGHT),
                                        maxLines = 1
                                    )
                                    Text(
                                        text = setEntry.reps.toString(),
                                        modifier = Modifier.weight(SETS_TABLE_REPS_WEIGHT),
                                        maxLines = 1
                                    )
                                    Box(
                                        modifier = Modifier.width(SETS_TABLE_ACTIONS_WIDTH)
                                    ) {
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.spacedBy(
                                                8.dp,
                                                Alignment.End
                                            ),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
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
                                }
                            }

                            if (exerciseDetails.sets.isEmpty()) {
                                Text(
                                    text = stringResource(R.string.empty_progress),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }

                            OutlinedButton(
                                onClick = {
                                    onAddSet(workoutExerciseId)
                                    startExerciseTimer(workoutExerciseId, 90)
                                },
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
private fun WorkoutExerciseQuickAddCard(
    availableExercises: List<ExerciseEntity>,
    onAddExerciseToWorkout: (Long) -> Unit
) {
    var expanded by remember(availableExercises) { mutableStateOf(false) }
    var selectedExerciseId by remember(availableExercises) {
        mutableStateOf(availableExercises.firstOrNull()?.id)
    }
    val selectedExerciseName = availableExercises
        .firstOrNull { it.id == selectedExerciseId }
        ?.name
        ?: stringResource(R.string.label_select_exercise)

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
                Icon(
                    imageVector = Icons.Default.Add,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = stringResource(R.string.title_add_exercise_to_workout_section),
                    style = MaterialTheme.typography.titleSmall
                )
            }

            if (availableExercises.isEmpty()) {
                Text(
                    text = stringResource(R.string.label_all_exercises_added),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Box(modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        onClick = { expanded = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = selectedExerciseName,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    DropdownMenu(
                        expanded = expanded,
                        onDismissRequest = { expanded = false }
                    ) {
                        availableExercises.forEach { exercise ->
                            DropdownMenuItem(
                                text = { Text(exercise.name) },
                                onClick = {
                                    selectedExerciseId = exercise.id
                                    expanded = false
                                }
                            )
                        }
                    }
                }

                OutlinedButton(
                    onClick = {
                        val selectedId = selectedExerciseId ?: return@OutlinedButton
                        onAddExerciseToWorkout(selectedId)
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(text = stringResource(R.string.action_add_to_workout))
                }
            }
        }
    }
}

@Composable
private fun ExerciseRestTimerRow(
    restSecondsRemaining: Int,
    onStart60: () -> Unit,
    onStart90: () -> Unit,
    onStart180: () -> Unit,
    onStop: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = stringResource(R.string.label_rest_timer_exercise),
                style = MaterialTheme.typography.labelLarge
            )
            Text(
                text = if (restSecondsRemaining > 0) {
                    formatTimerLabel(restSecondsRemaining)
                } else {
                    stringResource(R.string.label_timer_ready)
                },
                style = MaterialTheme.typography.labelLarge,
                color = if (restSecondsRemaining > 0) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
            )
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            TimerPresetButton(
                label = stringResource(R.string.label_timer_preset_60),
                onClick = onStart60,
                modifier = Modifier.weight(1f)
            )
            TimerPresetButton(
                label = stringResource(R.string.label_timer_preset_90),
                onClick = onStart90,
                modifier = Modifier.weight(1f)
            )
            TimerPresetButton(
                label = stringResource(R.string.label_timer_preset_180),
                onClick = onStart180,
                modifier = Modifier.weight(1f)
            )
        }
        OutlinedButton(
            onClick = onStop,
            modifier = Modifier.fillMaxWidth(),
            enabled = restSecondsRemaining > 0
        ) {
            Text(text = stringResource(R.string.action_timer_stop))
        }
    }
}

@Composable
private fun TimerPresetButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier,
        shape = ButtonDefaults.filledTonalShape,
        contentPadding = ButtonDefaults.ButtonWithIconContentPadding
    ) {
        Text(
            text = label,
            maxLines = 1,
            fontWeight = FontWeight.SemiBold
        )
    }
}

private fun formatTimerLabel(totalSeconds: Int): String {
    return String.format(
        Locale.getDefault(),
        "%02d:%02d",
        totalSeconds / 60,
        totalSeconds % 60
    )
}
