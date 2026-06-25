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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.gymapp.wear.R
import com.example.gymapp.wear.data.WearSetUiModel
import com.example.gymapp.wear.data.WearWorkoutSessionUiModel
import com.example.gymapp.wear.sync.SyncedWorkoutPlanMeta
import com.example.gymapp.wear.ui.WearSyncStatus
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

private data class NumericEditorState(
    val title: String,
    val value: String,
    val allowDecimal: Boolean,
    val onConfirm: (String) -> Unit
)

@Composable
private fun rememberWearLayoutSpec(): WearLayoutSpec {
    val configuration = LocalConfiguration.current
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
private fun CurrentSetPanel(
    set: WearSetInputUiState,
    weightLabel: String,
    repsLabel: String,
    layout: WearLayoutSpec,
    haptic: HapticFeedback,
    isSaving: Boolean,
    onSelectExercise: () -> Unit,
    onWeightClick: () -> Unit,
    onRepsClick: () -> Unit,
    onWeightPreset: (String) -> Unit,
    onRepsPreset: (String) -> Unit,
    onSave: () -> Unit
) {
    WearPanel(
        layout = layout,
        highlighted = true,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = stringResource(R.string.title_current_set),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold
        )
        OutlinedButton(
            onClick = { hapticClick(haptic, onSelectExercise) },
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
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            NumericValueButton(
                label = weightLabel,
                value = set.weight,
                onClick = { hapticClick(haptic, onWeightClick) },
                modifier = Modifier.weight(1f)
            )
            NumericValueButton(
                label = repsLabel,
                value = set.reps,
                onClick = { hapticClick(haptic, onRepsClick) },
                modifier = Modifier.weight(1f)
            )
        }
        QuickPresetRow(
            values = listOf("20", "40", "60"),
            onValueSelected = { value -> hapticClick(haptic) { onWeightPreset(value) } }
        )
        QuickPresetRow(
            values = listOf("8", "10", "12"),
            onValueSelected = { value -> hapticClick(haptic) { onRepsPreset(value) } }
        )
        FilledTonalButton(
            onClick = { hapticClick(haptic, onSave) },
            modifier = Modifier.fillMaxWidth(),
            enabled = !isSaving
        ) {
            if (isSaving) {
                CircularProgressIndicator(modifier = Modifier.width(20.dp), strokeWidth = 2.dp)
            } else {
                Text(stringResource(R.string.action_save_workout))
            }
        }
    }
}

@Composable
private fun QuickPresetRow(
    values: List<String>,
    onValueSelected: (String) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        values.forEach { value ->
            OutlinedButton(
                onClick = { onValueSelected(value) },
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
            ) {
                Text(
                    text = value,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
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
    val weightLabel = stringResource(R.string.label_set_weight)
    val repsLabel = stringResource(R.string.label_set_reps)
    val haptic = LocalHapticFeedback.current
    val currentSet = uiState.draftSets.lastOrNull()
    var numericEditor by remember { mutableStateOf<NumericEditorState?>(null) }

    Box(modifier = modifier) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
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
                    Text(
                        text = syncStatusLabel(uiState.syncStatus),
                        style = MaterialTheme.typography.bodySmall,
                        color = syncStatusColor(uiState.syncStatus)
                    )
                }
            }

            uiState.workoutPlanMeta?.let { planMeta ->
                item {
                    SmartPlanWatchPanel(
                        planMeta = planMeta,
                        setCount = uiState.draftSets.size,
                        layout = layout,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }

            if (currentSet != null) {
                item {
                    CurrentSetPanel(
                        set = currentSet,
                        weightLabel = weightLabel,
                        repsLabel = repsLabel,
                        layout = layout,
                        haptic = haptic,
                        isSaving = uiState.isSaving,
                        onSelectExercise = { onSelectExercise(currentSet.id) },
                        onWeightClick = {
                            numericEditor = NumericEditorState(
                                title = weightLabel,
                                value = currentSet.weight,
                                allowDecimal = true,
                                onConfirm = { onWeightChanged(currentSet.id, it) }
                            )
                        },
                        onRepsClick = {
                            numericEditor = NumericEditorState(
                                title = repsLabel,
                                value = currentSet.reps,
                                allowDecimal = false,
                                onConfirm = { onRepsChanged(currentSet.id, it) }
                            )
                        },
                        onWeightPreset = { value -> onWeightChanged(currentSet.id, value) },
                        onRepsPreset = { value -> onRepsChanged(currentSet.id, value) },
                        onSave = onSave
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
                        onClick = { hapticClick(haptic, onDuplicateLastSet) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = stringResource(R.string.action_duplicate_last_set),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = { hapticClick(haptic, onDuplicateWithWeight) },
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
                        onClick = { hapticClick(haptic, onDuplicateLastSet) },
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            text = stringResource(R.string.action_duplicate_last_set),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    OutlinedButton(
                        onClick = { hapticClick(haptic, onDuplicateWithWeight) },
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
                    NumericValueButton(
                        label = weightLabel,
                        value = set.weight,
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            numericEditor = NumericEditorState(
                                title = weightLabel,
                                value = set.weight,
                                allowDecimal = true,
                                onConfirm = { onWeightChanged(set.id, it) }
                            )
                        }
                    )
                    NumericValueButton(
                        label = repsLabel,
                        value = set.reps,
                        modifier = Modifier.fillMaxWidth(),
                        onClick = {
                            numericEditor = NumericEditorState(
                                title = repsLabel,
                                value = set.reps,
                                allowDecimal = false,
                                onConfirm = { onRepsChanged(set.id, it) }
                            )
                        }
                    )
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        NumericValueButton(
                            label = weightLabel,
                            value = set.weight,
                            modifier = Modifier.weight(1f),
                            onClick = {
                                numericEditor = NumericEditorState(
                                    title = weightLabel,
                                    value = set.weight,
                                    allowDecimal = true,
                                    onConfirm = { onWeightChanged(set.id, it) }
                                )
                            }
                        )
                        NumericValueButton(
                            label = repsLabel,
                            value = set.reps,
                            modifier = Modifier.weight(1f),
                            onClick = {
                                numericEditor = NumericEditorState(
                                    title = repsLabel,
                                    value = set.reps,
                                    allowDecimal = false,
                                    onConfirm = { onRepsChanged(set.id, it) }
                                )
                            }
                        )
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = {
                            hapticClick(haptic)
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
                            hapticClick(haptic)
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
                            hapticClick(haptic)
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
                            hapticClick(haptic)
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
                        onClick = { hapticClick(haptic) { onRemoveSet(set.id) } },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(stringResource(R.string.action_delete))
                    }
                }
            }
        }

        item {
            OutlinedButton(
                onClick = { hapticClick(haptic, onAddSet) },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(stringResource(R.string.action_add_set))
            }
        }

        item {
            FilledTonalButton(
                onClick = { hapticClick(haptic, onSave) },
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

        numericEditor?.let { editor ->
            NumericInputOverlay(
                editor = editor,
                layout = layout,
                onDismiss = { numericEditor = null },
                onConfirm = { value ->
                    editor.onConfirm(value)
                    numericEditor = null
                }
            )
        }
    }
}

@Composable
private fun SmartPlanWatchPanel(
    planMeta: SyncedWorkoutPlanMeta,
    setCount: Int,
    layout: WearLayoutSpec,
    modifier: Modifier = Modifier
) {
    WearPanel(
        layout = layout,
        highlighted = true,
        modifier = modifier
    ) {
        Text(
            text = stringResource(R.string.title_smart_plan),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            text = stringResource(R.string.label_smart_plan_sets, setCount),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = planMeta.smartPlanSummary(),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
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
    val weightLabel = stringResource(R.string.label_set_weight)
    val repsLabel = stringResource(R.string.label_set_reps)
    val haptic = LocalHapticFeedback.current
    var numericEditor by remember { mutableStateOf<NumericEditorState?>(null) }

    Box(modifier = modifier) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
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
                            onClick = { hapticClick(haptic) { onDeleteSet(set.id) } },
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
                                onClick = { hapticClick(haptic) { onDeleteSet(set.id) } },
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
            EditSetOverlay(
                layout = layout,
                weight = editWeight,
                reps = editReps,
                weightLabel = weightLabel,
                repsLabel = repsLabel,
                onWeightClick = {
                    numericEditor = NumericEditorState(
                        title = weightLabel,
                        value = editWeight,
                        allowDecimal = true,
                        onConfirm = { editWeight = it }
                    )
                },
                onRepsClick = {
                    numericEditor = NumericEditorState(
                        title = repsLabel,
                        value = editReps,
                        allowDecimal = false,
                        onConfirm = { editReps = it }
                    )
                },
                onDismiss = { editingSet = null },
                onSave = {
                    hapticClick(haptic) {
                        val currentSet = editingSet
                        if (currentSet != null) {
                            onUpdateSet(currentSet, editWeight, editReps)
                        }
                        editingSet = null
                    }
                }
            )
        }

        numericEditor?.let { editor ->
            NumericInputOverlay(
                editor = editor,
                layout = layout,
                onDismiss = { numericEditor = null },
                onConfirm = { value ->
                    editor.onConfirm(value)
                    numericEditor = null
                }
            )
        }
    }
}

@Composable
private fun NumericValueButton(
    label: String,
    value: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.88f),
        shape = RoundedCornerShape(14.dp),
        border = BorderStroke(
            width = 1.dp,
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.78f)
        )
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = value.ifBlank { "0" },
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
private fun EditSetOverlay(
    layout: WearLayoutSpec,
    weight: String,
    reps: String,
    weightLabel: String,
    repsLabel: String,
    onWeightClick: () -> Unit,
    onRepsClick: () -> Unit,
    onDismiss: () -> Unit,
    onSave: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = if (layout.isRound) 0.62f else 0.55f))
    ) {
        Surface(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth(if (layout.isRound) 0.9f else 0.76f)
                .padding(if (layout.isRound) 10.dp else 0.dp),
            shape = RoundedCornerShape(if (layout.isRound) 26.dp else 20.dp),
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
            border = BorderStroke(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.72f)
            )
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = stringResource(R.string.action_edit),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                NumericValueButton(
                    label = weightLabel,
                    value = weight,
                    onClick = onWeightClick,
                    modifier = Modifier.fillMaxWidth()
                )
                NumericValueButton(
                    label = repsLabel,
                    value = reps,
                    onClick = onRepsClick,
                    modifier = Modifier.fillMaxWidth()
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            text = stringResource(R.string.action_cancel),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    FilledTonalButton(
                        onClick = onSave,
                        modifier = Modifier.weight(1f)
                    ) {
                        Text(
                            text = stringResource(R.string.action_save),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun NumericInputOverlay(
    editor: NumericEditorState,
    layout: WearLayoutSpec,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var currentValue by remember(editor) { mutableStateOf(editor.value.trim()) }
    val haptic = LocalHapticFeedback.current
    val keypadRows = if (editor.allowDecimal) {
        listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
            listOf(".", "0", "Del")
        )
    } else {
        listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
            listOf("C", "0", "Del")
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = if (layout.isRound) 0.7f else 0.62f))
    ) {
        Surface(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth(if (layout.isRound) 0.92f else 0.78f)
                .padding(if (layout.isRound) 8.dp else 0.dp),
            shape = RoundedCornerShape(if (layout.isRound) 26.dp else 20.dp),
            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.98f),
            border = BorderStroke(
                width = 1.dp,
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.34f)
            )
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = editor.title,
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Surface(
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.14f),
                    contentColor = MaterialTheme.colorScheme.onSurface,
                    shape = RoundedCornerShape(14.dp),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.24f)),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = currentValue.ifBlank { "0" },
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                keypadRows.forEach { row ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        row.forEach { key ->
                            OutlinedButton(
                                onClick = {
                                    hapticClick(haptic)
                                    currentValue = nextNumericValue(
                                        current = currentValue,
                                        key = key,
                                        allowDecimal = editor.allowDecimal
                                    )
                                },
                                modifier = Modifier
                                    .weight(1f)
                                    .height(38.dp),
                                contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                            ) {
                                Text(
                                    text = key,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    textAlign = TextAlign.Center
                                )
                            }
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(
                        onClick = onDismiss,
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.action_cancel),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    FilledTonalButton(
                        onClick = { hapticClick(haptic) { onConfirm(currentValue) } },
                        modifier = Modifier.weight(1f),
                        contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.action_save),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun syncStatusLabel(status: WearSyncStatus): String {
    return when (status) {
        WearSyncStatus.Idle -> stringResource(R.string.sync_status_idle)
        WearSyncStatus.WaitingPhone -> stringResource(R.string.sync_status_waiting)
        WearSyncStatus.Sent -> stringResource(R.string.sync_status_sent)
        WearSyncStatus.Failed -> stringResource(R.string.sync_status_failed)
    }
}

@Composable
private fun syncStatusColor(status: WearSyncStatus): Color {
    return when (status) {
        WearSyncStatus.Failed -> MaterialTheme.colorScheme.error
        WearSyncStatus.Sent -> MaterialTheme.colorScheme.primary
        WearSyncStatus.WaitingPhone -> MaterialTheme.colorScheme.secondary
        WearSyncStatus.Idle -> MaterialTheme.colorScheme.onSurfaceVariant
    }
}

private fun hapticClick(
    haptic: HapticFeedback,
    action: () -> Unit = {}
) {
    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
    action()
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

private fun nextNumericValue(
    current: String,
    key: String,
    allowDecimal: Boolean
): String {
    val normalized = current.trim().replace(',', '.')
    return when (key) {
        "Del" -> normalized.dropLast(1)
        "C" -> ""
        "." -> {
            if (!allowDecimal || normalized.contains('.')) {
                normalized
            } else if (normalized.isBlank()) {
                "0."
            } else {
                "$normalized."
            }
        }
        else -> {
            if (!key.all { it.isDigit() }) {
                normalized
            } else {
                val next = if (normalized == "0") key else normalized + key
                if (allowDecimal) {
                    next.take(6)
                } else {
                    next.take(3)
                }
            }
        }
    }
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

private fun SyncedWorkoutPlanMeta.smartPlanSummary(): String {
    val parts = buildList {
        split?.let {
            add(
                when (it) {
                    "UpperLower" -> "верх/низ"
                    "FullBody" -> "все тіло"
                    "PushPullLegs" -> "жим/тяга/ноги"
                    else -> "своя програма"
                }
            )
        }
        workoutsPerWeek?.let { add("$it/тиж") }
        goal?.let {
            add(
                when (it) {
                    "AestheticFatLoss" -> "естетика"
                    "MuscleGain" -> "маса"
                    "Strength" -> "сила"
                    else -> "баланс"
                }
            )
        }
        calorieMode?.let {
            add(
                when (it) {
                    "Deficit" -> "дефіцит"
                    "Surplus" -> "профіцит"
                    else -> "підтримка"
                }
            )
        }
    }
    return parts.joinToString(" · ").ifBlank { planSource }
}
