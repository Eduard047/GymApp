package com.example.gymapp.service

import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Content-intent action carried by the ongoing-workout and rest-timer notifications. */
internal const val ACTION_OPEN_ACTIVE_WORKOUT = "com.setforge.gymapp.action.OPEN_ACTIVE_WORKOUT"

/** How long a tap waits for the active workout to load before it is dropped as stale. */
internal const val OPEN_ACTIVE_WORKOUT_GRACE_MILLIS = 4_000L

/** True only for the exact notification action; any other (or missing) action is ignored. */
internal fun isOpenActiveWorkoutAction(action: String?): Boolean =
    action == ACTION_OPEN_ACTIVE_WORKOUT

/** A restored/recreated activity replays its launch intent; only a fresh launch or new intent counts. */
internal fun shouldRequestOpenActiveWorkout(action: String?, restoredInstance: Boolean): Boolean =
    isOpenActiveWorkoutAction(action) && !restoredInstance

/** Launcher long-press "Start workout" shortcut action (res/xml/shortcuts.xml). */
internal const val ACTION_START_WORKOUT_SHORTCUT = "com.setforge.gymapp.action.START_WORKOUT_SHORTCUT"

/** Time the active-workout flow gets to emit before the shortcut falls back to the editor. */
internal const val START_WORKOUT_SHORTCUT_SETTLE_MILLIS = 700L

internal fun isStartWorkoutShortcutAction(action: String?): Boolean =
    action == ACTION_START_WORKOUT_SHORTCUT

/** Same replay guard as [shouldRequestOpenActiveWorkout]: recreation must not re-run the shortcut. */
internal fun shouldRequestStartWorkoutShortcut(action: String?, restoredInstance: Boolean): Boolean =
    isStartWorkoutShortcutAction(action) && !restoredInstance

internal enum class StartWorkoutShortcutRoute {
    OpenApp,
    OpenActiveWorkout,
    ResumeRetainedEditor,
    OpenWorkoutEditor
}

/**
 * Where the shortcut leads: signed out -> just the app; active draft -> the active workout;
 * an unsaved plan in the retained editor -> reopen it as-is (same as the Today resume path);
 * otherwise the screen the Today "Start workout" button opens (never auto-creates a workout).
 */
internal fun startWorkoutShortcutRoute(
    hasSession: Boolean,
    hasActiveWorkout: Boolean,
    hasRetainedDraft: Boolean = false
): StartWorkoutShortcutRoute = when {
    !hasSession -> StartWorkoutShortcutRoute.OpenApp
    hasActiveWorkout -> StartWorkoutShortcutRoute.OpenActiveWorkout
    hasRetainedDraft -> StartWorkoutShortcutRoute.ResumeRetainedEditor
    else -> StartWorkoutShortcutRoute.OpenWorkoutEditor
}

/**
 * Process-local hand-off from a notification tap to the root UI. A request is only acted on
 * when an active workout exists; otherwise the UI drops it after [OPEN_ACTIVE_WORKOUT_GRACE_MILLIS]
 * so a later workout start never opens the screen unexpectedly.
 */
internal class ActiveWorkoutOpenInbox {
    private val nextId = AtomicLong(0L)
    private val mutablePending = MutableStateFlow<Long?>(null)
    val pending: StateFlow<Long?> = mutablePending.asStateFlow()

    fun request() {
        mutablePending.value = nextId.incrementAndGet()
    }

    fun consume(id: Long) {
        if (mutablePending.value == id) mutablePending.value = null
    }

    fun clear() {
        mutablePending.value = null
    }

    private val nextShortcutId = AtomicLong(0L)
    private val mutableStartShortcut = MutableStateFlow<Long?>(null)
    val startShortcutPending: StateFlow<Long?> = mutableStartShortcut.asStateFlow()

    fun requestStartShortcut() {
        mutableStartShortcut.value = nextShortcutId.incrementAndGet()
    }

    fun consumeStartShortcut(id: Long) {
        if (mutableStartShortcut.value == id) mutableStartShortcut.value = null
    }
}
