package com.example.gymapp.data.repository

/** One completed set of a saved exercise, as the best-set picker sees it. */
internal data class BestSetCandidate(
    val weight: Double,
    val reps: Int,
    val isPersonalRecord: Boolean
)

/**
 * Picks the set to tag "Best" in a past workout. Same rules as iOS (shared/best-set-v1.json):
 * needs at least two completed sets (reps above zero); the best set has the highest estimated
 * one-rep max, ties go to the heavier weight, then the earlier set; 0 kg sets are ignored unless
 * every set is 0 kg, in which case the most reps wins. A set already marked as a personal record
 * keeps its record badge, so nothing is tagged then.
 */
internal object BestSetSelection {
    private const val ESTIMATE_TOLERANCE = 1e-9

    /** Index into [sets] of the best set, or null when no set should be tagged. */
    fun bestIndex(sets: List<BestSetCandidate>): Int? {
        val completed = sets.withIndex().filter { it.value.reps > 0 && it.value.weight >= 0.0 }
        if (completed.size < 2) return null
        val allBodyweight = completed.all { it.value.weight <= 0.0 }
        val pool = if (allBodyweight) completed else completed.filter { it.value.weight > 0.0 }
        var best: IndexedValue<BestSetCandidate>? = null
        for (entry in pool) {
            val current = best
            if (current == null || beats(entry.value, current.value, allBodyweight)) best = entry
        }
        val winner = best ?: return null
        return if (winner.value.isPersonalRecord) null else winner.index
    }

    /** True when [candidate] strictly beats [incumbent]; equal sets keep the earlier one. */
    private fun beats(candidate: BestSetCandidate, incumbent: BestSetCandidate, byReps: Boolean): Boolean {
        if (byReps) return candidate.reps > incumbent.reps
        val candidateEstimate = GymOneRepMax.estimate(candidate.weight, candidate.reps)
        val incumbentEstimate = GymOneRepMax.estimate(incumbent.weight, incumbent.reps)
        if (candidateEstimate > incumbentEstimate + ESTIMATE_TOLERANCE) return true
        if (candidateEstimate < incumbentEstimate - ESTIMATE_TOLERANCE) return false
        return candidate.weight > incumbent.weight
    }
}
