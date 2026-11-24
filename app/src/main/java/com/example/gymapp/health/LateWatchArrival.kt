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
 * same time was already saved. The identical-sets check uses [HealthImportRules.overlaps]
 * (OVERLAP_TOLERANCE_SECONDS on both ends); the activity-only check uses the real intersection.
 *
 * - An arrival with no sets (Garmin free activity) is skipped only when a stored workout with
 *   sets and a positive duration really covers it: their actual time intersection (no tolerance)
 *   is at least half the arrival's duration (a zero-length arrival must lie inside it). A
 *   separate back-to-back session (phone 10:00-11:00, watch run 11:01-11:31) is stored, and a
 *   stored workout without a duration never causes this skip.
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
        if (arrivalSets.isEmpty()) {
            val covered = candidates.any { candidate ->
                candidate.sets.isNotEmpty() &&
                    coversActivity(arrivalStartMillis, arrivalEndMillis, candidate)
            }
            return if (covered) LateWatchArrivalDecision.Skip else LateWatchArrivalDecision.Store
        }
        val overlapping = candidates.filter { candidate ->
            candidate.sets.isNotEmpty() &&
                HealthImportRules.overlaps(
                    arrivalStartMillis,
                    arrivalEndMillis,
                    HealthExistingWorkout(candidate.startMillis, candidate.durationSeconds)
                )
        }
        if (overlapping.isEmpty()) return LateWatchArrivalDecision.Store
        val arrival = canonical(arrivalSets)
        return if (overlapping.any { canonical(it.sets) == arrival }) {
            LateWatchArrivalDecision.Skip
        } else {
            LateWatchArrivalDecision.Store
        }
    }

    /**
     * Whether [candidate] really holds an activity-only arrival: the actual intersection of the
     * two intervals (no tolerance) is at least half the arrival's duration. A zero-length arrival
     * must lie inside the stored workout. A stored workout without a positive duration never
     * covers anything.
     */
    private fun coversActivity(
        arrivalStartMillis: Long,
        arrivalEndMillis: Long,
        candidate: LateWatchStoredWorkout
    ): Boolean {
        val storedDurationSeconds = candidate.durationSeconds
            ?.takeIf { it > 0L }
            ?.coerceAtMost(WorkoutDataLimits.MAX_WORKOUT_DURATION_SECONDS)
            ?: return false
        val storedStart = candidate.startMillis
        val storedEnd = storedStart + storedDurationSeconds * 1_000L
        val arrivalLength = arrivalEndMillis - arrivalStartMillis
        if (arrivalLength <= 0L) return arrivalStartMillis in storedStart..storedEnd
        val intersection = minOf(arrivalEndMillis, storedEnd) - maxOf(arrivalStartMillis, storedStart)
        return intersection > 0L && intersection * 2L >= arrivalLength
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
