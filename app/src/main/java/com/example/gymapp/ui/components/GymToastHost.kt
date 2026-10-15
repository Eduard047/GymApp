package com.example.gymapp.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Draggable2DState
import androidx.compose.foundation.gestures.draggable2D
import androidx.compose.foundation.gestures.rememberDraggable2DState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalAccessibilityManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.rememberUpdatedState
import com.example.gymapp.R
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max

/**
 * The toast controller of the running app. The default is a detached controller that no host draws,
 * so previews and tests that never install a host can call it without null checks.
 */
val LocalGymToastController = compositionLocalOf { GymToastController() }

/** Maximum capsule width on wide screens; on phones the 16 dp gutter is the limit. */
internal val GymToastMaxWidth: Dp = 560.dp
internal val GymToastGutter: Dp = 16.dp
private val GymToastEnterOffset: Dp = 14.dp

/**
 * The one root toast host. It owns the countdown (a toast timed out by a sheet host is still timed
 * out here) and draws the toast above [bottomOffset] unless a sheet has taken over with
 * [GymToastSheetHost]. Mount it once, last, over the whole app so it sits above content and the tab bar.
 */
@Composable
fun GymToastHost(
    controller: GymToastController,
    modifier: Modifier = Modifier,
    bottomOffset: Dp = 0.dp,
    glass: HazeState? = null
) {
    val state by controller.state.collectAsState()
    GymToastCountdown(controller, state)
    if (state.sheetHost == null) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .padding(bottom = bottomOffset),
            contentAlignment = Alignment.BottomCenter
        ) {
            GymToastLayer(controller, state, glass)
        }
    }
}

/**
 * Keeps toasts above an open sheet. A `ModalBottomSheet` renders in its own window over the root, so
 * the root host would be hidden behind the sheet and its scrim. While this is composed (the shared
 * `GymModalBottomSheet` composes it) the topmost sheet takes over drawing through a non-focusable
 * [Popup] pinned to the bottom of the sheet window, above its content and the navigation bar. Touches
 * outside the toast reach the sheet underneath.
 */
@Composable
fun GymToastSheetHost() {
    val controller = LocalGymToastController.current
    val host = remember { Any() }
    DisposableEffect(controller, host) {
        controller.registerSheetHost(host)
        onDispose { controller.unregisterSheetHost(host) }
    }
    val state by controller.state.collectAsState()
    if (state.sheetHost !== host) return
    val density = LocalDensity.current
    val bottomMarginPx = with(density) {
        max(
            WindowInsets.navigationBars.getBottom(density),
            WindowInsets.ime.getBottom(density)
        ) + GymToastGutter.roundToPx()
    }
    val positionProvider = remember(bottomMarginPx) { GymToastPopupPositionProvider(bottomMarginPx) }
    Popup(
        popupPositionProvider = positionProvider,
        properties = PopupProperties(
            focusable = false,
            dismissOnBackPress = false,
            dismissOnClickOutside = false,
            clippingEnabled = false
        )
    ) {
        // The sheet is its own window: the app content cannot be blurred behind it, so the toast stays solid.
        GymToastLayer(controller, state, glass = null)
    }
}

/** Bottom-centers the popup in its window, [bottomMarginPx] above the bottom edge. */
internal class GymToastPopupPositionProvider(private val bottomMarginPx: Int) : PopupPositionProvider {
    override fun calculatePosition(
        anchorBounds: IntRect,
        windowSize: IntSize,
        layoutDirection: LayoutDirection,
        popupContentSize: IntSize
    ): IntOffset = IntOffset(
        x = (windowSize.width - popupContentSize.width) / 2,
        y = windowSize.height - popupContentSize.height - bottomMarginPx
    )
}

/** Runs the timeout for the current toast; restarts when the toast changes or the hold is released. */
@Composable
private fun GymToastCountdown(controller: GymToastController, state: GymToastUiState) {
    val toast = state.toast ?: return
    val accessibilityManager = LocalAccessibilityManager.current
    LaunchedEffect(toast.id, state.paused) {
        controller.markShown(toast.id)
        if (state.paused) return@LaunchedEffect
        val remaining = controller.remainingMillis() ?: return@LaunchedEffect
        // TalkBack / switch access users get at least the system's recommended time to reach the action.
        val timeout = accessibilityManager?.calculateRecommendedTimeoutMillis(
            originalTimeoutMillis = remaining,
            containsIcons = false,
            containsText = true,
            containsControls = toast.actionLabel != null
        ) ?: remaining
        delay(timeout)
        controller.dismiss(toast.id)
    }
}

/** The animated slot for the toast: replacement cross-fades and slides, never stacks. */
@Composable
private fun GymToastLayer(controller: GymToastController, state: GymToastUiState, glass: HazeState?) {
    val reduceMotion = rememberReduceMotion()
    val enterOffsetPx = with(LocalDensity.current) { GymToastEnterOffset.roundToPx() }
    AnimatedContent(
        targetState = state.toast,
        contentKey = { it?.id },
        transitionSpec = { gymToastTransition(reduceMotion, enterOffsetPx) },
        label = "gymToast",
        modifier = Modifier.padding(horizontal = GymToastGutter)
    ) { toast ->
        if (toast != null) {
            GymToastCapsule(
                toast = toast,
                glass = glass,
                onTap = { controller.dismiss(toast.id) },
                onAction = { controller.performAction(toast.id) },
                onDismissed = { controller.dismiss(toast.id) },
                onPause = { reason, paused -> controller.setPaused(toast.id, reason, paused) }
            )
        } else {
            Box(Modifier.fillMaxWidth())
        }
    }
}

/**
 * Enter: slide up 14 dp + fade with `spring-standard`. Exit: fade over 90 ms while sinking toward the
 * bottom, so it leaves faster than it arrived. Reduced motion is opacity only (150 ms in, 90 ms out).
 */
internal fun AnimatedContentTransitionScope<*>.gymToastTransition(reduceMotion: Boolean, enterOffsetPx: Int): ContentTransform {
    val enter: EnterTransition = if (reduceMotion) {
        fadeIn(GymMotion.fadeInSpec())
    } else {
        fadeIn(GymMotion.fadeInSpec()) +
            slideInVertically(GymMotion.standardSpring(IntOffset.VisibilityThreshold)) { enterOffsetPx }
    }
    val exit: ExitTransition = if (reduceMotion) {
        fadeOut(GymMotion.fadeOutSpec())
    } else {
        fadeOut(GymMotion.fadeOutSpec()) +
            slideOutVertically(tween(durationMillis = GymMotion.FadeOutMillis)) { enterOffsetPx }
    }
    return (enter togetherWith exit) using SizeTransform(clip = false)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GymToastCapsule(
    toast: GymToast,
    glass: HazeState?,
    onTap: () -> Unit,
    onAction: () -> Unit,
    onDismissed: () -> Unit,
    onPause: (GymToastPauseReason, Boolean) -> Unit
) {
    val colors = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val reduceMotion = rememberReduceMotion()
    val settle = remember(toast.id) { Animatable(Offset.Zero, Offset.VectorConverter) }
    var sizePx by remember(toast.id) { mutableStateOf(IntSize.Zero) }
    val currentOnDismissed by rememberUpdatedState(onDismissed)
    val currentOnPause by rememberUpdatedState(onPause)
    val dragState: Draggable2DState = rememberDraggable2DState { delta ->
        scope.launch {
            settle.snapTo(gymToastClampDrag(settle.value + delta))
        }
    }
    val fadeProgress = gymToastDragProgress(settle.value, sizePx.width.toFloat(), sizePx.height.toFloat())
    val density = LocalDensity.current
    val velocityThresholdPx = with(density) { GymToastDismissVelocity.toPx() }

    // Chip glass blurs the app content behind it (no shadow, hairline kept); otherwise the solid surface.
    val glassActive = rememberGymGlassActive(glass)
    Surface(
        color = if (glassActive) Color.Transparent else colors.surface,
        contentColor = colors.onSurface,
        shape = CircleShape,
        tonalElevation = 0.dp,
        border = BorderStroke(1.dp, colors.outlineVariant),
        modifier = Modifier
            .widthIn(max = GymToastMaxWidth)
            // Outermost, so the shadow travels with the toast while it is dragged.
            .graphicsLayer {
                translationX = settle.value.x
                translationY = settle.value.y
                alpha = 1f - 0.5f * fadeProgress
            }
            .then(
                if (glassActive) {
                    Modifier
                } else {
                    Modifier.shadow(
                        elevation = 6.dp,
                        shape = CircleShape,
                        clip = false,
                        ambientColor = Color.Black.copy(alpha = 0.12f),
                        spotColor = Color.Black.copy(alpha = 0.24f)
                    )
                }
            )
            .gymGlass(glass, GymGlassMaterial.Chip, CircleShape)
            .onSizeChanged { sizePx = it }
            // Holding a finger on the toast holds its countdown; the pass is Initial so drags still reach draggable2D.
            .pointerInput(toast.id) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                    currentOnPause(GymToastPauseReason.Touch, true)
                    do {
                        val event = awaitPointerEvent(PointerEventPass.Initial)
                    } while (event.changes.any { it.pressed })
                    currentOnPause(GymToastPauseReason.Touch, false)
                }
            }
            .draggable2D(
                state = dragState,
                onDragStarted = { scope.launch { settle.stop() } },
                onDragStopped = { velocity ->
                    scope.launch {
                    val outcome = gymToastSwipeOutcome(
                        offset = settle.value,
                        velocity = velocity,
                        width = sizePx.width.toFloat(),
                        height = sizePx.height.toFloat(),
                        velocityThresholdPx = velocityThresholdPx
                    )
                    if (outcome == GymToastSwipeOutcome.Settle) {
                        settle.animateTo(
                            Offset.Zero,
                            if (reduceMotion) GymMotion.fadeInSpec() else GymMotion.standardSpring()
                        )
                    } else {
                        val target = gymToastExitTarget(outcome, sizePx.width.toFloat(), sizePx.height.toFloat())
                        settle.animateTo(target, tween(durationMillis = GymMotion.FadeOutMillis))
                        currentOnDismissed()
                    }
                    }
                }
            )
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier
                .heightIn(min = 48.dp)
                .padding(start = 20.dp, end = if (toast.actionLabel != null) 8.dp else 20.dp)
        ) {
            Text(
                text = toast.message,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f, fill = false)
                    .clickable(onClickLabel = stringResource(R.string.action_close), onClick = onTap)
                    .heightIn(min = 48.dp)
                    .padding(vertical = 14.dp)
                    // Polite live region: announced without stealing focus; the full text reaches
                    // assistive tech even when the visible line is ellipsized.
                    .semantics { liveRegion = LiveRegionMode.Polite }
            )
            val actionLabel = toast.actionLabel
            if (actionLabel != null) {
                TextButton(
                    onClick = onAction,
                    modifier = Modifier
                        .heightIn(min = 48.dp)
                        .onFocusChanged { currentOnPause(GymToastPauseReason.Focus, it.isFocused) }
                ) {
                    Text(actionLabel, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** Swipe past 40% of its own size, or flick faster than 500 dp/s, to dismiss; otherwise spring back. */
internal val GymToastDismissVelocity: Dp = 500.dp
internal const val GymToastDismissFraction = 0.4f

internal enum class GymToastSwipeOutcome { Settle, DismissDown, DismissLeft, DismissRight }

/** Upward drags resist completely; only down or sideways moves the toast. */
internal fun gymToastClampDrag(offset: Offset): Offset = Offset(offset.x, max(0f, offset.y))

/** 0..1 for how far the toast has been dragged, by its dominant axis. */
internal fun gymToastDragProgress(offset: Offset, width: Float, height: Float): Float {
    if (width <= 0f || height <= 0f) return 0f
    return max(abs(offset.x) / (width * GymToastDismissFraction), offset.y / (height * GymToastDismissFraction))
        .coerceIn(0f, 1f)
}

internal fun gymToastSwipeOutcome(
    offset: Offset,
    velocity: Velocity,
    width: Float,
    height: Float,
    velocityThresholdPx: Float
): GymToastSwipeOutcome {
    val horizontal = abs(offset.x) >= offset.y.coerceAtLeast(0f)
    return if (horizontal) {
        val far = abs(offset.x) >= width * GymToastDismissFraction
        val flick = abs(velocity.x) >= velocityThresholdPx && offset.x * velocity.x > 0f
        when {
            !far && !flick -> GymToastSwipeOutcome.Settle
            offset.x > 0f || (offset.x == 0f && velocity.x > 0f) -> GymToastSwipeOutcome.DismissRight
            else -> GymToastSwipeOutcome.DismissLeft
        }
    } else {
        val far = offset.y >= height * GymToastDismissFraction
        val flick = velocity.y >= velocityThresholdPx && offset.y > 0f
        if (far || flick) GymToastSwipeOutcome.DismissDown else GymToastSwipeOutcome.Settle
    }
}

internal fun gymToastExitTarget(outcome: GymToastSwipeOutcome, width: Float, height: Float): Offset = when (outcome) {
    GymToastSwipeOutcome.DismissDown -> Offset(0f, height * 2f)
    GymToastSwipeOutcome.DismissLeft -> Offset(-width * 1.5f, 0f)
    GymToastSwipeOutcome.DismissRight -> Offset(width * 1.5f, 0f)
    GymToastSwipeOutcome.Settle -> Offset.Zero
}
