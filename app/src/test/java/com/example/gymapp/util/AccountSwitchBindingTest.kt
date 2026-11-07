package com.example.gymapp.util

import com.example.gymapp.data.repository.WorkoutFeedbackRecord
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class AccountSwitchBindingTest {
    private val keyA = "a".repeat(64)

    @Test
    fun profileReadFailureSwitchesKeyAndFallsBackToDefaults() {
        val binding = resolveProfileBinding(keyA) { error("corrupt prefs") }
        assertEquals(keyA, binding.accountKey)
        assertEquals(TrainingProfile(), binding.profile)
    }

    @Test
    fun profileReadSuccessKeepsReadValues() {
        val stored = TrainingProfile(goal = TrainingGoal.Strength, workoutsPerWeek = 6)
        val binding = resolveProfileBinding(keyA) { stored }
        assertEquals(keyA, binding.accountKey)
        assertEquals(stored, binding.profile)
    }

    @Test
    fun profileSignedOutResolvesNullKeyAndDefaults() {
        val binding = resolveProfileBinding(null) { error("must not read") }
        assertEquals(null, binding.accountKey)
        assertEquals(TrainingProfile(), binding.profile)
    }

    @Test
    fun guidanceReadFailuresFallBackPerFieldAndKeepKeySwitched() {
        val progress = FirstRunTutorialProgress(version = 2, completion = FirstRunTutorialCompletion.entries.first())
        val binding = resolveGuidanceBinding(
            nextKey = keyA,
            readActivationDismissed = { error("boom") },
            readFeedback = { error("boom") },
            readTutorialProgress = { progress }
        )
        assertEquals(keyA, binding.accountKey)
        assertEquals(false, binding.activationDismissed)
        assertEquals(emptyMap<Long, WorkoutFeedbackRecord>(), binding.feedback)
        assertEquals(progress, binding.tutorialProgress)
    }

    @Test
    fun guidanceSignedOutResolvesDefaultsWithoutReading() {
        val binding = resolveGuidanceBinding(
            nextKey = null,
            readActivationDismissed = { error("must not read") },
            readFeedback = { error("must not read") },
            readTutorialProgress = { error("must not read") }
        )
        assertEquals(null, binding.accountKey)
        assertEquals(FirstRunTutorialProgress(), binding.tutorialProgress)
    }

    @Test(expected = kotlinx.coroutines.CancellationException::class)
    fun cancellationIsNotSwallowed() {
        readAccountStateOrDefault(0) { throw kotlinx.coroutines.CancellationException("cancelled") }
    }

    @Test
    fun defaultIsReturnedAsIs() {
        val default = emptyList<Int>()
        assertSame(default, readAccountStateOrDefault(default) { error("x") })
    }
}
