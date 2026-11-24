package com.example.gymapp.data.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Durable idempotency receipt for a workout imported from Health Connect (or HealthKit on iPhone).
 *
 * The database is already scoped to one account, so the key alone is unique. Receipts intentionally
 * survive workout deletion so a workout the user deleted is never imported again.
 * See shared/health-import-v1.json.
 */
@Entity(tableName = "health_import_receipts")
data class HealthImportReceiptEntity(
    @PrimaryKey val receiptKey: String,
    val importedAt: Long,
    val workoutStartedAt: Long
)

/**
 * Single-row state of this account's health import: when the last completed run finished and
 * whether the account opted in. Health Connect permission is per app, not per account, so the
 * import never runs for an account that has not enabled it itself.
 */
@Entity(tableName = "health_import_state")
data class HealthImportStateEntity(
    @PrimaryKey val id: Int = 1,
    val lastImportAt: Long? = null,
    @ColumnInfo(defaultValue = "0") val enabled: Boolean = false
)

/** Start and duration of one local workout, used for the import overlap check. */
data class HealthWorkoutIntervalRow(
    val startMillis: Long,
    val durationSeconds: Long?
)

/**
 * A local workout near a phone workout being finished, with its source markers
 * (see com.example.gymapp.health.PhoneDraftWatchOverlap).
 */
data class WorkoutOverlapCandidateRow(
    val startMillis: Long,
    val durationSeconds: Long?,
    val fromGarmin: Boolean,
    val fromHealthImport: Boolean,
    val latestWearCreateReceiptAt: Long?
)
