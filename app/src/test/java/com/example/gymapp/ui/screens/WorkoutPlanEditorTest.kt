package com.example.gymapp.ui.screens

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutPlanEditorTest {
    @Test
    fun cleanHydratedDraftClosesWithoutConfirmation() {
        assertFalse(workoutPlanCloseRequiresConfirmation(isDirty = false))
    }

    @Test
    fun userMutatedDraftRequiresExplicitDiscardConfirmation() {
        assertTrue(workoutPlanCloseRequiresConfirmation(isDirty = true))
    }
}
