package com.example.gymapp.wear.ui

import com.example.gymapp.wear.sync.SyncPaths

/**
 * Wall-clock bookkeeping of one workout: when it started, how long it has been paused in total
 * and whether a pause is open right now. Immutable and persisted with the draft, so a process
 * death neither loses the start time nor counts paused time as training.
 */
data class WorkoutClock(
    val startedAt: Long,
    val pausedTotalMs: Long = 0L,
    val pausedAtMs: Long? = null
) {
    val isPaused: Boolean get() = pausedAtMs != null

    fun pause(nowMs: Long): WorkoutClock = if (isPaused) this else copy(pausedAtMs = nowMs)

    fun resume(nowMs: Long): WorkoutClock {
        val pausedAt = pausedAtMs ?: return this
        return copy(
            pausedTotalMs = pausedTotalMs + (nowMs - pausedAt).coerceAtLeast(0L),
            pausedAtMs = null
        )
    }

    /** Training time so far, without pauses, clamped to the protocol's duration bounds. */
    fun elapsedSeconds(nowMs: Long): Long {
        val openPause = pausedAtMs?.let { (nowMs - it).coerceAtLeast(0L) } ?: 0L
        return ((nowMs - startedAt - pausedTotalMs.coerceAtLeast(0L) - openPause) / 1_000L)
            .coerceIn(0L, SyncPaths.MAX_DURATION_SECONDS)
    }
}
