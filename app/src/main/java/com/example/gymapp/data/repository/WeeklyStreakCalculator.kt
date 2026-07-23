package com.example.gymapp.data.repository

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

internal object WeeklyStreakCalculator {
    private const val MIN_WORKOUTS_PER_WEEK = 3

    fun current(
        sessionTimestamps: List<Long>,
        nowMillis: Long,
        zoneId: ZoneId
    ): Int {
        val counts = weeklyCounts(sessionTimestamps, zoneId)
        if (counts.isEmpty()) return 0

        var cursor = localDate(nowMillis, zoneId).mondayStart()
        if ((counts[cursor] ?: 0) < MIN_WORKOUTS_PER_WEEK) {
            cursor = cursor.minusWeeks(1)
        }

        var streak = 0
        while ((counts[cursor] ?: 0) >= MIN_WORKOUTS_PER_WEEK) {
            streak += 1
            cursor = cursor.minusWeeks(1)
        }
        return streak
    }

    fun bestDuringPeriod(
        sessionTimestamps: List<Long>,
        periodStartMillis: Long,
        periodEndMillis: Long,
        zoneId: ZoneId
    ): Int {
        if (periodEndMillis < periodStartMillis) return 0

        val validSessions = sessionTimestamps.mapNotNull { timestamp ->
            runCatching { localDate(timestamp, zoneId) }.getOrNull()
        }
        val periodStart = localDate(periodStartMillis, zoneId)
        val periodEnd = localDate(periodEndMillis, zoneId)
        val periodWorkoutWeeks = validSessions
            .filter { it in periodStart..periodEnd }
            .map { it.mondayStart() }
            .toSet()
        if (periodWorkoutWeeks.isEmpty()) return 0

        val counts = validSessions.groupingBy { it.mondayStart() }.eachCount()
        val successfulWeeks = counts
            .filterValues { it >= MIN_WORKOUTS_PER_WEEK }
            .keys
            .sorted()

        var previousWeek: LocalDate? = null
        var running = 0
        var best = 0
        successfulWeeks.forEach { weekStart ->
            running = if (previousWeek?.plusWeeks(1) == weekStart) running + 1 else 1
            if (weekStart in periodWorkoutWeeks) {
                best = maxOf(best, running)
            }
            previousWeek = weekStart
        }
        return best
    }

    private fun weeklyCounts(
        sessionTimestamps: List<Long>,
        zoneId: ZoneId
    ): Map<LocalDate, Int> = sessionTimestamps
        .mapNotNull { timestamp -> runCatching { localDate(timestamp, zoneId) }.getOrNull() }
        .groupingBy { it.mondayStart() }
        .eachCount()

    private fun localDate(timestamp: Long, zoneId: ZoneId): LocalDate =
        Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate()

    private fun LocalDate.mondayStart(): LocalDate =
        with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
}
