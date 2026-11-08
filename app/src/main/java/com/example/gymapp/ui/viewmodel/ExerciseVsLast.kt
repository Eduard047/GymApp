package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.garmin.isWorkoutEarlier

/** How one exercise of the finished workout compares with its previous session. */
enum class VsLastStatus(val wire: String) {
    New("new"),
    Up("up"),
    Down("down"),
    Same("same")
}

/** What decided the status: total volume, or total reps when both volumes are 0 (bodyweight only). */
enum class VsLastBasis(val wire: String) {
    Volume("volume"),
    Reps("reps")
}

data class VsLastSet(val weight: Double, val reps: Int)

/**
 * One "compared with last time" row. [delta] is current minus previous on [basis] (null for a new
 * exercise, 0 for "same"); [previousBest] is null for a new exercise.
 */
data class ExerciseVsLastUiState(
    val exerciseId: Long,
    val exerciseName: String,
    val status: VsLastStatus,
    val basis: VsLastBasis?,
    val delta: Double?,
    val best: VsLastSet,
    val previousBest: VsLastSet?
)

/** Rows shown in the "Compared with last time" card, like the iPhone summary. */
internal const val VS_LAST_MAX_EXERCISES = 8

private const val VS_LAST_EPSILON = 1e-9

/** A volume delta smaller than this (kg) counts as "same" (shared rule 5), so the UI never shows "+0 kg". */
private const val VS_LAST_VOLUME_SAME_THRESHOLD = 0.05

private data class FirstBlockSummary(
    val exerciseName: String,
    val blockOrderIndex: Int,
    val volume: Double,
    val reps: Int,
    val best: VsLastSet
)

/** Rows with reps <= 0 are dropped first; of the rest only the first block (lowest block index) counts. */
private fun firstBlockSummary(rows: List<ExerciseHistoryEntry>): FirstBlockSummary? {
    val valid = rows.filter { it.reps > 0 }
    if (valid.isEmpty()) return null
    val firstBlock = valid.minOf { it.blockOrderIndex }
    val sets = valid.filter { it.blockOrderIndex == firstBlock }
    val best = sets.maxWith(compareBy<ExerciseHistoryEntry>({ it.weight }, { it.reps }))
    return FirstBlockSummary(
        exerciseName = best.exerciseName,
        blockOrderIndex = firstBlock,
        volume = sets.sumOf { it.weight * it.reps },
        reps = sets.sumOf { it.reps },
        best = VsLastSet(best.weight, best.reps)
    )
}

/**
 * Per exercise of the finished workout (shared/exercise-vs-last-v1.json): how its first block
 * compares with the first block of the latest earlier session that has the exercise. Rows are in
 * workout order, at most [VS_LAST_MAX_EXERCISES]; the list is empty (card hidden) when every shown
 * exercise is new. [currentEntries] are the finished workout's sets with their block index.
 */
internal fun buildExerciseVsLast(
    currentEntries: List<ExerciseHistoryEntry>,
    allHistory: List<ExerciseHistoryEntry>,
    currentSessionId: Long,
    currentSessionDate: Long
): List<ExerciseVsLastUiState> {
    val previousByExercise = allHistory
        .filter { entry ->
            entry.reps > 0 && isWorkoutEarlier(
                candidateDate = entry.sessionDate,
                candidateId = entry.sessionId,
                currentDate = currentSessionDate,
                currentId = currentSessionId
            )
        }
        .groupBy { it.exerciseId }

    val rows = currentEntries
        .groupBy { it.exerciseId }
        .mapNotNull { (exerciseId, entries) ->
            val current = firstBlockSummary(entries) ?: return@mapNotNull null
            val previousRows = previousByExercise[exerciseId].orEmpty()
            val previous = previousRows
                .takeIf { it.isNotEmpty() }
                ?.let { rowsOfExercise ->
                    val latest = rowsOfExercise.maxWith(compareBy({ it.sessionDate }, { it.sessionId }))
                    firstBlockSummary(
                        rowsOfExercise.filter {
                            it.sessionDate == latest.sessionDate && it.sessionId == latest.sessionId
                        }
                    )
                }
            exerciseId to (current to previous)
        }
        .sortedWith(compareBy({ it.second.first.blockOrderIndex }, { it.first }))
        .take(VS_LAST_MAX_EXERCISES)
        .map { (exerciseId, pair) ->
            val (current, previous) = pair
            if (previous == null) {
                ExerciseVsLastUiState(
                    exerciseId = exerciseId,
                    exerciseName = current.exerciseName,
                    status = VsLastStatus.New,
                    basis = null,
                    delta = null,
                    best = current.best,
                    previousBest = null
                )
            } else {
                val repsBasis = current.volume <= VS_LAST_EPSILON && previous.volume <= VS_LAST_EPSILON
                val delta = if (repsBasis) {
                    (current.reps - previous.reps).toDouble()
                } else {
                    current.volume - previous.volume
                }
                val sameLimit = if (repsBasis) VS_LAST_EPSILON else VS_LAST_VOLUME_SAME_THRESHOLD - VS_LAST_EPSILON
                val status = when {
                    kotlin.math.abs(delta) < sameLimit || kotlin.math.abs(delta) <= VS_LAST_EPSILON -> VsLastStatus.Same
                    delta > 0.0 -> VsLastStatus.Up
                    else -> VsLastStatus.Down
                }
                ExerciseVsLastUiState(
                    exerciseId = exerciseId,
                    exerciseName = current.exerciseName,
                    status = status,
                    basis = if (repsBasis) VsLastBasis.Reps else VsLastBasis.Volume,
                    delta = if (status == VsLastStatus.Same) 0.0 else delta,
                    best = current.best,
                    previousBest = previous.best
                )
            }
        }
    return if (rows.all { it.status == VsLastStatus.New }) emptyList() else rows
}
