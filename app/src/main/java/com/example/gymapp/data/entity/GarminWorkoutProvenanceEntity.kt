package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.PrimaryKey

/**
 * Trusted source marker for a live workout created through the bound Garmin protocol.
 *
 * This row follows the workout lifecycle and is intentionally separate from replay receipts,
 * which must remain bounded even when users delete workouts.
 */
@Entity(
    tableName = "garmin_workout_provenance",
    foreignKeys = [
        ForeignKey(
            entity = WorkoutSessionEntity::class,
            parentColumns = ["id"],
            childColumns = ["workoutSessionId"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class GarminWorkoutProvenanceEntity(
    @PrimaryKey val workoutSessionId: Long
)
