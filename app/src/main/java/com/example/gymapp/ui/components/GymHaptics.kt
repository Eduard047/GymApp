package com.example.gymapp.ui.components

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView
import com.example.gymapp.util.HapticsGate
import com.example.gymapp.util.gymHapticAllowed

/**
 * The haptic events of the active-workout core loop. Each one is paired with a visual change at the
 * call site (DESIGN.md `haptics`). Compose 1.7's `HapticFeedbackType` only has LongPress and
 * TextHandleMove, so the platform constants go through [View.performHapticFeedback], which also
 * honors the system touch-feedback setting.
 */
internal enum class GymHapticEvent {
    RecordSet,
    Undo,
    StepperTick,
    StepperRepeatTick,
    DestructiveConfirm,
    Error,
    RestEnd,
    Reorder,
    ReorderPickup,
    /** A long-press that opens a menu. */
    LongPress,
    PersonalRecord
}

/** The [HapticFeedbackConstants] value for [event] on a device running [sdkInt]. */
internal fun gymHapticConstant(event: GymHapticEvent, sdkInt: Int): Int = when (event) {
    GymHapticEvent.RecordSet ->
        if (sdkInt >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
    GymHapticEvent.Undo -> HapticFeedbackConstants.CONTEXT_CLICK
    GymHapticEvent.StepperTick ->
        if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CLOCK_TICK
    GymHapticEvent.StepperRepeatTick ->
        if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            HapticFeedbackConstants.SEGMENT_FREQUENT_TICK
        } else {
            HapticFeedbackConstants.CLOCK_TICK
        }
    GymHapticEvent.Reorder ->
        if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) HapticFeedbackConstants.SEGMENT_TICK else HapticFeedbackConstants.CLOCK_TICK
    GymHapticEvent.ReorderPickup ->
        if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            HapticFeedbackConstants.GESTURE_THRESHOLD_ACTIVATE
        } else {
            HapticFeedbackConstants.LONG_PRESS
        }
    GymHapticEvent.DestructiveConfirm, GymHapticEvent.LongPress, GymHapticEvent.PersonalRecord ->
        HapticFeedbackConstants.LONG_PRESS
    // The foreground rest-end buzz; a notification channel owns the background one, so no Vibrator here.
    GymHapticEvent.RestEnd ->
        if (sdkInt >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS
    GymHapticEvent.Error ->
        if (sdkInt >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
}

/** Allows at most one stepper tick per [minIntervalMs] (100 ms is 10 ticks per second). */
internal class HapticThrottle(private val minIntervalMs: Long = STEPPER_MIN_INTERVAL_MS) {
    private var lastMs: Long = Long.MIN_VALUE

    fun tryAcquire(nowMs: Long): Boolean {
        if (lastMs != Long.MIN_VALUE && nowMs - lastMs < minIntervalMs) return false
        lastMs = nowMs
        return true
    }

    companion object {
        const val STEPPER_MIN_INTERVAL_MS = 100L
    }
}

internal class GymHaptics(private val view: View) {
    private val stepperThrottle = HapticThrottle()
    private val reorderThrottle = HapticThrottle()

    fun perform(event: GymHapticEvent) {
        if (!gymHapticAllowed(HapticsGate.enabled)) return
        view.performHapticFeedback(gymHapticConstant(event, Build.VERSION.SDK_INT))
    }

    /** A stepper step; [repeating] while a held button auto-repeats. Throttled to 10 per second. */
    fun stepperTick(repeating: Boolean) {
        if (!gymHapticAllowed(HapticsGate.enabled)) return
        if (!stepperThrottle.tryAcquire(android.os.SystemClock.uptimeMillis())) return
        perform(if (repeating) GymHapticEvent.StepperRepeatTick else GymHapticEvent.StepperTick)
    }

    /** A drag-to-reorder slot change. Throttled to 10 per second. */
    fun reorderTick() {
        if (!gymHapticAllowed(HapticsGate.enabled)) return
        if (!reorderThrottle.tryAcquire(android.os.SystemClock.uptimeMillis())) return
        perform(GymHapticEvent.Reorder)
    }
}

@Composable
internal fun rememberGymHaptics(): GymHaptics {
    val view = LocalView.current
    return remember(view) { GymHaptics(view) }
}
