package com.example.gymapp.ui.components

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The DESIGN.md "Toasts and banners" contract, as plain Kotlin with no Android or Compose types so
 * it can be unit tested on the JVM: one toast at a time (a new toast replaces the current one),
 * 4 s without an action and 6 s with one, a countdown that pauses while the person is touching or
 * focusing the toast, and a stack of hosts so exactly one of them (the root host, or the host of
 * the topmost open sheet) draws the toast.
 */
internal const val GymToastShortMillis = 4_000L
internal const val GymToastWithActionMillis = 6_000L

/** [Auto] is 4 s, or 6 s with an action; [Indefinite] stays until dismissed, replaced or acted on. */
enum class GymToastDuration { Auto, Indefinite }

enum class GymToastResult { ActionPerformed, Dismissed }

/** Why the countdown is held. Each reason is tracked on its own so one releasing cannot resume the other. */
enum class GymToastPauseReason { Touch, Focus }

data class GymToast(
    val id: Long,
    val message: String,
    val actionLabel: String?,
    /** Null means the toast has no timeout. */
    val durationMillis: Long?
)

internal fun gymToastDurationMillis(hasAction: Boolean, duration: GymToastDuration): Long? = when {
    duration == GymToastDuration.Indefinite -> null
    hasAction -> GymToastWithActionMillis
    else -> GymToastShortMillis
}

internal class GymToastShown(val toast: GymToast, val replaced: GymToast?)

/**
 * The single toast slot and its countdown. All times are caller supplied milliseconds on any
 * monotonic clock, which keeps pause/resume arithmetic deterministic under test.
 */
internal class GymToastSlot {
    var current: GymToast? = null
        private set
    private var nextId = 1L
    private var remainingMillis = 0L
    private var runningSince: Long? = null
    private var started = false
    private val pauseReasons = mutableSetOf<GymToastPauseReason>()

    val isPaused: Boolean get() = pauseReasons.isNotEmpty()

    /** Replaces whatever is showing. A fresh toast starts un-paused and un-started. */
    fun show(
        message: String,
        actionLabel: String?,
        duration: GymToastDuration
    ): GymToastShown {
        val replaced = current
        val toast = GymToast(
            id = nextId++,
            message = message,
            actionLabel = actionLabel,
            durationMillis = gymToastDurationMillis(actionLabel != null, duration)
        )
        current = toast
        remainingMillis = toast.durationMillis ?: 0L
        runningSince = null
        started = false
        pauseReasons.clear()
        return GymToastShown(toast, replaced)
    }

    /** Starts the countdown once a host actually draws the toast, so one posted before any host exists is not lost. */
    fun markShown(id: Long, nowMillis: Long) {
        val toast = current ?: return
        if (toast.id != id || started) return
        started = true
        if (toast.durationMillis != null && pauseReasons.isEmpty()) runningSince = nowMillis
    }

    fun setPaused(id: Long, reason: GymToastPauseReason, paused: Boolean, nowMillis: Long): Boolean {
        val toast = current ?: return false
        if (toast.id != id) return false
        val wasPaused = pauseReasons.isNotEmpty()
        if (paused) pauseReasons.add(reason) else pauseReasons.remove(reason)
        val isNowPaused = pauseReasons.isNotEmpty()
        if (toast.durationMillis != null && started) {
            when {
                !wasPaused && isNowPaused -> {
                    remainingMillis = remainingAt(nowMillis) ?: 0L
                    runningSince = null
                }
                wasPaused && !isNowPaused -> runningSince = nowMillis
            }
        }
        return wasPaused != isNowPaused
    }

    /** Milliseconds left on the countdown, or null when there is nothing to count down. */
    fun remainingAt(nowMillis: Long): Long? {
        val toast = current ?: return null
        if (toast.durationMillis == null) return null
        val since = runningSince ?: return remainingMillis
        return (remainingMillis - (nowMillis - since)).coerceAtLeast(0L)
    }

    /** Removes the toast only when [id] is still the one showing. Returns it, or null when it was already gone. */
    fun dismiss(id: Long): GymToast? {
        val toast = current ?: return null
        if (toast.id != id) return null
        return clear()
    }

    fun clear(): GymToast? {
        val toast = current
        current = null
        runningSince = null
        remainingMillis = 0L
        started = false
        pauseReasons.clear()
        return toast
    }
}

/**
 * Which host draws the toast. The root host draws it unless a sheet has registered a host, in which
 * case the topmost (last registered) sheet host does, because a sheet lives in its own window above
 * the root.
 */
internal class GymToastHostStack {
    private val sheetHosts = mutableListOf<Any>()

    val top: Any? get() = sheetHosts.lastOrNull()

    fun register(host: Any) {
        sheetHosts.remove(host)
        sheetHosts.add(host)
    }

    fun unregister(host: Any) {
        sheetHosts.remove(host)
    }
}

/** What hosts render: the toast, whether its countdown is held, and which sheet host (null = root) draws it. */
data class GymToastUiState(
    val toast: GymToast? = null,
    val paused: Boolean = false,
    val sheetHost: Any? = null
)

/**
 * App-level toast controller, provided at the root through `LocalGymToastController`.
 *
 * [show] suspends until the toast is acted on, dismissed, replaced, timed out, or the caller is
 * cancelled (which dismisses it), so call sites read like the Snackbar API they replace. [post] is
 * the fire-and-forget form for callers outside Compose, such as the Activity.
 */
class GymToastController internal constructor(
    private val clock: () -> Long
) {
    constructor() : this({ System.nanoTime() / 1_000_000L })

    private val lock = Any()
    private val slot = GymToastSlot()
    private val hostStack = GymToastHostStack()
    private val results = HashMap<Long, CompletableDeferred<GymToastResult>>()
    private val mutableState = MutableStateFlow(GymToastUiState())

    val state: StateFlow<GymToastUiState> = mutableState.asStateFlow()

    suspend fun show(
        message: String,
        actionLabel: String? = null,
        duration: GymToastDuration = GymToastDuration.Auto
    ): GymToastResult {
        val (id, result) = enqueue(message, actionLabel, duration)
        try {
            return result.await()
        } finally {
            dismiss(id)
        }
    }

    fun post(message: String, actionLabel: String? = null) {
        enqueue(message, actionLabel, GymToastDuration.Auto)
    }

    fun performAction(id: Long) = finish(id, GymToastResult.ActionPerformed)

    fun dismiss(id: Long) = finish(id, GymToastResult.Dismissed)

    fun dismissCurrent() {
        val id = synchronized(lock) { slot.current?.id } ?: return
        dismiss(id)
    }

    /** Drops any toast without a result, for an account switch where the old caller no longer matters. */
    fun clear() {
        synchronized(lock) {
            slot.clear()
            completeAll(GymToastResult.Dismissed)
            publish()
        }
    }

    /** Called by the host that draws the toast; starts the countdown. */
    fun markShown(id: Long) {
        synchronized(lock) {
            slot.markShown(id, clock())
            publish()
        }
    }

    fun setPaused(id: Long, reason: GymToastPauseReason, paused: Boolean) {
        synchronized(lock) {
            if (slot.setPaused(id, reason, paused, clock())) publish()
        }
    }

    /** Milliseconds until the toast times out, or null for no toast or no timeout. */
    fun remainingMillis(): Long? = synchronized(lock) { slot.remainingAt(clock()) }

    fun registerSheetHost(host: Any) {
        synchronized(lock) {
            hostStack.register(host)
            publish()
        }
    }

    fun unregisterSheetHost(host: Any) {
        synchronized(lock) {
            hostStack.unregister(host)
            publish()
        }
    }

    private fun enqueue(
        message: String,
        actionLabel: String?,
        duration: GymToastDuration
    ): Pair<Long, CompletableDeferred<GymToastResult>> = synchronized(lock) {
        val shown = slot.show(message, actionLabel, duration)
        shown.replaced?.let { results.remove(it.id)?.complete(GymToastResult.Dismissed) }
        val result = CompletableDeferred<GymToastResult>()
        results[shown.toast.id] = result
        publish()
        shown.toast.id to result
    }

    private fun finish(id: Long, result: GymToastResult) {
        synchronized(lock) {
            val removed = slot.dismiss(id)
            if (removed != null) {
                results.remove(id)?.complete(result)
                publish()
            }
        }
    }

    private fun completeAll(result: GymToastResult) {
        results.values.forEach { it.complete(result) }
        results.clear()
    }

    private fun publish() {
        mutableState.value = GymToastUiState(
            toast = slot.current,
            paused = slot.isPaused,
            sheetHost = hostStack.top
        )
    }
}
