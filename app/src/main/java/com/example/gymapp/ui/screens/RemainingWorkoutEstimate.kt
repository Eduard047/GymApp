package com.example.gymapp.ui.screens

/**
 * "N sets left · ~M min" for the active workout (shared/remaining-workout-estimate-v1.json; the
 * iPhone twin is RemainingWorkoutEstimate.swift).
 *
 * `setsLeft` is the number of sets not yet recorded. `minutes` applies the plan-duration
 * coefficients (3 min per exercise, 2 min per set) to what is left: `3 * exercisesWithSetsLeft +
 * 2 * setsLeft`, never less than 1. The plan estimate's 10-minute floor and 90-minute cap are
 * deliberately not applied, so one remaining set does not read "~10 min". No sets left means no
 * estimate. A running rest timer is ignored.
 */
internal object RemainingWorkoutEstimate {
    const val MINUTES_PER_EXERCISE = 3
    const val MINUTES_PER_SET = 2

    data class Result(val setsLeft: Int, val minutes: Int)

    /** [remainingSetsPerExercise] is the unrecorded set count of each exercise; negatives count as 0. */
    fun estimate(remainingSetsPerExercise: List<Int>): Result? {
        val counts = remainingSetsPerExercise.map { it.coerceAtLeast(0) }
        val setsLeft = counts.sum()
        if (setsLeft <= 0) return null
        val exercisesLeft = counts.count { it > 0 }
        val minutes = (MINUTES_PER_EXERCISE * exercisesLeft + MINUTES_PER_SET * setsLeft).coerceAtLeast(1)
        return Result(setsLeft = setsLeft, minutes = minutes)
    }
}
