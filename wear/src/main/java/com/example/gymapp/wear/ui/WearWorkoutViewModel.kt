package com.example.gymapp.wear.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.wear.R
import com.example.gymapp.wear.WearGymApplication
import com.example.gymapp.wear.data.WearWorkoutRepository
import com.example.gymapp.wear.data.WearWorkoutSetDraft
import com.example.gymapp.wear.health.RestTimerLogic
import com.example.gymapp.wear.health.RestWakeLock
import com.example.gymapp.wear.health.WearExerciseTracker
import com.example.gymapp.wear.health.WearHealthPermissions
import com.example.gymapp.wear.health.WearHealthState
import com.example.gymapp.wear.health.WearHaptics
import com.example.gymapp.wear.sync.FinishedWorkoutSnapshot
import com.example.gymapp.wear.sync.WatchExerciseCatalogStorage
import com.example.gymapp.wear.sync.WatchPendingWorkoutStorage
import com.example.gymapp.wear.sync.WatchPlanStorage
import com.example.gymapp.wear.sync.WatchSyncBindingStorage
import com.example.gymapp.wear.sync.WatchSettingsStorage
import com.example.gymapp.wear.sync.WatchSyncBinding
import com.example.gymapp.wear.sync.WearSyncClient
import com.example.gymapp.wear.sync.WatchSyncJson
import com.example.gymapp.wear.sync.SyncedWorkoutPlanMeta
import com.example.gymapp.wear.sync.SyncPaths
import com.example.gymapp.wear.sync.WatchSyncParseResult
import com.example.gymapp.wear.sync.WatchWorkoutDraft
import com.example.gymapp.wear.sync.WatchWorkoutDraftStorage
import com.example.gymapp.wear.util.parseWeightInputOrNull
import android.os.SystemClock
import java.util.UUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
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

/** Outcome of Summary → Save, shown on the result screen. */
enum class SaveOutcome {
    Sending,
    Saved,
    Deferred
}

enum class WearSyncStatus {
    Idle,
    WaitingPhone,
    Sent,
    Failed
}

data class WearWorkoutUiState(
    /** Logged sets only (plan rows are read-only [planTargets], phone rule). */
    val draftSets: List<WearSetInputUiState> = emptyList(),
    val availableExercises: List<String> = emptyList(),
    /** Read-only plan targets from the phone; empty without a plan. */
    val planTargets: List<WearWorkoutSetDraft> = emptyList(),
    /** True when the running workout follows the plan (false = free workout). */
    val usingPlan: Boolean = false,
    val selectedExercise: String? = null,
    val paused: Boolean = false,
    /** Id of the set that can still be undone (5 s window), null otherwise. */
    val undoSetId: Long? = null,
    val weightStepKg: Double = WorkoutMath.DEFAULT_WEIGHT_STEP_KG,
    val saveOutcome: SaveOutcome? = null,
    /** A finished workout is stored and waiting for the phone. */
    val hasQueuedWorkout: Boolean = false,
    /** The watch is linked to a signed-in phone account. */
    val isLinked: Boolean = false,
    val isSaving: Boolean = false,
    val message: String? = null,
    val syncStatus: WearSyncStatus = WearSyncStatus.Idle,
    val workoutPlanMeta: SyncedWorkoutPlanMeta? = null,
    /** Seconds since the workout started (first edit / explicit start); 0 before it starts. */
    val elapsedSeconds: Long = 0L,
    /** True from the workout's start until it is saved or discarded. */
    val workoutActive: Boolean = false,
    /** Rest countdown; 0 when no rest is running. */
    val restRemainingSeconds: Int = 0,
    /** Default rest length (the setting) used when a set is completed. */
    val restDefaultSeconds: Int = RestTimerLogic.DEFAULT_REST_SECONDS,
    /** Live heart rate / average / max / kcal and whether tracking is available. */
    val health: WearHealthState = WearHealthState()
) {
    val loggedSets: List<WearWorkoutSetDraft>
        get() = draftSets.mapNotNull { it.toDraftOrNull() }

    /** Plan targets the running workout follows (none in a free workout). */
    val activePlanTargets: List<WearWorkoutSetDraft>
        get() = if (usingPlan) planTargets else emptyList()

    val currentExercise: String?
        get() = WorkoutMath.currentExercise(selectedExercise, activePlanTargets, loggedSets)

    val setProgress: SetProgress
        get() = WorkoutMath.setProgress(currentExercise, activePlanTargets, loggedSets)

    val nextTarget: SetTarget?
        get() = WorkoutMath.nextTarget(currentExercise, activePlanTargets, loggedSets)

    val heartRateZone: Int?
        get() = WorkoutMath.heartRateZone(health.heartRate)

    val summary: WorkoutSummaryNumbers
        get() = WorkoutMath.summary(
            durationSeconds = elapsedSeconds,
            loggedSets = loggedSets,
            averageHeartRate = health.averageHeartRate,
            maxHeartRate = health.maxHeartRate,
            caloriesKcal = health.caloriesKcal
        )
}

internal fun WearSetInputUiState.toDraftOrNull(): WearWorkoutSetDraft? {
    val name = exerciseName.trim()
    if (name.isBlank()) return null
    val parsedWeight = parseWeightInputOrNull(weight) ?: return null
    val parsedReps = reps.trim().toIntOrNull() ?: return null
    return WearWorkoutSetDraft(name, parsedWeight, parsedReps)
}

private data class SessionExtras(
    val planTargets: List<WearWorkoutSetDraft> = emptyList(),
    val usingPlan: Boolean = false,
    val selectedExercise: String? = null,
    val paused: Boolean = false,
    val undoSetId: Long? = null,
    val weightStepKg: Double = WorkoutMath.DEFAULT_WEIGHT_STEP_KG,
    val saveOutcome: SaveOutcome? = null,
    val hasQueuedWorkout: Boolean = false,
    val isLinked: Boolean = false
)

class WearWorkoutViewModel(
    application: Application,
    private val repository: WearWorkoutRepository,
    private val syncClient: WearSyncClient,
    private val exerciseTracker: WearExerciseTracker,
    private val nowElapsedMs: () -> Long = { SystemClock.elapsedRealtime() }
) : AndroidViewModel(application) {
    private val appContext = application.applicationContext
    private var lastAppliedWorkoutPlanRaw: String? = null
    private var draftBinding = currentBindingIdentity()
    private var draftInstanceId = UUID.randomUUID().toString()

    /** Start time and pauses of the workout; null before it starts. Persisted with the draft. */
    private var clock: WorkoutClock? = null

    /**
     * Duration and heart rate frozen at the first Save. Retries send exactly these values: the
     * clock and the heart-rate tracker are stopped by then and must not be read again.
     */
    private var finishedSnapshot: FinishedWorkoutSnapshot? = null
    private var pausedRestRemainingSeconds = 0

    private var nextDraftSetId = 1L
    private val draftSets = MutableStateFlow<List<WearSetInputUiState>>(emptyList())
    private val isSaving = MutableStateFlow(false)
    private val message = MutableStateFlow<String?>(null)
    private val syncStatus = MutableStateFlow(WearSyncStatus.Idle)
    private val workoutPlanMeta = MutableStateFlow<SyncedWorkoutPlanMeta?>(null)
    private val extras = MutableStateFlow(
        SessionExtras(
            weightStepKg = WorkoutMath.normalizeWeightStep(WearUiSettings.weightStepKg(application)),
            isLinked = WatchSyncBindingStorage.load(application)?.ownerId != null
        )
    )

    // Live workout state: elapsed time, rest timer, health.
    private val restTimer = RestTimerLogic()
    private val restWakeLock by lazy { RestWakeLock(appContext) }
    private val undoWindow = UndoWindow()
    private val restDefaultSeconds = MutableStateFlow(WatchSettingsStorage.restSeconds(application))
    private val restRemainingSeconds = MutableStateFlow(0)
    private val elapsedSeconds = MutableStateFlow(0L)
    private val workoutActive = MutableStateFlow(false)
    private var tickerJob: Job? = null
    private var healthTrackingRequested = false
    private val _healthPermissionRequest = MutableStateFlow<List<String>?>(null)

    /**
     * Permissions the Activity should ask the user for right now (null when none). The Activity
     * launches the system dialog and reports back through [onHealthPermissionsResult].
     */
    val healthPermissionRequest: StateFlow<List<String>?> = _healthPermissionRequest

    private val editorState = combine(
        draftSets,
        repository.observeWorkoutSessions(),
        WatchExerciseCatalogStorage.observe(appContext),
        workoutPlanMeta
    ) { setInputs, sessions, syncedCatalog, planMeta ->
        val catalogExercises = syncedCatalog
            .map { it.trim() }
            .filter { it.isNotBlank() }
        // History from the phone is still stored (sync keeps working) but only its exercise names
        // are used, to fill the picker when the catalog is short.
        val historicalExercises = sessions
            .flatMap { session -> session.sets }
            .map { set -> set.exerciseName.trim() }
            .filter { it.isNotBlank() }
        val draftExercises = setInputs.map { it.exerciseName.trim() }.filter { it.isNotBlank() }
        val allExercises = (catalogExercises + historicalExercises + draftExercises)
            .distinctBy { it.lowercase() }

        EditorState(
            draftSets = setInputs,
            availableExercises = allExercises,
            workoutPlanMeta = planMeta
        )
    }

    private val liveState = combine(
        combine(elapsedSeconds, workoutActive, restRemainingSeconds, restDefaultSeconds) {
            elapsed, active, restRemaining, restDefault ->
            LiveState(elapsed, active, restRemaining, restDefault, WearHealthState())
        },
        exerciseTracker.state
    ) { live, health -> live.copy(health = health) }

    val uiState: StateFlow<WearWorkoutUiState> = combine(
        editorState,
        extras,
        isSaving,
        message,
        syncStatus
    ) { editor, extra, saving, currentMessage, currentSyncStatus ->
        WearWorkoutUiState(
            draftSets = editor.draftSets,
            availableExercises = editor.availableExercises,
            planTargets = extra.planTargets,
            usingPlan = extra.usingPlan,
            selectedExercise = extra.selectedExercise,
            paused = extra.paused,
            undoSetId = extra.undoSetId,
            weightStepKg = extra.weightStepKg,
            saveOutcome = extra.saveOutcome,
            hasQueuedWorkout = extra.hasQueuedWorkout,
            isLinked = extra.isLinked,
            isSaving = saving,
            message = currentMessage,
            syncStatus = currentSyncStatus,
            workoutPlanMeta = editor.workoutPlanMeta
        )
    }.combine(liveState) { ui, live ->
        ui.copy(
            elapsedSeconds = live.elapsedSeconds,
            workoutActive = live.workoutActive,
            restRemainingSeconds = live.restRemainingSeconds,
            restDefaultSeconds = live.restDefaultSeconds,
            health = live.health
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WearWorkoutUiState(
            weightStepKg = extras.value.weightStepKg,
            isLinked = extras.value.isLinked
        )
    )

    init {
        restoreWorkout()
        applyPendingWorkoutPlanFromSync()
        viewModelScope.launch {
            WatchPlanStorage.observe(appContext).collect { rawPlan ->
                applyPendingWorkoutPlanFromSync(rawPlan)
            }
        }
        viewModelScope.launch {
            WatchSyncBindingStorage.observe(appContext).collect { binding ->
                extras.update { it.copy(isLinked = binding?.ownerId != null) }
                val nextBinding = bindingIdentity(binding)
                if (nextBinding != draftBinding) {
                    draftBinding = nextBinding
                    resetAccountScopedEditor()
                }
            }
        }
        requestRemoteSync(showError = false)
        // A workout that could not be sent earlier is retried as soon as the app opens.
        if (extras.value.hasQueuedWorkout && extras.value.isLinked) saveWorkout()
    }

    /** Start plan (usePlan = true, needs plan targets) or Free workout. Clock + HR start now. */
    fun startWorkout(usePlan: Boolean = extras.value.planTargets.isNotEmpty()) {
        if (isSaving.value || !ensureDraftBindingCurrent()) return
        if (extras.value.hasQueuedWorkout) return
        extras.update {
            it.copy(
                usingPlan = usePlan && it.planTargets.isNotEmpty(),
                selectedExercise = null,
                paused = false,
                saveOutcome = null
            )
        }
        markWorkoutStarted()
        persistDraft(durable = true)
    }

    fun selectExercise(name: String) {
        val trimmed = name.trim().take(SyncPaths.MAX_EXERCISE_NAME_LENGTH)
        if (trimmed.isBlank()) return
        extras.update { it.copy(selectedExercise = trimmed) }
        persistDraft(durable = false)
    }

    /**
     * Logs one set, starts the rest countdown and opens the 5 s undo window. Returns false when
     * the values are out of range or the set limit is reached.
     */
    fun logSet(exerciseName: String, weight: Double, reps: Int): Boolean {
        if (isSaving.value || !ensureDraftBindingCurrent()) return false
        // A finished workout waiting for the phone is immutable: changing it would give it a new
        // operation id and could store it twice.
        if (extras.value.hasQueuedWorkout) return false
        val name = exerciseName.trim()
        if (
            name.isBlank() ||
            name.length > SyncPaths.MAX_EXERCISE_NAME_LENGTH ||
            !weight.isFinite() ||
            weight !in 0.0..SyncPaths.MAX_WEIGHT ||
            reps !in 1..SyncPaths.MAX_REPS
        ) {
            message.value = appContext.getString(R.string.message_invalid_set_input)
            return false
        }
        if (draftSets.value.size >= SyncPaths.MAX_WORKOUT_SETS) {
            message.value = appContext.getString(R.string.message_invalid_set_input)
            return false
        }
        val set = WearSetInputUiState(
            id = nextDraftSetId++,
            exerciseName = name,
            weight = formatWeight(weight),
            reps = reps.toString()
        )
        if (!commitDraftEdit(draftSets.value + set)) return false
        extras.update { it.copy(selectedExercise = name) }
        persistDraft(durable = true)
        startRest()
        undoWindow.open(set.id, nowElapsedMs())
        extras.update { it.copy(undoSetId = set.id) }
        return true
    }

    /** Removes the set saved less than 5 s ago and cancels its rest timer. */
    fun undoLastSet(): Boolean {
        val setId = undoWindow.consume(nowElapsedMs())
        extras.update { it.copy(undoSetId = null) }
        if (setId == null || extras.value.hasQueuedWorkout) return false
        commitDraftEdit(draftSets.value.filterNot { it.id == setId })
        persistDraft(durable = true)
        skipRest()
        return true
    }

    /** Any other tap during the undo window ends it. */
    fun endUndoWindow() {
        undoWindow.close()
        extras.update { it.copy(undoSetId = null) }
    }

    /** Pause menu: freezes the elapsed clock and the rest timer; HR keeps recording. */
    fun pauseWorkout() {
        val running = clock ?: return
        if (!workoutActive.value || running.isPaused) return
        endUndoWindow()
        clock = running.pause(System.currentTimeMillis())
        pausedRestRemainingSeconds =
            if (restTimer.isRunning) restTimer.remainingSeconds(nowElapsedMs()) else 0
        restTimer.skip()
        restWakeLock.release()
        restRemainingSeconds.value = pausedRestRemainingSeconds
        elapsedSeconds.value = activeElapsedSeconds()
        extras.update { it.copy(paused = true) }
        persistDraft(durable = false)
    }

    fun resumeWorkout() {
        val paused = clock ?: return
        if (!workoutActive.value || !paused.isPaused) return
        clock = paused.resume(System.currentTimeMillis())
        if (pausedRestRemainingSeconds > 0) {
            restTimer.start(nowElapsedMs(), pausedRestRemainingSeconds)
            restWakeLock.hold(pausedRestRemainingSeconds)
        }
        pausedRestRemainingSeconds = 0
        extras.update { it.copy(paused = false) }
        persistDraft(durable = false)
        ensureTicker()
    }

    fun cycleWeightStep() {
        val next = WorkoutMath.nextWeightStep(extras.value.weightStepKg)
        runCatching { WearUiSettings.setWeightStepKg(appContext, next) }
        extras.update { it.copy(weightStepKg = next) }
    }

    /**
     * Drops the unsent workout entirely (running or queued): clears sets, the rest timer and
     * stops heart-rate tracking. The UI always asks for confirmation first.
     */
    fun discardWorkout() {
        if (isSaving.value) return
        runCatching { WatchPendingWorkoutStorage.clear(appContext) }
        runCatching { WatchWorkoutDraftStorage.clear(appContext) }
        draftInstanceId = UUID.randomUUID().toString()
        endWorkoutLiveState()
        draftSets.value = emptyList()
        extras.update {
            it.copy(selectedExercise = null, usingPlan = false, hasQueuedWorkout = false, saveOutcome = null)
        }
    }

    /** Starts (or restarts) the rest countdown with the default length. */
    fun startRest() {
        restTimer.start(nowElapsedMs(), restDefaultSeconds.value)
        restRemainingSeconds.value = restTimer.remainingSeconds(nowElapsedMs())
        restWakeLock.hold(restRemainingSeconds.value)
        ensureTicker()
    }

    fun addRestSeconds(seconds: Int = RestTimerLogic.REST_STEP_SECONDS) {
        if (!restTimer.isRunning) return
        restTimer.addSeconds(nowElapsedMs(), seconds)
        restRemainingSeconds.value = restTimer.remainingSeconds(nowElapsedMs())
        restWakeLock.hold(restRemainingSeconds.value)
    }

    fun skipRest() {
        restTimer.skip()
        restWakeLock.release()
        restRemainingSeconds.value = 0
    }

    fun setRestDefaultSeconds(seconds: Int) {
        val clamped = seconds.coerceIn(RestTimerLogic.MIN_REST_SECONDS, RestTimerLogic.MAX_REST_SECONDS)
        runCatching { WatchSettingsStorage.setRestSeconds(appContext, clamped) }
        restDefaultSeconds.value = clamped
    }

    /** The Activity took the request and is showing the system dialog: do not hand it out twice. */
    fun onHealthPermissionRequestLaunched() {
        _healthPermissionRequest.value = null
    }

    /** The Activity reports that the permission dialog was answered (granted or not). */
    fun onHealthPermissionsResult() {
        _healthPermissionRequest.value = null
        if (!healthTrackingRequested) return
        if (WearHealthPermissions.hasHeartRate(appContext)) {
            exerciseTracker.start()
        } else {
            exerciseTracker.reportPermissionDenied()
        }
    }

    /** Result screen closed: forget the outcome (a deferred workout stays queued). */
    fun acknowledgeSaveOutcome() {
        extras.update { it.copy(saveOutcome = null) }
    }

    /** Re-sends a queued workout (Start screen, state D). */
    fun retryQueuedWorkout() {
        if (!extras.value.hasQueuedWorkout || isSaving.value) return
        saveWorkout()
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
        val submittedFullBinding = currentAccountBinding()
        // currentAccountBinding() resets the editor when the account changed under us.
        if (draftSets.value != submittedDraft) return
        val savedAt = System.currentTimeMillis()
        val workoutStartedAt = (clock?.startedAt ?: savedAt).coerceAtMost(savedAt)
        // Frozen once, at the first Save: a retry (seconds or days later, after a restart) must
        // send the same duration and heart rate, not a clock that kept running.
        val snapshot = finishedSnapshot ?: exerciseTracker.snapshot().let { heartRate ->
            FinishedWorkoutSnapshot(
                durationSeconds = activeElapsedSeconds(savedAt),
                averageHeartRate = heartRate?.average,
                maxHeartRate = heartRate?.max
            )
        }.also { finishedSnapshot = it }
        if (clock == null) clock = WorkoutClock(startedAt = workoutStartedAt)
        // On disk as "finished" before anything is sent, so no outcome below can lose it.
        persistDraft(durable = true)
        if (submittedFullBinding == null) {
            // Not linked to an account right now: keep the workout queued, like a failed send.
            stopLiveTracking()
            extras.update { it.copy(hasQueuedWorkout = true, paused = false, saveOutcome = SaveOutcome.Deferred) }
            syncStatus.value = WearSyncStatus.Failed
            return
        }
        val submittedBinding = bindingIdentity(submittedFullBinding)
        val submittedDraftId = draftInstanceId
        // A stored operation for this draft is resent as it is, plan reference included: a plan
        // that changed in the meantime must not turn the retry into a new operation id (the
        // phone may already have stored the first one and only its ACK got lost).
        val storedOperation = runCatching {
            WatchPendingWorkoutStorage.load(appContext, submittedFullBinding)
        }.getOrNull()?.takeIf { it.draftId == submittedDraftId }
        val submittedSourcePlan = if (storedOperation != null) {
            storedOperation.sourcePlanRaw
        } else {
            lastAppliedWorkoutPlanRaw.takeIf { extras.value.usingPlan }
        }
        isSaving.value = true
        syncStatus.value = WearSyncStatus.WaitingPhone
        extras.update { it.copy(saveOutcome = SaveOutcome.Sending) }
        viewModelScope.launch {
            runCatching {
                syncClient.createWorkout(
                    binding = submittedFullBinding,
                    draftId = submittedDraftId,
                    startedAt = workoutStartedAt,
                    note = null,
                    sets = parsedSets,
                    sourcePlanRaw = submittedSourcePlan,
                    durationSeconds = snapshot.durationSeconds,
                    averageHeartRate = snapshot.averageHeartRate,
                    maxHeartRate = snapshot.maxHeartRate
                )
            }.onSuccess { pendingMutation ->
                if (currentBindingIdentity() != submittedBinding || draftSets.value != submittedDraft) {
                    return@onSuccess
                }
                val storedPlan = WatchPlanStorage.load(appContext)
                val consumedStoredPlan = submittedSourcePlan != null && storedPlan == submittedSourcePlan
                draftSets.value = emptyList()
                draftInstanceId = UUID.randomUUID().toString()
                endWorkoutLiveState()
                extras.update {
                    it.copy(
                        selectedExercise = null,
                        usingPlan = false,
                        hasQueuedWorkout = false,
                        saveOutcome = SaveOutcome.Saved
                    )
                }
                if (consumedStoredPlan) {
                    WatchPlanStorage.clear(appContext)
                    lastAppliedWorkoutPlanRaw = null
                    workoutPlanMeta.value = null
                    extras.update { it.copy(planTargets = emptyList()) }
                } else {
                    lastAppliedWorkoutPlanRaw = null
                    applyPendingWorkoutPlanFromSync(storedPlan)
                }
                syncStatus.value = WearSyncStatus.Sent
                // The draft goes first and the operation id last: a crash in between restores
                // the workout from the stored operation and resends it under the same id, which
                // the phone recognises. The other order could resend it under a new id.
                runCatching { WatchWorkoutDraftStorage.clear(appContext) }
                // This is deliberately last: until the plan/editor transition is complete,
                // retain the stable operation id so a crash retry remains idempotent.
                WatchPendingWorkoutStorage.clearIfMatches(appContext, pendingMutation)
                requestRemoteSync(showError = false)
            }.onFailure {
                if (currentBindingIdentity() != submittedBinding) return@onFailure
                // The workout is finished: stop the clock and HR, keep the sets queued for retry.
                stopLiveTracking()
                extras.update { it.copy(hasQueuedWorkout = true, paused = false, saveOutcome = SaveOutcome.Deferred) }
                syncStatus.value = WearSyncStatus.Failed
            }
            if (currentBindingIdentity() == submittedBinding) {
                isSaving.value = false
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
        val draft = input.toDraftOrNull() ?: return null
        if (
            draft.exerciseName.length > SyncPaths.MAX_EXERCISE_NAME_LENGTH ||
            !draft.weight.isFinite() ||
            draft.weight !in 0.0..SyncPaths.MAX_WEIGHT ||
            draft.reps !in 1..SyncPaths.MAX_REPS
        ) {
            return null
        }
        return draft
    }

    private fun applyPendingWorkoutPlanFromSync() {
        applyPendingWorkoutPlanFromSync(WatchPlanStorage.load(appContext))
    }

    private fun applyPendingWorkoutPlanFromSync(rawPlan: String?) {
        if (rawPlan == null) {
            // Keep the targets of a running plan workout; otherwise forget the plan.
            if (workoutActive.value && extras.value.usingPlan) return
            lastAppliedWorkoutPlanRaw = null
            workoutPlanMeta.value = null
            extras.update { it.copy(planTargets = emptyList()) }
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
        // A running workout or a queued one keeps its plan; the new one applies after it.
        if (workoutActive.value || draftSets.value.isNotEmpty()) {
            message.value = appContext.getString(R.string.message_plan_deferred)
            return
        }
        val payload = parsed.value
        lastAppliedWorkoutPlanRaw = rawPlan
        workoutPlanMeta.value = payload.meta
        extras.update { it.copy(planTargets = payload.sets) }
    }

    /** Idempotent: records the real start time once and kicks off the clock and health tracking. */
    private fun markWorkoutStarted() {
        if (clock == null) clock = WorkoutClock(startedAt = System.currentTimeMillis())
        workoutActive.value = true
        ensureTicker()
        ensureHealthTracking()
    }

    private fun ensureHealthTracking() {
        if (healthTrackingRequested) return
        healthTrackingRequested = true
        val missing = WearHealthPermissions.missing(appContext)
        if (missing.isEmpty()) {
            exerciseTracker.start()
        } else {
            // Ask once per workout; a denial leaves the workout fully usable without heart rate.
            _healthPermissionRequest.value = missing
        }
    }

    private fun activeElapsedSeconds(now: Long = System.currentTimeMillis()): Long {
        return clock?.elapsedSeconds(now) ?: 0L
    }

    /**
     * Writes the workout to disk. Called after every change that would otherwise be lost with
     * the process: a set, the start, a pause, the exercise, the frozen result of Save.
     */
    private fun persistDraft(durable: Boolean) {
        val running = clock ?: return
        val draft = WatchWorkoutDraft(
            draftId = draftInstanceId,
            startedAt = running.startedAt,
            pausedTotalMs = running.pausedTotalMs,
            pausedAtMs = running.pausedAtMs,
            usingPlan = extras.value.usingPlan,
            selectedExercise = extras.value.selectedExercise,
            sets = draftSets.value.mapNotNull(::parseDraftSet),
            finished = finishedSnapshot
        )
        runCatching {
            WatchWorkoutDraftStorage.save(appContext, WatchSyncBindingStorage.load(appContext), draft, durable)
        }
    }

    /** Stops clock, rest, undo and HR, but keeps the sets and start time (queued workout). */
    private fun stopLiveTracking() {
        workoutActive.value = false
        restTimer.skip()
        restWakeLock.release()
        restRemainingSeconds.value = 0
        undoWindow.close()
        pausedRestRemainingSeconds = 0
        healthTrackingRequested = false
        _healthPermissionRequest.value = null
        exerciseTracker.stop()
        tickerJob?.cancel()
        tickerJob = null
        extras.update { it.copy(paused = false, undoSetId = null) }
    }

    /** Workout finished or thrown away: reset clock, rest timer and health. */
    private fun endWorkoutLiveState() {
        stopLiveTracking()
        clock = null
        finishedSnapshot = null
        elapsedSeconds.value = 0L
    }

    private fun ensureTicker() {
        if (tickerJob?.isActive == true) return
        tickerJob = viewModelScope.launch {
            while (isActive) {
                if (clock != null && workoutActive.value) {
                    elapsedSeconds.value = activeElapsedSeconds()
                }
                val now = nowElapsedMs()
                if (restTimer.pollFinished(now)) {
                    restRemainingSeconds.value = 0
                    WearHaptics.restFinished(appContext)
                    restWakeLock.release()
                } else if (restTimer.isRunning) {
                    restRemainingSeconds.value = restTimer.remainingSeconds(now)
                }
                if (undoWindow.expireIfDue(now)) {
                    extras.update { it.copy(undoSetId = null) }
                }
                if (!workoutActive.value && !restTimer.isRunning) break
                delay(TICK_MS)
            }
            tickerJob = null
        }
    }

    private fun formatWeight(weight: Double): String {
        return if (weight % 1.0 == 0.0) {
            weight.toInt().toString()
        } else {
            String.format(java.util.Locale.US, "%.2f", weight).trimEnd('0').trimEnd('.')
        }
    }

    private fun commitDraftEdit(candidate: List<WearSetInputUiState>): Boolean {
        if (candidate == draftSets.value) return true
        return runCatching {
            WatchPendingWorkoutStorage.clear(appContext)
            draftInstanceId = UUID.randomUUID().toString()
            draftSets.value = candidate
            markWorkoutStarted()
            true
        }.getOrElse {
            message.value = appContext.getString(R.string.message_sync_unavailable)
            false
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
            // A new generation for the same owner (re-login) must not discard the unsent draft; the
            // pending workout is re-stamped with the new generation when it is retried.
            accountGeneration = 0L
        )

    private fun resetAccountScopedEditor() {
        runCatching { WatchPendingWorkoutStorage.clear(appContext) }
        runCatching { WatchWorkoutDraftStorage.clear(appContext) }
        draftInstanceId = UUID.randomUUID().toString()
        endWorkoutLiveState()
        draftSets.value = emptyList()
        lastAppliedWorkoutPlanRaw = null
        workoutPlanMeta.value = null
        extras.update {
            it.copy(
                planTargets = emptyList(),
                usingPlan = false,
                selectedExercise = null,
                hasQueuedWorkout = false,
                saveOutcome = null
            )
        }
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

    /**
     * Brings back the workout the process was holding when it died: a stored operation (finished,
     * sent at least once, possibly already on the phone) wins over the draft, which covers both
     * a running workout and a finished one that never got an operation id.
     */
    private fun restoreWorkout() {
        val binding = WatchSyncBindingStorage.load(appContext)
        val pending = WatchPendingWorkoutStorage.load(context = appContext, binding = binding)
        val stored = runCatching { WatchWorkoutDraftStorage.load(appContext, binding) }.getOrNull()
        val draft = when {
            pending == null -> stored
            else -> WatchWorkoutDraft(
                draftId = pending.draftId,
                startedAt = pending.startedAt,
                pausedTotalMs = 0L,
                pausedAtMs = null,
                usingPlan = pending.sourcePlanRaw != null,
                selectedExercise = null,
                sets = pending.sets,
                finished = FinishedWorkoutSnapshot(
                    durationSeconds = pending.durationSeconds,
                    averageHeartRate = pending.averageHeartRate,
                    maxHeartRate = pending.maxHeartRate
                )
            )
        } ?: return
        draftInstanceId = draft.draftId
        clock = WorkoutClock(draft.startedAt, draft.pausedTotalMs, draft.pausedAtMs)
        finishedSnapshot = draft.finished
        draftSets.value = draft.sets.map { set ->
            WearSetInputUiState(
                id = nextDraftSetId++,
                exerciseName = set.exerciseName,
                weight = formatWeight(set.weight),
                reps = set.reps.toString()
            )
        }
        val storedPlan = WatchPlanStorage.load(appContext)
        var usingPlan = draft.usingPlan && storedPlan != null &&
            (pending == null || pending.sourcePlanRaw == storedPlan)
        if (usingPlan && storedPlan != null) {
            val parsed = WatchSyncJson.parseWorkoutPlanPayload(storedPlan)
            if (parsed is WatchSyncParseResult.Valid) {
                lastAppliedWorkoutPlanRaw = storedPlan
                workoutPlanMeta.value = parsed.value.meta
                extras.update { it.copy(planTargets = parsed.value.sets) }
            } else {
                usingPlan = false
            }
        }
        val queued = draft.finished != null
        extras.update {
            it.copy(
                usingPlan = usingPlan,
                selectedExercise = draft.selectedExercise,
                hasQueuedWorkout = queued,
                paused = !queued && draft.pausedAtMs != null
            )
        }
        if (!queued) {
            // The workout was still running: carry on with the same clock (a pause that was open
            // stays open until the UI resumes it) and restart heart-rate tracking.
            workoutActive.value = true
            elapsedSeconds.value = activeElapsedSeconds()
            ensureTicker()
            ensureHealthTracking()
        }
    }

    override fun onCleared() {
        // The exercise itself outlives the ViewModel (process-wide tracker + foreground service).
        tickerJob?.cancel()
        super.onCleared()
    }

    companion object {
        private const val TICK_MS = 250L

        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val app = application as WearGymApplication
                WearWorkoutViewModel(
                    application = application,
                    repository = app.repository,
                    syncClient = WearSyncClient(application),
                    exerciseTracker = app.exerciseTracker
                )
            }
        }
    }
}

private data class LiveState(
    val elapsedSeconds: Long,
    val workoutActive: Boolean,
    val restRemainingSeconds: Int,
    val restDefaultSeconds: Int,
    val health: WearHealthState
)

private data class EditorState(
    val draftSets: List<WearSetInputUiState>,
    val availableExercises: List<String>,
    val workoutPlanMeta: SyncedWorkoutPlanMeta?
)

private data class DraftBindingIdentity(
    val sourceNodeId: String?,
    val ownerId: String?,
    val accountGeneration: Long
)
