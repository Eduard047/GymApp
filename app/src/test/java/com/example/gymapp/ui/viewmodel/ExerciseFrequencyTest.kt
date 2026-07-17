package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import org.junit.Assert.assertEquals
import org.junit.Test

class ExerciseFrequencyTest {
    @Test
    fun countsUniqueWorkoutsInsteadOfSets() {
        val history = listOf(
            entry(setId = 1, sessionId = 10, exerciseId = 100),
            entry(setId = 2, sessionId = 10, exerciseId = 100),
            entry(setId = 3, sessionId = 20, exerciseId = 100),
            entry(setId = 4, sessionId = 20, exerciseId = 200)
        )

        assertEquals(mapOf(100L to 2, 200L to 1), workoutCountByExercise(history))
    }

    private fun entry(setId: Long, sessionId: Long, exerciseId: Long) = ExerciseHistoryEntry(
        setId = setId,
        sessionId = sessionId,
        sessionDate = sessionId,
        exerciseId = exerciseId,
        exerciseName = "Exercise $exerciseId",
        weight = 10.0,
        reps = 5,
        setOrderIndex = 0
    )
}
