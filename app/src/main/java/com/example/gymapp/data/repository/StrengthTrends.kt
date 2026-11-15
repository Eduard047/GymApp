package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry

/** Recent strength of one exercise: its heaviest set in the window and how that weight moved. */
data class StrengthTrend(
    val exerciseId: Long,
    val exerciseName: String,
    val bestWeight: Double,
    val bestReps: Int,
    /** Best weight in the window minus best weight in the previous window; null with no sets there. */
    val deltaKg: Double?
)

private const val DAY_MILLIS = 24L * 60L * 60L * 1000L

/**
 * Shared rule (shared/strength-trends-v1.json, same on iOS): the window is the last [windowDays] days,
 * the previous window the [windowDays] days before it. The [limit] exercises with the most logged sets
 * in the window are ranked (ties by exercise id). Each one's best set is its heaviest set in the window
 * (ties: more reps) and the delta is that weight minus the heaviest set of the previous window, null
 * when the exercise has no sets there. Sets without a positive weight (bodyweight) are ignored.
 */
fun buildStrengthTrends(
    history: List<ExerciseHistoryEntry>,
    now: Long = System.currentTimeMillis(),
    windowDays: Int = 30,
    limit: Int = 3
): List<StrengthTrend> {
    val windowStart = now - windowDays * DAY_MILLIS
    val previousStart = now - 2L * windowDays * DAY_MILLIS
    val valid = history.filter {
        it.sessionDate <= now && it.sessionDate >= previousStart && it.weight.isFinite() &&
            it.weight > 0.0 && it.weight <= 1_000_000.0 && it.reps in 1..10_000
    }
    val (recent, previous) = valid.partition { it.sessionDate >= windowStart }
    val previousBest = previous.groupBy { it.exerciseId }
        .mapValues { (_, sets) -> sets.maxOf { it.weight } }
    return recent.groupBy { it.exerciseId }.values
        .sortedWith(
            compareByDescending<List<ExerciseHistoryEntry>> { it.size }
                .thenBy { it.first().exerciseId }
        )
        .take(limit)
        .map { sets ->
            val best = sets.maxWith(
                compareBy<ExerciseHistoryEntry> { it.weight }
                    .thenBy { it.reps }
                    .thenBy { it.sessionDate }
            )
            val latest = sets.maxBy { it.sessionDate }
            StrengthTrend(
                exerciseId = best.exerciseId,
                exerciseName = latest.exerciseName,
                bestWeight = best.weight,
                bestReps = best.reps,
                deltaKg = previousBest[best.exerciseId]?.let { best.weight - it }
            )
        }
}
