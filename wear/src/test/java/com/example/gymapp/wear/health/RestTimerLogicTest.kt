package com.example.gymapp.wear.health

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
}
