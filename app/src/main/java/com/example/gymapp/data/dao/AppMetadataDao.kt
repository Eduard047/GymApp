package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.AppMetadataEntity

@Dao
interface AppMetadataDao {
    @Query("SELECT catalogSeedVersion FROM app_metadata WHERE id = 1")
    suspend fun getCatalogSeedVersion(): Int?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(metadata: AppMetadataEntity)
}
