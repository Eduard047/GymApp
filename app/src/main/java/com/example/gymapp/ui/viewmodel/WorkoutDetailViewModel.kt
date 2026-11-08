package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.LiveCompletedSet
import com.example.gymapp.data.repository.LivePersonalRecords
import com.example.gymapp.data.repository.SetDeletionImpact
import com.example.gymapp.data.repository.SetDeletionSnapshot
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.data.repository.normalizedExerciseName
import com.example.gymapp.data.repository.normalizedWorkoutNote
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.garmin.WorkoutComparison
import com.example.gymapp.garmin.buildWorkoutComparisonForSession
import com.example.gymapp.garmin.isWorkoutEarlier
import com.example.gymapp.garmin.toExerciseHistoryEntries
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.parseWeightInputOrNull
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.shareIn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class WorkoutDetailUiState(
    val sessionDetails: WorkoutSessionDetails? = null,
    val hasGarminReceipt: Boolean = false,
    val pendingSetDeletion: SetDeletionSnapshot? = null,
    /** Set or exercise hidden for 5 s behind the undo bar; storage is untouched until it commits. */
    val stagedRemoval: WorkoutDetailStagedRemoval? = null,
    val isSetDeletionInProgress: Boolean = false,
    val setDeletionError: LocalizedText? = null,
    val personalRecordFlags: Map<Long, Boolean> = emptyMap(),
    val personalRecordSetIds: Set<Long> = emptySet(),
    val setAdditionsInFlight: Set<Long> = emptySet(),
    val availableExercisesToAdd: List<ExerciseEntity> = emptyList(),
    val frequentExerciseIds: List<Long> = emptyList(),
    /** Picker "Recent" section, already limited to the exercises the picker offers. */
    val recentExerciseIds: List<Long> = emptyList(),
    val exerciseWorkoutCounts: Map<Long, Int> = emptyMap(),
    val exerciseMuscleIds: Map<String, Set<String>> = emptyMap(),
    val workoutComparison: WorkoutComparison? = null
)

private data class WorkoutDetailSessionContext(
    val details: WorkoutSessionDetails?,
    val comparison: WorkoutComparison?,
    val hasGarminReceipt: Boolean
)

/** A removal staged behind the undo bar (iOS pending deletion): hidden on screen, not yet stored. */
sealed interface WorkoutDetailStagedRemoval {
    data class Set(val snapshot: SetDeletionSnapshot) : WorkoutDetailStagedRemoval
    data class Exercise(val workoutExerciseId: Long) : WorkoutDetailStagedRemoval
}

private data class SetDeletionState(
    val pending: SetDeletionSnapshot?,
    val staged: WorkoutDetailStagedRemoval?,
    val isInProgress: Boolean,
    val error: LocalizedText?
)

private data class WorkoutDetailRecords(
    val flags: Map<Long, Boolean>,
    val setIds: Set<Long>
)

private data class WorkoutDetailMutationState(
    val setAdditionsInFlight: Set<Long>,
    val exerciseAdditionsInFlight: Set<Long>
)

private data class WorkoutDetailExerciseCatalog(
    val exercises: List<ExerciseEntity>,
    val frequentExerciseIds: List<Long>,
    /** Newest first over every exercise; the add picker narrows it to the exercises it offers. */
    val recentExerciseIds: List<Long>,
    val workoutCounts: Map<Long, Int>,
    val muscleIdsByName: Map<String, Set<String>>
)

sealed interface WorkoutDetailEvent {
    data object AddSetFailed : WorkoutDetailEvent
    data object AddExerciseFailed : WorkoutDetailEvent
    data object SetDeleted : WorkoutDetailEvent
    data object SessionDeleted : WorkoutDetailEvent
    data object InvalidInput : WorkoutDetailEvent
    data object ExerciseRemoved : WorkoutDetailEvent
    data object RemoveExerciseFailed : WorkoutDetailEvent
    data object DetailsSaved : WorkoutDetailEvent
    data object DetailsInvalid : WorkoutDetailEvent
    data object DetailsSaveFailed : WorkoutDetailEvent
    data object DeleteTargetChanged : WorkoutDetailEvent
    data object DeleteFailed : WorkoutDetailEvent
}

@OptIn(ExperimentalCoroutinesApi::class)
class WorkoutDetailViewModel(
    private val repository: GymRepository,
    private val sessionId: Long
) : ViewModel() {
    private val setAdditionGate = PerExerciseSetAdditionGate()
    private val exerciseAdditionGate = PerExerciseSetAdditionGate()
    private val sessionDetailsFlow = repository.observeSessionDetails(sessionId).shareIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(
            stopTimeoutMillis = 5_000,
            replayExpirationMillis = 0
        ),
        replay = 1
    )
    private val allExercisesFlow = repository.observeExercises()
    private val allExerciseHistoryFlow = repository.observeAllExerciseHistory().shareIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(
            stopTimeoutMillis = 5_000,
            replayExpirationMillis = 0
        ),
        replay = 1
    )
    private val exerciseCatalogFlow = combine(
        allExercisesFlow,
        allExerciseHistoryFlow,
        repository.observeExerciseMuscleMappings()
    ) { exercises, history, mappings ->
        val manualMappings = mappings.toManualContributionMap()
        val exerciseFrequencies = exerciseFrequencyByExercise(history)
        val workoutCounts = exerciseFrequencies.mapValues { (_, frequency) ->
            frequency.workoutCount
        }
        val frequentIds = frequentExerciseIds(exerciseFrequencies)
        WorkoutDetailExerciseCatalog(
            exercises = exercises,
            frequentExerciseIds = frequentIds,
            recentExerciseIds = recentExerciseIds(
                history,
                exercises.mapTo(HashSet()) { it.id },
                limit = Int.MAX_VALUE
            ),
            workoutCounts = workoutCounts,
            muscleIdsByName = exercises.associate { exercise ->
                val contributions = manualMappings[exercise.name.normalizedExerciseName()]
                    ?: defaultContributionsForExercise(exercise.name)
                exercise.name to contributions.mapTo(linkedSetOf()) { it.muscleId }
            }
        )
    }
    private val sessionContextFlow = combine(
        sessionDetailsFlow,
        repository.observeSessions(),
        allExerciseHistoryFlow
    ) { details, sessions, exerciseHistory ->
        val hasGarminReceipt = sessions
            .firstOrNull { summary -> summary.session.id == sessionId }
            ?.hasGarminReceipt == true
        WorkoutDetailSessionContext(
            details = details,
            comparison = details?.let { current ->
                buildWorkoutComparisonForSession(
                    currentSessionId = current.session.id,
                    currentSessionDate = current.session.date,
                    currentNote = current.session.note,
                    currentHasGarminReceipt = hasGarminReceipt,
                    currentEntries = current.toExerciseHistoryEntries(),
                    allSessions = sessions,
                    allHistory = exerciseHistory
                )
            },
            hasGarminReceipt = hasGarminReceipt
        )
    }
    private val pendingSetDeletion = MutableStateFlow<SetDeletionSnapshot?>(null)
    private val isSetDeletionInProgress = MutableStateFlow(false)
    private val setDeletionError = MutableStateFlow<LocalizedText?>(null)
    private val stagedDeletion = StagedDeletion<WorkoutDetailStagedRemoval>(
        scope = viewModelScope,
        onCommit = ::persistStagedRemoval
    )
    private val setDeletionState = combine(
        pendingSetDeletion,
        stagedDeletion.pending,
        isSetDeletionInProgress,
        setDeletionError
    ) { pending, staged, isInProgress, error ->
        SetDeletionState(
            pending = pending,
            staged = staged,
            isInProgress = isInProgress,
            error = error
        )
    }
    private val personalRecordFlags = combine(
        sessionDetailsFlow,
        allExerciseHistoryFlow
    ) { details, exerciseHistory ->
        if (details == null) {
            WorkoutDetailRecords(emptyMap(), emptySet())
        } else {
            val setIds = storedWorkoutPersonalRecordSetIds(details, exerciseHistory)
            WorkoutDetailRecords(
                flags = details.workoutExercises.associate { workoutExercise ->
                    workoutExercise.workoutExercise.id to
                        workoutExercise.sets.any { it.id in setIds }
                },
                setIds = setIds
            )
        }
    }
    private val _events = MutableSharedFlow<WorkoutDetailEvent>()
    val events = _events.asSharedFlow()
    private val mutationState = combine(
        setAdditionGate.inFlight,
        exerciseAdditionGate.inFlight
    ) { setAdditionsInFlight, exerciseAdditionsInFlight ->
        WorkoutDetailMutationState(
            setAdditionsInFlight = setAdditionsInFlight,
            exerciseAdditionsInFlight = exerciseAdditionsInFlight
        )
    }

    val uiState: StateFlow<WorkoutDetailUiState> = combine(
        sessionContextFlow,
        setDeletionState,
        personalRecordFlags,
        mutationState,
        exerciseCatalogFlow
    ) { sessionContext, deletion, records, mutations, catalog ->
        val details = sessionContext.details
        val selectedExerciseIds = details
            ?.workoutExercises
            ?.map { it.workoutExercise.exerciseId }
            ?.toSet()
            .orEmpty()
        val availableExercises = catalog.exercises.filterNot {
            it.id in selectedExerciseIds || it.id in mutations.exerciseAdditionsInFlight
        }
        WorkoutDetailUiState(
            sessionDetails = details?.withoutStagedRemoval(deletion.staged),
            hasGarminReceipt = sessionContext.hasGarminReceipt,
            pendingSetDeletion = deletion.pending,
            stagedRemoval = deletion.staged,
            isSetDeletionInProgress = deletion.isInProgress,
            setDeletionError = deletion.error,
            personalRecordFlags = records.flags,
            personalRecordSetIds = records.setIds,
            setAdditionsInFlight = mutations.setAdditionsInFlight,
            availableExercisesToAdd = availableExercises,
            frequentExerciseIds = catalog.frequentExerciseIds,
            recentExerciseIds = catalog.recentExerciseIds
                .limitedToPicker(availableExercises.mapTo(HashSet()) { it.id }),
            exerciseWorkoutCounts = catalog.workoutCounts,
            exerciseMuscleIds = catalog.muscleIdsByName,
            workoutComparison = sessionContext.comparison
        )
    }.flowOn(Dispatchers.Default).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WorkoutDetailUiState()
    )

    fun addSet(workoutExerciseId: Long) {
        viewModelScope.launch {
            val result = persistWorkoutDetailSet(
                workoutExerciseId = workoutExerciseId,
                gate = setAdditionGate,
                persist = {
                    val currentDetails = checkNotNull(uiState.value.sessionDetails) {
                        "Workout details are unavailable."
                    }
                    val workoutExercise = checkNotNull(
                        currentDetails.workoutExercises.firstOrNull {
                            it.workoutExercise.id == workoutExerciseId
                        }
                    ) {
                        "Workout exercise is unavailable."
                    }
                    val template = workoutExercise.sets.maxByOrNull { it.orderIndex }
                    val historicalWeight = repository.getLastWeightBeforeDate(
                        exerciseId = workoutExercise.workoutExercise.exerciseId,
                        beforeDate = currentDetails.session.date
                    )
                    repository.addSet(
                        workoutExerciseId = workoutExerciseId,
                        weight = pastWorkoutSetWeight(template?.weight, historicalWeight),
                        reps = template?.reps ?: 10
                    )
                }
            )
            when (result) {
                WorkoutDetailSetPersistenceResult.PersistenceFailed -> {
                    _events.emit(WorkoutDetailEvent.AddSetFailed)
                }

                WorkoutDetailSetPersistenceResult.AlreadyInFlight,
                WorkoutDetailSetPersistenceResult.SetSaved -> Unit
            }
        }
    }

    /** Creates a custom exercise from the picker; the caller then selects the returned id. */
    suspend fun createExerciseForPicker(name: String): Long = repository.addExercise(name)

    fun addExerciseToWorkout(exerciseId: Long) {
        viewModelScope.launch {
            when (
                persistWorkoutDetailExercise(
                    exerciseId = exerciseId,
                    gate = exerciseAdditionGate
                ) {
                    val currentDetails = uiState.value.sessionDetails ?: return@persistWorkoutDetailExercise
                    val alreadyAdded = currentDetails.workoutExercises.any {
                        it.workoutExercise.exerciseId == exerciseId
                    }
                    if (alreadyAdded) return@persistWorkoutDetailExercise

                    val historicalWeight = pastWorkoutSetWeight(
                        templateWeight = null,
                        historicalWeight = repository.getLastWeightBeforeDate(
                            exerciseId = exerciseId,
                            beforeDate = currentDetails.session.date
                        )
                    )

                    repository.addExerciseToSession(
                        sessionId = currentDetails.session.id,
                        exerciseId = exerciseId,
                        initialWeight = historicalWeight,
                        initialReps = 10
                    )
                }
            ) {
                WorkoutDetailExercisePersistenceResult.PersistenceFailed -> {
                    _events.emit(WorkoutDetailEvent.AddExerciseFailed)
                }
                WorkoutDetailExercisePersistenceResult.AlreadyInFlight,
                WorkoutDetailExercisePersistenceResult.ExerciseSaved -> Unit
            }
        }
    }

    fun updateSet(setEntry: SetEntryEntity, weight: String, reps: String) {
        val parsedWeight = parseWeightInputOrNull(weight)
        val repsInput = reps.trim()
        val parsedReps = repsInput.takeIf { it.length <= MAX_REPS_INPUT_LENGTH }?.toIntOrNull()
        if (parsedWeight == null || parsedReps == null ||
            !WorkoutDataLimits.isValidWeight(parsedWeight) || !WorkoutDataLimits.isValidReps(parsedReps)
        ) {
            viewModelScope.launch {
                _events.emit(WorkoutDetailEvent.InvalidInput)
            }
            return
        }

        viewModelScope.launch {
            repository.updateSet(
                setEntry.copy(
                    weight = parsedWeight,
                    reps = parsedReps
                )
            )
        }
    }

    fun requestDeleteSet(setEntry: SetEntryEntity) {
        if (isSetDeletionInProgress.value || pendingSetDeletion.value != null) return
        isSetDeletionInProgress.value = true
        setDeletionError.value = null
        viewModelScope.launch {
            try {
                // A new deletion commits the staged one first, so its snapshot sees the stored state.
                stagedDeletion.commitNow()
                val snapshot = repository.getSetDeletionSnapshot(setEntry.id)
                if (snapshot != null && snapshot.matchesRequestedSet(sessionId, setEntry)) {
                    if (snapshot.impact == SetDeletionImpact.SetOnly) {
                        // Like iOS: a set that leaves its exercise with other sets is staged at once.
                        stagedDeletion.stage(WorkoutDetailStagedRemoval.Set(snapshot))
                    } else {
                        pendingSetDeletion.value = snapshot
                    }
                } else {
                    _events.emit(WorkoutDetailEvent.DeleteTargetChanged)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                _events.emit(WorkoutDetailEvent.DeleteFailed)
            } finally {
                isSetDeletionInProgress.value = false
            }
        }
    }

    fun dismissSetDeletion() {
        if (isSetDeletionInProgress.value) return
        pendingSetDeletion.value = null
        setDeletionError.value = null
    }

    /** The dialog was confirmed (final set of an exercise): stage it behind the undo bar. */
    fun confirmSetDeletion() {
        val expected = pendingSetDeletion.value ?: return
        if (isSetDeletionInProgress.value || setDeletionError.value != null) return
        isSetDeletionInProgress.value = true
        viewModelScope.launch {
            try {
                stagedDeletion.stage(WorkoutDetailStagedRemoval.Set(expected))
                pendingSetDeletion.value = null
                setDeletionError.value = null
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                setDeletionError.value = LocalizedText(R.string.message_delete_failed)
            } finally {
                isSetDeletionInProgress.value = false
            }
        }
    }

    /** Undo bar: brings the staged set or exercise back; nothing was ever written. */
    fun undoStagedRemoval() {
        stagedDeletion.undo()
    }

    private suspend fun persistStagedRemoval(removal: WorkoutDetailStagedRemoval) {
        try {
            when (removal) {
                is WorkoutDetailStagedRemoval.Set -> {
                    if (!repository.deleteSetIfUnchanged(removal.snapshot)) {
                        _events.emit(WorkoutDetailEvent.DeleteTargetChanged)
                    }
                }

                is WorkoutDetailStagedRemoval.Exercise -> {
                    if (!repository.removeExerciseFromSession(sessionId, removal.workoutExerciseId)) {
                        _events.emit(WorkoutDetailEvent.RemoveExerciseFailed)
                    }
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            _events.emit(
                when (removal) {
                    is WorkoutDetailStagedRemoval.Set -> WorkoutDetailEvent.DeleteFailed
                    is WorkoutDetailStagedRemoval.Exercise -> WorkoutDetailEvent.RemoveExerciseFailed
                }
            )
        }
    }

    /**
     * Removes one exercise block from this saved workout behind the 5 s undo bar; the last visible
     * exercise is never removed (the whole workout is deleted through [deleteSession]).
     */
    fun removeExercise(workoutExerciseId: Long) {
        viewModelScope.launch {
            try {
                val visible = uiState.value.sessionDetails?.workoutExercises.orEmpty()
                val canRemove = visible.size > 1 &&
                    visible.any { it.workoutExercise.id == workoutExerciseId }
                if (canRemove) {
                    stagedDeletion.stage(WorkoutDetailStagedRemoval.Exercise(workoutExerciseId))
                } else {
                    _events.emit(WorkoutDetailEvent.RemoveExerciseFailed)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                _events.emit(WorkoutDetailEvent.RemoveExerciseFailed)
            }
        }
    }

    /** Saves the workout date and note (blank note clears it), like iOS "Save session details". */
    fun updateSessionDetails(dateMillis: Long, note: String) {
        if (!isValidWorkoutDetailsInput(dateMillis, note)) {
            viewModelScope.launch { _events.emit(WorkoutDetailEvent.DetailsInvalid) }
            return
        }
        viewModelScope.launch {
            try {
                repository.updateWorkoutSessionDetails(sessionId, dateMillis, note)
                _events.emit(WorkoutDetailEvent.DetailsSaved)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                _events.emit(WorkoutDetailEvent.DetailsSaveFailed)
            }
        }
    }

    fun deleteSession() {
        // The whole workout goes, so a staged set/exercise inside it is moot: forget it, don't commit.
        stagedDeletion.undo()
        viewModelScope.launch {
            repository.deleteWorkoutSessionById(sessionId)
            _events.emit(WorkoutDetailEvent.SessionDeleted)
        }
    }

    /** Leaving the screen commits the staged removal (iOS onDisappear), on a scope that outlives this view model. */
    override fun onCleared() {
        stagedDeletion.commitDetached()
        super.onCleared()
    }

    companion object {
        private const val MAX_REPS_INPUT_LENGTH = 10

        fun factory(
            repository: GymRepository,
            sessionId: Long
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                WorkoutDetailViewModel(
                    repository = repository,
                    sessionId = sessionId
                )
            }
        }
    }
}

/** [WorkoutSessionDetails] as the screen shows it while [staged] is hidden behind the undo bar. */
internal fun WorkoutSessionDetails.withoutStagedRemoval(
    staged: WorkoutDetailStagedRemoval?
): WorkoutSessionDetails = when (staged) {
    null -> this
    is WorkoutDetailStagedRemoval.Exercise -> copy(
        workoutExercises = workoutExercises.filterNot { it.workoutExercise.id == staged.workoutExerciseId }
    )

    is WorkoutDetailStagedRemoval.Set -> {
        val snapshot = staged.snapshot
        copy(
            workoutExercises = if (snapshot.impact == SetDeletionImpact.SetOnly) {
                workoutExercises.map { block ->
                    if (block.workoutExercise.id == snapshot.workoutExerciseId) {
                        block.copy(sets = block.sets.filterNot { it.id == snapshot.setId })
                    } else {
                        block
                    }
                }
            } else {
                // The final set takes its exercise block with it.
                workoutExercises.filterNot { it.workoutExercise.id == snapshot.workoutExerciseId }
            }
        )
    }
}

internal enum class WorkoutDetailSetPersistenceResult {
    AlreadyInFlight,
    PersistenceFailed,
    SetSaved
}

internal enum class WorkoutDetailExercisePersistenceResult {
    AlreadyInFlight,
    PersistenceFailed,
    ExerciseSaved
}

internal class PerExerciseSetAdditionGate {
    private val lock = Any()
    private val _inFlight = MutableStateFlow<Set<Long>>(emptySet())
    val inFlight: StateFlow<Set<Long>> = _inFlight

    fun tryStart(workoutExerciseId: Long): Boolean = synchronized(lock) {
        if (workoutExerciseId <= 0L || workoutExerciseId in _inFlight.value) {
            return@synchronized false
        }
        _inFlight.value = _inFlight.value + workoutExerciseId
        true
    }

    fun finish(workoutExerciseId: Long) {
        synchronized(lock) {
            _inFlight.value = _inFlight.value - workoutExerciseId
        }
    }
}

internal suspend fun persistWorkoutDetailSet(
    workoutExerciseId: Long,
    gate: PerExerciseSetAdditionGate,
    persist: suspend () -> Unit
): WorkoutDetailSetPersistenceResult {
    if (!gate.tryStart(workoutExerciseId)) {
        return WorkoutDetailSetPersistenceResult.AlreadyInFlight
    }
    return try {
        val persisted = try {
            persist()
            true
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            false
        }
        if (persisted) {
            WorkoutDetailSetPersistenceResult.SetSaved
        } else {
            WorkoutDetailSetPersistenceResult.PersistenceFailed
        }
    } finally {
        gate.finish(workoutExerciseId)
    }
}

internal suspend fun persistWorkoutDetailExercise(
    exerciseId: Long,
    gate: PerExerciseSetAdditionGate,
    persist: suspend () -> Unit
): WorkoutDetailExercisePersistenceResult {
    if (!gate.tryStart(exerciseId)) {
        return WorkoutDetailExercisePersistenceResult.AlreadyInFlight
    }
    return try {
        try {
            persist()
            WorkoutDetailExercisePersistenceResult.ExerciseSaved
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            WorkoutDetailExercisePersistenceResult.PersistenceFailed
        }
    } finally {
        gate.finish(exerciseId)
    }
}

/**
 * Records inside one saved workout, under the same rules as the live badge
 * ([LivePersonalRecords]): the baseline is the history of strictly earlier workouts, each set is
 * compared with the better of that baseline and every earlier set of this workout, an exercise
 * without earlier history never gets a record, a 0 kg set is never a record, and a weight record
 * must be strictly heavier while an estimated one-rep max must clear the best by a tolerance.
 * Returns the ids of the record sets.
 */
internal fun storedWorkoutPersonalRecordSetIds(
    details: WorkoutSessionDetails,
    exerciseHistory: List<ExerciseHistoryEntry>
): Set<Long> {
    val priorHistory = exerciseHistory.filter { entry ->
        isWorkoutEarlier(
            candidateDate = entry.sessionDate,
            candidateId = entry.sessionId,
            currentDate = details.session.date,
            currentId = details.session.id
        )
    }
    val completed = details.workoutExercises
        .sortedBy { it.workoutExercise.orderIndex }
        .flatMapIndexed { exerciseIndex, workoutExercise ->
            workoutExercise.sets
                .sortedBy { it.orderIndex }
                .mapIndexed { setIndex, set ->
                    LiveCompletedSet(
                        exerciseId = workoutExercise.workoutExercise.exerciseId,
                        setId = set.id.toString(),
                        weight = set.weight,
                        reps = set.reps,
                        completedAt = 0L,
                        exerciseIndex = exerciseIndex,
                        setIndex = setIndex
                    )
                }
        }
    return LivePersonalRecords
        .recordSetIds(completed, LivePersonalRecords.baselines(priorHistory))
        .mapTo(linkedSetOf()) { it.toLong() }
}

/** Per workout exercise: whether any of its sets is a record (see [storedWorkoutPersonalRecordSetIds]). */
internal fun storedWorkoutPersonalRecordFlags(
    details: WorkoutSessionDetails,
    exerciseHistory: List<ExerciseHistoryEntry>
): Map<Long, Boolean> {
    val recordSetIds = storedWorkoutPersonalRecordSetIds(details, exerciseHistory)
    return details.workoutExercises.associate { workoutExercise ->
        workoutExercise.workoutExercise.id to workoutExercise.sets.any { it.id in recordSetIds }
    }
}

/** Date within the supported timestamp range and a note within the shared note limits. */
internal fun isValidWorkoutDetailsInput(dateMillis: Long, note: String): Boolean =
    WorkoutDataLimits.isValidTimestamp(dateMillis) &&
        WorkoutDataLimits.isValidNote(normalizedWorkoutNote(note))

/**
 * Weight for a set or exercise added to a past workout (mirrors iPhone): the last set of the
 * block when it has one, else the exercise's last used weight from history, else 0.
 */
internal fun pastWorkoutSetWeight(templateWeight: Double?, historicalWeight: Double?): Double =
    templateWeight ?: historicalWeight ?: 0.0
