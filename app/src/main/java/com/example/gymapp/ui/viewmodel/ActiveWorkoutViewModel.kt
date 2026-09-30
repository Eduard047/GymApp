package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.auth.FriendGhosts
import com.example.gymapp.data.repository.ApplyActiveWorkoutAdaptationResult
import com.example.gymapp.data.repository.LiveCompletedSet
import com.example.gymapp.data.repository.LivePersonalRecords
import com.example.gymapp.data.repository.WorkoutAdaptation
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.ActiveWorkoutSetUpdate
import com.example.gymapp.data.repository.AddActiveWorkoutSetResult
import com.example.gymapp.data.repository.DiscardActiveWorkoutResult
import com.example.gymapp.data.repository.FinishActiveWorkoutResult
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.RecordActiveWorkoutSetResult
import com.example.gymapp.data.repository.RecordActiveWorkoutSetsResult
import com.example.gymapp.data.repository.SaveActiveWorkoutExerciseResult
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
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
    val completedAt: Long?,
    val previousWeight: Double? = null,
    val previousReps: Int? = null,
    val repeatWeight: Double? = null,
    val repeatReps: Int? = null,
    val allowedWeights: List<Double> = emptyList(),
    /** A completed set that beat this exercise's history best (see LivePersonalRecords). */
    val isPersonalRecord: Boolean = false
)

data class ActiveWorkoutExerciseUiState(
    val id: String,
    val exerciseId: Long?,
    val exerciseName: String,
    val orderIndex: Int,
    val restDurationSeconds: Int,
    val sets: List<ActiveWorkoutSetUiState>,
    /** Built-in catalog key, used for the plate calculator. */
    val catalogKey: String? = null,
    /** Matches a friend's result on the same exercise (see FriendGhosts). */
    val friendGhostKey: String = "",
    /** True when "Skip them" can drop this exercise's unrecorded sets (see WorkoutAdaptation.buildSkipCandidate). */
    val canSkipRemaining: Boolean = false
)

data class ActiveWorkoutAdaptationValue(val weight: Double, val reps: Int, val previousWeight: Double?, val previousReps: Int?)
data class ActiveWorkoutAdaptationLine(val name: String, val previousName: String, val before: Int, val after: Int, val values: List<ActiveWorkoutAdaptationValue>)
data class ActiveWorkoutAdaptationChoice(val exerciseId: Long, val name: String)
data class ActiveWorkoutAdaptationUiState(
    val reason: String,
    val choices: List<ActiveWorkoutAdaptationChoice> = emptyList(),
    val hasPreview: Boolean = false,
    val beforePending: Int = 0,
    val afterPending: Int = 0,
    val previewLines: List<ActiveWorkoutAdaptationLine> = emptyList(),
    val isApplying: Boolean = false
)
private data class ActiveWorkoutAdaptationRequest(
    val reason: String, val source: ActiveWorkoutDetails, val candidate: ActiveWorkoutDetails? = null,
    val catalog: List<ExerciseEntity>, val history: List<com.example.gymapp.data.entity.ExerciseHistoryEntry>,
    val profiles: Map<Long, com.example.gymapp.data.repository.ExerciseLoadProfile>,
    val choices: List<com.example.gymapp.data.repository.SmartWorkoutAlternative> = emptyList(), val isApplying: Boolean = false,
    val previewSource: ActiveWorkoutDetails = source,
    val trainingProfile: TrainingProfile = TrainingProfile(),
    val mappings: List<com.example.gymapp.data.entity.ExerciseMuscleMappingEntity> = emptyList()
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
    val liveSelfName: String? = null,
    val livePeerName: String? = null,
    val livePeerCompletedSetCount: Int = 0,
    val livePeerTotalSetCount: Int = 0,
    val livePeerFinished: Boolean = false,
    val livePeerExercises: List<LivePeerExerciseSummary> = emptyList(),
    val liveExerciseLanes: List<LiveExerciseLaneSummary> = emptyList(),
    val liveConnectionMode: LiveConnectionMode? = null,
    val livePendingOperationCount: Int = 0,
    val adaptation: ActiveWorkoutAdaptationUiState? = null
)

/** String shown after "Skip them": the frozen live plan, a stale/missing workout, or success. */
internal fun activeWorkoutSkipOutcomeMessage(result: ApplyActiveWorkoutAdaptationResult): Int = when (result) {
    is ApplyActiveWorkoutAdaptationResult.Applied -> R.string.active_workout_remaining_sets_skipped
    ApplyActiveWorkoutAdaptationResult.LivePlanFrozen -> R.string.training_adaptation_live_blocked
    else -> R.string.active_workout_changed
}

internal fun activeWorkoutOperationInProgress(
    setRecordingsInFlight: Set<String>,
    isRecordingAll: Boolean,
    isFinishing: Boolean,
    isDiscarding: Boolean,
    undoingSetId: String?
): Boolean = setRecordingsInFlight.isNotEmpty() || isRecordingAll || isFinishing ||
    isDiscarding || undoingSetId != null

private data class ActiveWorkoutInput(
    val weight: String,
    val reps: String
)

private data class ActiveWorkoutSourceState(
    val details: ActiveWorkoutDetails?,
    val inputs: Map<String, ActiveWorkoutInput>,
    val exercises: List<ExerciseEntity>,
    val hasLoaded: Boolean,
    val history: List<com.example.gymapp.data.entity.ExerciseHistoryEntry>,
    val loadProfiles: Map<Long, com.example.gymapp.data.repository.ExerciseLoadProfile>
)

/** Completed sets of the running workout that beat their exercise's history best. */
private fun personalRecordSetIds(
    activeWorkout: ActiveWorkoutDetails?,
    source: ActiveWorkoutSourceState,
    workoutStartedAt: Long
): Set<String> {
    if (activeWorkout == null) return emptySet()
    val completed = mutableListOf<LiveCompletedSet>()
    activeWorkout.exercises.forEachIndexed exercises@{ exerciseIndex, exercise ->
        val exerciseId = resolveActiveWorkoutExerciseId(
            exercises = source.exercises,
            exerciseName = exercise.activeWorkoutExercise.exerciseName,
            catalogKey = exercise.activeWorkoutExercise.catalogKey
        ) ?: return@exercises
        exercise.sets.forEachIndexed sets@{ setIndex, set ->
            val completedAt = set.completedAt ?: return@sets
            completed += LiveCompletedSet(
                exerciseId = exerciseId,
                setId = set.id,
                weight = set.weight,
                reps = set.reps,
                completedAt = completedAt,
                exerciseIndex = exerciseIndex,
                setIndex = setIndex
            )
        }
    }
    if (completed.isEmpty()) return emptySet()
    val exerciseIds = completed.mapTo(mutableSetOf()) { it.exerciseId }
    val history = source.history.filter { entry ->
        entry.exerciseId in exerciseIds && entry.sessionDate < workoutStartedAt
    }
    return LivePersonalRecords.recordSetIds(completed, LivePersonalRecords.baselines(history))
}

private data class ActiveWorkoutOperationState(
    val isRecordingAll: Boolean = false,
    val isFinishing: Boolean = false,
    val isDiscarding: Boolean = false,
    val undoingSetId: String? = null,
    val message: LocalizedText? = null,
    val messageSetId: String? = null,
    val finishedSessionId: Long? = null,
    val wasDiscarded: Boolean = false,
    val adaptation: ActiveWorkoutAdaptationRequest? = null
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
    val normalizedWeight = weightInput.trim()
    val weight = if (normalizedWeight.isEmpty()) {
        0.0
    } else {
        parseWeightInputOrNull(normalizedWeight) ?: return null
    }
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

internal fun shouldReconcileRestAfterUndoCleared(
    undoableSetId: String?,
    setCompletionStates: List<Boolean>
): Boolean = undoableSetId == null &&
    // Save-exercise and add-set clear undo even when other sets remain pending. A completed set
    // proves that this durable snapshot may own a rest interval that still needs retirement.
    // Do not require restEndsAt here: the ledger can be resumed while notification cleanup fails.
    setCompletionStates.any { it }

internal fun reconcileRestAfterDurableWorkoutSnapshot(
    undoableSetId: String?,
    setCompletionStates: List<Boolean>,
    timerReady: Boolean,
    stopRest: () -> Boolean
): ActiveWorkoutRestReconciliationStatus {
    if (!shouldReconcileRestAfterUndoCleared(undoableSetId, setCompletionStates)) {
        return ActiveWorkoutRestReconciliationStatus.NotRequired
    }
    val restStopped = timerReady && runCatching(stopRest).getOrDefault(false)
    return if (restStopped) {
        ActiveWorkoutRestReconciliationStatus.Reconciled
    } else {
        ActiveWorkoutRestReconciliationStatus.Failed
    }
}

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

internal enum class ActiveWorkoutRestReconciliationStatus {
    NotRequired,
    Reconciled,
    Failed
}

internal data class ActiveWorkoutPostMutationResult<T>(
    val repositoryResult: T,
    val restStatus: ActiveWorkoutRestReconciliationStatus
)

internal suspend fun <T> persistActiveWorkoutMutationAndReconcileRest(
    persist: suspend () -> T,
    isCommitted: (T) -> Boolean,
    stopRest: () -> Boolean
): ActiveWorkoutPostMutationResult<T> {
    val repositoryResult = persist()
    if (!isCommitted(repositoryResult)) {
        return ActiveWorkoutPostMutationResult(
            repositoryResult = repositoryResult,
            restStatus = ActiveWorkoutRestReconciliationStatus.NotRequired
        )
    }
    // The database mutation already cleared undo. Cleanup must still finish if the screen leaves.
    val restStopped = withContext(NonCancellable) {
        runCatching(stopRest).getOrDefault(false)
    }
    return ActiveWorkoutPostMutationResult(
        repositoryResult = repositoryResult,
        restStatus = if (restStopped) {
            ActiveWorkoutRestReconciliationStatus.Reconciled
        } else {
            ActiveWorkoutRestReconciliationStatus.Failed
        }
    )
}

class ActiveWorkoutViewModel(
    private val repository: GymRepository,
    private val restTimerController: RestTimerController,
    private val timerAccountKey: String,
    private val liveSync: ActiveLiveWorkoutSync? = null,
    private val currentTrainingProfile: () -> TrainingProfile = { TrainingProfile() }
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
                val restRecovery = reconcileRestAfterDurableWorkoutSnapshot(
                    undoableSetId = workout.activeWorkout.undoableSetId,
                    setCompletionStates = workout.exercises
                        .flatMap { exercise -> exercise.sets }
                        .map { set -> set.completedAt != null },
                    timerReady = timerReady,
                    stopRest = {
                        restTimerController.stopActiveWorkoutRest(timerAccountKey, startedAt)
                    }
                )
                if (restRecovery == ActiveWorkoutRestReconciliationStatus.Failed) {
                    operationState.update {
                        it.copy(
                            message = LocalizedText(
                                R.string.active_workout_change_saved_rest_failed
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
        combine(repository.observeExercises(), repository.observeAllExerciseHistory(), repository.observeExerciseLoadProfiles()) {
            catalog, history, profiles -> Triple(catalog, history, profiles)
        },
        hasLoaded
    ) { workout, setInputs, data, loaded ->
        ActiveWorkoutSourceState(workout, setInputs, data.first, loaded, data.second, data.third)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, ActiveWorkoutSourceState(null, emptyMap(), emptyList(), false, emptyList(), emptyMap()))

    private val adaptationMappings = repository.observeExerciseMuscleMappings()
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val clockNow = flow {
        while (true) {
            emit(System.currentTimeMillis())
            delay(1_000L)
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
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

    private val contentState = combine(
        sourceState,
        recordGate.inFlight,
        operationState,
        liveSync?.activeLiveUiState ?: kotlinx.coroutines.flow.flowOf(ActiveLiveWorkoutUiState())
    ) { source, inFlight, operation, live ->
        val activeWorkout = source.details
        val workoutStartedAt = activeWorkout?.activeWorkout?.startedAt ?: 0L
        val recordSetIds = personalRecordSetIds(activeWorkout, source, workoutStartedAt)
        val exercises = activeWorkout?.exercises.orEmpty().map { exercise ->
            val resolvedId = resolveActiveWorkoutExerciseId(source.exercises,
                exercise.activeWorkoutExercise.exerciseName, exercise.activeWorkoutExercise.catalogKey)
            val history = source.history.filter { it.exerciseId == resolvedId && it.sessionDate < (activeWorkout?.activeWorkout?.startedAt ?: 0L) }
            val latestSession = history.maxWithOrNull(compareBy<com.example.gymapp.data.entity.ExerciseHistoryEntry> { it.sessionDate }.thenBy { it.sessionId })?.sessionId
            val previous = history.filter { it.sessionId == latestSession }.sortedBy { it.setOrderIndex }
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
                    val last = previous.firstOrNull { it.setOrderIndex == set.orderIndex } ?: previous.lastOrNull()
                    val preceding = exercise.sets.lastOrNull { it.orderIndex < set.orderIndex && it.completedAt != null }
                    ActiveWorkoutSetUiState(
                        id = set.id,
                        orderIndex = set.orderIndex,
                        weightInput = input?.weight ?: formatActiveWeight(set.weight),
                        repsInput = input?.reps ?: set.reps.toString(),
                        isCompleted = set.completedAt != null,
                        completedAt = set.completedAt,
                        previousWeight = last?.weight,
                        previousReps = last?.reps,
                        repeatWeight = preceding?.weight ?: last?.weight,
                        repeatReps = preceding?.reps ?: last?.reps,
                        allowedWeights = source.loadProfiles[resolvedId]?.allowedWeightsKg.orEmpty(),
                        isPersonalRecord = set.id in recordSetIds
                    )
                },
                catalogKey = BuiltInExerciseCatalog.resolvedKey(
                    catalogKey = exercise.activeWorkoutExercise.catalogKey,
                    rawName = exercise.activeWorkoutExercise.exerciseName
                ),
                friendGhostKey = FriendGhosts.exerciseKey(
                    catalogKey = exercise.activeWorkoutExercise.catalogKey,
                    name = exercise.activeWorkoutExercise.exerciseName
                ),
                canSkipRemaining = activeWorkout != null && WorkoutAdaptation.buildSkipCandidate(
                    activeWorkout,
                    exercise.activeWorkoutExercise.id
                ) != null
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
            workoutElapsedSeconds = 0L,
            restSecondsRemaining = 0,
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
            liveSelfName = live.selfDisplayName,
            livePeerName = live.peerProgress?.displayName,
            livePeerCompletedSetCount = live.peerProgress?.completedSetCount ?: 0,
            livePeerTotalSetCount = live.peerProgress?.totalSetCount ?: 0,
            livePeerFinished = live.peerProgress?.isFinished == true,
            livePeerExercises = live.peerExercises,
            liveExerciseLanes = live.exerciseLanes,
            liveConnectionMode = live.connectionMode.takeIf { live.activeRoomId != null },
            livePendingOperationCount = live.pendingOperationCount,
            adaptation = operation.adaptation?.let { request ->
                val before = request.source.exercises.sumOf { b -> b.sets.count { it.completedAt == null } }
                val after = request.candidate?.exercises?.sumOf { b -> b.sets.count { it.completedAt == null } } ?: 0
                ActiveWorkoutAdaptationUiState(request.reason,
                    request.choices.map { ActiveWorkoutAdaptationChoice(it.exercise.id, it.exercise.name) }, request.candidate != null,
                    before, after, if (request.candidate == null) emptyList() else request.previewSource.exercises.mapNotNull { oldBlock ->
                        val oldSets = oldBlock.sets.filter { it.completedAt == null }
                        if (oldSets.isEmpty()) null else {
                            val ids = oldSets.map { it.id }.toSet()
                            val newBlock = request.candidate.exercises.firstOrNull { block -> block.sets.any { it.id in ids && it.completedAt == null } }
                            val newSets = newBlock?.sets?.filter { it.id in ids && it.completedAt == null }.orEmpty()
                            val replaced = newBlock != null && (newBlock.activeWorkoutExercise.catalogKey != oldBlock.activeWorkoutExercise.catalogKey || newBlock.activeWorkoutExercise.exerciseName != oldBlock.activeWorkoutExercise.exerciseName)
                            val changes = newSets.mapNotNull { set ->
                                val old = oldSets.first { it.id == set.id }
                                if (!replaced && old.weight == set.weight && old.reps == set.reps) null
                                else ActiveWorkoutAdaptationValue(set.weight, set.reps, if (replaced) null else old.weight, if (replaced) null else old.reps)
                            }.distinct()
                            if (oldSets.size == newSets.size && !replaced && changes.isEmpty()) null else
                                ActiveWorkoutAdaptationLine(newBlock?.activeWorkoutExercise?.exerciseName ?: oldBlock.activeWorkoutExercise.exerciseName,
                                    oldBlock.activeWorkoutExercise.exerciseName, oldSets.size, newSets.size, changes)
                        }
                    }, request.isApplying)

            }
        )
    }.flowOn(Dispatchers.Default)

    val uiState: StateFlow<ActiveWorkoutUiState> = combine(
        contentState,
        clockState
    ) { content, clock ->
        content.copy(
            workoutElapsedSeconds = clock.workoutElapsedSeconds.coerceAtLeast(0L),
            restSecondsRemaining = clock.restSecondsRemaining.coerceAtLeast(0)
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
        if (activeWorkoutOperationInProgress()) return
        if (!recordGate.tryStart(setId)) return

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

    fun saveExercise(exerciseId: String) {
        if (isInLiveRoom()) return
        val snapshot = details.value ?: return
        val target = snapshot.exercises.firstOrNull {
            it.activeWorkoutExercise.id == exerciseId
        } ?: return
        val operation = operationState.value
        if (recordGate.inFlight.value.isNotEmpty() || operation.isRecordingAll ||
            operation.isFinishing || operation.isDiscarding || operation.undoingSetId != null
        ) return
        val currentInputs = inputs.value
        val parsed = parseActiveWorkoutSetBatch(target.sets.map { set ->
            val input = currentInputs[set.id]
                ?: return operationState.update {
                    it.copy(message = LocalizedText(R.string.active_workout_changed))
                }
            ActiveWorkoutSetInputForBatch(set.id, input.weight, input.reps)
        })
        if (parsed is ParsedActiveWorkoutSetBatch.Invalid) {
            operationState.update {
                it.copy(
                    message = LocalizedText(R.string.message_invalid_set_input),
                    messageSetId = parsed.setId
                )
            }
            return
        }
        val updates = (parsed as ParsedActiveWorkoutSetBatch.Valid).updates
        operationState.update { it.copy(isRecordingAll = true, message = null, messageSetId = null) }
        viewModelScope.launch {
            val outcome = runCatching {
                persistActiveWorkoutMutationAndReconcileRest(
                    persist = {
                        repository.saveActiveWorkoutExercise(
                            exerciseId = exerciseId,
                            updates = updates,
                            expectedRevision = snapshot.activeWorkout.revision
                        )
                    },
                    isCommitted = { it is SaveActiveWorkoutExerciseResult.Saved },
                    stopRest = {
                        restTimerController.stopActiveWorkoutRest(
                            timerAccountKey,
                            snapshot.activeWorkout.startedAt
                        )
                    }
                )
            }.getOrNull()
            operationState.update {
                val restCleanupFailed = outcome?.restStatus ==
                    ActiveWorkoutRestReconciliationStatus.Failed
                when (outcome?.repositoryResult) {
                    is SaveActiveWorkoutExerciseResult.Saved -> it.copy(
                        isRecordingAll = false,
                        message = LocalizedText(
                            if (restCleanupFailed) {
                                R.string.active_workout_change_saved_rest_failed
                            } else {
                                R.string.active_workout_exercise_saved
                            }
                        ),
                        messageSetId = null
                    )
                    else -> it.copy(
                        isRecordingAll = false,
                        message = LocalizedText(R.string.active_workout_changed),
                        messageSetId = null
                    )
                }
            }
        }
    }

    /**
     * "Skip them": finishes the exercise by dropping its unrecorded sets instead of recording them.
     * Reuses the adaptation path (completed sets are preserved and re-validated by the repository).
     * The latest recorded set, its undo and its rest timer are untouched: skipped sets were never
     * recorded, so there is no timer or undo state that belongs to them.
     */
    fun skipRemainingSets(exerciseId: String) {
        if (activeWorkoutOperationInProgress()) return
        if (isInLiveRoom()) {
            operationState.update {
                it.copy(message = LocalizedText(R.string.training_adaptation_live_blocked), messageSetId = null)
            }
            return
        }
        val snapshot = details.value ?: return
        val currentInputs = inputs.value
        val hydrated = snapshot.copy(exercises = snapshot.exercises.map { block ->
            block.copy(sets = block.sets.map { set ->
                val parsed = currentInputs[set.id]?.let { parseActiveWorkoutSetInput(it.weight, it.reps) }
                if (set.completedAt != null || parsed == null) set else set.copy(weight = parsed.weight, reps = parsed.reps)
            })
        })
        val candidate = WorkoutAdaptation.buildSkipCandidate(hydrated, exerciseId)
        if (candidate == null) {
            operationState.update {
                it.copy(message = LocalizedText(R.string.active_workout_changed), messageSetId = null)
            }
            return
        }
        operationState.update { it.copy(isRecordingAll = true, message = null, messageSetId = null) }
        viewModelScope.launch {
            val result = runCatching { repository.applyActiveWorkoutAdaptation(snapshot, candidate) }
                .getOrDefault(ApplyActiveWorkoutAdaptationResult.Stale)
            operationState.update {
                it.copy(
                    isRecordingAll = false,
                    message = LocalizedText(activeWorkoutSkipOutcomeMessage(result)),
                    messageSetId = null
                )
            }
        }
    }

    private fun isInLiveRoom(): Boolean = liveSync?.activeLiveUiState?.value?.activeRoomId != null

    fun addSet(exerciseId: String) {
        if (isInLiveRoom()) return
        val snapshot = details.value ?: return
        val operation = operationState.value
        if (recordGate.inFlight.value.isNotEmpty() || operation.isRecordingAll ||
            operation.isFinishing || operation.isDiscarding || operation.undoingSetId != null
        ) return
        operationState.update { it.copy(isRecordingAll = true, message = null, messageSetId = null) }
        viewModelScope.launch {
            val outcome = runCatching {
                persistActiveWorkoutMutationAndReconcileRest(
                    persist = {
                        repository.addActiveWorkoutSet(
                            exerciseId,
                            snapshot.activeWorkout.revision
                        )
                    },
                    isCommitted = { it is AddActiveWorkoutSetResult.Added },
                    stopRest = {
                        restTimerController.stopActiveWorkoutRest(
                            timerAccountKey,
                            snapshot.activeWorkout.startedAt
                        )
                    }
                )
            }.getOrNull()
            operationState.update {
                val restCleanupFailed = outcome?.restStatus ==
                    ActiveWorkoutRestReconciliationStatus.Failed
                when (outcome?.repositoryResult) {
                    is AddActiveWorkoutSetResult.Added -> it.copy(
                        isRecordingAll = false,
                        message = if (restCleanupFailed) {
                            LocalizedText(R.string.active_workout_change_saved_rest_failed)
                        } else {
                            null
                        },
                        messageSetId = null
                    )
                    AddActiveWorkoutSetResult.LimitReached -> it.copy(
                        isRecordingAll = false,
                        message = LocalizedText(R.string.active_workout_set_limit_reached)
                    )
                    else -> it.copy(
                        isRecordingAll = false,
                        message = LocalizedText(R.string.active_workout_changed)
                    )
                }
            }
        }
    }

    fun previewAdaptation(reason: String, minutes: Int = 20, replacementId: Long? = null) {
        if (activeWorkoutOperationInProgress() || reason !in setOf("equipmentUnavailable", "timeCut", "tooHard") || liveSync?.activeLiveUiState?.value?.activeRoomId != null) return
        val source = sourceState.value
        val workout = source.details ?: return
        val values = source.inputs.mapValues { (_, input) -> parseActiveWorkoutSetInput(input.weight, input.reps) }
        if (workout.exercises.flatMap { it.sets }.any { it.completedAt == null && values[it.id] == null }) return
        val hydrated = workout.copy(exercises = workout.exercises.map { b -> b.copy(sets = b.sets.map { set ->
            if (set.completedAt != null) set else values.getValue(set.id)!!.let { set.copy(weight = it.weight, reps = it.reps) }
        }) })
        val current = hydrated.exercises.firstOrNull { it.sets.any { set -> set.completedAt == null } }
        val currentId = current?.let { resolveActiveWorkoutExerciseId(source.exercises, it.activeWorkoutExercise.exerciseName, it.activeWorkoutExercise.catalogKey) }
        val alternatives = if (reason == "equipmentUnavailable" && currentId != null) WorkoutRecommendationEngine.findAlternatives(
            currentId, hydrated.exercises.mapNotNull { resolveActiveWorkoutExerciseId(source.exercises, it.activeWorkoutExercise.exerciseName, it.activeWorkoutExercise.catalogKey) }.toSet(),
            source.exercises, source.history, trainingProfile = currentTrainingProfile(), loadProfiles = source.loadProfiles,
            manualMuscleMappings = adaptationMappings.value.toManualContributionMap(), hardSetEligible = false, limit = 6) else emptyList()
        val selected = replacementId?.let { id -> alternatives.firstOrNull { it.exercise.id == id } }
        val candidate = if ((reason == "equipmentUnavailable" && selected == null) || (reason == "timeCut" && minutes == 0)) null else WorkoutAdaptation.build(hydrated, reason, minutes, source.loadProfiles,
            exerciseId = { block -> resolveActiveWorkoutExerciseId(source.exercises, block.exerciseName, block.catalogKey) }, replacement = selected)
        operationState.update { it.copy(adaptation = ActiveWorkoutAdaptationRequest(reason, workout, candidate,
            source.exercises, source.history, source.loadProfiles, alternatives, previewSource = hydrated,
            trainingProfile = currentTrainingProfile(), mappings = adaptationMappings.value), message = null, messageSetId = null) }
    }

    fun dismissAdaptation() { operationState.update { it.copy(adaptation = null) } }

    fun applyAdaptation() {
        val request = operationState.value.adaptation ?: return
        val candidate = request.candidate ?: return
        if (request.isApplying) return
        operationState.update { it.copy(adaptation = request.copy(isApplying = true)) }
        viewModelScope.launch {
            val latest = sourceState.value
            val result = if (latest.exercises != request.catalog || latest.history != request.history || latest.loadProfiles != request.profiles ||
                request.trainingProfile != currentTrainingProfile() || request.mappings != adaptationMappings.value ||
                liveSync?.activeLiveUiState?.value?.activeRoomId != null) ApplyActiveWorkoutAdaptationResult.Stale
            else runCatching { repository.applyActiveWorkoutAdaptation(request.source, candidate) }.getOrDefault(ApplyActiveWorkoutAdaptationResult.Stale)
            if (result is ApplyActiveWorkoutAdaptationResult.Applied) {
                inputs.value = candidate.exercises.flatMap { it.sets }.associate { set ->
                    set.id to ActiveWorkoutInput(formatActiveWeight(set.weight), set.reps.toString())
                }
            }
            operationState.update { state -> when (result) {
                is ApplyActiveWorkoutAdaptationResult.Applied -> state.copy(adaptation = null, message = null)
                ApplyActiveWorkoutAdaptationResult.LivePlanFrozen -> state.copy(adaptation = null, message = LocalizedText(R.string.training_adaptation_live_blocked))
                else -> state.copy(adaptation = null, message = LocalizedText(R.string.active_workout_changed))
            } }
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
        if (activeWorkoutOperationInProgress()) return
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
        if (activeWorkoutOperationInProgress()) return
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
        .any { set -> set.id == setId && (liveSync == null || set.completedAt == null) } &&
        setId !in recordGate.inFlight.value

    private fun activeWorkoutOperationInProgress(): Boolean {
        val operation = operationState.value
        return activeWorkoutOperationInProgress(
            setRecordingsInFlight = recordGate.inFlight.value,
            isRecordingAll = operation.isRecordingAll,
            isFinishing = operation.isFinishing,
            isDiscarding = operation.isDiscarding,
            undoingSetId = operation.undoingSetId
        )
    }

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
            liveSync: ActiveLiveWorkoutSync? = null,
            currentTrainingProfile: () -> TrainingProfile = { TrainingProfile() }
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ActiveWorkoutViewModel(repository, restTimerController, timerAccountKey, liveSync, currentTrainingProfile)
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
