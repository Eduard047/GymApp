package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "app_metadata")
data class AppMetadataEntity(
    @PrimaryKey val id: Int = SINGLETON_ID,
    val catalogSeedVersion: Int = 0
) {
    companion object {
        const val SINGLETON_ID = 1
    }
}
