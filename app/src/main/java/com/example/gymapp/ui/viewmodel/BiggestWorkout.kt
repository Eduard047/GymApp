package com.example.gymapp.ui.viewmodel

import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId

/** Hero chip of the post-workout summary when the finished workout is the biggest by volume. */
enum class BiggestWorkoutBadge(val wire: String) {
    Ever("ever"),
    Month("month")
}

/** A workout earlier than the finished one: [date] in epoch ms, [volume] = sum of weight x reps. */
data class BiggestWorkoutSession(val id: Long, val date: Long, val volume: Double)

/** Earlier workouts needed before "biggest ever" means anything. */
internal const val BIGGEST_WORKOUT_MIN_EARLIER_EVER = 3

/** Earlier workouts in the same calendar month needed before "biggest this month" means anything. */
internal const val BIGGEST_WORKOUT_MIN_EARLIER_MONTH = 2

private const val BIGGEST_WORKOUT_EPSILON = 1e-9

/**
 * shared/biggest-workout-v1.json: "ever" when there are at least 3 earlier workouts and the finished
 * volume is strictly greater than every one of them, else "month" when at least 2 earlier workouts
 * share the finished workout's calendar month in [zone] and it is strictly greater than each of
 * them, else null. A workout without volume never gets a chip; "ever" wins over "month".
 */
internal fun biggestWorkoutBadge(
    earlier: List<BiggestWorkoutSession>,
    currentDate: Long,
    currentVolume: Double,
    zone: ZoneId
): BiggestWorkoutBadge? {
    if (currentVolume <= BIGGEST_WORKOUT_EPSILON) return null
    fun beatsAll(sessions: List<BiggestWorkoutSession>) =
        sessions.all { currentVolume > it.volume + BIGGEST_WORKOUT_EPSILON }

    if (earlier.size >= BIGGEST_WORKOUT_MIN_EARLIER_EVER && beatsAll(earlier)) {
        return BiggestWorkoutBadge.Ever
    }
    val currentMonth = YearMonth.from(Instant.ofEpochMilli(currentDate).atZone(zone))
    val sameMonth = earlier.filter {
        YearMonth.from(Instant.ofEpochMilli(it.date).atZone(zone)) == currentMonth
    }
    return if (sameMonth.size >= BIGGEST_WORKOUT_MIN_EARLIER_MONTH && beatsAll(sameMonth)) {
        BiggestWorkoutBadge.Month
    } else {
        null
    }
}
