package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.GymRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ExerciseListUiState(
    val exercises: List<ExerciseEntity> = emptyList(),
    val newExerciseName: String = "",
    val hasInputError: Boolean = false,
    val selectedExerciseId: Long? = null,
    val selectedExerciseName: String? = null,
    val selectedExerciseHistory: List<ExerciseHistoryEntry> = emptyList()
)

@OptIn(ExperimentalCoroutinesApi::class)
class ExerciseListViewModel(
    private val repository: GymRepository
) : ViewModel() {
    private val newExerciseName = MutableStateFlow("")
    private val hasInputError = MutableStateFlow(false)
    private val selectedExerciseId = MutableStateFlow<Long?>(null)

    private val selectedExerciseHistory = selectedExerciseId.flatMapLatest { exerciseId ->
        if (exerciseId == null) {
            flowOf(emptyList())
        } else {
            repository.observeExerciseHistory(exerciseId)
        }
    }

    val uiState: StateFlow<ExerciseListUiState> = combine(
        repository.observeExercises(),
        newExerciseName,
        hasInputError,
        selectedExerciseId,
        selectedExerciseHistory
    ) { exercises, name, error, selectedId, history ->
        ExerciseListUiState(
            exercises = exercises,
            newExerciseName = name,
            hasInputError = error,
            selectedExerciseId = selectedId,
            selectedExerciseName = exercises.firstOrNull { it.id == selectedId }?.name,
            selectedExerciseHistory = history
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ExerciseListUiState()
    )

    fun updateNewExerciseName(value: String) {
        newExerciseName.value = value
        hasInputError.value = false
    }

    fun addExercise() {
        val candidate = newExerciseName.value.trim()
        if (candidate.isEmpty()) {
            hasInputError.value = true
            return
        }

        viewModelScope.launch {
            runCatching {
                repository.addExercise(candidate)
            }.onSuccess {
                newExerciseName.value = ""
                hasInputError.value = false
            }.onFailure {
                hasInputError.value = true
            }
        }
    }

    fun deleteExercise(exercise: ExerciseEntity) {
        viewModelScope.launch {
            repository.deleteExercise(exercise)
        }
    }

    fun openExerciseHistory(exerciseId: Long) {
        selectedExerciseId.value = exerciseId
    }

    fun closeExerciseHistory() {
        selectedExerciseId.value = null
    }

    companion object {
        fun factory(repository: GymRepository): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ExerciseListViewModel(repository)
            }
        }
    }
}

