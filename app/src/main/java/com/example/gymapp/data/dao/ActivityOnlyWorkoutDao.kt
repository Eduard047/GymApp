package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.ActivityOnlyWorkoutEntity
import com.example.gymapp.data.entity.ActivityOnlyWorkoutSyncJournalEntity
import com.example.gymapp.data.entity.ActivityOnlyWorkoutSyncBaselineEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ActivityOnlyWorkoutDao {
    @Query("SELECT * FROM activity_only_workouts ORDER BY workoutStartedAt ASC")
    suspend fun getAll(): List<ActivityOnlyWorkoutEntity>

    @Query(
        "SELECT * FROM activity_only_workouts " +
            "WHERE workoutStartedAt = :workoutStartedAt LIMIT 1"
    )
    suspend fun getByStartedAt(workoutStartedAt: Long): ActivityOnlyWorkoutEntity?

    @Query("SELECT * FROM activity_only_workouts ORDER BY workoutStartedAt ASC")
    fun observeAll(): Flow<List<ActivityOnlyWorkoutEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(item: ActivityOnlyWorkoutEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(items: List<ActivityOnlyWorkoutEntity>)

    @Query("DELETE FROM activity_only_workouts WHERE workoutStartedAt = :workoutStartedAt")
    suspend fun deleteByStartedAt(workoutStartedAt: Long): Int

    @Query("DELETE FROM activity_only_workouts")
    suspend fun deleteAll()

    @Query("SELECT * FROM activity_only_workout_sync_journal WHERE id = 1 LIMIT 1")
    suspend fun getSyncJournal(): ActivityOnlyWorkoutSyncJournalEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertSyncJournal(journal: ActivityOnlyWorkoutSyncJournalEntity)

    @Query(
        "DELETE FROM activity_only_workout_sync_journal " +
            "WHERE id = 1 AND ownerUserId = :ownerUserId " +
            "AND expectedRevision = :expectedRevision AND requestId = :requestId " +
            "AND itemsDigest = :itemsDigest"
    )
    suspend fun deleteExactSyncJournal(
        ownerUserId: String,
        expectedRevision: Long,
        requestId: String,
        itemsDigest: String
    ): Int

    @Query("SELECT * FROM activity_only_workout_sync_baseline WHERE id = 1 LIMIT 1")
    suspend fun getSyncBaseline(): ActivityOnlyWorkoutSyncBaselineEntity?

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insertSyncBaseline(baseline: ActivityOnlyWorkoutSyncBaselineEntity)

    @Query(
        "UPDATE activity_only_workout_sync_baseline SET revision = :revision, " +
            "itemsJson = :itemsJson, itemsDigest = :itemsDigest " +
            "WHERE id = 1 AND ownerUserId = :ownerUserId"
    )
    suspend fun updateOwnerSyncBaseline(
        ownerUserId: String,
        revision: Long,
        itemsJson: String,
        itemsDigest: String
    ): Int
}
