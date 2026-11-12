package com.example.gymapp.data.entity

import androidx.room.Embedded
import androidx.room.Relation

data class WorkoutSessionSummary(
    @Embedded val session: WorkoutSessionEntity,
    val exerciseCount: Int,
    val setCount: Int,
    val totalVolume: Double,
    val hasGarminReceipt: Boolean = false
)

data class WorkoutExerciseWithDetails(
    @Embedded val workoutExercise: WorkoutExerciseEntity,
    @Relation(
        parentColumn = "exerciseId",
        entityColumn = "id"
    )
    val exercise: ExerciseEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "workoutExerciseId"
    )
    val sets: List<SetEntryEntity>
)

data class WorkoutSessionDetails(
    @Embedded val session: WorkoutSessionEntity,
    @Relation(
        entity = WorkoutExerciseEntity::class,
        parentColumn = "id",
        entityColumn = "sessionId"
    )
    val workoutExercises: List<WorkoutExerciseWithDetails>
)

/** The weight and reps of the most recent logged set of an exercise. */
data class LastLoggedSet(
    val weight: Double,
    val reps: Int
)

/** One exercise block of a stored workout, used to search past workouts by exercise name. */
data class SessionExerciseNameRow(
    val sessionId: Long,
    val exerciseName: String
)

data class ExerciseHistoryEntry(
    val setId: Long,
    val sessionId: Long,
    val sessionDate: Long,
    val exerciseId: Long,
    val exerciseName: String,
    val weight: Double,
    val reps: Int,
    val setOrderIndex: Int,
    /** Position of the set's exercise block in its workout; [setOrderIndex] restarts per block. */
    val blockOrderIndex: Int = 0
)
