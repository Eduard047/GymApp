package com.example.gymapp.ui.screens

import android.text.format.DateFormat as AndroidDateFormat
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.platform.testTag
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
import com.example.gymapp.ui.components.LoadingStatePanel
import com.example.gymapp.ui.components.MetricTile
import com.example.gymapp.ui.components.SectionTitle
import com.example.gymapp.ui.components.adaptiveScreenHorizontalPadding
import com.example.gymapp.ui.viewmodel.ActiveWorkoutExerciseUiState
import com.example.gymapp.ui.viewmodel.ActiveWorkoutSetUiState
import com.example.gymapp.ui.viewmodel.ActiveWorkoutUiState
import com.example.gymapp.ui.viewmodel.activeWorkoutOperationInProgress
import com.example.gymapp.ui.viewmodel.parseActiveWorkoutSetInput
import com.example.gymapp.ui.viewmodel.LiveConnectionMode
import com.example.gymapp.ui.viewmodel.LivePeerExerciseSummary
import com.example.gymapp.ui.theme.GymControlShape
import com.example.gymapp.ui.theme.GymSpacing
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.util.asString
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.text.NumberFormat

internal const val ACTIVE_WORKOUT_ELAPSED_METRIC_TAG = "active_workout_elapsed_metric"
internal const val ACTIVE_WORKOUT_COMPLETED_METRIC_TAG = "active_workout_completed_metric"

@Composable
fun ActiveWorkoutScreen(
    uiState: ActiveWorkoutUiState,
    exerciseMediaOwnerKey: String,
    onSetWeightChanged: (String, String) -> Unit,
    onSetRepsChanged: (String, String) -> Unit,
    onSaveExercise: (String) -> Unit,
    onAddSet: (String) -> Unit,
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
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    var showDiscardConfirmation by rememberSaveable { mutableStateOf(false) }
    var showMoreWorkoutOptions by rememberSaveable { mutableStateOf(false) }
    var liveParticipantTab by rememberSaveable(uiState.livePeerName) {
        mutableStateOf(LiveParticipantTab.Self)
    }

    when {
        uiState.isLoading -> {
            Box(
                modifier = modifier
                    .fillMaxSize()
                    .padding(horizontal = screenHorizontalPadding),
                contentAlignment = Alignment.Center
            ) {
                LoadingStatePanel(label = stringResource(R.string.active_workout_loading))
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

    val operationInProgress = activeWorkoutOperationInProgress(
        setRecordingsInFlight = uiState.setRecordingsInFlight,
        isRecordingAll = uiState.isRecordingAll,
        isFinishing = uiState.isFinishing,
        isDiscarding = uiState.isDiscarding,
        undoingSetId = uiState.undoingSetId
    )
    val contextStateExpanded = stringResource(R.string.state_expanded)
    val contextStateCollapsed = stringResource(R.string.state_collapsed)
    val peerName = uiState.livePeerName
    val showSelfParticipant = peerName == null || liveParticipantTab == LiveParticipantTab.Self
    val currentExerciseId = uiState.exercises.firstOrNull { exercise ->
        exercise.sets.any { set -> !set.isCompleted }
    }?.id
    val currentSetId = uiState.exercises.asSequence()
        .flatMap { exercise -> exercise.sets.asSequence() }
        .firstOrNull { set -> !set.isCompleted }
        ?.id

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = screenHorizontalPadding,
            top = GymSpacing.ScreenTop,
            end = screenHorizontalPadding,
            bottom = 112.dp
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
            val fullyCompleted = exercise.sets.isNotEmpty() &&
                exercise.sets.all(ActiveWorkoutSetUiState::isCompleted)
            ActiveWorkoutExerciseCard(
                exercise = exercise,
                initiallyExpanded = exercise.id == currentExerciseId,
                statusLabel = stringResource(
                    when {
                        exercise.id == currentExerciseId -> R.string.active_workout_exercise_current
                        fullyCompleted -> R.string.active_workout_exercise_completed
                        else -> R.string.active_workout_exercise_up_next
                    }
                ),
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                operationInProgress = operationInProgress,
                allowExerciseActions = uiState.liveConnectionMode == null,
                currentSetId = currentSetId,
                inFlightSetIds = uiState.setRecordingsInFlight,
                latestCompletedSetId = uiState.latestCompletedSetId,
                undoingSetId = uiState.undoingSetId,
                restSecondsRemaining = uiState.restSecondsRemaining,
                inlineMessage = uiState.message,
                inlineMessageSetId = uiState.messageSetId,
                onSetWeightChanged = onSetWeightChanged,
                onSetRepsChanged = onSetRepsChanged,
                onSaveExercise = { onSaveExercise(exercise.id) },
                onAddSet = { onAddSet(exercise.id) },
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
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
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
                    }
                    Button(
                        onClick = onFinishWorkout,
                        enabled = uiState.completedSetCount > 0 && !operationInProgress,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
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
                        onClick = { showMoreWorkoutOptions = !showMoreWorkoutOptions },
                        enabled = !operationInProgress,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .semantics {
                                stateDescription = if (showMoreWorkoutOptions) {
                                    contextStateExpanded
                                } else {
                                    contextStateCollapsed
                                }
                            }
                    ) {
                        Icon(
                            imageVector = if (showMoreWorkoutOptions) {
                                Icons.Default.ExpandLess
                            } else {
                                Icons.Default.ExpandMore
                            },
                            contentDescription = null
                        )
                        Text(
                            text = stringResource(R.string.active_workout_more_options),
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                    if (showMoreWorkoutOptions) {
                        OutlinedButton(
                            onClick = { showDiscardConfirmation = true },
                            enabled = !operationInProgress,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        ) {
                            Icon(imageVector = Icons.Default.Delete, contentDescription = null)
                            Text(
                                text = stringResource(R.string.active_workout_discard_action),
                                modifier = Modifier.padding(start = 8.dp)
                            )
                        }
                    }
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
                modifier = Modifier.semantics { heading() },
                style = MaterialTheme.typography.headlineSmall,
                color = Color.White
            )
            val progressDescription = stringResource(
                R.string.active_workout_progress,
                uiState.completedSetCount,
                uiState.totalSetCount
            )
            val progressAccessibilityLabel = stringResource(
                R.string.active_workout_progress_accessibility
            )
            val context = LocalContext.current
            val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
            val completedForProgress = uiState.completedSetCount.coerceAtLeast(0)
            val totalForProgress = uiState.totalSetCount.coerceAtLeast(0)
            val progressMaximum = totalForProgress.coerceAtLeast(1)
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                MetricTile(
                    label = stringResource(R.string.active_workout_elapsed_label),
                    value = formatActiveWorkoutTime(uiState.workoutElapsedSeconds, locale),
                    modifier = Modifier
                        .weight(1f)
                        .testTag(ACTIVE_WORKOUT_ELAPSED_METRIC_TAG),
                    emphasized = true,
                    onHero = true,
                    utilityValue = true
                )
                MetricTile(
                    label = stringResource(R.string.active_workout_completed_label),
                    value = stringResource(
                        R.string.active_workout_completed_value,
                        uiState.completedSetCount,
                        uiState.totalSetCount
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .testTag(ACTIVE_WORKOUT_COMPLETED_METRIC_TAG),
                    onHero = true,
                    utilityValue = true
                )
            }
            Text(
                text = stringResource(
                    R.string.active_workout_started_at,
                    formatActiveWorkoutStartedAt(
                        timestamp = uiState.startedAt,
                        locale = locale,
                        is24Hour = AndroidDateFormat.is24HourFormat(context)
                    )
                ),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.82f)
            )
            LinearProgressIndicator(
                progress = {
                    completedForProgress.coerceAtMost(progressMaximum).toFloat() /
                        progressMaximum.toFloat()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription = progressAccessibilityLabel
                        stateDescription = progressDescription
                        progressBarRangeInfo = ProgressBarRangeInfo(
                            current = completedForProgress.coerceAtMost(progressMaximum).toFloat(),
                            range = 0f..progressMaximum.toFloat(),
                            steps = (progressMaximum - 1).coerceAtLeast(0)
                        )
                    },
                color = Color.White,
                trackColor = Color.White.copy(alpha = 0.2f)
            )
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
    initiallyExpanded: Boolean,
    statusLabel: String,
    exerciseMediaOwnerKey: String,
    operationInProgress: Boolean,
    allowExerciseActions: Boolean,
    currentSetId: String?,
    inFlightSetIds: Set<String>,
    latestCompletedSetId: String?,
    undoingSetId: String?,
    restSecondsRemaining: Int,
    inlineMessage: com.example.gymapp.util.LocalizedText?,
    inlineMessageSetId: String?,
    onSetWeightChanged: (String, String) -> Unit,
    onSetRepsChanged: (String, String) -> Unit,
    onSaveExercise: () -> Unit,
    onAddSet: () -> Unit,
    onRecordSet: (String) -> Unit,
    onUndoLatestSet: (String) -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    onDismissMessage: () -> Unit
) {
    val fullyCompleted = exercise.sets.isNotEmpty() &&
        exercise.sets.all(ActiveWorkoutSetUiState::isCompleted)
    val containsLatestCompletedSet = latestCompletedSetId != null &&
        exercise.sets.any { it.id == latestCompletedSetId }
    var isExpanded by rememberSaveable(exercise.id) { mutableStateOf(initiallyExpanded) }
    LaunchedEffect(fullyCompleted, initiallyExpanded, containsLatestCompletedSet) {
        when {
            containsLatestCompletedSet -> isExpanded = true
            fullyCompleted -> isExpanded = false
            initiallyExpanded -> isExpanded = true
        }
    }
    val expandedState = stringResource(R.string.state_expanded)
    val collapsedState = stringResource(R.string.state_collapsed)
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
                    ).let { progress -> "$statusLabel · $progress" },
                    modifier = Modifier.weight(1f)
                )
                IconButton(
                    onClick = { isExpanded = !isExpanded },
                    modifier = Modifier.semantics {
                        stateDescription = if (isExpanded) expandedState else collapsedState
                    }
                ) {
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
                TextButton(
                    onClick = { isExpanded = true },
                    enabled = allowExerciseActions && !operationInProgress
                ) { Text(stringResource(R.string.active_workout_edit_exercise)) }
            }
            if (isExpanded) exercise.sets.forEach { set ->
                ActiveWorkoutSetRow(
                    set = set,
                    operationInProgress = operationInProgress,
                    editable = !set.isCompleted,
                    isCurrent = set.id == currentSetId,
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
            if (isExpanded && allowExerciseActions) {
                BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
                    val stackActions = maxWidth < 340.dp
                    val actions: @Composable (Modifier, Modifier) -> Unit = { addModifier, saveModifier ->
                        OutlinedButton(
                            onClick = onAddSet,
                            enabled = !operationInProgress,
                            modifier = addModifier.heightIn(min = 48.dp)
                        ) {
                            Icon(Icons.Default.Add, contentDescription = null)
                            Text(
                                stringResource(R.string.active_workout_add_set),
                                modifier = Modifier.padding(start = 6.dp)
                            )
                        }
                        Button(
                            onClick = onSaveExercise,
                            enabled = !operationInProgress,
                            modifier = saveModifier.heightIn(min = 48.dp)
                        ) {
                            Icon(Icons.Default.CheckCircle, contentDescription = null)
                            Text(
                                stringResource(R.string.active_workout_save_exercise),
                                modifier = Modifier.padding(start = 6.dp)
                            )
                        }
                    }
                    if (stackActions) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            actions(Modifier.fillMaxWidth(), Modifier.fillMaxWidth())
                        }
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            actions(Modifier.weight(1f), Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ActiveWorkoutSetRow(
    set: ActiveWorkoutSetUiState,
    operationInProgress: Boolean,
    editable: Boolean,
    isCurrent: Boolean,
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
    val validSetInput = parseActiveWorkoutSetInput(set.weightInput, set.repsInput) != null
    val containerColor = when {
        set.isCompleted -> MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.72f)
        isCurrent -> MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.72f)
        else -> MaterialTheme.colorScheme.surfaceVariant
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
            if (isCurrent && !set.isCompleted) {
                MaterialTheme.colorScheme.tertiary.copy(alpha = 0.72f)
            } else if (set.isCompleted) {
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
            if (isCurrent && !set.isCompleted) {
                InfoPill(text = stringResource(R.string.active_workout_set_current))
            }
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
        BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
            val stackEditors = maxWidth < 340.dp
            if (stackEditors) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ActiveWorkoutWeightField(
                        set = set,
                        editable = editable,
                        operationInProgress = operationInProgress,
                        onWeightChanged = onWeightChanged,
                        modifier = Modifier.fillMaxWidth()
                    )
                    ActiveWorkoutRepsField(
                        set = set,
                        editable = editable,
                        operationInProgress = operationInProgress,
                        onRepsChanged = onRepsChanged,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ActiveWorkoutWeightField(
                        set = set,
                        editable = editable,
                        operationInProgress = operationInProgress,
                        onWeightChanged = onWeightChanged,
                        modifier = Modifier.weight(1f)
                    )
                    ActiveWorkoutRepsField(
                        set = set,
                        editable = editable,
                        operationInProgress = operationInProgress,
                        onRepsChanged = onRepsChanged,
                        modifier = Modifier.weight(1f)
                    )
                }
            }
        }
        if (!set.isCompleted) {
            Button(
                onClick = onRecord,
                enabled = isCurrent && validSetInput && !operationInProgress,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) {
                if (isRecording) {
                    CircularProgressIndicator(
                        modifier = Modifier.padding(end = 8.dp).size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                }
                Text(stringResource(R.string.action_log_set_and_rest, restDurationSeconds))
            }
        }
        if (isLatestCompleted) {
            if (restSecondsRemaining > 0) {
                AppPanel(
                    modifier = Modifier.fillMaxWidth().semantics {
                        stateDescription = formatRestTime(restSecondsRemaining)
                    },
                    highlighted = true
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            stringResource(R.string.active_workout_rest_saved),
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary
                        )
                        Text(
                            formatRestTime(restSecondsRemaining),
                            style = MaterialTheme.typography.headlineSmall
                        )
                        ActiveWorkoutRestControls(
                            enabled = !operationInProgress,
                            onAdjustRestTimer = onAdjustRestTimer,
                            onStopRestTimer = onStopRestTimer
                        )
                    }
                }
            }
            OutlinedButton(
                onClick = onUndo,
                enabled = !operationInProgress,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) {
                if (isUndoing) {
                    CircularProgressIndicator(
                        modifier = Modifier.padding(end = 8.dp).size(18.dp),
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

@Composable
private fun ActiveWorkoutRestControls(
    enabled: Boolean,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit
) {
    val subtractDescription = stringResource(R.string.active_workout_rest_subtract)
    val addDescription = stringResource(R.string.active_workout_rest_add)
    BoxWithConstraints(modifier = Modifier.fillMaxWidth()) {
        val stacked = maxWidth < 320.dp
        val controls: @Composable (Modifier, Modifier, Modifier) -> Unit =
            { subtractModifier, addModifier, stopModifier ->
                OutlinedButton(
                    onClick = { onAdjustRestTimer(-15) },
                    enabled = enabled,
                    modifier = subtractModifier.heightIn(min = 48.dp).semantics {
                        contentDescription = subtractDescription
                    }
                ) { Text("−15") }
                OutlinedButton(
                    onClick = { onAdjustRestTimer(15) },
                    enabled = enabled,
                    modifier = addModifier.heightIn(min = 48.dp).semantics {
                        contentDescription = addDescription
                    }
                ) { Text("+15") }
                TextButton(
                    onClick = onStopRestTimer,
                    enabled = enabled,
                    modifier = stopModifier.heightIn(min = 48.dp)
                ) { Text(stringResource(R.string.active_workout_rest_stop)) }
            }
        if (stacked) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                controls(
                    Modifier.fillMaxWidth(),
                    Modifier.fillMaxWidth(),
                    Modifier.fillMaxWidth()
                )
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                controls(Modifier.weight(1f), Modifier.weight(1f), Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun ActiveWorkoutWeightField(
    set: ActiveWorkoutSetUiState,
    editable: Boolean,
    operationInProgress: Boolean,
    onWeightChanged: (String) -> Unit,
    modifier: Modifier
) {
    OutlinedTextField(
        value = set.weightInput,
        onValueChange = onWeightChanged,
        label = { Text(stringResource(R.string.label_weight_kg)) },
        placeholder = { Text("0") },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        enabled = editable && !operationInProgress,
        readOnly = !editable,
        singleLine = true,
        modifier = modifier
    )
}

@Composable
private fun ActiveWorkoutRepsField(
    set: ActiveWorkoutSetUiState,
    editable: Boolean,
    operationInProgress: Boolean,
    onRepsChanged: (String) -> Unit,
    modifier: Modifier
) {
    OutlinedTextField(
        value = set.repsInput,
        onValueChange = onRepsChanged,
        label = { Text(stringResource(R.string.label_reps)) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        enabled = editable && !operationInProgress,
        readOnly = !editable,
        singleLine = true,
        modifier = modifier
    )
}

private fun formatRestTime(totalSeconds: Int): String = String.format(
    Locale.getDefault(),
    "%d:%02d",
    totalSeconds.coerceAtLeast(0) / 60,
    totalSeconds.coerceAtLeast(0) % 60
)

internal fun formatActiveWorkoutTime(
    totalSeconds: Long,
    locale: Locale = Locale.getDefault()
): String {
    val bounded = totalSeconds.coerceAtLeast(0L)
    val hours = bounded / 3_600L
    val minutes = (bounded % 3_600L) / 60L
    val seconds = bounded % 60L
    return if (hours > 0L) {
        String.format(locale, "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(locale, "%02d:%02d", minutes, seconds)
    }
}

internal fun formatActiveWorkoutStartedAt(
    timestamp: Long,
    locale: Locale = Locale.getDefault(),
    zoneId: ZoneId = ZoneId.systemDefault(),
    is24Hour: Boolean = true
): String = DateTimeFormatter.ofPattern(if (is24Hour) "HH:mm" else "h:mm a", locale)
    .withZone(zoneId)
    .format(Instant.ofEpochMilli(timestamp))
