package com.example.gymapp.ui.components

import androidx.compose.animation.core.animate
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DragIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.example.gymapp.ui.theme.GymPanelShape
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/*
 * Drag-to-reorder for the exercise cards of a LazyColumn (plan editor and active workout).
 *
 * The state holder keeps the in-memory key order while a card is dragged; the screen renders the
 * list through [ExerciseReorderState.displayed], so neighbours part through `animateItem` while the
 * persisted order stays untouched. Exactly one write ([onCommit]) happens on drop. The dragged card
 * is translated by the finger inside its own graphicsLayer (scale, lifted shadow, drawn on top).
 */

/** Pixel bounds of one visible list item. */
internal data class ReorderBounds(val top: Float, val size: Float)

/** [order] with [key] moved to [toIndex], or the same list for an unknown key or an out-of-range index. */
internal fun <K> reorderedKeys(order: List<K>, key: K, toIndex: Int): List<K> {
    val from = order.indexOf(key)
    if (from < 0 || toIndex !in order.indices || toIndex == from) return order
    return order.toMutableList().apply { add(toIndex, removeAt(from)) }
}

/**
 * The slot the dragged item moves to, or null when it stays: it swaps with the next neighbour once
 * its centre is below that neighbour's midpoint and with the previous one once it is above the
 * previous neighbour's midpoint. Neighbours that are not laid out ([boundsOf] null) never swap.
 */
internal fun <K> dragSlotTarget(
    order: List<K>,
    key: K,
    draggedCentre: Float,
    boundsOf: (K) -> ReorderBounds?
): Int? {
    val position = order.indexOf(key)
    if (position < 0) return null
    if (position < order.lastIndex) {
        val next = boundsOf(order[position + 1])
        if (next != null && draggedCentre > next.top + next.size / 2f) return position + 1
    }
    if (position > 0) {
        val previous = boundsOf(order[position - 1])
        if (previous != null && draggedCentre < previous.top + previous.size / 2f) return position - 1
    }
    return null
}

/**
 * Pixels to scroll this frame (negative = up): zero outside the [edge] bands at the top and bottom of
 * the viewport, growing linearly with how deep the finger is inside a band, capped at [maxStep].
 */
internal fun autoScrollStep(
    fingerY: Float,
    viewportTop: Float,
    viewportBottom: Float,
    edge: Float,
    maxStep: Float
): Float {
    if (edge <= 0f || viewportBottom <= viewportTop) return 0f
    val topDepth = viewportTop + edge - fingerY
    if (topDepth > 0f) return -(topDepth / edge).coerceAtMost(1f) * maxStep
    val bottomDepth = fingerY - (viewportBottom - edge)
    if (bottomDepth > 0f) return (bottomDepth / edge).coerceAtMost(1f) * maxStep
    return 0f
}

private const val PickupScale = 0.02f
private const val PendingOrderTimeoutMs = 1500L

@Stable
internal class ExerciseReorderState(
    private val listState: LazyListState,
    private val scope: CoroutineScope,
    private val haptics: GymHaptics,
    private val edgePx: Float,
    private val maxScrollStepPx: Float,
    private val shadowPx: Float
) {
    var reduceMotion: Boolean = false
    var shadowColor: Color = Color.Black

    /** Key of the card being dragged or settling back into its slot; null otherwise. */
    var draggedKey: Any? by mutableStateOf(null)
        private set

    /** In-memory key order while dragging and until the persisted order catches up; empty when idle. */
    var order: List<Any> by mutableStateOf(emptyList())
        private set

    private var held by mutableStateOf(false)
    private var pickupSource: List<Any> = emptyList()
    private var startTop = 0f
    private var startFingerY = 0f
    private var fingerY by mutableFloatStateOf(0f)
    private var lift by mutableFloatStateOf(0f)
    private var settleTranslation by mutableFloatStateOf(0f)
    private var lastTranslation = 0f
    private var viewportTop = 0f
    private var viewportBottom = 0f
    private var loopJob: Job? = null
    private var settleJob: Job? = null
    private var liftJob: Job? = null
    private var onCommit: ((Any, Int) -> Unit)? = null

    /** True while a card is held, settling, or waiting for the persisted order (neighbours animate fast). */
    val isActive: Boolean get() = draggedKey != null

    val isPending: Boolean get() = order.isNotEmpty() && draggedKey == null

    fun updateViewport(top: Float, bottom: Float) {
        viewportTop = top
        viewportBottom = bottom
    }

    /** [source] reordered by the in-memory order while a drag (or its pending write) is in flight. */
    fun <T> displayed(source: List<T>, keyOf: (T) -> Any): List<T> {
        val current = order
        if (current.isEmpty()) return source
        val byKey = source.associateBy(keyOf)
        if (byKey.size != current.size || !current.all(byKey::containsKey)) return source
        return current.map(byKey::getValue)
    }

    /** Called with the persisted key order whenever it changes (and when the pending state starts). */
    fun onSourceChanged(source: List<Any>) {
        if (held) {
            // The data changed under the drag (exercise added/removed/moved elsewhere): snap back.
            if (source != pickupSource) cancel()
            return
        }
        if (isPending) {
            if (source == order || source.toSet() != order.toSet()) order = emptyList()
        }
    }

    /** Gives up on a persisted order that never arrived (a refused write): fall back to the stored order. */
    fun expirePending() {
        if (isPending) order = emptyList()
    }

    fun begin(key: Any, source: List<Any>, fingerRootY: Float, commit: (Any, Int) -> Unit) {
        if (draggedKey != null || order.isNotEmpty() || source.size < 2) return
        val info = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == key } ?: return
        settleJob?.cancel()
        liftJob?.cancel()
        pickupSource = source
        order = source
        startTop = info.offset.toFloat()
        startFingerY = fingerRootY
        fingerY = fingerRootY
        lastTranslation = 0f
        settleTranslation = 0f
        lift = 0f
        onCommit = commit
        draggedKey = key
        held = true
        haptics.perform(GymHapticEvent.ReorderPickup)
        if (!reduceMotion) {
            liftJob = scope.launch {
                animate(0f, 1f, animationSpec = spring(dampingRatio = 1f, stiffness = 1000f)) { value, _ ->
                    lift = value
                }
            }
        }
        loopJob?.cancel()
        loopJob = scope.launch {
            while (isActive && held) {
                withFrameNanos { }
                if (!held) break
                autoScroll()
                updateSlot()
            }
        }
    }

    fun dragTo(key: Any, fingerRootY: Float) {
        if (held && draggedKey == key) fingerY = fingerRootY
    }

    /** Finger lifted: commits one write when the slot changed, then settles the card into its slot. */
    fun end() {
        val key = draggedKey
        if (!held || key == null) return
        val residual = translationFor(key)
        val from = pickupSource.indexOf(key)
        val to = order.indexOf(key)
        settleTranslation = residual
        held = false
        loopJob?.cancel()
        if (from >= 0 && to >= 0 && from != to) {
            onCommit?.invoke(key, to)
        } else {
            // Dropped on its own slot: nothing to persist, the plain stored order applies.
            order = emptyList()
        }
        onCommit = null
        settle()
    }

    /** [cancel] only while a card is held (a settling card or a pending write is left alone). */
    fun cancelHeld() {
        if (held) cancel()
    }

    fun cancelHeld(key: Any) {
        if (draggedKey == key) cancelHeld()
    }

    /** Aborts without a write (pointer cancel, backgrounded, live room appeared, data changed). */
    fun cancel() {
        if (draggedKey == null) return
        held = false
        loopJob?.cancel()
        settleJob?.cancel()
        liftJob?.cancel()
        lift = 0f
        settleTranslation = 0f
        order = emptyList()
        onCommit = null
        draggedKey = null
    }

    private fun settle() {
        liftJob?.cancel()
        settleJob?.cancel()
        if (reduceMotion) {
            lift = 0f
            settleTranslation = 0f
            draggedKey = null
            return
        }
        val spec = spring<Float>(dampingRatio = 0.8f, stiffness = 320f)
        settleJob = scope.launch {
            coroutineScope {
                launch { animate(lift, 0f, animationSpec = spec) { value, _ -> lift = value } }
                launch { animate(settleTranslation, 0f, animationSpec = spec) { value, _ -> settleTranslation = value } }
            }
            draggedKey = null
        }
    }

    private suspend fun autoScroll() {
        val step = autoScrollStep(fingerY, viewportTop, viewportBottom, edgePx, maxScrollStepPx)
        if (step != 0f) listState.scrollBy(step)
    }

    private fun updateSlot() {
        val key = draggedKey ?: return
        val infos = listState.layoutInfo.visibleItemsInfo
        val dragged = infos.firstOrNull { it.key == key } ?: return
        val centre = startTop + (fingerY - startFingerY) + dragged.size / 2f
        val target = dragSlotTarget(order, key, centre) { other ->
            infos.firstOrNull { it.key == other }?.let { ReorderBounds(it.offset.toFloat(), it.size.toFloat()) }
        } ?: return
        order = reorderedKeys(order, key, target)
        haptics.reorderTick()
    }

    /** Vertical translation of the dragged card: finger-following while held, the settle spring after. */
    fun translationFor(key: Any): Float {
        if (!held) return settleTranslation
        val info = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == key } ?: return lastTranslation
        val translation = startTop + (fingerY - startFingerY) - info.offset
        lastTranslation = translation
        return translation
    }

    fun applyTo(layer: GraphicsLayerScope, key: Any) {
        if (draggedKey != key) return
        layer.translationY = translationFor(key)
        val scale = 1f + PickupScale * lift
        layer.scaleX = scale
        layer.scaleY = scale
        layer.shadowElevation = shadowPx * lift
        layer.shape = GymPanelShape
        layer.clip = false
        layer.ambientShadowColor = shadowColor
        layer.spotShadowColor = shadowColor
    }
}

@Composable
internal fun rememberExerciseReorderState(listState: LazyListState): ExerciseReorderState {
    val scope = rememberCoroutineScope()
    val haptics = rememberGymHaptics()
    val density = LocalDensity.current
    val reduceMotion = rememberReduceMotion()
    val dark = isSystemInDarkTheme()
    val state = remember(listState) {
        ExerciseReorderState(
            listState = listState,
            scope = scope,
            haptics = haptics,
            edgePx = with(density) { 64.dp.toPx() },
            maxScrollStepPx = with(density) { 12.dp.toPx() },
            shadowPx = with(density) { 8.dp.toPx() }
        )
    }
    SideEffect {
        state.reduceMotion = reduceMotion
        state.shadowColor = if (dark) Color.Black.copy(alpha = 0.40f) else Color(0xFF10233F).copy(alpha = 0.16f)
    }
    // Backgrounding or leaving the screen mid-drag snaps back without a write.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, state) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) state.cancel()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            state.cancel()
        }
    }
    return state
}

/**
 * Keeps [state] in sync with the persisted key order [sourceKeys] and drops the drag when
 * [enabled] turns false (a live room appeared, the editor locked).
 */
@Composable
internal fun ExerciseReorderSync(state: ExerciseReorderState, sourceKeys: List<Any>, enabled: Boolean) {
    LaunchedEffect(sourceKeys, state.isPending) { state.onSourceChanged(sourceKeys) }
    LaunchedEffect(state.isPending) {
        if (state.isPending) {
            delay(PendingOrderTimeoutMs)
            state.expirePending()
        }
    }
    LaunchedEffect(enabled) { if (!enabled) state.cancelHeld() }
}

/** Marks the LazyColumn whose bounds define the autoscroll bands. */
internal fun Modifier.exerciseReorderViewport(state: ExerciseReorderState): Modifier =
    onGloballyPositioned { coordinates ->
        val bounds = coordinates.boundsInRoot()
        state.updateViewport(bounds.top, bounds.bottom)
    }

/**
 * Per-card modifier: the dragged card follows the finger, scaled and lifted above its siblings.
 * Combine with `animateItem(placementSpec = ...)` on the same item (null spec for the dragged card).
 */
internal fun Modifier.exerciseReorderItem(state: ExerciseReorderState, key: Any): Modifier =
    zIndex(if (state.draggedKey == key) 1f else 0f)
        .graphicsLayer { state.applyTo(this, key) }

/**
 * The grip at the leading edge of a card header: pressing it and moving starts the drag at once (no
 * long press). It has no semantics (screen readers use the move actions), at least 48dp tall.
 */
@Composable
internal fun ExerciseDragHandle(
    state: ExerciseReorderState,
    itemKey: Any,
    sourceKeys: List<Any>,
    enabled: Boolean,
    onCommit: (Any, Int) -> Unit,
    modifier: Modifier = Modifier
) {
    var coordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    val currentSourceKeys by rememberUpdatedState(sourceKeys)
    val currentCommit by rememberUpdatedState(onCommit)
    DisposableEffect(state, itemKey) {
        onDispose { if (state.draggedKey == itemKey) state.cancelHeld() }
    }
    // A drag whose handle gets disabled mid-gesture (the pointer loop restarts) would stay held forever.
    LaunchedEffect(enabled) { if (!enabled && state.draggedKey == itemKey) state.cancelHeld() }
    Box(
        modifier = modifier
            .size(width = 48.dp, height = 48.dp)
            .onGloballyPositioned { coordinates = it }
            .pointerInput(itemKey, enabled) {
                if (!enabled) return@pointerInput
                detectDragGestures(
                    onDragStart = { offset ->
                        val rootY = coordinates?.takeIf { it.isAttached }?.localToRoot(offset)?.y
                        if (rootY != null) {
                            state.begin(itemKey, currentSourceKeys, rootY) { key, to -> currentCommit(key, to) }
                        }
                    },
                    onDrag = { change, _ ->
                        change.consume()
                        coordinates?.takeIf { it.isAttached }?.let { state.dragTo(itemKey, it.localToRoot(change.position).y) }
                    },
                    onDragEnd = { if (state.draggedKey == itemKey) state.end() },
                    onDragCancel = { state.cancelHeld(itemKey) }
                )
            }
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = Icons.Rounded.DragIndicator,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
