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
}
