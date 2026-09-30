package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutSetPresentationTest {
    @Test
    fun nominalStepIsTheDefaultWithoutAMachineProfile() {
        assertEquals(2.5, nominalWeightStep(emptyList()), 0.0)
        assertEquals(2.5, nominalWeightStep(listOf(20.0)), 0.0)
    }

    @Test
    fun nominalStepIsTheSmallestGapBetweenAllowedWeights() {
        assertEquals(5.0, nominalWeightStep(listOf(10.0, 15.0, 25.0, 30.0)), 0.0)
    }

    @Test
    fun freeWeightStepsBySteppingRuleAndShowsRealDelta() {
        val plan = weightStepPlan(60.0, emptyList())

        assertTrue(plan.minus.canMove)
        assertEquals(57.5, plan.minus.target, 0.0)
        assertEquals(2.5, plan.minus.delta, 0.0)
        assertTrue(plan.plus.canMove)
        assertEquals(62.5, plan.plus.target, 0.0)
        assertEquals(2.5, plan.plus.delta, 0.0)
    }

    @Test
    fun blockedDirectionShowsTheNominalStepAndCannotMove() {
        val plan = weightStepPlan(0.0, emptyList())

        assertFalse(plan.minus.canMove)
        assertEquals(2.5, plan.minus.delta, 0.0)
        assertTrue(plan.plus.canMove)
    }

    @Test
    fun machineStopsUseRealGapsAndNominalAtTheEnds() {
        val allowed = listOf(10.0, 15.0, 25.0)

        val middle = weightStepPlan(15.0, allowed)
        assertEquals(10.0, middle.minus.target, 0.0)
        assertEquals(5.0, middle.minus.delta, 0.0)
        assertEquals(25.0, middle.plus.target, 0.0)
        assertEquals(10.0, middle.plus.delta, 0.0)

        val top = weightStepPlan(25.0, allowed)
        assertFalse(top.plus.canMove)
        assertEquals(5.0, top.plus.delta, 0.0)
        assertTrue(top.minus.canMove)

        val bottom = weightStepPlan(10.0, allowed)
        assertFalse(bottom.minus.canMove)
        assertEquals(5.0, bottom.minus.delta, 0.0)
    }

    @Test
    fun unparseableWeightBlocksBothDirections() {
        val plan = weightStepPlan(weightForStepping("abc"), emptyList())

        assertFalse(plan.minus.canMove)
        assertFalse(plan.plus.canMove)
        assertEquals(2.5, plan.plus.delta, 0.0)
    }

    @Test
    fun blankWeightInputStepsFromZeroAndCommaDecimalsParse() {
        assertEquals(0.0, weightForStepping("")!!, 0.0)
        assertEquals(62.5, weightForStepping("62,5")!!, 0.0)
        assertNull(weightForStepping("1e999x"))
    }

    @Test
    fun repsStepNeverGoesBelowOne() {
        assertFalse(canStepReps(1, -1))
        assertTrue(canStepReps(2, -1))
        assertEquals(1, steppedReps(2, -1))
        assertEquals(1, steppedReps(1, -1))
        assertEquals(9, steppedReps(8, 1))
        assertEquals(1, steppedReps(null, 1))
        assertFalse(canStepReps(null, -1))
    }

    @Test
    fun previousCaptionShowsWeightAndRepsWhenWeightIsPositive() {
        val caption = previousCaption(60.0, 8, isBodyweight = false)!!

        assertTrue(caption.showsWeight)
        assertEquals(60.0, caption.weight, 0.0)
        assertEquals(8, caption.reps)
    }

    @Test
    fun previousCaptionIsHiddenForZeroWeightUnlessBodyweight() {
        assertNull(previousCaption(0.0, 8, isBodyweight = false))
        val bodyweight = previousCaption(0.0, 8, isBodyweight = true)!!
        assertFalse(bodyweight.showsWeight)
        assertEquals(8, bodyweight.reps)
    }

    @Test
    fun weightedBodyweightExerciseStillShowsItsWeight() {
        assertTrue(previousCaption(10.0, 6, isBodyweight = true)!!.showsWeight)
    }

    @Test
    fun previousCaptionNeedsBothValues() {
        assertNull(previousCaption(null, 8, isBodyweight = true))
        assertNull(previousCaption(60.0, null, isBodyweight = false))
    }

    @Test
    fun bodyweightKeysMatchTheIphoneList() {
        listOf("push_up", "dips", "pull_up", "plank", "hanging_leg_raise", "band_assisted_pull_up")
            .forEach { assertTrue(it, isBodyweightCatalogKey(it)) }
        assertFalse(isBodyweightCatalogKey("bench_press"))
        assertFalse(isBodyweightCatalogKey(null))
    }

    @Test
    fun restSuffixIsMinutesAndSecondsOnlyWhenARestApplies() {
        assertEquals("3:00", restClockLabel(180))
        assertEquals("1:30", restClockLabel(90))
        assertEquals("0:45", restClockLabel(45))
        assertNull(restClockLabel(0))
    }

    @Test
    fun announcementKeepsTheRestDurationThatTheBannerOmits() {
        val withRest = recordedSetAnnouncement("Recorded: 40 kg × 10", 180) { message, clock ->
            "$message · rest $clock"
        }
        assertEquals("Recorded: 40 kg × 10 · rest 3:00", withRest)

        val withoutRest = recordedSetAnnouncement("Recorded: 40 kg × 10", 0) { message, clock ->
            "$message · rest $clock"
        }
        assertEquals("Recorded: 40 kg × 10", withoutRest)
    }

    @Test
    fun confirmationStaysWhileTheSetIsRecordingOrLatestCompleted() {
        assertEquals(
            RecordedConfirmationStep.Waiting,
            recordedConfirmationStep("a", null, emptySet(), wasShowing = false, hasFailureForSet = false)
        )
        assertEquals(
            RecordedConfirmationStep.Showing,
            recordedConfirmationStep("a", null, setOf("a"), wasShowing = false, hasFailureForSet = false)
        )
        assertEquals(
            RecordedConfirmationStep.Showing,
            recordedConfirmationStep("a", "a", emptySet(), wasShowing = true, hasFailureForSet = false)
        )
    }

    @Test
    fun confirmationClearsWhenTheSetIsNoLongerTheLatestCompletedOne() {
        // Undone or superseded by a newer recorded set.
        assertEquals(
            RecordedConfirmationStep.Clear,
            recordedConfirmationStep("a", null, emptySet(), wasShowing = true, hasFailureForSet = false)
        )
        assertEquals(
            RecordedConfirmationStep.Clear,
            recordedConfirmationStep("a", "b", emptySet(), wasShowing = true, hasFailureForSet = false)
        )
        // Recording was rejected before it ever completed.
        assertEquals(
            RecordedConfirmationStep.Clear,
            recordedConfirmationStep("a", null, emptySet(), wasShowing = false, hasFailureForSet = true)
        )
    }
}
