package com.example.gymapp.data.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.example.gymapp.data.entity.HealthImportReceiptEntity
import com.example.gymapp.data.entity.HealthImportStateEntity
import com.example.gymapp.data.entity.HealthWorkoutIntervalRow
import com.example.gymapp.data.entity.WorkoutOverlapCandidateRow

@Dao
interface HealthImportDao {
    @Query("SELECT receiptKey FROM health_import_receipts WHERE receiptKey IN (:keys)")
    suspend fun existingReceiptKeys(keys: List<String>): List<String>

    @Query("SELECT COUNT(*) FROM health_import_receipts WHERE receiptKey = :receiptKey")
    suspend fun countReceipt(receiptKey: String): Int

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertReceipt(receipt: HealthImportReceiptEntity): Long

    @Query(
        "SELECT date AS startMillis, durationSeconds AS durationSeconds " +
            "FROM workout_sessions WHERE date >= :fromMillis ORDER BY date ASC"
    )
    suspend fun workoutIntervalsFrom(fromMillis: Long): List<HealthWorkoutIntervalRow>

    /**
     * Workouts starting in [fromMillis, toMillis] with their source markers: a Garmin provenance
     * row and a Health import receipt for the same start. Wear OS workouts are matched per
     * workout from [wearCreateReceiptTimesFrom] (see PhoneDraftWatchOverlap.isFromWear).
     */
    @Query(
        "SELECT s.date AS startMillis, s.durationSeconds AS durationSeconds, " +
            "EXISTS (SELECT 1 FROM garmin_workout_provenance p WHERE p.workoutSessionId = s.id) " +
            "AS fromGarmin, " +
            "EXISTS (SELECT 1 FROM health_import_receipts r WHERE r.workoutStartedAt = s.date) " +
            "AS fromHealthImport " +
            "FROM workout_sessions s WHERE s.date BETWEEN :fromMillis AND :toMillis " +
            "ORDER BY s.date ASC LIMIT 200"
    )
    suspend fun workoutOverlapCandidates(
        fromMillis: Long,
        toMillis: Long
    ): List<WorkoutOverlapCandidateRow>

    /** Times of the Wear OS "create workout" receipts written at or after [fromMillis]. */
    @Query(
        "SELECT createdAt FROM wear_mutation_receipts " +
            "WHERE mutationType = :wearCreateMutationType AND createdAt >= :fromMillis " +
            "ORDER BY createdAt ASC LIMIT 500"
    )
    suspend fun wearCreateReceiptTimesFrom(
        fromMillis: Long,
        wearCreateMutationType: String
    ): List<Long>

    /**
     * Counts workouts whose interval [date, date + duration] touches [windowStart, windowEnd].
     * The caller passes the imported interval widened by the overlap tolerance.
     */
    @Query(
        "SELECT COUNT(*) FROM workout_sessions " +
            "WHERE date <= :windowEnd " +
            "AND date + MIN(MAX(COALESCE(durationSeconds, 0), 0), :maxDurationSeconds) * 1000 " +
            ">= :windowStart"
    )
    suspend fun countOverlappingWorkouts(
        windowStart: Long,
        windowEnd: Long,
        maxDurationSeconds: Long
    ): Int

    @Query("SELECT COUNT(*) FROM health_import_receipts")
    suspend fun countReceipts(): Int

    /** Receipts whose imported workout started exactly at [workoutStartedAt]. */
    @Query("SELECT COUNT(*) FROM health_import_receipts WHERE workoutStartedAt = :workoutStartedAt")
    suspend fun countReceiptsForWorkoutStartedAt(workoutStartedAt: Long): Int

    @Query("SELECT * FROM health_import_state WHERE id = 1 LIMIT 1")
    suspend fun getState(): HealthImportStateEntity?

    /** Creates the default (disabled, never imported) row; keeps an existing row untouched. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertStateIfMissing(state: HealthImportStateEntity): Long

    @Query("UPDATE health_import_state SET lastImportAt = :millis WHERE id = 1")
    suspend fun updateLastImportAt(millis: Long): Int

    @Query("UPDATE health_import_state SET enabled = :enabled WHERE id = 1")
    suspend fun updateEnabled(enabled: Boolean): Int
}
