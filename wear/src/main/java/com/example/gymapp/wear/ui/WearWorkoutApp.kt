package com.example.gymapp.wear.ui

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.background
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.indication
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.graphics.takeOrElse
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.LineBreak
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
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
import androidx.wear.compose.material3.LocalContentColor
import androidx.wear.compose.material3.LocalTextConfiguration
import androidx.wear.compose.material3.LocalTextStyle
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.PickerGroup
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.SuccessConfirmationDialog
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.TextButton
import androidx.wear.compose.material3.TextButtonDefaults
import androidx.wear.compose.material3.minimumInteractiveComponentSize
import androidx.wear.compose.material3.ripple
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
private const val MESSAGE_MS = 4_000L

/** Height of the straight time line at the top of a square screen, plus a small gap. */
private val SQUARE_CLOCK_INSET = 24.dp

/** Clear space between a fixed edge button and the end of the list scrolling above it. */
private val EDGE_BUTTON_GAP = 8.dp

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
            Box(modifier = Modifier.fillMaxSize()) {
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
                        onLink = viewModel::linkToPhone,
                        onUnlink = viewModel::unlinkFromPhone,
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
            // Always-on: one layout over whichever route is open, so no screen keeps accent
            // fills, white text or buttons while the watch is dozing (spec §4.2).
            state.message?.let { text ->
                if (!isAmbient) MessageBanner(text = text, onDone = viewModel::consumeMessage)
            }
            if (isAmbient) AmbientScreen(state = state)
            }
        }
    }
}

/**
 * One transient line for what the ViewModel has to say (set limit reached, new plan waiting,
 * phone not connected). It goes away by itself or on a tap and is announced once.
 */
@Composable
private fun MessageBanner(text: String, onDone: () -> Unit) {
    LaunchedEffect(text) {
        delay(MESSAGE_MS)
        onDone()
    }
    val interaction = remember { MutableInteractionSource() }
    val dismissLabel = stringResource(R.string.a11y_dismiss)
    Box(
        modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = WatchColors.Text,
            textAlign = TextAlign.Center,
            maxLines = 5,
            overflow = TextOverflow.Ellipsis,
            // The click and its semantics sit on a 48dp minimum target; the pill, its ripple and
            // the text keep their own size inside it, so the banner looks the same on small screens.
            modifier = Modifier
                .clickable(
                    interactionSource = interaction,
                    indication = null,
                    role = Role.Button,
                    onClickLabel = dismissLabel,
                    onClick = onDone
                )
                .minimumInteractiveComponentSize()
                .clip(RoundedCornerShape(16.dp))
                .background(WatchColors.SurfaceHigh)
                .indication(interaction, ripple())
                .padding(horizontal = 12.dp, vertical = 8.dp)
                .semantics { liveRegion = LiveRegionMode.Polite }
        )
    }
}

/**
 * Always-on layout (spec §4.2): black, no accent fills, no buttons, secondary text, elapsed time
 * without seconds. It covers the open route and takes its touches, so nothing below reacts.
 */
@Composable
private fun AmbientScreen(state: WearWorkoutUiState) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(WatchColors.Background)
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) awaitPointerEvent().changes.forEach { it.consume() }
                }
            },
        contentAlignment = Alignment.Center
    ) {
        if (state.workoutActive && !state.paused) {
            DashboardScreen(
                state = state,
                isAmbient = true,
                onLogSet = {},
                onUndo = {},
                onAddRest = {},
                onSkipRest = {}
            )
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = stringResource(R.string.start_title),
                    style = MaterialTheme.typography.titleMedium,
                    color = WatchColors.TextSecondary
                )
                if (state.workoutActive) {
                    Text(
                        text = "${stringResource(R.string.paused)} · ${ambientElapsed(state.elapsedSeconds)}",
                        style = MaterialTheme.typography.labelMedium.tabular(),
                        color = WatchColors.TextSecondary
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

/**
 * Edge button label. A word is never broken across lines: screens under 225dp get a one-word
 * label ([singleLine], smaller type, no wrapping) or an icon, larger ones up to two whole words.
 */
@Composable
private fun EdgeLabel(text: String, singleLine: Boolean = false) {
    if (singleLine) {
        // At a large text size the one word steps down instead of ending in "Запис…".
        FitText(text, style = MaterialTheme.typography.labelSmall, textAlign = TextAlign.Center)
        return
    }
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        textAlign = TextAlign.Center,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis
    )
}

/**
 * One line that steps its type size down when it does not fit, instead of breaking a word
 * ("Продолжит / ь") or ending in an ellipsis. When the line fits (the default text size) it is
 * drawn at [style]'s own size, exactly like [Text].
 */
@Composable
private fun FitText(
    text: String,
    modifier: Modifier = Modifier,
    style: TextStyle = LocalTextStyle.current,
    textAlign: TextAlign = LocalTextConfiguration.current.textAlign ?: TextAlign.Unspecified,
    color: Color = Color.Unspecified
) {
    val textColor = color.takeOrElse { style.color.takeOrElse { LocalContentColor.current } }
    val maxSize = style.fontSize
    BasicText(
        text = text,
        modifier = modifier,
        style = style.copy(color = textColor, textAlign = textAlign),
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Ellipsis,
        autoSize = if (maxSize.isSpecified && maxSize > FIT_TEXT_MIN_SIZE) {
            TextAutoSize.StepBased(minFontSize = FIT_TEXT_MIN_SIZE, maxFontSize = maxSize, stepSize = 0.5.sp)
        } else {
            null
        }
    )
}

private val FIT_TEXT_MIN_SIZE = 10.sp

/** Height the edge button really takes, so the content above it is never drawn under it. */
@Composable
private fun edgeHeightDp(measuredPx: Int, fallback: Dp): Dp =
    if (measuredPx > 0) with(LocalDensity.current) { measuredPx.toDp() } else fallback

/** A duration in words for TalkBack ("1 hour 5 minutes 3 seconds"); zero parts are skipped. */
@Composable
private fun spokenDuration(totalSeconds: Long): String {
    val seconds = totalSeconds.coerceAtLeast(0L)
    val h = (seconds / 3600).toInt()
    val m = ((seconds % 3600) / 60).toInt()
    val s = (seconds % 60).toInt()
    val parts = buildList {
        if (h > 0) add(pluralStringResource(R.plurals.a11y_hours, h, h))
        if (m > 0) add(pluralStringResource(R.plurals.a11y_minutes, m, m))
        if (s > 0 || (h == 0 && m == 0)) add(pluralStringResource(R.plurals.a11y_seconds, s, s))
    }
    return parts.joinToString(" ")
}

/** Always-on elapsed time: minutes only, no seconds (spec §4.2). */
private fun ambientElapsed(elapsedSeconds: Long): String {
    val minutes = elapsedSeconds / 60
    return if (minutes >= 60) String.format(Locale.ROOT, "%d:%02d", minutes / 60, minutes % 60)
    else String.format(Locale.ROOT, "%d′", minutes)
}

/** Medium leaves room for the longer UK/RU labels ("Записати підхід") on 225dp+ screens. */
private fun edgeSize(large: Boolean): EdgeButtonSize =
    if (large) EdgeButtonSize.Medium else EdgeButtonSize.Small

private fun View.haptic(constant: Int) {
    performHapticFeedback(constant)
}

@Composable
private fun isLargeScreen(): Boolean = LocalConfiguration.current.screenWidthDp >= 225

/** Square and short rectangular screens: less height than the smallest round one. */
@Composable
private fun isShortScreen(): Boolean = LocalConfiguration.current.screenHeightDp < 190

/** The user picked a larger text size (Settings › Display › Font size, 1.15 and up). */
@Composable
private fun isLargeText(): Boolean = LocalDensity.current.fontScale >= 1.15f

@Composable
private fun locale(): Locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()

// ---------------------------------------------------------------- Start

@Composable
private fun StartScreen(
    state: WearWorkoutUiState,
    onStart: (usePlan: Boolean) -> Unit,
    onCycleStep: () -> Unit,
    onLink: () -> Unit,
    onUnlink: () -> Unit,
    onRetry: () -> Unit,
    onDiscardQueued: () -> Unit
) {
    val listState = rememberScalingLazyListState()
    val hasPlan = state.planTargets.isNotEmpty()
    val queued = state.hasQueuedWorkout
    // Held work (its account is not the one bound now) blocks Start like a queued workout.
    val canStart = state.isLinked && !queued && !state.isSaving && !state.workoutOnHold
    var confirmDiscard by remember { mutableStateOf(false) }
    var confirmUnlink by remember { mutableStateOf(false) }
    val status = when {
        queued && state.isSaving -> stringResource(R.string.sending)
        state.unlinked -> stringResource(R.string.link_unlinked)
        !state.isLinked -> stringResource(R.string.open_phone)
        // Held for another account, or refused by the phone: the queued block says so. "Will
        // send when the phone is nearby" would be wrong for both, so there is no status line.
        queued && (state.workoutOnHold || state.sendRejected) -> null
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
                            text = stringResource(
                                when {
                                    state.workoutOnHold -> R.string.queued_hold_body
                                    state.sendRejected -> R.string.send_rejected
                                    else -> R.string.queued_body
                                }
                            ),
                            style = MaterialTheme.typography.labelSmall,
                            color = WatchColors.TextSecondary,
                            textAlign = TextAlign.Center,
                            maxLines = 5
                        )
                    }
                }
                if (state.isLinked && !state.isSaving && !state.workoutOnHold) {
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
            // Not paired: pairing is the one thing to do here, so it is the filled button.
            if (state.unlinked) {
                item {
                    Button(
                        onClick = onLink,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text(stringResource(R.string.link_phone), maxLines = 2) }
                    )
                }
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
            // Unpairing is rare and loses the synced plan: last in the list, text only, and it
            // asks first. It never deletes a workout stored on the watch.
            if (!state.unlinked && state.isLinked && !state.isSaving) {
                item {
                    Button(
                        onClick = { confirmUnlink = true },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.childButtonColors(contentColor = WatchColors.TextSecondary),
                        label = { CenteredLabel(R.string.unlink_phone) }
                    )
                }
            }
        }
    }
    DiscardDialog(visible = confirmDiscard, onKeep = { confirmDiscard = false }, onDiscard = {
        confirmDiscard = false
        onDiscardQueued()
    })
    UnlinkDialog(visible = confirmUnlink, onCancel = { confirmUnlink = false }, onUnlink = {
        confirmUnlink = false
        onUnlink()
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
    val short = isShortScreen()
    // Under 225dp a large text size makes the stack taller than the space above the edge
    // button; the numbers drop one numeral step so the set line and Undo stay clear of it.
    val compactType = !large && isLargeText()
    var edgePx by remember { mutableIntStateOf(0) }
    val edgeButtonSize = when {
        resting -> if (large) EdgeButtonSize.Small else EdgeButtonSize.ExtraSmall
        else -> edgeSize(large)
    }
    val edgeHeight = edgeHeightDp(
        edgePx,
        when (edgeButtonSize) {
            EdgeButtonSize.ExtraSmall -> 46.dp
            EdgeButtonSize.Small -> 56.dp
            else -> 70.dp
        }
    )
    val bottomPadding = when {
        isAmbient -> 16.dp
        // The compact button keeps 8dp of clear touch margin under its pill; that margin may sit
        // over the top of the edge button, the pill itself never does.
        resting -> (edgeHeight - 8.dp).coerceAtLeast(0.dp)
        else -> edgeHeight
    }
    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = if (large) 28.dp else 26.dp, bottom = bottomPadding)
                .padding(horizontal = 18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            HeartRateRow(state = state, isAmbient = isAmbient)
            if (!resting && !compactType) Spacer(Modifier.height(6.dp))
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
                    style = (if (short || compactType) MaterialTheme.typography.numeralSmall
                    else MaterialTheme.typography.numeralMedium).tabular(),
                    color = textColor,
                    maxLines = 1,
                    modifier = Modifier.clearAndSetSemantics { contentDescription = restLabel }
                )
                // "Next: …" only where it fits above the rest actions (spec §4.3 / §8 / §10: 225dp+).
                if (large) {
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
                    // No spacer: the compact button brings its own 8dp touch margin above the pill.
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
                    // Under 225dp the second line would push the set line under the edge button
                    // (spec §8: the name gives way before a number does).
                    maxLines = if (large) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = if (exercise == null) Modifier else Modifier.semantics { contentDescription = exercise }
                )
                // No exercise yet (free workout, nothing logged): there is no set to preview, so
                // no "0 kg × 10" for a nameless exercise; the edge button picks the exercise.
                if (exercise == null) return@Column
                val target = state.nextTarget ?: SetTarget(0.0, WorkoutMath.DEFAULT_REPS)
                val weightText = WorkoutMath.formatWeight(target.weight, loc)
                val hero = stringResource(R.string.weight_reps, weightText, target.reps.toString())
                val heroLabel = stringResource(
                    R.string.a11y_set_values,
                    weightText,
                    pluralStringResource(R.plurals.a11y_reps, target.reps, target.reps)
                )
                Text(
                    text = hero,
                    style = (if (hero.length > 11 || compactType) MaterialTheme.typography.numeralExtraSmall
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
                modifier = Modifier.align(Alignment.BottomCenter).onSizeChanged { edgePx = it.height },
                buttonSize = edgeButtonSize,
                colors = if (resting) ButtonDefaults.filledTonalButtonColors() else ButtonDefaults.buttonColors()
            ) {
                when {
                    // "Пропустить" / "Пропустити" do not fit one line of a small edge button.
                    resting && !large ->
                        Icon(WatchIcons.SkipForward, contentDescription = stringResource(R.string.skip))
                    resting -> EdgeLabel(stringResource(R.string.skip))
                    state.currentExercise == null -> EdgeLabel(
                        stringResource(if (large) R.string.choose_exercise else R.string.choose_short),
                        singleLine = !large
                    )
                    else -> EdgeLabel(
                        stringResource(if (large) R.string.log_set else R.string.log_set_short),
                        singleLine = !large
                    )
                }
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
        bpm != null && zone != null -> stringResource(
            R.string.a11y_heart_rate,
            pluralStringResource(R.plurals.a11y_beats, bpm, bpm),
            zone
        )
        else -> stringResource(R.string.a11y_heart_rate_waiting)
    }
    val elapsed = if (isAmbient) ambientElapsed(state.elapsedSeconds) else WorkoutMath.formatDuration(state.elapsedSeconds)
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
                color = if (off || isAmbient) WatchColors.TextSecondary else WatchColors.Text
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
            color = if (isAmbient) WatchColors.TextSecondary else WatchColors.Text
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
    val repOptions = remember(target.reps) { WorkoutMath.repOptions(target.reps) }
    val repsState = rememberPickerState(
        initialNumberOfOptions = repOptions.size,
        initiallySelectedIndex = WorkoutMath.repIndex(repOptions, target.reps),
        shouldRepeatOptions = false
    )
    // The picker states are saveable and outlive a change of their option lists (another exercise
    // picked, next target changed). When the count differs, resize the wheel and move it to the
    // target; reads below are clamped for the frame before this runs.
    LaunchedEffect(weightOptions) {
        if (weightOptions.isNotEmpty() && weightState.numberOfOptions != weightOptions.size) {
            weightState.numberOfOptions = weightOptions.size
            weightState.scrollToOption(WorkoutMath.closestIndex(weightOptions, target.weight))
        }
    }
    LaunchedEffect(repOptions) {
        if (repOptions.isNotEmpty() && repsState.numberOfOptions != repOptions.size) {
            repsState.numberOfOptions = repOptions.size
            repsState.scrollToOption(WorkoutMath.repIndex(repOptions, target.reps))
        }
    }
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
                            val weight = WorkoutMath.optionAt(weightOptions, weightState.selectedOptionIndex)
                            "$weightLabel, ${weight?.let { WorkoutMath.formatWeight(it, loc) }.orEmpty()} $kg"
                        },
                        option = { index, columnSelected ->
                            val weight = WorkoutMath.optionAt(weightOptions, index)
                            PickerValue(
                                text = weight?.let { WorkoutMath.formatWeight(it, loc) }.orEmpty(),
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
                            "$repsLabel, ${WorkoutMath.optionAt(repOptions, repsState.selectedOptionIndex) ?: ""}"
                        },
                        option = { index, columnSelected ->
                            PickerValue(
                                text = WorkoutMath.optionAt(repOptions, index)?.toString().orEmpty(),
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
                val weight = WorkoutMath.optionAt(weightOptions, weightState.selectedOptionIndex)
                val repsValue = WorkoutMath.optionAt(repOptions, repsState.selectedOptionIndex)
                if (exercise != null && weight != null && repsValue != null) {
                    onSave(exercise, weight, repsValue)
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
    // At a large text size the current value's line is taller than its row; clamped to the row,
    // its bottom (the comma's tail in "62,5") was cut off and read as "62.5". It keeps its own
    // height and overflows the row evenly instead.
    val unclamped = current && isLargeText()
    Box(modifier = Modifier.fillMaxWidth().height(rowHeight), contentAlignment = Alignment.Center) {
        Text(
            text = text,
            modifier = if (unclamped) Modifier.wrapContentHeight(unbounded = true) else Modifier,
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
                    // One word: it steps down at a large text size instead of breaking ("Продолжит / ь").
                    label = { FitText(stringResource(R.string.resume)) }
                )
            }
            item {
                FilledTonalButton(
                    onClick = {
                        if (state.loggedSets.isEmpty()) showNeedSet = true else onFinish()
                    },
                    modifier = Modifier.fillMaxWidth(),
                    icon = { Icon(WatchIcons.Check, contentDescription = null) },
                    label = { FitText(stringResource(R.string.finish)) }
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
 * Keep workout (filled, the safe default) comes first so it is on screen without scrolling on
 * every size; Discard is below it; back-swipe keeps. Same order on Apple Watch (this replaces
 * the order of spec §4.8). Both are list buttons rather than an edge button: "Залишити
 * тренування" / "Оставить тренировку" need two lines, which an edge button clips against the
 * round bezel, while list items stay inside the scaffold's safe area.
 */
@Composable
private fun DiscardDialog(visible: Boolean, onKeep: () -> Unit, onDiscard: () -> Unit) {
    AlertDialog(
        visible = visible,
        onDismissRequest = onKeep,
        title = { Text(stringResource(R.string.discard_title), textAlign = TextAlign.Center) },
        text = { Text(stringResource(R.string.discard_body), textAlign = TextAlign.Center) }
    ) {
        item { Button(onClick = onKeep, modifier = Modifier.fillMaxWidth(), label = { CenteredLabel(R.string.keep) }) }
        item { DiscardButton(onClick = onDiscard) }
    }
}

/** Unpairing forgets the phone's plan and exercises on the watch, so it asks first. */
@Composable
private fun UnlinkDialog(visible: Boolean, onCancel: () -> Unit, onUnlink: () -> Unit) {
    AlertDialog(
        visible = visible,
        onDismissRequest = onCancel,
        title = { Text(stringResource(R.string.unlink_title), textAlign = TextAlign.Center) },
        text = { Text(stringResource(R.string.unlink_body), textAlign = TextAlign.Center) }
    ) {
        item { Button(onClick = onCancel, modifier = Modifier.fillMaxWidth(), label = { CenteredLabel(R.string.cancel) }) }
        item {
            FilledTonalButton(
                onClick = onUnlink,
                modifier = Modifier.fillMaxWidth(),
                label = { CenteredLabel(R.string.unlink_phone) }
            )
        }
    }
}

@Composable
private fun CenteredLabel(textRes: Int) {
    Text(
        stringResource(textRes),
        modifier = Modifier.fillMaxWidth(),
        textAlign = TextAlign.Center,
        maxLines = 2
    )
}

// ---------------------------------------------------------------- Summary

@Composable
private fun SummaryScreen(state: WearWorkoutUiState, onSave: () -> Unit, onDiscarded: () -> Unit) {
    val loc = locale()
    val listState = rememberScalingLazyListState(initialCenterItemIndex = 0)
    var confirmDiscard by remember { mutableStateOf(false) }
    val summary = state.summary
    val none = "—"
    val noData = stringResource(R.string.a11y_no_data)
    val large = isLargeScreen()
    var edgePx by remember { mutableIntStateOf(0) }
    val edgeHeight = edgeHeightDp(edgePx, if (large) 70.dp else 46.dp)
    val direction = LocalLayoutDirection.current
    // Square screens draw the time as a straight line across the top. The list's viewport starts
    // below it, so the title (and every row scrolled up) is clipped there instead of passing
    // under the clock. Round screens keep the curved time over the list, as on the other screens.
    val round = LocalConfiguration.current.isScreenRound
    val clockInset = if (round) 0.dp else SQUARE_CLOCK_INSET
    Box(modifier = Modifier.fillMaxSize()) {
    ScreenScaffold(scrollState = listState) { padding ->
        ScalingLazyColumn(
            // The list's own viewport ends a gap above the Save button: rows are clipped there,
            // so no part of a row shows next to or behind the button, and the last row (Discard)
            // scrolls fully clear of it.
            modifier = Modifier
                .fillMaxSize()
                .padding(top = clockInset, bottom = edgeHeight + EDGE_BUTTON_GAP),
            state = listState,
            contentPadding = PaddingValues(
                start = padding.calculateStartPadding(direction),
                top = if (round) maxOf(padding.calculateTopPadding(), 24.dp) else 4.dp,
                end = padding.calculateEndPadding(direction),
                bottom = 8.dp
            ),
            // The list starts at its top (title under the clock) instead of centring a row in
            // the shortened viewport, which pushed the title under the time text.
            autoCentering = null
        ) {
            item { ListHeader { Text(stringResource(R.string.summary), textAlign = TextAlign.Center) } }
            item {
                MetricRow(
                    SummaryCell(
                        WorkoutMath.formatDuration(summary.durationSeconds),
                        stringResource(R.string.label_duration),
                        spokenDuration(summary.durationSeconds)
                    ),
                    SummaryCell(summary.setCount.toString(), stringResource(R.string.label_sets), summary.setCount.toString())
                )
            }
            item {
                val volume = WorkoutMath.formatVolume(summary.volumeKg, loc)
                MetricRow(
                    SummaryCell(
                        stringResource(R.string.weight_kg, volume),
                        stringResource(R.string.label_volume),
                        stringResource(R.string.a11y_kilograms, volume)
                    ),
                    SummaryCell(
                        summary.caloriesKcal?.let { stringResource(R.string.value_kcal, it) } ?: none,
                        stringResource(R.string.calories),
                        summary.caloriesKcal?.let { pluralStringResource(R.plurals.a11y_kcal, it, it) } ?: noData
                    )
                )
            }
            item {
                MetricRow(
                    SummaryCell(
                        summary.averageHeartRate?.let { stringResource(R.string.value_bpm, it) } ?: none,
                        stringResource(R.string.label_avg_hr),
                        summary.averageHeartRate?.let { pluralStringResource(R.plurals.a11y_beats, it, it) } ?: noData,
                        stringResource(R.string.a11y_avg_hr)
                    ),
                    SummaryCell(
                        summary.maxHeartRate?.let { stringResource(R.string.value_bpm, it) } ?: none,
                        stringResource(R.string.label_max_hr),
                        summary.maxHeartRate?.let { pluralStringResource(R.plurals.a11y_beats, it, it) } ?: noData,
                        stringResource(R.string.a11y_max_hr)
                    )
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
    // Save stays on screen from the first view (spec §4.7) instead of appearing only at the end
    // of the list. Under 225dp "Сохранить" would break inside the word, so it is a check mark.
    EdgeButton(
        onClick = onSave,
        enabled = summary.setCount > 0 && !state.isSaving,
        modifier = Modifier.align(Alignment.BottomCenter).onSizeChanged { edgePx = it.height },
        buttonSize = if (large) EdgeButtonSize.Medium else EdgeButtonSize.ExtraSmall
    ) {
        if (large) {
            EdgeLabel(stringResource(R.string.save))
        } else {
            Icon(WatchIcons.Check, contentDescription = stringResource(R.string.save))
        }
    }
    }
    DiscardDialog(visible = confirmDiscard, onKeep = { confirmDiscard = false }, onDiscard = {
        confirmDiscard = false
        onDiscarded()
    })
}

/** A summary cell: what it shows, and what TalkBack reads (label first, then the value). */
private data class SummaryCell(
    val value: String,
    val label: String,
    val spokenValue: String,
    val spokenLabel: String = label
)

@Composable
private fun MetricRow(left: SummaryCell, right: SummaryCell) {
    // A large text size widens the cells into the round bezel near the top and bottom of the
    // list ("Подходь"); an extra side inset keeps them inside it.
    val inset = if (LocalConfiguration.current.isScreenRound && isLargeText()) 8.dp else 0.dp
    // A fixed gap keeps two long labels ("Сред. пульс" / "Макс. пульс") apart on narrow screens.
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = inset),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Metric(left, Modifier.weight(1f))
        Metric(right, Modifier.weight(1f))
    }
}

/**
 * A summary cell reads label first, then a spoken value: "no data" instead of the dash, and a
 * duration in words instead of "12:34", which TalkBack would read as a clock time.
 */
@Composable
private fun Metric(cell: SummaryCell, modifier: Modifier) {
    val (value, label, spokenValue, spokenLabel) = cell
    Column(
        modifier = modifier.clearAndSetSemantics { contentDescription = "$spokenLabel, $spokenValue" },
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(value, style = MaterialTheme.typography.titleLarge.tabular(), maxLines = 1)
        if (isLargeText()) {
            FitText(label, style = MaterialTheme.typography.labelSmall, color = WatchColors.TextSecondary)
        } else {
            Text(
                label,
                style = MaterialTheme.typography.labelSmall,
                color = WatchColors.TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
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
        state.saveOutcome == SaveOutcome.Rejected -> SaveOutcome.Rejected
        state.saveOutcome == SaveOutcome.Deferred || timedOut -> SaveOutcome.Deferred
        else -> SaveOutcome.Sending
    }
    val large = isLargeScreen()
    var edgePx by remember { mutableIntStateOf(0) }
    val edgeHeight = edgeHeightDp(edgePx, if (large) 70.dp else 56.dp)
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
        SaveOutcome.Deferred, SaveOutcome.Rejected -> Box(modifier = Modifier.fillMaxSize()) {
            // Three different reasons, three different texts: the phone is away (waiting helps),
            // the workout belongs to an account that is not signed in on the phone, or the phone
            // answered and refused it.
            val rejected = outcome == SaveOutcome.Rejected
            val held = !rejected && state.workoutOnHold
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(start = 24.dp, end = 24.dp, top = 24.dp, bottom = edgeHeight),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    // Phone with a slash = "the phone is not reachable" (iphone.slash on Apple
                    // Watch); a refusal is a real warning.
                    if (rejected) WatchIcons.Warning else WatchIcons.PhoneSlash,
                    contentDescription = null,
                    tint = WatchColors.Warning,
                    modifier = Modifier.size(if (rejected || held) 22.dp else 28.dp)
                )
                Spacer(Modifier.height(if (rejected || held) 2.dp else 6.dp))
                Text(
                    stringResource(
                        when {
                            rejected -> R.string.send_rejected
                            held -> R.string.queued_hold_body
                            else -> R.string.send_later
                        }
                    ),
                    // The two long explanations use the label size so they fit a 192dp screen.
                    style = if (rejected || held) MaterialTheme.typography.labelSmall
                    else MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center,
                    maxLines = 5,
                    overflow = TextOverflow.Ellipsis
                )
            }
            EdgeButton(
                onClick = onClose,
                modifier = Modifier.align(Alignment.BottomCenter).onSizeChanged { edgePx = it.height },
                buttonSize = edgeSize(large)
            ) {
                EdgeLabel(stringResource(R.string.done))
            }
        }
    }
}

private fun androidx.compose.ui.text.TextStyle.withHyphens() =
    copy(hyphens = Hyphens.Auto, lineBreak = LineBreak.Heading)
