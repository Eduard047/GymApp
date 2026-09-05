package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters

data class WeeklyReviewInsight(val previous: ExerciseHistoryEntry, val current: ExerciseHistoryEntry)
data class WeeklyReview(
    val start: LocalDate,
    val end: LocalDate,
    val partial: Boolean,
    val trainingDays: Int,
    val sessions: List<Pair<Long, Long>>,
    val comparableCount: Int,
    val insights: List<WeeklyReviewInsight>
) {
    companion object {
        fun build(history: List<ExerciseHistoryEntry>, offset: Int = 0,
                  now: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault()): WeeklyReview {
            require(offset in -520..0)
            val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
            val start = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).plusWeeks(offset.toLong())
            val end = start.plusWeeks(1)
            val from = start.atStartOfDay(zone).toInstant().toEpochMilli()
            val until = end.atStartOfDay(zone).toInstant().toEpochMilli()
            val before = start.minusWeeks(1).atStartOfDay(zone).toInstant().toEpochMilli()
            val valid = history.filter { it.sessionDate <= now && it.sessionDate >= before && it.sessionDate < until &&
                it.weight.isFinite() && it.weight in 0.0..1_000_000.0 && it.reps in 1..10_000 }
            val current = valid.filter { it.sessionDate >= from }
            val previous = valid.filter { it.sessionDate < from }
            fun best(rows: List<ExerciseHistoryEntry>) = rows.groupBy { it.exerciseId to it.weight }.mapValues { (_, sets) ->
                sets.maxWith(compareBy<ExerciseHistoryEntry> { it.reps }.thenBy { it.sessionDate }.thenBy { it.setId })
            }
            val previousBest = best(previous)
            val comparisons = best(current).mapNotNull { (key, set) -> previousBest[key]?.let { WeeklyReviewInsight(it, set) } }
            val insights = comparisons.filter { it.current.reps != it.previous.reps }
                .sortedWith(compareByDescending<WeeklyReviewInsight> { kotlin.math.abs(it.current.reps - it.previous.reps) }
                    .thenBy { it.current.exerciseId }.thenBy { it.current.weight })
                .distinctBy { it.current.exerciseId }.take(3)
            return WeeklyReview(start, end.minusDays(1), offset == 0,
                current.map { Instant.ofEpochMilli(it.sessionDate).atZone(zone).toLocalDate() }.distinct().size,
                current.map { it.sessionId to it.sessionDate }.distinct().sortedByDescending { it.second },
                comparisons.size, insights)
        }
    }
}
