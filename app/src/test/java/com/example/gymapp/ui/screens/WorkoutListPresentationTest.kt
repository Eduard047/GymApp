package com.example.gymapp.ui.screens

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutListPresentationTest {
    @Test
    fun retainedDraftReplacesTodayActionUnlessAnActiveWorkoutOwnsTheScreen() {
        assertTrue(
            shouldShowRetainedWorkoutDraftAction(
                hasRetainedWorkoutDraft = true,
                hasActiveWorkout = false
            )
        )
        assertFalse(
            shouldShowRetainedWorkoutDraftAction(
                hasRetainedWorkoutDraft = true,
                hasActiveWorkout = true
            )
        )
        assertFalse(
            shouldShowRetainedWorkoutDraftAction(
                hasRetainedWorkoutDraft = false,
                hasActiveWorkout = false
            )
        )
    }
}
