package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.WorkoutExerciseDraft
import com.example.gymapp.data.repository.WorkoutSetDraft
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SetInputState(
    val weight: String = "",
    val reps: String = ""
)

data class ExerciseInputState(
    val draftId: Long,
    val exerciseId: Long? = null,
    val sets: List<SetInputState> = listOf(SetInputState())
)

data class AddWorkoutUiState(
    val workoutDate: Long = System.currentTimeMillis(),
    val note: String = "",
    val exercises: List<ExerciseEntity> = emptyList(),
    val exerciseDrafts: List<ExerciseInputState> = emptyList(),
    val lastWeights: Map<Long, Double?> = emptyMap(),
    val canRepeatFromLast: Boolean = false,
    val isTemplateLoading: Boolean = false,
    val isSaving: Boolean = false,
    val hasValidationError: Boolean = false,
    val createdSessionId: Long? = null
)

@OptIn(ExperimentalCoroutinesApi::class)
class AddWorkoutViewModel(
    private val repository: GymRepository
) : ViewModel() {
    private data class LocalState(
        val note: String,
        val exerciseDrafts: List<ExerciseInputState>,
        val isTemplateLoading: Boolean,
        val isSaving: Boolean,
        val hasValidationError: Boolean,
        val createdSessionId: Long?
    )

    private var nextDraftId = 2L

    private val note = MutableStateFlow("")
    private val exerciseDrafts = MutableStateFlow(listOf(ExerciseInputState(draftId = 1L)))
    private val isTemplateLoading = MutableStateFlow(false)
    private val isSaving = MutableStateFlow(false)
    private val hasValidationError = MutableStateFlow(false)
    private val createdSessionId = MutableStateFlow<Long?>(null)

    private val exercises = repository.observeExercises()
    private val hasPreviousWorkouts = repository.observeSessions().map { sessions ->
        sessions.isNotEmpty()
    }

    private val selectedExerciseIds = exerciseDrafts.map { drafts ->
        drafts.mapNotNull { it.exerciseId }
    }

    private val lastWeights = selectedExerciseIds.flatMapLatest { ids ->
        repository.observeLastWeights(ids)
    }

    private val editorState = combine(
        note,
        exerciseDrafts,
        isTemplateLoading
    ) { noteValue, drafts, templateLoading ->
        Triple(noteValue, drafts, templateLoading)
    }

    private val localState = combine(
        editorState,
        isSaving,
        hasValidationError,
        createdSessionId
    ) { editor, saving, validationError, createdId ->
        LocalState(
            note = editor.first,
            exerciseDrafts = editor.second,
            isTemplateLoading = editor.third,
            isSaving = saving,
            hasValidationError = validationError,
            createdSessionId = createdId
        )
    }

    val uiState: StateFlow<AddWorkoutUiState> = combine(
        exercises,
        lastWeights,
        hasPreviousWorkouts,
        localState
    ) { exerciseList, lastWeightsMap, canRepeat, local ->
        AddWorkoutUiState(
            note = local.note,
            exercises = exerciseList,
            exerciseDrafts = local.exerciseDrafts,
            lastWeights = lastWeightsMap,
            canRepeatFromLast = canRepeat,
            isTemplateLoading = local.isTemplateLoading,
            isSaving = local.isSaving,
            hasValidationError = local.hasValidationError,
            createdSessionId = local.createdSessionId
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = AddWorkoutUiState(exerciseDrafts = listOf(ExerciseInputState(draftId = 1L)))
    )

    fun updateNote(value: String) {
        note.value = value
    }

    fun addExerciseDraft() {
        exerciseDrafts.update { current ->
            current + ExerciseInputState(draftId = nextDraftId++)
        }
    }

    fun removeExerciseDraft(draftId: Long) {
        exerciseDrafts.update { current ->
            val updated = current.filterNot { it.draftId == draftId }
            if (updated.isEmpty()) listOf(ExerciseInputState(draftId = nextDraftId++)) else updated
        }
    }

    fun updateExerciseSelection(draftId: Long, exerciseId: Long) {
        hasValidationError.value = false
        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId == draftId) draft.copy(exerciseId = exerciseId) else draft
            }
        }
    }

    fun addSet(draftId: Long) {
        hasValidationError.value = false
        val lastWeightsSnapshot = uiState.value.lastWeights
        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId == draftId) {
                    val lastWeight = draft.exerciseId?.let { lastWeightsSnapshot[it] }
                    draft.copy(
                        sets = draft.sets + SetInputState(
                            weight = lastWeight?.let(::formatWeight).orEmpty()
                        )
                    )
                } else {
                    draft
                }
            }
        }
    }

    fun removeSet(draftId: Long, setIndex: Int) {
        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId != draftId) {
                    draft
                } else {
                    val updatedSets = draft.sets.filterIndexed { index, _ -> index != setIndex }
                    draft.copy(sets = if (updatedSets.isEmpty()) listOf(SetInputState()) else updatedSets)
                }
            }
        }
    }

    fun updateSetWeight(draftId: Long, setIndex: Int, value: String) {
        hasValidationError.value = false
        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId == draftId) {
                    val updatedSets = draft.sets.mapIndexed { index, set ->
                        if (index == setIndex) set.copy(weight = value) else set
                    }
                    draft.copy(sets = updatedSets)
                } else {
                    draft
                }
            }
        }
    }

    fun updateSetReps(draftId: Long, setIndex: Int, value: String) {
        hasValidationError.value = false
        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId == draftId) {
                    val updatedSets = draft.sets.mapIndexed { index, set ->
                        if (index == setIndex) set.copy(reps = value) else set
                    }
                    draft.copy(sets = updatedSets)
                } else {
                    draft
                }
            }
        }
    }

    fun saveWorkout() {
        viewModelScope.launch {
            val parsedExercises = parseDrafts(exerciseDrafts.value)
            if (parsedExercises.isEmpty()) {
                hasValidationError.value = true
                return@launch
            }

            isSaving.value = true
            hasValidationError.value = false

            runCatching {
                repository.createWorkoutSession(
                    date = System.currentTimeMillis(),
                    note = note.value,
                    workoutExercises = parsedExercises
                )
            }.onSuccess { sessionId ->
                createdSessionId.value = sessionId
            }.onFailure {
                hasValidationError.value = true
            }

            isSaving.value = false
        }
    }

    fun repeatLastWorkout() {
        viewModelScope.launch {
            isTemplateLoading.value = true
            val latestWorkout = repository.getLatestWorkoutTemplate()
            if (latestWorkout == null) {
                isTemplateLoading.value = false
                return@launch
            }

            note.value = latestWorkout.session.note.orEmpty()
            val drafts = latestWorkout.workoutExercises.map { exerciseDetails ->
                val mappedSets = exerciseDetails.sets.map { set ->
                    SetInputState(
                        weight = formatWeight(set.weight),
                        reps = set.reps.toString()
                    )
                }
                ExerciseInputState(
                    draftId = nextDraftId++,
                    exerciseId = exerciseDetails.workoutExercise.exerciseId,
                    sets = if (mappedSets.isEmpty()) listOf(SetInputState()) else mappedSets
                )
            }

            exerciseDrafts.value = if (drafts.isEmpty()) {
                listOf(ExerciseInputState(draftId = nextDraftId++))
            } else {
                drafts
            }
            hasValidationError.value = false
            isTemplateLoading.value = false
        }
    }

    fun applyLastWeight(draftId: Long) {
        val draftsSnapshot = uiState.value.exerciseDrafts
        val selectedExerciseId = draftsSnapshot.firstOrNull { it.draftId == draftId }?.exerciseId ?: return
        val lastWeight = uiState.value.lastWeights[selectedExerciseId] ?: return
        val formattedWeight = formatWeight(lastWeight)

        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId == draftId) {
                    draft.copy(
                        sets = draft.sets.map { set ->
                            if (set.weight.isBlank()) set.copy(weight = formattedWeight) else set
                        }
                    )
                } else {
                    draft
                }
            }
        }
    }

    fun consumeCreatedSession() {
        createdSessionId.value = null
    }

    private fun parseDrafts(drafts: List<ExerciseInputState>): List<WorkoutExerciseDraft> {
        return drafts.mapNotNull { draft ->
            val exerciseId = draft.exerciseId ?: return@mapNotNull null
            val sets = draft.sets.mapNotNull { set ->
                val weightText = set.weight.trim()
                val weight = if (weightText.isBlank()) 0.0 else weightText.toDoubleOrNull()
                val reps = set.reps.trim().toIntOrNull()
                if (weight == null || reps == null || weight < 0.0 || reps <= 0) {
                    null
                } else {
                    WorkoutSetDraft(weight = weight, reps = reps)
                }
            }

            if (sets.isEmpty()) {
                null
            } else {
                WorkoutExerciseDraft(
                    exerciseId = exerciseId,
                    sets = sets
                )
            }
        }
    }

    private fun formatWeight(weight: Double): String {
        return if (weight % 1.0 == 0.0) {
            weight.toInt().toString()
        } else {
            String.format(java.util.Locale.US, "%.1f", weight)
        }
    }

    companion object {
        fun factory(repository: GymRepository): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                AddWorkoutViewModel(repository)
            }
        }
    }
}

