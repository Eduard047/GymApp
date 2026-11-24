package com.example.gymapp.health

import com.example.gymapp.data.repository.WorkoutDataLimits

/**
 * One stored workout near a phone workout that is being finished, with the markers that say where
 * it came from. Built from [com.example.gymapp.data.entity.WorkoutOverlapCandidateRow].
 */
internal data class StoredWorkoutOverlapCandidate(
    val startMillis: Long,
    val durationSeconds: Long?,
    /** A Garmin provenance row names this workout. */
    val fromGarmin: Boolean,
    /** A Health Connect / HealthKit import receipt names this workout's start. */
    val fromHealthImport: Boolean
)

/**
 * Pure rule for the "A watch workout already covers this time" prompt (audit P2-1): finishing a
 * phone workout whose time window overlaps a workout that came from a watch (Wear OS, Garmin) or
 * a Health import would store the same session twice. Phone-created workouts never trigger it.
 * Overlap uses [HealthImportRules.overlaps] (OVERLAP_TOLERANCE_SECONDS on both ends).
 */
internal object PhoneDraftWatchOverlap {

    /** How long after a Wear OS workout ends its "create workout" receipt may still arrive. */
    const val WEAR_RECEIPT_WINDOW_MILLIS = 6L * 60 * 60 * 1_000

    /**
     * Wear OS workouts carry no per-workout marker, so a "create workout" receipt (written when the
     * phone stores the watch workout, after it ended) marks [candidate] as a Wear workout when:
     * - the receipt time lies in [start, start + duration + [WEAR_RECEIPT_WINDOW_MILLIS]], and
     * - no other stored workout in [candidates] starts after [candidate] and at or before the
     *   receipt (the receipt then more likely belongs to that later workout).
     * A phone workout followed later by any unrelated Wear receipt is no longer marked.
     */
    fun isFromWear(
        candidate: StoredWorkoutOverlapCandidate,
        candidates: List<StoredWorkoutOverlapCandidate>,
        wearCreateReceiptTimes: List<Long>
    ): Boolean {
        val durationMillis = (candidate.durationSeconds ?: 0L)
            .coerceIn(0L, WorkoutDataLimits.MAX_WORKOUT_DURATION_SECONDS) * 1_000L
        val windowEnd = candidate.startMillis + durationMillis + WEAR_RECEIPT_WINDOW_MILLIS
        return wearCreateReceiptTimes.any { receiptAt ->
            receiptAt >= candidate.startMillis &&
                receiptAt <= windowEnd &&
                candidates.none { other ->
                    other.startMillis > candidate.startMillis && other.startMillis <= receiptAt
                }
        }
    }

    fun isFromWatchOrImport(
        candidate: StoredWorkoutOverlapCandidate,
        candidates: List<StoredWorkoutOverlapCandidate> = listOf(candidate),
        wearCreateReceiptTimes: List<Long> = emptyList()
    ): Boolean =
        candidate.fromGarmin ||
            candidate.fromHealthImport ||
            isFromWear(candidate, candidates, wearCreateReceiptTimes)

    fun watchWorkoutCovers(
        draftStartMillis: Long,
        draftEndMillis: Long,
        candidates: List<StoredWorkoutOverlapCandidate>,
        wearCreateReceiptTimes: List<Long> = emptyList()
    ): Boolean {
        if (draftStartMillis <= 0L || draftEndMillis < draftStartMillis) return false
        return candidates.any { candidate ->
            isFromWatchOrImport(candidate, candidates, wearCreateReceiptTimes) &&
                HealthImportRules.overlaps(
                    draftStartMillis,
                    draftEndMillis,
                    HealthExistingWorkout(candidate.startMillis, candidate.durationSeconds)
                )
        }
    }
}
