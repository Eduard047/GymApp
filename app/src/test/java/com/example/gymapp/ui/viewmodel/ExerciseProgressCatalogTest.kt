package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import org.junit.Assert.assertEquals
import org.junit.Test

class ExerciseProgressCatalogTest {
    @Test
    fun frequentExercisesPreferDistinctWorkoutCountThenRecency() {
        val history = listOf(
            entry(setId = 1L, sessionId = 10L, sessionDate = 100L, exerciseId = 1L),
            entry(setId = 2L, sessionId = 10L, sessionDate = 100L, exerciseId = 1L),
            entry(setId = 3L, sessionId = 20L, sessionDate = 200L, exerciseId = 2L),
            entry(setId = 4L, sessionId = 30L, sessionDate = 300L, exerciseId = 2L),
            entry(setId = 5L, sessionId = 40L, sessionDate = 400L, exerciseId = 3L),
            entry(setId = 6L, sessionId = 50L, sessionDate = 500L, exerciseId = 1L)
        )

        assertEquals(listOf(1L, 2L, 3L), progressFrequentExerciseIds(history))
        assertEquals(listOf(1L, 2L), progressFrequentExerciseIds(history, limit = 2))
        assertEquals(emptyList<Long>(), progressFrequentExerciseIds(history, limit = 0))
    }

    private fun entry(
        setId: Long,
        sessionId: Long,
        sessionDate: Long,
        exerciseId: Long
    ) = ExerciseHistoryEntry(
        setId = setId,
        sessionId = sessionId,
        sessionDate = sessionDate,
        exerciseId = exerciseId,
        exerciseName = "Exercise $exerciseId",
        weight = 20.0,
        reps = 10,
        setOrderIndex = 0
    )
}
