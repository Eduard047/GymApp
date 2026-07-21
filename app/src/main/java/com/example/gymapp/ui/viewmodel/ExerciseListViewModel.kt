package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.data.repository.BackupOwner
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.data.repository.normalizedExerciseName
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.util.LocalizedText
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
    val exerciseWorkoutCounts: Map<Long, Int> = emptyMap(),
    val muscleMappings: List<ExerciseMuscleMappingUiModel> = emptyList(),
    val mappingEditorExerciseName: String? = null,
    val mappingEditorMuscles: List<ExerciseMuscleOptionUiModel> = emptyList(),
    val newExerciseName: String = "",
    val hasInputError: Boolean = false,
    val editingExercise: ExerciseEntity? = null,
    val editingExerciseName: String = "",
    val selectedExerciseId: Long? = null,
    val selectedExerciseName: String? = null,
    val selectedExerciseHistory: List<ExerciseHistoryEntry> = emptyList(),
    val backupJson: String? = null,
    val backupIsDiagnostics: Boolean = false,
    val backupMessage: LocalizedText? = null,
    val importJson: String = "",
    val importMessage: LocalizedText? = null,
    val isImportOpen: Boolean = false,
    val accountLabel: String = "",
    val accountSupporting: String = "",
    val isCloudAccount: Boolean = false,
    val canLogout: Boolean = false
)

data class ExerciseMuscleMappingUiModel(
    val exerciseName: String,
    val muscleIds: List<String>,
    val isMapped: Boolean
)

data class ExerciseMuscleOptionUiModel(
    val id: String,
    val isSelected: Boolean
)

internal fun workoutCountByExercise(
    history: List<ExerciseHistoryEntry>
): Map<Long, Int> = history
    .groupBy { it.exerciseId }
    .mapValues { (_, entries) -> entries.map { it.sessionId }.distinct().size }

private data class ExerciseListBaseState(
    val exercises: List<ExerciseEntity>,
    val exerciseWorkoutCounts: Map<Long, Int>,
    val newExerciseName: String,
    val hasInputError: Boolean,
    val selectedExerciseId: Long?,
    val selectedExerciseHistory: List<ExerciseHistoryEntry>
)

private data class ExerciseLibraryState(
    val exercises: List<ExerciseEntity>,
    val exerciseWorkoutCounts: Map<Long, Int>
)

private data class ExerciseEditState(
    val editingExercise: ExerciseEntity?,
    val editingExerciseName: String
)

private data class ExerciseBackupState(
    val generatedExport: GeneratedExerciseExport?,
    val backupMessage: LocalizedText?,
    val importJson: String,
    val importMessage: LocalizedText?,
    val isImportOpen: Boolean
)

private data class GeneratedExerciseExport(
    val json: String,
    val diagnosticsOnly: Boolean
)

private data class ExerciseMappingState(
    val mappings: List<ExerciseMuscleMappingUiModel>,
    val editorExerciseName: String?,
    val editorMuscles: List<ExerciseMuscleOptionUiModel>
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
    private val generatedExport = MutableStateFlow<GeneratedExerciseExport?>(null)
    private val backupMessage = MutableStateFlow<LocalizedText?>(null)
    private val importJson = MutableStateFlow("")
    private val importMessage = MutableStateFlow<LocalizedText?>(null)
    private val isImportOpen = MutableStateFlow(false)
    private val mappingEditorExerciseName = MutableStateFlow<String?>(null)

    private val selectedExerciseHistory = selectedExerciseId.flatMapLatest { exerciseId ->
        if (exerciseId == null) {
            flowOf(emptyList())
        } else {
            repository.observeExerciseHistory(exerciseId)
        }
    }

    private val exerciseLibraryState = combine(
        repository.observeExercises(),
        repository.observeAllExerciseHistory()
    ) { exercises, history ->
        ExerciseLibraryState(
            exercises = exercises,
            exerciseWorkoutCounts = workoutCountByExercise(history)
        )
    }

    private val baseState = combine(
        exerciseLibraryState,
        newExerciseName,
        hasInputError,
        selectedExerciseId,
        selectedExerciseHistory
    ) { library, name, error, selectedId, history ->
        ExerciseListBaseState(
            exercises = library.exercises,
            exerciseWorkoutCounts = library.exerciseWorkoutCounts,
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
        generatedExport,
        backupMessage,
        importJson,
        importMessage,
        isImportOpen
    ) { export, backupStatus, importText, importStatus, importOpen ->
        ExerciseBackupState(
            generatedExport = export,
            backupMessage = backupStatus,
            importJson = importText,
            importMessage = importStatus,
            isImportOpen = importOpen
        )
    }

    private val mappingState = combine(
        repository.observeExercises(),
        repository.observeExerciseMuscleMappings(),
        mappingEditorExerciseName
    ) { exercises, muscleMappings, editorExerciseName ->
        val manualMap = muscleMappings.toManualContributionMap()
        val mappingRows = exercises.map { exercise ->
            val contributions = manualMap[exercise.name.normalizedExerciseName()]
                ?: defaultContributionsForExercise(exercise.name)
            val muscleIds = contributions
                .map { it.muscleId }
                .distinct()
            ExerciseMuscleMappingUiModel(
                exerciseName = exercise.name,
                muscleIds = muscleIds,
                isMapped = muscleIds.isNotEmpty()
            )
        }.sortedWith(
            compareBy<ExerciseMuscleMappingUiModel> { it.isMapped }
                .thenBy { it.exerciseName.lowercase() }
        )
        val editorSelectedIds = editorExerciseName
            ?.let { name ->
                manualMap[name.normalizedExerciseName()]
                    ?: defaultContributionsForExercise(name).takeIf { it.isNotEmpty() }
            }
            ?.map { it.muscleId }
            ?.toSet()
            ?: emptySet()
        ExerciseMappingState(
            mappings = mappingRows,
            editorExerciseName = editorExerciseName,
            editorMuscles = MUSCLE_DEFINITIONS.map { definition ->
                ExerciseMuscleOptionUiModel(
                    id = definition.id,
                    isSelected = definition.id in editorSelectedIds
                )
            }
        )
    }

    val uiState: StateFlow<ExerciseListUiState> = combine(
        baseState,
        editState,
        backupState,
        mappingState
    ) { base, edit, backup, mapping ->
        ExerciseListUiState(
            exercises = base.exercises,
            exerciseWorkoutCounts = base.exerciseWorkoutCounts,
            muscleMappings = mapping.mappings,
            mappingEditorExerciseName = mapping.editorExerciseName,
            mappingEditorMuscles = mapping.editorMuscles,
            newExerciseName = base.newExerciseName,
            hasInputError = base.hasInputError,
            editingExercise = edit.editingExercise,
            editingExerciseName = edit.editingExerciseName,
            selectedExerciseId = base.selectedExerciseId,
            selectedExerciseName = base.exercises.firstOrNull { it.id == base.selectedExerciseId }?.name,
            selectedExerciseHistory = base.selectedExerciseHistory,
            backupJson = backup.generatedExport?.json,
            backupIsDiagnostics = backup.generatedExport?.diagnosticsOnly == true,
            backupMessage = backup.backupMessage,
            importJson = backup.importJson,
            importMessage = backup.importMessage,
            isImportOpen = backup.isImportOpen,
            accountLabel = activeAccountLabel(),
            accountSupporting = activeAccountSupporting(),
            isCloudAccount = authManager?.authState?.value?.session is AccountSession.Cloud,
            canLogout = authManager != null
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ExerciseListUiState()
    )

    init {
        viewModelScope.launch {
            repository.seedDefaultExerciseMuscleMappings()
        }
    }

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

    fun toggleFavorite(exercise: ExerciseEntity) {
        viewModelScope.launch {
            repository.toggleExerciseFavorite(exercise.id)
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

    fun openExerciseMapping(exerciseName: String) {
        mappingEditorExerciseName.value = exerciseName
    }

    fun closeExerciseMapping() {
        mappingEditorExerciseName.value = null
    }

    fun toggleExerciseMappingMuscle(muscleId: String) {
        val current = mappingEditorExerciseName.value ?: return
        val selectedIds = uiState.value.mappingEditorMuscles
            .filter { it.isSelected }
            .map { it.id }
            .toMutableSet()
        if (!selectedIds.add(muscleId)) {
            selectedIds.remove(muscleId)
        }
        viewModelScope.launch {
            repository.saveExerciseMuscleMapping(current, selectedIds.toList())
        }
    }

    fun saveExerciseMapping() {
        val exerciseName = mappingEditorExerciseName.value ?: return
        val selectedIds = uiState.value.mappingEditorMuscles
            .filter { it.isSelected }
            .map { it.id }
        viewModelScope.launch {
            repository.saveExerciseMuscleMapping(exerciseName, selectedIds)
            closeExerciseMapping()
        }
    }

    fun exportBackup() {
        viewModelScope.launch {
            runCatching {
                repository.exportBackupJson(includeDiagnostics = false, owner = activeBackupOwner())
            }.onSuccess { json ->
                generatedExport.value = GeneratedExerciseExport(
                    json = json,
                    diagnosticsOnly = false
                )
                backupMessage.value = LocalizedText(R.string.backup_export_ready)
            }.onFailure {
                backupMessage.value = LocalizedText(R.string.backup_export_failed)
            }
        }
    }

    fun exportDiagnostics() {
        viewModelScope.launch {
            runCatching {
                repository.exportDiagnosticsJson()
            }.onSuccess { json ->
                generatedExport.value = GeneratedExerciseExport(
                    json = json,
                    diagnosticsOnly = true
                )
                backupMessage.value = LocalizedText(R.string.backup_diagnostics_ready)
            }.onFailure {
                backupMessage.value = LocalizedText(R.string.backup_diagnostics_export_failed)
            }
        }
    }

    fun clearBackupJson() {
        generatedExport.value = null
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
        if (!WorkoutDataLimits.canRetainBackupText(value)) {
            importJson.value = ""
            importMessage.value = LocalizedText(R.string.backup_file_too_large)
            return
        }
        importJson.value = value
        importMessage.value = null
    }

    fun importBackup() {
        val rawInput = importJson.value
        if (!WorkoutDataLimits.canRetainBackupText(rawInput)) {
            importMessage.value = LocalizedText(R.string.backup_file_too_large)
            return
        }
        val rawJson = rawInput.trim()
        if (rawJson.isBlank()) {
            importMessage.value = LocalizedText(R.string.backup_paste_first)
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
                    LocalizedText(R.string.backup_imported_workouts, importedSessions)
                } else {
                    LocalizedText(R.string.backup_import_no_new)
                }
                importJson.value = ""
                importMessage.value = null
                isImportOpen.value = false
            }.onFailure {
                val message = LocalizedText(R.string.backup_import_failed)
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
            null -> ""
        }
    }

    private fun activeAccountSupporting(): String {
        return when (val session = authManager?.authState?.value?.session) {
            is AccountSession.Cloud -> session.email
            is AccountSession.Local -> ""
            null -> ""
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
