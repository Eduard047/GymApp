package com.example.gymapp.wear.health

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RestTimerLogicTest {
    @Test
    fun countsDownFromTheDefaultAndFinishesExactlyOnce() {
        val timer = RestTimerLogic()
        assertEquals(0, timer.remainingSeconds(0))
        assertFalse(timer.pollFinished(0))

        timer.start(nowMs = 1_000, seconds = RestTimerLogic.DEFAULT_REST_SECONDS)
        assertTrue(timer.isRunning)
        assertEquals(90, timer.remainingSeconds(1_000))
        assertEquals(60, timer.remainingSeconds(31_000))
        assertEquals(1, timer.remainingSeconds(90_500))
        assertFalse(timer.pollFinished(90_999))

        assertTrue(timer.pollFinished(91_000))
        assertFalse(timer.pollFinished(91_001))
        assertFalse(timer.isRunning)
        assertEquals(0, timer.remainingSeconds(95_000))
    }

    @Test
    fun addsFifteenSecondsOnlyWhileRunningAndCapsTheTotal() {
        val timer = RestTimerLogic()
        timer.addSeconds(0)
        assertFalse(timer.isRunning)

        timer.start(0, 60)
        timer.addSeconds(10_000)
        assertEquals(65, timer.remainingSeconds(10_000))

        repeat(100) { timer.addSeconds(10_000) }
        assertEquals(RestTimerLogic.MAX_REST_SECONDS, timer.remainingSeconds(10_000))
    }

    @Test
    fun skipStopsWithoutFiring() {
        val timer = RestTimerLogic()
        timer.start(0, 30)
        timer.skip()
        assertFalse(timer.isRunning)
        assertEquals(0, timer.remainingSeconds(1_000))
        assertFalse(timer.pollFinished(60_000))
    }

    @Test
    fun restartReplacesTheRunningCountdown() {
        val timer = RestTimerLogic()
        timer.start(0, 30)
        timer.start(20_000, 90)
        assertEquals(90, timer.remainingSeconds(20_000))
        assertFalse(timer.pollFinished(30_000))
    }

    @Test
    fun startClampsAbsurdDurations() {
        val timer = RestTimerLogic()
        timer.start(0, Int.MAX_VALUE)
        assertEquals(RestTimerLogic.MAX_REST_SECONDS, timer.remainingSeconds(0))
        timer.start(0, -5)
        assertEquals(1, timer.remainingSeconds(0))
    }
    @Test
    fun aRestIsStoredAsAWallClockEndOnlyWhileTimeIsLeft() {
        assertEquals(1_000_045_000L, RestTimerLogic.wallClockEnd(nowWallMs = 1_000_000_000L, remainingMs = 45_000L))
        assertNull(RestTimerLogic.wallClockEnd(nowWallMs = 1_000_000_000L, remainingMs = 0L))
    }

    @Test
    fun aRestoredRestContinuesToItsStoredEnd() {
        val now = 1_700_000_000_000L
        // Draft with a rest deadline 40 s ahead restores 40 s.
        val remaining = RestTimerLogic.restoredRemainingMs(now + 40_000L, now)
        assertEquals(40_000L, remaining)
        val timer = RestTimerLogic()
        timer.startRemaining(nowMs = 5_000L, remainingMs = remaining)
        assertEquals(40, timer.remainingSeconds(5_000L))
        assertFalse(timer.pollFinished(44_999L))
        assertTrue(timer.pollFinished(45_000L))
    }

    @Test
    fun aRestWhoseEndPassedWhileTheAppWasGoneIsNotRestored() {
        val now = 1_700_000_000_000L
        assertEquals(0L, RestTimerLogic.restoredRemainingMs(now - 1L, now))
        assertEquals(0L, RestTimerLogic.restoredRemainingMs(now, now))
        assertEquals(0L, RestTimerLogic.restoredRemainingMs(null, now))
    }

    @Test
    fun aClockThatMovedBackNeverRestoresMoreThanTheLongestRest() {
        val now = 1_700_000_000_000L
        assertEquals(
            RestTimerLogic.MAX_REST_SECONDS * 1_000L,
            RestTimerLogic.restoredRemainingMs(now + 3_600_000L, now)
        )
    }

    @Test
    fun aPausedRestIsRestoredOnlyWithinRange() {
        assertEquals(47, RestTimerLogic.restoredPausedSeconds(47))
        assertEquals(0, RestTimerLogic.restoredPausedSeconds(0))
        assertEquals(0, RestTimerLogic.restoredPausedSeconds(-3))
        assertEquals(0, RestTimerLogic.restoredPausedSeconds(RestTimerLogic.MAX_REST_SECONDS + 1))
    }

    @Test
    fun remainingMillisecondsFollowTheDeadline() {
        val timer = RestTimerLogic()
        assertEquals(0L, timer.remainingMs(0L))
        timer.start(nowMs = 1_000L, seconds = 30)
        assertEquals(29_500L, timer.remainingMs(1_500L))
        assertEquals(0L, timer.remainingMs(60_000L))
    }

    @Test
    fun theRestEndVibrationIsOwedOnlyForTheScheduledRest() {
        assertTrue(RestEndAlarm.shouldDeliver(scheduledToken = 42L, token = 42L))
        // Already claimed by the ticker (or the alarm), cancelled, or replaced by a newer rest.
        assertFalse(RestEndAlarm.shouldDeliver(scheduledToken = null, token = 42L))
        assertFalse(RestEndAlarm.shouldDeliver(scheduledToken = 43L, token = 42L))
        assertFalse(RestEndAlarm.shouldDeliver(scheduledToken = 0L, token = 0L))
    }
}
