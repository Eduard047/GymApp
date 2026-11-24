package com.example.gymapp.wear.health

import kotlin.math.ceil

/**
 * Deadline-based rest countdown. It stores an absolute end time, so a slow ticker, a
 * recomposition or a brief pause of the process never drifts the remaining time. The clock is
 * passed in (monotonic milliseconds) to keep the logic unit-testable.
 */
class RestTimerLogic {
    private var endAtMs: Long? = null
    private var finishedPending = false

    val isRunning: Boolean get() = endAtMs != null

    fun start(nowMs: Long, seconds: Int) {
        val clamped = seconds.coerceIn(1, MAX_REST_SECONDS)
        endAtMs = nowMs + clamped * 1_000L
        finishedPending = false
    }

    /** Restarts a timer with an exact remainder (a rest brought back after a restart). */
    fun startRemaining(nowMs: Long, remainingMs: Long) {
        endAtMs = nowMs + remainingMs.coerceIn(1L, MAX_REST_SECONDS * 1_000L)
        finishedPending = false
    }

    /** Extends a running timer; ignored when nothing is running. Total is capped. */
    fun addSeconds(nowMs: Long, seconds: Int = REST_STEP_SECONDS) {
        val end = endAtMs ?: return
        val cap = nowMs + MAX_REST_SECONDS * 1_000L
        endAtMs = (end + seconds * 1_000L).coerceAtMost(cap)
        finishedPending = false
    }

    fun skip() {
        endAtMs = null
        finishedPending = false
    }

    fun remainingSeconds(nowMs: Long): Int {
        val end = endAtMs ?: return 0
        return ceil((end - nowMs) / 1_000.0).toInt().coerceAtLeast(0)
    }

    /** Milliseconds left on a running timer; 0 when idle or already elapsed. */
    fun remainingMs(nowMs: Long): Long {
        val end = endAtMs ?: return 0L
        return (end - nowMs).coerceAtLeast(0L)
    }

    /**
     * True exactly once when a running timer has elapsed; the timer is then idle again. The
     * caller vibrates on true.
     */
    fun pollFinished(nowMs: Long): Boolean {
        val end = endAtMs ?: return false
        if (nowMs < end) return false
        endAtMs = null
        return true
    }

    companion object {
        const val DEFAULT_REST_SECONDS = 90
        const val REST_STEP_SECONDS = 15
        const val MIN_REST_SECONDS = 15
        const val MAX_REST_SECONDS = 900

        /** Wall-clock end (epoch ms) of a rest with [remainingMs] left, as stored in the draft. */
        fun wallClockEnd(nowWallMs: Long, remainingMs: Long): Long? =
            if (remainingMs > 0L) nowWallMs + remainingMs else null

        /**
         * Rest left after a restart, from the stored wall-clock end. 0 when nothing was stored or
         * the end already passed (no countdown and no vibration then). A clock that moved back
         * can never yield more than the longest rest.
         */
        fun restoredRemainingMs(endsAtWallMs: Long?, nowWallMs: Long): Long {
            val end = endsAtWallMs ?: return 0L
            if (end <= nowWallMs) return 0L
            return (end - nowWallMs).coerceAtMost(MAX_REST_SECONDS * 1_000L)
        }

        /** Rest left while paused, as stored; out-of-range values mean no rest. */
        fun restoredPausedSeconds(storedSeconds: Int): Int =
            storedSeconds.takeIf { it in 1..MAX_REST_SECONDS } ?: 0
    }
}
