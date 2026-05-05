package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "exercise_muscle_mappings",
    primaryKeys = ["exerciseNameKey", "muscleId"],
    indices = [Index(value = ["exerciseName"])]
)
data class ExerciseMuscleMappingEntity(
    val exerciseNameKey: String,
    val exerciseName: String,
    val muscleId: String,
    val weight: Double,
    val updatedAt: Long
)
