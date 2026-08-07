package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutDetailPresentationTest {
    @Test
    fun completedWorkoutStartsWithNoExpandedExerciseAndUsesAccordionToggling() {
        var expandedExerciseId: Long? = null

        expandedExerciseId = nextExpandedWorkoutExerciseId(expandedExerciseId, 10L)
        assertEquals(10L, expandedExerciseId)

        expandedExerciseId = nextExpandedWorkoutExerciseId(expandedExerciseId, 20L)
        assertEquals(20L, expandedExerciseId)

        expandedExerciseId = nextExpandedWorkoutExerciseId(expandedExerciseId, 20L)
        assertNull(expandedExerciseId)
    }

    @Test
    fun readModeHasNoMutationOrTimerControls() {
        val controls = workoutDetailControlVisibility(isEditingWorkout = false)

        assertFalse(controls.showAddExercise)
        assertFalse(controls.showAddSet)
        assertFalse(controls.showSetActions)
        assertFalse(controls.showDeleteWorkout)
        assertFalse(controls.showRestTimer)
        assertFalse(controls.showLogSetAndRest)
    }

    @Test
    fun editModeAllowsCorrectionsButNeverRestTimerActions() {
        val controls = workoutDetailControlVisibility(isEditingWorkout = true)

        assertTrue(controls.showAddExercise)
        assertTrue(controls.showAddSet)
        assertTrue(controls.showSetActions)
        assertTrue(controls.showDeleteWorkout)
        assertFalse(controls.showRestTimer)
        assertFalse(controls.showLogSetAndRest)
    }
}
