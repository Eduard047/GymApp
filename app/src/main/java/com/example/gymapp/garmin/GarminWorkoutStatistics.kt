package com.example.gymapp.garmin

import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.normalizedExerciseName
import kotlin.math.roundToInt

private const val MAX_GARMIN_SET_HEART_RATE = 240

data class GarminWorkoutMetrics(
    val durationSeconds: Long? = null,
    val gymCalories: Int? = null,
    val garminCalories: Int? = null,
    val averageHeartRate: Int? = null,
    val maximumHeartRate: Int? = null,
    val endingHeartRateZone: Int? = null,
    val setEvidence: List<GarminSetEvidenceMetrics> = emptyList(),
    val setIntervals: List<GarminSetIntervalMetrics> = emptyList(),
    val omittedSetIntervalCount: Int = 0,
    val plannedSetCount: Int? = null,
    val completedSetCount: Int? = null
)

internal enum class GarminWorkoutPresentationOrigin {
    VerifiedLocalReceipt,
    SavedNote
}

internal data class GarminWorkoutPresentation(
    val metrics: GarminWorkoutMetrics,
    val origin: GarminWorkoutPresentationOrigin
) {
    val hasVerifiedGarminOrigin: Boolean
        get() = origin == GarminWorkoutPresentationOrigin.VerifiedLocalReceipt
}

internal fun parseGarminWorkoutPresentation(
    note: String,
    hasGarminReceipt: Boolean
): GarminWorkoutPresentation? = parseGarminWorkoutMetrics(note)?.let { metrics ->
    GarminWorkoutPresentation(
        metrics = metrics,
        origin = if (hasGarminReceipt) {
            GarminWorkoutPresentationOrigin.VerifiedLocalReceipt
        } else {
            GarminWorkoutPresentationOrigin.SavedNote
        }
    )
}

internal fun GarminWorkoutMetrics.hasSetIntervalDetails(): Boolean =
    setEvidence.isNotEmpty() || setIntervals.isNotEmpty() || omittedSetIntervalCount > 0

data class GarminSetEvidenceMetrics(
    val setNumber: Int,
    val activeSeconds: Long? = null,
    val restBeforeSeconds: Long? = null,
    val startHeartRate: Int? = null,
    val peakHeartRate: Int? = null,
    val endHeartRate: Int? = null,
    val recoveryHeartRateDrop: Int? = null,
    val detectionConfidence: Int? = null
)

data class GarminSetIntervalMetrics(
    val setNumber: Int,
    val startOffsetSeconds: Long,
    val endOffsetSeconds: Long,
    val gymCalories: Double,
    val garminCalories: Int?,
    val heartRateZoneSeconds: List<Int>,
    val restBeforeSeconds: Long? = null,
    val startHeartRate: Int? = null,
    val peakHeartRate: Int? = null,
    val endHeartRate: Int? = null,
    val recoveryHeartRateDrop: Int? = null,
    val detectionConfidence: Int? = null
) {
    val activeSeconds: Long
        get() = endOffsetSeconds - startOffsetSeconds
}

internal data class GarminSetHeartRateChartPoint(
    val setNumber: Int,
    val startHeartRate: Int?,
    val peakHeartRate: Int?,
    val endHeartRate: Int?
) {
    val readings: List<Int>
        get() = listOfNotNull(startHeartRate, peakHeartRate, endHeartRate)
}

internal data class GarminSetRecognitionSummary(
    val averageConfidence: Int,
    val measuredSetCount: Int,
    val lowConfidenceSetNumbers: List<Int>
)

internal data class GarminRecoverySummary(
    val medianHeartRateDrop: Int,
    val measuredSetCount: Int
)

internal data class GarminWorkoutRhythmSummary(
    val capturedSpanSeconds: Long,
    val activeSetSeconds: Long,
    val betweenSetSeconds: Long
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
private val SET_INTERVAL_VALUE = Regex(
    """(?:^| · )S([1-9][0-9]?)\s+([^·]{0,180}?)I([0-9]{1,6})-([0-9]{1,6})s\s+K([0-9]{1,6}(?:\.[0-9]{1,8})?)/(-|[0-9]{1,6})\s+Z([0-9]{1,4}(?:/[0-9]{1,4}){5})s(?= ·|$)"""
)
private val SET_EVIDENCE_ROW_VALUE = Regex(
    """(?:^| · )S([1-9][0-9]?)\s+([^·]{1,180})(?= ·|$)"""
)
private val SET_ACTIVE_SECONDS_VALUE = Regex("""^([0-9]{1,6})s(?:\s|$)""")
private val SET_REST_SECONDS_VALUE = Regex("""(?:^|\s)R([0-9]{1,6})s(?:\s|$)""")
private val SET_HEART_RATE_VALUE = Regex(
    """(?:^|\s)HR(-|[0-9]{1,3})/(-|[0-9]{1,3})/(-|[0-9]{1,3})(?:\s|$)"""
)
private val SET_RECOVERY_DROP_VALUE = Regex("""(?:^|\s)↓([0-9]{1,3})(?:\s|$)""")
private val SET_DETECTION_CONFIDENCE_VALUE = Regex("""(?:^|\s)C([0-9]{1,3})%(?:\s|$)""")
private val OMITTED_SET_INTERVALS_VALUE =
    Regex("""(?:^| · )S\+([0-9]{1,2})(?= ·|$)""")
private val PARTIAL_SET_COUNT_VALUE = Regex(
    """(?:Completed|Partial|Виконано|Частково|Выполнено|Частично)\s+([0-9]{1,2})/([0-9]{1,2})\s+(?:sets|підходів|подходов)(?= ·|$)""",
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
    val setIntervals = parseGarminSetIntervals(
        note = note,
        workoutDurationSeconds = durationSeconds,
        workoutGymCalories = gymCalories,
        workoutGarminCalories = garminCalories
    )
    val setEvidence = parseGarminSetEvidence(note)
    val omittedSetIntervalCount = OMITTED_SET_INTERVALS_VALUE
        .boundedInt(note, 1..MAX_GARMIN_WORKOUT_SETS)
        ?: 0
    val partialProgress = PARTIAL_SET_COUNT_VALUE.find(note)?.let { match ->
        val completed = match.groupValues.getOrNull(1)?.toIntOrNull()
        val planned = match.groupValues.getOrNull(2)?.toIntOrNull()
        if (
            completed != null && planned != null &&
            completed in 0 until planned && planned <= MAX_GARMIN_WORKOUT_SETS
        ) {
            completed to planned
        } else {
            null
        }
    }

    return GarminWorkoutMetrics(
        durationSeconds = durationSeconds,
        gymCalories = gymCalories,
        garminCalories = garminCalories,
        averageHeartRate = averageHeartRate,
        maximumHeartRate = maximumHeartRate,
        endingHeartRateZone = endingHeartRateZone,
        setEvidence = setEvidence,
        setIntervals = setIntervals,
        omittedSetIntervalCount = omittedSetIntervalCount,
        plannedSetCount = partialProgress?.second,
        completedSetCount = partialProgress?.first
    )
}

private fun parseGarminSetEvidence(note: String): List<GarminSetEvidenceMetrics> {
    val seenSetNumbers = mutableSetOf<Int>()
    return SET_EVIDENCE_ROW_VALUE.findAll(note)
        .take(MAX_GARMIN_WORKOUT_SETS)
        .mapNotNull { match ->
            val setNumber = match.groupValues[1].toIntOrNull()
                ?.takeIf { it in 1..MAX_GARMIN_WORKOUT_SETS }
                ?: return@mapNotNull null
            if (!seenSetNumbers.add(setNumber)) return@mapNotNull null
            val body = match.groupValues[2]
            val activeSeconds = SET_ACTIVE_SECONDS_VALUE.firstGroup(body)
                ?.toLongOrNull()
                ?.takeIf { it in 0L..MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS }
            val statistics = parseGarminSetStatisticsPrefix(body)
            if (activeSeconds == null && statistics.isEmpty()) return@mapNotNull null
            GarminSetEvidenceMetrics(
                setNumber = setNumber,
                activeSeconds = activeSeconds,
                restBeforeSeconds = statistics.restBeforeSeconds,
                startHeartRate = statistics.startHeartRate,
                peakHeartRate = statistics.peakHeartRate,
                endHeartRate = statistics.endHeartRate,
                recoveryHeartRateDrop = statistics.recoveryHeartRateDrop,
                detectionConfidence = statistics.detectionConfidence
            )
        }
        .toList()
}

private fun parseGarminSetIntervals(
    note: String,
    workoutDurationSeconds: Long?,
    workoutGymCalories: Int?,
    workoutGarminCalories: Int?
): List<GarminSetIntervalMetrics> {
    val seenSetNumbers = mutableSetOf<Int>()
    var previousEndOffsetSeconds = 0L
    val intervals = SET_INTERVAL_VALUE.findAll(note)
        .take(MAX_GARMIN_WORKOUT_SETS)
        .mapNotNull { match ->
            val setNumber = match.groupValues[1].toIntOrNull()
                ?.takeIf { it in 1..MAX_GARMIN_WORKOUT_SETS }
                ?: return@mapNotNull null
            if (!seenSetNumbers.add(setNumber)) return@mapNotNull null
            val statisticsPrefix = match.groupValues[2]
            val startOffsetSeconds = match.groupValues[3].toLongOrNull()
                ?.takeIf { it in 0L..MAX_GARMIN_SET_INTERVAL_OFFSET_SECONDS }
                ?: return@mapNotNull null
            val endOffsetSeconds = match.groupValues[4].toLongOrNull()
                ?.takeIf { it in startOffsetSeconds..MAX_GARMIN_SET_INTERVAL_OFFSET_SECONDS }
                ?: return@mapNotNull null
            val activeSeconds = endOffsetSeconds - startOffsetSeconds
            if (activeSeconds > MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS) return@mapNotNull null
            if (startOffsetSeconds < previousEndOffsetSeconds) return@mapNotNull null
            if (workoutDurationSeconds != null && endOffsetSeconds > workoutDurationSeconds) {
                return@mapNotNull null
            }
            val gymCalories = match.groupValues[5].toDoubleOrNull()
                ?.takeIf { it.isFinite() && it in 0.0..MAX_GARMIN_SET_INTERVAL_CALORIES }
                ?: return@mapNotNull null
            val garminCalories = match.groupValues[6]
                .takeUnless { it == "-" }
                ?.toIntOrNull()
                ?.takeIf { it in 0..MAX_GARMIN_SET_INTERVAL_CALORIES.toInt() }
                ?: if (match.groupValues[6] == "-") null else return@mapNotNull null
            val zones = match.groupValues[7]
                .split('/')
                .map { value ->
                    value.toIntOrNull()
                        ?.takeIf { it in 0..MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS.toInt() }
                        ?: return@mapNotNull null
                }
            if (zones.size != 6 || zones.sumOf { it.toLong() } > activeSeconds) {
                return@mapNotNull null
            }
            val parsedStatistics = parseGarminSetStatisticsPrefix(statisticsPrefix)
            previousEndOffsetSeconds = endOffsetSeconds
            GarminSetIntervalMetrics(
                setNumber = setNumber,
                startOffsetSeconds = startOffsetSeconds,
                endOffsetSeconds = endOffsetSeconds,
                gymCalories = gymCalories,
                garminCalories = garminCalories,
                heartRateZoneSeconds = zones,
                restBeforeSeconds = parsedStatistics.restBeforeSeconds,
                startHeartRate = parsedStatistics.startHeartRate,
                peakHeartRate = parsedStatistics.peakHeartRate,
                endHeartRate = parsedStatistics.endHeartRate,
                recoveryHeartRateDrop = parsedStatistics.recoveryHeartRateDrop,
                detectionConfidence = parsedStatistics.detectionConfidence
            )
        }
        .toList()

    if (workoutGymCalories != null &&
        intervals.sumOf(GarminSetIntervalMetrics::gymCalories) >
        workoutGymCalories + 1.0 + GARMIN_SET_INTERVAL_CALORIE_ROUNDING_TOLERANCE
    ) {
        return emptyList()
    }
    val intervalGarminCalories = intervals.mapNotNull(GarminSetIntervalMetrics::garminCalories)
    if (workoutGarminCalories != null && intervalGarminCalories.sum() > workoutGarminCalories) {
        return emptyList()
    }
    return intervals
}

private data class ParsedGarminSetStatistics(
    val restBeforeSeconds: Long?,
    val startHeartRate: Int?,
    val peakHeartRate: Int?,
    val endHeartRate: Int?,
    val recoveryHeartRateDrop: Int?,
    val detectionConfidence: Int?
) {
    fun isEmpty(): Boolean = restBeforeSeconds == null && startHeartRate == null &&
        peakHeartRate == null && endHeartRate == null && recoveryHeartRateDrop == null &&
        detectionConfidence == null
}

private fun parseGarminSetStatisticsPrefix(prefix: String): ParsedGarminSetStatistics {
    val restBeforeSeconds = SET_REST_SECONDS_VALUE.firstGroup(prefix)
        ?.toLongOrNull()
        ?.takeIf { it in 0L..86_400L }
    val heartRates = SET_HEART_RATE_VALUE.find(prefix)?.let { match ->
        List(3) { index ->
            match.groupValues[index + 1]
                .takeUnless { it == "-" }
                ?.toIntOrNull()
                ?.takeIf { it in 1..MAX_GARMIN_SET_HEART_RATE }
        }
    }.orEmpty()
    val startHeartRate = heartRates.getOrNull(0)
    val reportedPeakHeartRate = heartRates.getOrNull(1)
    val endHeartRate = heartRates.getOrNull(2)
    val peakHeartRate = listOfNotNull(
        startHeartRate,
        reportedPeakHeartRate,
        endHeartRate
    ).maxOrNull()
    val recoveryHeartRateDrop = SET_RECOVERY_DROP_VALUE.firstGroup(prefix)
        ?.toIntOrNull()
        ?.takeIf { it in 0..MAX_GARMIN_SET_HEART_RATE }
    val detectionConfidence = SET_DETECTION_CONFIDENCE_VALUE.firstGroup(prefix)
        ?.toIntOrNull()
        ?.takeIf { it in 0..100 }

    return ParsedGarminSetStatistics(
        restBeforeSeconds = restBeforeSeconds,
        startHeartRate = startHeartRate,
        peakHeartRate = peakHeartRate,
        endHeartRate = endHeartRate,
        recoveryHeartRateDrop = recoveryHeartRateDrop,
        detectionConfidence = detectionConfidence
    )
}

internal fun GarminWorkoutMetrics.totalHeartRateZoneSeconds(): List<Long> {
    if (setIntervals.isEmpty() || setIntervals.size > MAX_GARMIN_WORKOUT_SETS) return emptyList()
    val totals = LongArray(6)
    setIntervals.forEach { interval ->
        if (interval.heartRateZoneSeconds.size != totals.size) return emptyList()
        interval.heartRateZoneSeconds.forEachIndexed { index, seconds ->
            if (seconds !in 0..MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS.toInt()) {
                return emptyList()
            }
            totals[index] = Math.addExact(totals[index], seconds.toLong())
        }
    }
    return totals.toList().takeIf { values -> values.any { it > 0L } }.orEmpty()
}

internal fun GarminWorkoutMetrics.setHeartRateChartPoints(): List<GarminSetHeartRateChartPoint> {
    val evidence = boundedSetEvidence() ?: return emptyList()
    return evidence
        .sortedBy(GarminSetEvidenceMetrics::setNumber)
        .mapNotNull { item ->
            val point = GarminSetHeartRateChartPoint(
                setNumber = item.setNumber,
                startHeartRate = item.startHeartRate?.takeIf { it in 1..MAX_GARMIN_SET_HEART_RATE },
                peakHeartRate = item.peakHeartRate?.takeIf { it in 1..MAX_GARMIN_SET_HEART_RATE },
                endHeartRate = item.endHeartRate?.takeIf { it in 1..MAX_GARMIN_SET_HEART_RATE }
            )
            point.takeIf { it.readings.isNotEmpty() }
        }
}

internal fun GarminWorkoutMetrics.setRecognitionSummary(): GarminSetRecognitionSummary? {
    val evidence = boundedSetEvidence() ?: return null
    val measured = evidence.mapNotNull { item ->
        item.detectionConfidence?.let { confidence -> item.setNumber to confidence }
    }
    if (measured.isEmpty()) return null
    return GarminSetRecognitionSummary(
        averageConfidence = (measured.sumOf { it.second } / measured.size.toDouble())
            .roundToInt()
            .coerceIn(0, 100),
        measuredSetCount = measured.size,
        lowConfidenceSetNumbers = measured
            .filter { (_, confidence) -> confidence < 40 }
            .map { (setNumber, _) -> setNumber }
    )
}

internal fun GarminWorkoutMetrics.recoverySummary(): GarminRecoverySummary? {
    val evidence = boundedSetEvidence() ?: return null
    val drops = evidence.mapNotNull(GarminSetEvidenceMetrics::recoveryHeartRateDrop).sorted()
    if (drops.isEmpty()) return null
    val middle = drops.size / 2
    val median = if (drops.size % 2 == 0) {
        (drops[middle - 1] + drops[middle]) / 2
    } else {
        drops[middle]
    }
    return GarminRecoverySummary(
        medianHeartRateDrop = median,
        measuredSetCount = drops.size
    )
}

private fun GarminWorkoutMetrics.boundedSetEvidence(): List<GarminSetEvidenceMetrics>? {
    if (setEvidence.size > MAX_GARMIN_WORKOUT_SETS ||
        setIntervals.size > MAX_GARMIN_WORKOUT_SETS
    ) return null
    val combined = linkedMapOf<Int, GarminSetEvidenceMetrics>()
    setEvidence.forEach { item ->
        if (!item.isBounded() || combined.put(item.setNumber, item) != null) return null
    }
    setIntervals.forEach { interval ->
        val fallback = GarminSetEvidenceMetrics(
            setNumber = interval.setNumber,
            activeSeconds = interval.activeSeconds,
            restBeforeSeconds = interval.restBeforeSeconds,
            startHeartRate = interval.startHeartRate,
            peakHeartRate = interval.peakHeartRate,
            endHeartRate = interval.endHeartRate,
            recoveryHeartRateDrop = interval.recoveryHeartRateDrop,
            detectionConfidence = interval.detectionConfidence
        )
        if (!fallback.isBounded()) return null
        combined.putIfAbsent(interval.setNumber, fallback)
    }
    return combined.values.toList()
}

private fun GarminSetEvidenceMetrics.isBounded(): Boolean =
    setNumber in 1..MAX_GARMIN_WORKOUT_SETS &&
        (activeSeconds == null || activeSeconds in 0L..MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS) &&
        (restBeforeSeconds == null || restBeforeSeconds in 0L..86_400L) &&
        listOf(startHeartRate, peakHeartRate, endHeartRate, recoveryHeartRateDrop)
            .all { it == null || it in 0..MAX_GARMIN_SET_HEART_RATE } &&
        (detectionConfidence == null || detectionConfidence in 0..100)

internal fun GarminWorkoutMetrics.rhythmSummary(): GarminWorkoutRhythmSummary? {
    val intervals = setIntervals.takeIf {
        it.isNotEmpty() && it.size <= MAX_GARMIN_WORKOUT_SETS && it.all { interval ->
            interval.startOffsetSeconds in 0L..MAX_GARMIN_SET_INTERVAL_OFFSET_SECONDS &&
                interval.endOffsetSeconds >= interval.startOffsetSeconds &&
                interval.endOffsetSeconds <= MAX_GARMIN_SET_INTERVAL_OFFSET_SECONDS &&
                interval.activeSeconds <= MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS
        }
    } ?: return null
    if (intervals.zipWithNext().any { (previous, current) ->
            current.startOffsetSeconds < previous.endOffsetSeconds
        }
    ) {
        return null
    }
    val firstStart = intervals.first().startOffsetSeconds
    val finalEnd = intervals.last().endOffsetSeconds
    val capturedSpan = finalEnd - firstStart
    val activeSeconds = intervals.sumOf(GarminSetIntervalMetrics::activeSeconds)
    if (capturedSpan < 0L || activeSeconds !in 0L..capturedSpan) return null
    return GarminWorkoutRhythmSummary(
        capturedSpanSeconds = capturedSpan,
        activeSetSeconds = activeSeconds,
        betweenSetSeconds = capturedSpan - activeSeconds
    )
}

/**
 * A Garmin-looking note is user-controlled workout data. Only a local receipt written by the
 * bound-device ingestion transaction upgrades those parsed values to trusted Garmin metrics.
 */
internal fun parseTrustedGarminWorkoutMetrics(
    note: String,
    hasGarminReceipt: Boolean
): GarminWorkoutMetrics? = if (hasGarminReceipt) {
    parseGarminWorkoutMetrics(note)
} else {
    null
}

internal fun buildWorkoutComparisonForSession(
    currentSessionId: Long,
    currentSessionDate: Long,
    currentNote: String?,
    currentHasGarminReceipt: Boolean,
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
        hasGarminReceipt = currentHasGarminReceipt,
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
            hasGarminReceipt = summary.hasGarminReceipt,
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
    hasGarminReceipt: Boolean = false,
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
        garminMetrics = note?.let { value ->
            parseTrustedGarminWorkoutMetrics(value, hasGarminReceipt)
        }
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
