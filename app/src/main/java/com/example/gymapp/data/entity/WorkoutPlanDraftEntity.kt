package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "workout_plan_draft")
data class WorkoutPlanDraftEntity(
    @PrimaryKey val id: Long = 1L,
    val payload: String,
    val updatedAt: Long
)
