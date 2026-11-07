package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.GarminLatinNameEntity

@Dao
interface GarminLatinNameDao {
    @Query("SELECT * FROM garmin_latin_names ORDER BY createdAt ASC, latin ASC")
    suspend fun getAll(): List<GarminLatinNameEntity>

    @Query("SELECT raw FROM garmin_latin_names WHERE latin = :latin LIMIT 1")
    suspend fun getRawForLatin(latin: String): String?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertAll(entries: List<GarminLatinNameEntity>)

    @Query("DELETE FROM garmin_latin_names WHERE latin IN (:latinNames)")
    suspend fun deleteByLatin(latinNames: List<String>)
}
