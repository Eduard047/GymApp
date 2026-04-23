package com.example.gymapp.wear.ui

import android.content.res.Configuration
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.gymapp.wear.R
import com.example.gymapp.wear.data.WearSetUiModel
import com.example.gymapp.wear.data.WearWorkoutSessionUiModel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import java.text.DateFormat
import java.util.Date
import java.util.Locale

private enum class WearTab {
    Record,
    History
}

private data class WearLayoutSpec(
    val isRound: Boolean,
    val horizontalPadding: Dp,
    val verticalPadding: Dp,
    val itemSpacing: Dp,
    val cardPadding: Dp,
    val cardInnerSpacing: Dp
)

@Composable
private fun rememberWearLayoutSpec(): WearLayoutSpec {
    val configuration = LocalContext.current.resources.configuration
    val isRound = (configuration.screenLayout and Configuration.SCREENLAYOUT_ROUND_MASK) ==
        Configuration.SCREENLAYOUT_ROUND_YES

    return if (isRound) {
        WearLayoutSpec(
            isRound = true,
            horizontalPadding = 22.dp,
            verticalPadding = 14.dp,
            itemSpacing = 8.dp,
            cardPadding = 10.dp,
            cardInnerSpacing = 6.dp
        )
    } else {
        WearLayoutSpec(
            isRound = false,
            horizontalPadding = 10.dp,
            verticalPadding = 8.dp,
            itemSpacing = 8.dp,
            cardPadding = 10.dp,
            cardInnerSpacing = 6.dp
        )
    }
}

@Composable
fun WearWorkoutApp(
    viewModel: WearWorkoutViewModel,
    rotaryEvents: Flow<Float> = emptyFlow(),
    isAmbient: Boolean = false
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    var selectedTab by rememberSaveable { mutableStateOf(WearTab.Record) }
    var exercisePickerTargetSetId by rememberSaveable { mutableStateOf<Long?>(null) }
    val layout = rememberWearLayoutSpec()
    val recordListState = rememberLazyListState()
    val historyListState = rememberLazyListState()
    val detailListState = rememberLazyListState()
    val exercisePickerListState = rememberLazyListState()

    LaunchedEffect(uiState.message) {
        val message = uiState.message ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
        viewModel.consumeMessage()
    }

    LaunchedEffect(rotaryEvents, selectedTab, uiState.selectedSession, exercisePickerTargetSetId) {
        rotaryEvents.collect { delta ->
            val listState = when {
                exercisePickerTargetSetId != null -> exercisePickerListState
                uiState.selectedSession != null -> detailListState
                selectedTab == WearTab.Record -> recordListState
                else -> historyListState
            }
            listState.scrollBy(-delta * 48f)
        }
    }

    Scaffold(
        containerColor = if (isAmbient) Color.Black else Color.Transparent,
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) }
    ) { innerPadding ->
        val backgroundModifier = if (isAmbient) {
            Modifier.background(Color.Black)
        } else {
            Modifier.background(
                Brush.verticalGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.surface,
                        MaterialTheme.colorScheme.background,
                        MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.86f)
                    )
                )
            )
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .then(backgroundModifier)
                .padding(innerPadding)
        ) {
            val selectedSession = uiState.selectedSession
            if (selectedSession != null) {
                SessionDetailScreen(
                    session = selectedSession,
                    onBack = { viewModel.selectSession(null) },
                    onUpdateSet = viewModel::updateExistingSet,
                    onDeleteSet = viewModel::deleteSet,
                    listState = detailListState,
                    layout = layout,
                    modifier = Modifier.fillMaxSize()
                )
            } else {
                Column(modifier = Modifier.fillMaxSize()) {
                    TabSelector(
                        selectedTab = selectedTab,
                        onTabSelected = { selectedTab = it },
                        layout = layout,
                        isAmbient = isAmbient
                    )
                    when (selectedTab) {
                        WearTab.Record -> {
                            RecordScreen(
                                uiState = uiState,
                                onAddSet = viewModel::addDraftSet,
                                onDuplicateLastSet = { viewModel.duplicateLastDraftSet() },
                                onDuplicateWithWeight = {
                                    viewModel.duplicateLastDraftSet(weightDelta = 2.5)
                                },
                                onRemoveSet = viewModel::removeDraftSet,
                                onSelectExercise = { setId -> exercisePickerTargetSetId = setId },
                                onWeightChanged = viewModel::updateDraftWeight,
                                onRepsChanged = viewModel::updateDraftReps,
                                onSave = viewModel::saveWorkout,
                                listState = recordListState,
                                layout = layout,
                                modifier = Modifier.fillMaxSize()
                            )
                        }

                        WearTab.History -> {
                            HistoryScreen(
                                sessions = uiState.sessions,
                                onOpenSession = { sessionId -> viewModel.selectSession(sessionId) },
                                onSyncNow = { viewModel.requestRemoteSync(showError = true) },
                                listState = historyListState,
                                layout = layout,
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                    }
                }
            }
            if (exercisePickerTargetSetId != null) {
                ExercisePickerOverlay(
                    availableExercises = uiState.availableExercises,
                    listState = exercisePickerListState,
                    layout = layout,
                    onDismiss = { exercisePickerTargetSetId = null },
                    onExercisePicked = { exerciseName ->
                        val selectedSetId = exercisePickerTargetSetId ?: return@ExercisePickerOverlay
                        viewModel.updateDraftExercise(selectedSetId, exerciseName)
                        exercisePickerTargetSetId = null
                    }
                )
            }
        }
    }
}

@Composable
private fun TabSelector(
    selectedTab: WearTab,
    onTabSelected: (WearTab) -> Unit,
    layout: WearLayoutSpec,
    isAmbient: Boolean
) {
    val recordLabel = stringResource(R.string.tab_record)
    val historyLabel = stringResource(R.string.tab_history)

    if (layout.isRound) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(80.dp)
                .padding(horizontal = 8.dp)
        ) {
            Row(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 36.dp)
                    .width(168.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ArcTabButton(
                    label = recordLabel,
                    selected = selectedTab == WearTab.Record,
                    onClick = { onTabSelected(WearTab.Record) },
                    outerOnStart = true,
                    isAmbient = isAmbient,
                    modifier = Modifier.weight(1f)
                )
                ArcTabButton(
                    label = historyLabel,
                    selected = selectedTab == WearTab.History,
                    onClick = { onTabSelected(WearTab.History) },
                    outerOnStart = false,
                    isAmbient = isAmbient,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    } else {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = layout.horizontalPadding, vertical = 6.dp)
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.88f),
                shape = CircleShape,
                border = BorderStroke(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.72f)
                )
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    SegmentedTabButton(
                        label = recordLabel,
                        selected = selectedTab == WearTab.Record,
                        onClick = { onTabSelected(WearTab.Record) },
                        isAmbient = isAmbient,
                        modifier = Modifier.weight(1f)
                    )
                    SegmentedTabButton(
                        label = historyLabel,
                        selected = selectedTab == WearTab.History,
                        onClick = { onTabSelected(WearTab.History) },
                        isAmbient = isAmbient,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
    }
}

@Composable
private fun ArcTabButton(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    outerOnStart: Boolean,
    isAmbient: Boolean,
    modifier: Modifier = Modifier
) {
    val outerShape = if (outerOnStart) {
        RoundedCornerShape(topStart = 22.dp, bottomStart = 22.dp, topEnd = 12.dp, bottomEnd = 12.dp)
    } else {
        RoundedCornerShape(topStart = 12.dp, bottomStart = 12.dp, topEnd = 22.dp, bottomEnd = 22.dp)
    }

    Surface(
        modifier = modifier
            .clickable(onClick = onClick),
        color = if (selected) {
            if (isAmbient) Color.Black else MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
        } else {
            if (isAmbient) Color.Black else MaterialTheme.colorScheme.surface.copy(alpha = 0.88f)
        },
        shape = outerShape,
        border = BorderStroke(
            width = 1.dp,
            color = if (selected) {
                if (isAmbient) MaterialTheme.colorScheme.onBackground else MaterialTheme.colorScheme.primary.copy(alpha = 0.48f)
            } else {
                if (isAmbient) MaterialTheme.colorScheme.onBackground.copy(alpha = 0.65f) else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f)
            }
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun SegmentedTabButton(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    isAmbient: Boolean,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        color = if (selected) {
            if (isAmbient) Color.Black else MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
        } else {
            Color.Transparent
        },
        shape = CircleShape,
        border = BorderStroke(
            width = 1.dp,
            color = if (selected) {
                if (isAmbient) MaterialTheme.colorScheme.onBackground else MaterialTheme.colorScheme.primary.copy(alpha = 0.46f)
            } else {
                if (isAmbient) MaterialTheme.colorScheme.onBackground.copy(alpha = 0.65f) else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.62f)
            }
        )
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 10.dp, vertical = 8.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun WearPanel(
    layout: WearLayoutSpec,
    modifier: Modifier = Modifier,
    highlighted: Boolean = false,
    content: @Composable ColumnScope.() -> Unit
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(
            containerColor = if (highlighted) {
                MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)
            } else {
                MaterialTheme.colorScheme.surface.copy(alpha = 0.94f)
            }
        ),
        border = BorderStroke(
            1.dp,
            if (highlighted) {
                MaterialTheme.colorScheme.primary.copy(alpha = 0.35f)
            } else {
                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.65f)
            }
        ),
        shape = RoundedCornerShape(if (layout.isRound) 22.dp else 16.dp)
    ) {
        Column(
            modifier = Modifier.padding(layout.cardPadding),
            verticalArrangement = Arrangement.spacedBy(layout.cardInnerSpacing),
            content = content
        )
    }
}

@Composable
private fun RecordScreen(
    uiState: WearWorkoutUiState,
    onAddSet: () -> Unit,
    onDuplicateLastSet: () -> Unit,
    onDuplicateWithWeight: () -> Unit,
    onRemoveSet: (Long) -> Unit,
    onSelectExercise: (Long) -> Unit,
    onWeightChanged: (Long, String) -> Unit,
    onRepsChanged: (Long, String) -> Unit,
    onSave: () -> Unit,
    listState: LazyListState,
    layout: WearLayoutSpec,
    modifier: Modifier = Modifier
) {
    val estimatedVolume = estimateDraftVolume(uiState.draftSets)

    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = PaddingValues(
            start = layout.horizontalPadding,
            end = layout.horizontalPadding,
            top = layout.verticalPadding,
            bottom = if (layout.isRound) 22.dp else 10.dp
        ),
        verticalArrangement = Arrangement.spacedBy(layout.itemSpacing)
    ) {
        item {
            WearPanel(
                layout = layout,
                highlighted = true,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = stringResource(R.string.title_record_summary),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = stringResource(R.string.label_draft_sets_count, uiState.draftSets.size),
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    text = stringResource(R.string.label_draft_volume, estimatedVolume),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = stringResource(R.string.hint_record_shortcut),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        item {
            if (layout.isRound) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onDuplicateLastSet,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = stringResource(R.string.action_duplicate_last_set),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = onDuplicateWithWeight,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = stringResource(R.string.action_duplicate_last_plus),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onDuplicateLastSet,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            text = stringResource(R.string.action_duplicate_last_set),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = onDuplicateWithWeight,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            text = stringResource(R.string.action_duplicate_last_plus),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }

        items(uiState.draftSets, key = { it.id }) { set ->
            val isConfigured = set.exerciseName.isNotBlank() || set.weight.isNotBlank() || set.reps.isNotBlank()
            WearPanel(
                layout = layout,
                modifier = Modifier.fillMaxWidth(),
                highlighted = isConfigured
            ) {
                Text(
                    text = stringResource(R.string.label_set_exercise),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                OutlinedButton(
                    onClick = { onSelectExercise(set.id) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = if (set.exerciseName.isBlank()) {
                            stringResource(R.string.action_select_exercise)
                        } else {
                            set.exerciseName
                        },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                if (layout.isRound) {
                    OutlinedTextField(
                        value = set.weight,
                        onValueChange = { onWeightChanged(set.id, it) },
                        label = { Text(stringResource(R.string.label_set_weight)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = set.reps,
                        onValueChange = { onRepsChanged(set.id, it) },
                        label = { Text(stringResource(R.string.label_set_reps)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = set.weight,
                            onValueChange = { onWeightChanged(set.id, it) },
                            label = { Text(stringResource(R.string.label_set_weight)) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                        OutlinedTextField(
                            value = set.reps,
                            onValueChange = { onRepsChanged(set.id, it) },
                            label = { Text(stringResource(R.string.label_set_reps)) },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.weight(1f),
                            singleLine = true
                        )
                    }
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
                        Text(stringResource(R.string.action_weight_minus))
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
                        Text(stringResource(R.string.action_weight_plus))
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
                        Text(stringResource(R.string.action_reps_minus))
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
                        Text(stringResource(R.string.action_reps_plus))
                    }
                }

                if (uiState.draftSets.size > 1) {
                    OutlinedButton(
                        onClick = { onRemoveSet(set.id) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.action_delete))
                    }
                }
            }
        }

        item {
            OutlinedButton(
                onClick = onAddSet,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_add_set))
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
                    Text(stringResource(R.string.action_save_workout))
                }
            }
        }
    }
}

@Composable
private fun ExercisePickerOverlay(
    availableExercises: List<String>,
    listState: LazyListState,
    layout: WearLayoutSpec,
    onDismiss: () -> Unit,
    onExercisePicked: (String) -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = if (layout.isRound) 0.62f else 0.55f))
    ) {
        Surface(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth(if (layout.isRound) 0.94f else 0.82f)
                .fillMaxHeight(if (layout.isRound) 0.84f else 0.76f)
                .padding(if (layout.isRound) 8.dp else 0.dp),
            shape = RoundedCornerShape(if (layout.isRound) 26.dp else 20.dp),
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
            border = BorderStroke(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.72f)
            )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = if (layout.isRound) 12.dp else 14.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = stringResource(R.string.title_select_exercise),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                if (availableExercises.isEmpty()) {
                    Text(
                        text = stringResource(R.string.message_no_exercises_to_pick),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        contentPadding = PaddingValues(
                            top = 2.dp,
                            bottom = if (layout.isRound) 4.dp else 2.dp
                        ),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(availableExercises, key = { it }) { exercise ->
                            OutlinedButton(
                                onClick = { onExercisePicked(exercise) },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .heightIn(min = if (layout.isRound) 50.dp else 44.dp)
                            ) {
                                Text(
                                    text = exercise,
                                    maxLines = if (layout.isRound) 2 else 1,
                                    overflow = TextOverflow.Ellipsis,
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier.padding(horizontal = 2.dp)
                                )
                            }
                        }
                    }
                }

                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.action_cancel))
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
    listState: LazyListState,
    layout: WearLayoutSpec,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = PaddingValues(
            start = layout.horizontalPadding,
            end = layout.horizontalPadding,
            top = layout.verticalPadding,
            bottom = if (layout.isRound) 22.dp else 10.dp
        ),
        verticalArrangement = Arrangement.spacedBy(layout.itemSpacing)
    ) {
        item {
            OutlinedButton(
                onClick = onSyncNow,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_sync_now))
            }
        }

        if (sessions.isEmpty()) {
            item {
                WearPanel(layout = layout, modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = stringResource(R.string.empty_history),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
            return@LazyColumn
        }

        items(sessions, key = { it.id }) { session ->
            WearPanel(
                layout = layout,
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onOpenSession(session.id) }
            ) {
                Text(
                    text = formatDateTime(session.startedAt),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = stringResource(R.string.label_session_sets, session.setCount),
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    text = stringResource(R.string.label_session_volume, session.totalVolume),
                    style = MaterialTheme.typography.bodyMedium
                )
                val note = session.note
                if (!note.isNullOrBlank()) {
                    Text(
                        text = note,
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
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
    listState: LazyListState,
    layout: WearLayoutSpec,
    modifier: Modifier = Modifier
) {
    var editingSet by remember { mutableStateOf<WearSetUiModel?>(null) }
    var editWeight by remember { mutableStateOf("") }
    var editReps by remember { mutableStateOf("") }

    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = PaddingValues(
            start = layout.horizontalPadding,
            end = layout.horizontalPadding,
            top = layout.verticalPadding,
            bottom = if (layout.isRound) 22.dp else 10.dp
        ),
        verticalArrangement = Arrangement.spacedBy(layout.itemSpacing)
    ) {
        item {
            OutlinedButton(
                onClick = onBack,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_back))
            }
        }

        item {
            WearPanel(layout = layout, highlighted = true, modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = stringResource(R.string.title_workout_details),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = formatDateTime(session.startedAt),
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    text = stringResource(R.string.label_session_sets, session.setCount),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }

        items(session.sets, key = { it.id }) { set ->
            WearPanel(layout = layout, modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = stringResource(
                        R.string.label_set_summary,
                        set.exerciseName,
                        set.weight,
                        set.reps
                    ),
                    style = MaterialTheme.typography.bodyMedium
                )

                if (layout.isRound) {
                    OutlinedButton(
                        onClick = {
                            editingSet = set
                            editWeight = String.format(Locale.US, "%.1f", set.weight)
                            editReps = set.reps.toString()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.action_edit))
                    }
                    OutlinedButton(
                        onClick = { onDeleteSet(set.id) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.action_delete))
                    }
                } else {
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
                            Text(stringResource(R.string.action_edit))
                        }
                        OutlinedButton(
                            onClick = { onDeleteSet(set.id) },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.action_delete))
                        }
                    }
                }
            }
        }
    }

    if (editingSet != null) {
        AlertDialog(
            onDismissRequest = { editingSet = null },
            title = { Text(stringResource(R.string.action_edit)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = editWeight,
                        onValueChange = { editWeight = it },
                        label = { Text(stringResource(R.string.label_set_weight)) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = editReps,
                        onValueChange = { editReps = it },
                        label = { Text(stringResource(R.string.label_set_reps)) },
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
                    Text(stringResource(R.string.action_save))
                }
            },
            dismissButton = {
                OutlinedButton(onClick = { editingSet = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        )
    }
}

private fun estimateDraftVolume(draftSets: List<WearSetInputUiState>): Double {
    return draftSets.sumOf { set ->
        val weight = set.weight.trim().replace(',', '.').toDoubleOrNull() ?: 0.0
        val reps = set.reps.trim().toIntOrNull() ?: 0
        if (weight <= 0.0 || reps <= 0) 0.0 else weight * reps
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
