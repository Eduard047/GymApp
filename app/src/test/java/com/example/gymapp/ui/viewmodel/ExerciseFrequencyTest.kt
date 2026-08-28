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

    @Test
    fun onePassFrequencyIndexKeepsRecencyOrderingAndStableTieBreaks() {
        val history = listOf(
            entry(setId = 1, sessionId = 10, exerciseId = 300),
            entry(setId = 2, sessionId = 11, exerciseId = 100),
            entry(setId = 3, sessionId = 11, exerciseId = 100),
            entry(setId = 4, sessionId = 12, exerciseId = 200),
            entry(setId = 5, sessionId = 13, exerciseId = 300)
        )

        val frequencies = exerciseFrequencyByExercise(history)

        assertEquals(2, frequencies.getValue(300L).workoutCount)
        assertEquals(13L, frequencies.getValue(300L).latestSessionDate)
        assertEquals(listOf(300L, 200L, 100L), frequentExerciseIds(frequencies))
        assertEquals(listOf(300L, 200L), frequentExerciseIds(frequencies, limit = 2))
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
