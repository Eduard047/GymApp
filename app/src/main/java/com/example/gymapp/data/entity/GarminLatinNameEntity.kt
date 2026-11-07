package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * One row of the append-only Garmin watch name table of this account database: the ASCII name the
 * watch shows (`latin`) and the stored exercise name it stands for (`raw`). Rows are never rewritten,
 * so a name already shown on a watch keeps meaning the same exercise.
 */
@Entity(
    tableName = "garmin_latin_names",
    indices = [Index(value = ["raw"], unique = true)]
)
data class GarminLatinNameEntity(
    @PrimaryKey val latin: String,
    val raw: String,
    val createdAt: Long
)
