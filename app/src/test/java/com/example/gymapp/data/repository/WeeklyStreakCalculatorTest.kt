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
                targetWorkoutsPerWeek = 3,
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
                targetWorkoutsPerWeek = 3,
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
                targetWorkoutsPerWeek = 3,
                periodStartMillis = date(2026, 6, 1),
                periodEndMillis = date(2026, 6, 30, endOfDay = true),
                zoneId = zoneId
            )
        )
    }

    @Test
    fun duplicateSessionsOnOneLocalDayCountOnce() {
        val monday = date(2026, 6, 1)
        val sessions = listOf(
            monday,
            monday + 3_600_000L,
            date(2026, 6, 2),
            date(2026, 6, 8),
            date(2026, 6, 9)
        )

        assertEquals(
            2,
            WeeklyStreakCalculator.current(
                sessionTimestamps = sessions,
                targetWorkoutsPerWeek = 2,
                nowMillis = date(2026, 6, 9),
                zoneId = zoneId
            )
        )
        assertEquals(
            0,
            WeeklyStreakCalculator.current(
                sessionTimestamps = listOf(monday, monday + 3_600_000L),
                targetWorkoutsPerWeek = 2,
                nowMillis = date(2026, 6, 2),
                zoneId = zoneId
            )
        )
    }

    @Test
    fun currentPartialWeekAndRestDaysDoNotBreakTheCompletedWeeklyStreak() {
        val sessions = listOf(
            date(2026, 6, 1),
            date(2026, 6, 3),
            date(2026, 6, 8),
            date(2026, 6, 10),
            date(2026, 6, 15)
        )

        assertEquals(
            2,
            WeeklyStreakCalculator.current(
                sessionTimestamps = sessions,
                targetWorkoutsPerWeek = 2,
                nowMillis = date(2026, 6, 17),
                zoneId = zoneId
            )
        )
    }

    @Test
    fun localTimezoneControlsTheTrainingDayAndMondayBoundary() {
        val kyiv = ZoneId.of("Europe/Kyiv")
        val sundayUtc = LocalDate.of(2026, 6, 7)
            .atTime(21, 30)
            .atZone(ZoneId.of("UTC"))
            .toInstant()
            .toEpochMilli()
        val mondayKyiv = LocalDate.of(2026, 6, 8)
            .atStartOfDay(kyiv)
            .toInstant()
            .toEpochMilli()

        val rhythm = WeeklyTrainingRhythmCalculator.calculate(
            sessionTimestamps = listOf(sundayUtc, mondayKyiv + 60_000L),
            targetTrainingDays = 2,
            recoveryRecommended = false,
            nowMillis = mondayKyiv + 3_600_000L,
            zoneId = kyiv
        )

        assertEquals(1, rhythm.completedTrainingDays)
        assertEquals(WeeklyTrainingDecision.Train, rhythm.decision)
    }

    @Test
    fun rhythmHonorsTargetsAndKeepsRestDaysAdvisory() {
        val timestamps = listOf(
            date(2026, 6, 1),
            date(2026, 6, 2),
            date(2026, 6, 3),
            date(2026, 6, 4)
        )
        val now = date(2026, 6, 5)

        val restRhythm = WeeklyTrainingRhythmCalculator.calculate(
            timestamps,
            4,
            false,
            now,
            zoneId
        )
        assertEquals(WeeklyTrainingDecision.Rest, restRhythm.decision)
        assertEquals(date(2026, 6, 8), restRhythm.nextRecommendedDayMillis)
        val recoveryRhythm = WeeklyTrainingRhythmCalculator.calculate(
            timestamps,
            6,
            true,
            now,
            zoneId
        )
        assertEquals(WeeklyTrainingDecision.Recovery, recoveryRhythm.decision)
        assertEquals(now, recoveryRhythm.nextRecommendedDayMillis)
        assertEquals(
            WeeklyTrainingDecision.Train,
            WeeklyTrainingRhythmCalculator.calculate(timestamps, 6, false, now, zoneId).decision
        )
    }

    @Test
    fun futureSessionsCannotCompleteCurrentOrHistoricalWeek() {
        val monday = date(2026, 6, 1)
        val now = monday + 12 * 3_600_000L
        val futureSameWeek = date(2026, 6, 2)

        assertEquals(
            0,
            WeeklyStreakCalculator.current(
                sessionTimestamps = listOf(monday, futureSameWeek),
                targetWorkoutsPerWeek = 2,
                nowMillis = now,
                zoneId = zoneId
            )
        )
        assertEquals(
            WeeklyTrainingDecision.Train,
            WeeklyTrainingRhythmCalculator.calculate(
                sessionTimestamps = listOf(monday, now + 3_600_000L),
                targetTrainingDays = 2,
                recoveryRecommended = false,
                nowMillis = now,
                zoneId = zoneId
            ).decision
        )
        assertEquals(
            0,
            WeeklyStreakCalculator.bestDuringPeriod(
                sessionTimestamps = listOf(monday, futureSameWeek),
                targetWorkoutsPerWeek = 2,
                periodStartMillis = monday,
                periodEndMillis = now,
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
