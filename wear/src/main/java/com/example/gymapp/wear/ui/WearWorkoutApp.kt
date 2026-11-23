package com.example.gymapp.wear.ui

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.AlertDialog
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.CircularProgressIndicator
import androidx.wear.compose.material3.CompactButton
import androidx.wear.compose.material3.EdgeButton
import androidx.wear.compose.material3.EdgeButtonSize
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.PickerGroup
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SuccessConfirmationDialog
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.TextButton
import androidx.wear.compose.material3.TextButtonDefaults
import androidx.wear.compose.material3.curvedText
import androidx.wear.compose.material3.rememberPickerState
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.currentBackStackEntryAsState
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import com.example.gymapp.wear.R
import com.example.gymapp.wear.health.WearHealthStatus
import java.text.Collator
import java.util.Locale
import kotlinx.coroutines.delay

private object Routes {
    const val START = "start"
    const val DASHBOARD = "dashboard"
    const val PAUSE = "pause"
    const val SET_ENTRY = "setEntry"
    const val PICKER = "picker"
    const val SUMMARY = "summary"
    const val RESULT = "result"
}

private const val SENDING_TIMEOUT_MS = 15_000L
private const val SAVED_DIALOG_MS = 2_000L

@Composable
fun WearWorkoutApp(viewModel: WearWorkoutViewModel, isAmbient: Boolean) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val nav = rememberSwipeDismissableNavController()
    val view = LocalView.current
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route

    // Pause menu and summary freeze the clocks; workout screens run them (spec §3).
    LaunchedEffect(route, state.workoutActive) {
        if (!state.workoutActive) return@LaunchedEffect
        when (route) {
            Routes.PAUSE, Routes.SUMMARY -> if (!state.paused) {
                viewModel.pauseWorkout()
                view.haptic(HapticFeedbackConstants.CONTEXT_CLICK)
            }
            Routes.DASHBOARD, Routes.SET_ENTRY, Routes.PICKER -> if (state.paused) {
                viewModel.resumeWorkout()
                view.haptic(HapticFeedbackConstants.CONFIRM)
            }
        }
    }

    // An active workout survives leaving the app: reopen on the dashboard.
    var restoredActive by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.workoutActive) {
        if (state.workoutActive && !restoredActive && route == Routes.START) {
            restoredActive = true
            nav.goToDashboard()
        }
    }

    GymWatchTheme {
        AppScaffold {
            SwipeDismissableNavHost(navController = nav, startDestination = Routes.START) {
                composable(Routes.START) {
                    StartScreen(
                        state = state,
                        onStart = { usePlan ->
                            restoredActive = true
                            viewModel.startWorkout(usePlan)
                            view.haptic(HapticFeedbackConstants.CONFIRM)
                            nav.goToDashboard()
                        },
                        onCycleStep = viewModel::cycleWeightStep,
                        onRetry = {
                            viewModel.retryQueuedWorkout()
                            nav.goToRoot(Routes.RESULT)
                        },
                        onDiscardQueued = {
                            viewModel.discardWorkout()
                            view.haptic(HapticFeedbackConstants.REJECT)
                        }
                    )
                }
                composable(Routes.PAUSE) {
                    PauseScreen(
                        state = state,
                        onResume = { nav.navigate(Routes.DASHBOARD) },
                        onFinish = { nav.navigate(Routes.SUMMARY) },
                        onDiscarded = {
                            viewModel.discardWorkout()
                            view.haptic(HapticFeedbackConstants.REJECT)
                            nav.goToRoot(Routes.START)
                        }
                    )
                }
                composable(Routes.DASHBOARD) {
                    DashboardScreen(
                        state = state,
                        isAmbient = isAmbient,
                        onLogSet = {
                            viewModel.endUndoWindow()
                            nav.navigate(Routes.SET_ENTRY)
                            // Nothing chosen yet (free workout): the first tap picks the exercise
                            // and comes back to the set entry (spec §3).
                            if (state.currentExercise == null) nav.navigate(Routes.PICKER)
                        },
                        onUndo = {
                            if (viewModel.undoLastSet()) view.haptic(HapticFeedbackConstants.REJECT)
                        },
                        onAddRest = {
                            viewModel.endUndoWindow()
                            viewModel.addRestSeconds()
                        },
                        onSkipRest = {
                            viewModel.endUndoWindow()
                            viewModel.skipRest()
                        }
                    )
                }
                composable(Routes.SET_ENTRY) {
                    SetEntryScreen(
                        state = state,
                        onPickExercise = { nav.navigate(Routes.PICKER) },
                        onSave = { exercise, weight, reps ->
                            if (viewModel.logSet(exercise, weight, reps)) {
                                view.haptic(HapticFeedbackConstants.CONFIRM)
                                nav.popBackStack(Routes.DASHBOARD, inclusive = false)
                            }
                        }
                    )
                }
                composable(Routes.PICKER) {
                    ExercisePickerScreen(
                        state = state,
                        onSelect = { name ->
                            viewModel.selectExercise(name)
                            nav.popBackStack()
                        }
                    )
                }
                composable(Routes.SUMMARY) {
                    SummaryScreen(
                        state = state,
                        onSave = {
                            viewModel.saveWorkout()
                            nav.goToRoot(Routes.RESULT)
                        },
                        onDiscarded = {
                            viewModel.discardWorkout()
                            view.haptic(HapticFeedbackConstants.REJECT)
                            nav.goToRoot(Routes.START)
                        }
                    )
                }
                composable(Routes.RESULT) {
                    ResultScreen(
                        state = state,
                        onSavedHaptic = { view.haptic(HapticFeedbackConstants.CONFIRM) },
                        onClose = {
                            viewModel.acknowledgeSaveOutcome()
                            restoredActive = false
                            nav.goToRoot(Routes.START)
                        }
                    )
                }
            }
        }
    }
}

/** Pause sits under the dashboard, so a back-swipe from the dashboard reveals it (spec §3). */
private fun NavHostController.goToDashboard() {
    navigate(Routes.PAUSE) { popUpTo(graph.id) { inclusive = true } }
    navigate(Routes.DASHBOARD)
}

private fun NavHostController.goToRoot(route: String) {
    navigate(route) { popUpTo(graph.id) { inclusive = true } }
}

/** Edge button label: up to 2 centred lines so UK/RU labels are never cut. */
@Composable
private fun EdgeLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        textAlign = TextAlign.Center,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis
    )
}

/** Medium leaves room for the longer UK/RU labels ("Записати підхід") on 225dp+ screens. */
private fun edgeSize(large: Boolean): EdgeButtonSize =
    if (large) EdgeButtonSize.Medium else EdgeButtonSize.Small

private fun View.haptic(constant: Int) {
    performHapticFeedback(constant)
}

@Composable
private fun isLargeScreen(): Boolean = LocalConfiguration.current.screenWidthDp >= 225

@Composable
private fun showNextLine(): Boolean = LocalConfiguration.current.screenHeightDp >= 240

@Composable
private fun locale(): Locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()

// ---------------------------------------------------------------- Start

@Composable
private fun StartScreen(
    state: WearWorkoutUiState,
    onStart: (usePlan: Boolean) -> Unit,
    onCycleStep: () -> Unit,
    onRetry: () -> Unit,
    onDiscardQueued: () -> Unit
) {
    val listState = rememberScalingLazyListState()
    val hasPlan = state.planTargets.isNotEmpty()
    val queued = state.hasQueuedWorkout
    val canStart = state.isLinked && !queued && !state.isSaving
    var confirmDiscard by remember { mutableStateOf(false) }
    val status = when {
        queued && state.isSaving -> stringResource(R.string.sending)
        !state.isLinked -> stringResource(R.string.open_phone)
        // The queued block below says why starting is blocked and what to do about it.
        queued -> stringResource(R.string.send_later)
        !hasPlan -> stringResource(R.string.open_phone)
        state.syncStatus == WearSyncStatus.Failed -> stringResource(R.string.phone_off)
        else -> null
    }
    val loc = locale()
    ScreenScaffold(scrollState = listState) { padding ->
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            contentPadding = padding
        ) {
            item {
                ListHeader(modifier = Modifier.semantics { heading() }) {
                    Text(stringResource(R.string.start_title))
                }
            }
            if (hasPlan && canStart) {
                item {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = state.planTargets.first().exerciseName,
                            style = MaterialTheme.typography.titleMedium.withHyphens(),
                            textAlign = TextAlign.Center,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = stringResource(R.string.sets_count, state.planTargets.size),
                            style = MaterialTheme.typography.labelSmall,
                            color = WatchColors.TextSecondary
                        )
                    }
                }
                item {
                    Button(
                        onClick = { onStart(true) },
                        modifier = Modifier.fillMaxWidth(),
                        icon = { Icon(WatchIcons.Play, contentDescription = null) },
                        label = { Text(stringResource(R.string.start_plan), maxLines = 2) }
                    )
                }
            }
            if (canStart) {
                item {
                    val label: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {
                        Text(stringResource(R.string.free_workout), maxLines = 2)
                    }
                    if (hasPlan) {
                        FilledTonalButton(onClick = { onStart(false) }, modifier = Modifier.fillMaxWidth(), label = label)
                    } else {
                        Button(onClick = { onStart(false) }, modifier = Modifier.fillMaxWidth(), label = label)
                    }
                }
            }
            if (queued) {
                // State D: one finished workout is waiting for the phone. Starting another is
                // blocked until this one is sent or knowingly discarded, so neither can be lost.
                item {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = stringResource(R.string.queued_title),
                            style = MaterialTheme.typography.titleMedium,
                            textAlign = TextAlign.Center,
                            maxLines = 2
                        )
                        Text(
                            text = stringResource(R.string.sets_count, state.loggedSets.size),
                            style = MaterialTheme.typography.labelSmall.tabular(),
                            color = WatchColors.TextSecondary
                        )
                        Text(
                            text = stringResource(R.string.queued_body),
                            style = MaterialTheme.typography.labelSmall,
                            color = WatchColors.TextSecondary,
                            textAlign = TextAlign.Center,
                            maxLines = 4
                        )
                    }
                }
                if (state.isLinked && !state.isSaving) {
                    item {
                        Button(
                            onClick = onRetry,
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(stringResource(R.string.send_now), maxLines = 2) }
                        )
                    }
                }
                if (!state.isSaving) {
                    item { DiscardButton(onClick = { confirmDiscard = true }) }
                }
            }
            item {
                FilledTonalButton(
                    onClick = onCycleStep,
                    modifier = Modifier.fillMaxWidth(),
                    label = {
                        Text(
                            stringResource(R.string.weight_step),
                            modifier = Modifier.weight(1f),
                            maxLines = 2
                        )
                        Text(
                            stringResource(R.string.weight_kg, WorkoutMath.formatWeight(state.weightStepKg, loc)),
                            style = MaterialTheme.typography.labelMedium.tabular(),
                            color = WatchColors.TextSecondary
                        )
                    }
                )
            }
            if (status != null) {
                item {
                    Text(
                        text = status,
                        style = MaterialTheme.typography.labelSmall,
                        color = WatchColors.TextSecondary,
                        textAlign = TextAlign.Center,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    )
                }
            }
        }
    }
    DiscardDialog(visible = confirmDiscard, onKeep = { confirmDiscard = false }, onDiscard = {
        confirmDiscard = false
        onDiscardQueued()
    })
}

// ---------------------------------------------------------------- Dashboard

@Composable
private fun DashboardScreen(
    state: WearWorkoutUiState,
    isAmbient: Boolean,
    onLogSet: () -> Unit,
    onUndo: () -> Unit,
    onAddRest: () -> Unit,
    onSkipRest: () -> Unit
) {
    val loc = locale()
    val resting = state.restRemainingSeconds > 0
    val undoOpen = state.undoSetId != null
    val textColor = if (isAmbient) WatchColors.TextSecondary else WatchColors.Text
    val large = isLargeScreen()
    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 28.dp, bottom = if (isAmbient) 16.dp else if (large && !resting) 64.dp else 50.dp)
                .padding(horizontal = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            HeartRateRow(state = state, isAmbient = isAmbient)
            if (!resting) Spacer(Modifier.height(6.dp))
            if (resting) {
                Text(
                    text = stringResource(if (undoOpen) R.string.set_saved else R.string.rest),
                    style = MaterialTheme.typography.labelSmall,
                    color = WatchColors.TextSecondary
                )
                val minutes = state.restRemainingSeconds / 60
                val seconds = state.restRemainingSeconds % 60
                val restLabel = stringResource(R.string.a11y_rest, minutes, seconds)
                Text(
                    text = WorkoutMath.formatDuration(state.restRemainingSeconds.toLong()),
                    style = MaterialTheme.typography.numeralMedium.tabular(),
                    color = textColor,
                    maxLines = 1,
                    modifier = Modifier.clearAndSetSemantics { contentDescription = restLabel }
                )
                // "Next: …" only where it fits above the rest actions (spec §4.3 / §8).
                if (showNextLine()) {
                    state.nextTarget?.let { next ->
                        Text(
                            text = stringResource(
                                R.string.next,
                                stringResource(R.string.weight_reps, WorkoutMath.formatWeight(next.weight, loc), next.reps.toString())
                            ),
                            style = MaterialTheme.typography.labelSmall.tabular(),
                            color = WatchColors.TextSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                if (!isAmbient) {
                    Spacer(Modifier.height(4.dp))
                    CompactButton(
                        onClick = if (undoOpen) onUndo else onAddRest,
                        colors = ButtonDefaults.filledTonalButtonColors(),
                        label = {
                            Text(stringResource(if (undoOpen) R.string.undo else R.string.rest_add), maxLines = 1)
                        }
                    )
                }
            } else {
                val exercise = state.currentExercise
                Text(
                    // Before the first exercise the edge button says what to do; here only the mode.
                    text = exercise ?: stringResource(R.string.free_workout),
                    style = MaterialTheme.typography.titleMedium.withHyphens(),
                    color = if (exercise == null) WatchColors.TextSecondary else textColor,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                // No exercise yet (free workout, nothing logged): there is no set to preview, so
                // no "0 kg × 10" for a nameless exercise; the edge button picks the exercise.
                if (exercise == null) return@Column
                val target = state.nextTarget ?: SetTarget(0.0, WorkoutMath.DEFAULT_REPS)
                val weightText = WorkoutMath.formatWeight(target.weight, loc)
                val hero = stringResource(R.string.weight_reps, weightText, target.reps.toString())
                val heroLabel = stringResource(R.string.a11y_set_values, weightText, target.reps)
                Text(
                    text = hero,
                    style = (if (hero.length > 11) MaterialTheme.typography.numeralExtraSmall
                    else MaterialTheme.typography.numeralSmall).tabular(),
                    color = textColor,
                    maxLines = 1,
                    modifier = Modifier.clearAndSetSemantics { contentDescription = heroLabel }
                )
                val progress = state.setProgress
                Text(
                    text = progress.setCount?.let { stringResource(R.string.set_k_of_n, progress.setNumber, it) }
                        ?: stringResource(R.string.set_k, progress.setNumber),
                    style = MaterialTheme.typography.labelSmall.tabular(),
                    color = WatchColors.TextSecondary
                )
            }
        }
        if (!isAmbient) {
            EdgeButton(
                onClick = if (resting) onSkipRest else onLogSet,
                modifier = Modifier.align(Alignment.BottomCenter),
                buttonSize = if (resting) EdgeButtonSize.Small else edgeSize(large),
                colors = if (resting) ButtonDefaults.filledTonalButtonColors() else ButtonDefaults.buttonColors()
            ) {
                EdgeLabel(
                    stringResource(
                        when {
                            resting -> R.string.skip
                            state.currentExercise == null -> R.string.choose_exercise
                            else -> R.string.log_set
                        }
                    )
                )
            }
        }
    }
}

@Composable
private fun HeartRateRow(state: WearWorkoutUiState, isAmbient: Boolean) {
    val health = state.health
    val off = health.status == WearHealthStatus.Denied || health.status == WearHealthStatus.Unavailable
    val bpm = health.heartRate
    val zone = state.heartRateZone
    val label = when {
        off -> stringResource(R.string.hr_off)
        bpm != null && zone != null -> stringResource(R.string.a11y_heart_rate, bpm, zone)
        else -> stringResource(R.string.a11y_heart_rate_waiting)
    }
    val elapsed = if (isAmbient) {
        val minutes = state.elapsedSeconds / 60
        if (minutes >= 60) String.format(Locale.ROOT, "%d:%02d", minutes / 60, minutes % 60)
        else String.format(Locale.ROOT, "%d′", minutes)
    } else {
        WorkoutMath.formatDuration(state.elapsedSeconds)
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.clearAndSetSemantics { contentDescription = label }
        ) {
            Icon(
                imageVector = if (off) WatchIcons.HeartSlash else WatchIcons.Heart,
                contentDescription = null,
                tint = when {
                    off || isAmbient || zone == null -> WatchColors.TextSecondary
                    else -> WatchColors.zone(zone)
                },
                modifier = Modifier.size(16.dp)
            )
            Spacer(Modifier.width(4.dp))
            Text(
                text = when {
                    off -> "—"
                    bpm == null -> "--"
                    else -> bpm.toString()
                },
                style = MaterialTheme.typography.labelMedium.tabular(),
                color = if (off) WatchColors.TextSecondary else WatchColors.Text
            )
            if (!off && zone != null && !isAmbient) {
                Spacer(Modifier.width(4.dp))
                Box(
                    modifier = Modifier
                        .size(20.dp)
                        .background(WatchColors.zone(zone), RoundedCornerShape(6.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = zone.toString(),
                        style = MaterialTheme.typography.labelSmall.tabular(),
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black
                    )
                }
            }
        }
        Spacer(Modifier.width(12.dp))
        Text(
            text = elapsed,
            style = MaterialTheme.typography.labelMedium.tabular(),
            color = WatchColors.Text
        )
    }
}

// ---------------------------------------------------------------- Set entry

@Composable
private fun SetEntryScreen(
    state: WearWorkoutUiState,
    onPickExercise: () -> Unit,
    onSave: (exercise: String, weight: Double, reps: Int) -> Unit
) {
    val loc = locale()
    val exercise = state.currentExercise
    val target = state.nextTarget ?: SetTarget(0.0, WorkoutMath.DEFAULT_REPS)
    val weightOptions = remember(state.weightStepKg, target.weight) {
        WorkoutMath.weightOptions(state.weightStepKg, target.weight)
    }
    val weightState = rememberPickerState(
        initialNumberOfOptions = weightOptions.size,
        initiallySelectedIndex = WorkoutMath.closestIndex(weightOptions, target.weight),
        shouldRepeatOptions = false
    )
    val repsState = rememberPickerState(
        initialNumberOfOptions = WorkoutMath.repOptions.size,
        initiallySelectedIndex = WorkoutMath.repIndex(target.reps),
        shouldRepeatOptions = false
    )
    var selectedColumn by remember { mutableIntStateOf(0) }
    val weightLabel = stringResource(R.string.label_weight)
    val repsLabel = stringResource(R.string.label_reps)
    val kg = stringResource(R.string.unit_kg)
    val reps = stringResource(R.string.unit_reps)
    val changeExercise = stringResource(R.string.a11y_change_exercise)
    val large = isLargeScreen()

    // Vertical budget (spec §4.4): slim exercise chip, unit labels sitting directly on their
    // wheel, then exactly three option rows so each column reads as a wheel. The chip starts
    // below the scaffold's time text. 227dp round: 22 + 30 chip + 16 labels + 90 wheels above the
    // 56dp edge button; 192dp: 22 + 26 + 15 + 75 above the 46dp one.
    val topInset = 22.dp
    val chipHeight = if (large) 30.dp else 26.dp
    val rowHeight = if (large) 30.dp else 25.dp
    val weightWidth = 76.dp
    val repsWidth = 56.dp
    val unitStyle = MaterialTheme.typography.labelSmall

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(bottom = if (large) 58.dp else 48.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            ExerciseChip(
                text = exercise ?: stringResource(R.string.choose_exercise),
                placeholder = exercise == null,
                description = "${exercise ?: ""}. $changeExercise",
                topInset = topInset,
                height = chipHeight,
                widthFraction = if (large) 0.6f else 0.66f,
                onClick = onPickExercise
            )
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.Center) {
                Text(
                    kg,
                    modifier = Modifier.width(weightWidth),
                    style = unitStyle,
                    color = WatchColors.TextSecondary,
                    textAlign = TextAlign.Center,
                    maxLines = 1
                )
                Text(
                    reps,
                    modifier = Modifier.width(repsWidth),
                    style = unitStyle,
                    color = WatchColors.TextSecondary,
                    textAlign = TextAlign.Center,
                    maxLines = 1
                )
            }
            Box(
                modifier = Modifier.fillMaxWidth().height(rowHeight * 3),
                contentAlignment = Alignment.Center
            ) {
                PickerGroup(
                    modifier = Modifier.fillMaxWidth().height(rowHeight * 3),
                    selectedPickerState = if (selectedColumn == 0) weightState else repsState,
                    autoCenter = false
                ) {
                    PickerGroupItem(
                        pickerState = weightState,
                        selected = selectedColumn == 0,
                        onSelected = { selectedColumn = 0 },
                        modifier = Modifier.width(weightWidth).height(rowHeight * 3),
                        contentDescription = {
                            "$weightLabel, ${WorkoutMath.formatWeight(weightOptions[weightState.selectedOptionIndex], loc)} $kg"
                        },
                        option = { index, columnSelected ->
                            PickerValue(
                                text = WorkoutMath.formatWeight(weightOptions[index], loc),
                                current = index == weightState.selectedOptionIndex,
                                columnSelected = columnSelected,
                                rowHeight = rowHeight
                            )
                        }
                    )
                    PickerGroupItem(
                        pickerState = repsState,
                        selected = selectedColumn == 1,
                        onSelected = { selectedColumn = 1 },
                        modifier = Modifier.width(repsWidth).height(rowHeight * 3),
                        contentDescription = {
                            "$repsLabel, ${WorkoutMath.repOptions[repsState.selectedOptionIndex]}"
                        },
                        option = { index, columnSelected ->
                            PickerValue(
                                text = WorkoutMath.repOptions[index].toString(),
                                current = index == repsState.selectedOptionIndex,
                                columnSelected = columnSelected,
                                rowHeight = rowHeight
                            )
                        }
                    )
                }
            }
            Spacer(Modifier.weight(1f))
        }
        EdgeButton(
            onClick = {
                if (exercise != null) {
                    onSave(
                        exercise,
                        weightOptions[weightState.selectedOptionIndex],
                        WorkoutMath.repOptions[repsState.selectedOptionIndex]
                    )
                }
            },
            enabled = exercise != null,
            modifier = Modifier.align(Alignment.BottomCenter),
            buttonSize = if (large) EdgeButtonSize.Small else EdgeButtonSize.ExtraSmall
        ) {
            // The extra-small edge button holds about seven letters per line: "Сохранить подход"
            // / "Зберегти підхід" would be cut mid-word, so small screens get a check mark.
            if (large) {
                EdgeLabel(stringResource(R.string.save_set))
            } else {
                Icon(WatchIcons.Check, contentDescription = stringResource(R.string.save_set))
            }
        }
    }
}

/**
 * Slim exercise row. The pill is short to leave the height to the wheels, but the whole strip
 * from the top of the screen down to its bottom edge takes the tap.
 */
@Composable
private fun ExerciseChip(
    text: String,
    placeholder: Boolean,
    description: String,
    topInset: Dp,
    height: Dp,
    widthFraction: Float,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxWidth(widthFraction)
            .height(topInset + height)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClick = onClick
            )
            .semantics { contentDescription = description },
        contentAlignment = Alignment.BottomCenter
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(height)
                .clip(RoundedCornerShape(50))
                .background(WatchColors.SurfaceHigh)
                .padding(start = 12.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.labelMedium,
                color = if (placeholder) WatchColors.TextSecondary else WatchColors.Text,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).clearAndSetSemantics { }
            )
            Icon(
                WatchIcons.Chevron,
                contentDescription = null,
                tint = WatchColors.TextSecondary,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

/** One wheel row of a fixed height: the current value large, its neighbours small and dim. */
@Composable
private fun PickerValue(text: String, current: Boolean, columnSelected: Boolean, rowHeight: Dp) {
    Box(modifier = Modifier.fillMaxWidth().height(rowHeight), contentAlignment = Alignment.Center) {
        Text(
            text = text,
            style = (if (current) MaterialTheme.typography.displaySmall else MaterialTheme.typography.titleMedium).tabular(),
            color = when {
                current && columnSelected -> WatchColors.Accent
                current -> WatchColors.Text
                else -> WatchColors.TextSecondary
            },
            maxLines = 1
        )
    }
}

// ---------------------------------------------------------------- Exercise picker

@Composable
private fun ExercisePickerScreen(state: WearWorkoutUiState, onSelect: (String) -> Unit) {
    val loc = locale()
    val plan = WorkoutMath.planProgress(state.activePlanTargets, state.loggedSets)
    val planNames = plan.map { it.exerciseName }.toSet()
    val collator = remember(loc) { Collator.getInstance(loc) }
    val catalog = remember(state.availableExercises, planNames, collator) {
        state.availableExercises.filterNot { it in planNames }.sortedWith(collator)
    }
    val firstRemaining = plan.indexOfFirst { it.hasRemaining }.coerceAtLeast(0)
    val listState = rememberScalingLazyListState(
        initialCenterItemIndex = if (plan.isEmpty()) 1 else firstRemaining + 1
    )
    val current = state.currentExercise
    ScreenScaffold(scrollState = listState) { padding ->
        ScalingLazyColumn(modifier = Modifier.fillMaxSize(), state = listState, contentPadding = padding) {
            if (plan.isNotEmpty()) {
                item { ListHeader { Text(stringResource(R.string.section_plan)) } }
                plan.forEach { row ->
                    item {
                        FilledTonalButton(
                            onClick = { onSelect(row.exerciseName) },
                            modifier = Modifier.fillMaxWidth(),
                            colors = if (row.exerciseName == current) {
                                ButtonDefaults.filledTonalButtonColors(containerColor = WatchColors.AccentTonal)
                            } else {
                                ButtonDefaults.filledTonalButtonColors()
                            },
                            label = {
                                Text(
                                    row.exerciseName,
                                    modifier = Modifier.weight(1f),
                                    maxLines = 3,
                                    overflow = TextOverflow.Ellipsis
                                )
                                Text(
                                    "${row.done}/${row.total}",
                                    style = MaterialTheme.typography.labelMedium.tabular(),
                                    color = WatchColors.TextSecondary,
                                    modifier = Modifier.padding(start = 4.dp)
                                )
                            }
                        )
                    }
                }
            }
            item { ListHeader { Text(stringResource(R.string.section_all)) } }
            if (catalog.isEmpty() && plan.isEmpty()) {
                item {
                    Text(
                        stringResource(R.string.no_exercises),
                        style = MaterialTheme.typography.bodyLarge,
                        color = WatchColors.TextSecondary,
                        textAlign = TextAlign.Center
                    )
                }
            }
            catalog.forEach { name ->
                item {
                    FilledTonalButton(
                        onClick = { onSelect(name) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(name, maxLines = 3, overflow = TextOverflow.Ellipsis) }
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------- Pause

@Composable
private fun PauseScreen(
    state: WearWorkoutUiState,
    onResume: () -> Unit,
    onFinish: () -> Unit,
    onDiscarded: () -> Unit
) {
    val listState = rememberScalingLazyListState()
    var showNeedSet by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    ScreenScaffold(scrollState = listState) { padding ->
        ScalingLazyColumn(modifier = Modifier.fillMaxSize(), state = listState, contentPadding = padding) {
            item {
                ListHeader {
                    Text(
                        "${stringResource(R.string.paused)} · ${WorkoutMath.formatDuration(state.elapsedSeconds)}",
                        style = MaterialTheme.typography.titleMedium.tabular()
                    )
                }
            }
            item {
                Button(
                    onClick = onResume,
                    modifier = Modifier.fillMaxWidth(),
                    icon = { Icon(WatchIcons.Play, contentDescription = null) },
                    label = { Text(stringResource(R.string.resume)) }
                )
            }
            item {
                FilledTonalButton(
                    onClick = {
                        if (state.loggedSets.isEmpty()) showNeedSet = true else onFinish()
                    },
                    modifier = Modifier.fillMaxWidth(),
                    icon = { Icon(WatchIcons.Check, contentDescription = null) },
                    label = { Text(stringResource(R.string.finish)) }
                )
            }
            item {
                DiscardButton(onClick = { confirmDiscard = true })
            }
            if (showNeedSet) {
                item {
                    Text(
                        stringResource(R.string.need_set),
                        style = MaterialTheme.typography.labelSmall,
                        color = WatchColors.TextSecondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)
                    )
                }
            }
        }
    }
    DiscardDialog(visible = confirmDiscard, onKeep = { confirmDiscard = false }, onDiscard = {
        confirmDiscard = false
        onDiscarded()
    })
}

@Composable
private fun DiscardButton(onClick: () -> Unit) {
    FilledTonalButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = WatchColors.DestructiveTonal,
            contentColor = WatchColors.Destructive,
            iconColor = WatchColors.Destructive
        ),
        icon = { Icon(WatchIcons.Trash, contentDescription = null) },
        label = { Text(stringResource(R.string.discard), maxLines = 2) }
    )
}

/**
 * Spec §4.8: Discard above, Keep workout (filled) below as the default; back-swipe keeps.
 * Both are list buttons rather than an edge button: "Залишити тренування" / "Оставить
 * тренировку" need two lines, which an edge button clips against the round bezel, while list
 * items always stay inside the scaffold's safe area on 192–227dp screens.
 */
@Composable
private fun DiscardDialog(visible: Boolean, onKeep: () -> Unit, onDiscard: () -> Unit) {
    AlertDialog(
        visible = visible,
        onDismissRequest = onKeep,
        title = { Text(stringResource(R.string.discard_title), textAlign = TextAlign.Center) },
        text = { Text(stringResource(R.string.discard_body), textAlign = TextAlign.Center) }
    ) {
        item { DiscardButton(onClick = onDiscard) }
        item {
            Button(
                onClick = onKeep,
                modifier = Modifier.fillMaxWidth(),
                label = {
                    Text(
                        stringResource(R.string.keep),
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.Center,
                        maxLines = 2
                    )
                }
            )
        }
    }
}

// ---------------------------------------------------------------- Summary

@Composable
private fun SummaryScreen(state: WearWorkoutUiState, onSave: () -> Unit, onDiscarded: () -> Unit) {
    val loc = locale()
    val listState = rememberScalingLazyListState()
    var confirmDiscard by remember { mutableStateOf(false) }
    val summary = state.summary
    val none = "—"
    ScreenScaffold(
        scrollState = listState,
        edgeButton = {
            EdgeButton(
                onClick = onSave,
                enabled = summary.setCount > 0 && !state.isSaving,
                buttonSize = edgeSize(isLargeScreen())
            ) {
                EdgeLabel(stringResource(R.string.save))
            }
        }
    ) { padding ->
        ScalingLazyColumn(modifier = Modifier.fillMaxSize(), state = listState, contentPadding = padding) {
            item { ListHeader { Text(stringResource(R.string.summary), textAlign = TextAlign.Center) } }
            item {
                MetricRow(
                    WorkoutMath.formatDuration(summary.durationSeconds) to stringResource(R.string.label_duration),
                    summary.setCount.toString() to stringResource(R.string.label_sets)
                )
            }
            item {
                MetricRow(
                    stringResource(R.string.weight_kg, WorkoutMath.formatVolume(summary.volumeKg, loc)) to
                        stringResource(R.string.label_volume),
                    (summary.caloriesKcal?.let { stringResource(R.string.value_kcal, it) } ?: none) to
                        stringResource(R.string.calories)
                )
            }
            item {
                MetricRow(
                    (summary.averageHeartRate?.let { stringResource(R.string.value_bpm, it) } ?: none) to
                        stringResource(R.string.label_avg_hr),
                    (summary.maxHeartRate?.let { stringResource(R.string.value_bpm, it) } ?: none) to
                        stringResource(R.string.label_max_hr)
                )
            }
            item {
                TextButton(
                    onClick = { confirmDiscard = true },
                    modifier = Modifier.fillMaxWidth(),
                    colors = TextButtonDefaults.textButtonColors(contentColor = WatchColors.Destructive)
                ) {
                    Text(stringResource(R.string.discard), textAlign = TextAlign.Center, maxLines = 2)
                }
            }
        }
    }
    DiscardDialog(visible = confirmDiscard, onKeep = { confirmDiscard = false }, onDiscard = {
        confirmDiscard = false
        onDiscarded()
    })
}

@Composable
private fun MetricRow(left: Pair<String, String>, right: Pair<String, String>) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
        Metric(left.first, left.second, Modifier.weight(1f))
        Metric(right.first, right.second, Modifier.weight(1f))
    }
}

@Composable
private fun Metric(value: String, label: String, modifier: Modifier) {
    Column(
        modifier = modifier.semantics(mergeDescendants = true) { },
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, style = MaterialTheme.typography.titleLarge.tabular(), maxLines = 1)
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = WatchColors.TextSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

// ---------------------------------------------------------------- Result

@Composable
private fun ResultScreen(state: WearWorkoutUiState, onSavedHaptic: () -> Unit, onClose: () -> Unit) {
    var timedOut by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(SENDING_TIMEOUT_MS)
        timedOut = true
    }
    val outcome = when {
        state.saveOutcome == SaveOutcome.Saved -> SaveOutcome.Saved
        state.saveOutcome == SaveOutcome.Deferred || timedOut -> SaveOutcome.Deferred
        else -> SaveOutcome.Sending
    }
    val savedText = stringResource(R.string.saved_phone)
    when (outcome) {
        SaveOutcome.Sending -> Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            CircularProgressIndicator(modifier = Modifier.size(48.dp))
            Spacer(Modifier.height(8.dp))
            Text(stringResource(R.string.sending), style = MaterialTheme.typography.labelMedium)
        }
        SaveOutcome.Saved -> {
            LaunchedEffect(Unit) { onSavedHaptic() }
            SuccessConfirmationDialog(
                visible = true,
                onDismissRequest = onClose,
                curvedText = { curvedText(savedText) },
                durationMillis = SAVED_DIALOG_MS
            )
        }
        SaveOutcome.Deferred -> Box(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(start = 24.dp, end = 24.dp, bottom = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    WatchIcons.Warning,
                    contentDescription = null,
                    tint = WatchColors.Warning,
                    modifier = Modifier.size(28.dp)
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    stringResource(R.string.send_later),
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center
                )
            }
            EdgeButton(
                onClick = onClose,
                modifier = Modifier.align(Alignment.BottomCenter),
                buttonSize = edgeSize(isLargeScreen())
            ) {
                EdgeLabel(stringResource(R.string.done))
            }
        }
    }
}

private fun androidx.compose.ui.text.TextStyle.withHyphens() =
    copy(hyphens = Hyphens.Auto, lineBreak = LineBreak.Heading)
