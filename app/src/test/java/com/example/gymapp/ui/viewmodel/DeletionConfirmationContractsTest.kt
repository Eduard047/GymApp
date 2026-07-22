package com.example.gymapp.ui.viewmodel

import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.repository.ExerciseDeletionSnapshot
import com.example.gymapp.data.repository.SetDeletionImpact
import com.example.gymapp.data.repository.SetDeletionSnapshot
import com.example.gymapp.ui.screens.setDeleteImpactTextResource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DeletionConfirmationContractsTest {
    @Test
    fun exercisePreviewMustMatchTheExactRequestedRow() {
        val exercise = ExerciseEntity(id = 7, name = "Bench Press", isFavorite = true)
        val snapshot = ExerciseDeletionSnapshot(
            exerciseId = exercise.id,
            exerciseName = exercise.name,
            isFavorite = exercise.isFavorite,
            workoutCount = 2,
            exerciseBlockCount = 3,
            setCount = 8,
            cascadeFingerprint = "a".repeat(64),
            deletionStoreToken = "test-store"
        )

        assertTrue(snapshot.matchesRequestedExercise(exercise))
        assertFalse(snapshot.copy(exerciseId = 8).matchesRequestedExercise(exercise))
        assertFalse(snapshot.copy(exerciseName = "Other").matchesRequestedExercise(exercise))
        assertFalse(snapshot.copy(isFavorite = false).matchesRequestedExercise(exercise))
    }

    @Test
    fun setPreviewMustMatchTheExactDetailAndHistoryRows() {
        val setEntry = SetEntryEntity(
            id = 41,
            workoutExerciseId = 31,
            weight = 82.5,
            reps = 6,
            orderIndex = 2
        )
        val snapshot = SetDeletionSnapshot(
            setId = setEntry.id,
            workoutExerciseId = setEntry.workoutExerciseId,
            workoutSessionId = 21,
            exerciseId = 11,
            exerciseName = "Bench Press",
            sessionDate = 1_750_000_000_000,
            weight = setEntry.weight,
            reps = setEntry.reps,
            orderIndex = setEntry.orderIndex,
            displayOrdinal = 3,
            setsInExerciseBlock = 3,
            exerciseBlocksInWorkout = 2,
            impact = SetDeletionImpact.SetOnly,
            removedWorkoutExercise = null,
            removedWorkoutSession = null,
            removedGarminProvenance = null,
            deletionStoreToken = "test-store"
        )
        val historyEntry = ExerciseHistoryEntry(
            setId = snapshot.setId,
            sessionId = snapshot.workoutSessionId,
            sessionDate = snapshot.sessionDate,
            exerciseId = snapshot.exerciseId,
            exerciseName = snapshot.exerciseName,
            weight = snapshot.weight,
            reps = snapshot.reps,
            setOrderIndex = snapshot.orderIndex
        )

        assertTrue(snapshot.matchesRequestedSet(snapshot.workoutSessionId, setEntry))
        assertTrue(snapshot.matchesRequestedHistoryEntry(historyEntry))

        assertFalse(snapshot.copy(setId = 42).matchesRequestedSet(snapshot.workoutSessionId, setEntry))
        assertFalse(snapshot.matchesRequestedSet(22, setEntry))
        assertFalse(snapshot.copy(weight = 85.0).matchesRequestedSet(snapshot.workoutSessionId, setEntry))
        assertFalse(snapshot.copy(exerciseName = "Other").matchesRequestedHistoryEntry(historyEntry))
        assertFalse(snapshot.copy(sessionDate = snapshot.sessionDate + 1).matchesRequestedHistoryEntry(historyEntry))
    }

    @Test
    fun everySetCascadeLevelUsesAnExplicitWarning() {
        assertEquals(
            R.string.dialog_delete_set_impact_set_only,
            setDeleteImpactTextResource(SetDeletionImpact.SetOnly)
        )
        assertEquals(
            R.string.dialog_delete_set_impact_exercise,
            setDeleteImpactTextResource(SetDeletionImpact.ExerciseBlock)
        )
        assertEquals(
            R.string.dialog_delete_set_impact_workout,
            setDeleteImpactTextResource(SetDeletionImpact.WorkoutSession)
        )
    }
}
