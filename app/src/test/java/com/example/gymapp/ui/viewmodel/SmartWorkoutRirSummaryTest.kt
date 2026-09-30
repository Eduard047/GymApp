package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.SmartWorkoutEffort
import org.junit.Assert.assertEquals
import org.junit.Test

class SmartWorkoutRirSummaryTest {
    @Test
    fun sharedRangeIsShownOnce() {
        assertEquals(
            "2–3",
            smartWorkoutRirSummary(listOf(2..3, 2..3, 2..3), SmartWorkoutEffort.Standard)
        )
        assertEquals(
            "3–4",
            smartWorkoutRirSummary(listOf(3..4), SmartWorkoutEffort.Recovery)
        )
    }

    @Test
    fun mixedRangesAreOrderedHardestFirst() {
        assertEquals(
            "1–2 · 2–3",
            smartWorkoutRirSummary(listOf(2..3, 1..2, 2..3), SmartWorkoutEffort.Hard)
        )
        assertEquals(
            "1–2 · 2–3 · 3–4",
            smartWorkoutRirSummary(listOf(3..4, 2..3, 1..2), SmartWorkoutEffort.Hard)
        )
    }

    @Test
    fun emptyPlanFallsBackToAppliedEffortRange() {
        assertEquals("2–3", smartWorkoutRirSummary(emptyList(), SmartWorkoutEffort.Auto))
        assertEquals("2–3", smartWorkoutRirSummary(emptyList(), SmartWorkoutEffort.Standard))
        assertEquals("3–4", smartWorkoutRirSummary(emptyList(), SmartWorkoutEffort.Recovery))
        assertEquals("1–2", smartWorkoutRirSummary(emptyList(), SmartWorkoutEffort.Hard))
    }

    @Test
    fun launchPlanRangesFollowHardSlotsAndAppliedEffort() {
        assertEquals(
            listOf(1..2, 2..3),
            smartWorkoutLaunchRirRanges(listOf(true, false), SmartWorkoutEffort.Hard)
        )
        assertEquals(
            listOf(3..4, 3..4),
            smartWorkoutLaunchRirRanges(listOf(false, false), SmartWorkoutEffort.Recovery)
        )
        assertEquals(
            "2–3",
            smartWorkoutRirSummary(
                smartWorkoutLaunchRirRanges(listOf(false, false), SmartWorkoutEffort.Standard),
                SmartWorkoutEffort.Standard
            )
        )
    }

    @Test
    fun summaryModelDefaultsToAppliedEffortRange() {
        val model = SmartWorkoutPlanSummaryUiModel(
            focus = com.example.gymapp.data.repository.SmartWorkoutFocus.FullBody,
            variant = com.example.gymapp.data.repository.SmartWorkoutVariant.A,
            requestedEffort = SmartWorkoutEffort.Auto,
            appliedEffort = SmartWorkoutEffort.Recovery,
            effortAdjustment = null
        )
        assertEquals("3–4", model.rirSummary)
    }
}
