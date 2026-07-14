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
import com.example.gymapp.wear.sync.WatchPendingWorkoutStorage
import com.example.gymapp.wear.sync.WatchPlanStorage
import com.example.gymapp.wear.sync.WatchSyncBindingStorage
import com.example.gymapp.wear.sync.WatchSyncBinding
import com.example.gymapp.wear.sync.WearSyncClient
import com.example.gymapp.wear.sync.WatchSyncJson
import com.example.gymapp.wear.sync.SyncedWorkoutPlanMeta
import com.example.gymapp.wear.sync.SyncPaths
import com.example.gymapp.wear.sync.WatchSyncParseResult
import com.example.gymapp.wear.util.parseWeightInputOrNull
import java.util.UUID
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
    val syncStatus: WearSyncStatus = WearSyncStatus.Idle,
    val workoutPlanMeta: SyncedWorkoutPlanMeta? = null
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
    private var draftBinding = currentBindingIdentity()
    private var draftInstanceId = UUID.randomUUID().toString()

    private var nextDraftSetId = 2L
    private val draftSets = MutableStateFlow(listOf(WearSetInputUiState(id = 1L)))
    private val selectedSessionId = MutableStateFlow<Long?>(null)
    private val isSaving = MutableStateFlow(false)
    private val message = MutableStateFlow<String?>(null)
    private val syncStatus = MutableStateFlow(WearSyncStatus.Idle)
    private val workoutPlanMeta = MutableStateFlow<SyncedWorkoutPlanMeta?>(null)

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
            sessions = sessions,
            workoutPlanMeta = workoutPlanMeta.value
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
            syncStatus = currentSyncStatus,
            workoutPlanMeta = editor.workoutPlanMeta
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WearWorkoutUiState(draftSets = listOf(WearSetInputUiState(id = 1L)))
    )

    init {
        restorePendingWorkoutDraft()
        applyPendingWorkoutPlanFromSync()
        viewModelScope.launch {
            WatchPlanStorage.observe(appContext).collect { rawPlan ->
                applyPendingWorkoutPlanFromSync(rawPlan)
            }
        }
        viewModelScope.launch {
            WatchSyncBindingStorage.observe(appContext).collect { binding ->
                val nextBinding = bindingIdentity(binding)
                if (nextBinding != draftBinding) {
                    draftBinding = nextBinding
                    resetAccountScopedEditor()
                }
            }
        }
        requestRemoteSync(showError = false)
    }

    fun addDraftSet() {
        if (isSaving.value || !ensureDraftBindingCurrent()) return
        if (draftSets.value.size >= SyncPaths.MAX_WORKOUT_SETS) {
            message.value = appContext.getString(R.string.message_invalid_draft)
            return
        }
        commitDraftEdit(draftSets.value + WearSetInputUiState(id = nextDraftSetId++))
    }

    fun duplicateLastDraftSet(weightDelta: Double = 0.0) {
        if (isSaving.value || !ensureDraftBindingCurrent()) return
        if (draftSets.value.size >= SyncPaths.MAX_WORKOUT_SETS) {
            message.value = appContext.getString(R.string.message_invalid_draft)
            return
        }
        val current = draftSets.value
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
        commitDraftEdit(
            current + lastSet.copy(
                id = nextDraftSetId++,
                weight = adjustedWeight
            )
        )
    }

    fun removeDraftSet(setId: Long) {
        if (isSaving.value || !ensureDraftBindingCurrent()) return
        val updated = draftSets.value.filterNot { it.id == setId }
        commitDraftEdit(
            if (updated.isEmpty()) listOf(WearSetInputUiState(id = nextDraftSetId++)) else updated
        )
    }

    fun updateDraftExercise(setId: Long, value: String) {
        if (isSaving.value || !ensureDraftBindingCurrent()) return
        commitDraftEdit(
            draftSets.value.map { set ->
                if (set.id == setId) {
                    set.copy(exerciseName = value.take(SyncPaths.MAX_EXERCISE_NAME_LENGTH))
                } else {
                    set
                }
            }
        )
    }

    fun updateDraftWeight(setId: Long, value: String) {
        if (isSaving.value || !ensureDraftBindingCurrent()) return
        commitDraftEdit(
            draftSets.value.map { set ->
                if (set.id == setId) set.copy(weight = value.take(32)) else set
            }
        )
    }

    fun updateDraftReps(setId: Long, value: String) {
        if (isSaving.value || !ensureDraftBindingCurrent()) return
        commitDraftEdit(
            draftSets.value.map { set ->
                if (set.id == setId) set.copy(reps = value.take(6)) else set
            }
        )
    }

    fun saveWorkout() {
        if (isSaving.value) return
        if (!ensureDraftBindingCurrent()) return
        val submittedDraft = draftSets.value
        val parsedSets = submittedDraft.mapNotNull(::parseDraftSet)
        if (parsedSets.size != submittedDraft.size || parsedSets.isEmpty()) {
            message.value = appContext.getString(R.string.message_invalid_draft)
            return
        }
        val submittedFullBinding = currentAccountBinding() ?: return
        val submittedBinding = bindingIdentity(submittedFullBinding)
        val submittedDraftId = draftInstanceId
        val submittedSourcePlan = lastAppliedWorkoutPlanRaw
        isSaving.value = true
        syncStatus.value = WearSyncStatus.WaitingPhone
        viewModelScope.launch {
            runCatching {
                syncClient.createWorkout(
                    binding = submittedFullBinding,
                    draftId = submittedDraftId,
                    startedAt = System.currentTimeMillis(),
                    note = null,
                    sets = parsedSets,
                    sourcePlanRaw = submittedSourcePlan
                )
            }.onSuccess { pendingMutation ->
                if (currentBindingIdentity() != submittedBinding || draftSets.value != submittedDraft) {
                    return@onSuccess
                }
                val storedPlan = WatchPlanStorage.load(appContext)
                val consumedStoredPlan = storedPlan != null && storedPlan == lastAppliedWorkoutPlanRaw
                draftSets.value = listOf(WearSetInputUiState(id = nextDraftSetId++))
                draftInstanceId = UUID.randomUUID().toString()
                selectedSessionId.value = null
                if (consumedStoredPlan) {
                    WatchPlanStorage.clear(appContext)
                    lastAppliedWorkoutPlanRaw = null
                    workoutPlanMeta.value = null
                } else {
                    applyPendingWorkoutPlanFromSync(storedPlan)
                }
                message.value = appContext.getString(R.string.message_workout_saved)
                syncStatus.value = WearSyncStatus.Sent
                // This is deliberately last: until the plan/editor transition is complete,
                // retain the stable operation id so a crash retry remains idempotent.
                WatchPendingWorkoutStorage.clearIfMatches(appContext, pendingMutation)
                requestRemoteSync(showError = false)
            }.onFailure {
                if (currentBindingIdentity() != submittedBinding) return@onFailure
                message.value = appContext.getString(R.string.message_sync_unavailable)
                syncStatus.value = WearSyncStatus.Failed
            }
            if (currentBindingIdentity() == submittedBinding) {
                isSaving.value = false
            }
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
        if (
            parsedWeight == null ||
            !parsedWeight.isFinite() ||
            parsedReps == null ||
            parsedWeight !in 0.0..SyncPaths.MAX_WEIGHT ||
            parsedReps !in 1..SyncPaths.MAX_REPS
        ) {
            message.value = appContext.getString(R.string.message_invalid_set_input)
            return
        }

        val submittedBinding = currentAccountBinding() ?: return
        val submittedIdentity = currentBindingIdentity()
        viewModelScope.launch {
            syncStatus.value = WearSyncStatus.WaitingPhone
            runCatching {
                syncClient.updateSet(
                    binding = submittedBinding,
                    setId = set.id,
                    weight = parsedWeight,
                    reps = parsedReps
                )
            }.onSuccess {
                if (currentBindingIdentity() != submittedIdentity) return@onSuccess
                syncStatus.value = WearSyncStatus.Sent
                requestRemoteSync(showError = false)
            }.onFailure {
                if (currentBindingIdentity() != submittedIdentity) return@onFailure
                message.value = appContext.getString(R.string.message_sync_unavailable)
                syncStatus.value = WearSyncStatus.Failed
            }
        }
    }

    fun deleteSet(setId: Long) {
        val submittedBinding = currentAccountBinding() ?: return
        val submittedIdentity = currentBindingIdentity()
        viewModelScope.launch {
            syncStatus.value = WearSyncStatus.WaitingPhone
            runCatching {
                syncClient.deleteSet(binding = submittedBinding, setId = setId)
            }.onSuccess {
                if (currentBindingIdentity() != submittedIdentity) return@onSuccess
                syncStatus.value = WearSyncStatus.Sent
                requestRemoteSync(showError = false)
            }.onFailure {
                if (currentBindingIdentity() != submittedIdentity) return@onFailure
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
        if (
            exerciseName.length > SyncPaths.MAX_EXERCISE_NAME_LENGTH ||
            !weight.isFinite() ||
            weight !in 0.0..SyncPaths.MAX_WEIGHT ||
            reps !in 1..SyncPaths.MAX_REPS
        ) {
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
            workoutPlanMeta.value = null
            return
        }
        if (rawPlan == lastAppliedWorkoutPlanRaw) {
            return
        }

        val parsed = WatchSyncJson.parseWorkoutPlanPayload(rawPlan)
        if (parsed !is WatchSyncParseResult.Valid) {
            WatchPlanStorage.clear(appContext)
            return
        }
        val payload = parsed.value

        val hasMeaningfulDraft = draftSets.value.size > 1 || draftSets.value.any { set ->
            set.exerciseName.isNotBlank() || set.weight.isNotBlank() || set.reps.isNotBlank()
        }
        if (hasMeaningfulDraft) {
            message.value = appContext.getString(R.string.message_plan_deferred)
            return
        }

        val mappedDrafts = payload.sets.map { draft ->
            WearSetInputUiState(
                id = nextDraftSetId++,
                exerciseName = draft.exerciseName,
                weight = formatWeight(draft.weight),
                reps = draft.reps.toString()
            )
        }
        WatchPendingWorkoutStorage.clear(appContext)
        draftInstanceId = UUID.randomUUID().toString()
        draftSets.value = mappedDrafts
        workoutPlanMeta.value = payload.meta
        lastAppliedWorkoutPlanRaw = rawPlan
    }

    private fun formatWeight(weight: Double): String {
        return if (weight % 1.0 == 0.0) {
            weight.toInt().toString()
        } else {
            String.format(java.util.Locale.US, "%.1f", weight)
        }
    }

    private fun commitDraftEdit(candidate: List<WearSetInputUiState>) {
        if (candidate == draftSets.value) return
        runCatching {
            WatchPendingWorkoutStorage.clear(appContext)
            draftInstanceId = UUID.randomUUID().toString()
            draftSets.value = candidate
        }.getOrElse {
            message.value = appContext.getString(R.string.message_sync_unavailable)
        }
    }

    private fun currentBindingIdentity(): DraftBindingIdentity {
        return bindingIdentity(WatchSyncBindingStorage.load(appContext))
    }

    private fun currentAccountBinding(): WatchSyncBinding? {
        val snapshot = WatchSyncBindingStorage.load(appContext) ?: return null
        val identity = bindingIdentity(snapshot)
        if (identity != draftBinding) {
            draftBinding = identity
            resetAccountScopedEditor()
            return null
        }
        return snapshot.takeIf {
            it.ownerId != null && it.accountGeneration in 1L..SyncPaths.MAX_PROTOCOL_COUNTER
        }
    }

    private fun bindingIdentity(binding: WatchSyncBinding?): DraftBindingIdentity =
        DraftBindingIdentity(
            sourceNodeId = binding?.sourceNodeId,
            ownerId = binding?.ownerId,
            accountGeneration = binding?.accountGeneration ?: 0L
        )

    private fun resetAccountScopedEditor() {
        runCatching { WatchPendingWorkoutStorage.clear(appContext) }
        draftInstanceId = UUID.randomUUID().toString()
        draftSets.value = listOf(WearSetInputUiState(id = nextDraftSetId++))
        selectedSessionId.value = null
        lastAppliedWorkoutPlanRaw = null
        workoutPlanMeta.value = null
        isSaving.value = false
        message.value = null
        syncStatus.value = WearSyncStatus.Idle
    }

    private fun ensureDraftBindingCurrent(): Boolean {
        val current = currentBindingIdentity()
        if (current == draftBinding) return true
        draftBinding = current
        resetAccountScopedEditor()
        return false
    }

    private fun restorePendingWorkoutDraft() {
        val pending = WatchPendingWorkoutStorage.load(
            context = appContext,
            binding = WatchSyncBindingStorage.load(appContext)
        ) ?: return
        draftInstanceId = pending.draftId
        draftSets.value = pending.sets.map { set ->
            WearSetInputUiState(
                id = nextDraftSetId++,
                exerciseName = set.exerciseName,
                weight = formatWeight(set.weight),
                reps = set.reps.toString()
            )
        }
        val storedPlan = WatchPlanStorage.load(appContext)
        if (pending.sourcePlanRaw != null && pending.sourcePlanRaw == storedPlan) {
            lastAppliedWorkoutPlanRaw = storedPlan
            val parsed = WatchSyncJson.parseWorkoutPlanPayload(storedPlan)
            if (parsed is WatchSyncParseResult.Valid) {
                workoutPlanMeta.value = parsed.value.meta
            }
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
    val sessions: List<WearWorkoutSessionUiModel>,
    val workoutPlanMeta: SyncedWorkoutPlanMeta?
)

private data class DraftBindingIdentity(
    val sourceNodeId: String?,
    val ownerId: String?,
    val accountGeneration: Long
)
