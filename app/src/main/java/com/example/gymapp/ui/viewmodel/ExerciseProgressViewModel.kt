package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.absoluteValue
import kotlin.math.roundToInt

data class ExerciseProgressPoint(
    val sessionId: Long,
    val sessionDate: Long,
    val maxWeight: Double,
    val totalVolume: Double,
    val totalReps: Int
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
    val isLatest: Boolean = false
)

data class ExerciseTrendChartUiModel(
    val points: List<ExerciseTrendChartPointUiModel> = emptyList(),
    val weightTrendLabel: String = "",
    val volumeTrendLabel: String = "",
    val peakWeightLabel: String = "--",
    val averageVolumeLabel: String = "--"
)

data class ExerciseProgressUiState(
    val monthOffset: Int = 0,
    val monthLabel: String = DateTimeUtils.monthLabel(0),
    val exercises: List<ExerciseEntity> = emptyList(),
    val selectedExerciseId: Long? = null,
    val selectedExerciseName: String? = null,
    val history: List<ExerciseHistoryEntry> = emptyList(),
    val progressPoints: List<ExerciseProgressPoint> = emptyList(),
    val bestWeight: Double? = null,
    val averageWeight: Double? = null,
    val spotlight: ExerciseProgressSpotlightUiModel = ExerciseProgressSpotlightUiModel(),
    val trendChart: ExerciseTrendChartUiModel = ExerciseTrendChartUiModel()
)

@OptIn(ExperimentalCoroutinesApi::class)
class ExerciseProgressViewModel(
    private val repository: GymRepository
) : ViewModel() {
    private val zoneId = ZoneId.systemDefault()
    private val locale = Locale.getDefault()
    private val isUkrainian = locale.language.equals("uk", ignoreCase = true)
    private val shortDateFormatter = DateTimeFormatter.ofPattern("d MMM", locale)
    private val monthOffset = MutableStateFlow(0)
    private val selectedExerciseId = MutableStateFlow<Long?>(null)

    private val exercises = repository.observeExercises().stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = emptyList()
    )

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

    val uiState: StateFlow<ExerciseProgressUiState> = combine(
        monthOffset,
        exercises,
        selectedExerciseId,
        historyFlow,
        fullHistoryFlow
    ) { offset, exerciseList, selectedId, history, fullHistory ->
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
            selectedExerciseId = selectedId,
            selectedExerciseName = selectedExerciseName,
            history = history,
            progressPoints = progressPoints,
            bestWeight = bestWeight,
            averageWeight = averageWeight,
            spotlight = buildSpotlight(
                exerciseName = selectedExerciseName,
                monthPoints = progressPoints,
                allTimePoints = allTimePoints
            ),
            trendChart = buildTrendChart(progressPoints)
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ExerciseProgressUiState()
    )

    init {
        viewModelScope.launch {
            exercises.collect { list ->
                if (list.isEmpty()) {
                    selectedExerciseId.value = null
                } else {
                    val current = selectedExerciseId.value
                    val stillExists = current != null && list.any { it.id == current }
                    if (!stillExists) {
                        selectedExerciseId.value = list.first().id
                    }
                }
            }
        }
    }

    fun selectExercise(exerciseId: Long) {
        selectedExerciseId.value = exerciseId
    }

    fun previousMonth() {
        monthOffset.update { it - 1 }
    }

    fun nextMonth() {
        monthOffset.update { it + 1 }
    }

    fun currentMonth() {
        monthOffset.value = 0
    }

    fun deleteHistoryEntry(setId: Long) {
        viewModelScope.launch {
            repository.deleteSetById(setId)
        }
    }

    private fun List<ExerciseHistoryEntry>.toProgressPoints(): List<ExerciseProgressPoint> {
        return groupBy { it.sessionId }
            .values
            .map { entries ->
                ExerciseProgressPoint(
                    sessionId = entries.first().sessionId,
                    sessionDate = entries.first().sessionDate,
                    maxWeight = entries.maxOfOrNull { it.weight } ?: 0.0,
                    totalVolume = entries.sumOf { it.weight * it.reps },
                    totalReps = entries.sumOf { it.reps }
                )
            }
            .sortedBy { it.sessionDate }
    }

    private fun buildSpotlight(
        exerciseName: String?,
        monthPoints: List<ExerciseProgressPoint>,
        allTimePoints: List<ExerciseProgressPoint>
    ): ExerciseProgressSpotlightUiModel {
        if (monthPoints.isEmpty()) {
            return ExerciseProgressSpotlightUiModel(
                title = exerciseName ?: t(
                    en = "No exercise data yet",
                    uk = "Ще немає даних вправи"
                ),
                subtitle = if (exerciseName == null) {
                    t(
                        en = "Pick an exercise to see solo progress.",
                        uk = "Обери вправу, щоб побачити свій прогрес."
                    )
                } else {
                    t(
                        en = "Log sets for $exerciseName to unlock trends.",
                        uk = "Додай підходи для $exerciseName, щоб відкрити тренди."
                    )
                }
            )
        }

        val latest = monthPoints.last()
        val previous = monthPoints.getOrNull(monthPoints.lastIndex - 1)
        val allTimeBest = allTimePoints.maxOfOrNull { it.maxWeight } ?: latest.maxWeight

        return ExerciseProgressSpotlightUiModel(
            title = exerciseName ?: t(en = "Exercise spotlight", uk = "Фокус вправи"),
            subtitle = if (isUkrainian) {
                "${monthPoints.size} сес. у вибраному місяці."
            } else {
                "${monthPoints.size} session${if (monthPoints.size == 1) "" else "s"} in the selected month."
            },
            latestWeightLabel = formatWeight(latest.maxWeight),
            latestWeightCaption = t(en = "Latest max", uk = "Останній макс"),
            weightDeltaLabel = deltaLabel(
                latest = latest.maxWeight,
                previous = previous?.maxWeight,
                unit = t(en = "kg", uk = "кг")
            ),
            latestVolumeLabel = latest.totalVolume.roundToInt().toString(),
            latestVolumeCaption = t(en = "Latest volume", uk = "Останній обсяг"),
            volumeDeltaLabel = deltaLabel(
                latest = latest.totalVolume,
                previous = previous?.totalVolume,
                unit = t(en = "volume", uk = "обсягу")
            ),
            allTimeBestLabel = "PR ${formatWeight(allTimeBest)}",
            consistencyLabel = if (isUkrainian) {
                "${monthPoints.size} цього місяця"
            } else {
                "${monthPoints.size} this month"
            }
        )
    }

    private fun buildTrendChart(points: List<ExerciseProgressPoint>): ExerciseTrendChartUiModel {
        if (points.isEmpty()) {
            return ExerciseTrendChartUiModel()
        }

        val visiblePoints = points.takeLast(8)
        val maxWeight = visiblePoints.maxOfOrNull { it.maxWeight }?.coerceAtLeast(1.0) ?: 1.0
        val maxVolume = visiblePoints.maxOfOrNull { it.totalVolume }?.coerceAtLeast(1.0) ?: 1.0

        val chartPoints = visiblePoints.mapIndexed { index, point ->
            val localDate = Instant.ofEpochMilli(point.sessionDate).atZone(zoneId).toLocalDate()
            ExerciseTrendChartPointUiModel(
                sessionId = point.sessionId,
                label = localDate.format(shortDateFormatter),
                shortLabel = localDate.dayOfMonth.toString(),
                maxWeight = point.maxWeight,
                totalVolume = point.totalVolume,
                totalReps = point.totalReps,
                weightLabel = formatWeight(point.maxWeight),
                volumeLabel = point.totalVolume.roundToInt().toString(),
                repsLabel = if (isUkrainian) {
                    "${point.totalReps} повт"
                } else {
                    "${point.totalReps} reps"
                },
                weightRatio = (point.maxWeight / maxWeight).toFloat().coerceIn(0f, 1f),
                volumeRatio = (point.totalVolume / maxVolume).toFloat().coerceIn(0f, 1f),
                isLatest = index == visiblePoints.lastIndex
            )
        }

        return ExerciseTrendChartUiModel(
            points = chartPoints,
            weightTrendLabel = trendLabel(
                start = visiblePoints.first().maxWeight,
                end = visiblePoints.last().maxWeight,
                unit = t(en = "kg", uk = "кг")
            ),
            volumeTrendLabel = trendLabel(
                start = visiblePoints.first().totalVolume,
                end = visiblePoints.last().totalVolume,
                unit = t(en = "volume", uk = "обсяг")
            ),
            peakWeightLabel = formatWeight(points.maxOfOrNull { it.maxWeight } ?: 0.0),
            averageVolumeLabel = visiblePoints.map { it.totalVolume }.average().roundToInt().toString()
        )
    }

    private fun trendLabel(start: Double, end: Double, unit: String): String {
        val delta = end - start
        if (delta.absoluteValue < 0.05) {
            return t(en = "Holding steady", uk = "Стабільно")
        }
        val prefix = if (delta > 0) "+" else "-"
        return if (isUkrainian) {
            "$prefix${formatTrendValue(delta.absoluteValue)} $unit відносно першої сесії"
        } else {
            "$prefix${formatTrendValue(delta.absoluteValue)} $unit vs first session"
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
        val prefix = if (delta > 0) "+" else "-"
        return if (isUkrainian) {
            "$prefix${formatTrendValue(delta.absoluteValue)} $unit відносно попередньої"
        } else {
            "$prefix${formatTrendValue(delta.absoluteValue)} $unit vs previous"
        }
    }

    private fun formatTrendValue(value: Double): String {
        return if (value >= 10) {
            value.roundToInt().toString()
        } else {
            String.format(locale, "%.1f", value)
        }
    }

    private fun formatWeight(weight: Double): String = String.format(
        locale,
        "%.1f %s",
        weight,
        if (isUkrainian) "кг" else "kg"
    )

    private fun t(en: String, uk: String): String = if (isUkrainian) uk else en

    companion object {
        fun factory(repository: GymRepository): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ExerciseProgressViewModel(repository)
            }
        }
    }
}

