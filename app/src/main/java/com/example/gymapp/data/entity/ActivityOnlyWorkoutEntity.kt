package com.example.gymapp.data.entity

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import com.example.gymapp.data.repository.ActivityOnlyWorkoutSyncJournalRecord
import com.example.gymapp.data.repository.ActivityOnlyWorkoutSyncBaselineRecord
import com.example.gymapp.data.repository.activityOnlyGymCaloriesMillis
import com.example.gymapp.data.repository.requireValidActivityOnlyWorkoutItem

/** Exact offline mirror of the owner-private activity-only Supabase sidecar. */
@Entity(tableName = "activity_only_workouts")
data class ActivityOnlyWorkoutEntity(
    @PrimaryKey val workoutStartedAt: Long,
    val durationSeconds: Long,
    val gymCaloriesMillis: Long,
    val garminCalories: Int?,
    val averageHeartRate: Int?,
    val maximumHeartRate: Int?,
    val endingHeartRateZone: Int?,
    val note: String?
) {
    fun toItem(): ActivityOnlyWorkoutItem = ActivityOnlyWorkoutItem(
        workoutStartedAt = workoutStartedAt,
        durationSeconds = durationSeconds,
        gymCalories = gymCaloriesMillis.toDouble() / 1_000.0,
        garminCalories = garminCalories,
        averageHeartRate = averageHeartRate,
        maximumHeartRate = maximumHeartRate,
        endingHeartRateZone = endingHeartRateZone,
        note = note
    ).also(::requireValidActivityOnlyWorkoutItem)

    companion object {
        fun fromItem(item: ActivityOnlyWorkoutItem): ActivityOnlyWorkoutEntity {
            requireValidActivityOnlyWorkoutItem(item)
            return ActivityOnlyWorkoutEntity(
                workoutStartedAt = item.workoutStartedAt,
                durationSeconds = item.durationSeconds,
                gymCaloriesMillis = activityOnlyGymCaloriesMillis(item.gymCalories),
                garminCalories = item.garminCalories,
                averageHeartRate = item.averageHeartRate,
                maximumHeartRate = item.maximumHeartRate,
                endingHeartRateZone = item.endingHeartRateZone,
                note = item.note
            )
        }
    }
}

/**
 * One durable outcome-unknown CAS attempt for this account database. The exact JSON array is
 * retained because local workouts may continue changing before the server outcome is known.
 */
@Entity(tableName = "activity_only_workout_sync_journal")
data class ActivityOnlyWorkoutSyncJournalEntity(
    @PrimaryKey val id: Int = 1,
    val ownerUserId: String,
    val expectedRevision: Long,
    val requestId: String,
    val itemsJson: String,
    val itemsDigest: String
) {
    fun toRecord(): ActivityOnlyWorkoutSyncJournalRecord =
        ActivityOnlyWorkoutSyncJournalRecord(
            ownerUserId = ownerUserId,
            expectedRevision = expectedRevision,
            requestId = requestId,
            itemsJson = itemsJson,
            itemsDigest = itemsDigest
        )

    companion object {
        fun fromRecord(
            record: ActivityOnlyWorkoutSyncJournalRecord
        ): ActivityOnlyWorkoutSyncJournalEntity = ActivityOnlyWorkoutSyncJournalEntity(
            ownerUserId = record.ownerUserId,
            expectedRevision = record.expectedRevision,
            requestId = record.requestId,
            itemsJson = record.itemsJson,
            itemsDigest = record.itemsDigest
        )
    }
}

/** Exact canonical server baseline used to distinguish deletion from unchanged absence. */
@Entity(tableName = "activity_only_workout_sync_baseline")
data class ActivityOnlyWorkoutSyncBaselineEntity(
    @PrimaryKey val id: Int = 1,
    val ownerUserId: String,
    val revision: Long,
    val itemsJson: String,
    val itemsDigest: String
) {
    fun toRecord(): ActivityOnlyWorkoutSyncBaselineRecord =
        ActivityOnlyWorkoutSyncBaselineRecord(
            ownerUserId = ownerUserId,
            revision = revision,
            itemsJson = itemsJson,
            itemsDigest = itemsDigest
        )

    companion object {
        fun fromRecord(
            record: ActivityOnlyWorkoutSyncBaselineRecord
        ): ActivityOnlyWorkoutSyncBaselineEntity = ActivityOnlyWorkoutSyncBaselineEntity(
            ownerUserId = record.ownerUserId,
            revision = record.revision,
            itemsJson = record.itemsJson,
            itemsDigest = record.itemsDigest
        )
    }
}
