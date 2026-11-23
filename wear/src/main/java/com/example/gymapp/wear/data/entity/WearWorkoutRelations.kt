package com.example.gymapp.wear.data.entity

import androidx.room.Embedded
import androidx.room.Relation

data class WearWorkoutSessionWithSets(
    @Embedded
    val session: WearWorkoutSessionEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "sessionId"
    )
    val sets: List<WearSetEntryEntity>
)
