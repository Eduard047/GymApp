package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAuthManager
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.repository.BackupOwner
import com.example.gymapp.data.repository.ExerciseDeletionSnapshot
import com.example.gymapp.data.repository.ExerciseLoadDirection
import com.example.gymapp.data.repository.ExerciseLoadProfile
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.data.repository.normalizedExerciseName
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.util.LocalizedText
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class ExerciseListUiState(
    val isLoading: Boolean = false,
    val loadError: LocalizedText? = null,
    val exercises: List<ExerciseEntity> = emptyList(),
    val exerciseWorkoutCounts: Map<Long, Int> = emptyMap(),
    val muscleMappings: List<ExerciseMuscleMappingUiModel> = emptyList(),
    val mappingEditorExerciseName: String? = null,
    val mappingEditorMuscles: List<ExerciseMuscleOptionUiModel> = emptyList(),
    val loadProfiles: Map<Long, ExerciseLoadProfile> = emptyMap(),
    val loadEditorExercise: ExerciseEntity? = null,
    val loadEditorDirection: ExerciseLoadDirection = ExerciseLoadDirection.HigherIsHarder,
    val loadEditorWeights: String = "",
    val loadEditorHasError: Boolean = false,
    val newExerciseName: String = "",
    val hasInputError: Boolean = false,
    val editingExercise: ExerciseEntity? = null,
    val editingExerciseName: String = "",
    val selectedExerciseId: Long? = null,
    val selectedExerciseName: String? = null,
    val selectedExerciseHistory: List<ExerciseHistoryEntry> = emptyList(),
    val pendingExerciseDeletion: ExerciseDeletionSnapshot? = null,
    val isExerciseDeletionInProgress: Boolean = false,
    val exerciseDeletionError: LocalizedText? = null,
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

internal data class ExerciseAccountUiModel(
    val label: String,
    val supporting: String,
    val isCloudAccount: Boolean,
    val canLogout: Boolean
)

internal fun exerciseAccountUiModel(
    session: AccountSession?,
    canLogout: Boolean
): ExerciseAccountUiModel = when (session) {
    is AccountSession.Cloud -> ExerciseAccountUiModel(
        label = session.displayName,
        supporting = session.email,
        isCloudAccount = true,
        canLogout = canLogout
    )
    is AccountSession.Local -> ExerciseAccountUiModel(
        label = session.displayName,
        supporting = "",
        isCloudAccount = false,
        canLogout = canLogout
    )
    null -> ExerciseAccountUiModel(
        label = "",
        supporting = "",
        isCloudAccount = false,
        canLogout = false
    )
}

data class ExerciseMuscleMappingUiModel(
    val exerciseName: String,
    val muscleIds: List<String>,
    val isMapped: Boolean
)

data class ExerciseMuscleOptionUiModel(
    val id: String,
    val isSelected: Boolean
)

internal data class ExerciseFrequencySummary(
    val workoutCount: Int,
    val latestSessionDate: Long
)

internal fun exerciseFrequencyByExercise(
    history: List<ExerciseHistoryEntry>
): Map<Long, ExerciseFrequencySummary> {
    data class MutableFrequency(
        val sessionIds: MutableSet<Long> = hashSetOf(),
        var latestSessionDate: Long = Long.MIN_VALUE
    )

    val frequencies = linkedMapOf<Long, MutableFrequency>()
    history.forEach { entry ->
        val frequency = frequencies.getOrPut(entry.exerciseId) { MutableFrequency() }
        frequency.sessionIds += entry.sessionId
        if (entry.sessionDate > frequency.latestSessionDate) {
            frequency.latestSessionDate = entry.sessionDate
        }
    }
    return frequencies.mapValues { (_, frequency) ->
        ExerciseFrequencySummary(
            workoutCount = frequency.sessionIds.size,
            latestSessionDate = frequency.latestSessionDate
        )
    }
}

internal fun workoutCountByExercise(
    history: List<ExerciseHistoryEntry>
): Map<Long, Int> = exerciseFrequencyByExercise(history)
    .mapValues { (_, frequency) -> frequency.workoutCount }

internal fun frequentExerciseIds(
    frequencies: Map<Long, ExerciseFrequencySummary>,
    limit: Int = 12
): List<Long> {
    if (limit <= 0) return emptyList()
    return frequencies.entries
        .sortedWith(
            compareByDescending<Map.Entry<Long, ExerciseFrequencySummary>> {
                it.value.workoutCount
            }
                .thenByDescending { it.value.latestSessionDate }
                .thenBy { it.key }
        )
        .take(limit)
        .map(Map.Entry<Long, ExerciseFrequencySummary>::key)
}

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

private data class ExerciseDeletionState(
    val pending: ExerciseDeletionSnapshot?,
    val isInProgress: Boolean,
    val error: LocalizedText?
)

private data class ExerciseLoadEditorState(
    val profiles: Map<Long, ExerciseLoadProfile>,
    val exercise: ExerciseEntity?,
    val direction: ExerciseLoadDirection,
    val weights: String,
    val hasError: Boolean
)

private data class ExerciseConfigurationState(
    val mappings: ExerciseMappingState,
    val loadEditor: ExerciseLoadEditorState
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
    private val loadEditorExercise = MutableStateFlow<ExerciseEntity?>(null)
    private val loadEditorDirection = MutableStateFlow(ExerciseLoadDirection.HigherIsHarder)
    private val loadEditorWeights = MutableStateFlow("")
    private val loadEditorHasError = MutableStateFlow(false)
    private val pendingExerciseDeletion = MutableStateFlow<ExerciseDeletionSnapshot?>(null)
    private val isExerciseDeletionInProgress = MutableStateFlow(false)
    private val exerciseDeletionError = MutableStateFlow<LocalizedText?>(null)
    private val loadGeneration = MutableStateFlow(0L)

    private val exercises = repository.observeExercises()
    private val allExerciseHistory = repository.observeAllExerciseHistory()
    private val muscleMappings = repository.observeExerciseMuscleMappings()
    private val loadProfiles = repository.observeExerciseLoadProfiles()

    private val selectedExerciseHistory = selectedExerciseId.flatMapLatest { exerciseId ->
        if (exerciseId == null) {
            flowOf(emptyList())
        } else {
            repository.observeExerciseHistory(exerciseId)
        }
    }

    private val exerciseLibraryState = combine(
        exercises,
        allExerciseHistory
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
        exercises,
        muscleMappings,
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

    private val deletionState = combine(
        pendingExerciseDeletion,
        isExerciseDeletionInProgress,
        exerciseDeletionError
    ) { pending, isInProgress, error ->
        ExerciseDeletionState(
            pending = pending,
            isInProgress = isInProgress,
            error = error
        )
    }

    private val loadEditorState = combine(
        loadProfiles,
        loadEditorExercise,
        loadEditorDirection,
        loadEditorWeights,
        loadEditorHasError
    ) { profiles, exercise, direction, weights, error ->
        ExerciseLoadEditorState(
            profiles = profiles,
            exercise = exercise,
            direction = direction,
            weights = weights,
            hasError = error
        )
    }

    private val configurationState = combine(mappingState, loadEditorState) { mapping, loadEditor ->
        ExerciseConfigurationState(mapping, loadEditor)
    }

    val uiState: StateFlow<ExerciseListUiState> = loadGeneration.flatMapLatest {
        combine(
            baseState,
            editState,
            backupState,
            configurationState,
            deletionState
        ) { base, edit, backup, configuration, deletion ->
            val mapping = configuration.mappings
            val loadEditor = configuration.loadEditor
            val account = activeAccountUiModel()
            ExerciseListUiState(
                isLoading = false,
                exercises = base.exercises,
                exerciseWorkoutCounts = base.exerciseWorkoutCounts,
                muscleMappings = mapping.mappings,
                mappingEditorExerciseName = mapping.editorExerciseName,
                mappingEditorMuscles = mapping.editorMuscles,
                loadProfiles = loadEditor.profiles,
                loadEditorExercise = loadEditor.exercise,
                loadEditorDirection = loadEditor.direction,
                loadEditorWeights = loadEditor.weights,
                loadEditorHasError = loadEditor.hasError,
                newExerciseName = base.newExerciseName,
                hasInputError = base.hasInputError,
                editingExercise = edit.editingExercise,
                editingExerciseName = edit.editingExerciseName,
                selectedExerciseId = base.selectedExerciseId,
                selectedExerciseName = base.exercises
                    .firstOrNull { it.id == base.selectedExerciseId }
                    ?.name,
                selectedExerciseHistory = base.selectedExerciseHistory,
                pendingExerciseDeletion = deletion.pending,
                isExerciseDeletionInProgress = deletion.isInProgress,
                exerciseDeletionError = deletion.error,
                backupJson = backup.generatedExport?.json,
                backupIsDiagnostics = backup.generatedExport?.diagnosticsOnly == true,
                backupMessage = backup.backupMessage,
                importJson = backup.importJson,
                importMessage = backup.importMessage,
                isImportOpen = backup.isImportOpen,
                accountLabel = account.label,
                accountSupporting = account.supporting,
                isCloudAccount = account.isCloudAccount,
                canLogout = account.canLogout
            )
        }.catch { error ->
            if (error is CancellationException) throw error
            emit(accountOnlyUiState(
                loadError = LocalizedText(R.string.exercises_load_failed)
            ))
        }
    }.flowOn(Dispatchers.Default).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = accountOnlyUiState(isLoading = true)
    )

    init {
        viewModelScope.launch {
            repository.seedDefaultExerciseMuscleMappings()
        }
    }

    fun retryLoad() {
        loadGeneration.value += 1L
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

    fun requestDeleteExercise(exercise: ExerciseEntity) {
        if (isExerciseDeletionInProgress.value || pendingExerciseDeletion.value != null) return
        isExerciseDeletionInProgress.value = true
        exerciseDeletionError.value = null
        viewModelScope.launch {
            try {
                val snapshot = repository.getExerciseDeletionSnapshot(exercise.id)
                if (snapshot != null && snapshot.matchesRequestedExercise(exercise)) {
                    pendingExerciseDeletion.value = snapshot
                } else {
                    exerciseDeletionError.value = LocalizedText(R.string.message_delete_target_changed)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                exerciseDeletionError.value = LocalizedText(R.string.message_delete_failed)
            } finally {
                isExerciseDeletionInProgress.value = false
            }
        }
    }

    fun dismissExerciseDeletion() {
        if (isExerciseDeletionInProgress.value) return
        pendingExerciseDeletion.value = null
        exerciseDeletionError.value = null
    }

    fun confirmExerciseDeletion() {
        val expected = pendingExerciseDeletion.value ?: return
        if (isExerciseDeletionInProgress.value || exerciseDeletionError.value != null) return
        isExerciseDeletionInProgress.value = true
        viewModelScope.launch {
            try {
                if (repository.deleteExerciseIfUnchanged(expected)) {
                    pendingExerciseDeletion.value = null
                    exerciseDeletionError.value = null
                } else {
                    exerciseDeletionError.value = LocalizedText(R.string.message_delete_target_changed)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                exerciseDeletionError.value = LocalizedText(R.string.message_delete_failed)
            } finally {
                isExerciseDeletionInProgress.value = false
            }
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

    fun openExerciseLoadProfile(exercise: ExerciseEntity) {
        val current = uiState.value.loadProfiles[exercise.id]
        loadEditorExercise.value = exercise
        loadEditorDirection.value = current?.direction ?: defaultLoadDirection(exercise)
        loadEditorWeights.value = current?.allowedWeightsKg
            ?.joinToString(separator = "\n", transform = ::formatLoadWeight)
            .orEmpty()
        loadEditorHasError.value = false
    }

    fun closeExerciseLoadProfile() {
        loadEditorExercise.value = null
        loadEditorWeights.value = ""
        loadEditorHasError.value = false
    }

    fun updateExerciseLoadDirection(direction: ExerciseLoadDirection) {
        loadEditorDirection.value = direction
        loadEditorHasError.value = false
    }

    fun updateExerciseLoadWeights(value: String) {
        if (value.length > 2_048) {
            loadEditorHasError.value = true
            return
        }
        loadEditorWeights.value = value
        loadEditorHasError.value = false
    }

    fun applyExerciseLoadPreset(stepKg: Double) {
        if (stepKg != 2.5 && stepKg != 5.0) return
        val maximum = if (stepKg == 2.5) 200.0 else 300.0
        loadEditorWeights.value = generateSequence(stepKg) { previous ->
            (previous + stepKg).takeIf { it <= maximum }
        }.joinToString(separator = "\n", transform = ::formatLoadWeight)
        loadEditorHasError.value = false
    }

    fun saveExerciseLoadProfile() {
        val exercise = loadEditorExercise.value ?: return
        val weights = parseLoadWeights(loadEditorWeights.value)
        if (weights == null) {
            loadEditorHasError.value = true
            return
        }
        val profile = runCatching {
            ExerciseLoadProfile(loadEditorDirection.value, weights)
        }.getOrNull()
        if (profile == null) {
            loadEditorHasError.value = true
            return
        }
        viewModelScope.launch {
            runCatching { repository.saveExerciseLoadProfile(exercise.id, profile) }
                .onSuccess { closeExerciseLoadProfile() }
                .onFailure { loadEditorHasError.value = true }
        }
    }

    fun clearExerciseLoadProfile() {
        val exercise = loadEditorExercise.value ?: return
        viewModelScope.launch {
            runCatching { repository.saveExerciseLoadProfile(exercise.id, null) }
                .onSuccess { closeExerciseLoadProfile() }
                .onFailure { loadEditorHasError.value = true }
        }
    }

    private fun defaultLoadDirection(exercise: ExerciseEntity): ExerciseLoadDirection =
        if (BuiltInExerciseCatalog.inferKey(exercise.name) in setOf("assisted_pull_up", "assisted_dip")) {
            ExerciseLoadDirection.LowerIsHarder
        } else {
            ExerciseLoadDirection.HigherIsHarder
        }

    private fun parseLoadWeights(raw: String): List<Double>? {
        val tokens = raw
            .replace(Regex(",(?=\\s|$)"), " ")
            .split(Regex("[;\\s]+"))
            .filter { it.isNotBlank() }
            .flatMap { token ->
                if (token.count { it == ',' } > 1 || token.contains(',') && token.contains('.')) {
                    token.split(',').filter(String::isNotBlank)
                } else {
                    listOf(token)
                }
            }
        if (tokens.isEmpty() || tokens.size > ExerciseLoadProfile.MAX_WEIGHT_OPTIONS) return null
        val parsed = tokens.map { token ->
            token.replace(',', '.').toDoubleOrNull()?.takeIf(WorkoutDataLimits::isValidWeight)
                ?: return null
        }
        return parsed.distinct().sorted().takeIf {
            ExerciseLoadProfile.isValid(loadEditorDirection.value, it)
        }
    }

    private fun formatLoadWeight(weight: Double): String =
        if (weight % 1.0 == 0.0) weight.toLong().toString() else weight.toString()

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

    private fun activeAccountUiModel(): ExerciseAccountUiModel = exerciseAccountUiModel(
        session = authManager?.authState?.value?.session,
        canLogout = authManager != null
    )

    private fun accountOnlyUiState(
        isLoading: Boolean = false,
        loadError: LocalizedText? = null
    ): ExerciseListUiState {
        val account = activeAccountUiModel()
        return ExerciseListUiState(
            isLoading = isLoading,
            loadError = loadError,
            accountLabel = account.label,
            accountSupporting = account.supporting,
            isCloudAccount = account.isCloudAccount,
            canLogout = account.canLogout
        )
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
