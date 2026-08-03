package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

@Entity(
    tableName = "exercise_load_profiles",
    foreignKeys = [
        ForeignKey(
            entity = ExerciseEntity::class,
            parentColumns = ["id"],
            childColumns = ["exerciseId"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class ExerciseLoadProfileEntity(
    @androidx.room.PrimaryKey val exerciseId: Long,
    val direction: String,
    val updatedAt: Long
)

@Entity(
    tableName = "exercise_weight_options",
    primaryKeys = ["exerciseId", "ordinal"],
    foreignKeys = [
        ForeignKey(
            entity = ExerciseEntity::class,
            parentColumns = ["id"],
            childColumns = ["exerciseId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["exerciseId", "weight"], unique = true)]
)
data class ExerciseWeightOptionEntity(
    val exerciseId: Long,
    val ordinal: Int,
    val weight: Double
)
