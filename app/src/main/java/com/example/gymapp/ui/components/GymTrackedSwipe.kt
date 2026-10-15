package com.example.gymapp.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitHorizontalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.horizontalDrag
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.sign
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** What a finished horizontal swipe does to a week or month navigator. A drag to the right goes back in time. */
internal enum class TrackedSwipeResult { Previous, Next, Stay }

/** DESIGN.md "Sheets": a drag commits past 40% of the width, or when released faster than 0.5 dp/ms. */
internal const val TrackedSwipeCommitFraction = 0.4f
internal const val TrackedSwipeCommitVelocityDpPerSecond = 500f

/**
 * The commit decision of a tracked swipe. [offsetPx] is the finger travel (positive = right), [velocityPxPerSecond]
 * the release velocity, [widthPx] the width of the swiped surface and [density] converts the dp velocity threshold.
 * A direction the navigator cannot go ([canPrevious] / [canNext]) never commits. A fling against the drag
 * direction does not commit the drag.
 */
internal fun trackedSwipeResult(
    offsetPx: Float,
    velocityPxPerSecond: Float,
    widthPx: Float,
    canPrevious: Boolean,
    canNext: Boolean,
    density: Float
): TrackedSwipeResult {
    if (widthPx <= 0f || offsetPx == 0f) return TrackedSwipeResult.Stay
    val direction = sign(offsetPx)
    val travelled = abs(offsetPx) >= widthPx * TrackedSwipeCommitFraction
    val flung = sign(velocityPxPerSecond) == direction &&
        abs(velocityPxPerSecond) >= TrackedSwipeCommitVelocityDpPerSecond * density
    if (!travelled && !flung) return TrackedSwipeResult.Stay
    return if (direction > 0f) {
        if (canPrevious) TrackedSwipeResult.Previous else TrackedSwipeResult.Stay
    } else {
        if (canNext) TrackedSwipeResult.Next else TrackedSwipeResult.Stay
    }
}

/**
 * Rubber-band resistance for a drag toward a direction that cannot be taken: the offset grows less and
 * less per pixel and never passes [limit] (the Apple scroll-edge curve with c = 0.55).
 */
internal fun trackedSwipeRubberBand(offsetPx: Float, limit: Float): Float {
    if (limit <= 0f || offsetPx == 0f) return 0f
    val x = abs(offsetPx)
    return sign(offsetPx) * (1f - 1f / (x * 0.55f / limit + 1f)) * limit
}

/** The on-screen offset for a finger travel of [travelPx]: 1:1 where the swipe can commit, rubber-banded where it cannot. */
internal fun trackedSwipeDisplayOffset(
    travelPx: Float,
    widthPx: Float,
    canPrevious: Boolean,
    canNext: Boolean
): Float {
    val allowed = if (travelPx > 0f) canPrevious else canNext
    return if (allowed) {
        travelPx.coerceIn(-widthPx, widthPx)
    } else {
        trackedSwipeRubberBand(travelPx, widthPx * 0.25f)
    }
}

/**
 * Finger-following horizontal swipe for week and month navigation. [offset] is the content's
 * translation in px: apply it with `graphicsLayer { translationX = offset }` to the content that
 * should follow the finger, and put [gesture] on the surface that listens. The drag is interruptible
 * (a new touch stops the spring and continues from where the content is), releases with
 * `spring-momentum` from the release velocity, and starts at least 16 dp from either edge so system
 * back gestures are never overridden. With reduced motion nothing translates: the swipe only
 * commits. The navigation buttons stay as the accessible alternative.
 */
@Stable
internal class GymTrackedSwipeState internal constructor(
    private val animatable: Animatable<Float, *>,
    val gesture: Modifier
) {
    val offset: Float get() = animatable.value
}

@Composable
internal fun rememberGymTrackedSwipe(
    canPrevious: Boolean,
    canNext: Boolean,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    key: Any? = null
): GymTrackedSwipeState {
    val reduceMotion = rememberReduceMotion()
    val density = LocalDensity.current.density
    val scope = rememberCoroutineScope()
    val animatable = remember { Animatable(0f) }
    val currentCanPrevious by rememberUpdatedState(canPrevious)
    val currentCanNext by rememberUpdatedState(canNext)
    val currentOnPrevious by rememberUpdatedState(onPrevious)
    val currentOnNext by rememberUpdatedState(onNext)
    val gesture = Modifier.pointerInput(reduceMotion, key) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            val edge = 16.dp.toPx()
            if (down.position.x < edge || down.position.x > size.width - edge) return@awaitEachGesture
            val width = size.width.toFloat()
            val tracker = VelocityTracker()
            tracker.addPosition(down.uptimeMillis, down.position)
            var travel = if (reduceMotion) 0f else animatable.value
            val drag = awaitHorizontalTouchSlopOrCancellation(down.id) { change, over ->
                change.consume()
                travel += over
            } ?: return@awaitEachGesture
            scope.launch { animatable.stop() }
            if (!reduceMotion) {
                scope.snapTo(animatable, trackedSwipeDisplayOffset(travel, width, currentCanPrevious, currentCanNext))
            }
            val completed = horizontalDrag(drag.id) { change ->
                // Read the delta before consuming: a consumed change reports no position change.
                travel += change.positionChange().x
                tracker.addPosition(change.uptimeMillis, change.position)
                change.consume()
                if (!reduceMotion) {
                    scope.snapTo(animatable, trackedSwipeDisplayOffset(travel, width, currentCanPrevious, currentCanNext))
                }
            }
            val velocity = if (completed) tracker.calculateVelocity().x else 0f
            val result = if (completed) {
                trackedSwipeResult(travel, velocity, width, currentCanPrevious, currentCanNext, density)
            } else {
                TrackedSwipeResult.Stay
            }
            when (result) {
                TrackedSwipeResult.Previous -> currentOnPrevious()
                TrackedSwipeResult.Next -> currentOnNext()
                TrackedSwipeResult.Stay -> Unit
            }
            if (!reduceMotion) {
                scope.launch {
                    animatable.animateTo(0f, GymMotion.momentumSpring(), initialVelocity = velocity)
                }
            }
        }
    }
    return remember(animatable, gesture) { GymTrackedSwipeState(animatable, gesture) }
}

private fun CoroutineScope.snapTo(animatable: Animatable<Float, *>, value: Float) {
    launch { animatable.snapTo(value) }
}
