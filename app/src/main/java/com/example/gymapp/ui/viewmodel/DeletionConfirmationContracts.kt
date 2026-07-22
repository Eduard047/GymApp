package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.repository.ExerciseDeletionSnapshot
import com.example.gymapp.data.repository.SetDeletionSnapshot

internal fun ExerciseDeletionSnapshot.matchesRequestedExercise(
    exercise: ExerciseEntity
): Boolean =
    exerciseId == exercise.id &&
        exerciseName == exercise.name &&
        isFavorite == exercise.isFavorite

internal fun SetDeletionSnapshot.matchesRequestedSet(
    sessionId: Long,
    setEntry: SetEntryEntity
): Boolean =
    workoutSessionId == sessionId &&
        setId == setEntry.id &&
        workoutExerciseId == setEntry.workoutExerciseId &&
        weight.toBits() == setEntry.weight.toBits() &&
        reps == setEntry.reps &&
        orderIndex == setEntry.orderIndex

internal fun SetDeletionSnapshot.matchesRequestedHistoryEntry(
    entry: ExerciseHistoryEntry
): Boolean =
    setId == entry.setId &&
        workoutSessionId == entry.sessionId &&
        sessionDate == entry.sessionDate &&
        exerciseId == entry.exerciseId &&
        exerciseName == entry.exerciseName &&
        weight.toBits() == entry.weight.toBits() &&
        reps == entry.reps &&
        orderIndex == entry.setOrderIndex
