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

data class ExerciseProgressPoint(
    val sessionId: Long,
    val sessionDate: Long,
    val maxWeight: Double,
    val totalVolume: Double,
    val totalReps: Int
)

data class ExerciseProgressUiState(
    val monthOffset: Int = 0,
    val monthLabel: String = DateTimeUtils.monthLabel(0),
    val exercises: List<ExerciseEntity> = emptyList(),
    val selectedExerciseId: Long? = null,
    val history: List<ExerciseHistoryEntry> = emptyList(),
    val progressPoints: List<ExerciseProgressPoint> = emptyList(),
    val bestWeight: Double? = null,
    val averageWeight: Double? = null
)

@OptIn(ExperimentalCoroutinesApi::class)
class ExerciseProgressViewModel(
    private val repository: GymRepository
) : ViewModel() {
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

    val uiState: StateFlow<ExerciseProgressUiState> = combine(
        monthOffset,
        exercises,
        selectedExerciseId,
        historyFlow
    ) { offset, exerciseList, selectedId, history ->
        val progressPoints = history
            .groupBy { it.sessionId }
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

        ExerciseProgressUiState(
            monthOffset = offset,
            monthLabel = DateTimeUtils.monthLabel(offset),
            exercises = exerciseList,
            selectedExerciseId = selectedId,
            history = history,
            progressPoints = progressPoints,
            bestWeight = progressPoints.maxOfOrNull { it.maxWeight },
            averageWeight = if (progressPoints.isEmpty()) null else {
                progressPoints.map { it.maxWeight }.average()
            }
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

    companion object {
        fun factory(repository: GymRepository): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ExerciseProgressViewModel(repository)
            }
        }
    }
}

