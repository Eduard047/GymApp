package com.example.gymapp.ui.screens

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FriendsPrivacyUiPolicyTest {
    @Test
    fun workoutDetailToggleRequiresCanonicalIdleValue() {
        assertFalse(
            isWorkoutDetailPrivacyToggleEnabled(
                savedValue = null,
                isLoading = false,
                isSaving = false
            )
        )
        assertFalse(
            isWorkoutDetailPrivacyToggleEnabled(
                savedValue = true,
                isLoading = true,
                isSaving = false
            )
        )
        assertFalse(
            isWorkoutDetailPrivacyToggleEnabled(
                savedValue = false,
                isLoading = false,
                isSaving = true
            )
        )
        assertTrue(
            isWorkoutDetailPrivacyToggleEnabled(
                savedValue = false,
                isLoading = false,
                isSaving = false
            )
        )
    }
}
