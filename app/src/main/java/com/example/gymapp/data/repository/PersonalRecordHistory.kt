package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry

/** What a historical record beat; a set that beats both is reported as [WEIGHT]. */
enum class PersonalRecordKind { WEIGHT, ESTIMATED_ONE_REP_MAX }

/** One set that broke the exercise's record when it was logged. */
data class PersonalRecordEvent(
    val sessionId: Long,
    val setId: Long,
    val setOrderIndex: Int,
    val sessionDate: Long,
    val weight: Double,
    val reps: Int,
    val kind: PersonalRecordKind
)

/** The most records the progress screen ever lists. */
const val MAX_PERSONAL_RECORD_HISTORY = 50

/**
 * Replays one exercise's whole history in date order with the live-PR rules
 * ([LivePersonalRecords.evaluate] / [LivePersonalRecords.advanced]): the first session only sets
 * the baseline (it never holds a record, even when every set is 0 kg), a 0 kg set is never a
 * record, a tie is not a record, and each set is compared with the best of everything logged
 * before it (earlier sessions and earlier sets of its own session, walked block by block like
 * the stored workout's record chips: block index, then set index). Same shared fixture as iOS:
 * shared/pr-history-v1.json.
 *
 * Returns at most [limit] events, newest first.
 */
fun personalRecordHistory(
    history: List<ExerciseHistoryEntry>,
    limit: Int = MAX_PERSONAL_RECORD_HISTORY
): List<PersonalRecordEvent> {
    if (history.isEmpty() || limit <= 0) return emptyList()
    val sessions = history.groupBy { it.sessionId }.values.sortedWith(
        compareBy<List<ExerciseHistoryEntry>> { it.first().sessionDate }.thenBy { it.first().sessionId }
    )
    var best: PersonalRecordBaseline? = null
    val events = ArrayList<PersonalRecordEvent>()
    for (session in sessions) {
        val isBaseline = best == null
        var running = best ?: PersonalRecordBaseline(bestWeight = 0.0, bestEstimatedOneRepMax = 0.0)
        for (set in session.sortedWith(
            compareBy<ExerciseHistoryEntry> { it.blockOrderIndex }.thenBy { it.setOrderIndex }.thenBy { it.setId }
        )) {
            if (!isBaseline && set.weight > 0.0) {
                val result = LivePersonalRecords.evaluate(set.weight, set.reps, running)
                if (result.isRecord) {
                    events += PersonalRecordEvent(
                        sessionId = set.sessionId,
                        setId = set.setId,
                        setOrderIndex = set.setOrderIndex,
                        sessionDate = set.sessionDate,
                        weight = set.weight,
                        reps = set.reps,
                        kind = if (result.weight) PersonalRecordKind.WEIGHT else PersonalRecordKind.ESTIMATED_ONE_REP_MAX
                    )
                }
            }
            running = LivePersonalRecords.advanced(running, set.weight, set.reps)
        }
        best = running
    }
    events.reverse()
    return if (events.size > limit) events.subList(0, limit).toList() else events
}
