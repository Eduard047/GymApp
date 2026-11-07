package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.GymOneRepMax
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.MuscleContribution
import com.example.gymapp.data.repository.PersonalRecordEvent
import com.example.gymapp.data.repository.personalRecordHistory
import com.example.gymapp.data.repository.muscleContributionsForExercise
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.util.AppLanguageSignal
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.formatSessionVolume
import com.example.gymapp.util.localizedText
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.shareIn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.ZoneId
import java.util.Locale
import kotlin.math.absoluteValue
import kotlin.math.roundToInt

data class ExerciseProgressPoint(
    val sessionId: Long,
    val sessionDate: Long,
    val maxWeight: Double,
    val totalVolume: Double,
    val totalReps: Int,
    /** Best estimated 1RM among this session's sets; null when no set has a positive weight. */
    val estimatedOneRepMax: Double? = null
)

data class ExerciseProgressSpotlightUiModel(
    val title: String = "",
    val subtitle: String = "",
    val latestWeightLabel: String = "--",
    val latestWeightCaption: String = "",
    val weightDeltaLabel: String = "",
    val latestVolumeLabel: String = "--",
    val latestVolumeCaption: String = "",
    val volumeDeltaLabel: String = "",
    val allTimeBestLabel: String = "PR --",
    val consistencyLabel: String = ""
)

data class ExerciseTrendChartPointUiModel(
    val sessionId: Long,
    val label: String,
    val shortLabel: String,
    val maxWeight: Double,
    val totalVolume: Double,
    val totalReps: Int,
    val weightLabel: String,
    val volumeLabel: String,
    val repsLabel: String,
    val weightRatio: Float,
    val volumeRatio: Float,
    val isLatest: Boolean = false,
    val estimatedOneRepMax: Double? = null,
    val oneRepMaxRatio: Float = 0f
)

data class ExerciseTrendChartUiModel(
    val points: List<ExerciseTrendChartPointUiModel> = emptyList(),
    val weightTrendLabel: String = "",
    val volumeTrendLabel: String = "",
    val peakWeightLabel: String = "--",
    val averageVolumeLabel: String = "--",
    /** Sessions (of the visible window) with an estimated 1RM; empty when fewer than two have one. */
    val oneRepMaxPoints: List<ExerciseTrendChartPointUiModel> = emptyList(),
    val oneRepMaxTrendLabel: String = "",
    /** Best estimated 1RM across all given sessions; null when none has one. */
    val bestOneRepMaxLabel: String? = null
)

data class ExerciseProgressUiState(
    val monthOffset: Int = 0,
    val monthLabel: String = DateTimeUtils.monthLabel(0),
    val exercises: List<ExerciseEntity> = emptyList(),
    val frequentExerciseIds: List<Long> = emptyList(),
    val exerciseWorkoutCounts: Map<Long, Int> = emptyMap(),
    val exerciseMuscleIds: Map<String, Set<String>> = emptyMap(),
    /** Muscle id to weight for the selected exercise: the manual mapping when set, else the default. */
    val selectedMuscleIntensities: Map<String, Float> = emptyMap(),
    val selectedExerciseId: Long? = null,
    val selectedExerciseName: String? = null,
    val history: List<ExerciseHistoryEntry> = emptyList(),
    val progressPoints: List<ExerciseProgressPoint> = emptyList(),
    val bestWeight: Double? = null,
    val averageWeight: Double? = null,
    val spotlight: ExerciseProgressSpotlightUiModel = ExerciseProgressSpotlightUiModel(),
    val trendChart: ExerciseTrendChartUiModel = ExerciseTrendChartUiModel(),
    /** Record-breaking sets of the selected exercise over its whole history, newest first (max 50). */
    val personalRecords: List<PersonalRecordEvent> = emptyList()
)

private data class ExerciseProgressCatalog(
    val exercises: List<ExerciseEntity>,
    val frequentExerciseIds: List<Long>,
    val workoutCounts: Map<Long, Int>,
    val muscleIdsByName: Map<String, Set<String>>,
    val manualMappings: Map<String, List<MuscleContribution>>
)

/**
 * Muscles loaded by [exerciseName] with their weights, matching iOS
 * `MuscleMappingEngine.contributions(for:manualMappings:)`: a non-empty manual mapping wins as-is
 * (its stored weights), otherwise the catalog/name-guess default.
 */
internal fun progressMuscleIntensities(
    exerciseName: String?,
    manualMappings: Map<String, List<MuscleContribution>>
): Map<String, Float> {
    if (exerciseName == null) return emptyMap()
    return muscleContributionsForExercise(exerciseName, manualMappings)
        .associate { it.muscleId to it.weight.toFloat() }
}

/** Month offsets are 0 (current) or negative; the next month never goes into the future. */
internal fun nextProgressMonthOffset(current: Int): Int = (current + 1).coerceAtMost(0)

/** "100 kg" / "102.5 kg": 0-1 fraction digits in the app locale, like iOS. */
internal fun formatProgressWeightLabel(weight: Double, locale: Locale, unit: String): String {
    val number = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 0
        maximumFractionDigits = 1
    }.format(weight)
    return "$number $unit"
}

internal fun progressFrequentExerciseIds(
    history: List<ExerciseHistoryEntry>,
    limit: Int = 12
): List<Long> = frequentExerciseIds(
    frequencies = exerciseFrequencyByExercise(history),
    limit = limit
)

/** Most-logged exercise (distinct sessions, then latest session) that exists in [exercises]. */
internal fun defaultProgressExerciseId(
    exercises: List<ExerciseEntity>,
    history: List<ExerciseHistoryEntry>
): Long? {
    if (exercises.isEmpty()) return null
    val knownIds = exercises.mapTo(hashSetOf()) { it.id }
    val mostLogged = frequentExerciseIds(
        frequencies = exerciseFrequencyByExercise(history),
        limit = Int.MAX_VALUE
    ).firstOrNull { it in knownIds }
    return mostLogged ?: exercises.first().id
}

/**
 * Keeps an explicit pick while it still exists; otherwise falls back to the most-logged exercise
 * (or the first listed exercise when nothing is logged yet).
 */
internal fun resolveProgressExerciseSelection(
    exercises: List<ExerciseEntity>,
    history: List<ExerciseHistoryEntry>,
    currentId: Long?,
    userPicked: Boolean
): Long? = resolveProgressExerciseSelection(exercises, currentId, userPicked) {
    defaultProgressExerciseId(exercises, history)
}

/** Same rule with the default computed by the caller (so the history scan can run off the main thread). */
internal inline fun resolveProgressExerciseSelection(
    exercises: List<ExerciseEntity>,
    currentId: Long?,
    userPicked: Boolean,
    defaultId: () -> Long?
): Long? {
    if (exercises.isEmpty()) return null
    if (userPicked && currentId != null && exercises.any { it.id == currentId }) return currentId
    return defaultId()
}

/**
 * Best estimated 1RM among one session's sets, using the shared [GymOneRepMax] formula. A set
 * without a positive weight (0 kg, bodyweight) has no estimate; null when no set qualifies.
 */
internal fun sessionEstimatedOneRepMax(entries: List<ExerciseHistoryEntry>): Double? =
    entries.filter { it.weight > 0.0 }.maxOfOrNull { GymOneRepMax.estimate(it.weight, it.reps) }

/** One point per session, oldest first. */
internal fun List<ExerciseHistoryEntry>.toExerciseProgressPoints(): List<ExerciseProgressPoint> =
    groupBy { it.sessionId }
        .values
        .map { entries ->
            ExerciseProgressPoint(
                sessionId = entries.first().sessionId,
                sessionDate = entries.first().sessionDate,
                maxWeight = entries.maxOfOrNull { it.weight } ?: 0.0,
                totalVolume = entries.sumOf { it.weight * it.reps },
                totalReps = entries.sumOf { it.reps },
                estimatedOneRepMax = sessionEstimatedOneRepMax(entries)
            )
        }
        .sortedBy { it.sessionDate }

/** Builds the localized spotlight/trend text for one language; a new instance per emission. */
internal class ExerciseProgressTextBuilder(
    private val languageTag: String,
    private val zoneId: ZoneId
) {
    private val locale: Locale = Locale.forLanguageTag(languageTag)
    private val isUkrainian = locale.language.equals("uk", ignoreCase = true)
    private val isRussian = locale.language.equals("ru", ignoreCase = true)

    fun buildSpotlight(
        exerciseName: String?,
        monthPoints: List<ExerciseProgressPoint>,
        allTimePoints: List<ExerciseProgressPoint>
    ): ExerciseProgressSpotlightUiModel {
        if (monthPoints.isEmpty()) {
            return ExerciseProgressSpotlightUiModel(
                title = exerciseName ?: t(
                    en = "No exercise data yet",
                    uk = "Ще немає даних вправи"
                )
            )
        }

        val latest = monthPoints.last()
        val previous = monthPoints.getOrNull(monthPoints.lastIndex - 1)
        val allTimeBest = allTimePoints.maxOfOrNull { it.maxWeight } ?: latest.maxWeight

        return ExerciseProgressSpotlightUiModel(
            title = exerciseName ?: t(en = "Exercise spotlight", uk = "Фокус вправи"),
            latestWeightLabel = formatWeight(latest.maxWeight),
            latestWeightCaption = t(en = "Latest max", uk = "Останній макс"),
            weightDeltaLabel = deltaLabel(
                latest = latest.maxWeight,
                previous = previous?.maxWeight,
                unit = t(en = "kg", uk = "кг")
            ),
            latestVolumeLabel = formatSessionVolume(latest.totalVolume.roundToInt().toDouble(), locale),
            latestVolumeCaption = t(en = "Latest volume", uk = "Останній обсяг"),
            volumeDeltaLabel = deltaLabel(
                latest = latest.totalVolume,
                previous = previous?.totalVolume,
                unit = t(en = "volume", uk = "обсягу")
            ),
            allTimeBestLabel = "PR ${formatWeight(allTimeBest)}",
            consistencyLabel = when {
                isUkrainian -> "${monthPoints.size} цього місяця"
                isRussian -> "${monthPoints.size} в этом месяце"
                else -> "${monthPoints.size} this month"
            }
        )
    }

    fun buildTrendChart(points: List<ExerciseProgressPoint>): ExerciseTrendChartUiModel {
        if (points.isEmpty()) {
            return ExerciseTrendChartUiModel()
        }

        val visiblePoints = points.takeLast(8)
        val maxWeight = visiblePoints.maxOfOrNull { it.maxWeight }?.coerceAtLeast(1.0) ?: 1.0
        val maxVolume = visiblePoints.maxOfOrNull { it.totalVolume }?.coerceAtLeast(1.0) ?: 1.0
        val maxOneRepMax = visiblePoints.mapNotNull { it.estimatedOneRepMax }.maxOrNull()?.coerceAtLeast(1.0) ?: 1.0

        val chartPoints = visiblePoints.mapIndexed { index, point ->
            ExerciseTrendChartPointUiModel(
                sessionId = point.sessionId,
                label = DateTimeUtils.formatDate(point.sessionDate, locale, zoneId),
                shortLabel = DateTimeUtils.formatChartAxisDate(point.sessionDate, locale, zoneId),
                maxWeight = point.maxWeight,
                totalVolume = point.totalVolume,
                totalReps = point.totalReps,
                weightLabel = formatWeight(point.maxWeight),
                volumeLabel = formatSessionVolume(point.totalVolume.roundToInt().toDouble(), locale),
                repsLabel = when {
                    isUkrainian -> "${point.totalReps} повт"
                    isRussian -> "${point.totalReps} повт"
                    point.totalReps == 1 -> "1 rep"
                    else -> "${point.totalReps} reps"
                },
                weightRatio = (point.maxWeight / maxWeight).toFloat().coerceIn(0f, 1f),
                volumeRatio = (point.totalVolume / maxVolume).toFloat().coerceIn(0f, 1f),
                isLatest = index == visiblePoints.lastIndex,
                estimatedOneRepMax = point.estimatedOneRepMax,
                oneRepMaxRatio = ((point.estimatedOneRepMax ?: 0.0) / maxOneRepMax).toFloat().coerceIn(0f, 1f)
            )
        }
        // The 1RM chart needs two sessions with an estimate, like any other trend.
        val oneRepMaxPoints = chartPoints
            .filter { it.estimatedOneRepMax != null }
            .let { withEstimate ->
                if (withEstimate.size >= 2) {
                    withEstimate.mapIndexed { index, point -> point.copy(isLatest = index == withEstimate.lastIndex) }
                } else {
                    emptyList()
                }
            }

        // A trend needs at least two sessions; one point has nothing to compare against.
        val hasTrend = visiblePoints.size >= 2
        val noTrendLabel = t(en = "No trend yet", uk = "Тренду ще немає")

        return ExerciseTrendChartUiModel(
            points = chartPoints,
            weightTrendLabel = if (hasTrend) {
                trendLabel(
                    start = visiblePoints.first().maxWeight,
                    end = visiblePoints.last().maxWeight,
                    unit = t(en = "kg", uk = "кг")
                )
            } else {
                noTrendLabel
            },
            volumeTrendLabel = if (hasTrend) {
                trendLabel(
                    start = visiblePoints.first().totalVolume,
                    end = visiblePoints.last().totalVolume,
                    unit = t(en = "volume", uk = "обсяг")
                )
            } else {
                noTrendLabel
            },
            peakWeightLabel = formatWeight(points.maxOfOrNull { it.maxWeight } ?: 0.0),
            averageVolumeLabel = visiblePoints.map { it.totalVolume }.average().roundToInt().toString(),
            oneRepMaxPoints = oneRepMaxPoints,
            oneRepMaxTrendLabel = if (oneRepMaxPoints.size >= 2) {
                trendLabel(
                    start = oneRepMaxPoints.first().estimatedOneRepMax ?: 0.0,
                    end = oneRepMaxPoints.last().estimatedOneRepMax ?: 0.0,
                    unit = t(en = "kg", uk = "кг")
                )
            } else {
                noTrendLabel
            },
            bestOneRepMaxLabel = points.mapNotNull { it.estimatedOneRepMax }.maxOrNull()?.let(::formatWeight)
        )
    }

    private fun trendLabel(start: Double, end: Double, unit: String): String {
        val delta = end - start
        if (delta.absoluteValue < 0.05) {
            return t(en = "Holding steady", uk = "Стабільно")
        }
        val prefix = if (delta > 0) "+" else "\u2212"
        return when {
            isUkrainian -> "$prefix${formatTrendValue(delta.absoluteValue)} $unit відносно першої сесії"
            isRussian -> "$prefix${formatTrendValue(delta.absoluteValue)} $unit относительно первой сессии"
            else -> "$prefix${formatTrendValue(delta.absoluteValue)} $unit vs first session"
        }
    }

    private fun deltaLabel(latest: Double, previous: Double?, unit: String): String {
        if (previous == null) {
            return t(en = "First session in range", uk = "Перша сесія у вибраному періоді")
        }
        val delta = latest - previous
        if (delta.absoluteValue < 0.05) {
            return t(en = "Flat vs previous", uk = "Без змін від попередньої")
        }
        val prefix = if (delta > 0) "+" else "\u2212"
        return when {
            isUkrainian -> "$prefix${formatTrendValue(delta.absoluteValue)} $unit відносно попередньої"
            isRussian -> "$prefix${formatTrendValue(delta.absoluteValue)} $unit относительно предыдущей"
            else -> "$prefix${formatTrendValue(delta.absoluteValue)} $unit vs previous"
        }
    }

    private fun formatTrendValue(value: Double): String {
        return if (value >= 10) {
            value.roundToInt().toString()
        } else {
            String.format(locale, "%.1f", value)
        }
    }

    private fun formatWeight(weight: Double): String = formatProgressWeightLabel(
        weight = weight,
        locale = locale,
        unit = if (isUkrainian || isRussian) "кг" else "kg"
    )

    private fun t(en: String, uk: String): String = localizedText(languageTag, en, uk)
}

@OptIn(ExperimentalCoroutinesApi::class)
class ExerciseProgressViewModel(
    private val repository: GymRepository,
    private val zoneProvider: () -> ZoneId = { ZoneId.systemDefault() },
    // The in-app language; labels are rebuilt when it changes (ViewModel outlives the Activity recreate).
    private val languageTag: StateFlow<String> = AppLanguageSignal.tag
) : ViewModel() {
    // Read per use (not cached) so a device timezone change is picked up on the next emission.
    private val zoneId: ZoneId get() = zoneProvider()
    private val monthOffset = MutableStateFlow(0)
    private val selectedExerciseId = MutableStateFlow<Long?>(null)
    /** Set once the user picks an exercise, so the most-logged default stops following history. */
    private var userPickedExercise = false

    private val exercises = repository.observeExercises().stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = emptyList()
    )
    /** One upstream of the whole-history join for this ViewModel; comparison runs off the main thread. */
    private val allExerciseHistoryFlow = repository.observeAllExerciseHistory()
        .distinctUntilChanged()
        .flowOn(Dispatchers.Default)
        .shareIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            replay = 1
        )
    private val exerciseCatalogFlow = combine(
        exercises,
        allExerciseHistoryFlow,
        repository.observeExerciseMuscleMappings()
    ) { exerciseList, history, mappings ->
        val manualMappings = mappings.toManualContributionMap()
        val exerciseFrequencies = exerciseFrequencyByExercise(history)
        ExerciseProgressCatalog(
            exercises = exerciseList,
            frequentExerciseIds = frequentExerciseIds(exerciseFrequencies),
            workoutCounts = exerciseFrequencies.mapValues { (_, frequency) ->
                frequency.workoutCount
            },
            muscleIdsByName = exerciseList.associate { exercise ->
                val contributions = muscleContributionsForExercise(exercise.name, manualMappings)
                exercise.name to contributions.mapTo(linkedSetOf()) { it.muscleId }
            },
            manualMappings = manualMappings
        )
    }

    private val historyFlow = combine(selectedExerciseId, monthOffset) { exerciseId, offset ->
        exerciseId to offset
    }.flatMapLatest { (exerciseId, offset) ->
        if (exerciseId == null) {
            flowOf(emptyList())
        } else {
            repository.observeExerciseHistoryForMonth(exerciseId, offset)
        }
    }

    private val fullHistoryFlow = selectedExerciseId.flatMapLatest { exerciseId ->
        if (exerciseId == null) {
            flowOf(emptyList())
        } else {
            repository.observeExerciseHistory(exerciseId)
        }
    }

    // The record replay walks the whole history, so it runs once per history change on Default and is
    // not repeated when only the month or language changes.
    private val fullHistoryWithRecordsFlow = fullHistoryFlow
        .map { history -> history to personalRecordHistory(history) }
        .flowOn(Dispatchers.Default)

    // Re-emits when the in-app language changes so spotlight/trend text and number formats follow it.
    private val localizedHistoryFlow = combine(historyFlow, languageTag) { history, tag -> history to tag }

    private val progressState = combine(
        monthOffset,
        exerciseCatalogFlow,
        selectedExerciseId,
        localizedHistoryFlow,
        fullHistoryWithRecordsFlow
    ) { offset, catalog, selectedId, (history, tag), (fullHistory, personalRecords) ->
        val textBuilder = ExerciseProgressTextBuilder(tag, zoneId)
        val exerciseList = catalog.exercises
        val selectedExerciseName = exerciseList.firstOrNull { it.id == selectedId }?.name
        val progressPoints = history.toProgressPoints()
        val allTimePoints = fullHistory.toProgressPoints()
        val bestWeight = progressPoints.maxOfOrNull { it.maxWeight }
        val averageWeight = if (progressPoints.isEmpty()) null else {
            progressPoints.map { it.maxWeight }.average()
        }

        ExerciseProgressUiState(
            monthOffset = offset,
            monthLabel = DateTimeUtils.monthLabel(offset),
            exercises = exerciseList,
            frequentExerciseIds = catalog.frequentExerciseIds,
            exerciseWorkoutCounts = catalog.workoutCounts,
            exerciseMuscleIds = catalog.muscleIdsByName,
            selectedMuscleIntensities = progressMuscleIntensities(selectedExerciseName, catalog.manualMappings),
            selectedExerciseId = selectedId,
            selectedExerciseName = selectedExerciseName,
            history = history,
            progressPoints = progressPoints,
            bestWeight = bestWeight,
            averageWeight = averageWeight,
            spotlight = textBuilder.buildSpotlight(
                exerciseName = selectedExerciseName,
                monthPoints = progressPoints,
                allTimePoints = allTimePoints
            ),
            trendChart = textBuilder.buildTrendChart(progressPoints),
            personalRecords = personalRecords
        )
    }

    val uiState: StateFlow<ExerciseProgressUiState> = progressState
        .flowOn(Dispatchers.Default)
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = ExerciseProgressUiState()
        )

    init {
        viewModelScope.launch {
            // The history scan for the default pick runs on Default; the pick itself is resolved on the
            // collector's thread so a concurrent user selection is never overwritten by a stale value.
            combine(exercises, allExerciseHistoryFlow) { list, history ->
                list to defaultProgressExerciseId(list, history)
            }.flowOn(Dispatchers.Default).collect { (list, defaultId) ->
                selectedExerciseId.value = resolveProgressExerciseSelection(
                    exercises = list,
                    currentId = selectedExerciseId.value,
                    userPicked = userPickedExercise
                ) { defaultId }
            }
        }
    }

    fun selectExercise(exerciseId: Long) {
        userPickedExercise = true
        selectedExerciseId.value = exerciseId
    }

    fun previousMonth() {
        monthOffset.update { it - 1 }
    }

    fun nextMonth() {
        monthOffset.update(::nextProgressMonthOffset)
    }

    fun currentMonth() {
        monthOffset.value = 0
    }

    private fun List<ExerciseHistoryEntry>.toProgressPoints(): List<ExerciseProgressPoint> =
        toExerciseProgressPoints()

    companion object {
        fun factory(repository: GymRepository): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ExerciseProgressViewModel(repository)
            }
        }
    }
}
