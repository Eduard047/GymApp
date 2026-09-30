package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.ui.screens.formatPostWorkoutRecordValue
import com.example.gymapp.ui.screens.postWorkoutSubtitle
import com.example.gymapp.util.DateTimeUtils
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class PostWorkoutSummaryFormattingTest {
    private val bench = 1L
    private val squat = 2L
    private val currentId = 10L
    private val currentDate = 2_000L

    private var nextSetId = 0L

    private fun entry(
        exerciseId: Long,
        weight: Double,
        reps: Int,
        sessionId: Long,
        sessionDate: Long
    ) = ExerciseHistoryEntry(
        setId = nextSetId++,
        sessionId = sessionId,
        sessionDate = sessionDate,
        exerciseId = exerciseId,
        exerciseName = "Exercise $exerciseId",
        weight = weight,
        reps = reps,
        setOrderIndex = 0
    )

    private fun past(exerciseId: Long, weight: Double, reps: Int) =
        entry(exerciseId, weight, reps, sessionId = 1L, sessionDate = 1_000L)

    private fun today(exerciseId: Long, weight: Double, reps: Int) =
        entry(exerciseId, weight, reps, sessionId = currentId, sessionDate = currentDate)

    private fun records(session: List<ExerciseHistoryEntry>, history: List<ExerciseHistoryEntry>) =
        buildPostWorkoutPersonalRecords(
            sessionEntries = session,
            allHistory = history + session,
            currentSessionId = currentId,
            currentSessionDate = currentDate
        )

    @Test
    fun firstSessionOfAnExerciseIsNeverARecord() {
        assertTrue(records(listOf(today(bench, 60.0, 8)), history = emptyList()).isEmpty())
    }

    @Test
    fun zeroKilogramsIsNeverARecord() {
        val result = records(listOf(today(bench, 0.0, 20)), history = listOf(past(bench, 0.0, 10)))
        assertTrue(result.isEmpty())
    }

    @Test
    fun tiesWithThePreviousBestAreNotRecords() {
        val result = records(listOf(today(bench, 60.0, 8)), history = listOf(past(bench, 60.0, 8)))
        assertTrue(result.isEmpty())
    }

    @Test
    fun heavierWeightAndBetterEstimateBothAreReported() {
        val result = records(listOf(today(bench, 60.0, 8)), history = listOf(past(bench, 50.0, 8)))
        assertEquals(1, result.size)
        assertEquals(60.0, result[0].weight!!, 1e-9)
        assertEquals(60.0 * (1 + 8 / 30.0), result[0].estimatedOneRepMax!!, 1e-9)
    }

    @Test
    fun betterEstimateAloneCarriesNoWeight() {
        // Same top weight as before, but more reps: only the estimated 1RM improves.
        val result = records(listOf(today(bench, 60.0, 12)), history = listOf(past(bench, 60.0, 8)))
        assertEquals(1, result.size)
        assertNull(result[0].weight)
        assertEquals(60.0 * (1 + 12 / 30.0), result[0].estimatedOneRepMax!!, 1e-9)
    }

    @Test
    fun heavierWeightAloneCarriesNoEstimateWhenRepsDropped() {
        // 100 x 1 -> 103.3 estimate; previous 80 x 12 -> 112 estimate. Weight beats, estimate does not.
        val result = records(listOf(today(bench, 100.0, 1)), history = listOf(past(bench, 80.0, 12)))
        assertEquals(1, result.size)
        assertEquals(100.0, result[0].weight!!, 1e-9)
        assertNull(result[0].estimatedOneRepMax)
    }

    @Test
    fun oneRowPerExerciseInWorkoutOrder() {
        val result = records(
            listOf(today(squat, 100.0, 5), today(bench, 60.0, 8), today(bench, 62.5, 6)),
            history = listOf(past(squat, 90.0, 5), past(bench, 50.0, 8))
        )
        assertEquals(listOf(squat, bench), result.map { it.exerciseId })
        assertEquals(62.5, result[1].weight!!, 1e-9)
    }

    @Test
    fun laterSessionsDoNotCountAsPreviousHistory() {
        val later = entry(bench, 200.0, 5, sessionId = 99L, sessionDate = 9_000L)
        val result = records(
            listOf(today(bench, 60.0, 8)),
            history = listOf(past(bench, 50.0, 8), later)
        )
        assertEquals(1, result.size)
    }

    @Test
    fun recordValuesShowAtMostOneDecimalInTheAppLocale() {
        assertEquals("60", formatPostWorkoutRecordValue(60.0, Locale.ENGLISH))
        assertEquals("72.5", formatPostWorkoutRecordValue(72.5, Locale.ENGLISH))
        assertEquals("72,5", formatPostWorkoutRecordValue(72.5, Locale("uk")))
        assertEquals("72,5", formatPostWorkoutRecordValue(72.5, Locale("ru")))
        assertEquals("72", formatPostWorkoutRecordValue(72.04, Locale.ENGLISH))
    }

    @Test
    fun subtitleAddsDurationOnlyWhenKnown() {
        val date = 1_780_000_000_000L
        val locale = Locale.ENGLISH
        val datePart = DateTimeUtils.formatShortDate(date, locale)
        assertEquals(datePart, postWorkoutSubtitle(date, null, locale))
        assertEquals(datePart, postWorkoutSubtitle(date, 0L, locale))
        assertEquals("$datePart · 4h 31m", postWorkoutSubtitle(date, 16271L, locale))
        assertEquals(
            DateTimeUtils.formatShortDate(date, Locale("ru")) + " · 4 ч 31 мин",
            postWorkoutSubtitle(date, 16271L, Locale("ru"))
        )
    }
}
