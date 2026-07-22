package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.example.gymapp.data.entity.ExerciseEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ExerciseDao {
    @Query("SELECT COUNT(*) FROM exercises")
    suspend fun getExerciseCount(): Int

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(exercise: ExerciseEntity): Long

    @Update
    suspend fun update(exercise: ExerciseEntity)

    @Delete
    suspend fun delete(exercise: ExerciseEntity)

    @Query(
        """
        DELETE FROM exercises
        WHERE id = :exerciseId
            AND name = :expectedName
            AND isFavorite = :expectedFavorite
        """
    )
    suspend fun deleteIfUnchanged(
        exerciseId: Long,
        expectedName: String,
        expectedFavorite: Boolean
    ): Int

    @Query("DELETE FROM exercises")
    suspend fun deleteAllExercises()

    @Query("SELECT * FROM exercises ORDER BY name ASC")
    fun getExercises(): Flow<List<ExerciseEntity>>

    @Query("SELECT * FROM exercises ORDER BY name COLLATE NOCASE ASC")
    suspend fun getExercisesSnapshot(): List<ExerciseEntity>

    @Query("SELECT * FROM exercises WHERE id = :exerciseId LIMIT 1")
    suspend fun getById(exerciseId: Long): ExerciseEntity?

    @Query("UPDATE exercises SET isFavorite = :isFavorite WHERE id = :exerciseId")
    suspend fun setFavorite(exerciseId: Long, isFavorite: Boolean): Int

    @Query(
        "UPDATE exercises SET isFavorite = CASE WHEN isFavorite = 1 THEN 0 ELSE 1 END " +
            "WHERE id = :exerciseId"
    )
    suspend fun toggleFavorite(exerciseId: Long): Int

    @Query(
        """
        SELECT name
        FROM exercises
        WHERE TRIM(name) != ''
        ORDER BY name COLLATE NOCASE ASC
        LIMIT :limit
        """
    )
    suspend fun getExerciseNamesForSync(limit: Int): List<String>
}
