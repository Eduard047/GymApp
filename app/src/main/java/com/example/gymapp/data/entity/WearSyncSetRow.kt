package com.example.gymapp.data.entity

data class WearSyncSetRow(
    val sessionId: Long,
    val sessionDate: Long,
    val sessionNote: String?,
    val workoutExerciseOrder: Int,
    val setId: Long,
    val exerciseName: String,
    val weight: Double,
    val reps: Int,
    val setOrder: Int
)
