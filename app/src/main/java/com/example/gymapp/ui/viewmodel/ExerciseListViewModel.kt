package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.data.repository.BackupOwner
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
    val editingExercise: ExerciseEntity? = null,
    val editingExerciseName: String = "",
    val selectedExerciseId: Long? = null,
    val selectedExerciseName: String? = null,
    val selectedExerciseHistory: List<ExerciseHistoryEntry> = emptyList(),
    val backupJson: String? = null,
    val backupMessage: String? = null,
    val importJson: String = "",
    val importMessage: String? = null,
    val isImportOpen: Boolean = false,
    val accountLabel: String = "Local",
    val accountSupporting: String = "Offline on this phone",
    val canLogout: Boolean = false
)

private data class ExerciseListBaseState(
    val exercises: List<ExerciseEntity>,
    val newExerciseName: String,
    val hasInputError: Boolean,
    val selectedExerciseId: Long?,
    val selectedExerciseHistory: List<ExerciseHistoryEntry>
)

private data class ExerciseEditState(
    val editingExercise: ExerciseEntity?,
    val editingExerciseName: String
)

private data class ExerciseBackupState(
    val backupJson: String?,
    val backupMessage: String?,
    val importJson: String,
    val importMessage: String?,
    val isImportOpen: Boolean
)

@OptIn(ExperimentalCoroutinesApi::class)
class ExerciseListViewModel(
    private val repository: GymRepository,
    private val authManager: CloudAuthManager? = null
) : ViewModel() {
    private val newExerciseName = MutableStateFlow("")
    private val hasInputError = MutableStateFlow(false)
    private val editingExercise = MutableStateFlow<ExerciseEntity?>(null)
    private val editingExerciseName = MutableStateFlow("")
    private val selectedExerciseId = MutableStateFlow<Long?>(null)
    private val backupJson = MutableStateFlow<String?>(null)
    private val backupMessage = MutableStateFlow<String?>(null)
    private val importJson = MutableStateFlow("")
    private val importMessage = MutableStateFlow<String?>(null)
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

    private val editState = combine(
        editingExercise,
        editingExerciseName
    ) { exercise, name ->
        ExerciseEditState(
            editingExercise = exercise,
            editingExerciseName = name
        )
    }

    private val backupState = combine(
        backupJson,
        backupMessage,
        importJson,
        importMessage,
        isImportOpen
    ) { backup, backupStatus, importText, importStatus, importOpen ->
        ExerciseBackupState(
            backupJson = backup,
            backupMessage = backupStatus,
            importJson = importText,
            importMessage = importStatus,
            isImportOpen = importOpen
        )
    }

    val uiState: StateFlow<ExerciseListUiState> = combine(
        baseState,
        editState,
        backupState
    ) { base, edit, backup ->
        ExerciseListUiState(
            exercises = base.exercises,
            newExerciseName = base.newExerciseName,
            hasInputError = base.hasInputError,
            editingExercise = edit.editingExercise,
            editingExerciseName = edit.editingExerciseName,
            selectedExerciseId = base.selectedExerciseId,
            selectedExerciseName = base.exercises.firstOrNull { it.id == base.selectedExerciseId }?.name,
            selectedExerciseHistory = base.selectedExerciseHistory,
            backupJson = backup.backupJson,
            backupMessage = backup.backupMessage,
            importJson = backup.importJson,
            importMessage = backup.importMessage,
            isImportOpen = backup.isImportOpen,
            accountLabel = activeAccountLabel(),
            accountSupporting = activeAccountSupporting(),
            canLogout = authManager != null
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

    fun startRenameExercise(exercise: ExerciseEntity) {
        editingExercise.value = exercise
        editingExerciseName.value = exercise.name
        hasInputError.value = false
    }

    fun updateEditingExerciseName(value: String) {
        editingExerciseName.value = value
        hasInputError.value = false
    }

    fun closeRenameExercise() {
        editingExercise.value = null
        editingExerciseName.value = ""
    }

    fun saveRenameExercise() {
        val exercise = editingExercise.value ?: return
        val candidate = editingExerciseName.value.trim()
        if (candidate.isEmpty()) {
            hasInputError.value = true
            return
        }

        viewModelScope.launch {
            runCatching {
                repository.renameExercise(exercise, candidate)
            }.onSuccess {
                closeRenameExercise()
                hasInputError.value = false
            }.onFailure {
                hasInputError.value = true
            }
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
                repository.exportBackupJson(includeDiagnostics = false, owner = activeBackupOwner())
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
                repository.exportBackupJson(includeDiagnostics = true, owner = activeBackupOwner())
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
        importMessage.value = null
        isImportOpen.value = true
    }

    fun closeImport() {
        isImportOpen.value = false
        importMessage.value = null
    }

    fun updateImportJson(value: String) {
        importJson.value = value
        importMessage.value = null
    }

    fun importBackup() {
        val rawJson = importJson.value.trim()
        if (rawJson.isBlank()) {
            importMessage.value = "Paste backup JSON first"
            return
        }
        viewModelScope.launch {
            runCatching {
                val session = authManager?.authState?.value?.session
                repository.importBackupJson(
                    rawJson,
                    activeAccountId = (session as? AccountSession.Local)?.displayName,
                    activeUserId = (session as? AccountSession.Cloud)?.userId,
                    activeRemote = session is AccountSession.Cloud
                )
            }.onSuccess { importedSessions ->
                backupMessage.value = if (importedSessions > 0) {
                    "Imported $importedSessions workouts"
                } else {
                    "Import finished: no new workouts found"
                }
                importJson.value = ""
                importMessage.value = null
                isImportOpen.value = false
            }.onFailure { throwable ->
                val message = throwable.message
                    ?.takeIf { it.isNotBlank() }
                    ?: "Backup import failed. Check that the pasted text is valid GymApp JSON."
                importMessage.value = message
                backupMessage.value = message
            }
        }
    }

    fun logout() {
        authManager?.logout()
    }

    private fun activeBackupOwner(): BackupOwner? {
        return when (val session = authManager?.authState?.value?.session) {
            is AccountSession.Cloud -> BackupOwner(
                accountId = session.userId,
                userId = session.userId,
                email = session.email,
                remote = true
            )
            is AccountSession.Local -> BackupOwner(
                accountId = session.displayName,
                remote = false
            )
            null -> null
        }
    }

    private fun activeAccountLabel(): String {
        return when (val session = authManager?.authState?.value?.session) {
            is AccountSession.Cloud -> session.displayName
            is AccountSession.Local -> session.displayName
            null -> "Local"
        }
    }

    private fun activeAccountSupporting(): String {
        return when (val session = authManager?.authState?.value?.session) {
            is AccountSession.Cloud -> session.email
            is AccountSession.Local -> "Offline on this phone"
            null -> "Offline on this phone"
        }
    }

    companion object {
        fun factory(
            repository: GymRepository,
            authManager: CloudAuthManager? = null
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ExerciseListViewModel(repository, authManager)
            }
        }
    }
}

