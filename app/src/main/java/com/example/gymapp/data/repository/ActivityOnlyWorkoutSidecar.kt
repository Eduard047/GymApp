package com.example.gymapp.data.repository

import java.math.BigDecimal
import java.math.RoundingMode
import java.nio.ByteBuffer
import java.security.MessageDigest

internal const val MAX_ACTIVITY_ONLY_WORKOUT_ITEMS = 5_000
internal const val MAX_ACTIVITY_ONLY_GYM_CALORIES = 100_000.0
internal const val MAX_ACTIVITY_ONLY_HEART_RATE = 240
internal const val MAX_ACTIVITY_ONLY_HEART_RATE_ZONE = 5
internal const val MAX_ACTIVITY_ONLY_NOTE_CODE_POINTS = 512
internal const val MAX_ACTIVITY_ONLY_NOTE_BYTES = 2_048
internal const val MAX_ACTIVITY_ONLY_REVISION = 9_007_199_254_740_991L

data class ActivityOnlyWorkoutItem(
    val workoutStartedAt: Long,
    val durationSeconds: Long,
    val gymCalories: Double,
    val garminCalories: Int? = null,
    val averageHeartRate: Int? = null,
    val maximumHeartRate: Int? = null,
    val endingHeartRateZone: Int? = null,
    val note: String? = null
)

data class ActivityOnlyWorkoutLocalSnapshot(
    val items: List<ActivityOnlyWorkoutItem>
) {
    val digest: String = activityOnlyWorkoutDigest(items)
}

data class ActivityOnlyWorkoutSyncJournalRecord(
    val ownerUserId: String,
    val expectedRevision: Long,
    val requestId: String,
    val itemsJson: String,
    val itemsDigest: String
)

/** Last server snapshot confirmed for exactly one authenticated owner. */
data class ActivityOnlyWorkoutSyncBaselineRecord(
    val ownerUserId: String,
    val revision: Long,
    val itemsJson: String,
    val itemsDigest: String
)

/**
 * Garmin computes calories as a floating-point accumulator while the owner-private RPC stores
 * numeric(9,3). Canonicalize only trusted local sensor output; attacker-controlled remote values
 * are validated without rounding by [requireValidActivityOnlyWorkoutItem].
 */
internal fun canonicalActivityOnlyGymCalories(value: Double): Double {
    require(value.isFinite() && value in 0.0..MAX_ACTIVITY_ONLY_GYM_CALORIES) {
        "Activity-only Gym calories are invalid."
    }
    val rounded = BigDecimal.valueOf(if (value == 0.0) 0.0 else value)
        .setScale(3, RoundingMode.HALF_UP)
        .stripTrailingZeros()
        .toDouble()
    require(rounded in 0.0..MAX_ACTIVITY_ONLY_GYM_CALORIES)
    return if (rounded == 0.0) 0.0 else rounded
}

internal fun requireValidActivityOnlyWorkoutItem(item: ActivityOnlyWorkoutItem) {
    require(WorkoutDataLimits.isValidTimestamp(item.workoutStartedAt)) {
        "Activity-only workout timestamp is invalid."
    }
    require(item.durationSeconds in 1L..WorkoutDataLimits.MAX_WORKOUT_DURATION_SECONDS) {
        "Activity-only workout duration is invalid."
    }
    require(item.gymCalories.isFinite() &&
        item.gymCalories in 0.0..MAX_ACTIVITY_ONLY_GYM_CALORIES &&
        BigDecimal.valueOf(if (item.gymCalories == 0.0) 0.0 else item.gymCalories)
            .stripTrailingZeros().scale() <= 3) {
        "Activity-only Gym calories are invalid."
    }
    require(item.garminCalories == null ||
        item.garminCalories in 0..MAX_ACTIVITY_ONLY_GYM_CALORIES.toInt()) {
        "Activity-only Garmin calories are invalid."
    }
    require(item.averageHeartRate == null ||
        item.averageHeartRate in 0..MAX_ACTIVITY_ONLY_HEART_RATE) {
        "Activity-only average heart rate is invalid."
    }
    require(item.maximumHeartRate == null ||
        item.maximumHeartRate in 0..MAX_ACTIVITY_ONLY_HEART_RATE) {
        "Activity-only maximum heart rate is invalid."
    }
    require(item.averageHeartRate == null || item.maximumHeartRate == null ||
        item.averageHeartRate <= item.maximumHeartRate) {
        "Activity-only heart-rate order is invalid."
    }
    require(item.endingHeartRateZone == null ||
        item.endingHeartRateZone in 0..MAX_ACTIVITY_ONLY_HEART_RATE_ZONE) {
        "Activity-only ending heart-rate zone is invalid."
    }
    item.note?.let { note ->
        require(note.codePointCount(0, note.length) <= MAX_ACTIVITY_ONLY_NOTE_CODE_POINTS &&
            WorkoutDataLimits.utf8ByteLengthAtMost(
                note,
                MAX_ACTIVITY_ONLY_NOTE_BYTES
            ) != null) {
            "Activity-only workout note is invalid."
        }
    }
}

internal fun requireValidActivityOnlyWorkoutItems(
    items: List<ActivityOnlyWorkoutItem>,
    requireSorted: Boolean = true
) {
    require(items.size <= MAX_ACTIVITY_ONLY_WORKOUT_ITEMS) {
        "Activity-only workout snapshot is too large."
    }
    var previousStartedAt: Long? = null
    val seenStartedAt = hashSetOf<Long>()
    items.forEach { item ->
        requireValidActivityOnlyWorkoutItem(item)
        require(seenStartedAt.add(item.workoutStartedAt)) {
            "Activity-only workouts must have unique timestamps."
        }
        previousStartedAt?.let { previous ->
            require(!requireSorted || item.workoutStartedAt > previous) {
                "Activity-only workouts must use ascending timestamps."
            }
        }
        previousStartedAt = item.workoutStartedAt
    }
}

/**
 * Deterministic three-way merge of exact full snapshots, keyed only by the immutable start time.
 * Equality deliberately uses every field so absent optionals, zeroes, empty notes, and null notes
 * remain distinct. A delete/edit race or two divergent edits is ambiguous and therefore fails
 * closed instead of silently resurrecting or overwriting an activity.
 */
internal fun threeWayMergeActivityOnlyWorkoutItems(
    base: List<ActivityOnlyWorkoutItem>,
    local: List<ActivityOnlyWorkoutItem>,
    remote: List<ActivityOnlyWorkoutItem>
): List<ActivityOnlyWorkoutItem> {
    requireValidActivityOnlyWorkoutItems(base)
    requireValidActivityOnlyWorkoutItems(local)
    requireValidActivityOnlyWorkoutItems(remote)

    val baseByStartedAt = base.associateBy(ActivityOnlyWorkoutItem::workoutStartedAt)
    val localByStartedAt = local.associateBy(ActivityOnlyWorkoutItem::workoutStartedAt)
    val remoteByStartedAt = remote.associateBy(ActivityOnlyWorkoutItem::workoutStartedAt)
    val startedAtValues = (baseByStartedAt.keys + localByStartedAt.keys + remoteByStartedAt.keys)
        .toSortedSet()
    require(startedAtValues.size <= MAX_ACTIVITY_ONLY_WORKOUT_ITEMS) {
        "Merged activity-only workout snapshot is too large."
    }

    return buildList {
        startedAtValues.forEach { startedAt ->
            val baseItem = baseByStartedAt[startedAt]
            val localItem = localByStartedAt[startedAt]
            val remoteItem = remoteByStartedAt[startedAt]
            val selected = when {
                localItem == remoteItem -> localItem
                localItem == baseItem -> remoteItem
                remoteItem == baseItem -> localItem
                else -> throw IllegalArgumentException(
                    "Activity-only workout has conflicting edits at $startedAt."
                )
            }
            selected?.let(::add)
        }
    }.also(::requireValidActivityOnlyWorkoutItems)
}

internal fun activityOnlyWorkoutDigest(items: List<ActivityOnlyWorkoutItem>): String {
    requireValidActivityOnlyWorkoutItems(items)
    val digest = MessageDigest.getInstance("SHA-256")

    fun updateLong(value: Long) {
        digest.update(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(value).array())
    }

    fun updateOptionalInt(value: Int?) {
        digest.update(if (value == null) 0.toByte() else 1.toByte())
        value?.let { updateLong(it.toLong()) }
    }

    fun updateOptionalText(value: String?) {
        digest.update(if (value == null) 0.toByte() else 1.toByte())
        value?.let { text ->
            val bytes = text.toByteArray(Charsets.UTF_8)
            updateLong(bytes.size.toLong())
            digest.update(bytes)
        }
    }

    digest.update("GymAppActivityOnlyWorkoutSidecarV1".toByteArray(Charsets.UTF_8))
    updateLong(items.size.toLong())
    items.forEach { item ->
        updateLong(item.workoutStartedAt)
        updateLong(item.durationSeconds)
        updateLong(activityOnlyGymCaloriesMillis(item.gymCalories))
        updateOptionalInt(item.garminCalories)
        updateOptionalInt(item.averageHeartRate)
        updateOptionalInt(item.maximumHeartRate)
        updateOptionalInt(item.endingHeartRateZone)
        updateOptionalText(item.note)
    }
    return digest.digest().joinToString(separator = "") { byte -> "%02x".format(byte) }
}

internal fun activityOnlyGymCaloriesMillis(value: Double): Long {
    requireValidActivityOnlyWorkoutItem(
        ActivityOnlyWorkoutItem(
            workoutStartedAt = 0L,
            durationSeconds = 1L,
            gymCalories = value
        )
    )
    return BigDecimal.valueOf(if (value == 0.0) 0.0 else value)
        .movePointRight(3)
        .setScale(0, RoundingMode.UNNECESSARY)
        .longValueExact()
}
