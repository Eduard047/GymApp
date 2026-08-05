package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.entity.ActiveWorkoutEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseEntity
import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ActiveWorkoutDao {
    @Transaction
    @Query("SELECT * FROM active_workouts WHERE id = :activeWorkoutId LIMIT 1")
    fun observe(activeWorkoutId: Long): Flow<ActiveWorkoutDetails?>

    @Transaction
    @Query("SELECT * FROM active_workouts WHERE id = :activeWorkoutId LIMIT 1")
    suspend fun getSnapshot(activeWorkoutId: Long): ActiveWorkoutDetails?

    @Insert
    suspend fun insert(activeWorkout: ActiveWorkoutEntity)

    @Insert
    suspend fun insertExercises(exercises: List<ActiveWorkoutExerciseEntity>)

    @Insert
    suspend fun insertSets(sets: List<ActiveWorkoutSetEntity>)

    @Query(
        """
        UPDATE active_workouts
        SET revision = revision + 1
        WHERE id = :activeWorkoutId
            AND revision = :expectedRevision
            AND revision >= 0
            AND revision < 9223372036854775807
        """
    )
    suspend fun advanceRevision(activeWorkoutId: Long, expectedRevision: Long): Int

    @Query(
        """
        UPDATE active_workout_sets
        SET weight = :weight,
            reps = :reps,
            completedAt = :completedAt
        WHERE id = :setId
            AND activeWorkoutExerciseId = :expectedActiveWorkoutExerciseId
            AND completedAt IS NULL
        """
    )
    suspend fun completeSetIfPending(
        setId: String,
        expectedActiveWorkoutExerciseId: String,
        weight: Double,
        reps: Int,
        completedAt: Long
    ): Int

    @Query(
        """
        DELETE FROM active_workouts
        WHERE id = :activeWorkoutId
            AND revision = :expectedRevision
        """
    )
    suspend fun deleteIfRevisionMatches(
        activeWorkoutId: Long,
        expectedRevision: Long
    ): Int
}
