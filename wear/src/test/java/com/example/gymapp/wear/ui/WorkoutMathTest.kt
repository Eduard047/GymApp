package com.example.gymapp.wear.ui

import com.example.gymapp.wear.data.WearWorkoutSetDraft
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutMathTest {
    private val plan = listOf(
        WearWorkoutSetDraft("Bench press", 60.0, 8),
        WearWorkoutSetDraft("Bench press", 62.5, 8),
        WearWorkoutSetDraft("Row", 50.0, 10)
    )

    @Test
    fun heartRateZoneUsesPercentOfMax190() {
        assertNull(WorkoutMath.heartRateZone(null))
        assertNull(WorkoutMath.heartRateZone(0))
        assertEquals(1, WorkoutMath.heartRateZone(113)) // 59.5 %
        assertEquals(2, WorkoutMath.heartRateZone(114)) // 60 %
        assertEquals(3, WorkoutMath.heartRateZone(133)) // 70 %
        assertEquals(4, WorkoutMath.heartRateZone(152)) // 80 %
        assertEquals(5, WorkoutMath.heartRateZone(171)) // 90 %
        assertEquals(5, WorkoutMath.heartRateZone(230))
    }

    @Test
    fun setProgressCountsLoggedSetsAndStopsAtPlanTotal() {
        assertEquals(SetProgress(1, 2), WorkoutMath.setProgress("Bench press", plan, emptyList()))
        val one = listOf(WearWorkoutSetDraft("Bench press", 60.0, 8))
        assertEquals(SetProgress(2, 2), WorkoutMath.setProgress("Bench press", plan, one))
        val three = one + one + one
        assertEquals(SetProgress(2, 2), WorkoutMath.setProgress("Bench press", plan, three))
        assertEquals(SetProgress(1, null), WorkoutMath.setProgress("Curl", plan, three))
        assertEquals(SetProgress(4, null), WorkoutMath.setProgress(null, emptyList(), three))
    }

    @Test
    fun currentExerciseFollowsPlanOrderUnlessChosen() {
        assertEquals("Bench press", WorkoutMath.currentExercise(null, plan, emptyList()))
        val benchDone = listOf(
            WearWorkoutSetDraft("Bench press", 60.0, 8),
            WearWorkoutSetDraft("Bench press", 62.5, 8)
        )
        assertEquals("Row", WorkoutMath.currentExercise(null, plan, benchDone))
        assertEquals("Curl", WorkoutMath.currentExercise("Curl", plan, benchDone))
        assertNull(WorkoutMath.currentExercise(null, emptyList(), emptyList()))
    }

    @Test
    fun nextTargetPrefersPlanThenLastLogged() {
        assertEquals(SetTarget(60.0, 8), WorkoutMath.nextTarget("Bench press", plan, emptyList()))
        val one = listOf(WearWorkoutSetDraft("Bench press", 70.0, 5))
        assertEquals(SetTarget(62.5, 8), WorkoutMath.nextTarget("Bench press", plan, one))
        val curl = listOf(WearWorkoutSetDraft("Curl", 12.5, 12))
        assertEquals(SetTarget(12.5, 12), WorkoutMath.nextTarget("Curl", plan, curl))
        assertNull(WorkoutMath.nextTarget("Curl", plan, emptyList()))
    }

    @Test
    fun volumeAndSummaryNumbers() {
        val sets = listOf(WearWorkoutSetDraft("A", 60.0, 8), WearWorkoutSetDraft("B", 0.0, 10))
        assertEquals(480.0, WorkoutMath.volumeKg(sets), 0.0001)
        val summary = WorkoutMath.summary(2892, sets, 124, 161, null)
        assertEquals(2892L, summary.durationSeconds)
        assertEquals(2, summary.setCount)
        assertEquals(480.0, summary.volumeKg, 0.0001)
        assertEquals(124, summary.averageHeartRate)
        assertNull(summary.caloriesKcal)
        assertNull(WorkoutMath.summary(1, sets, 0, null, 0).averageHeartRate)
    }

    @Test
    fun weightOptionsIncludeOffGridPlannedWeight() {
        val options = WorkoutMath.weightOptions(2.5, 61.0)
        assertEquals(0.0, options.first(), 0.0)
        assertEquals(500.0, options.last(), 0.0)
        assertEquals(202, options.size)
        assertTrue(options.contains(61.0))
        assertEquals(options.sorted(), options)
        assertEquals(501, WorkoutMath.weightOptions(1.0).size)
        assertEquals(WorkoutMath.closestIndex(options, 61.0), options.indexOf(61.0))
        assertEquals(2.5, WorkoutMath.nextWeightStep(1.0), 0.0)
        assertEquals(1.0, WorkoutMath.nextWeightStep(5.0), 0.0)
    }

    @Test
    fun formattingUsesLocaleSeparatorAndDropsZeroDecimals() {
        val uk = Locale.forLanguageTag("uk")
        assertEquals("60", WorkoutMath.formatWeight(60.0, uk))
        assertEquals("62,5", WorkoutMath.formatWeight(62.5, uk))
        assertEquals("62.5", WorkoutMath.formatWeight(62.5, Locale.US))
        assertEquals("1:12", WorkoutMath.formatDuration(72))
        assertEquals("1:00:05", WorkoutMath.formatDuration(3605))
        assertEquals("5,240", WorkoutMath.formatVolume(5240.0, Locale.US))
    }

    @Test
    fun undoWindowLastsFiveSeconds() {
        val window = UndoWindow()
        window.open(7L, nowMs = 1_000L)
        assertTrue(window.isOpen(5_999L))
        assertFalse(window.expireIfDue(5_999L))
        assertEquals(7L, window.consume(5_999L))
        assertNull(window.setId)

        window.open(8L, nowMs = 0L)
        assertTrue(window.expireIfDue(5_000L))
        assertNull(window.consume(5_000L))

        window.open(9L, nowMs = 0L)
        window.close()
        assertNull(window.consume(1L))
    }
}
