package com.example.gymapp.ui.components

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContinueWorkoutBarTest {
    @Test
    fun showsOnlyForAMinimisedWorkoutOutsideToday() {
        assertTrue(shouldShowContinueWorkoutBar(true, isActiveWorkoutRoute = false, isTodayRoute = false))
        assertFalse(shouldShowContinueWorkoutBar(false, isActiveWorkoutRoute = false, isTodayRoute = false))
        assertFalse(shouldShowContinueWorkoutBar(true, isActiveWorkoutRoute = true, isTodayRoute = false))
        assertFalse(shouldShowContinueWorkoutBar(true, isActiveWorkoutRoute = false, isTodayRoute = true))
    }
}
