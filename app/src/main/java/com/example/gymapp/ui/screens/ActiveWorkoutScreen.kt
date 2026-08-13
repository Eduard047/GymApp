package com.example.gymapp.ui.screens

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.viewmodel.ActiveWorkoutExerciseUiState
import com.example.gymapp.ui.viewmodel.ActiveWorkoutSetUiState
import com.example.gymapp.ui.viewmodel.ActiveWorkoutUiState
import com.example.gymapp.ui.viewmodel.LiveConnectionMode
import com.example.gymapp.ui.viewmodel.LivePeerExerciseSummary
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.asString
import java.util.Locale
import java.text.NumberFormat

@Composable
fun ActiveWorkoutScreen(
    uiState: ActiveWorkoutUiState,
    exerciseMediaOwnerKey: String,
    onSetWeightChanged: (String, String) -> Unit,
    onSetRepsChanged: (String, String) -> Unit,
    onRecordSet: (String) -> Unit,
    onRecordAllPendingSets: () -> Unit,
    onUndoLatestSet: (String) -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    onFinishWorkout: () -> Unit,
    onDiscardWorkout: () -> Unit,
    onDismissMessage: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showDiscardConfirmation by rememberSaveable { mutableStateOf(false) }
    var liveParticipantTab by rememberSaveable(uiState.livePeerName) {
        mutableStateOf(LiveParticipantTab.Self)
    }

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

    val operationInProgress = uiState.isRecordingAll || uiState.isFinishing || uiState.isDiscarding ||
        uiState.setRecordingsInFlight.isNotEmpty() || uiState.undoingSetId != null
    val peerName = uiState.livePeerName
    val showSelfParticipant = peerName == null || liveParticipantTab == LiveParticipantTab.Self

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = GymSpacing.ScreenHorizontal,
            top = GymSpacing.ScreenTop,
            end = GymSpacing.ScreenHorizontal,
            bottom = GymSpacing.ScreenBottom
        ),
        verticalArrangement = Arrangement.spacedBy(GymSpacing.Large)
    ) {
        if (peerName != null) {
            item {
                GymSegmentedControl(
                    items = listOf(
                        GymSegmentItem(
                            LiveParticipantTab.Self,
                            uiState.liveSelfName ?: stringResource(R.string.live_workout_lane_you)
                        ),
                        GymSegmentItem(LiveParticipantTab.Peer, peerName)
                    ),
                    selected = liveParticipantTab,
                    onSelected = { liveParticipantTab = it },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        item {
            if (showSelfParticipant) {
                ActiveWorkoutHero(uiState)
            } else {
                LivePeerWorkoutHero(uiState = uiState, peerName = peerName.orEmpty())
            }
        }

        if (showSelfParticipant) {
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
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
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
                        title = stringResource(R.string.action_finish_workout)
                    )
                    if (uiState.completedSetCount < uiState.totalSetCount) {
                        OutlinedButton(
                            onClick = onRecordAllPendingSets,
                            enabled = !operationInProgress,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            if (uiState.isRecordingAll) {
                                CircularProgressIndicator(
                                    modifier = Modifier
                                        .padding(end = 8.dp)
                                        .size(18.dp),
                                    strokeWidth = 2.dp
                                )
                            }
                            Text(text = stringResource(R.string.action_save_all_pending_sets))
                        }
                        Text(
                            text = stringResource(R.string.active_workout_save_all_supporting),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Text(
                        text = stringResource(R.string.active_workout_finish_supporting),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
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
        } else {
            item {
                Text(
                    text = stringResource(
                        when (uiState.liveConnectionMode) {
                            LiveConnectionMode.Realtime -> R.string.live_workout_active_realtime
                            LiveConnectionMode.Polling -> R.string.live_workout_active_polling
                            LiveConnectionMode.Offline,
                            null -> R.string.live_workout_active_offline
                        },
                        uiState.livePendingOperationCount
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            items(
                items = uiState.livePeerExercises,
                key = LivePeerExerciseSummary::exerciseId
            ) { exercise ->
                LivePeerExerciseCard(exercise)
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

private enum class LiveParticipantTab { Self, Peer }

@Composable
private fun ActiveWorkoutHero(uiState: ActiveWorkoutUiState) {
    HeroPanel(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = stringResource(R.string.active_workout_title),
                style = MaterialTheme.typography.headlineSmall,
                color = Color.White
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
                InfoPill(text = progressDescription)
                InfoPill(text = DateTimeUtils.formatDate(uiState.date))
            }
            Text(
                text = stringResource(
                    R.string.active_workout_total_time,
                    formatActiveWorkoutTime(uiState.workoutElapsedSeconds)
                ),
                style = MaterialTheme.typography.titleMedium,
                color = Color.White
            )
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

@Composable
private fun LivePeerWorkoutHero(
    uiState: ActiveWorkoutUiState,
    peerName: String
) {
    HeroPanel(modifier = Modifier.fillMaxWidth()) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = peerName,
                style = MaterialTheme.typography.headlineSmall,
                color = Color.White
            )
            val progressDescription = if (uiState.livePeerFinished) {
                stringResource(R.string.live_workout_peer_finished)
            } else {
                stringResource(
                    R.string.live_workout_peer_progress,
                    uiState.livePeerCompletedSetCount,
                    uiState.livePeerTotalSetCount
                )
            }
            InfoPill(text = progressDescription)
            Text(
                text = stringResource(R.string.live_workout_peer_read_only),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.84f)
            )
        }
    }
}

@Composable
private fun LivePeerExerciseCard(exercise: LivePeerExerciseSummary) {
    val numberFormat = remember {
        NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 }
    }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = localizedExerciseName(exercise.exerciseName),
                style = MaterialTheme.typography.titleMedium
            )
            exercise.sets.forEach { set ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = stringResource(R.string.label_set, set.orderIndex + 1),
                        modifier = Modifier.weight(1f),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = if (set.isCompleted) {
                            stringResource(
                                R.string.live_workout_peer_set_completed,
                                numberFormat.format(set.completedWeight ?: 0.0),
                                set.completedReps ?: 0
                            )
                        } else {
                            stringResource(
                                R.string.live_workout_peer_set_pending,
                                numberFormat.format(set.plannedWeight),
                                set.plannedReps
                            )
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (set.isCompleted) {
                            MaterialTheme.colorScheme.onSurface
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun ActiveWorkoutExerciseCard(
    exercise: ActiveWorkoutExerciseUiState,
    exerciseMediaOwnerKey: String,
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
    val fullyCompleted = exercise.sets.isNotEmpty() &&
        exercise.sets.all(ActiveWorkoutSetUiState::isCompleted)
    var isExpanded by rememberSaveable(exercise.id) { mutableStateOf(!fullyCompleted) }
    LaunchedEffect(fullyCompleted) {
        isExpanded = !fullyCompleted
    }
    AppPanel(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                exercise.exerciseId?.let { exerciseId ->
                    ExerciseMediaPreview(
                        exerciseId = exerciseId,
                        exerciseName = exercise.exerciseName,
                        ownerKey = exerciseMediaOwnerKey,
                        width = 76.dp,
                        height = 64.dp,
                        editable = false
                    )
                }
                SectionTitle(
                    eyebrow = stringResource(
                        R.string.active_workout_exercise_number,
                        exercise.orderIndex + 1
                    ),
                    title = localizedExerciseName(exercise.exerciseName),
                    supporting = stringResource(
                        R.string.active_workout_exercise_progress,
                        exercise.sets.count(ActiveWorkoutSetUiState::isCompleted),
                        exercise.sets.size
                    ),
                    modifier = Modifier.weight(1f)
                )
                IconButton(onClick = { isExpanded = !isExpanded }) {
                    Icon(
                        imageVector = if (isExpanded) {
                            Icons.Default.ExpandLess
                        } else {
                            Icons.Default.ExpandMore
                        },
                        contentDescription = stringResource(
                            if (isExpanded) {
                                R.string.cd_collapse_exercise
                            } else {
                                R.string.cd_expand_exercise
                            }
                        )
                    )
                }
            }
            if (!isExpanded && fullyCompleted) {
                Text(
                    text = stringResource(R.string.active_workout_exercise_completed_collapsed),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            if (isExpanded) exercise.sets.forEach { set ->
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
    val containerColor = if (set.isCompleted) {
        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.72f)
    } else {
        MaterialTheme.colorScheme.surfaceVariant
    }
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = GymControlShape,
        color = containerColor,
        contentColor = if (set.isCompleted) {
            MaterialTheme.colorScheme.onPrimaryContainer
        } else {
            MaterialTheme.colorScheme.onSurfaceVariant
        },
        border = BorderStroke(
            1.dp,
            if (set.isCompleted) {
                MaterialTheme.colorScheme.primary.copy(alpha = 0.55f)
            } else {
                MaterialTheme.colorScheme.outline.copy(alpha = 0.45f)
            }
        )
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
                enabled = set.isCompleted || !operationInProgress,
                readOnly = set.isCompleted,
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
            OutlinedTextField(
                value = set.repsInput,
                onValueChange = onRepsChanged,
                label = { Text(text = stringResource(R.string.label_reps)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                enabled = set.isCompleted || !operationInProgress,
                readOnly = set.isCompleted,
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
}

private fun formatRestTime(totalSeconds: Int): String = String.format(
    Locale.getDefault(),
    "%02d:%02d",
    totalSeconds / 60,
    totalSeconds % 60
)

private fun formatActiveWorkoutTime(totalSeconds: Long): String {
    val bounded = totalSeconds.coerceAtLeast(0L)
    val hours = bounded / 3_600L
    val minutes = (bounded % 3_600L) / 60L
    val seconds = bounded % 60L
    return if (hours > 0L) {
        String.format(Locale.getDefault(), "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.getDefault(), "%02d:%02d", minutes, seconds)
    }
}
