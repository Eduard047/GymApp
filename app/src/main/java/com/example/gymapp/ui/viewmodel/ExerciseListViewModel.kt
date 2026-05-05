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
    val selectedExerciseHistory: List<ExerciseHistoryEntry> = emptyList(),
    val backupJson: String? = null,
    val backupMessage: String? = null,
    val importJson: String = "",
    val isImportOpen: Boolean = false
)

private data class ExerciseListBaseState(
    val exercises: List<ExerciseEntity>,
    val newExerciseName: String,
    val hasInputError: Boolean,
    val selectedExerciseId: Long?,
    val selectedExerciseHistory: List<ExerciseHistoryEntry>
)

private data class ExerciseBackupState(
    val backupJson: String?,
    val backupMessage: String?,
    val importJson: String,
    val isImportOpen: Boolean
)

@OptIn(ExperimentalCoroutinesApi::class)
class ExerciseListViewModel(
    private val repository: GymRepository
) : ViewModel() {
    private val newExerciseName = MutableStateFlow("")
    private val hasInputError = MutableStateFlow(false)
    private val selectedExerciseId = MutableStateFlow<Long?>(null)
    private val backupJson = MutableStateFlow<String?>(null)
    private val backupMessage = MutableStateFlow<String?>(null)
    private val importJson = MutableStateFlow("")
    private val isImportOpen = MutableStateFlow(false)

    private val selectedExerciseHistory = selectedExerciseId.flatMapLatest { exerciseId ->
        if (exerciseId == null) {
            flowOf(emptyList())
        } else {
            repository.observeExerciseHistory(exerciseId)
        }
    }

    private val baseState = combine(
        repository.observeExercises(),
        newExerciseName,
        hasInputError,
        selectedExerciseId,
        selectedExerciseHistory
    ) { exercises, name, error, selectedId, history ->
        ExerciseListBaseState(
            exercises = exercises,
            newExerciseName = name,
            hasInputError = error,
            selectedExerciseId = selectedId,
            selectedExerciseHistory = history
        )
    }

    private val backupState = combine(
        backupJson,
        backupMessage,
        importJson,
        isImportOpen
    ) { backup, backupStatus, importText, importOpen ->
        ExerciseBackupState(
            backupJson = backup,
            backupMessage = backupStatus,
            importJson = importText,
            isImportOpen = importOpen
        )
    }

    val uiState: StateFlow<ExerciseListUiState> = combine(
        baseState,
        backupState
    ) { base, backup ->
        ExerciseListUiState(
            exercises = base.exercises,
            newExerciseName = base.newExerciseName,
            hasInputError = base.hasInputError,
            selectedExerciseId = base.selectedExerciseId,
            selectedExerciseName = base.exercises.firstOrNull { it.id == base.selectedExerciseId }?.name,
            selectedExerciseHistory = base.selectedExerciseHistory,
            backupJson = backup.backupJson,
            backupMessage = backup.backupMessage,
            importJson = backup.importJson,
            isImportOpen = backup.isImportOpen
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

    fun exportBackup() {
        viewModelScope.launch {
            runCatching {
                repository.exportBackupJson(includeDiagnostics = false)
            }.onSuccess { json ->
                backupJson.value = json
                backupMessage.value = "Backup JSON ready"
            }.onFailure {
                backupMessage.value = "Backup export failed"
            }
        }
    }

    fun exportDiagnostics() {
        viewModelScope.launch {
            runCatching {
                repository.exportBackupJson(includeDiagnostics = true)
            }.onSuccess { json ->
                backupJson.value = json
                backupMessage.value = "Diagnostics snapshot ready"
            }.onFailure {
                backupMessage.value = "Diagnostics export failed"
            }
        }
    }

    fun clearBackupJson() {
        backupJson.value = null
    }

    fun openImport() {
        isImportOpen.value = true
    }

    fun closeImport() {
        isImportOpen.value = false
    }

    fun updateImportJson(value: String) {
        importJson.value = value
    }

    fun importBackup() {
        val rawJson = importJson.value
        viewModelScope.launch {
            runCatching {
                repository.importBackupJson(rawJson)
            }.onSuccess { importedSessions ->
                backupMessage.value = "Imported $importedSessions workouts"
                importJson.value = ""
                isImportOpen.value = false
            }.onFailure {
                backupMessage.value = "Backup import failed"
            }
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

