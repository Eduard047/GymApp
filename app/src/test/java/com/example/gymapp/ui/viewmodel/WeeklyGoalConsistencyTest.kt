package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.WeeklyReview
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Today ("Goal: x of y") and Progress ("x of y" in the weekly review) count training days from two
 * sources: workout session summaries and set history. For sessions that have sets they must agree.
 */
class WeeklyGoalConsistencyTest {
    private val zone = ZoneId.of("Europe/Kyiv")

    private fun millis(iso: String) = Instant.parse(iso).toEpochMilli()

    private fun summary(id: Long, date: Long, sets: Int = 3) = WorkoutSessionSummary(
        session = WorkoutSessionEntity(id = id, date = date, note = null),
        exerciseCount = if (sets > 0) 1 else 0,
        setCount = sets,
        totalVolume = sets * 100.0
    )

    private fun history(sessionId: Long, date: Long) = ExerciseHistoryEntry(
        setId = sessionId,
        sessionId = sessionId,
        sessionDate = date,
        exerciseId = 1L,
        exerciseName = "Bench Press",
        weight = 60.0,
        reps = 8,
        setOrderIndex = 0
    )

    @Test
    fun agreeForSessionsWithSetsAcrossMonthBoundaryAndAtNow() {
        // Thursday 2026-10-01; the week started on Monday 2026-09-28 (previous month).
        val now = millis("2026-10-01T12:00:00Z")
        val dates = listOf(
            millis("2026-09-29T08:00:00Z"),
            millis("2026-09-30T20:30:00Z"),
            now, // finished right now: date == now is included by both
            millis("2026-10-01T15:00:00Z"), // later today: excluded by both
            millis("2026-09-27T18:00:00Z") // Sunday 21:00 local, previous week
        )
        val sessions = dates.mapIndexed { index, date -> summary(index + 1L, date) }
        val history = dates.mapIndexed { index, date -> history(index + 1L, date) }

        val today = buildWeeklyTrainingSummary(sessions, targetTrainingDays = 4, nowMillis = now, zoneId = zone)
        val review = WeeklyReview.build(history, offset = 0, now = now, zone = zone)

        assertEquals(3, today.completedTrainingDays)
        assertEquals(today.completedTrainingDays, review.trainingDays)
    }

    @Test
    fun twoSessionsOnOneLocalDayCountOnceInBoth() {
        val now = millis("2026-10-01T12:00:00Z")
        val dates = listOf(millis("2026-09-30T05:00:00Z"), millis("2026-09-30T18:00:00Z"))
        val today = buildWeeklyTrainingSummary(
            dates.mapIndexed { i, d -> summary(i + 1L, d) }, 4, now, zone
        )
        val review = WeeklyReview.build(dates.mapIndexed { i, d -> history(i + 1L, d) }, 0, now, zone)

        assertEquals(1, today.completedTrainingDays)
        assertEquals(2, today.completedWorkoutCount)
        assertEquals(1, review.trainingDays)
    }

    @Test
    fun onlyActivityWithoutSetsCanMakeTodayCountHigherThanProgress() {
        val now = millis("2026-10-01T12:00:00Z")
        val withSets = millis("2026-09-29T08:00:00Z")
        val activityOnly = millis("2026-09-30T08:00:00Z")
        val today = buildWeeklyTrainingSummary(
            listOf(summary(1, withSets), summary(2, activityOnly, sets = 0)), 4, now, zone
        )
        val review = WeeklyReview.build(listOf(history(1, withSets)), 0, now, zone)

        assertEquals(2, today.completedTrainingDays)
        assertEquals(1, review.trainingDays)
    }
}
