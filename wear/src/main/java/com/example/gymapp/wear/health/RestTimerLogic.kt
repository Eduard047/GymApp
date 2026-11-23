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
    }
}
