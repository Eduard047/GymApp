package com.example.gymapp.ui.screens

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.unit.Dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import com.example.gymapp.ui.components.BrandHeroPanel
import com.example.gymapp.R
import com.example.gymapp.auth.FriendGhost
import com.example.gymapp.auth.FriendGhosts
import com.example.gymapp.data.repository.PlateCalculator
import com.example.gymapp.data.repository.PlateLoad
import com.example.gymapp.data.repository.VoiceWorkoutCommand
import com.example.gymapp.data.repository.VoiceWorkoutCommandParser
import com.example.gymapp.data.repository.VoiceWorkoutDraftParser
import com.example.gymapp.ui.components.AppPanel
import com.example.gymapp.ui.components.EmptyStatePanel
import com.example.gymapp.ui.components.ExerciseMediaPreview
import com.example.gymapp.ui.components.GymSegmentItem
import com.example.gymapp.ui.components.GymSegmentedControl
import com.example.gymapp.ui.components.HeroPanel
import com.example.gymapp.ui.components.InfoPill
import com.example.gymapp.ui.components.tabularDigits
import com.example.gymapp.ui.components.LoadingStatePanel
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
import com.example.gymapp.ui.util.currentAppLanguageTag
import com.example.gymapp.ui.util.localizedExerciseName
import com.example.gymapp.util.asString
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.text.NumberFormat
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

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
    onSkipRemainingSets: (String) -> Unit = {},
    onDeleteSet: (String) -> Unit = {},
    onRemoveExercise: (String) -> Unit = {},
    onRecordSet: (String) -> Unit,
    onRecordAllPendingSets: () -> Unit,
    onUndoLatestSet: (String) -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    onFinishWorkout: () -> Unit,
    onDiscardWorkout: () -> Unit,
    onDismissMessage: () -> Unit,
    onPreviewAdaptation: (String, Int, Long?) -> Unit = { _, _, _ -> },
    onApplyAdaptation: () -> Unit = {},
    onDismissAdaptation: () -> Unit = {},
    voiceCommandSnackbarHostState: SnackbarHostState? = null,
    friendGhosts: Map<String, FriendGhost> = emptyMap(),
    toolbarState: ActiveWorkoutToolbarState? = null,
    modifier: Modifier = Modifier
) {
    val screenHorizontalPadding = adaptiveScreenHorizontalPadding()
    val haptics = LocalHapticFeedback.current
    val recordSetIds = uiState.exercises.asSequence()
        .flatMap { exercise -> exercise.sets.asSequence() }
        .filter { set -> set.isPersonalRecord }
        .map { set -> set.id }
        .toSet()
    var knownRecordSetIds by remember { mutableStateOf<Set<String>?>(null) }
    LaunchedEffect(recordSetIds) {
        // A newly logged record gets a short vibration; opening a workout that already holds
        // records does not.
        val known = knownRecordSetIds
        if (known != null && (recordSetIds - known).isNotEmpty()) {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        }
        knownRecordSetIds = recordSetIds
    }
    val voiceCommandScope = rememberCoroutineScope()
    // Feedback channel for the in-workout voice mic (LogSet/RepeatPrevious/SkipRest/
    // Unknown): a Snackbar with an optional action (e.g. "Отменить" after LogSet).
    val onVoiceCommandFeedback: (String, String?, (() -> Unit)?) -> Unit = feedback@{ message, actionLabel, onAction ->
        val hostState = voiceCommandSnackbarHostState ?: return@feedback
        voiceCommandScope.launch {
            val result = hostState.showSnackbar(message = message, actionLabel = actionLabel, withDismissAction = actionLabel == null)
            if (result == SnackbarResult.ActionPerformed) onAction?.invoke()
        }
    }
    // The one confirmation banner for a recorded set (visible Log button and the voice commands).
    val bannerContext = LocalContext.current
    var recordedConfirmation by remember { mutableStateOf<RecordedConfirmation?>(null) }
    var confirmationWasShowing by remember(recordedConfirmation) { mutableStateOf(false) }
    LaunchedEffect(
        recordedConfirmation,
        uiState.latestCompletedSetId,
        uiState.setRecordingsInFlight,
        uiState.message,
        uiState.messageSetId
    ) {
        val current = recordedConfirmation ?: return@LaunchedEffect
        when (
            recordedConfirmationStep(
                setId = current.setId,
                latestCompletedSetId = uiState.latestCompletedSetId,
                setRecordingsInFlight = uiState.setRecordingsInFlight,
                wasShowing = confirmationWasShowing,
                hasFailureForSet = uiState.message != null && uiState.messageSetId == current.setId
            )
        ) {
            RecordedConfirmationStep.Showing -> confirmationWasShowing = true
            RecordedConfirmationStep.Clear -> recordedConfirmation = null
            RecordedConfirmationStep.Waiting -> Unit
        }
    }
    // A finished/skipped exercise replaces the recorded-set banner with its own status.
    LaunchedEffect(uiState.message) {
        val message = uiState.message
        if (message != null && uiState.messageSetId == null && activeWorkoutMessageIsSuccess(message.resourceId)) {
            recordedConfirmation = null
        }
    }
    val onSetRecorded: (String, String, String, Int) -> Unit = { setId, weightText, repsText, restSeconds ->
        val summary = bannerContext.getString(R.string.active_workout_set_summary, weightText, repsText)
        val message = bannerContext.getString(R.string.active_workout_recorded_banner, summary)
        val announcement = recordedSetAnnouncement(message, restSeconds) { text, clock ->
            bannerContext.getString(R.string.active_workout_recorded_announcement, text, clock)
        }
        recordedConfirmation = RecordedConfirmation(message, announcement, setId)
    }
    val onVoiceStarted: () -> Unit = { recordedConfirmation = null }
    var showDiscardConfirmation by rememberSaveable { mutableStateOf(false) }
    var liveParticipantTab by rememberSaveable(uiState.livePeerName) {
        mutableStateOf(LiveParticipantTab.Self)
    }

    val operationInProgress = activeWorkoutOperationInProgress(
        setRecordingsInFlight = uiState.setRecordingsInFlight,
        isRecordingAll = uiState.isRecordingAll,
        isFinishing = uiState.isFinishing,
        isDiscarding = uiState.isDiscarding,
        undoingSetId = uiState.undoingSetId
    )
    // The toolbar overflow (Adapt workout / Discard) lives in the navigation bar, so the screen
    // publishes what it may offer and consumes the discard request the menu raises.
    val overflowAvailable = !uiState.isLoading && !uiState.isMissing && uiState.liveConnectionMode == null
    val adaptAvailable = overflowAvailable &&
        !uiState.isFinishing &&
        !uiState.isDiscarding &&
        uiState.exercises.any { exercise -> exercise.sets.any { set -> !set.isCompleted } }
    SideEffect {
        toolbarState?.let { toolbar ->
            toolbar.showsOverflow = overflowAvailable
            toolbar.canAdapt = adaptAvailable
            toolbar.canDiscard = !operationInProgress
            toolbar.previewAdaptation = onPreviewAdaptation
        }
    }
    DisposableEffect(toolbarState) {
        onDispose { toolbarState?.reset() }
    }
    val discardRequested = toolbarState?.discardRequested == true
    LaunchedEffect(discardRequested) {
        if (discardRequested) {
            showDiscardConfirmation = true
            toolbarState?.discardRequested = false
        }
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

    // New on every entry to the screen (not saved), so each exercise card re-derives its entry expansion; it is
    // stable while the screen stays in composition, so scrolling cards in and out keeps the user's toggles.
    val screenEntryToken = remember { Any() }
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
                val isSuccess = activeWorkoutMessageIsSuccess(message.resourceId)
                AppPanel(
                    modifier = Modifier.fillMaxWidth(),
                    containerColor = if (isSuccess) {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
                    } else {
                        MaterialTheme.colorScheme.error.copy(alpha = 0.16f)
                    },
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
                            color = if (isSuccess) {
                                MaterialTheme.colorScheme.onSurface
                            } else {
                                MaterialTheme.colorScheme.error
                            }
                        )
                        TextButton(onClick = onDismissMessage) {
                            Text(text = stringResource(R.string.action_close))
                        }
                    }
                }
            }
        }

        recordedConfirmation?.let { confirmation ->
            item(key = "recorded-confirmation") {
                RecordedConfirmationBanner(
                    confirmation = confirmation,
                    undoEnabled = confirmation.setId == uiState.latestCompletedSetId && !operationInProgress,
                    onUndo = {
                        onUndoLatestSet(confirmation.setId)
                        recordedConfirmation = null
                    },
                    onDismiss = { recordedConfirmation = null }
                )
            }
        }

        items(
            items = uiState.exercises,
            key = ActiveWorkoutExerciseUiState::id
        ) { exercise ->
            ActiveWorkoutExerciseCard(
                exercise = exercise,
                initiallyExpanded = exercise.id == currentExerciseId,
                screenEntryToken = screenEntryToken,
                isCurrent = exercise.id == currentExerciseId,
                exerciseMediaOwnerKey = exerciseMediaOwnerKey,
                friendGhost = friendGhosts[exercise.friendGhostKey],
                operationInProgress = operationInProgress,
                allowExerciseActions = uiState.liveConnectionMode == null,
                canSkipRemaining = exercise.canSkipRemaining,
                currentSetId = currentSetId,
                inFlightSetIds = uiState.setRecordingsInFlight,
                latestCompletedSetId = uiState.latestCompletedSetId,
                restSecondsRemaining = uiState.restSecondsRemaining,
                inlineMessage = uiState.message,
                inlineMessageSetId = uiState.messageSetId,
                onSetWeightChanged = onSetWeightChanged,
                onSetRepsChanged = onSetRepsChanged,
                onSaveExercise = { onSaveExercise(exercise.id) },
                onAddSet = { onAddSet(exercise.id) },
                onSkipRemainingSets = { onSkipRemainingSets(exercise.id) },
                canRemoveExercise = uiState.liveConnectionMode == null && uiState.exercises.size > 1,
                onRemoveExercise = { onRemoveExercise(exercise.id) },
                onDeleteSet = onDeleteSet,
                onRecordSet = onRecordSet,
                onUndoLatestSet = onUndoLatestSet,
                onAdjustRestTimer = onAdjustRestTimer,
                onStopRestTimer = onStopRestTimer,
                onDismissMessage = onDismissMessage,
                onSetRecorded = onSetRecorded,
                onVoiceStarted = onVoiceStarted,
                onVoiceCommandFeedback = onVoiceCommandFeedback
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

    uiState.adaptation?.let { adaptation ->
        AlertDialog(onDismissRequest = onDismissAdaptation,
            title = { Text(stringResource(when (adaptation.reason) { "equipmentUnavailable" -> R.string.training_equipment_busy; "timeCut" -> R.string.training_short_time; else -> R.string.training_too_hard })) },
            text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (adaptation.reason == "timeCut" && !adaptation.hasPreview) Row { listOf(10,20,30).forEach { minutes ->
                    TextButton(onClick = { onPreviewAdaptation(adaptation.reason, minutes, null) }) { Text("$minutes") }
                } }
                if (adaptation.reason == "equipmentUnavailable" && !adaptation.hasPreview) adaptation.choices.forEach { choice ->
                    TextButton(onClick = { onPreviewAdaptation(adaptation.reason, 20, choice.exerciseId) }) { Text(localizedExerciseName(choice.name)) }
                }
                if (!adaptation.hasPreview && adaptation.choices.isEmpty() && adaptation.reason == "equipmentUnavailable") Text(stringResource(R.string.training_no_alternative))
                if (adaptation.hasPreview) {
                    Text(stringResource(R.string.training_remaining_sets, adaptation.beforePending, adaptation.afterPending))
                    if (adaptation.reason == "timeCut") Text(stringResource(R.string.training_time_estimate))
                    adaptation.previewLines.forEach { line ->
                        val name = localizedExerciseName(line.name)
                        val before = if (line.previousName.isNotEmpty() && line.previousName != line.name) localizedExerciseName(line.previousName) + " → " else ""
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("$before$name", style = MaterialTheme.typography.titleSmall)
                            Text(stringResource(R.string.training_remaining_sets, line.before, line.after))
                            val number = java.text.NumberFormat.getNumberInstance()
                            line.values.forEach { value ->
                                val old = if (value.previousWeight != null) stringResource(R.string.set_weight_reps_value,
                                    number.format(value.previousWeight), value.previousReps.toString()) + " → " else ""
                                Text(old + stringResource(R.string.set_weight_reps_value, number.format(value.weight), value.reps.toString()),
                                    style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            } },
            confirmButton = { if (adaptation.hasPreview) TextButton(onClick = onApplyAdaptation, enabled = !adaptation.isApplying) { Text(stringResource(R.string.training_apply_changes)) } },
            dismissButton = { TextButton(onClick = onDismissAdaptation, enabled = !adaptation.isApplying) { Text(stringResource(R.string.action_cancel)) } })
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

/**
 * What the navigation bar needs from the active workout screen: whether to show the overflow menu,
 * which actions it may offer, and the callbacks it triggers. The screen publishes it, the bar reads
 * it, so the Minimize/overflow controls live in the toolbar like on iOS.
 */
@Stable
class ActiveWorkoutToolbarState {
    var showsOverflow by mutableStateOf(false)
    var canAdapt by mutableStateOf(false)
    var canDiscard by mutableStateOf(false)
    var discardRequested by mutableStateOf(false)
    var previewAdaptation: (String, Int, Long?) -> Unit = { _, _, _ -> }

    internal fun reset() {
        showsOverflow = false
        canAdapt = false
        canDiscard = false
        discardRequested = false
        previewAdaptation = { _, _, _ -> }
    }
}

@Composable
fun ActiveWorkoutOverflowMenu(state: ActiveWorkoutToolbarState) {
    var expanded by remember { mutableStateOf(false) }
    var adaptOpen by remember { mutableStateOf(false) }
    val close = {
        expanded = false
        adaptOpen = false
    }
    Box {
        IconButton(onClick = { expanded = true }) {
            Icon(
                imageVector = Icons.Default.MoreVert,
                contentDescription = stringResource(R.string.active_workout_more_options)
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = close) {
            if (state.canAdapt) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.training_adapt_workout)) },
                    leadingIcon = { Icon(Icons.Default.Tune, contentDescription = null) },
                    trailingIcon = {
                        Icon(
                            imageVector = if (adaptOpen) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                            contentDescription = null
                        )
                    },
                    onClick = { adaptOpen = !adaptOpen }
                )
                if (adaptOpen) {
                    listOf(
                        "equipmentUnavailable" to R.string.training_equipment_busy,
                        "timeCut" to R.string.training_short_time,
                        "tooHard" to R.string.training_too_hard
                    ).forEach { (reason, label) ->
                        DropdownMenuItem(
                            text = { Text(stringResource(label)) },
                            modifier = Modifier.padding(start = 24.dp),
                            onClick = {
                                close()
                                state.previewAdaptation(reason, if (reason == "timeCut") 0 else 20, null)
                            }
                        )
                    }
                }
            }
            DropdownMenuItem(
                text = {
                    Text(
                        text = stringResource(R.string.active_workout_discard_short),
                        color = MaterialTheme.colorScheme.error
                    )
                },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error
                    )
                },
                enabled = state.canDiscard,
                onClick = {
                    close()
                    state.discardRequested = true
                }
            )
        }
    }
}

private enum class LiveParticipantTab { Self, Peer }

@Composable
private fun ActiveWorkoutHero(uiState: ActiveWorkoutUiState) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val completed = uiState.completedSetCount.coerceAtLeast(0)
    val total = uiState.totalSetCount.coerceAtLeast(0)
    val currentExerciseName = uiState.exercises
        .firstOrNull { exercise -> exercise.sets.any { set -> !set.isCompleted } }
        ?.let { exercise -> localizedExerciseName(exercise.exerciseName) }
    val elapsed = formatActiveWorkoutTime(uiState.workoutElapsedSeconds, locale)
    val setsDone = pluralStringResource(
        R.plurals.active_workout_hero_sets_done,
        total,
        completed,
        total
    )
    val summary = if (currentExerciseName != null) {
        stringResource(R.string.active_workout_hero_summary_now, elapsed, setsDone, currentExerciseName)
    } else {
        stringResource(R.string.active_workout_hero_summary, elapsed, setsDone)
    }
    val fraction = (completed.toFloat() / total.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)
    val softWhite = Color.White.copy(alpha = 0.85f)
    BrandHeroPanel(
        modifier = Modifier
            .fillMaxWidth()
            // The whole card is one accessibility element: elapsed, sets done and current exercise.
            .clearAndSetSemantics { contentDescription = summary },
        contentPadding = 18.dp
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .background(Color.White, CircleShape)
                    )
                    Text(
                        text = stringResource(R.string.active_workout_status_in_progress),
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                        color = softWhite
                    )
                }
                Text(
                    text = elapsed,
                    modifier = Modifier.testTag(ACTIVE_WORKOUT_ELAPSED_METRIC_TAG),
                    style = TextStyle(
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 36.sp
                    ).tabularDigits(),
                    color = Color.White,
                    maxLines = 1
                )
                if (currentExerciseName != null) {
                    Text(
                        text = stringResource(R.string.active_workout_now, currentExerciseName),
                        style = MaterialTheme.typography.labelMedium,
                        color = softWhite,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Box(
                modifier = Modifier
                    .size(68.dp)
                    .testTag(ACTIVE_WORKOUT_COMPLETED_METRIC_TAG),
                contentAlignment = Alignment.Center
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val strokeWidth = 7.dp.toPx()
                    val arcSize = Size(size.width - strokeWidth, size.height - strokeWidth)
                    val topLeft = Offset(strokeWidth / 2f, strokeWidth / 2f)
                    drawArc(
                        color = Color.White.copy(alpha = 0.28f),
                        startAngle = 0f,
                        sweepAngle = 360f,
                        useCenter = false,
                        topLeft = topLeft,
                        size = arcSize,
                        style = Stroke(width = strokeWidth)
                    )
                    if (fraction > 0f) {
                        drawArc(
                            color = Color.White,
                            startAngle = -90f,
                            sweepAngle = 360f * fraction,
                            useCenter = false,
                            topLeft = topLeft,
                            size = arcSize,
                            style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
                        )
                    }
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "$completed/$total",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.SemiBold
                        ).tabularDigits(),
                        color = Color.White,
                        maxLines = 1
                    )
                    Text(
                        text = stringResource(R.string.active_workout_sets_caption),
                        style = TextStyle(fontSize = 10.sp),
                        color = softWhite,
                        maxLines = 1
                    )
                }
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

/**
 * Expansion change for an exercise card, or null to keep what the user set. Mirrors iOS
 * `collapseCompletedExercises` on appear: on every screen entry only the current exercise and the one holding
 * the latest (undoable) recorded set start open, every other exercise starts collapsed. Afterwards recording a
 * set expands its card, and a fully recorded card collapses again once a later set becomes the latest one.
 */
internal fun exerciseCardExpansionUpdate(
    entering: Boolean,
    fullyCompleted: Boolean,
    containsLatestCompletedSet: Boolean,
    wasFullyCompleted: Boolean,
    wasContainsLatestCompletedSet: Boolean,
    initiallyExpanded: Boolean
): Boolean? = when {
    entering -> initiallyExpanded || containsLatestCompletedSet
    fullyCompleted -> {
        val changed = !wasFullyCompleted || wasContainsLatestCompletedSet != containsLatestCompletedSet
        if (changed) containsLatestCompletedSet else null
    }
    containsLatestCompletedSet -> if (!wasContainsLatestCompletedSet) true else null
    initiallyExpanded -> true
    else -> null
}

@Composable
private fun ActiveWorkoutExerciseCard(
    exercise: ActiveWorkoutExerciseUiState,
    initiallyExpanded: Boolean,
    screenEntryToken: Any,
    isCurrent: Boolean,
    exerciseMediaOwnerKey: String,
    friendGhost: FriendGhost?,
    operationInProgress: Boolean,
    allowExerciseActions: Boolean,
    canSkipRemaining: Boolean,
    currentSetId: String?,
    inFlightSetIds: Set<String>,
    latestCompletedSetId: String?,
    restSecondsRemaining: Int,
    inlineMessage: com.example.gymapp.util.LocalizedText?,
    inlineMessageSetId: String?,
    onSetWeightChanged: (String, String) -> Unit,
    onSetRepsChanged: (String, String) -> Unit,
    onSaveExercise: () -> Unit,
    onAddSet: () -> Unit,
    onSkipRemainingSets: () -> Unit,
    canRemoveExercise: Boolean,
    onRemoveExercise: () -> Unit,
    onDeleteSet: (String) -> Unit,
    onRecordSet: (String) -> Unit,
    onUndoLatestSet: (String) -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    onDismissMessage: () -> Unit,
    onSetRecorded: (setId: String, weightText: String, repsText: String, restSeconds: Int) -> Unit = { _, _, _, _ -> },
    onVoiceStarted: () -> Unit = {},
    onVoiceCommandFeedback: (String, String?, (() -> Unit)?) -> Unit = { _, _, _ -> }
) {
    val fullyCompleted = exercise.sets.isNotEmpty() &&
        exercise.sets.all(ActiveWorkoutSetUiState::isCompleted)
    val containsLatestCompletedSet = latestCompletedSetId != null &&
        exercise.sets.any { it.id == latestCompletedSetId }
    var isExpanded by rememberSaveable(exercise.id, screenEntryToken) {
        mutableStateOf(initiallyExpanded || containsLatestCompletedSet)
    }
    var showFinishDialog by remember(exercise.id) { mutableStateOf(false) }
    var showRemoveDialog by remember(exercise.id) { mutableStateOf(false) }
    // Set when the finish dialog starts a save or skip; the card then collapses as soon as every
    // remaining set is done, even though the latest recorded set still belongs to it.
    var collapseAfterFinish by remember(exercise.id) { mutableStateOf(false) }
    val unrecordedCount = exercise.sets.count { !it.isCompleted }
    // Last seen (fullyCompleted, containsLatestCompletedSet) as bit flags, -1 before the first pass. Saved with
    // the card so a rotation does not replay screen entry and override the user's own expand/collapse.
    var seenFlags by rememberSaveable(exercise.id, screenEntryToken) { mutableStateOf(-1) }
    LaunchedEffect(fullyCompleted, initiallyExpanded, containsLatestCompletedSet) {
        val entering = seenFlags < 0
        exerciseCardExpansionUpdate(
            entering = entering,
            fullyCompleted = fullyCompleted,
            containsLatestCompletedSet = containsLatestCompletedSet,
            wasFullyCompleted = seenFlags >= 0 && seenFlags and 2 != 0,
            wasContainsLatestCompletedSet = seenFlags >= 0 && seenFlags and 1 != 0,
            initiallyExpanded = initiallyExpanded
        )?.let { isExpanded = it }
        seenFlags = (if (containsLatestCompletedSet) 1 else 0) or (if (fullyCompleted) 2 else 0)
    }
    // Declared after the effect above so it wins when both fire for the same change: after the
    // finish dialog's save/skip succeeds, the card collapses although it still holds the latest set.
    LaunchedEffect(collapseAfterFinish, fullyCompleted) {
        if (collapseAfterFinish && fullyCompleted) {
            isExpanded = false
            collapseAfterFinish = false
        }
    }
    val completedCount = exercise.sets.count(ActiveWorkoutSetUiState::isCompleted)
    val totalCount = exercise.sets.size
    val exerciseName = localizedExerciseName(exercise.exerciseName)
    val progressValue = "$completedCount / $totalCount"
    WorkoutExerciseCardShell {
        WorkoutExerciseCardHeader(
            title = exerciseName,
            expanded = isExpanded,
            onToggleExpanded = { isExpanded = !isExpanded },
            stateText = progressValue,
            media = exercise.exerciseId?.let { exerciseId ->
                {
                    WorkoutExerciseMedia(
                        exerciseId = exerciseId,
                        exerciseName = exercise.exerciseName,
                        ownerKey = exerciseMediaOwnerKey
                    )
                }
            },
            menu = if (canRemoveExercise) {
                {
                    WorkoutExerciseMenu(
                        enabled = !operationInProgress,
                        onRemove = { showRemoveDialog = true }
                    )
                }
            } else {
                null
            }
        ) {
            if (isExpanded) {
                if (totalCount > 0) {
                    val index = exercise.sets
                        .indexOfFirst { set -> !set.isCompleted }
                        .takeIf { it >= 0 } ?: (totalCount - 1)
                    Text(
                        text = stringResource(
                            R.string.active_workout_exercise_set_subtitle,
                            index + 1,
                            totalCount
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1
                    )
                }
            } else {
                val progressColor = if (fullyCompleted) {
                    MaterialTheme.colorScheme.secondary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = if (fullyCompleted) {
                            Icons.Default.Verified
                        } else {
                            Icons.Default.RadioButtonUnchecked
                        },
                        contentDescription = null,
                        tint = progressColor,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = progressValue,
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontWeight = FontWeight.Bold
                        ).tabularDigits(),
                        color = progressColor
                    )
                }
                if (!isCurrent) {
                    Text(
                        text = if (fullyCompleted) {
                            stringResource(R.string.active_workout_exercise_done)
                        } else {
                            pluralStringResource(
                                R.plurals.active_workout_exercise_up_next_sets,
                                totalCount,
                                totalCount
                            )
                        },
                        style = MaterialTheme.typography.labelMedium.copy(
                            fontWeight = FontWeight.SemiBold
                        ),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        if (isExpanded && friendGhost != null) friendGhost.let { ghost ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Group,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = friendGhostLine(ghost),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2
                )
            }
        }
        if (isExpanded) Column(modifier = Modifier.fillMaxWidth()) {
            exercise.sets.forEachIndexed { index, set ->
                val isCurrentSet = set.id == currentSetId && !set.isCompleted
                val followsCurrentSet = index > 0 && exercise.sets[index - 1].let { previous ->
                    previous.id == currentSetId && !previous.isCompleted
                }
                // Thin dividers separate plain rows only, never the current set's card.
                if (index > 0 && !isCurrentSet && !followsCurrentSet) {
                    HorizontalDivider(
                        thickness = 1.dp,
                        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f)
                    )
                }
                ActiveWorkoutSetRow(
                    set = set,
                    operationInProgress = operationInProgress,
                    editable = !set.isCompleted,
                    isCurrent = set.id == currentSetId,
                    isRecording = set.id in inFlightSetIds,
                    isLatestCompleted = set.id == latestCompletedSetId,
                    showsPlateCalculator = PlateCalculator.applies(exercise.catalogKey),
                    isBodyweight = isBodyweightCatalogKey(exercise.catalogKey),
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
                    canDelete = allowExerciseActions && !set.isCompleted &&
                        exercise.sets.size > 1 && !operationInProgress,
                    onDelete = { onDeleteSet(set.id) },
                    onAdjustRestTimer = onAdjustRestTimer,
                    onStopRestTimer = onStopRestTimer,
                    onDismissMessage = onDismissMessage,
                    isRestActive = restSecondsRemaining > 0,
                    onRecorded = { weightText, repsText ->
                        onSetRecorded(set.id, weightText, repsText, exercise.restDurationSeconds)
                    },
                    onVoiceStarted = onVoiceStarted,
                    onVoiceCommandFeedback = onVoiceCommandFeedback
                )
            }
        }
        if (isExpanded && allowExerciseActions) {
            // Two equal columns, no divider: dashed "+ Set" leading, solid "Finish" trailing.
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                WorkoutFooterButton(
                    label = stringResource(R.string.active_workout_add_set_short),
                    accessibilityLabel = stringResource(R.string.active_workout_add_set),
                    dashed = true,
                    enabled = !operationInProgress,
                    onClick = onAddSet,
                    modifier = Modifier.weight(1f)
                )
                WorkoutFooterButton(
                    label = stringResource(R.string.active_workout_finish_exercise),
                    accessibilityLabel = stringResource(R.string.active_workout_save_exercise),
                    dashed = false,
                    enabled = !operationInProgress,
                    onClick = {
                        // Nothing unrecorded: finish immediately (collapse). Otherwise ask first.
                        if (unrecordedCount > 0) showFinishDialog = true else isExpanded = false
                    },
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
    if (showRemoveDialog) {
        WorkoutRemoveExerciseDialog(
            exerciseName = exerciseName,
            recordedCount = completedCount,
            onConfirm = {
                showRemoveDialog = false
                onRemoveExercise()
            },
            onDismiss = { showRemoveDialog = false }
        )
    }
    if (showFinishDialog && unrecordedCount > 0) {
        ActiveWorkoutFinishExerciseDialog(
            unrecordedCount = unrecordedCount,
            canSkip = canSkipRemaining && allowExerciseActions,
            onLogAsPlanned = {
                showFinishDialog = false
                collapseAfterFinish = true
                onSaveExercise()
            },
            onSkip = {
                showFinishDialog = false
                collapseAfterFinish = true
                onSkipRemainingSets()
            },
            onDismiss = { showFinishDialog = false }
        )
    }
}

/** "N sets left": log as planned, skip them (when a skip candidate exists), or cancel. */
@Composable
private fun ActiveWorkoutFinishExerciseDialog(
    unrecordedCount: Int,
    canSkip: Boolean,
    onLogAsPlanned: () -> Unit,
    onSkip: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                pluralStringResource(
                    R.plurals.active_workout_finish_sets_left,
                    unrecordedCount,
                    unrecordedCount
                )
            )
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = onLogAsPlanned,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                ) {
                    Text(stringResource(R.string.active_workout_finish_log_as_planned))
                }
                if (canSkip) {
                    OutlinedButton(
                        onClick = onSkip,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                    ) {
                        Text(stringResource(R.string.active_workout_finish_skip_them))
                    }
                }
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                ) {
                    Text(stringResource(R.string.action_cancel))
                }
            }
        },
        confirmButton = {}
    )
}

@Composable
private fun ActiveWorkoutSetRow(
    set: ActiveWorkoutSetUiState,
    operationInProgress: Boolean,
    editable: Boolean,
    isCurrent: Boolean,
    isRecording: Boolean,
    isLatestCompleted: Boolean,
    showsPlateCalculator: Boolean,
    isBodyweight: Boolean,
    restDurationSeconds: Int,
    restSecondsRemaining: Int,
    inlineMessage: com.example.gymapp.util.LocalizedText?,
    onWeightChanged: (String) -> Unit,
    onRepsChanged: (String) -> Unit,
    onRecord: () -> Unit,
    onUndo: () -> Unit,
    canDelete: Boolean,
    onDelete: () -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit,
    onDismissMessage: () -> Unit,
    isRestActive: Boolean = false,
    onRecorded: (weightText: String, repsText: String) -> Unit = { _, _ -> },
    onVoiceStarted: () -> Unit = {},
    onVoiceCommandFeedback: (String, String?, (() -> Unit)?) -> Unit = { _, _, _ -> }
) {
    val validSetInput = parseActiveWorkoutSetInput(set.weightInput, set.repsInput) != null
    Column(modifier = Modifier.fillMaxWidth()) {
        when {
            set.isCompleted -> CompletedSetRow(
                set = set,
                operationInProgress = operationInProgress,
                isLatestCompleted = isLatestCompleted,
                restSecondsRemaining = restSecondsRemaining,
                onUndo = onUndo,
                onAdjustRestTimer = onAdjustRestTimer,
                onStopRestTimer = onStopRestTimer
            )
            isCurrent -> CurrentSetCard(
                set = set,
                operationInProgress = operationInProgress,
                validSetInput = validSetInput,
                isRecording = isRecording,
                showsPlateCalculator = showsPlateCalculator,
                isBodyweight = isBodyweight,
                restDurationSeconds = restDurationSeconds,
                isRestActive = isRestActive,
                onWeightChanged = onWeightChanged,
                onRepsChanged = onRepsChanged,
                onRecord = onRecord,
                onRecorded = onRecorded,
                onVoiceStarted = onVoiceStarted,
                onStopRestTimer = onStopRestTimer,
                onVoiceCommandFeedback = onVoiceCommandFeedback,
                canDelete = canDelete,
                onDelete = onDelete
            )
            else -> UpcomingSetRow(
                set = set,
                editorsEnabled = editable && !operationInProgress,
                canLog = validSetInput && !operationInProgress,
                isRecording = isRecording,
                canDelete = canDelete,
                onWeightChanged = onWeightChanged,
                onRepsChanged = onRepsChanged,
                onRecord = {
                    onRecord()
                    onRecorded(set.weightInput.ifBlank { "0" }, set.repsInput.ifBlank { "0" })
                },
                onDelete = onDelete
            )
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

/** A not-yet-reached set: one plain line, tappable to expand into an inline editor. */
@Composable
private fun UpcomingSetRow(
    set: ActiveWorkoutSetUiState,
    editorsEnabled: Boolean,
    canLog: Boolean,
    isRecording: Boolean,
    canDelete: Boolean,
    onWeightChanged: (String) -> Unit,
    onRepsChanged: (String) -> Unit,
    onRecord: () -> Unit,
    onDelete: () -> Unit
) {
    var isExpanded by rememberSaveable(set.id) { mutableStateOf(false) }
    val number = set.orderIndex + 1
    val summary = rememberSetSummary(set.weightInput, set.repsInput)
    EditableSetRow(
        number = number,
        summary = summary,
        rowDescription = stringResource(R.string.active_workout_set_upcoming_cd, number, summary),
        editHint = stringResource(R.string.active_workout_set_upcoming_hint),
        deleteLabel = stringResource(R.string.active_workout_delete_set),
        expanded = isExpanded,
        onExpandedChange = { isExpanded = it },
        canDelete = canDelete,
        onDelete = onDelete,
        trailing = {
            UpcomingLogButton(
                enabled = canLog,
                isRecording = isRecording,
                description = stringResource(R.string.active_workout_log_set_cd, number),
                onClick = onRecord
            )
        }
    ) {
        SetPendingEditor(
            number = number,
            weightInput = set.weightInput,
            repsInput = set.repsInput,
            enabled = editorsEnabled,
            onWeightChanged = onWeightChanged,
            onRepsChanged = onRepsChanged
        )
    }
}

/** Compact "Log" pill on a pending row: logs this set now, in any order. */
@Composable
private fun UpcomingLogButton(
    enabled: Boolean,
    isRecording: Boolean,
    description: String,
    onClick: () -> Unit
) {
    val primary = MaterialTheme.colorScheme.primary
    val contentColor = if (enabled) primary else primary.copy(alpha = 0.38f)
    Box(
        modifier = Modifier
            .heightIn(min = 44.dp)
            .clip(CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = description }
            .padding(horizontal = 4.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center
    ) {
        Row(
            modifier = Modifier
                .background(primary.copy(alpha = if (enabled) 0.12f else 0.06f), CircleShape)
                .padding(horizontal = 14.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (isRecording) {
                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
            }
            Text(
                text = stringResource(R.string.action_log_set),
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                color = contentColor,
                maxLines = 1,
                modifier = Modifier.clearAndSetSemantics {}
            )
        }
    }
}

internal fun activeWorkoutCompletedSetTag(setId: String): String = "active_workout_completed_set_$setId"

/**
 * A recorded set: one line — check, "60 kg × 8", optional record badge, and (latest set, only
 * while its rest timer runs) a trailing compact countdown with −15 / +15 / stop pills that wraps
 * under the summary when it does not fit. Undo is a long-press menu / accessibility action, never
 * a standing button.
 */
@Composable
private fun CompletedSetRow(
    set: ActiveWorkoutSetUiState,
    operationInProgress: Boolean,
    isLatestCompleted: Boolean,
    restSecondsRemaining: Int,
    onUndo: () -> Unit,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit
) {
    val number = set.orderIndex + 1
    val summary = rememberSetSummary(set.weightInput, set.repsInput)
    val description = stringResource(
        if (set.isPersonalRecord) {
            R.string.active_workout_set_recorded_record_cd
        } else {
            R.string.active_workout_set_recorded_cd
        },
        number,
        summary
    )
    val canUndo = isLatestCompleted && !operationInProgress
    val showsRest = isLatestCompleted && restSecondsRemaining > 0
    RecordedSetRow(
        summary = summary,
        description = description,
        isPersonalRecord = set.isPersonalRecord,
        modifier = Modifier.testTag(activeWorkoutCompletedSetTag(set.id)),
        longPressActionLabel = stringResource(R.string.active_workout_undo_action).takeIf { canUndo },
        onLongPressAction = onUndo.takeIf { canUndo },
        trailing = if (showsRest) {
            {
                CompactRestControls(
                    remainingSeconds = restSecondsRemaining,
                    enabled = !operationInProgress,
                    onAdjustRestTimer = onAdjustRestTimer,
                    onStopRestTimer = onStopRestTimer
                )
            }
        } else {
            null
        }
    )
}

/** Monospaced countdown + "−15" / "+15" / stop pills (~32dp visual, 44dp targets). */
@Composable
private fun CompactRestControls(
    remainingSeconds: Int,
    enabled: Boolean,
    onAdjustRestTimer: (Int) -> Unit,
    onStopRestTimer: () -> Unit
) {
    val clock = formatRestTime(remainingSeconds)
    val timerDescription = stringResource(R.string.active_workout_rest_timer_cd)
    val decreaseDescription = stringResource(R.string.active_workout_rest_subtract)
    val increaseDescription = stringResource(R.string.active_workout_rest_add)
    val stopDescription = stringResource(R.string.active_workout_rest_stop)
    val pillTextStyle = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold)
    Row(
        modifier = Modifier.semantics {
            isTraversalGroup = true
            contentDescription = timerDescription
            stateDescription = clock
        },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Text(
            text = clock,
            style = MaterialTheme.typography.labelLarge.copy(
                fontWeight = FontWeight.SemiBold
            ).tabularDigits(),
            color = MaterialTheme.colorScheme.primary,
            maxLines = 1,
            softWrap = false,
            modifier = Modifier.clearAndSetSemantics {}
        )
        RestPillButton(enabled, decreaseDescription, { onAdjustRestTimer(-15) }) { tint ->
            Text("−15", style = pillTextStyle, color = tint, maxLines = 1, softWrap = false)
        }
        RestPillButton(enabled, increaseDescription, { onAdjustRestTimer(15) }) { tint ->
            Text("+15", style = pillTextStyle, color = tint, maxLines = 1, softWrap = false)
        }
        RestPillButton(enabled, stopDescription, onStopRestTimer) { tint ->
            Icon(
                imageVector = Icons.Default.Stop,
                contentDescription = null,
                tint = tint,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

/** A ~32dp hairline-outlined capsule inside a full 44dp tap target. */
@Composable
private fun RestPillButton(
    enabled: Boolean,
    description: String,
    onClick: () -> Unit,
    content: @Composable (tint: Color) -> Unit
) {
    val tint = MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 1f else 0.38f)
    Box(
        modifier = Modifier
            .defaultMinSize(minWidth = 44.dp, minHeight = 44.dp)
            .clip(RoundedCornerShape(22.dp))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .height(32.dp)
                .background(MaterialTheme.colorScheme.surface, CircleShape)
                .border(Dp.Hairline, MaterialTheme.colorScheme.outlineVariant, CircleShape)
                .padding(horizontal = 10.dp),
            contentAlignment = Alignment.Center
        ) {
            content(tint)
        }
    }
}

internal const val ACTIVE_WORKOUT_RECORDED_BANNER_TAG = "active_workout_recorded_banner"

/**
 * "Recorded: 40 kg × 10" with a trailing "Undo" (that exact set) and a dismiss button. The message
 * is a polite live region whose spoken text carries the fuller announcement (rest duration).
 */
@Composable
private fun RecordedConfirmationBanner(
    confirmation: RecordedConfirmation,
    undoEnabled: Boolean,
    onUndo: () -> Unit,
    onDismiss: () -> Unit
) {
    val dismissDescription = stringResource(R.string.action_dismiss)
    val primary = MaterialTheme.colorScheme.primary
    Surface(
        shape = GymControlShape,
        color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, primary.copy(alpha = 0.36f)),
        modifier = Modifier
            .fillMaxWidth()
            .testTag(ACTIVE_WORKOUT_RECORDED_BANNER_TAG)
    ) {
        Row(
            modifier = Modifier.padding(start = 12.dp, top = 2.dp, bottom = 2.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                tint = primary
            )
            Text(
                text = confirmation.message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f)
                    .semantics {
                        contentDescription = confirmation.announcement
                        liveRegion = LiveRegionMode.Polite
                    }
            )
            TextButton(onClick = onUndo, enabled = undoEnabled) {
                Text(
                    text = stringResource(R.string.voice_command_undo),
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold)
                )
            }
            IconButton(onClick = onDismiss) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = dismissDescription,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

/**
 * The current set: brand-tinted card with "Set N" + plate calculator + tappable "previous"
 * caption, one centered value line, two step capsules, then the mic + Log action row (or the
 * listening/typed voice states, see [rememberSetVoiceCommand]).
 */
@Composable
private fun CurrentSetCard(
    set: ActiveWorkoutSetUiState,
    operationInProgress: Boolean,
    validSetInput: Boolean,
    isRecording: Boolean,
    showsPlateCalculator: Boolean,
    isBodyweight: Boolean,
    restDurationSeconds: Int,
    isRestActive: Boolean,
    onWeightChanged: (String) -> Unit,
    onRepsChanged: (String) -> Unit,
    onRecord: () -> Unit,
    onRecorded: (weightText: String, repsText: String) -> Unit,
    onVoiceStarted: () -> Unit,
    onStopRestTimer: () -> Unit,
    onVoiceCommandFeedback: (String, String?, (() -> Unit)?) -> Unit,
    canDelete: Boolean = false,
    onDelete: () -> Unit = {}
) {
    var deleteMenuOpen by remember { mutableStateOf(false) }
    val deleteHaptics = LocalHapticFeedback.current
    val deleteLabel = stringResource(R.string.active_workout_delete_set)
    val voice = rememberSetVoiceCommand(
        set = set,
        enabled = !operationInProgress,
        isRestActive = isRestActive,
        onWeightChanged = onWeightChanged,
        onRepsChanged = onRepsChanged,
        onRecord = onRecord,
        onRecorded = onRecorded,
        onVoiceStarted = onVoiceStarted,
        onStopRestTimer = onStopRestTimer,
        onFeedback = onVoiceCommandFeedback
    )
    val format = rememberDecimalFormat()
    val caption = previousCaption(set.previousWeight, set.previousReps, isBodyweight)
    val repeatWeight = set.repeatWeight
    val repeatReps = set.repeatReps
    val currentSetState = stringResource(R.string.active_workout_current_set_state)
    val editorsEnabled = !operationInProgress
    Box {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .background(
                MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
                RoundedCornerShape(16.dp)
            )
            .pointerInput(canDelete) {
                // Long-press on an empty part of the card; its buttons and fields consume their own presses.
                if (canDelete) {
                    detectTapGestures(onLongPress = {
                        deleteHaptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        deleteMenuOpen = true
                    })
                }
            }
            .padding(10.dp)
            .semantics {
                selected = true
                stateDescription = currentSetState
                if (canDelete) {
                    customActions = listOf(
                        CustomAccessibilityAction(deleteLabel) {
                            deleteMenuOpen = false
                            onDelete()
                            true
                        }
                    )
                }
            },
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.label_set, set.orderIndex + 1),
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.primary
            )
            if (showsPlateCalculator) {
                PlateCalculatorButton(
                    weight = com.example.gymapp.util.parseWeightInputOrNull(set.weightInput)
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            if (caption != null && repeatWeight != null && repeatReps != null) {
                val captionText = if (caption.showsWeight) {
                    stringResource(
                        R.string.active_workout_previous_caption,
                        format.format(caption.weight),
                        caption.reps
                    )
                } else {
                    stringResource(R.string.active_workout_previous_caption_bodyweight, caption.reps)
                }
                val captionDescription = if (caption.showsWeight) {
                    stringResource(
                        R.string.active_workout_previous_cd,
                        format.format(caption.weight),
                        caption.reps
                    )
                } else {
                    pluralStringResource(
                        R.plurals.active_workout_previous_bodyweight_cd,
                        caption.reps,
                        caption.reps
                    )
                }
                val captionHint = stringResource(R.string.active_workout_previous_hint)
                Text(
                    text = captionText,
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    modifier = Modifier
                        .heightIn(min = 44.dp)
                        .clickable(
                            enabled = editorsEnabled,
                            onClickLabel = captionHint,
                            role = Role.Button,
                            onClick = {
                                onWeightChanged(VoiceWorkoutDraftParser.formatWeight(repeatWeight))
                                onRepsChanged(repeatReps.toString())
                            }
                        )
                        .wrapContentHeight(Alignment.CenterVertically)
                        .clearAndSetSemantics { contentDescription = captionDescription }
                )
            }
        }
        if (voice.phase == VoicePhase.Listening) {
            VoiceListeningValueLine(transcript = voice.partial)
        } else {
            SetValueLine(
                number = set.orderIndex + 1,
                weightInput = set.weightInput,
                repsInput = set.repsInput,
                enabled = editorsEnabled,
                onWeightChanged = onWeightChanged
            )
            SetStepCapsules(
                weightInput = set.weightInput,
                repsInput = set.repsInput,
                allowedWeights = set.allowedWeights,
                enabled = editorsEnabled,
                format = format,
                onWeightChanged = onWeightChanged,
                onRepsChanged = onRepsChanged
            )
        }
        when (voice.phase) {
            VoicePhase.Typed -> VoiceTypedActionRow(voice)
            VoicePhase.Listening -> VoiceListeningActionRow(voice)
            else -> Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                VoiceMicButton(enabled = editorsEnabled, onClick = voice.onMic)
                SetLogButton(
                    enabled = validSetInput && !operationInProgress,
                    isRecording = isRecording,
                    restDurationSeconds = restDurationSeconds,
                    onClick = {
                        onRecord()
                        onRecorded(set.weightInput.ifBlank { "0" }, set.repsInput.ifBlank { "0" })
                    },
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
    DropdownMenu(expanded = deleteMenuOpen && canDelete, onDismissRequest = { deleteMenuOpen = false }) {
        DropdownMenuItem(
            text = { Text(deleteLabel, color = MaterialTheme.colorScheme.error) },
            onClick = {
                deleteMenuOpen = false
                onDelete()
            }
        )
    }
    }
}

/** "Log" plus, when a rest applies, a lighter " · 3:00"; always one line. */
@Composable
private fun SetLogButton(
    enabled: Boolean,
    isRecording: Boolean,
    restDurationSeconds: Int,
    onClick: () -> Unit,
    modifier: Modifier
) {
    val label = stringResource(R.string.action_log_set)
    val rest = restClockLabel(restDurationSeconds)
    val description = if (rest != null) {
        stringResource(R.string.action_log_set_and_rest, rest)
    } else {
        label
    }
    val suffixStyle = SpanStyle(
        fontSize = MaterialTheme.typography.bodyMedium.fontSize,
        fontWeight = FontWeight.Normal,
        color = Color.White.copy(alpha = 0.75f)
    )
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.heightIn(min = 48.dp)
    ) {
        if (isRecording) {
            CircularProgressIndicator(
                modifier = Modifier.padding(end = 8.dp).size(18.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary
            )
        }
        Text(
            text = buildAnnotatedString {
                append(label)
                if (rest != null) withStyle(suffixStyle) { append(" · $rest") }
            },
            style = MaterialTheme.typography.titleMedium,
            maxLines = 1,
            overflow = TextOverflow.Clip,
            modifier = Modifier.clearAndSetSemantics { contentDescription = description }
        )
    }
}

/** Compact "Блины" capsule in the current set's header, like iOS; opens the per-side plates. */
@Composable
private fun PlateCalculatorButton(weight: Double?) {
    var showsPlates by remember { mutableStateOf(false) }
    val locale = LocalConfiguration.current.locales[0]
    val numberFormat = remember(locale) {
        NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 2 }
    }
    val description = stringResource(R.string.plate_calculator_content_description)
    Box {
        Surface(
            onClick = { showsPlates = true },
            enabled = weight != null,
            shape = RoundedCornerShape(percent = 50),
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
            contentColor = MaterialTheme.colorScheme.primary,
            modifier = Modifier.semantics { contentDescription = description }
        ) {
            Text(
                text = stringResource(R.string.plate_calculator_button),
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
            )
        }
        DropdownMenu(expanded = showsPlates && weight != null, onDismissRequest = { showsPlates = false }) {
            if (weight != null) {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = stringResource(R.string.plate_calculator_total, numberFormat.format(weight)),
                        style = MaterialTheme.typography.titleSmall
                    )
                    plateSummaryLines(PlateCalculator.load(weight)) { value -> numberFormat.format(value) }
                        .forEach { line -> Text(text = line, style = MaterialTheme.typography.bodyMedium) }
                }
            }
        }
    }
}

@Composable
private fun plateSummaryLines(load: PlateLoad, format: (Double) -> String): List<String> {
    val bar = format(PlateCalculator.BAR_WEIGHT)
    return when (load.status) {
        PlateLoad.Status.BelowBar -> listOf(stringResource(R.string.plate_calculator_below_bar, bar))
        PlateLoad.Status.BarOnly -> listOf(stringResource(R.string.plate_calculator_bar_only, bar))
        PlateLoad.Status.Loaded -> buildList {
            if (load.platesPerSide.isNotEmpty()) {
                add(
                    stringResource(
                        R.string.plate_calculator_per_side,
                        load.platesPerSide.joinToString(separator = " + ", transform = format)
                    )
                )
            }
            if (load.remainderPerSide > 0.0) {
                add(stringResource(R.string.plate_calculator_remainder, format(load.remainderPerSide)))
            }
        }
    }
}

/** "Саша: 85 × 8 · 3 дня назад"; a bodyweight result reads "Саша: 12 повторений · вчера". */
@Composable
private fun friendGhostLine(ghost: FriendGhost): String {
    val locale = LocalConfiguration.current.locales[0]
    val numberFormat = remember(locale) {
        NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = 2 }
    }
    val result = if (ghost.weightKg > 0.0) {
        stringResource(R.string.friend_ghost_weight_reps, numberFormat.format(ghost.weightKg), ghost.reps)
    } else {
        pluralStringResource(R.plurals.friend_ghost_reps, ghost.reps, ghost.reps)
    }
    val days = FriendGhosts.daysAgo(ghost.workoutDay, java.time.LocalDate.now())
    val day = when (days) {
        0 -> stringResource(R.string.friend_ghost_today)
        1 -> stringResource(R.string.friend_ghost_yesterday)
        else -> pluralStringResource(R.plurals.friend_ghost_days_ago, days, days)
    }
    return stringResource(R.string.friend_ghost_line, ghost.friendName, result, day)
}

private fun formatRestTime(totalSeconds: Int): String = String.format(
    Locale.getDefault(),
    "%d:%02d",
    totalSeconds.coerceAtLeast(0) / 60,
    totalSeconds.coerceAtLeast(0) % 60
)

private enum class VoicePhase { Idle, Requesting, Listening, Typed }

/** Phase + text for one current set's voice row; the lambdas are refreshed on every recomposition. */
@Stable
private class SetVoiceCommand {
    var phase by mutableStateOf(VoicePhase.Idle)
    var partial by mutableStateOf("")
    var typed by mutableStateOf("")
    var onMic: () -> Unit = {}
    var onStop: () -> Unit = {}
    var onTypeInstead: () -> Unit = {}
    var onCancel: () -> Unit = {}
    var onSubmit: () -> Unit = {}
}

/**
 * In-workout voice command state machine for the current set (shared/voice-workout-command-v1.json):
 * Idle -> (Requesting) -> Listening, or Idle/Listening -> Typed. On-device recognition only
 * (reuses [OnDeviceVoiceTranscriber], the wrapper [VoiceWorkoutDraftSheet] uses); when it is
 * unavailable or the microphone permission is denied the row goes straight to typed entry, never
 * to a cloud recognizer. Recognized commands are routed through exactly the same
 * [onRecord]/[onUndo]/[onStopRestTimer] actions the visible buttons use, so live-room freeze and
 * commit locks apply identically. No audio or transcript is persisted or logged. State is keyed
 * to the set id, so it resets (and recognition stops) when another set becomes current.
 */
@Composable
private fun rememberSetVoiceCommand(
    set: ActiveWorkoutSetUiState,
    enabled: Boolean,
    isRestActive: Boolean,
    onWeightChanged: (String) -> Unit,
    onRepsChanged: (String) -> Unit,
    onRecord: () -> Unit,
    onRecorded: (weightText: String, repsText: String) -> Unit,
    onVoiceStarted: () -> Unit,
    onStopRestTimer: () -> Unit,
    onFeedback: (message: String, actionLabel: String?, onAction: (() -> Unit)?) -> Unit
): SetVoiceCommand {
    val context = LocalContext.current
    val languageTag = currentAppLanguageTag()
    val ui = remember(set.id) { SetVoiceCommand() }
    val unavailable = remember { voiceTranscriptionAvailability(context) }

    fun handleHeard(heard: String) {
        if (heard.isBlank()) {
            onFeedback(context.getString(R.string.voice_command_no_speech), null, null)
            return
        }
        when (val command = VoiceWorkoutCommandParser.parse(heard, languageTag)) {
            is VoiceWorkoutCommand.LogSet -> {
                if (!enabled) {
                    onFeedback(context.getString(R.string.voice_command_busy), null, null)
                    return
                }
                val weightText = command.weightKg?.let(VoiceWorkoutDraftParser::formatWeight) ?: set.weightInput
                val repsText = command.reps?.toString() ?: set.repsInput
                val parsed = parseActiveWorkoutSetInput(weightText, repsText)
                if (parsed == null) {
                    onFeedback(context.getString(R.string.voice_command_missing_values), null, null)
                    return
                }
                onWeightChanged(weightText)
                onRepsChanged(repsText)
                onRecord()
                onRecorded(weightText.ifBlank { "0" }, repsText.ifBlank { "0" })
            }
            VoiceWorkoutCommand.RepeatPrevious -> {
                val weight = set.repeatWeight
                val reps = set.repeatReps
                if (weight == null || reps == null) {
                    onFeedback(context.getString(R.string.voice_command_no_previous_set), null, null)
                    return
                }
                if (!enabled) {
                    onFeedback(context.getString(R.string.voice_command_busy), null, null)
                    return
                }
                // Same text the "previous" caption fills in, so no "60.0".
                val weightText = VoiceWorkoutDraftParser.formatWeight(weight)
                val repsText = reps.toString()
                onWeightChanged(weightText)
                onRepsChanged(repsText)
                onRecord()
                onRecorded(weightText.ifBlank { "0" }, repsText)
            }
            VoiceWorkoutCommand.SkipRest -> {
                if (!isRestActive) {
                    onFeedback(context.getString(R.string.voice_command_not_resting), null, null)
                    return
                }
                onStopRestTimer()
            }
            is VoiceWorkoutCommand.Unknown -> {
                // Shows what was heard and records nothing.
                onFeedback(context.getString(R.string.voice_command_unknown, command.transcript), null, null)
            }
        }
    }

    val handler by rememberUpdatedState<(String) -> Unit>({ heard -> handleHeard(heard) })

    val transcriber = remember(set.id) {
        OnDeviceVoiceTranscriber(
            context = context.applicationContext,
            onPartial = { ui.partial = it },
            onFinished = { error ->
                if (ui.phase == VoicePhase.Listening) {
                    val heard = ui.partial
                    ui.partial = ""
                    when (error) {
                        VoiceTranscriptionError.Unavailable,
                        VoiceTranscriptionError.UnsupportedLanguage,
                        VoiceTranscriptionError.PermissionDenied,
                        VoiceTranscriptionError.AudioFailure -> {
                            ui.typed = ""
                            ui.phase = VoicePhase.Typed
                        }
                        else -> {
                            ui.phase = VoicePhase.Idle
                            handler(if (error == null) heard else "")
                        }
                    }
                }
            }
        )
    }
    DisposableEffect(transcriber) { onDispose { transcriber.stop() } }

    // Leaving the foreground cancels an in-progress recognition without acting on it, like the
    // iPhone client cancelling when the scene goes inactive.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, transcriber, ui) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && ui.phase == VoicePhase.Listening) {
                transcriber.stop()
                ui.partial = ""
                ui.phase = VoicePhase.Idle
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // Tapping stop (or hitting the auto-stop cap) processes whatever partial transcript was heard
    // so far: SpeechRecognizer.cancel() (used by transcriber.stop()) never delivers onResults, so
    // this is the only path that acts on it in those cases.
    fun stopAndProcess() {
        val heard = ui.partial
        transcriber.stop()
        ui.partial = ""
        ui.phase = VoicePhase.Idle
        handler(heard)
    }
    LaunchedEffect(ui, ui.phase) {
        if (ui.phase == VoicePhase.Listening) {
            delay(VoiceWorkoutDraftParser.AUTO_STOP_SECONDS * 1_000L)
            if (ui.phase == VoicePhase.Listening) stopAndProcess()
        }
    }

    fun beginListening() {
        ui.partial = ""
        ui.phase = VoicePhase.Listening
        transcriber.start(languageTag)
    }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (ui.phase == VoicePhase.Requesting) {
            if (granted) {
                beginListening()
            } else {
                ui.typed = ""
                ui.phase = VoicePhase.Typed
            }
        }
    }

    ui.onMic = {
        when {
            // Tapping again while the permission prompt is pending cancels the attempt.
            ui.phase == VoicePhase.Requesting -> ui.phase = VoicePhase.Idle
            !enabled -> Unit
            unavailable != null -> {
                onVoiceStarted()
                ui.typed = ""
                ui.phase = VoicePhase.Typed
            }
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED -> {
                onVoiceStarted()
                beginListening()
            }
            else -> {
                onVoiceStarted()
                ui.phase = VoicePhase.Requesting
                permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
        }
    }
    ui.onStop = { stopAndProcess() }
    ui.onTypeInstead = {
        transcriber.stop()
        ui.partial = ""
        ui.typed = ""
        ui.phase = VoicePhase.Typed
    }
    ui.onCancel = {
        transcriber.stop()
        ui.partial = ""
        ui.typed = ""
        ui.phase = VoicePhase.Idle
    }
    ui.onSubmit = {
        val text = ui.typed.trim()
        ui.typed = ""
        ui.phase = VoicePhase.Idle
        if (text.isNotEmpty()) handler(text)
    }
    return ui
}

private val VoiceButtonShape = RoundedCornerShape(12.dp)

@Composable
private fun VoiceMicButton(enabled: Boolean, onClick: () -> Unit) {
    val description = stringResource(R.string.voice_command_mic_description)
    val hint = stringResource(R.string.voice_command_mic_hint)
    Box(
        modifier = Modifier
            .size(48.dp)
            .background(MaterialTheme.colorScheme.surface, VoiceButtonShape)
            .clip(VoiceButtonShape)
            .clickable(enabled = enabled, onClickLabel = hint, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Default.Mic,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary.copy(alpha = if (enabled) 1f else 0.38f)
        )
    }
}

/** Listening value line: live partial transcript (large, quoted) plus the phrase hint. */
@Composable
private fun VoiceListeningValueLine(transcript: String) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(
            text = if (transcript.isBlank()) {
                stringResource(R.string.voice_command_listening)
            } else {
                "«$transcript»"
            },
            style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { liveRegion = LiveRegionMode.Polite }
        )
        Text(
            text = stringResource(R.string.voice_command_hint),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

/** Filled stop button + capsule ("Listening…" with a trailing "Type instead" escape hatch). */
@Composable
private fun VoiceListeningActionRow(voice: SetVoiceCommand) {
    val stopDescription = stringResource(R.string.voice_command_stop_description)
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .background(MaterialTheme.colorScheme.primary, VoiceButtonShape)
                .clip(VoiceButtonShape)
                .clickable(role = Role.Button, onClick = voice.onStop)
                .semantics { contentDescription = stopDescription },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Stop,
                contentDescription = null,
                tint = Color.White
            )
        }
        Row(
            modifier = Modifier
                .weight(1f)
                .heightIn(min = 48.dp)
                .background(MaterialTheme.colorScheme.surface, CircleShape)
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = Icons.Default.GraphicEq,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary
            )
            Text(
                text = stringResource(R.string.voice_command_listening),
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = stringResource(R.string.voice_command_type_instead),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.primary,
                maxLines = 1,
                modifier = Modifier
                    .heightIn(min = 44.dp)
                    .clickable(role = Role.Button, onClick = voice.onTypeInstead)
                    .wrapContentHeight(Alignment.CenterVertically)
            )
        }
    }
}

/** Cancel button + text field with a 36dp send control inside its trailing edge. */
@Composable
private fun VoiceTypedActionRow(voice: SetVoiceCommand) {
    val cancelDescription = stringResource(R.string.action_cancel)
    val fieldLabel = stringResource(R.string.voice_command_typed_label)
    val sendDescription = stringResource(R.string.voice_command_send_description)
    val isEmpty = voice.typed.isBlank()
    val focusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focusRequester.requestFocus() } }
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .background(MaterialTheme.colorScheme.surface, VoiceButtonShape)
                .clip(VoiceButtonShape)
                .clickable(role = Role.Button, onClick = voice.onCancel)
                .semantics { contentDescription = cancelDescription },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Default.Close,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Box(
            modifier = Modifier
                .weight(1f)
                .heightIn(min = 48.dp)
                .background(MaterialTheme.colorScheme.surface, VoiceButtonShape),
            contentAlignment = Alignment.CenterStart
        ) {
            BasicTextField(
                value = voice.typed,
                onValueChange = { voice.typed = it },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { voice.onSubmit() }),
                modifier = Modifier
                    .fillMaxWidth()
                    .focusRequester(focusRequester)
                    .padding(start = 14.dp, end = 44.dp)
                    .semantics { contentDescription = fieldLabel },
                decorationBox = { innerTextField ->
                    Box(contentAlignment = Alignment.CenterStart) {
                        if (voice.typed.isEmpty()) {
                            Text(
                                text = stringResource(R.string.voice_command_typed_placeholder),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                            )
                        }
                        innerTextField()
                    }
                }
            )
            Box(
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 6.dp)
                    .size(36.dp)
                    .background(
                        MaterialTheme.colorScheme.primary.copy(alpha = if (isEmpty) 0.4f else 1f),
                        RoundedCornerShape(10.dp)
                    )
                    .clip(RoundedCornerShape(10.dp))
                    .clickable(enabled = !isEmpty, role = Role.Button, onClick = voice.onSubmit)
                    .semantics { contentDescription = sendDescription },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.ArrowUpward,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(18.dp)
                )
            }
        }
    }
}

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
