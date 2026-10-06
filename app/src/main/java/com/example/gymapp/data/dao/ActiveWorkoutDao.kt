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
        SET revision = revision + 1,
            undoableSetId = :setId
        WHERE id = :activeWorkoutId
            AND revision = :expectedRevision
            AND revision >= 0
            AND revision < 9223372036854775807
        """
    )
    suspend fun advanceRevisionAndSetUndoable(
        activeWorkoutId: Long,
        expectedRevision: Long,
        setId: String
    ): Int

    @Query(
        """
        UPDATE active_workouts
        SET revision = revision + 1,
            undoableSetId = NULL
        WHERE id = :activeWorkoutId
            AND revision = :expectedRevision
            AND undoableSetId = :setId
            AND revision >= 0
            AND revision < 9223372036854775807
        """
    )
    suspend fun advanceRevisionAndClearUndoable(
        activeWorkoutId: Long,
        expectedRevision: Long,
        setId: String
    ): Int

    @Query(
        """
        UPDATE active_workouts
        SET revision = revision + 1,
            undoableSetId = NULL
        WHERE id = :activeWorkoutId
            AND revision = :expectedRevision
            AND revision >= 0
            AND revision < 9223372036854775807
        """
    )
    suspend fun advanceRevisionForBulkRecord(
        activeWorkoutId: Long,
        expectedRevision: Long
    ): Int

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

    /** Fills an unplanned (0 kg) pending set with the weight just recorded on its predecessor. */
    @Query(
        """
        UPDATE active_workout_sets
        SET weight = :weight
        WHERE id = :setId
            AND activeWorkoutExerciseId = :expectedActiveWorkoutExerciseId
            AND completedAt IS NULL
            AND weight = 0
        """
    )
    suspend fun carryWeightToPendingSet(
        setId: String,
        expectedActiveWorkoutExerciseId: String,
        weight: Double
    ): Int

    @Query(
        """
        UPDATE active_workout_sets
        SET weight = :weight,
            reps = :reps,
            completedAt = :completedAt
        WHERE id = :setId
            AND activeWorkoutExerciseId = :expectedActiveWorkoutExerciseId
        """
    )
    suspend fun saveSetForExercise(
        setId: String,
        expectedActiveWorkoutExerciseId: String,
        weight: Double,
        reps: Int,
        completedAt: Long
    ): Int

    @Query(
        """
        UPDATE active_workout_sets
        SET completedAt = NULL
        WHERE id = :setId
            AND activeWorkoutExerciseId = :expectedActiveWorkoutExerciseId
            AND completedAt = :expectedCompletedAt
        """
    )
    suspend fun reopenCompletedSet(
        setId: String,
        expectedActiveWorkoutExerciseId: String,
        expectedCompletedAt: Long
    ): Int

    /** Revision bump that keeps the single-set undo target (a pending-set edit cannot own it). */
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
    suspend fun advanceRevisionKeepingUndoable(
        activeWorkoutId: Long,
        expectedRevision: Long
    ): Int

    @Query(
        """
        DELETE FROM active_workout_sets
        WHERE id = :setId
            AND activeWorkoutExerciseId = :expectedActiveWorkoutExerciseId
            AND completedAt IS NULL
        """
    )
    suspend fun deletePendingSet(
        setId: String,
        expectedActiveWorkoutExerciseId: String
    ): Int

    @Query(
        """
        DELETE FROM active_workout_sets
        WHERE id = :setId
            AND activeWorkoutExerciseId = :expectedActiveWorkoutExerciseId
        """
    )
    suspend fun deleteSetOfExercise(
        setId: String,
        expectedActiveWorkoutExerciseId: String
    ): Int

    @Query(
        """
        UPDATE active_workout_sets
        SET orderIndex = :orderIndex
        WHERE id = :setId
            AND activeWorkoutExerciseId = :expectedActiveWorkoutExerciseId
        """
    )
    suspend fun updateSetOrderIndex(
        setId: String,
        expectedActiveWorkoutExerciseId: String,
        orderIndex: Int
    ): Int

    @Query("DELETE FROM active_workout_sets WHERE activeWorkoutExerciseId = :exerciseId")
    suspend fun deleteSetsOfExercise(exerciseId: String): Int

    @Query(
        """
        DELETE FROM active_workout_exercises
        WHERE id = :exerciseId
            AND activeWorkoutId = :activeWorkoutId
        """
    )
    suspend fun deleteExercise(activeWorkoutId: Long, exerciseId: String): Int

    @Query(
        """
        UPDATE active_workout_exercises
        SET orderIndex = :orderIndex
        WHERE id = :exerciseId
            AND activeWorkoutId = :activeWorkoutId
        """
    )
    suspend fun updateExerciseOrderIndex(
        activeWorkoutId: Long,
        exerciseId: String,
        orderIndex: Int
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
