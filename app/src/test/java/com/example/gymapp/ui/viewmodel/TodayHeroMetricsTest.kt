package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import org.junit.Assert.assertEquals
import org.junit.Test

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

    private fun summary(id: Long, volume: Double) = WorkoutSessionSummary(
        session = WorkoutSessionEntity(id = id, date = 1_787_000_000_000, note = null),
        exerciseCount = 1,
        setCount = 1,
        totalVolume = volume
    )
}
