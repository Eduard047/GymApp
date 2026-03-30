package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.util.RestTimerController
import com.example.gymapp.util.parseWeightInputOrNull
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class WorkoutDetailUiState(
    val sessionDetails: WorkoutSessionDetails? = null,
    val canUndoDelete: Boolean = false,
    val personalRecordFlags: Map<Long, Boolean> = emptyMap(),
    val restSecondsRemaining: Int = 0,
    val availableExercisesToAdd: List<ExerciseEntity> = emptyList()
)

sealed interface WorkoutDetailEvent {
    data object SetDeleted : WorkoutDetailEvent
    data object InvalidInput : WorkoutDetailEvent
}

@OptIn(ExperimentalCoroutinesApi::class)
class WorkoutDetailViewModel(
    private val repository: GymRepository,
    private val sessionId: Long,
    private val restTimerController: RestTimerController
) : ViewModel() {
    private val sessionDetailsFlow = repository.observeSessionDetails(sessionId)
    private val allExercisesFlow = repository.observeExercises()
    private val deletedSetForUndo = MutableStateFlow<SetEntryEntity?>(null)
    private val personalRecordFlags = sessionDetailsFlow.mapLatest { details ->
        if (details == null) {
            emptyMap()
        } else {
            val flags = mutableMapOf<Long, Boolean>()
            details.workoutExercises.forEach { workoutExercise ->
                val maxWeightInSession = workoutExercise.sets.maxOfOrNull { it.weight } ?: 0.0
                val maxWeightBeforeSession = repository.getExerciseMaxWeightExcludingSession(
                    exerciseId = workoutExercise.workoutExercise.exerciseId,
                    sessionId = sessionId
                )
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

    val uiState: StateFlow<WorkoutDetailUiState> = combine(
        sessionDetailsFlow,
        deletedSetForUndo,
        personalRecordFlags,
        restTimerController.remainingSeconds,
        allExercisesFlow
    ) { details, deletedSet, prFlags, restSeconds, allExercises ->
        val selectedExerciseIds = details
            ?.workoutExercises
            ?.map { it.workoutExercise.exerciseId }
            ?.toSet()
            .orEmpty()
        WorkoutDetailUiState(
            sessionDetails = details,
            canUndoDelete = deletedSet != null,
            personalRecordFlags = prFlags,
            restSecondsRemaining = restSeconds,
            availableExercisesToAdd = allExercises.filterNot { it.id in selectedExerciseIds }
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WorkoutDetailUiState()
    )

    fun addSet(workoutExerciseId: Long) {
        viewModelScope.launch {
            val currentDetails = uiState.value.sessionDetails ?: return@launch
            val workoutExercise = currentDetails.workoutExercises
                .firstOrNull { it.workoutExercise.id == workoutExerciseId }
                ?: return@launch
            val existingSets = workoutExercise.sets
            val template = existingSets?.maxByOrNull { it.orderIndex }
            val historicalWeight = repository.getLastWeightBeforeDate(
                exerciseId = workoutExercise.workoutExercise.exerciseId,
                beforeDate = currentDetails.session.date
            )
            repository.addSet(
                workoutExerciseId = workoutExerciseId,
                weight = template?.weight ?: historicalWeight ?: 20.0,
                reps = template?.reps ?: 10
            )
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
        val parsedReps = reps.trim().toIntOrNull()
        if (parsedWeight == null || parsedReps == null || parsedWeight < 0.0 || parsedReps <= 0) {
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

    fun deleteSet(setEntry: SetEntryEntity) {
        viewModelScope.launch {
            deletedSetForUndo.value = setEntry
            repository.deleteSet(setEntry)
            _events.emit(WorkoutDetailEvent.SetDeleted)
        }
    }

    fun undoDeleteSet() {
        val setToRestore = deletedSetForUndo.value ?: return
        viewModelScope.launch {
            repository.insertSet(setToRestore)
            deletedSetForUndo.value = null
        }
    }

    fun startRestTimer(seconds: Int = DEFAULT_REST_SECONDS) {
        restTimerController.start(seconds)
    }

    fun stopRestTimer() {
        restTimerController.stop()
    }

    companion object {
        private const val DEFAULT_REST_SECONDS = 90

        fun factory(
            repository: GymRepository,
            sessionId: Long,
            restTimerController: RestTimerController
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                WorkoutDetailViewModel(
                    repository = repository,
                    sessionId = sessionId,
                    restTimerController = restTimerController
                )
            }
        }
    }
}

