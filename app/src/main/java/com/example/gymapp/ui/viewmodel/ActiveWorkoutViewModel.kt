package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.data.entity.ActiveWorkoutDetails
import com.example.gymapp.data.repository.DiscardActiveWorkoutResult
import com.example.gymapp.data.repository.FinishActiveWorkoutResult
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.RecordActiveWorkoutSetResult
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.parseWeightInputOrNull
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

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
    val exerciseName: String,
    val orderIndex: Int,
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
    val restSecondsRemaining: Int = 0,
    val setRecordingsInFlight: Set<String> = emptySet(),
    val isFinishing: Boolean = false,
    val isDiscarding: Boolean = false,
    val message: LocalizedText? = null,
    val finishedSessionId: Long? = null,
    val wasDiscarded: Boolean = false
)

private data class ActiveWorkoutInput(
    val weight: String,
    val reps: String
)

private data class ActiveWorkoutSourceState(
    val details: ActiveWorkoutDetails?,
    val inputs: Map<String, ActiveWorkoutInput>,
    val hasLoaded: Boolean
)

private data class ActiveWorkoutOperationState(
    val isFinishing: Boolean = false,
    val isDiscarding: Boolean = false,
    val message: LocalizedText? = null,
    val finishedSessionId: Long? = null,
    val wasDiscarded: Boolean = false
)

internal data class ParsedActiveWorkoutSet(
    val weight: Double,
    val reps: Int
)

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
    private val restTimerController: RestTimerController
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
            hasLoaded.value = true
        }
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.Eagerly,
            initialValue = null
        )

    private val sourceState = combine(details, inputs, hasLoaded) { workout, setInputs, loaded ->
        ActiveWorkoutSourceState(workout, setInputs, loaded)
    }

    val uiState: StateFlow<ActiveWorkoutUiState> = combine(
        sourceState,
        recordGate.inFlight,
        restTimerController.remainingSeconds,
        operationState
    ) { source, inFlight, restSeconds, operation ->
        val activeWorkout = source.details
        val exercises = activeWorkout?.exercises.orEmpty().map { exercise ->
            ActiveWorkoutExerciseUiState(
                id = exercise.activeWorkoutExercise.id,
                exerciseName = exercise.activeWorkoutExercise.exerciseName,
                orderIndex = exercise.activeWorkoutExercise.orderIndex,
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
            restSecondsRemaining = restSeconds.coerceAtLeast(0),
            setRecordingsInFlight = inFlight,
            isFinishing = operation.isFinishing,
            isDiscarding = operation.isDiscarding,
            message = operation.message,
            finishedSessionId = operation.finishedSessionId,
            wasDiscarded = operation.wasDiscarded
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = ActiveWorkoutUiState()
    )

    fun updateSetWeight(setId: String, value: String) {
        if (value.length > MAX_ACTIVE_WEIGHT_INPUT_LENGTH || !canEditSet(setId)) return
        operationState.update { state -> state.copy(message = null) }
        inputs.update { current ->
            val existing = current[setId] ?: return@update current
            current + (setId to existing.copy(weight = value))
        }
    }

    fun updateSetReps(setId: String, value: String) {
        if (value.length > MAX_ACTIVE_REPS_INPUT_LENGTH || !canEditSet(setId)) return
        operationState.update { state -> state.copy(message = null) }
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
                it.copy(message = LocalizedText(R.string.message_invalid_set_input))
            }
            return
        }
        if (!recordGate.tryStart(setId)) return

        operationState.update { state -> state.copy(message = null) }
        viewModelScope.launch {
            try {
                val outcome = persistActiveWorkoutSetBeforeRest(
                    persist = {
                        repository.recordActiveWorkoutSet(
                            setId = target.id,
                            expectedRevision = snapshot.activeWorkout.revision,
                            weight = parsed.weight,
                            reps = parsed.reps
                        )
                    },
                    startRest = { restTimerController.start(DEFAULT_ACTIVE_REST_SECONDS) }
                )
                when (outcome) {
                    ActiveWorkoutRecordAndRestResult.RecordedAndTimerStarted -> Unit
                    ActiveWorkoutRecordAndRestResult.RecordedButTimerFailed -> {
                        operationState.update {
                            it.copy(message = LocalizedText(R.string.message_rest_timer_save_failed))
                        }
                    }
                    is ActiveWorkoutRecordAndRestResult.NotRecorded -> {
                        operationState.update {
                            it.copy(message = messageForRecordFailure(outcome.repositoryResult))
                        }
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                operationState.update {
                    it.copy(message = LocalizedText(R.string.active_workout_record_failed))
                }
            } finally {
                recordGate.finish(setId)
            }
        }
    }

    fun finishWorkout() {
        val snapshot = details.value ?: return
        if (recordGate.inFlight.value.isNotEmpty() || operationState.value.isFinishing ||
            operationState.value.isDiscarding
        ) {
            return
        }
        operationState.update { it.copy(isFinishing = true, message = null) }
        viewModelScope.launch {
            try {
                when (val result = repository.finishActiveWorkout(snapshot.activeWorkout.revision)) {
                    is FinishActiveWorkoutResult.Finished -> {
                        runCatching { restTimerController.stop() }
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
            }
        }
    }

    fun discardWorkout() {
        val snapshot = details.value ?: return
        if (recordGate.inFlight.value.isNotEmpty() || operationState.value.isFinishing ||
            operationState.value.isDiscarding
        ) {
            return
        }
        operationState.update { it.copy(isDiscarding = true, message = null) }
        viewModelScope.launch {
            try {
                when (repository.discardActiveWorkout(snapshot.activeWorkout.revision)) {
                    DiscardActiveWorkoutResult.Discarded -> {
                        runCatching { restTimerController.stop() }
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
        operationState.update { state -> state.copy(message = null) }
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

        fun factory(
            repository: GymRepository,
            restTimerController: RestTimerController
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ActiveWorkoutViewModel(repository, restTimerController)
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
