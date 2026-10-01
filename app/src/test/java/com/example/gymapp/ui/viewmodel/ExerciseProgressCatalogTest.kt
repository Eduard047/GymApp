package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    private val exercises = listOf(
        ExerciseEntity(id = 1L, name = "Assisted Dip"),
        ExerciseEntity(id = 2L, name = "Bench Press"),
        ExerciseEntity(id = 3L, name = "Squat")
    )

    @Test
    fun defaultExerciseIsTheMostLoggedThenMostRecent() {
        val history = listOf(
            entry(setId = 1L, sessionId = 10L, sessionDate = 100L, exerciseId = 2L),
            entry(setId = 2L, sessionId = 20L, sessionDate = 200L, exerciseId = 2L),
            entry(setId = 3L, sessionId = 20L, sessionDate = 200L, exerciseId = 3L),
            entry(setId = 4L, sessionId = 30L, sessionDate = 300L, exerciseId = 3L)
        )

        // Bench and Squat both have two sessions; Squat is more recent.
        assertEquals(3L, defaultProgressExerciseId(exercises, history))
    }

    @Test
    fun defaultExerciseFallsBackToFirstListedWithoutUsableHistory() {
        assertEquals(1L, defaultProgressExerciseId(exercises, emptyList()))
        // History of an exercise that no longer exists is ignored.
        val orphan = listOf(entry(setId = 1L, sessionId = 10L, sessionDate = 100L, exerciseId = 99L))
        assertEquals(1L, defaultProgressExerciseId(exercises, orphan))
        assertNull(defaultProgressExerciseId(emptyList(), orphan))
    }

    @Test
    fun explicitPickSurvivesHistoryUpdatesButDefaultFollowsThem() {
        val history = listOf(entry(setId = 1L, sessionId = 10L, sessionDate = 100L, exerciseId = 3L))

        // Not picked: initial list-first selection is replaced once history loads.
        assertEquals(
            3L,
            resolveProgressExerciseSelection(exercises, history, currentId = 1L, userPicked = false)
        )
        // Picked: kept even though another exercise is more logged.
        assertEquals(
            1L,
            resolveProgressExerciseSelection(exercises, history, currentId = 1L, userPicked = true)
        )
        // Picked exercise deleted: fall back to the default.
        assertEquals(
            3L,
            resolveProgressExerciseSelection(exercises, history, currentId = 42L, userPicked = true)
        )
        assertNull(resolveProgressExerciseSelection(emptyList(), history, null, false))
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
