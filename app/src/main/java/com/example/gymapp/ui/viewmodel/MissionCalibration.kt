package com.example.gymapp.ui.viewmodel

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.TemporalAdjusters

internal data class MissionCalendarWindows(
    val dayStartInclusive: LocalDate,
    val dayEndInclusive: LocalDate,
    val completedWeekStartInclusive: LocalDate,
    val currentWeekStartExclusive: LocalDate,
    val completedMonthStartInclusive: YearMonth,
    val currentMonthStartExclusive: YearMonth,
    val sessionStartInclusive: LocalDate
) {
    fun containsRecentDay(day: LocalDate): Boolean =
        day >= dayStartInclusive && day <= dayEndInclusive

    fun containsCompletedWeek(weekStart: LocalDate): Boolean =
        weekStart >= completedWeekStartInclusive && weekStart < currentWeekStartExclusive

    fun containsCompletedMonth(month: YearMonth): Boolean =
        month >= completedMonthStartInclusive && month < currentMonthStartExclusive

    fun containsRecentSession(day: LocalDate): Boolean =
        day >= sessionStartInclusive && day <= dayEndInclusive
}

internal fun missionCalendarWindows(today: LocalDate): MissionCalendarWindows {
    val currentWeekStart = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val currentMonth = YearMonth.from(today)
    val completedMonthStart = currentMonth.minusMonths(RECENT_MISSION_MONTHS)
    return MissionCalendarWindows(
        dayStartInclusive = today.minusDays(RECENT_MISSION_DAYS),
        dayEndInclusive = today.minusDays(1),
        completedWeekStartInclusive = currentWeekStart.minusWeeks(RECENT_MISSION_WEEKS),
        currentWeekStartExclusive = currentWeekStart,
        completedMonthStartInclusive = completedMonthStart,
        currentMonthStartExclusive = currentMonth,
        sessionStartInclusive = completedMonthStart.atDay(1)
    )
}

/**
 * Returns a conservative recent baseline for mission selection.
 *
 * Sparse history uses the family fallback. With enough samples, the lower median
 * keeps a personal record from turning every future mission into a personal record.
 */
internal fun realisticMissionBaseline(values: Iterable<Int>, fallback: Int): Int {
    require(fallback >= 0)
    val sorted = values.filter { it > 0 }.sorted()
    if (sorted.size < 2) {
        return fallback
    }
    val baseline = sorted.getOrElse((sorted.size - 1) / 2) { 0 }
    return baseline
}

internal fun missionSelectionMetric(family: String): String = when (family) {
    "active-days" -> "workouts"
    "max-session-volume", "days-1000-volume" -> "volume"
    "max-session-exercises", "sessions-3-exercises" -> "exercises"
    "max-session-sets", "days-10-sets", "sessions-8-sets" -> "sets"
    else -> family
}

private const val RECENT_MISSION_DAYS = 42L
private const val RECENT_MISSION_WEEKS = 8L
private const val RECENT_MISSION_MONTHS = 6L
