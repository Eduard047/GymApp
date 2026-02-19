package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.GymRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ExerciseListUiState(
    val exercises: List<ExerciseEntity> = emptyList(),
    val newExerciseName: String = "",
    val hasInputError: Boolean = false
)

class ExerciseListViewModel(
    private val repository: GymRepository
) : ViewModel() {
    private val newExerciseName = MutableStateFlow("")
    private val hasInputError = MutableStateFlow(false)

    val uiState: StateFlow<ExerciseListUiState> = combine(
        repository.observeExercises(),
        newExerciseName,
        hasInputError
    ) { exercises, name, error ->
        ExerciseListUiState(
            exercises = exercises,
            newExerciseName = name,
            hasInputError = error
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

    companion object {
        fun factory(repository: GymRepository): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ExerciseListViewModel(repository)
            }
        }
    }
}

