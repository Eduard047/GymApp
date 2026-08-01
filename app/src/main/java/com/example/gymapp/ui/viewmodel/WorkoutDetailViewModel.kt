package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.SetDeletionSnapshot
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.garmin.WorkoutComparison
import com.example.gymapp.garmin.buildWorkoutComparisonForSession
import com.example.gymapp.garmin.isWorkoutEarlier
import com.example.gymapp.garmin.toExerciseHistoryEntries
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.parseWeightInputOrNull
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class WorkoutDetailUiState(
    val sessionDetails: WorkoutSessionDetails? = null,
    val hasGarminReceipt: Boolean = false,
    val pendingSetDeletion: SetDeletionSnapshot? = null,
    val isSetDeletionInProgress: Boolean = false,
    val setDeletionError: LocalizedText? = null,
    val personalRecordFlags: Map<Long, Boolean> = emptyMap(),
    val restSecondsRemaining: Int = 0,
    val exerciseRestDeadlineMillis: Map<Long, Long> = emptyMap(),
    val setAdditionsInFlight: Set<Long> = emptySet(),
    val availableExercisesToAdd: List<ExerciseEntity> = emptyList(),
    val workoutComparison: WorkoutComparison? = null
)

private data class WorkoutDetailSessionContext(
    val details: WorkoutSessionDetails?,
    val comparison: WorkoutComparison?,
    val hasGarminReceipt: Boolean
)

private data class SetDeletionState(
    val pending: SetDeletionSnapshot?,
    val isInProgress: Boolean,
    val error: LocalizedText?
)

private data class WorkoutRestTimerState(
    val restSecondsRemaining: Int,
    val exerciseRestDeadlineMillis: Map<Long, Long>,
    val setAdditionsInFlight: Set<Long>
)

sealed interface WorkoutDetailEvent {
    data object AddSetFailed : WorkoutDetailEvent
    data object RestTimerFailed : WorkoutDetailEvent
    data object SetDeleted : WorkoutDetailEvent
    data object SessionDeleted : WorkoutDetailEvent
    data object InvalidInput : WorkoutDetailEvent
    data object DeleteTargetChanged : WorkoutDetailEvent
    data object DeleteFailed : WorkoutDetailEvent
}

@OptIn(ExperimentalCoroutinesApi::class)
class WorkoutDetailViewModel(
    private val repository: GymRepository,
    private val sessionId: Long,
    private val restTimerController: RestTimerController,
    private val timerAccountKey: String
) : ViewModel() {
    private val setAdditionGate = PerExerciseSetAdditionGate()
    private val exerciseRestDeadlines = restTimerController.exerciseRestDeadlineMillis.map {
        deadlines ->
        deadlines.entries
            .asSequence()
            .filter { (key, _) ->
                key.accountKey == timerAccountKey && key.sessionId == sessionId
            }
            .associate { (key, deadline) -> key.workoutExerciseId to deadline }
    }
    private val sessionDetailsFlow = repository.observeSessionDetails(sessionId)
    private val allExercisesFlow = repository.observeExercises()
    private val allExerciseHistoryFlow = repository.observeAllExerciseHistory()
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
    private val setDeletionState = combine(
        pendingSetDeletion,
        isSetDeletionInProgress,
        setDeletionError
    ) { pending, isInProgress, error ->
        SetDeletionState(
            pending = pending,
            isInProgress = isInProgress,
            error = error
        )
    }
    private val personalRecordFlags = combine(
        sessionDetailsFlow,
        allExerciseHistoryFlow
    ) { details, exerciseHistory ->
        if (details == null) {
            emptyMap()
        } else {
            val maxWeightBeforeSessionByExercise = mutableMapOf<Long, Double>()
            exerciseHistory.forEach { entry ->
                if (isWorkoutEarlier(
                        candidateDate = entry.sessionDate,
                        candidateId = entry.sessionId,
                        currentDate = details.session.date,
                        currentId = sessionId
                    )
                ) {
                    val previousMaximum = maxWeightBeforeSessionByExercise[entry.exerciseId]
                    if (previousMaximum == null || entry.weight > previousMaximum) {
                        maxWeightBeforeSessionByExercise[entry.exerciseId] = entry.weight
                    }
                }
            }
            val flags = mutableMapOf<Long, Boolean>()
            details.workoutExercises.forEach { workoutExercise ->
                val maxWeightInSession = workoutExercise.sets.maxOfOrNull { it.weight } ?: 0.0
                val maxWeightBeforeSession =
                    maxWeightBeforeSessionByExercise[workoutExercise.workoutExercise.exerciseId]
                flags[workoutExercise.workoutExercise.id] = (
                    maxWeightInSession > 0.0 &&
                        (maxWeightBeforeSession == null || maxWeightInSession > maxWeightBeforeSession)
                    )
            }
            flags
        }
    }
    private val _events = MutableSharedFlow<WorkoutDetailEvent>()
    val events = _events.asSharedFlow()
    private val restTimerState = combine(
        restTimerController.remainingSeconds,
        exerciseRestDeadlines,
        setAdditionGate.inFlight
    ) { restSecondsRemaining, exerciseRestDeadlineMillis, setAdditionsInFlight ->
        WorkoutRestTimerState(
            restSecondsRemaining = restSecondsRemaining,
            exerciseRestDeadlineMillis = exerciseRestDeadlineMillis,
            setAdditionsInFlight = setAdditionsInFlight
        )
    }

    val uiState: StateFlow<WorkoutDetailUiState> = combine(
        sessionContextFlow,
        setDeletionState,
        personalRecordFlags,
        restTimerState,
        allExercisesFlow
    ) { sessionContext, deletion, prFlags, timers, allExercises ->
        val details = sessionContext.details
        val selectedExerciseIds = details
            ?.workoutExercises
            ?.map { it.workoutExercise.exerciseId }
            ?.toSet()
            .orEmpty()
        WorkoutDetailUiState(
            sessionDetails = details,
            hasGarminReceipt = sessionContext.hasGarminReceipt,
            pendingSetDeletion = deletion.pending,
            isSetDeletionInProgress = deletion.isInProgress,
            setDeletionError = deletion.error,
            personalRecordFlags = prFlags,
            restSecondsRemaining = timers.restSecondsRemaining,
            exerciseRestDeadlineMillis = timers.exerciseRestDeadlineMillis,
            setAdditionsInFlight = timers.setAdditionsInFlight,
            availableExercisesToAdd = allExercises.filterNot { it.id in selectedExerciseIds },
            workoutComparison = sessionContext.comparison
        )
    }.stateIn(
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
                        weight = template?.weight ?: historicalWeight ?: 20.0,
                        reps = template?.reps ?: 10
                    )
                },
                afterPersist = {
                    restTimerController.startExercise(
                        accountKey = timerAccountKey,
                        sessionId = sessionId,
                        workoutExerciseId = workoutExerciseId,
                        seconds = DEFAULT_REST_SECONDS
                    )
                }
            )
            when (result) {
                WorkoutDetailSetPersistenceResult.PersistenceFailed -> {
                    _events.emit(WorkoutDetailEvent.AddSetFailed)
                }

                WorkoutDetailSetPersistenceResult.SetSavedButTimerFailed -> {
                    _events.emit(WorkoutDetailEvent.RestTimerFailed)
                }

                WorkoutDetailSetPersistenceResult.AlreadyInFlight,
                WorkoutDetailSetPersistenceResult.SetSavedAndTimerStarted -> Unit
            }
        }
    }

    fun addExerciseToWorkout(exerciseId: Long) {
        viewModelScope.launch {
            val currentDetails = uiState.value.sessionDetails ?: return@launch
            val alreadyAdded = currentDetails.workoutExercises.any {
                it.workoutExercise.exerciseId == exerciseId
            }
            if (alreadyAdded) return@launch

            val historicalWeight = repository.getLastWeightBeforeDate(
                exerciseId = exerciseId,
                beforeDate = currentDetails.session.date
            ) ?: 20.0

            repository.addExerciseToSession(
                sessionId = currentDetails.session.id,
                exerciseId = exerciseId,
                initialWeight = historicalWeight,
                initialReps = 10
            )
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
                val snapshot = repository.getSetDeletionSnapshot(setEntry.id)
                if (snapshot != null && snapshot.matchesRequestedSet(sessionId, setEntry)) {
                    pendingSetDeletion.value = snapshot
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

    fun confirmSetDeletion() {
        val expected = pendingSetDeletion.value ?: return
        if (isSetDeletionInProgress.value || setDeletionError.value != null) return
        isSetDeletionInProgress.value = true
        viewModelScope.launch {
            try {
                if (repository.deleteSetIfUnchanged(expected)) {
                    pendingSetDeletion.value = null
                    setDeletionError.value = null
                    _events.emit(WorkoutDetailEvent.SetDeleted)
                } else {
                    setDeletionError.value = LocalizedText(R.string.message_delete_target_changed)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                setDeletionError.value = LocalizedText(R.string.message_delete_failed)
            } finally {
                isSetDeletionInProgress.value = false
            }
        }
    }

    fun deleteSession() {
        viewModelScope.launch {
            repository.deleteWorkoutSessionById(sessionId)
            _events.emit(WorkoutDetailEvent.SessionDeleted)
        }
    }

    fun startRestTimer(seconds: Int = DEFAULT_REST_SECONDS) {
        restTimerController.start(seconds)
    }

    fun stopRestTimer() {
        restTimerController.stop()
    }

    fun startExerciseRestTimer(
        workoutExerciseId: Long,
        seconds: Int = DEFAULT_REST_SECONDS
    ) {
        if (!restTimerController.startExercise(
                accountKey = timerAccountKey,
                sessionId = sessionId,
                workoutExerciseId = workoutExerciseId,
                seconds = seconds
            )
        ) {
            viewModelScope.launch { _events.emit(WorkoutDetailEvent.RestTimerFailed) }
        }
    }

    fun stopExerciseRestTimer(workoutExerciseId: Long) {
        if (!restTimerController.stopExercise(
                accountKey = timerAccountKey,
                sessionId = sessionId,
                workoutExerciseId = workoutExerciseId
            )
        ) {
            viewModelScope.launch { _events.emit(WorkoutDetailEvent.RestTimerFailed) }
        }
    }

    companion object {
        private const val MAX_REPS_INPUT_LENGTH = 10

        private const val DEFAULT_REST_SECONDS = 90

        fun factory(
            repository: GymRepository,
            sessionId: Long,
            restTimerController: RestTimerController,
            timerAccountKey: String
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                WorkoutDetailViewModel(
                    repository = repository,
                    sessionId = sessionId,
                    restTimerController = restTimerController,
                    timerAccountKey = timerAccountKey
                )
            }
        }
    }
}

internal enum class WorkoutDetailSetPersistenceResult {
    AlreadyInFlight,
    PersistenceFailed,
    SetSavedButTimerFailed,
    SetSavedAndTimerStarted
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
    persist: suspend () -> Unit,
    afterPersist: () -> Boolean
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
        when {
            !persisted -> WorkoutDetailSetPersistenceResult.PersistenceFailed
            withContext(NonCancellable) { afterPersist() } -> {
                WorkoutDetailSetPersistenceResult.SetSavedAndTimerStarted
            }
            else -> WorkoutDetailSetPersistenceResult.SetSavedButTimerFailed
        }
    } finally {
        gate.finish(workoutExerciseId)
    }
}
