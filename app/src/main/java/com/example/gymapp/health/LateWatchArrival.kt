package com.example.gymapp.health

import com.example.gymapp.data.repository.WorkoutDataLimits
import java.util.Locale

/** One logged set, as the watch sent it or as a stored workout keeps it. */
internal data class LateWatchSet(
    val exerciseName: String,
    val weight: Double,
    val reps: Int
)

/** A stored workout near a late watch arrival, with its sets in stored order (may be empty). */
internal data class LateWatchStoredWorkout(
    val startMillis: Long,
    val durationSeconds: Long?,
    val sets: List<LateWatchSet>
)

internal enum class LateWatchArrivalDecision {
    /** Store the arrival as today (keep both when anything overlaps). */
    Store,

    /** The arrival is already covered by a stored workout: store nothing, acknowledge it as applied. */
    Skip
}

/**
 * Pure rule for a watch workout (Wear OS, Garmin) that reaches the phone after a workout for the
 * same time was already saved. Overlap uses [HealthImportRules.overlaps]
 * (OVERLAP_TOLERANCE_SECONDS on both ends).
 *
 * - An arrival with no sets (Garmin free activity) that overlaps a stored workout with sets is
 *   skipped: the stored workout already records the session.
 * - An arrival with sets is skipped only when an overlapping stored workout has exactly the same
 *   sets (same exercise names after trim and case folding, same weights, reps and order). Any
 *   difference stores the arrival, so no differing workout is ever dropped.
 * - Everything else is stored.
 */
internal object LateWatchArrivalRule {

    fun decide(
        arrivalStartMillis: Long,
        arrivalDurationSeconds: Long?,
        arrivalSets: List<LateWatchSet>,
        candidates: List<LateWatchStoredWorkout>
    ): LateWatchArrivalDecision {
        if (arrivalStartMillis <= 0L) return LateWatchArrivalDecision.Store
        val durationSeconds = arrivalDurationSeconds
            ?.takeIf { it > 0L }
            ?.coerceAtMost(WorkoutDataLimits.MAX_WORKOUT_DURATION_SECONDS)
            ?: 0L
        val arrivalEndMillis = arrivalStartMillis + durationSeconds * 1_000L
        val overlapping = candidates.filter { candidate ->
            candidate.sets.isNotEmpty() &&
                HealthImportRules.overlaps(
                    arrivalStartMillis,
                    arrivalEndMillis,
                    HealthExistingWorkout(candidate.startMillis, candidate.durationSeconds)
                )
        }
        if (overlapping.isEmpty()) return LateWatchArrivalDecision.Store
        if (arrivalSets.isEmpty()) return LateWatchArrivalDecision.Skip
        val arrival = canonical(arrivalSets)
        return if (overlapping.any { canonical(it.sets) == arrival }) {
            LateWatchArrivalDecision.Skip
        } else {
            LateWatchArrivalDecision.Store
        }
    }

    /**
     * Sets grouped by exercise in first-seen order, the order a stored workout keeps them in
     * (the phone groups a watch workout's sets per exercise when it stores them). Set order inside
     * each exercise is preserved.
     */
    private fun canonical(sets: List<LateWatchSet>): List<Triple<String, Double, Int>> {
        val grouped = linkedMapOf<String, MutableList<Triple<String, Double, Int>>>()
        sets.forEach { set ->
            val name = set.exerciseName.trim().lowercase(Locale.ROOT)
            // +0.0 normalises -0.0 so equal weights compare equal in the Triple.
            grouped.getOrPut(name) { mutableListOf() }.add(Triple(name, set.weight + 0.0, set.reps))
        }
        return grouped.values.flatten()
    }
}
