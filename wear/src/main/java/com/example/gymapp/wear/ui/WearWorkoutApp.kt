package com.example.gymapp.wear.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.gymapp.wear.R
import com.example.gymapp.wear.data.WearSetUiModel
import com.example.gymapp.wear.data.WearWorkoutSessionUiModel
import java.text.DateFormat
import java.util.Date
import java.util.Locale

private enum class WearTab {
    Record,
    History
}

@Composable
fun WearWorkoutApp(
    viewModel: WearWorkoutViewModel
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedTab by rememberSaveable { mutableStateOf(WearTab.Record) }

    LaunchedEffect(uiState.message) {
        val message = uiState.message ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
        viewModel.consumeMessage()
    }

    Scaffold(
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) }
    ) { innerPadding ->
        val selectedSession = uiState.selectedSession
        if (selectedSession != null) {
            SessionDetailScreen(
                session = selectedSession,
                onBack = { viewModel.selectSession(null) },
                onUpdateSet = viewModel::updateExistingSet,
                onDeleteSet = viewModel::deleteSet,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
            )
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
            ) {
                TabSelector(
                    selectedTab = selectedTab,
                    onTabSelected = { selectedTab = it }
                )
                when (selectedTab) {
                    WearTab.Record -> {
                        RecordScreen(
                            uiState = uiState,
                            onNoteChanged = viewModel::updateNote,
                            onAddSet = viewModel::addDraftSet,
                            onRemoveSet = viewModel::removeDraftSet,
                            onExerciseChanged = viewModel::updateDraftExercise,
                            onWeightChanged = viewModel::updateDraftWeight,
                            onRepsChanged = viewModel::updateDraftReps,
                            onSave = viewModel::saveWorkout,
                            modifier = Modifier.fillMaxSize()
                        )
                    }

                    WearTab.History -> {
                        HistoryScreen(
                            sessions = uiState.sessions,
                            onOpenSession = { sessionId -> viewModel.selectSession(sessionId) },
                            onSyncNow = { viewModel.requestRemoteSync(showError = true) },
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TabSelector(
    selectedTab: WearTab,
    onTabSelected: (WearTab) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        val recordLabel = androidx.compose.ui.res.stringResource(R.string.tab_record)
        val historyLabel = androidx.compose.ui.res.stringResource(R.string.tab_history)

        if (selectedTab == WearTab.Record) {
            FilledTonalButton(
                onClick = { onTabSelected(WearTab.Record) },
                modifier = Modifier.weight(1f)
            ) {
                Text(recordLabel)
            }
        } else {
            OutlinedButton(
                onClick = { onTabSelected(WearTab.Record) },
                modifier = Modifier.weight(1f)
            ) {
                Text(recordLabel)
            }
        }

        if (selectedTab == WearTab.History) {
            FilledTonalButton(
                onClick = { onTabSelected(WearTab.History) },
                modifier = Modifier.weight(1f)
            ) {
                Text(historyLabel)
            }
        } else {
            OutlinedButton(
                onClick = { onTabSelected(WearTab.History) },
                modifier = Modifier.weight(1f)
            ) {
                Text(historyLabel)
            }
        }
    }
}

@Composable
private fun RecordScreen(
    uiState: WearWorkoutUiState,
    onNoteChanged: (String) -> Unit,
    onAddSet: () -> Unit,
    onRemoveSet: (Long) -> Unit,
    onExerciseChanged: (Long, String) -> Unit,
    onWeightChanged: (Long, String) -> Unit,
    onRepsChanged: (Long, String) -> Unit,
    onSave: () -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            OutlinedTextField(
                value = uiState.note,
                onValueChange = onNoteChanged,
                label = { Text(androidx.compose.ui.res.stringResource(R.string.label_workout_note)) },
                placeholder = { Text(androidx.compose.ui.res.stringResource(R.string.hint_note_optional)) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true
            )
        }

        items(uiState.draftSets, key = { it.id }) { set ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedTextField(
                        value = set.exerciseName,
                        onValueChange = { onExerciseChanged(set.id, it) },
                        label = {
                            Text(androidx.compose.ui.res.stringResource(R.string.label_set_exercise))
                        },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = set.weight,
                            onValueChange = { onWeightChanged(set.id, it) },
                            label = {
                                Text(androidx.compose.ui.res.stringResource(R.string.label_set_weight))
                            },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                        OutlinedTextField(
                            value = set.reps,
                            onValueChange = { onRepsChanged(set.id, it) },
                            label = {
                                Text(androidx.compose.ui.res.stringResource(R.string.label_set_reps))
                            },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedButton(
                            onClick = {
                                onWeightChanged(
                                    set.id,
                                    adjustWeightText(set.weight, delta = -2.5)
                                )
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(androidx.compose.ui.res.stringResource(R.string.action_weight_minus))
                        }
                        OutlinedButton(
                            onClick = {
                                onWeightChanged(
                                    set.id,
                                    adjustWeightText(set.weight, delta = 2.5)
                                )
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(androidx.compose.ui.res.stringResource(R.string.action_weight_plus))
                        }
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedButton(
                            onClick = {
                                onRepsChanged(
                                    set.id,
                                    adjustRepsText(set.reps, delta = -1)
                                )
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(androidx.compose.ui.res.stringResource(R.string.action_reps_minus))
                        }
                        OutlinedButton(
                            onClick = {
                                onRepsChanged(
                                    set.id,
                                    adjustRepsText(set.reps, delta = 1)
                                )
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(androidx.compose.ui.res.stringResource(R.string.action_reps_plus))
                        }
                    }
                    if (uiState.draftSets.size > 1) {
                        OutlinedButton(
                            onClick = { onRemoveSet(set.id) },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text(androidx.compose.ui.res.stringResource(R.string.action_delete))
                        }
                    }
                }
            }
        }

        item {
            OutlinedButton(
                onClick = onAddSet,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(androidx.compose.ui.res.stringResource(R.string.action_add_set))
            }
        }

        item {
            FilledTonalButton(
                onClick = onSave,
                modifier = Modifier.fillMaxWidth(),
                enabled = !uiState.isSaving
            ) {
                if (uiState.isSaving) {
                    CircularProgressIndicator(modifier = Modifier.width(20.dp), strokeWidth = 2.dp)
                } else {
                    Text(androidx.compose.ui.res.stringResource(R.string.action_save_workout))
                }
            }
        }
    }
}

@Composable
private fun HistoryScreen(
    sessions: List<WearWorkoutSessionUiModel>,
    onOpenSession: (Long) -> Unit,
    onSyncNow: () -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            OutlinedButton(
                onClick = onSyncNow,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(androidx.compose.ui.res.stringResource(R.string.action_sync_now))
            }
        }

        if (sessions.isEmpty()) {
            item {
                Text(text = androidx.compose.ui.res.stringResource(R.string.empty_history))
            }
            return@LazyColumn
        }

        items(sessions, key = { it.id }) { session ->
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onOpenSession(session.id) }
            ) {
                Column(
                    modifier = Modifier.padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = formatDateTime(session.startedAt),
                        style = MaterialTheme.typography.titleSmall
                    )
                    Text(
                        text = androidx.compose.ui.res.stringResource(
                            R.string.label_session_sets,
                            session.setCount
                        ),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = androidx.compose.ui.res.stringResource(
                            R.string.label_session_volume,
                            session.totalVolume
                        ),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    val note = session.note
                    if (!note.isNullOrBlank()) {
                        Text(
                            text = note,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SessionDetailScreen(
    session: WearWorkoutSessionUiModel,
    onBack: () -> Unit,
    onUpdateSet: (WearSetUiModel, String, String) -> Unit,
    onDeleteSet: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    var editingSet by remember { mutableStateOf<WearSetUiModel?>(null) }
    var editWeight by remember { mutableStateOf("") }
    var editReps by remember { mutableStateOf("") }

    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            OutlinedButton(
                onClick = onBack,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(androidx.compose.ui.res.stringResource(R.string.action_back))
            }
        }

        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Text(
                        text = androidx.compose.ui.res.stringResource(R.string.title_workout_details),
                        style = MaterialTheme.typography.titleSmall
                    )
                    Text(
                        text = formatDateTime(session.startedAt),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = androidx.compose.ui.res.stringResource(
                            R.string.label_session_sets,
                            session.setCount
                        ),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }

        items(session.sets, key = { it.id }) { set ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = androidx.compose.ui.res.stringResource(
                            R.string.label_set_summary,
                            set.exerciseName,
                            set.weight,
                            set.reps
                        ),
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedButton(
                            onClick = {
                                editingSet = set
                                editWeight = String.format(Locale.US, "%.1f", set.weight)
                                editReps = set.reps.toString()
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(androidx.compose.ui.res.stringResource(R.string.action_edit))
                        }
                        OutlinedButton(
                            onClick = { onDeleteSet(set.id) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(androidx.compose.ui.res.stringResource(R.string.action_delete))
                        }
                    }
                }
            }
        }
    }

    if (editingSet != null) {
        AlertDialog(
            onDismissRequest = { editingSet = null },
            title = { Text(androidx.compose.ui.res.stringResource(R.string.action_edit)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = editWeight,
                        onValueChange = { editWeight = it },
                        label = { Text(androidx.compose.ui.res.stringResource(R.string.label_set_weight)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = editReps,
                        onValueChange = { editReps = it },
                        label = { Text(androidx.compose.ui.res.stringResource(R.string.label_set_reps)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true
                    )
                }
            },
            confirmButton = {
                OutlinedButton(
                    onClick = {
                        val currentSet = editingSet
                        if (currentSet != null) {
                            onUpdateSet(currentSet, editWeight, editReps)
                        }
                        editingSet = null
                    }
                ) {
                    Text(androidx.compose.ui.res.stringResource(R.string.action_save))
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { editingSet = null }) {
                    Text(androidx.compose.ui.res.stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

private fun formatDateTime(timestamp: Long): String {
    val formatter = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
    return formatter.format(Date(timestamp))
}

private fun adjustWeightText(current: String, delta: Double): String {
    val parsed = current.trim().replace(',', '.').toDoubleOrNull() ?: 0.0
    val adjusted = (parsed + delta).coerceAtLeast(0.0)
    return if (adjusted % 1.0 == 0.0) {
        adjusted.toInt().toString()
    } else {
        String.format(Locale.US, "%.1f", adjusted)
    }
}

private fun adjustRepsText(current: String, delta: Int): String {
    val parsed = current.trim().toIntOrNull() ?: 1
    return (parsed + delta).coerceAtLeast(1).toString()
}
