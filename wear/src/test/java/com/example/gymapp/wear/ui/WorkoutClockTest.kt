package com.example.gymapp.wear.ui

import com.example.gymapp.wear.sync.SyncPaths
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutClockTest {
    private val start = 1_700_000_000_000L

    @Test
    fun elapsedCountsWallClockSecondsFromTheStart() {
        val clock = WorkoutClock(startedAt = start)
        assertEquals(0L, clock.elapsedSeconds(start))
        assertEquals(90L, clock.elapsedSeconds(start + 90_999L))
    }

    @Test
    fun pausedTimeIsExcludedWhileThePauseIsOpenAndAfterResume() {
        val paused = WorkoutClock(startedAt = start).pause(start + 60_000L)
        assertTrue(paused.isPaused)
        // Ten minutes into the pause the workout is still one minute long.
        assertEquals(60L, paused.elapsedSeconds(start + 660_000L))

        val resumed = paused.resume(start + 660_000L)
        assertFalse(resumed.isPaused)
        assertEquals(600_000L, resumed.pausedTotalMs)
        assertEquals(start, resumed.startedAt)
        assertEquals(90L, resumed.elapsedSeconds(start + 690_000L))
    }

    @Test
    fun aRestoredOpenPauseKeepsExcludingTimeAcrossAProcessDeath() {
        // What the draft storage brings back: one earlier pause of 30 s and a pause still open.
        val restored = WorkoutClock(startedAt = start, pausedTotalMs = 30_000L, pausedAtMs = start + 120_000L)
        assertEquals(90L, restored.elapsedSeconds(start + 3_600_000L))
        assertEquals(100L, restored.resume(start + 3_600_000L).elapsedSeconds(start + 3_610_000L))
    }

    @Test
    fun repeatedPauseAndResumeAreIdempotent() {
        val paused = WorkoutClock(startedAt = start).pause(start + 5_000L)
        assertSame(paused, paused.pause(start + 9_000L))
        val running = paused.resume(start + 9_000L)
        assertSame(running, running.resume(start + 20_000L))
        assertEquals(4_000L, running.pausedTotalMs)
    }

    @Test
    fun clockChangesNeverProduceNegativeOrOversizedDurations() {
        val clock = WorkoutClock(startedAt = start)
        // Wall clock moved back before the start, or a pause "ending" before it began.
        assertEquals(0L, clock.elapsedSeconds(start - 5_000L))
        assertEquals(0L, clock.pause(start + 10_000L).resume(start + 4_000L).pausedTotalMs)
        // A draft found days later is capped at the protocol's duration bound.
        assertEquals(SyncPaths.MAX_DURATION_SECONDS, clock.elapsedSeconds(start + 5L * 86_400_000L))
    }
}
