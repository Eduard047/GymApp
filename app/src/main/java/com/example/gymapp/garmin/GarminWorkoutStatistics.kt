package com.example.gymapp.garmin

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.normalizedExerciseName

data class GarminWorkoutMetrics(
    val durationSeconds: Long? = null,
    val gymCalories: Int? = null,
    val garminCalories: Int? = null,
    val averageHeartRate: Int? = null,
    val maximumHeartRate: Int? = null,
    val endingHeartRateZone: Int? = null
)

data class ScalarMetricComparison(
    val currentValue: Double,
    val previousValue: Double
) {
    val delta: Double
        get() = currentValue - previousValue
}

data class WorkoutComparison(
    val previousSessionId: Long,
    val previousSessionDate: Long,
    val matchedExerciseCount: Int,
    val setCount: ScalarMetricComparison,
    val totalReps: ScalarMetricComparison,
    val totalVolume: ScalarMetricComparison,
    val durationSeconds: ScalarMetricComparison?,
    val gymCalories: ScalarMetricComparison?,
    val garminCalories: ScalarMetricComparison?,
    val averageHeartRate: ScalarMetricComparison?,
    val maximumHeartRate: ScalarMetricComparison?
)

internal data class ComparableWorkoutSnapshot(
    val sessionId: Long,
    val sessionDate: Long,
    val exerciseSignature: List<String>,
    val setCount: Int,
    val totalReps: Long,
    val totalVolume: Double,
    val garminMetrics: GarminWorkoutMetrics?
)

private val GARMIN_NOTE_MARKER =
    Regex("""^Garmin(?: Fenix 8)?(?: ·|$)""", RegexOption.IGNORE_CASE)
private val DURATION_VALUE = Regex(
    """(?:Duration|Тривалість|Длительность)\s+([0-9]{1,5}:[0-9]{2}(?::[0-9]{2})?)(?![0-9:])""",
    RegexOption.IGNORE_CASE
)
private val GYM_CALORIE_VALUE =
    Regex("""Gym\s+(?:kcal|ккал)\s+([0-9]{1,6})(?![0-9])""", RegexOption.IGNORE_CASE)
private val GARMIN_CALORIE_VALUE =
    Regex("""Garmin\s+(?:kcal|ккал)\s+([0-9]{1,6})(?![0-9])""", RegexOption.IGNORE_CASE)
private val AVERAGE_HEART_RATE_VALUE = Regex(
    """(?:Avg HR|Сер пульс|Средний пульс)\s+([0-9]{1,3})(?![0-9])""",
    RegexOption.IGNORE_CASE
)
private val MAXIMUM_HEART_RATE_VALUE = Regex(
    """(?:Max HR|Макс пульс|Макс\. пульс)\s+([0-9]{1,3})(?![0-9])""",
    RegexOption.IGNORE_CASE
)
private val ENDING_HEART_RATE_ZONE_VALUE = Regex(
    """(?:Ending HR zone|Кінцева зона пульсу|Конечная зона пульса|HR zone|Зона пульсу|Зона пульса)\s+Z([0-9])(?![0-9])""",
    RegexOption.IGNORE_CASE
)

internal fun parseGarminWorkoutMetrics(note: String): GarminWorkoutMetrics? {
    if (!WorkoutDataLimits.isValidNote(note) || !GARMIN_NOTE_MARKER.containsMatchIn(note)) return null

    val durationSeconds = DURATION_VALUE.firstGroup(note)
        ?.let(::parseDurationSeconds)
    val gymCalories = GYM_CALORIE_VALUE.boundedInt(note, 1..MAX_GARMIN_CALORIES.toInt())
    val garminCalories = GARMIN_CALORIE_VALUE.boundedInt(note, 1..MAX_GARMIN_CALORIES.toInt())
    var averageHeartRate = AVERAGE_HEART_RATE_VALUE.boundedInt(note, 1..MAX_GARMIN_HEART_RATE)
    var maximumHeartRate = MAXIMUM_HEART_RATE_VALUE.boundedInt(note, 1..MAX_GARMIN_HEART_RATE)
    if (averageHeartRate != null && maximumHeartRate != null && averageHeartRate > maximumHeartRate) {
        averageHeartRate = null
        maximumHeartRate = null
    }
    val endingHeartRateZone = ENDING_HEART_RATE_ZONE_VALUE.boundedInt(
        note,
        1..MAX_GARMIN_HEART_RATE_ZONE
    )

    return GarminWorkoutMetrics(
        durationSeconds = durationSeconds,
        gymCalories = gymCalories,
        garminCalories = garminCalories,
        averageHeartRate = averageHeartRate,
        maximumHeartRate = maximumHeartRate,
        endingHeartRateZone = endingHeartRateZone
    )
}

internal fun buildWorkoutComparisonForSession(
    currentSessionId: Long,
    currentSessionDate: Long,
    currentNote: String?,
    currentEntries: List<ExerciseHistoryEntry>,
    allSessions: List<WorkoutSessionSummary>,
    allHistory: List<ExerciseHistoryEntry>
): WorkoutComparison? {
    if (allSessions.size > WorkoutDataLimits.MAX_SESSIONS ||
        allHistory.size > WorkoutDataLimits.MAX_TOTAL_SETS
    ) {
        return null
    }
    val current = comparableWorkoutSnapshotOrNull(
        sessionId = currentSessionId,
        sessionDate = currentSessionDate,
        note = currentNote,
        entries = currentEntries
    ) ?: return null
    val entriesBySession = allHistory.groupBy(ExerciseHistoryEntry::sessionId)
    val candidates = allSessions.mapNotNull { summary ->
        val candidateId = summary.session.id
        if (candidateId == currentSessionId) return@mapNotNull null
        comparableWorkoutSnapshotOrNull(
            sessionId = candidateId,
            sessionDate = summary.session.date,
            note = summary.session.note,
            entries = entriesBySession[candidateId].orEmpty()
        )
    }
    return findPreviousComparableWorkout(current = current, candidates = candidates)
}

internal fun WorkoutSessionDetails.toExerciseHistoryEntries(): List<ExerciseHistoryEntry> {
    return workoutExercises.flatMap { workoutExercise ->
        workoutExercise.sets.map { set ->
            ExerciseHistoryEntry(
                setId = set.id,
                sessionId = session.id,
                sessionDate = session.date,
                exerciseId = workoutExercise.exercise.id,
                exerciseName = workoutExercise.exercise.name,
                weight = set.weight,
                reps = set.reps,
                setOrderIndex = set.orderIndex
            )
        }
    }
}

internal fun findPreviousComparableWorkout(
    current: ComparableWorkoutSnapshot,
    candidates: List<ComparableWorkoutSnapshot>
): WorkoutComparison? {
    val previous = candidates
        .asSequence()
        .filter { candidate ->
            candidate.exerciseSignature == current.exerciseSignature && candidate.isEarlierThan(current)
        }
        .maxWithOrNull(compareBy<ComparableWorkoutSnapshot>({ it.sessionDate }, { it.sessionId }))
        ?: return null

    return WorkoutComparison(
        previousSessionId = previous.sessionId,
        previousSessionDate = previous.sessionDate,
        matchedExerciseCount = current.exerciseSignature.size,
        setCount = compare(current.setCount, previous.setCount),
        totalReps = compare(current.totalReps, previous.totalReps),
        totalVolume = compare(current.totalVolume, previous.totalVolume),
        durationSeconds = compareOptional(
            current.garminMetrics?.durationSeconds,
            previous.garminMetrics?.durationSeconds
        ),
        gymCalories = compareOptional(
            current.garminMetrics?.gymCalories,
            previous.garminMetrics?.gymCalories
        ),
        garminCalories = compareOptional(
            current.garminMetrics?.garminCalories,
            previous.garminMetrics?.garminCalories
        ),
        averageHeartRate = compareOptional(
            current.garminMetrics?.averageHeartRate,
            previous.garminMetrics?.averageHeartRate
        ),
        maximumHeartRate = compareOptional(
            current.garminMetrics?.maximumHeartRate,
            previous.garminMetrics?.maximumHeartRate
        )
    )
}

internal fun isWorkoutEarlier(
    candidateDate: Long,
    candidateId: Long,
    currentDate: Long,
    currentId: Long
): Boolean = candidateDate < currentDate ||
    (candidateDate == currentDate && candidateId < currentId)

internal fun comparableWorkoutSnapshotOrNull(
    sessionId: Long,
    sessionDate: Long,
    note: String?,
    entries: List<ExerciseHistoryEntry>
): ComparableWorkoutSnapshot? {
    val maximumEntryCount =
        WorkoutDataLimits.MAX_EXERCISES_PER_SESSION * WorkoutDataLimits.MAX_SETS_PER_EXERCISE
    if (sessionId <= 0L || !WorkoutDataLimits.isValidTimestamp(sessionDate) ||
        entries.isEmpty() || entries.size > maximumEntryCount
    ) {
        return null
    }
    if (entries.any { entry ->
            entry.sessionId != sessionId ||
                !WorkoutDataLimits.isValidExerciseName(entry.exerciseName) ||
                !WorkoutDataLimits.isValidWeight(entry.weight) ||
                !WorkoutDataLimits.isValidReps(entry.reps)
        }
    ) {
        return null
    }

    val exerciseSignature = entries
        .asSequence()
        .map(ExerciseHistoryEntry::exerciseName)
        .map(::canonicalExerciseIdentity)
        .distinct()
        .sorted()
        .toList()
    if (exerciseSignature.isEmpty() ||
        exerciseSignature.size > WorkoutDataLimits.MAX_EXERCISES_PER_SESSION
    ) {
        return null
    }

    val totalVolume = entries.sumOf { entry -> entry.weight * entry.reps }
    if (!totalVolume.isFinite()) return null

    return ComparableWorkoutSnapshot(
        sessionId = sessionId,
        sessionDate = sessionDate,
        exerciseSignature = exerciseSignature,
        setCount = entries.size,
        totalReps = entries.sumOf { entry -> entry.reps.toLong() },
        totalVolume = totalVolume,
        garminMetrics = note?.let(::parseGarminWorkoutMetrics)
    )
}

private fun ComparableWorkoutSnapshot.isEarlierThan(other: ComparableWorkoutSnapshot): Boolean {
    return isWorkoutEarlier(
        candidateDate = sessionDate,
        candidateId = sessionId,
        currentDate = other.sessionDate,
        currentId = other.sessionId
    )
}

private fun canonicalExerciseIdentity(name: String): String {
    return BuiltInExerciseCatalog.inferKey(name)
        ?.let { key -> "catalog:$key" }
        ?: "custom:${name.normalizedExerciseName()}"
}

private fun Regex.firstGroup(value: String): String? =
    find(value)?.groupValues?.getOrNull(1)

private fun Regex.boundedInt(value: String, range: IntRange): Int? =
    firstGroup(value)?.toIntOrNull()?.takeIf { it in range }

private fun parseDurationSeconds(value: String): Long? {
    val parts = value.split(':').map { part -> part.toLongOrNull() ?: return null }
    if (parts.size !in 2..3) return null
    val seconds = when (parts.size) {
        2 -> {
            val (minutes, remainingSeconds) = parts
            if (remainingSeconds !in 0L..59L) return null
            minutes * 60L + remainingSeconds
        }

        else -> {
            val (hours, minutes, remainingSeconds) = parts
            if (minutes !in 0L..59L || remainingSeconds !in 0L..59L) return null
            hours * 3_600L + minutes * 60L + remainingSeconds
        }
    }
    return seconds.takeIf { it in 1L..MAX_GARMIN_DURATION_SECONDS }
}

private fun compare(current: Int, previous: Int) =
    ScalarMetricComparison(current.toDouble(), previous.toDouble())

private fun compare(current: Long, previous: Long) =
    ScalarMetricComparison(current.toDouble(), previous.toDouble())

private fun compare(current: Double, previous: Double) =
    ScalarMetricComparison(current, previous)

private fun compareOptional(current: Int?, previous: Int?): ScalarMetricComparison? {
    if (current == null || previous == null) return null
    return compare(current, previous)
}

private fun compareOptional(current: Long?, previous: Long?): ScalarMetricComparison? {
    if (current == null || previous == null) return null
    return compare(current, previous)
}
