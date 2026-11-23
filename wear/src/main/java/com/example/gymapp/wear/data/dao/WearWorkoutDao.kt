package com.example.gymapp.wear.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.example.gymapp.wear.data.entity.WearSetEntryEntity
import com.example.gymapp.wear.data.entity.WearWorkoutSessionEntity
import com.example.gymapp.wear.data.entity.WearWorkoutSessionWithSets
import kotlinx.coroutines.flow.Flow

@Dao
interface WearWorkoutDao {
    @Transaction
    @Query("SELECT * FROM wear_workout_sessions ORDER BY startedAt DESC")
    fun observeSessionsWithSets(): Flow<List<WearWorkoutSessionWithSets>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSession(session: WearWorkoutSessionEntity): Long

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSessions(sessions: List<WearWorkoutSessionEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSets(sets: List<WearSetEntryEntity>)

    @Query("DELETE FROM wear_set_entries")
    suspend fun clearSets()

    @Query("DELETE FROM wear_workout_sessions")
    suspend fun clearSessions()

    @Update
    suspend fun updateSet(set: WearSetEntryEntity)

    @Query("DELETE FROM wear_set_entries WHERE id = :setId")
    suspend fun deleteSetById(setId: Long)

    @Query("SELECT sessionId FROM wear_set_entries WHERE id = :setId LIMIT 1")
    suspend fun getSessionIdBySetId(setId: Long): Long?

    @Query("SELECT COUNT(*) FROM wear_set_entries WHERE sessionId = :sessionId")
    suspend fun getSetCountForSession(sessionId: Long): Int

    @Query("DELETE FROM wear_workout_sessions WHERE id = :sessionId")
    suspend fun deleteSessionById(sessionId: Long)
}
