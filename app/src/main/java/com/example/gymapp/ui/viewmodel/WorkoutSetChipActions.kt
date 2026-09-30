package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.parseWeightInputOrNull

/** Pure per-set quick actions for the workout plan editor chips (Last, Prev., +2.5, Copy). */
internal const val WORKOUT_SET_QUICK_WEIGHT_STEP = 2.5

internal fun formatPlanWeight(weight: Double): String =
    if (weight % 1.0 == 0.0) {
        weight.toInt().toString()
    } else {
        String.format(java.util.Locale.US, "%.1f", weight)
    }

/** Sets this set's weight to the last logged weight; null when there is nothing to apply. */
internal fun List<SetInputState>.withLastWeightAt(index: Int, lastWeight: Double?): List<SetInputState>? {
    if (lastWeight == null || index !in indices) return null
    val formatted = formatPlanWeight(lastWeight)
    if (this[index].weight == formatted) return null
    return mapIndexed { i, set -> if (i == index) set.copy(weight = formatted) else set }
}

/** Copies weight and reps from the previous set; unavailable for the first set. */
internal fun List<SetInputState>.withPreviousSetCopiedAt(index: Int): List<SetInputState>? {
    if (index <= 0 || index !in indices) return null
    val previous = this[index - 1]
    if (this[index].weight == previous.weight && this[index].reps == previous.reps) return null
    return mapIndexed { i, set ->
        if (i == index) set.copy(weight = previous.weight, reps = previous.reps) else set
    }
}

/**
 * Adds [delta] to this set's weight (a blank weight counts as 0). Returns null when the current
 * text is not a valid weight or the result would leave the accepted range.
 */
internal fun List<SetInputState>.withWeightAddedAt(
    index: Int,
    delta: Double = WORKOUT_SET_QUICK_WEIGHT_STEP
): List<SetInputState>? {
    if (index !in indices) return null
    val current = this[index].weight
    val base = if (current.isBlank()) 0.0 else parseWeightInputOrNull(current) ?: return null
    val adjusted = base + delta
    if (!WorkoutDataLimits.isValidWeight(adjusted)) return null
    return mapIndexed { i, set -> if (i == index) set.copy(weight = formatPlanWeight(adjusted)) else set }
}

/** Inserts a duplicate right after [index]; null when the index is invalid or the set cap is hit. */
internal fun List<SetInputState>.withSetDuplicatedAfter(
    index: Int,
    maxSets: Int = WorkoutDataLimits.MAX_SETS_PER_EXERCISE
): List<SetInputState>? {
    if (index !in indices || size >= maxSets) return null
    return take(index + 1) + this[index].copy() + drop(index + 1)
}
