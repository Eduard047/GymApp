package com.example.gymapp.data.repository

import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

class WeeklyStreakCalculatorTest {
    private val zoneId = ZoneId.of("UTC")

    @Test
    fun historicalMonthKeepsTheBestStreakReachedInsideThatMonth() {
        val sessions = listOf(
            date(2026, 6, 1),
            date(2026, 6, 2),
            date(2026, 6, 4),
            date(2026, 6, 9),
            date(2026, 6, 11),
            date(2026, 6, 12),
            date(2026, 6, 15),
            date(2026, 6, 16)
        )

        assertEquals(
            2,
            WeeklyStreakCalculator.bestDuringPeriod(
                sessionTimestamps = sessions,
                periodStartMillis = date(2026, 6, 1),
                periodEndMillis = date(2026, 6, 30, endOfDay = true),
                zoneId = zoneId
            )
        )
    }

    @Test
    fun currentStreakStillUsesTheLatestSuccessfulWeek() {
        val sessions = listOf(
            date(2026, 6, 1),
            date(2026, 6, 2),
            date(2026, 6, 4),
            date(2026, 6, 9),
            date(2026, 6, 11),
            date(2026, 6, 12)
        )

        assertEquals(
            0,
            WeeklyStreakCalculator.current(
                sessionTimestamps = sessions,
                nowMillis = date(2026, 7, 23),
                zoneId = zoneId
            )
        )
    }

    @Test
    fun workoutsWithoutAThreeSessionWeekDoNotCreateAWeeklyStreak() {
        val sessions = listOf(date(2026, 6, 1), date(2026, 6, 9))

        assertEquals(
            0,
            WeeklyStreakCalculator.bestDuringPeriod(
                sessionTimestamps = sessions,
                periodStartMillis = date(2026, 6, 1),
                periodEndMillis = date(2026, 6, 30, endOfDay = true),
                zoneId = zoneId
            )
        )
    }

    private fun date(
        year: Int,
        month: Int,
        day: Int,
        endOfDay: Boolean = false
    ): Long {
        val start = LocalDate.of(year, month, day).atStartOfDay(zoneId).toInstant().toEpochMilli()
        return if (endOfDay) start + 86_400_000L - 1 else start
    }
}
