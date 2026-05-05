package com.example.gymapp.wear.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.wear.R
import com.example.gymapp.wear.WearGymApplication
import com.example.gymapp.wear.data.WearSetUiModel
import com.example.gymapp.wear.data.WearWorkoutRepository
import com.example.gymapp.wear.data.WearWorkoutSessionUiModel
import com.example.gymapp.wear.data.WearWorkoutSetDraft
import com.example.gymapp.wear.sync.WatchExerciseCatalogStorage
import com.example.gymapp.wear.sync.WatchPlanStorage
import com.example.gymapp.wear.sync.WearSyncClient
import com.example.gymapp.wear.sync.WatchSyncJson
import com.example.gymapp.wear.util.parseWeightInputOrNull
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class WearSetInputUiState(
    val id: Long,
    val exerciseName: String = "",
    val weight: String = "",
    val reps: String = ""
)

enum class WearSyncStatus {
    Idle,
    WaitingPhone,
    Sent,
    Failed
}

data class WearWorkoutUiState(
    val draftSets: List<WearSetInputUiState> = emptyList(),
    val availableExercises: List<String> = emptyList(),
    val sessions: List<WearWorkoutSessionUiModel> = emptyList(),
    val selectedSessionId: Long? = null,
    val isSaving: Boolean = false,
    val message: String? = null,
    val syncStatus: WearSyncStatus = WearSyncStatus.Idle
) {
    val selectedSession: WearWorkoutSessionUiModel?
        get() = sessions.firstOrNull { it.id == selectedSessionId }
}

class WearWorkoutViewModel(
    application: Application,
    private val repository: WearWorkoutRepository,
    private val syncClient: WearSyncClient
) : AndroidViewModel(application) {
    private val appContext = application.applicationContext
    private var lastAppliedWorkoutPlanRaw: String? = null

    private var nextDraftSetId = 2L
    private val draftSets = MutableStateFlow(listOf(WearSetInputUiState(id = 1L)))
    private val selectedSessionId = MutableStateFlow<Long?>(null)
    private val isSaving = MutableStateFlow(false)
    private val message = MutableStateFlow<String?>(null)
    private val syncStatus = MutableStateFlow(WearSyncStatus.Idle)

    private val editorState = combine(
        draftSets,
        repository.observeWorkoutSessions(),
        WatchExerciseCatalogStorage.observe(appContext)
    ) { setInputs, sessions, syncedCatalog ->
        val catalogExercises = syncedCatalog
            .map { it.trim() }
            .filter { it.isNotBlank() }

        val historicalExercises = sessions
            .flatMap { session -> session.sets }
            .map { set -> set.exerciseName.trim() }
            .filter { it.isNotBlank() }
            .groupingBy { it }
            .eachCount()
            .entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { it.key }

        val draftOnlyExercises = setInputs
            .map { it.exerciseName.trim() }
            .filter { it.isNotBlank() && it !in historicalExercises }

        val allExercises = buildList {
            addAll(catalogExercises)
            addAll(historicalExercises.filterNot { it in catalogExercises })
            addAll(draftOnlyExercises.filterNot { it in catalogExercises || it in historicalExercises })
        }.distinctBy { it.lowercase() }

        EditorState(
            draftSets = setInputs,
            availableExercises = allExercises,
            sessions = sessions
        )
    }

    val uiState: StateFlow<WearWorkoutUiState> = combine(
        editorState,
        selectedSessionId,
        isSaving,
        message,
        syncStatus
    ) { editor, selectedId, saving, currentMessage, currentSyncStatus ->
        WearWorkoutUiState(
            draftSets = editor.draftSets,
            availableExercises = editor.availableExercises,
            sessions = editor.sessions,
            selectedSessionId = selectedId,
            isSaving = saving,
            message = currentMessage,
            syncStatus = currentSyncStatus
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WearWorkoutUiState(draftSets = listOf(WearSetInputUiState(id = 1L)))
    )

    init {
        applyPendingWorkoutPlanFromSync()
        viewModelScope.launch {
            WatchPlanStorage.observe(appContext).collect { rawPlan ->
                applyPendingWorkoutPlanFromSync(rawPlan)
            }
        }
        requestRemoteSync(showError = false)
    }

    fun addDraftSet() {
        draftSets.update { current ->
            current + WearSetInputUiState(id = nextDraftSetId++)
        }
    }

    fun duplicateLastDraftSet(weightDelta: Double = 0.0) {
        draftSets.update { current ->
            val lastSet = current.lastOrNull() ?: WearSetInputUiState(id = nextDraftSetId++)
            val adjustedWeight = when {
                lastSet.weight.isBlank() -> ""
                weightDelta == 0.0 -> lastSet.weight
                else -> {
                    val parsed = parseWeightInputOrNull(lastSet.weight)
                    if (parsed == null) {
                        lastSet.weight
                    } else {
                        formatWeight((parsed + weightDelta).coerceAtLeast(0.0))
                    }
                }
            }
            current + lastSet.copy(
                id = nextDraftSetId++,
                weight = adjustedWeight
            )
        }
    }

    fun removeDraftSet(setId: Long) {
        draftSets.update { current ->
            val updated = current.filterNot { it.id == setId }
            if (updated.isEmpty()) listOf(WearSetInputUiState(id = nextDraftSetId++)) else updated
        }
    }

    fun updateDraftExercise(setId: Long, value: String) {
        draftSets.update { current ->
            current.map { set ->
                if (set.id == setId) set.copy(exerciseName = value) else set
            }
        }
    }

    fun updateDraftWeight(setId: Long, value: String) {
        draftSets.update { current ->
            current.map { set ->
                if (set.id == setId) set.copy(weight = value) else set
            }
        }
    }

    fun updateDraftReps(setId: Long, value: String) {
        draftSets.update { current ->
            current.map { set ->
                if (set.id == setId) set.copy(reps = value) else set
            }
        }
    }

    fun saveWorkout() {
        viewModelScope.launch {
            val parsedSets = draftSets.value.mapNotNull(::parseDraftSet)
            if (parsedSets.size != draftSets.value.size || parsedSets.isEmpty()) {
                message.value = appContext.getString(R.string.message_invalid_draft)
                return@launch
            }

            isSaving.value = true
            syncStatus.value = WearSyncStatus.WaitingPhone
            runCatching {
                syncClient.createWorkout(
                    startedAt = System.currentTimeMillis(),
                    note = null,
                    sets = parsedSets
                )
            }.onSuccess {
                draftSets.value = listOf(WearSetInputUiState(id = nextDraftSetId++))
                selectedSessionId.value = null
                WatchPlanStorage.clear(appContext)
                message.value = appContext.getString(R.string.message_workout_saved)
                syncStatus.value = WearSyncStatus.Sent
                requestRemoteSync(showError = false)
            }.onFailure {
                message.value = appContext.getString(R.string.message_sync_unavailable)
                syncStatus.value = WearSyncStatus.Failed
            }
            isSaving.value = false
        }
    }

    fun selectSession(sessionId: Long?) {
        selectedSessionId.value = sessionId
    }

    fun updateExistingSet(
        set: WearSetUiModel,
        updatedWeight: String,
        updatedReps: String
    ) {
        val parsedWeight = parseWeightInputOrNull(updatedWeight)
        val parsedReps = updatedReps.trim().toIntOrNull()
        if (parsedWeight == null || parsedReps == null || parsedWeight < 0.0 || parsedReps <= 0) {
            message.value = appContext.getString(R.string.message_invalid_set_input)
            return
        }

        viewModelScope.launch {
            syncStatus.value = WearSyncStatus.WaitingPhone
            runCatching {
                syncClient.updateSet(
                    setId = set.id,
                    weight = parsedWeight,
                    reps = parsedReps
                )
            }.onSuccess {
                syncStatus.value = WearSyncStatus.Sent
                requestRemoteSync(showError = false)
            }.onFailure {
                message.value = appContext.getString(R.string.message_sync_unavailable)
                syncStatus.value = WearSyncStatus.Failed
            }
        }
    }

    fun deleteSet(setId: Long) {
        viewModelScope.launch {
            syncStatus.value = WearSyncStatus.WaitingPhone
            runCatching {
                syncClient.deleteSet(setId)
            }.onSuccess {
                syncStatus.value = WearSyncStatus.Sent
                requestRemoteSync(showError = false)
            }.onFailure {
                message.value = appContext.getString(R.string.message_sync_unavailable)
                syncStatus.value = WearSyncStatus.Failed
            }
        }
    }

    fun consumeMessage() {
        message.value = null
    }

    fun requestRemoteSync(showError: Boolean = true) {
        viewModelScope.launch {
            syncStatus.value = WearSyncStatus.WaitingPhone
            runCatching {
                syncClient.requestFullSync()
            }.onSuccess {
                syncStatus.value = WearSyncStatus.Sent
            }.onFailure {
                syncStatus.value = WearSyncStatus.Failed
                if (showError) {
                    message.value = appContext.getString(R.string.message_sync_unavailable)
                }
            }
        }
    }

    private fun parseDraftSet(input: WearSetInputUiState): WearWorkoutSetDraft? {
        val exerciseName = input.exerciseName.trim()
        if (exerciseName.isBlank()) {
            return null
        }

        val weight = parseWeightInputOrNull(input.weight) ?: return null
        val reps = input.reps.trim().toIntOrNull() ?: return null
        if (weight < 0.0 || reps <= 0) {
            return null
        }

        return WearWorkoutSetDraft(
            exerciseName = exerciseName,
            weight = weight,
            reps = reps
        )
    }

    private fun applyPendingWorkoutPlanFromSync() {
        applyPendingWorkoutPlanFromSync(WatchPlanStorage.load(appContext))
    }

    private fun applyPendingWorkoutPlanFromSync(rawPlan: String?) {
        if (rawPlan == null) {
            lastAppliedWorkoutPlanRaw = null
            return
        }
        if (rawPlan == lastAppliedWorkoutPlanRaw) {
            return
        }

        val parsedSets = WatchSyncJson.parseWorkoutPlanPayload(rawPlan)
        if (parsedSets.isEmpty()) {
            return
        }

        val mappedDrafts = parsedSets.map { draft ->
            WearSetInputUiState(
                id = nextDraftSetId++,
                exerciseName = draft.exerciseName,
                weight = formatWeight(draft.weight),
                reps = draft.reps.toString()
            )
        }
        draftSets.value = mappedDrafts
        lastAppliedWorkoutPlanRaw = rawPlan
    }

    private fun formatWeight(weight: Double): String {
        return if (weight % 1.0 == 0.0) {
            weight.toInt().toString()
        } else {
            String.format(java.util.Locale.US, "%.1f", weight)
        }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val app = application as WearGymApplication
                WearWorkoutViewModel(
                    application = application,
                    repository = app.repository,
                    syncClient = WearSyncClient(application)
                )
            }
        }
    }
}

private data class EditorState(
    val draftSets: List<WearSetInputUiState>,
    val availableExercises: List<String>,
    val sessions: List<WearWorkoutSessionUiModel>
)
