package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.LastLoggedSet
import org.junit.Assert.assertEquals
import org.junit.Test

class ActiveWorkoutAddedExercisePrefillTest {
    @Test
    fun usesTheLastLoggedWeightAndRepsForThreeSets() {
        val sets = prefilledSetsForAddedActiveExercise(LastLoggedSet(weight = 52.5, reps = 7))
        assertEquals(3, sets.size)
        assertEquals(List(3) { WorkoutSetDraft(weight = 52.5, reps = 7) }, sets)
    }

    @Test
    fun fallsBackToTheSavedWorkoutDefaultsWithoutHistory() {
        assertEquals(
            List(3) { WorkoutSetDraft(weight = 20.0, reps = 10) },
            prefilledSetsForAddedActiveExercise(null)
        )
    }

    @Test
    fun ignoresInvalidHistoryValues() {
        assertEquals(
            List(3) { WorkoutSetDraft(weight = 20.0, reps = 10) },
            prefilledSetsForAddedActiveExercise(LastLoggedSet(weight = Double.NaN, reps = 0))
        )
    }
}
