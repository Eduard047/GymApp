package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry

/** Most exercises shown in the picker's "Recent" section. */
internal const val RECENT_EXERCISES_MAX = 8

/**
 * Exercise ids of the picker's "Recent" section (shared/recent-exercises-v1.json): the exercises of
 * the latest completed sessions, newest first. Sessions go by date descending (ties: the higher
 * sessionId), exercises inside a session by block order. Each id is listed once at its first
 * position; ids that are not in [pickerExerciseIds] (deleted / archived / hidden) are skipped and do
 * not use up a slot. Non-blank [query] hides the section (empty result). One pass over the rows, so
 * callers compute it off the main thread together with the other picker data.
 */
internal fun recentExerciseIds(
    history: List<ExerciseHistoryEntry>,
    pickerExerciseIds: Set<Long>,
    query: String = "",
    limit: Int = RECENT_EXERCISES_MAX
): List<Long> {
    if (query.isNotBlank() || history.isEmpty() || pickerExerciseIds.isEmpty()) return emptyList()
    val newestRow = HashMap<Long, ExerciseHistoryEntry>()
    for (row in history) {
        if (row.exerciseId !in pickerExerciseIds) continue
        val current = newestRow[row.exerciseId]
        if (current == null || RecentRowOrder.compare(row, current) < 0) newestRow[row.exerciseId] = row
    }
    return newestRow.values
        .sortedWith(RecentRowOrder.thenBy { it.exerciseId })
        .take(limit)
        .map { it.exerciseId }
}

/** Keeps the recent ids the picker can still offer (e.g. not already in the workout), capped like the section. */
internal fun List<Long>.limitedToPicker(pickerExerciseIds: Set<Long>): List<Long> =
    filter { it in pickerExerciseIds }.take(RECENT_EXERCISES_MAX)

private val RecentRowOrder: Comparator<ExerciseHistoryEntry> =
    compareByDescending<ExerciseHistoryEntry> { it.sessionDate }
        .thenByDescending { it.sessionId }
        .thenBy { it.blockOrderIndex }
