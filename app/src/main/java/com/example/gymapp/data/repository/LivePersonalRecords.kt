package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry

/**
 * Epley one-rep-max estimate. Live records use the same formula as iOS so records never diverge
 * between clients.
 */
internal object GymOneRepMax {
    fun estimate(weight: Double, reps: Int): Double = weight * (1 + reps / 30.0)
}

/** History-only bests for one exercise, taken before the current workout. */
internal data class PersonalRecordBaseline(
    val bestWeight: Double,
    val bestEstimatedOneRepMax: Double
)

/** Which record kinds one set achieves; both false when it is no record. */
internal data class RecordEvaluation(val weight: Boolean, val estimatedOneRepMax: Boolean) {
    val isRecord: Boolean get() = weight || estimatedOneRepMax
}

/** One completed set of the running workout, in the order the athlete sees it. */
internal data class LiveCompletedSet(
    val exerciseId: Long,
    val setId: String,
    val weight: Double,
    val reps: Int,
    val completedAt: Long,
    val exerciseIndex: Int,
    val setIndex: Int
)

/**
 * Detects personal records while a workout is running.
 *
 * Rules: an exercise needs logged history (its first session never sets a record); a 0 kg set is
 * never a record; matching the best is not a record; and each set is compared with the better of
 * the history best and every set recorded earlier in this workout. Records are derived from the
 * workout rather than stored, so undoing a set removes its record as well.
 */
internal object LivePersonalRecords {
    /** Tolerance for comparing estimates computed from different weight/rep pairs. */
    private const val ESTIMATE_TOLERANCE = 1e-9

    fun baselines(history: List<ExerciseHistoryEntry>): Map<Long, PersonalRecordBaseline> =
        history.groupBy { it.exerciseId }.mapValues { (_, entries) ->
            PersonalRecordBaseline(
                bestWeight = entries.maxOf { it.weight },
                bestEstimatedOneRepMax = entries.maxOf { GymOneRepMax.estimate(it.weight, it.reps) }
            )
        }

    /**
     * Which record kinds one set achieves against the best seen so far (same rule as iOS
     * `LivePersonalRecords.evaluate`). A 0 kg set never qualifies; weight must be strictly greater;
     * the estimate must exceed the best by more than the tolerance.
     */
    fun evaluate(weight: Double, reps: Int, best: PersonalRecordBaseline): RecordEvaluation {
        if (weight <= 0.0) return RecordEvaluation(weight = false, estimatedOneRepMax = false)
        val estimate = GymOneRepMax.estimate(weight, reps)
        return RecordEvaluation(
            weight = weight > best.bestWeight,
            estimatedOneRepMax = estimate > best.bestEstimatedOneRepMax + ESTIMATE_TOLERANCE
        )
    }

    /** The running best after a set has been performed (a 0 kg set changes nothing). */
    fun advanced(best: PersonalRecordBaseline, weight: Double, reps: Int): PersonalRecordBaseline {
        if (weight <= 0.0) return best
        return PersonalRecordBaseline(
            bestWeight = maxOf(best.bestWeight, weight),
            bestEstimatedOneRepMax = maxOf(best.bestEstimatedOneRepMax, GymOneRepMax.estimate(weight, reps))
        )
    }

    fun recordSetIds(
        completed: List<LiveCompletedSet>,
        baselines: Map<Long, PersonalRecordBaseline>
    ): Set<String> {
        val ordered = completed.sortedWith(
            compareBy<LiveCompletedSet> { it.completedAt }
                .thenBy { it.exerciseIndex }
                .thenBy { it.setIndex }
        )
        val bests = baselines.toMutableMap()
        val records = mutableSetOf<String>()
        for (entry in ordered) {
            if (entry.weight <= 0.0) continue
            val best = bests[entry.exerciseId] ?: continue
            if (LivePersonalRecords.evaluate(entry.weight, entry.reps, best).isRecord) records += entry.setId
            bests[entry.exerciseId] = advanced(best, entry.weight, entry.reps)
        }
        return records
    }
}
