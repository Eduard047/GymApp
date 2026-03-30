package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update
import com.example.gymapp.data.entity.SetEntryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SetDao {
    @Insert
    suspend fun insert(setEntry: SetEntryEntity): Long

    @Insert
    suspend fun insertAll(setEntries: List<SetEntryEntity>)

    @Update
    suspend fun update(setEntry: SetEntryEntity)

    @Delete
    suspend fun delete(setEntry: SetEntryEntity)

    @Query("SELECT workoutExerciseId FROM set_entries WHERE id = :setId LIMIT 1")
    suspend fun getWorkoutExerciseIdBySetId(setId: Long): Long?

    @Query("SELECT * FROM set_entries WHERE id = :setId LIMIT 1")
    suspend fun getById(setId: Long): SetEntryEntity?

    @Query("DELETE FROM set_entries WHERE id = :setId")
    suspend fun deleteById(setId: Long)

    @Query("SELECT COUNT(*) FROM set_entries WHERE workoutExerciseId = :workoutExerciseId")
    suspend fun getSetCountForWorkoutExercise(workoutExerciseId: Long): Int

    @Query(
        "SELECT * FROM set_entries WHERE workoutExerciseId = :workoutExerciseId ORDER BY orderIndex ASC"
    )
    fun getSetsByWorkoutExercise(workoutExerciseId: Long): Flow<List<SetEntryEntity>>

    @Query("SELECT MAX(orderIndex) FROM set_entries WHERE workoutExerciseId = :workoutExerciseId")
    suspend fun getMaxOrderIndex(workoutExerciseId: Long): Int?
}

