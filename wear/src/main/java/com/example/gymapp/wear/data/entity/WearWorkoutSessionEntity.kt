package com.example.gymapp.wear.data.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "wear_workout_sessions")
data class WearWorkoutSessionEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val startedAt: Long,
    val note: String? = null
)
