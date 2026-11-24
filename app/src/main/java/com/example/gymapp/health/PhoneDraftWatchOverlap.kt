package com.example.gymapp.health

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
    val fromHealthImport: Boolean,
    /** Newest Wear OS "create workout" receipt on this phone, or null when there is none. */
    val latestWearCreateReceiptAt: Long?
)

/**
 * Pure rule for the "A watch workout already covers this time" prompt (audit P2-1): finishing a
 * phone workout whose time window overlaps a workout that came from a watch (Wear OS, Garmin) or
 * a Health import would store the same session twice. Phone-created workouts never trigger it.
 * Overlap uses [HealthImportRules.overlaps] (OVERLAP_TOLERANCE_SECONDS on both ends).
 */
internal object PhoneDraftWatchOverlap {

    /**
     * Wear OS workouts carry no per-workout marker; a "create workout" receipt can only be written
     * after the watch workout started, so a receipt at or after [StoredWorkoutOverlapCandidate.startMillis]
     * marks it as a watch workout.
     */
    fun isFromWatchOrImport(candidate: StoredWorkoutOverlapCandidate): Boolean =
        candidate.fromGarmin ||
            candidate.fromHealthImport ||
            (candidate.latestWearCreateReceiptAt != null &&
                candidate.latestWearCreateReceiptAt >= candidate.startMillis)

    fun watchWorkoutCovers(
        draftStartMillis: Long,
        draftEndMillis: Long,
        candidates: List<StoredWorkoutOverlapCandidate>
    ): Boolean {
        if (draftStartMillis <= 0L || draftEndMillis < draftStartMillis) return false
        return candidates.any { candidate ->
            isFromWatchOrImport(candidate) &&
                HealthImportRules.overlaps(
                    draftStartMillis,
                    draftEndMillis,
                    HealthExistingWorkout(candidate.startMillis, candidate.durationSeconds)
                )
        }
    }
}
