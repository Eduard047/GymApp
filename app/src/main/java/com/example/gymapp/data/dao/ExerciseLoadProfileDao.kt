package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.ExerciseLoadProfileEntity
import com.example.gymapp.data.entity.ExerciseWeightOptionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ExerciseLoadProfileDao {
    @Query("SELECT * FROM exercise_load_profiles ORDER BY exerciseId ASC")
    fun observeProfiles(): Flow<List<ExerciseLoadProfileEntity>>

    @Query("SELECT * FROM exercise_weight_options ORDER BY exerciseId ASC, ordinal ASC")
    fun observeWeightOptions(): Flow<List<ExerciseWeightOptionEntity>>

    @Query("SELECT * FROM exercise_load_profiles ORDER BY exerciseId ASC")
    suspend fun getProfilesSnapshot(): List<ExerciseLoadProfileEntity>

    @Query("SELECT * FROM exercise_weight_options ORDER BY exerciseId ASC, ordinal ASC")
    suspend fun getWeightOptionsSnapshot(): List<ExerciseWeightOptionEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertProfile(profile: ExerciseLoadProfileEntity)

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertWeightOptions(options: List<ExerciseWeightOptionEntity>)

    @Query("DELETE FROM exercise_weight_options WHERE exerciseId = :exerciseId")
    suspend fun deleteWeightOptions(exerciseId: Long)

    @Query("DELETE FROM exercise_load_profiles WHERE exerciseId = :exerciseId")
    suspend fun deleteProfile(exerciseId: Long)
}
