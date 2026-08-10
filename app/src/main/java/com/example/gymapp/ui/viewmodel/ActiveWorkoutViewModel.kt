package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.ActiveWorkoutSetUpdate
import com.example.gymapp.data.repository.DiscardActiveWorkoutResult
import com.example.gymapp.data.repository.FinishActiveWorkoutResult
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.RecordActiveWorkoutSetResult
import com.example.gymapp.data.repository.RecordActiveWorkoutSetsResult
import com.example.gymapp.data.repository.UndoActiveWorkoutSetResult
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.WorkoutRecommendationEngine
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.ActiveWorkoutTimerSnapshot
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.activeWorkoutRestSecondsRemaining
import com.example.gymapp.util.parseWeightInputOrNull
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class ActiveWorkoutSetUiState(
    val id: String,
    val orderIndex: Int,
    val weightInput: String,
    val repsInput: String,
    val isCompleted: Boolean,
    val completedAt: Long?
)

data class ActiveWorkoutExerciseUiState(
    val id: String,
    val exerciseId: Long?,
    val exerciseName: String,
    val orderIndex: Int,
    val restDurationSeconds: Int,
    val sets: List<ActiveWorkoutSetUiState>
)

data class ActiveWorkoutUiState(
    val isLoading: Boolean = true,
    val isMissing: Boolean = false,
    val date: Long = 0L,
    val note: String? = null,
    val startedAt: Long = 0L,
    val revision: Long = 0L,
    val exercises: List<ActiveWorkoutExerciseUiState> = emptyList(),
    val completedSetCount: Int = 0,
    val totalSetCount: Int = 0,
    val workoutElapsedSeconds: Long = 0L,
    val restSecondsRemaining: Int = 0,
    val latestCompletedSetId: String? = null,
    val setRecordingsInFlight: Set<String> = emptySet(),
    val undoingSetId: String? = null,
    val isRecordingAll: Boolean = false,
    val isFinishing: Boolean = false,
    val isDiscarding: Boolean = false,
    val message: LocalizedText? = null,
    val messageSetId: String? = null,
    val finishedSessionId: Long? = null,
    val wasDiscarded: Boolean = false,
    val livePeerName: String? = null,
    val livePeerCompletedSetCount: Int = 0,
    val livePeerTotalSetCount: Int = 0,
    val livePeerFinished: Boolean = false,
    val liveConnectionMode: LiveConnectionMode? = null,
    val livePendingOperationCount: Int = 0
)

private data class ActiveWorkoutInput(
    val weight: String,
    val reps: String
)

private data class ActiveWorkoutSourceState(
    val details: ActiveWorkoutDetails?,
    val inputs: Map<String, ActiveWorkoutInput>,
    val exercises: List<ExerciseEntity>,
    val hasLoaded: Boolean
)

private data class ActiveWorkoutOperationState(
    val isRecordingAll: Boolean = false,
    val isFinishing: Boolean = false,
    val isDiscarding: Boolean = false,
    val undoingSetId: String? = null,
    val message: LocalizedText? = null,
    val messageSetId: String? = null,
    val finishedSessionId: Long? = null,
    val wasDiscarded: Boolean = false
)

private data class ActiveWorkoutClockUiState(
    val workoutElapsedSeconds: Long = 0L,
    val restSecondsRemaining: Int = 0
)

internal data class ParsedActiveWorkoutSet(
    val weight: Double,
    val reps: Int
)

internal data class ActiveWorkoutSetInputForBatch(
    val setId: String,
    val weightInput: String,
    val repsInput: String
)

internal sealed interface ParsedActiveWorkoutSetBatch {
    data class Valid(val updates: List<ActiveWorkoutSetUpdate>) : ParsedActiveWorkoutSetBatch
    data class Invalid(val setId: String) : ParsedActiveWorkoutSetBatch
}

internal fun parseActiveWorkoutSetInput(
    weightInput: String,
    repsInput: String
): ParsedActiveWorkoutSet? {
    val weight = parseWeightInputOrNull(weightInput) ?: return null
    val normalizedReps = repsInput.trim()
    if (normalizedReps.length > MAX_ACTIVE_REPS_INPUT_LENGTH) return null
    val reps = normalizedReps.toIntOrNull() ?: return null
    return ParsedActiveWorkoutSet(weight, reps).takeIf { parsed ->
        WorkoutDataLimits.isValidWeight(parsed.weight) &&
            WorkoutDataLimits.isValidReps(parsed.reps)
    }
}

internal fun parseActiveWorkoutSetBatch(
    inputs: List<ActiveWorkoutSetInputForBatch>
): ParsedActiveWorkoutSetBatch {
    require(inputs.map { it.setId }.toSet().size == inputs.size) {
        "Active workout batch contains duplicate set identifiers."
    }
    val updates = ArrayList<ActiveWorkoutSetUpdate>(inputs.size)
    inputs.forEach { input ->
        val parsed = parseActiveWorkoutSetInput(input.weightInput, input.repsInput)
            ?: return ParsedActiveWorkoutSetBatch.Invalid(input.setId)
        updates += ActiveWorkoutSetUpdate(
            setId = input.setId,
            weight = parsed.weight,
            reps = parsed.reps
        )
    }
    return ParsedActiveWorkoutSetBatch.Valid(updates)
}

internal fun hasCompleteActiveWorkoutSetInputs(
    pendingSetIds: List<String>,
    availableInputIds: Set<String>
): Boolean = pendingSetIds.isNotEmpty() &&
    pendingSetIds.distinct().size == pendingSetIds.size &&
    pendingSetIds.all(availableInputIds::contains)

internal fun totalWorkoutElapsedSeconds(startedAtMillis: Long?, nowMillis: Long): Long {
    if (startedAtMillis == null ||
        !WorkoutDataLimits.isValidTimestamp(startedAtMillis) ||
        !WorkoutDataLimits.isValidTimestamp(nowMillis)
    ) {
        return 0L
    }
    return (nowMillis - startedAtMillis).coerceAtLeast(0L) / 1_000L
}

internal fun resolvedWorkoutElapsedSeconds(
    startedAtMillis: Long?,
    nowMillis: Long
): Long = totalWorkoutElapsedSeconds(startedAtMillis, nowMillis)

internal fun shouldRetireRestAfterBulkRecord(
    undoableSetId: String?,
    setCompletionStates: List<Boolean>
): Boolean = undoableSetId == null &&
    // The bulk transaction clears undo, unlike recording the final set individually.
    setCompletionStates.isNotEmpty() &&
    setCompletionStates.all { it }

internal fun resolveActiveWorkoutExerciseId(
    exercises: List<ExerciseEntity>,
    exerciseName: String,
    catalogKey: String?
): Long? {
    val exactMatches = exercises.filter { exercise -> exercise.name == exerciseName }
    if (exactMatches.size == 1) return exactMatches.single().id
    if (exactMatches.size > 1) return null
    val resolvedCatalogKey = BuiltInExerciseCatalog.resolvedKey(catalogKey, exerciseName)
        ?: return null
    return exercises
        .filter { exercise -> BuiltInExerciseCatalog.inferKey(exercise.name) == resolvedCatalogKey }
        .map { exercise -> exercise.id }
        .distinct()
        .singleOrNull()
}

internal sealed interface ActiveWorkoutRecordAndRestResult {
    data class NotRecorded(
        val repositoryResult: RecordActiveWorkoutSetResult
    ) : ActiveWorkoutRecordAndRestResult

    data object RecordedAndTimerStarted : ActiveWorkoutRecordAndRestResult
    data object RecordedButTimerFailed : ActiveWorkoutRecordAndRestResult
}

internal suspend fun persistActiveWorkoutSetBeforeRest(
    persist: suspend () -> RecordActiveWorkoutSetResult,
    startRest: () -> Unit
): ActiveWorkoutRecordAndRestResult {
    val result = persist()
    if (result !is RecordActiveWorkoutSetResult.Recorded) {
        return ActiveWorkoutRecordAndRestResult.NotRecorded(result)
    }
    currentCoroutineContext().ensureActive()
    return try {
        startRest()
        ActiveWorkoutRecordAndRestResult.RecordedAndTimerStarted
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        ActiveWorkoutRecordAndRestResult.RecordedButTimerFailed
    }
}

class ActiveWorkoutViewModel(
    private val repository: GymRepository,
    private val restTimerController: RestTimerController,
    private val timerAccountKey: String,
    private val liveSync: ActiveLiveWorkoutSync? = null
) : ViewModel() {
    private val inputs = MutableStateFlow<Map<String, ActiveWorkoutInput>>(emptyMap())
    private val hasLoaded = MutableStateFlow(false)
    private val recordGate = ActiveWorkoutSetRecordGate()
    private val operationState = MutableStateFlow(ActiveWorkoutOperationState())

    private val details = repository.observeActiveWorkout()
        .onEach { activeWorkout ->
            inputs.update { current ->
                activeWorkout?.exercises
                    .orEmpty()
                    .flatMap { exercise -> exercise.sets }
                    .associate { set ->
                        val persisted = ActiveWorkoutInput(
                            weight = formatActiveWeight(set.weight),
                            reps = set.reps.toString()
                        )
                        set.id to if (set.completedAt == null) {
                            current[set.id] ?: persisted
                        } else {
                            persisted
                        }
                    }
            }
            activeWorkout?.let { workout ->
                val startedAt = workout.activeWorkout.startedAt
                val timerReady = restTimerController.ensureActiveWorkoutTimer(
                    timerAccountKey,
                    startedAt
                )
                val shouldRetireRest = shouldRetireRestAfterBulkRecord(
                    undoableSetId = workout.activeWorkout.undoableSetId,
                    setCompletionStates = workout.exercises
                        .flatMap { exercise -> exercise.sets }
                        .map { set -> set.completedAt != null }
                )
                if (shouldRetireRest &&
                    (!timerReady ||
                        !restTimerController.stopActiveWorkoutRest(timerAccountKey, startedAt))
                ) {
                    operationState.update {
                        it.copy(
                            message = LocalizedText(
                                R.string.active_workout_all_sets_saved_rest_failed
                            ),
                            messageSetId = null
                        )
                    }
                }
            }
            hasLoaded.value = true
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.Eagerly,
            initialValue = null
        )

    private val sourceState = combine(
        details,
        inputs,
        repository.observeExercises(),
        hasLoaded
    ) { workout, setInputs, exercises, loaded ->
        ActiveWorkoutSourceState(workout, setInputs, exercises, loaded)
    }

    private val clockNow = flow {
        while (true) {
            emit(System.currentTimeMillis())
            delay(1_000L)
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.Eagerly,
        initialValue = System.currentTimeMillis()
    )

    private val clockState = combine(
        details,
        restTimerController.activeWorkoutTimerSnapshot,
        clockNow
    ) { activeWorkout, timerSnapshot, now ->
        val startedAt = activeWorkout?.activeWorkout?.startedAt
        val matchingTimer = timerSnapshot?.takeIf { snapshot ->
            snapshot.accountKey == timerAccountKey && snapshot.sessionStartedAt == startedAt
        }
        if (matchingTimer?.restEndsAt != null && now >= matchingTimer.restEndsAt) {
            restTimerController.resumeActiveWorkoutRestIfExpired(
                timerAccountKey,
                matchingTimer.sessionStartedAt
            )
        }
        ActiveWorkoutClockUiState(
            // The displayed total is continuous wall-clock time and intentionally includes rest.
            // The sidecar snapshot remains authoritative only for rest recovery/countdown.
            workoutElapsedSeconds = resolvedWorkoutElapsedSeconds(startedAt, now),
            restSecondsRemaining = activeWorkoutRestSecondsRemaining(matchingTimer, now)
        )
    }

    val uiState: StateFlow<ActiveWorkoutUiState> = combine(
        sourceState,
        recordGate.inFlight,
        clockState,
        operationState,
        liveSync?.activeLiveUiState ?: kotlinx.coroutines.flow.flowOf(ActiveLiveWorkoutUiState())
    ) { source, inFlight, clock, operation, live ->
        val activeWorkout = source.details
        val exercises = activeWorkout?.exercises.orEmpty().map { exercise ->
            ActiveWorkoutExerciseUiState(
                id = exercise.activeWorkoutExercise.id,
                exerciseId = resolveActiveWorkoutExerciseId(
                    exercises = source.exercises,
                    exerciseName = exercise.activeWorkoutExercise.exerciseName,
                    catalogKey = exercise.activeWorkoutExercise.catalogKey
                ),
                exerciseName = exercise.activeWorkoutExercise.exerciseName,
                orderIndex = exercise.activeWorkoutExercise.orderIndex,
                restDurationSeconds = WorkoutRecommendationEngine.recommendedRestSeconds(
                    exercise.activeWorkoutExercise.exerciseName
                ),
                sets = exercise.sets.map { set ->
                    val input = source.inputs[set.id]
                    ActiveWorkoutSetUiState(
                        id = set.id,
                        orderIndex = set.orderIndex,
                        weightInput = input?.weight ?: formatActiveWeight(set.weight),
                        repsInput = input?.reps ?: set.reps.toString(),
                        isCompleted = set.completedAt != null,
                        completedAt = set.completedAt
                    )
                }
            )
        }
        val allSets = exercises.flatMap(ActiveWorkoutExerciseUiState::sets)
        val latestCompletedSetId = activeWorkout?.activeWorkout?.undoableSetId?.takeIf { undoableId ->
            allSets.any { set -> set.id == undoableId && set.isCompleted }
        }
        ActiveWorkoutUiState(
            isLoading = !source.hasLoaded,
            isMissing = source.hasLoaded && activeWorkout == null &&
                !operation.isFinishing && !operation.isDiscarding &&
                operation.finishedSessionId == null && !operation.wasDiscarded,
            date = activeWorkout?.activeWorkout?.date ?: 0L,
            note = activeWorkout?.activeWorkout?.note,
            startedAt = activeWorkout?.activeWorkout?.startedAt ?: 0L,
            revision = activeWorkout?.activeWorkout?.revision ?: 0L,
            exercises = exercises,
            completedSetCount = allSets.count(ActiveWorkoutSetUiState::isCompleted),
            totalSetCount = allSets.size,
            workoutElapsedSeconds = clock.workoutElapsedSeconds.coerceAtLeast(0L),
            restSecondsRemaining = clock.restSecondsRemaining.coerceAtLeast(0),
            latestCompletedSetId = latestCompletedSetId,
            setRecordingsInFlight = inFlight,
            undoingSetId = operation.undoingSetId,
            isRecordingAll = operation.isRecordingAll,
            isFinishing = operation.isFinishing,
            isDiscarding = operation.isDiscarding,
            message = operation.message,
            messageSetId = operation.messageSetId,
            finishedSessionId = operation.finishedSessionId,
            wasDiscarded = operation.wasDiscarded,
            livePeerName = live.peerProgress?.displayName,
            livePeerCompletedSetCount = live.peerProgress?.completedSetCount ?: 0,
            livePeerTotalSetCount = live.peerProgress?.totalSetCount ?: 0,
            livePeerFinished = live.peerProgress?.isFinished == true,
            liveConnectionMode = live.connectionMode.takeIf { live.activeRoomId != null },
            livePendingOperationCount = live.pendingOperationCount
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ActiveWorkoutUiState()
    )

    fun updateSetWeight(setId: String, value: String) {
        if (value.length > MAX_ACTIVE_WEIGHT_INPUT_LENGTH || !canEditSet(setId)) return
        operationState.update { state -> state.copy(message = null, messageSetId = null) }
        inputs.update { current ->
            val existing = current[setId] ?: return@update current
            current + (setId to existing.copy(weight = value))
        }
    }

    fun updateSetReps(setId: String, value: String) {
        if (value.length > MAX_ACTIVE_REPS_INPUT_LENGTH || !canEditSet(setId)) return
        operationState.update { state -> state.copy(message = null, messageSetId = null) }
        inputs.update { current ->
            val existing = current[setId] ?: return@update current
            current + (setId to existing.copy(reps = value))
        }
    }

    fun recordSet(setId: String) {
        val snapshot = details.value ?: return
        val target = snapshot.exercises.asSequence()
            .flatMap { exercise -> exercise.sets.asSequence() }
            .firstOrNull { set -> set.id == setId && set.completedAt == null }
            ?: return
        val input = inputs.value[setId] ?: return
        val parsed = parseActiveWorkoutSetInput(input.weight, input.reps)
        if (parsed == null) {
            operationState.update {
                it.copy(
                    message = LocalizedText(R.string.message_invalid_set_input),
                    messageSetId = setId
                )
            }
            return
        }
        if (operationState.value.undoingSetId != null || operationState.value.isRecordingAll ||
            !recordGate.tryStart(setId)
        ) return

        val restDurationSeconds = snapshot.exercises
            .firstOrNull { exercise -> exercise.sets.any { it.id == setId } }
            ?.activeWorkoutExercise
            ?.exerciseName
            ?.let(WorkoutRecommendationEngine::recommendedRestSeconds)
            ?: DEFAULT_ACTIVE_REST_SECONDS
        operationState.update { state -> state.copy(message = null, messageSetId = null) }
        viewModelScope.launch {
            var preparation: LiveLocalMutationPreparation = LiveLocalMutationPreparation.Standalone
            var localCommitted = false
            try {
                preparation = liveSync?.prepareLocalSetCompleted(
                    localSetId = setId,
                    expectedLocalRevision = snapshot.activeWorkout.revision,
                    weight = parsed.weight,
                    reps = parsed.reps
                ) ?: LiveLocalMutationPreparation.Standalone
                if (preparation == LiveLocalMutationPreparation.Rejected) {
                    operationState.update {
                        it.copy(
                            message = LocalizedText(R.string.live_workout_queue_save_failed),
                            messageSetId = setId
                        )
                    }
                    return@launch
                }
                val outcome = persistActiveWorkoutSetBeforeRest(
                    persist = {
                        val result = repository.recordActiveWorkoutSet(
                            setId = target.id,
                            expectedRevision = snapshot.activeWorkout.revision,
                            weight = parsed.weight,
                            reps = parsed.reps
                        )
                        if (result is RecordActiveWorkoutSetResult.Recorded) {
                            localCommitted = true
                            (preparation as? LiveLocalMutationPreparation.Prepared)?.let {
                                liveSync?.commitPreparedLocalMutation(it)
                            }
                        }
                        result
                    },
                    startRest = {
                        check(
                            restTimerController.startActiveWorkoutRest(
                                accountKey = timerAccountKey,
                                sessionStartedAt = snapshot.activeWorkout.startedAt,
                                seconds = restDurationSeconds
                            )
                        ) { "Active workout rest timer could not be persisted." }
                    }
                )
                when (outcome) {
                    ActiveWorkoutRecordAndRestResult.RecordedAndTimerStarted -> Unit
                    ActiveWorkoutRecordAndRestResult.RecordedButTimerFailed -> {
                        operationState.update {
                            it.copy(
                                message = LocalizedText(R.string.message_rest_timer_save_failed),
                                messageSetId = setId
                            )
                        }
                    }
                    is ActiveWorkoutRecordAndRestResult.NotRecorded -> {
                        operationState.update {
                            it.copy(
                                message = messageForRecordFailure(outcome.repositoryResult),
                                messageSetId = setId
                            )
                        }
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                operationState.update {
                    it.copy(
                        message = LocalizedText(R.string.active_workout_record_failed),
                        messageSetId = setId
                    )
                }
            } finally {
                if (!localCommitted) {
                    (preparation as? LiveLocalMutationPreparation.Prepared)?.let { prepared ->
                        withContext(NonCancellable) {
                            liveSync?.cancelPreparedLocalMutation(prepared)
                        }
                    }
                }
                recordGate.finish(setId)
            }
        }
    }

    fun recordAllPendingSets() {
        val snapshot = details.value ?: return
        val operation = operationState.value
        if (recordGate.inFlight.value.isNotEmpty() || operation.isRecordingAll ||
            operation.isFinishing || operation.isDiscarding || operation.undoingSetId != null
        ) {
            return
        }
        val pendingSets = snapshot.exercises
            .flatMap { exercise -> exercise.sets }
            .filter { set -> set.completedAt == null }
        if (pendingSets.isEmpty()) return
        val currentInputs = inputs.value
        if (!hasCompleteActiveWorkoutSetInputs(
                pendingSetIds = pendingSets.map { it.id },
                availableInputIds = currentInputs.keys
            )
        ) {
            operationState.update {
                it.copy(
                    message = LocalizedText(R.string.active_workout_changed),
                    messageSetId = null
                )
            }
            return
        }
        val pendingInputs = pendingSets.map { set ->
            val input = checkNotNull(currentInputs[set.id])
            ActiveWorkoutSetInputForBatch(set.id, input.weight, input.reps)
        }
        when (val parsed = parseActiveWorkoutSetBatch(pendingInputs)) {
            is ParsedActiveWorkoutSetBatch.Invalid -> {
                operationState.update {
                    it.copy(
                        message = LocalizedText(R.string.message_invalid_set_input),
                        messageSetId = parsed.setId
                    )
                }
            }
            is ParsedActiveWorkoutSetBatch.Valid -> {
                operationState.update {
                    it.copy(isRecordingAll = true, message = null, messageSetId = null)
                }
                viewModelScope.launch {
                    var preparation: LiveLocalMutationPreparation =
                        LiveLocalMutationPreparation.Standalone
                    var localCommitted = false
                    try {
                        preparation = liveSync?.prepareLocalSetsCompleted(
                            updates = parsed.updates,
                            expectedLocalRevision = snapshot.activeWorkout.revision
                        ) ?: LiveLocalMutationPreparation.Standalone
                        if (preparation == LiveLocalMutationPreparation.Rejected) {
                            operationState.update {
                                it.copy(
                                    isRecordingAll = false,
                                    message = LocalizedText(R.string.live_workout_queue_save_failed)
                                )
                            }
                            return@launch
                        }
                        when (
                            val result = repository.recordActiveWorkoutSets(
                                updates = parsed.updates,
                                expectedRevision = snapshot.activeWorkout.revision
                            )
                        ) {
                            is RecordActiveWorkoutSetsResult.Recorded -> {
                                localCommitted = true
                                (preparation as? LiveLocalMutationPreparation.Prepared)?.let {
                                    liveSync?.commitPreparedLocalMutation(it)
                                }
                                val restStopped = runCatching {
                                    restTimerController.stopActiveWorkoutRest(
                                        timerAccountKey,
                                        snapshot.activeWorkout.startedAt
                                    )
                                }.getOrDefault(false)
                                operationState.update {
                                    it.copy(
                                        isRecordingAll = false,
                                        message = if (restStopped) {
                                            LocalizedText(
                                                R.string.active_workout_all_sets_saved,
                                                result.count
                                            )
                                        } else {
                                            LocalizedText(
                                                R.string.active_workout_all_sets_saved_rest_failed
                                            )
                                        },
                                        messageSetId = null
                                    )
                                }
                            }
                            RecordActiveWorkoutSetsResult.Missing -> operationState.update {
                                it.copy(
                                    isRecordingAll = false,
                                    message = LocalizedText(R.string.active_workout_missing)
                                )
                            }
                            RecordActiveWorkoutSetsResult.Stale,
                            RecordActiveWorkoutSetsResult.TargetChanged,
                            RecordActiveWorkoutSetsResult.AlreadyCompleted -> operationState.update {
                                it.copy(
                                    isRecordingAll = false,
                                    message = LocalizedText(R.string.active_workout_changed)
                                )
                            }
                        }
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        operationState.update {
                            it.copy(
                                isRecordingAll = false,
                                message = LocalizedText(R.string.active_workout_record_failed)
                            )
                        }
                    } finally {
                        if (!localCommitted) {
                            (preparation as? LiveLocalMutationPreparation.Prepared)?.let { prepared ->
                                withContext(NonCancellable) {
                                    liveSync?.cancelPreparedLocalMutation(prepared)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fun undoLatestSet(setId: String) {
        val snapshot = details.value ?: return
        if (recordGate.inFlight.value.isNotEmpty() || operationState.value.isRecordingAll ||
            operationState.value.isFinishing ||
            operationState.value.isDiscarding || operationState.value.undoingSetId != null
        ) {
            return
        }
        operationState.update {
            it.copy(undoingSetId = setId, message = null, messageSetId = null)
        }
        viewModelScope.launch {
            var preparation: LiveLocalMutationPreparation = LiveLocalMutationPreparation.Standalone
            var localCommitted = false
            try {
                preparation = liveSync?.prepareLocalSetUndone(
                    localSetId = setId,
                    expectedLocalRevision = snapshot.activeWorkout.revision
                ) ?: LiveLocalMutationPreparation.Standalone
                if (preparation == LiveLocalMutationPreparation.Rejected) {
                    operationState.update {
                        it.copy(
                            undoingSetId = null,
                            message = LocalizedText(R.string.live_workout_queue_save_failed),
                            messageSetId = setId
                        )
                    }
                    return@launch
                }
                when (repository.undoLatestActiveWorkoutSet(setId, snapshot.activeWorkout.revision)) {
                    is UndoActiveWorkoutSetResult.Undone -> {
                        localCommitted = true
                        (preparation as? LiveLocalMutationPreparation.Prepared)?.let {
                            liveSync?.commitPreparedLocalMutation(it)
                        }
                        runCatching {
                            restTimerController.stopActiveWorkoutRest(
                                timerAccountKey,
                                snapshot.activeWorkout.startedAt
                            )
                        }
                        operationState.update {
                            it.copy(
                                undoingSetId = null,
                                message = it.message,
                                messageSetId = it.messageSetId
                            )
                        }
                    }
                    UndoActiveWorkoutSetResult.Missing -> operationState.update {
                        it.copy(
                            undoingSetId = null,
                            message = LocalizedText(R.string.active_workout_missing),
                            messageSetId = setId
                        )
                    }
                    UndoActiveWorkoutSetResult.Stale,
                    UndoActiveWorkoutSetResult.NotLatest,
                    UndoActiveWorkoutSetResult.TargetChanged -> operationState.update {
                        it.copy(
                            undoingSetId = null,
                            message = LocalizedText(R.string.active_workout_undo_changed),
                            messageSetId = setId
                        )
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                operationState.update {
                    it.copy(
                        undoingSetId = null,
                        message = LocalizedText(R.string.active_workout_undo_failed),
                        messageSetId = setId
                    )
                }
            } finally {
                if (!localCommitted) {
                    (preparation as? LiveLocalMutationPreparation.Prepared)?.let { prepared ->
                        withContext(NonCancellable) {
                            liveSync?.cancelPreparedLocalMutation(prepared)
                        }
                    }
                }
            }
        }
    }

    fun adjustRestTimer(deltaSeconds: Int) {
        if (deltaSeconds !in -MAX_REST_ADJUST_SECONDS..MAX_REST_ADJUST_SECONDS) return
        if (deltaSeconds == 0) return
        val snapshot = details.value ?: return
        if (restTimerController.adjustActiveWorkoutRest(
                accountKey = timerAccountKey,
                sessionStartedAt = snapshot.activeWorkout.startedAt,
                deltaSeconds = deltaSeconds
            ) == null
        ) {
            operationState.update {
                it.copy(message = LocalizedText(R.string.message_rest_timer_save_failed))
            }
        }
    }

    fun stopRestTimer() {
        val snapshot = details.value ?: return
        if (!restTimerController.stopActiveWorkoutRest(
                accountKey = timerAccountKey,
                sessionStartedAt = snapshot.activeWorkout.startedAt
            )
        ) {
            operationState.update {
                it.copy(message = LocalizedText(R.string.message_rest_timer_save_failed))
            }
        }
    }

    fun finishWorkout() {
        val snapshot = details.value ?: return
        if (recordGate.inFlight.value.isNotEmpty() || operationState.value.isRecordingAll ||
            operationState.value.isFinishing ||
            operationState.value.isDiscarding || operationState.value.undoingSetId != null
        ) {
            return
        }
        operationState.update { it.copy(isFinishing = true, message = null) }
        viewModelScope.launch {
            var preparation: LiveLocalMutationPreparation = LiveLocalMutationPreparation.Standalone
            var localCommitted = false
            try {
                preparation = liveSync?.prepareLocalWorkoutFinished(
                    expectedLocalRevision = snapshot.activeWorkout.revision
                ) ?: LiveLocalMutationPreparation.Standalone
                if (preparation == LiveLocalMutationPreparation.Rejected) {
                    operationState.update {
                        it.copy(
                            isFinishing = false,
                            message = LocalizedText(R.string.live_workout_queue_save_failed)
                        )
                    }
                    return@launch
                }
                when (val result = repository.finishActiveWorkout(snapshot.activeWorkout.revision)) {
                    is FinishActiveWorkoutResult.Finished -> {
                        localCommitted = true
                        (preparation as? LiveLocalMutationPreparation.Prepared)?.let {
                            liveSync?.commitPreparedLocalMutation(it)
                        }
                        runCatching {
                            restTimerController.clearActiveWorkoutTimer(
                                timerAccountKey,
                                snapshot.activeWorkout.startedAt
                            )
                            restTimerController.stop()
                        }
                        operationState.value = ActiveWorkoutOperationState(
                            finishedSessionId = result.sessionId
                        )
                    }
                    FinishActiveWorkoutResult.Missing -> {
                        operationState.update {
                            it.copy(
                                isFinishing = false,
                                message = LocalizedText(R.string.active_workout_missing)
                            )
                        }
                    }
                    FinishActiveWorkoutResult.Stale -> {
                        operationState.update {
                            it.copy(
                                isFinishing = false,
                                message = LocalizedText(R.string.active_workout_changed)
                            )
                        }
                    }
                    FinishActiveWorkoutResult.NoCompletedSets -> {
                        operationState.update {
                            it.copy(
                                isFinishing = false,
                                message = LocalizedText(R.string.active_workout_finish_requires_set)
                            )
                        }
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                operationState.update {
                    it.copy(
                        isFinishing = false,
                        message = LocalizedText(R.string.active_workout_finish_failed)
                    )
                }
            } finally {
                if (!localCommitted) {
                    (preparation as? LiveLocalMutationPreparation.Prepared)?.let { prepared ->
                        withContext(NonCancellable) {
                            liveSync?.cancelPreparedLocalMutation(prepared)
                        }
                    }
                }
            }
        }
    }

    fun discardWorkout() {
        val snapshot = details.value ?: return
        if (recordGate.inFlight.value.isNotEmpty() || operationState.value.isRecordingAll ||
            operationState.value.isFinishing ||
            operationState.value.isDiscarding || operationState.value.undoingSetId != null
        ) {
            return
        }
        operationState.update { it.copy(isDiscarding = true, message = null) }
        viewModelScope.launch {
            try {
                when (repository.discardActiveWorkout(snapshot.activeWorkout.revision)) {
                    DiscardActiveWorkoutResult.Discarded -> {
                        liveSync?.afterLocalWorkoutDiscarded()
                        runCatching {
                            restTimerController.clearActiveWorkoutTimer(
                                timerAccountKey,
                                snapshot.activeWorkout.startedAt
                            )
                            restTimerController.stop()
                        }
                        operationState.value = ActiveWorkoutOperationState(wasDiscarded = true)
                    }
                    DiscardActiveWorkoutResult.Missing -> {
                        operationState.update {
                            it.copy(
                                isDiscarding = false,
                                message = LocalizedText(R.string.active_workout_missing)
                            )
                        }
                    }
                    DiscardActiveWorkoutResult.Stale -> {
                        operationState.update {
                            it.copy(
                                isDiscarding = false,
                                message = LocalizedText(R.string.active_workout_changed)
                            )
                        }
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                operationState.update {
                    it.copy(
                        isDiscarding = false,
                        message = LocalizedText(R.string.active_workout_discard_failed)
                    )
                }
            }
        }
    }

    fun dismissMessage() {
        operationState.update { state -> state.copy(message = null, messageSetId = null) }
    }

    fun consumeNavigation() {
        operationState.update { state ->
            state.copy(finishedSessionId = null, wasDiscarded = false)
        }
    }

    private fun canEditSet(setId: String): Boolean = details.value?.exercises
        .orEmpty()
        .asSequence()
        .flatMap { exercise -> exercise.sets.asSequence() }
        .any { set -> set.id == setId && set.completedAt == null } &&
        setId !in recordGate.inFlight.value

    private fun messageForRecordFailure(result: RecordActiveWorkoutSetResult): LocalizedText =
        when (result) {
            RecordActiveWorkoutSetResult.Missing -> LocalizedText(R.string.active_workout_missing)
            RecordActiveWorkoutSetResult.Stale,
            RecordActiveWorkoutSetResult.TargetChanged,
            RecordActiveWorkoutSetResult.AlreadyCompleted ->
                LocalizedText(R.string.active_workout_changed)
            is RecordActiveWorkoutSetResult.Recorded ->
                LocalizedText(R.string.active_workout_record_failed)
        }

    companion object {
        private const val DEFAULT_ACTIVE_REST_SECONDS = 90
        private const val MAX_REST_ADJUST_SECONDS = 15

        fun factory(
            repository: GymRepository,
            restTimerController: RestTimerController,
            timerAccountKey: String,
            liveSync: ActiveLiveWorkoutSync? = null
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ActiveWorkoutViewModel(repository, restTimerController, timerAccountKey, liveSync)
            }
        }
    }
}

internal class ActiveWorkoutSetRecordGate {
    private val lock = Any()
    private val _inFlight = MutableStateFlow<Set<String>>(emptySet())
    val inFlight: StateFlow<Set<String>> = _inFlight

    fun tryStart(setId: String): Boolean = synchronized(lock) {
        if (setId.isBlank() || _inFlight.value.isNotEmpty()) return@synchronized false
        _inFlight.value = setOf(setId)
        true
    }

    fun finish(setId: String) {
        synchronized(lock) {
            _inFlight.value = _inFlight.value - setId
        }
    }
}

private fun formatActiveWeight(weight: Double): String = if (weight % 1.0 == 0.0) {
    weight.toLong().toString()
} else {
    String.format(Locale.US, "%.2f", weight).trimEnd('0').trimEnd('.')
}

private const val MAX_ACTIVE_WEIGHT_INPUT_LENGTH = 64
private const val MAX_ACTIVE_REPS_INPUT_LENGTH = 10
