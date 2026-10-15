package com.example.gymapp.ui.components

import android.provider.Settings
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.TweenSpec
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize

/**
 * The DESIGN.md `motion` tokens. Springs for anything that changes layout or is touched; opacity-only
 * fades are 150 ms in and 90 ms out. [standardSpring] and [snappySpring] never bounce (damping 1).
 */
internal object GymMotion {
    const val FadeInMillis = 150
    const val FadeOutMillis = 90

    /** `spring-standard`: expand, layout, selection. */
    fun <T> standardSpring(visibilityThreshold: T? = null): SpringSpec<T> =
        spring(dampingRatio = 1f, stiffness = 440f, visibilityThreshold = visibilityThreshold)

    /** `spring-snappy`: press release, toggles, chevrons. */
    fun <T> snappySpring(visibilityThreshold: T? = null): SpringSpec<T> =
        spring(dampingRatio = 1f, stiffness = 1000f, visibilityThreshold = visibilityThreshold)

    /** `spring-soft`: slow progress sweeps such as the workout ring. */
    fun <T> softSpring(visibilityThreshold: T? = null): SpringSpec<T> =
        spring(dampingRatio = 1f, stiffness = 300f, visibilityThreshold = visibilityThreshold)

    fun <T> fadeInSpec(): TweenSpec<T> = tween(durationMillis = FadeInMillis, easing = FastOutSlowInEasing)

    fun <T> fadeOutSpec(): TweenSpec<T> = tween(durationMillis = FadeOutMillis)
}

/** True when the system animator duration scale is 0 (the "remove animations" setting). */
@Composable
internal fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        runCatching {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) <= 0f
        }.getOrDefault(false)
    }
}

/** Fade + vertical expand with `spring-standard`; reduced motion is the fade alone. */
internal fun gymExpandVertically(reduceMotion: Boolean): EnterTransition =
    if (reduceMotion) {
        fadeIn(GymMotion.fadeInSpec())
    } else {
        fadeIn(GymMotion.fadeInSpec()) + expandVertically(GymMotion.standardSpring(IntSize.VisibilityThreshold))
    }

/** The mirror of [gymExpandVertically]. */
internal fun gymShrinkVertically(reduceMotion: Boolean): ExitTransition =
    if (reduceMotion) {
        fadeOut(GymMotion.fadeOutSpec())
    } else {
        fadeOut(GymMotion.fadeOutSpec()) + shrinkVertically(GymMotion.standardSpring(IntSize.VisibilityThreshold))
    }

/** Fade + horizontal expand with `spring-standard`; reduced motion is the fade alone. */
internal fun gymExpandHorizontally(reduceMotion: Boolean): EnterTransition =
    if (reduceMotion) {
        fadeIn(GymMotion.fadeInSpec())
    } else {
        fadeIn(GymMotion.fadeInSpec()) + expandHorizontally(GymMotion.standardSpring(IntSize.VisibilityThreshold))
    }

/** The mirror of [gymExpandHorizontally]. */
internal fun gymShrinkHorizontally(reduceMotion: Boolean): ExitTransition =
    if (reduceMotion) {
        fadeOut(GymMotion.fadeOutSpec())
    } else {
        fadeOut(GymMotion.fadeOutSpec()) + shrinkHorizontally(GymMotion.standardSpring(IntSize.VisibilityThreshold))
    }

/** Switching between bottom tabs is a crossfade: the destination fades in over the one fading out. */
internal fun gymTabEnter(): EnterTransition = fadeIn(GymMotion.fadeInSpec())

/** The outgoing half of [gymTabEnter]. */
internal fun gymTabExit(): ExitTransition = fadeOut(GymMotion.fadeOutSpec())

/** A pushed screen slides in from the end edge with `spring-standard`; reduced motion is the fade alone. */
internal fun gymDrillEnter(reduceMotion: Boolean): EnterTransition =
    if (reduceMotion) {
        fadeIn(GymMotion.fadeInSpec())
    } else {
        fadeIn(GymMotion.fadeInSpec()) +
            slideInHorizontally(GymMotion.standardSpring(IntOffset.VisibilityThreshold)) { it }
    }

/** The screen underneath a pushed one drifts back a quarter of its width; it stays opaque so no gap opens behind the slide. */
internal fun gymDrillExit(reduceMotion: Boolean): ExitTransition =
    if (reduceMotion) {
        fadeOut(GymMotion.fadeOutSpec())
    } else {
        slideOutHorizontally(GymMotion.standardSpring(IntOffset.VisibilityThreshold)) { -it / 4 }
    }

/** The mirror of [gymDrillExit]: the screen underneath returns from the parallax offset on back. */
internal fun gymDrillPopEnter(reduceMotion: Boolean): EnterTransition =
    if (reduceMotion) {
        fadeIn(GymMotion.fadeInSpec())
    } else {
        fadeIn(GymMotion.fadeInSpec()) +
            slideInHorizontally(GymMotion.standardSpring(IntOffset.VisibilityThreshold)) { -it / 4 }
    }

/** The mirror of [gymDrillEnter]: the popped screen leaves through the end edge. */
internal fun gymDrillPopExit(reduceMotion: Boolean): ExitTransition =
    if (reduceMotion) {
        fadeOut(GymMotion.fadeOutSpec())
    } else {
        slideOutHorizontally(GymMotion.standardSpring(IntOffset.VisibilityThreshold)) { it }
    }
