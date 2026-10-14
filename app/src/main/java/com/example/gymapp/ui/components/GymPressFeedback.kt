package com.example.gymapp.ui.components

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.PressInteraction
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** DESIGN.md `motion.press`: scale 0.97, in 100 ms ease-out, out `spring-snappy` (stiffness 1000, no bounce). */
internal const val PressedScale = 0.97f
private val PressEaseOut = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)

/**
 * Scales the control to [PressedScale] while [interactionSource] reports a press. The scale is skipped
 * when the system animator duration scale is 0 (the ripple still shows the press).
 */
internal fun Modifier.pressScale(interactionSource: InteractionSource): Modifier = composed {
    val animationsEnabled = !rememberReduceMotion()
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && animationsEnabled) PressedScale else 1f,
        animationSpec = if (pressed) tween(durationMillis = 100, easing = PressEaseOut) else spring(dampingRatio = 1f, stiffness = 1000f),
        label = "pressScale"
    )
    graphicsLayer {
        scaleX = scale
        scaleY = scale
    }
}

/** Platform tap-indication delay: a press inside a scrolling list only shows once it is not a scroll. */
private const val PressIndicationDelayMs = 100L

/**
 * Long-press target that is not a button (a recorded set row, the current set card): shows the ripple
 * from touch-down, like a clickable would, without adding click semantics. Taps do nothing; a long
 * press calls [onLongPress]. Children that consume their own presses keep them.
 */
internal fun Modifier.longPressRipple(enabled: Boolean, onLongPress: () -> Unit): Modifier = composed {
    val interactionSource = remember { MutableInteractionSource() }
    val currentOnLongPress by rememberUpdatedState(onLongPress)
    indication(interactionSource, LocalIndication.current).pointerInput(enabled) {
        if (enabled) {
            detectTapGestures(
                onPress = { offset ->
                    coroutineScope {
                        val press = PressInteraction.Press(offset)
                        val show = launch {
                            delay(PressIndicationDelayMs)
                            interactionSource.emit(press)
                        }
                        val released = tryAwaitRelease()
                        if (show.isActive) {
                            // Released inside the delay: a quick tap still gets its short ripple.
                            show.cancel()
                            if (released) {
                                interactionSource.emit(press)
                                interactionSource.emit(PressInteraction.Release(press))
                            }
                        } else {
                            interactionSource.emit(
                                if (released) PressInteraction.Release(press) else PressInteraction.Cancel(press)
                            )
                        }
                    }
                },
                onLongPress = { currentOnLongPress() }
            )
        }
    }
}

/**
 * Hold-to-repeat schedule of a weight/reps stepper button (DESIGN.md Steppers). A tap is one step
 * (the normal click). A button held past [INITIAL_DELAY_MS] steps at that moment, then at 8 steps per
 * second ([SLOW_INTERVAL_MS]), and at 16 per second ([FAST_INTERVAL_MS]) once the next slow step would
 * land after [ACCELERATE_AT_MS]. Times are milliseconds since touch-down.
 */
internal object StepperHoldRepeat {
    const val INITIAL_DELAY_MS = 350.0
    const val SLOW_INTERVAL_MS = 125.0
    const val FAST_INTERVAL_MS = 62.5
    const val ACCELERATE_AT_MS = 1500.0

    /** The time of the step after the one at [previousStepAtMs]; the first step when it is null. */
    fun nextStepAtMs(previousStepAtMs: Double?): Double = when {
        previousStepAtMs == null -> INITIAL_DELAY_MS
        previousStepAtMs + SLOW_INTERVAL_MS <= ACCELERATE_AT_MS -> previousStepAtMs + SLOW_INTERVAL_MS
        else -> previousStepAtMs + FAST_INTERVAL_MS
    }

    /** Times of every hold step that fires before the finger lifts at [heldForMs] (a step at that instant counts). */
    fun stepTimesMs(heldForMs: Double): List<Double> {
        val times = mutableListOf<Double>()
        var next = nextStepAtMs(null)
        while (next <= heldForMs) {
            times += next
            next = nextStepAtMs(next)
        }
        return times
    }
}
