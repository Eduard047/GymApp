package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WeeklyReviewTest {
    private val zone = ZoneId.of("UTC")
    private val now = Instant.parse("2026-09-04T12:00:00Z").toEpochMilli()

    @Test
    fun comparesBestRepsOnlyAtTheExactSameWeight() {
        val review = WeeklyReview.build(
            listOf(
                row(1, "2026-08-27T12:00:00Z", 1, 50.0, 8),
                row(2, "2026-09-02T12:00:00Z", 1, 50.0, 10),
                row(3, "2026-09-03T12:00:00Z", 1, 55.0, 12)
            ),
            now = now,
            zone = zone
        )

        assertTrue(review.partial)
        assertEquals(2, review.trainingDays)
        assertEquals(1, review.comparableCount)
        assertEquals(2, review.insights.single().current.reps - review.insights.single().previous.reps)
    }

    @Test
    fun ignoresFutureAndInvalidRows() {
        val review = WeeklyReview.build(
            listOf(
                row(1, "2026-09-02T12:00:00Z", 1, 50.0, 8),
                row(2, "2026-09-05T12:00:00Z", 1, 50.0, 9),
                row(3, "2026-09-03T12:00:00Z", 1, Double.NaN, 9)
            ),
            now = now,
            zone = zone
        )

        assertEquals(1, review.sessions.size)
        assertEquals(0, review.comparableCount)
    }

    private fun row(id: Long, date: String, exercise: Long, weight: Double, reps: Int) =
        ExerciseHistoryEntry(id, id, Instant.parse(date).toEpochMilli(), exercise, "Exercise $exercise", weight, reps, 0)
}
