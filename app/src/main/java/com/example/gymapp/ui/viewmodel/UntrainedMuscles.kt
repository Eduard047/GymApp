package com.example.gymapp.ui.viewmodel

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Major muscles the "Not trained for 10+ days" hint can name, in heatmap display order. This is the
 * set the Balance recommendation already watches; the heatmap has no coarser groups.
 */
internal val UNTRAINED_HINT_MUSCLE_IDS: List<String> =
    listOf("chest", "lats", "upperBack", "glutes", "quads", "hamstrings")

internal const val UNTRAINED_HINT_MIN_WORKOUTS = 3
internal const val UNTRAINED_HINT_RECENT_WORKOUT_DAYS = 30L
internal const val UNTRAINED_HINT_DAYS = 10L
internal const val UNTRAINED_HINT_MAX_GROUPS = 3

/** One logged set: [date] in epoch ms and the muscles it trains with their contribution weights. */
internal data class UntrainedMuscleSet(val date: Long, val reps: Int, val muscles: Map<String, Double>)

/**
 * shared/untrained-muscles-v1.json: ids of major muscles with no training for 10+ local days (or never),
 * never-trained first then longest untrained first, ties in display order, at most 3. Empty for a user
 * with fewer than 3 workouts or no workout in the last 30 days. Only sets with reps > 0 and a positive
 * contribution weight count as training.
 */
internal fun untrainedMuscleIds(
    workoutDates: List<Long>,
    sets: List<UntrainedMuscleSet>,
    now: Long,
    zone: ZoneId
): List<String> {
    if (workoutDates.size < UNTRAINED_HINT_MIN_WORKOUTS) return emptyList()
    val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
    fun dayOf(millis: Long): LocalDate = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
    val hasRecentWorkout = workoutDates.any {
        ChronoUnit.DAYS.between(dayOf(it), today) <= UNTRAINED_HINT_RECENT_WORKOUT_DAYS
    }
    if (!hasRecentWorkout) return emptyList()

    val lastTrained = HashMap<String, LocalDate>()
    sets.forEach { set ->
        if (set.reps <= 0) return@forEach
        val day = dayOf(set.date)
        set.muscles.forEach { (muscleId, weight) ->
            if (weight <= 0.0 || muscleId !in UNTRAINED_HINT_MUSCLE_IDS) return@forEach
            val previous = lastTrained[muscleId]
            if (previous == null || day.isAfter(previous)) lastTrained[muscleId] = day
        }
    }

    return UNTRAINED_HINT_MUSCLE_IDS
        .mapIndexedNotNull { index, muscleId ->
            val last = lastTrained[muscleId]
            val days = if (last == null) Long.MAX_VALUE else ChronoUnit.DAYS.between(last, today)
            if (days >= UNTRAINED_HINT_DAYS) Triple(index, muscleId, days) else null
        }
        .sortedWith(compareByDescending<Triple<Int, String, Long>> { it.third }.thenBy { it.first })
        .take(UNTRAINED_HINT_MAX_GROUPS)
        .map { it.second }
}
