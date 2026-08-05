package com.example.gymapp.data.entity

import androidx.room.Embedded
import androidx.room.Relation

data class ActiveWorkoutExerciseWithDetails(
    @Embedded val activeWorkoutExercise: ActiveWorkoutExerciseEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "activeWorkoutExerciseId"
    )
    val sets: List<ActiveWorkoutSetEntity>
)

data class ActiveWorkoutDetails(
    @Embedded val activeWorkout: ActiveWorkoutEntity,
    @Relation(
        entity = ActiveWorkoutExerciseEntity::class,
        parentColumn = "id",
        entityColumn = "activeWorkoutId"
    )
    val exercises: List<ActiveWorkoutExerciseWithDetails>
)
