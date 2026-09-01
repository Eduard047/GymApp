package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class TodayHeroMetricsTest {
    @Test
    fun usesOnlyCanonicalCompletedSummariesAndBoundsVolume() {
        val sessions = listOf(
            summary(id = 1, volume = 1_250.5),
            summary(id = 2, volume = Double.NaN),
            summary(id = 3, volume = -50.0),
            summary(id = 4, volume = 2_000_000_000_000_000.0)
        )

        assertEquals(
            TodayHeroMetricsUiModel(
                totalWorkouts = 4,
                weeklyStreakWeeks = 0,
                totalVolume = 1_000_000_000_000_000.0
            ),
            buildTodayHeroMetrics(sessions, weeklyStreakWeeks = -3)
        )
    }

    @Test
    fun weeklySummaryUsesMondayCirclesCompletedSessionsAndNinetyMinuteEstimateCap() {
        val zoneId = ZoneId.of("UTC")
        val now = LocalDate.of(2026, 8, 15).atTime(12, 0).atZone(zoneId).toInstant().toEpochMilli()
        val sessions = listOf(
            summary(
                1,
                100.0,
                LocalDate.of(2026, 8, 10),
                zoneId,
                exercises = 2,
                sets = 3,
                durationSeconds = 95L
            ),
            summary(
                2,
                200.0,
                LocalDate.of(2026, 8, 15),
                zoneId,
                exercises = 10,
                sets = 40,
                note = "Garmin · Duration 62:03"
            ),
            summary(3, Double.NaN, LocalDate.of(2026, 8, 15), zoneId, exercises = 1, sets = 5),
            summary(4, 400.0, LocalDate.of(2026, 8, 9), zoneId, exercises = 1, sets = 1),
            summary(
                id = 5,
                volume = 500.0,
                date = LocalDate.of(2026, 8, 15),
                zoneId = zoneId,
                exercises = 1,
                sets = 1,
                hour = 18
            )
        )

        val summary = buildWeeklyTrainingSummary(sessions, 4, now, zoneId)

        assertEquals(7, summary.days.size)
        assertEquals(LocalDate.of(2026, 8, 10), summary.days.first().date)
        assertEquals(LocalDate.of(2026, 8, 16), summary.days.last().date)
        assertTrue(summary.days[0].isCompleted)
        assertTrue(summary.days[5].isCompleted)
        assertTrue(summary.days[5].isToday)
        assertFalse(summary.days[6].isCompleted)
        assertEquals(3, summary.completedWorkoutCount)
        assertEquals(2, summary.completedTrainingDays)
        assertEquals(4, summary.targetTrainingDays)
        assertEquals(78, summary.estimatedMinutes)
        assertEquals(300.0, summary.totalVolume, 0.0)
    }

    @Test
    fun weeklySummarySelectsHistoricalWeekAndClampsFutureOffsetsToCurrentWeek() {
        val zoneId = ZoneId.of("UTC")
        val now = LocalDate.of(2026, 8, 15).atTime(12, 0).atZone(zoneId).toInstant().toEpochMilli()
        val sessions = listOf(
            summary(1, 100.0, LocalDate.of(2026, 8, 5), zoneId),
            summary(2, 200.0, LocalDate.of(2026, 8, 12), zoneId),
            summary(3, 300.0, LocalDate.of(2026, 8, 15), zoneId, hour = 18)
        )

        val previousWeek = buildWeeklyTrainingSummary(
            sessions = sessions,
            targetTrainingDays = 4,
            nowMillis = now,
            zoneId = zoneId,
            weekOffset = -1
        )
        val futureRequest = buildWeeklyTrainingSummary(
            sessions = sessions,
            targetTrainingDays = 4,
            nowMillis = now,
            zoneId = zoneId,
            weekOffset = 1
        )

        assertEquals(LocalDate.of(2026, 8, 3), previousWeek.days.first().date)
        assertEquals(LocalDate.of(2026, 8, 9), previousWeek.days.last().date)
        assertEquals(listOf(1L), previousWeek.workouts.map { it.session.id })
        assertEquals(1, previousWeek.completedTrainingDays)
        assertFalse(previousWeek.days.any { it.isToday })
        assertEquals(LocalDate.of(2026, 8, 10), futureRequest.days.first().date)
        assertEquals(listOf(2L), futureRequest.workouts.map { it.session.id })
    }

    @Test
    fun todayCompletionIgnoresFutureRowsAndDurationEstimateIsBounded() {
        val zoneId = ZoneId.of("UTC")
        val today = LocalDate.of(2026, 8, 15)
        val now = today.atTime(12, 0).atZone(zoneId).toInstant().toEpochMilli()

        assertFalse(
            hasCompletedWorkoutToday(
                listOf(summary(1, 0.0, today, zoneId, hour = 18)),
                now,
                zoneId
            )
        )
        assertTrue(
            hasCompletedWorkoutToday(
                listOf(summary(1, 0.0, today, zoneId, hour = 8)),
                now,
                zoneId
            )
        )
        assertEquals(10, estimateWorkoutMinutes(exerciseCount = -1, setCount = -1))
        assertEquals(0, estimateWorkoutMinutes(exerciseCount = 6, setCount = 18, measuredDurationSeconds = 0))
        assertEquals(90, estimateWorkoutMinutes(exerciseCount = Int.MAX_VALUE, setCount = Int.MAX_VALUE))
        assertEquals(
            63,
            estimateWorkoutMinutes(
                exerciseCount = Int.MAX_VALUE,
                setCount = Int.MAX_VALUE,
                measuredDurationSeconds = 3_723L
            )
        )
        assertEquals(
            90,
            estimateWorkoutMinutes(
                exerciseCount = Int.MAX_VALUE,
                setCount = Int.MAX_VALUE,
                measuredDurationSeconds = Long.MAX_VALUE
            )
        )
    }

    @Test
    fun dashboardStatsReuseLoadedSessionsWithoutChangingCurrentMonthSemantics() {
        val zoneId = ZoneId.of("UTC")
        val now = LocalDate.of(2026, 8, 15)
            .atTime(12, 0)
            .atZone(zoneId)
            .toInstant()
            .toEpochMilli()
        val sessions = listOf(
            summary(1, 100.0, LocalDate.of(2026, 8, 15), zoneId, sets = 2),
            summary(2, 300.0, LocalDate.of(2026, 8, 14), zoneId, sets = 3),
            summary(3, 200.0, LocalDate.of(2026, 8, 12), zoneId, sets = 1)
        )

        val stats = buildDashboardStatsForMonth(
            monthOffset = 0,
            targetWorkoutsPerWeek = 2,
            monthSessions = sessions,
            allSessions = sessions,
            nowMillis = now,
            zoneId = zoneId
        )

        assertEquals(3, stats.workoutCount)
        assertEquals(600.0, stats.totalVolume, 0.0)
        assertEquals(100.0, stats.averageIntensity, 0.0)
        assertEquals(2, stats.streakDays)
        assertEquals(1, stats.weeklyStreakWeeks)
    }

    private fun summary(
        id: Long,
        volume: Double,
        date: LocalDate = LocalDate.of(2026, 8, 15),
        zoneId: ZoneId = ZoneId.of("UTC"),
        exercises: Int = 1,
        sets: Int = 1,
        hour: Int = 8,
        note: String? = null,
        durationSeconds: Long? = null
    ) = WorkoutSessionSummary(
        session = WorkoutSessionEntity(
            id = id,
            date = date.atTime(hour, 0).atZone(zoneId).toInstant().toEpochMilli(),
            note = note,
            durationSeconds = durationSeconds
        ),
        exerciseCount = exercises,
        setCount = sets,
        totalVolume = volume
    )
}
