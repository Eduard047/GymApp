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
    fun weightOptionsExtendToPlannedWeightAbove500() {
        val options = WorkoutMath.weightOptions(2.5, 520.0)
        assertTrue(options.contains(520.0))
        assertEquals(520.0, options.last(), 0.0)
        assertEquals(options.indexOf(520.0), WorkoutMath.closestIndex(options, 520.0))
        // Off-grid above 500: grid goes up to the next step, the exact value is included.
        val offGrid = WorkoutMath.weightOptions(5.0, 521.25)
        assertTrue(offGrid.contains(521.25))
        assertEquals(525.0, offGrid.last(), 0.0)
        assertEquals(offGrid.sorted(), offGrid)
        // Beyond the protocol maximum nothing is added; a huge plan keeps the grid bounded.
        assertEquals(500.0, WorkoutMath.weightOptions(1.0, 2_000_000.0).last(), 0.0)
        val huge = WorkoutMath.weightOptions(1.0, 900_000.0)
        assertTrue(huge.size <= WorkoutMath.MAX_WEIGHT_OPTION_COUNT + 1)
        assertTrue(huge.contains(900_000.0))
        // A 3-decimal planned weight stays distinct from its grid neighbour.
        assertTrue(WorkoutMath.weightOptions(2.5, 21.125).contains(21.125))
    }

    @Test
    fun repOptionsExtendToPlannedRepsAbove100() {
        assertEquals(WorkoutMath.repOptions, WorkoutMath.repOptions(null))
        assertEquals(WorkoutMath.repOptions, WorkoutMath.repOptions(12))
        val options = WorkoutMath.repOptions(120)
        assertEquals(1, options.first())
        assertEquals(120, options.last())
        assertEquals(120, options[WorkoutMath.repIndex(options, 120)])
        assertEquals(10_000, WorkoutMath.repOptions(50_000).last())
        assertEquals(0, WorkoutMath.repIndex(options, 0))
        assertEquals(99, WorkoutMath.repIndex(WorkoutMath.repOptions, 500))
    }

    @Test
    fun loggedWeightKeepsThreeDecimalsAndRoundTrips() {
        assertEquals("21.125", WorkoutMath.formatLoggedWeight(21.125))
        assertEquals(21.125, com.example.gymapp.wear.util.parseWeightInputOrNull(WorkoutMath.formatLoggedWeight(21.125))!!, 0.0)
        assertEquals("60", WorkoutMath.formatLoggedWeight(60.0))
        assertEquals("62.5", WorkoutMath.formatLoggedWeight(62.5))
        assertEquals("1.25", WorkoutMath.formatLoggedWeight(1.25))
        assertEquals("520", WorkoutMath.formatLoggedWeight(520.0))
        assertEquals("21,125", WorkoutMath.formatWeight(21.125, Locale.forLanguageTag("uk")))
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

    @Test
    fun clampIndexKeepsStalePickerIndexInsideShrunkList() {
        // Wheel saved at 110 of a 1..120 list, then the list shrinks back to 1..100.
        val shrunk = WorkoutMath.repOptions(80)
        assertEquals(99, WorkoutMath.clampIndex(110, shrunk.size))
        assertEquals(100, WorkoutMath.optionAt(shrunk, 110))
        assertEquals(0, WorkoutMath.clampIndex(-3, shrunk.size))
        assertEquals(1, WorkoutMath.optionAt(shrunk, -3))
        assertEquals(42, WorkoutMath.optionAt(shrunk, 41))
        val weights = WorkoutMath.weightOptions(2.5)
        assertEquals(weights.last(), WorkoutMath.optionAt(weights, weights.size + 50))
    }

    @Test
    fun clampIndexHandlesEmptyList() {
        assertEquals(0, WorkoutMath.clampIndex(5, 0))
        assertEquals(0, WorkoutMath.clampIndex(0, -1))
        assertNull(WorkoutMath.optionAt(emptyList<Int>(), 0))
        assertNull(WorkoutMath.optionAt(emptyList<Double>(), 7))
        assertEquals(0, WorkoutMath.closestIndex(emptyList(), 60.0))
        assertEquals(0, WorkoutMath.repIndex(emptyList(), 8))
    }

    @Test
    fun missingValueSelectsNearestOption() {
        val weights = listOf(0.0, 2.5, 5.0, 7.5)
        assertEquals(1, WorkoutMath.closestIndex(weights, 3.0))
        assertEquals(2, WorkoutMath.closestIndex(weights, 4.0))
        assertEquals(3, WorkoutMath.closestIndex(weights, 500.0))
        assertEquals(0, WorkoutMath.closestIndex(weights, -1.0))
        // Target above the shrunk reps list lands on its last entry.
        val reps = WorkoutMath.repOptions(null)
        assertEquals(reps.lastIndex, WorkoutMath.repIndex(reps, 120))
        assertEquals(0, WorkoutMath.repIndex(reps, 0))
    }

    @Test
    fun pickerTargetIndexFollowsTheNewExerciseTarget() {
        // Leg Press 450 kg x 150 -> Biceps Curl 12.5 kg x 10: same weight grid, shorter reps list.
        val weights = WorkoutMath.weightOptions(2.5, 450.0)
        assertEquals(450.0, weights[WorkoutMath.pickerTargetIndex(weights, 450.0)], 0.0)
        assertEquals(12.5, weights[WorkoutMath.pickerTargetIndex(weights, 12.5)], 0.0)

        val legPressReps = WorkoutMath.repOptions(150)
        assertEquals(150, legPressReps.size)
        assertEquals(149, WorkoutMath.pickerTargetIndex(legPressReps, 150))
        val curlReps = WorkoutMath.repOptions(10)
        assertEquals(100, curlReps.size)
        assertEquals(9, WorkoutMath.pickerTargetIndex(curlReps, 10))
        assertEquals(10, curlReps[WorkoutMath.pickerTargetIndex(curlReps, 10)])
    }

    @Test
    fun pickerTargetIndexStaysInsideTheList() {
        val reps = WorkoutMath.repOptions(null)
        assertEquals(reps.lastIndex, WorkoutMath.pickerTargetIndex(reps, 150))
        assertEquals(0, WorkoutMath.pickerTargetIndex(reps, 0))
        assertEquals(0, WorkoutMath.pickerTargetIndex(emptyList<Int>(), 10))
        assertEquals(0, WorkoutMath.pickerTargetIndex(emptyList<Double>(), 12.5))
        val weights = WorkoutMath.weightOptions(5.0, null)
        assertEquals(weights.lastIndex, WorkoutMath.pickerTargetIndex(weights, 10_000.0))
        assertEquals(0, WorkoutMath.pickerTargetIndex(weights, -5.0))
    }

    // FitText size picking (a line 10 px wide per sp, so 16sp is 160 px).
    private val widthAt: (Float) -> Int = { size -> (size * 10).toInt() }

    @Test
    fun fitTextKeepsTheFullSizeWhenTheLineFits() {
        var calls = 0
        val size = WorkoutMath.fitTextSize(16f, 10f, 0.5f, 200) { calls++; widthAt(it) }
        assertEquals(16f, size, 0f)
        assertEquals(1, calls)
    }

    @Test
    fun fitTextStepsDownToTheLargestSizeThatFits() {
        assertEquals(14.5f, WorkoutMath.fitTextSize(16f, 10f, 0.5f, 145, widthAt), 0f)
        assertEquals(14f, WorkoutMath.fitTextSize(16f, 10f, 0.5f, 144, widthAt), 0f)
    }

    @Test
    fun fitTextNeverGoesBelowTheMinimum() {
        assertEquals(10f, WorkoutMath.fitTextSize(16f, 10f, 0.5f, 20, widthAt), 0f)
        assertEquals(10f, WorkoutMath.fitTextSize(16f, 10f, 0.5f, 0, widthAt), 0f)
    }

    @Test
    fun fitTextLeavesSmallOrStepLessStylesAlone() {
        assertEquals(9f, WorkoutMath.fitTextSize(9f, 10f, 0.5f, 1) { error("not measured") }, 0f)
        assertEquals(16f, WorkoutMath.fitTextSize(16f, 10f, 0f, 1) { error("not measured") }, 0f)
    }
}
