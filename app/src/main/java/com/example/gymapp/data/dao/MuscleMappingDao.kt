package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MuscleMappingDao {
    @Query(
        """
        SELECT *
        FROM exercise_muscle_mappings
        ORDER BY exerciseName COLLATE NOCASE ASC, muscleId ASC
        """
    )
    fun observeMappings(): Flow<List<ExerciseMuscleMappingEntity>>

    @Query("DELETE FROM exercise_muscle_mappings WHERE exerciseNameKey = :exerciseNameKey")
    suspend fun deleteForExercise(exerciseNameKey: String)

    @Query("SELECT * FROM exercise_muscle_mappings WHERE exerciseNameKey = :exerciseNameKey")
    suspend fun getForExercise(exerciseNameKey: String): List<ExerciseMuscleMappingEntity>

    @Query("SELECT * FROM exercise_muscle_mappings")
    suspend fun getMappingsSnapshot(): List<ExerciseMuscleMappingEntity>

    @Query(
        """
        UPDATE exercise_muscle_mappings
        SET exerciseName = :exerciseName,
            updatedAt = :updatedAt
        WHERE exerciseNameKey = :exerciseNameKey
        """
    )
    suspend fun updateExerciseName(
        exerciseNameKey: String,
        exerciseName: String,
        updatedAt: Long
    )

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(mappings: List<ExerciseMuscleMappingEntity>)
}
