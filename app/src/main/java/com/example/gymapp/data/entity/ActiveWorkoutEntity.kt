package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "active_workouts")
data class ActiveWorkoutEntity(
    @PrimaryKey val id: Long,
    val date: Long,
    val note: String?,
    val startedAt: Long,
    val revision: Long
)

@Entity(
    tableName = "active_workout_exercises",
    foreignKeys = [
        ForeignKey(
            entity = ActiveWorkoutEntity::class,
            parentColumns = ["id"],
            childColumns = ["activeWorkoutId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["activeWorkoutId"]),
        Index(value = ["activeWorkoutId", "orderIndex"], unique = true)
    ]
)
data class ActiveWorkoutExerciseEntity(
    @PrimaryKey val id: String,
    val activeWorkoutId: Long,
    val exerciseName: String,
    val catalogKey: String?,
    val orderIndex: Int
)

@Entity(
    tableName = "active_workout_sets",
    foreignKeys = [
        ForeignKey(
            entity = ActiveWorkoutExerciseEntity::class,
            parentColumns = ["id"],
            childColumns = ["activeWorkoutExerciseId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["activeWorkoutExerciseId"]),
        Index(value = ["activeWorkoutExerciseId", "orderIndex"], unique = true)
    ]
)
data class ActiveWorkoutSetEntity(
    @PrimaryKey val id: String,
    val activeWorkoutExerciseId: String,
    val weight: Double,
    val reps: Int,
    val orderIndex: Int,
    val completedAt: Long?
)
