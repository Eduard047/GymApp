package com.example.gymapp.service

import org.junit.Assert.assertEquals
import org.junit.Test

class RestTimerAlarmTriggerTest {
    @Test
    fun futureWallClockDeadlineBecomesTheSameDelayOnTheElapsedClock() {
        val trigger = RestTimerService.elapsedTriggerAt(
            nowElapsedMillis = 5_000L,
            nowWallMillis = 1_700_000_000_000L,
            deadlineWallMillis = 1_700_000_090_000L
        )
        assertEquals(95_000L, trigger)
    }

    @Test
    fun pastDeadlineFiresImmediatelyInsteadOfInThePast() {
        val trigger = RestTimerService.elapsedTriggerAt(
            nowElapsedMillis = 42_000L,
            nowWallMillis = 1_700_000_100_000L,
            deadlineWallMillis = 1_700_000_000_000L
        )
        assertEquals(42_000L, trigger)
    }

    @Test
    fun deadlineExactlyNowFiresNow() {
        assertEquals(
            7L,
            RestTimerService.elapsedTriggerAt(
                nowElapsedMillis = 7L,
                nowWallMillis = 1_000L,
                deadlineWallMillis = 1_000L
            )
        )
    }
}
