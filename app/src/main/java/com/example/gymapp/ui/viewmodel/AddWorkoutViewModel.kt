package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.data.repository.WorkoutExerciseDraft
import com.example.gymapp.data.repository.WorkoutSetDraft
import com.example.gymapp.sync.PhoneSyncClient
import com.example.gymapp.util.parseWeightInputOrNull
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

data class WorkoutTemplatePreviewUiModel(
    val sessionId: Long,
    val date: Long,
    val exerciseCount: Int,
    val setCount: Int,
    val totalVolume: Double
)

data class AddWorkoutUiState(
    val workoutDate: Long = System.currentTimeMillis(),
    val note: String = "",
    val exercises: List<ExerciseEntity> = emptyList(),
    val exerciseDrafts: List<ExerciseInputState> = emptyList(),
    val lastWeights: Map<Long, Double?> = emptyMap(),
    val canRepeatFromLast: Boolean = false,
    val workoutTemplates: List<WorkoutTemplatePreviewUiModel> = emptyList(),
    val isTemplatePickerOpen: Boolean = false,
    val isTemplateLoading: Boolean = false,
    val isSyncingPlanToWatch: Boolean = false,
    val didSyncPlanToWatch: Boolean? = null,
    val isSaving: Boolean = false,
    val hasValidationError: Boolean = false,
    val createdSessionId: Long? = null
)

@OptIn(ExperimentalCoroutinesApi::class)
class AddWorkoutViewModel(
    private val repository: GymRepository,
    private val syncClient: PhoneSyncClient
) : androidx.lifecycle.ViewModel() {
    private data class TransientState(
        val isSyncingPlanToWatch: Boolean,
        val didSyncPlanToWatch: Boolean?,
        val isSaving: Boolean,
        val hasValidationError: Boolean,
        val createdSessionId: Long?
    )

    private data class LocalState(
        val note: String,
        val exerciseDrafts: List<ExerciseInputState>,
        val isTemplatePickerOpen: Boolean,
        val isTemplateLoading: Boolean,
        val isSyncingPlanToWatch: Boolean,
        val didSyncPlanToWatch: Boolean?,
        val isSaving: Boolean,
        val hasValidationError: Boolean,
        val createdSessionId: Long?
    )

    private data class EditorState(
        val note: String,
        val exerciseDrafts: List<ExerciseInputState>,
        val isTemplatePickerOpen: Boolean,
        val isTemplateLoading: Boolean
    )

    private var nextDraftId = 2L

    private val note = MutableStateFlow("")
    private val exerciseDrafts = MutableStateFlow(listOf(ExerciseInputState(draftId = 1L)))
    private val isTemplatePickerOpen = MutableStateFlow(false)
    private val isTemplateLoading = MutableStateFlow(false)
    private val isSyncingPlanToWatch = MutableStateFlow(false)
    private val didSyncPlanToWatch = MutableStateFlow<Boolean?>(null)
    private val isSaving = MutableStateFlow(false)
    private val hasValidationError = MutableStateFlow(false)
    private val createdSessionId = MutableStateFlow<Long?>(null)

    private val exercises = repository.observeExercises()
    private val workoutTemplates = repository.observeSessions().map { sessions ->
        sessions
            .take(60)
            .map { summary ->
                WorkoutTemplatePreviewUiModel(
                    sessionId = summary.session.id,
                    date = summary.session.date,
                    exerciseCount = summary.exerciseCount,
                    setCount = summary.setCount,
                    totalVolume = summary.totalVolume
                )
            }
    }

    private val selectedExerciseIds = exerciseDrafts.map { drafts ->
        drafts.mapNotNull { it.exerciseId }
    }

    private fun resetWatchPlanSyncResult() {
        didSyncPlanToWatch.value = null
    }

    private val lastWeights = selectedExerciseIds.flatMapLatest { ids ->
        repository.observeLastWeights(ids)
    }

    private val editorState = combine(
        note,
        exerciseDrafts,
        isTemplatePickerOpen,
        isTemplateLoading
    ) { noteValue, drafts, templatePickerOpen, templateLoading ->
        EditorState(
            note = noteValue,
            exerciseDrafts = drafts,
            isTemplatePickerOpen = templatePickerOpen,
            isTemplateLoading = templateLoading
        )
    }

    private val transientState = combine(
        isSyncingPlanToWatch,
        didSyncPlanToWatch,
        isSaving,
        hasValidationError,
        createdSessionId
    ) { syncingPlan, planSyncState, saving, validationError, createdId ->
        TransientState(
            isSyncingPlanToWatch = syncingPlan,
            didSyncPlanToWatch = planSyncState,
            isSaving = saving,
            hasValidationError = validationError,
            createdSessionId = createdId
        )
    }

    private val localState = combine(
        editorState,
        transientState
    ) { editor, transient ->
        LocalState(
            note = editor.note,
            exerciseDrafts = editor.exerciseDrafts,
            isTemplatePickerOpen = editor.isTemplatePickerOpen,
            isTemplateLoading = editor.isTemplateLoading,
            isSyncingPlanToWatch = transient.isSyncingPlanToWatch,
            didSyncPlanToWatch = transient.didSyncPlanToWatch,
            isSaving = transient.isSaving,
            hasValidationError = transient.hasValidationError,
            createdSessionId = transient.createdSessionId
        )
    }

    val uiState: StateFlow<AddWorkoutUiState> = combine(
        exercises,
        lastWeights,
        workoutTemplates,
        localState
    ) { exerciseList, lastWeightsMap, templates, local ->
        AddWorkoutUiState(
            note = local.note,
            exercises = exerciseList,
            exerciseDrafts = local.exerciseDrafts,
            lastWeights = lastWeightsMap,
            canRepeatFromLast = templates.isNotEmpty(),
            workoutTemplates = templates,
            isTemplatePickerOpen = local.isTemplatePickerOpen,
            isTemplateLoading = local.isTemplateLoading,
            isSyncingPlanToWatch = local.isSyncingPlanToWatch,
            didSyncPlanToWatch = local.didSyncPlanToWatch,
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
        resetWatchPlanSyncResult()
        note.value = value
    }

    fun addExerciseDraft() {
        resetWatchPlanSyncResult()
        exerciseDrafts.update { current ->
            current + ExerciseInputState(draftId = nextDraftId++)
        }
    }

    fun removeExerciseDraft(draftId: Long) {
        resetWatchPlanSyncResult()
        exerciseDrafts.update { current ->
            val updated = current.filterNot { it.draftId == draftId }
            if (updated.isEmpty()) listOf(ExerciseInputState(draftId = nextDraftId++)) else updated
        }
    }

    fun updateExerciseSelection(draftId: Long, exerciseId: Long) {
        hasValidationError.value = false
        resetWatchPlanSyncResult()
        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId == draftId) draft.copy(exerciseId = exerciseId) else draft
            }
        }
    }

    fun addSet(draftId: Long) {
        hasValidationError.value = false
        resetWatchPlanSyncResult()
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

    fun addSetFromPrevious(draftId: Long, weightDelta: Double = 0.0) {
        hasValidationError.value = false
        resetWatchPlanSyncResult()
        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId != draftId) {
                    draft
                } else {
                    val previousSet = draft.sets.lastOrNull() ?: SetInputState()
                    val nextWeight = when {
                        previousSet.weight.isBlank() -> ""
                        weightDelta == 0.0 -> previousSet.weight
                        else -> {
                            val parsedWeight = parseWeightInputOrNull(previousSet.weight)
                            if (parsedWeight == null) {
                                previousSet.weight
                            } else {
                                formatWeight((parsedWeight + weightDelta).coerceAtLeast(0.0))
                            }
                        }
                    }

                    draft.copy(
                        sets = draft.sets + previousSet.copy(weight = nextWeight)
                    )
                }
            }
        }
    }

    fun removeSet(draftId: Long, setIndex: Int) {
        resetWatchPlanSyncResult()
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
        resetWatchPlanSyncResult()
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
        resetWatchPlanSyncResult()
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

    fun syncPlanToWatch() {
        viewModelScope.launch {
            val namedSets = parseNamedDrafts(
                drafts = exerciseDrafts.value,
                exercises = uiState.value.exercises
            )
            if (namedSets.isEmpty()) {
                hasValidationError.value = true
                didSyncPlanToWatch.value = false
                return@launch
            }

            hasValidationError.value = false
            isSyncingPlanToWatch.value = true
            didSyncPlanToWatch.value = null

            runCatching {
                val exerciseCatalog = uiState.value.exercises.map { it.name }
                syncClient.pushWorkoutPlan(
                    sets = namedSets,
                    exerciseCatalog = exerciseCatalog
                )
            }.onSuccess {
                didSyncPlanToWatch.value = true
            }.onFailure {
                didSyncPlanToWatch.value = false
            }

            isSyncingPlanToWatch.value = false
        }
    }

    fun openWorkoutTemplatePicker() {
        isTemplatePickerOpen.value = true
    }

    fun closeWorkoutTemplatePicker() {
        isTemplatePickerOpen.value = false
    }

    fun copyWorkoutTemplate(sessionId: Long) {
        viewModelScope.launch {
            isTemplateLoading.value = true
            resetWatchPlanSyncResult()
            runCatching {
                repository.getWorkoutTemplate(sessionId)
            }.onSuccess { template ->
                if (template != null) {
                    applyWorkoutTemplate(template)
                    isTemplatePickerOpen.value = false
                }
            }.onFailure {
                hasValidationError.value = true
            }
            isTemplateLoading.value = false
        }
    }

    fun repeatLastWorkout() {
        viewModelScope.launch {
            isTemplateLoading.value = true
            resetWatchPlanSyncResult()
            val latestWorkout = repository.getLatestWorkoutTemplate()
            if (latestWorkout == null) {
                isTemplateLoading.value = false
                return@launch
            }

            applyWorkoutTemplate(latestWorkout)
            isTemplateLoading.value = false
        }
    }

    fun applyLastWeight(draftId: Long) {
        resetWatchPlanSyncResult()
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

    private fun applyWorkoutTemplate(template: WorkoutSessionDetails) {
        note.value = template.session.note.orEmpty()
        val drafts = template.workoutExercises.map { exerciseDetails ->
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
    }

    private fun parseDrafts(drafts: List<ExerciseInputState>): List<WorkoutExerciseDraft> {
        return drafts.mapNotNull { draft ->
            val exerciseId = draft.exerciseId ?: return@mapNotNull null
            val sets = draft.sets.mapNotNull { set ->
                val weight = parseWeightInputOrNull(set.weight)
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

    private fun parseNamedDrafts(
        drafts: List<ExerciseInputState>,
        exercises: List<ExerciseEntity>
    ): List<NamedWorkoutSetDraft> {
        val exerciseNameById = exercises.associate { it.id to it.name.trim() }
        val result = mutableListOf<NamedWorkoutSetDraft>()

        drafts.forEach { draft ->
            val exerciseId = draft.exerciseId ?: return@forEach
            val exerciseName = exerciseNameById[exerciseId].orEmpty()
            if (exerciseName.isBlank()) {
                return emptyList()
            }

            val sourceSets = if (draft.sets.isEmpty()) listOf(SetInputState()) else draft.sets
            val parsedSets = sourceSets.map { set ->
                val parsedWeight = parseWeightInputOrNull(set.weight)
                val parsedReps = set.reps.trim().toIntOrNull()
                val safeWeight = parsedWeight?.takeIf { it >= 0.0 } ?: 0.0
                val safeReps = parsedReps?.takeIf { it > 0 } ?: 1
                NamedWorkoutSetDraft(
                    exerciseName = exerciseName,
                    weight = safeWeight,
                    reps = safeReps
                )
            }

            if (parsedSets.isEmpty()) {
                result += NamedWorkoutSetDraft(
                    exerciseName = exerciseName,
                    weight = 0.0,
                    reps = 1
                )
            } else {
                result += parsedSets
            }
        }

        return result
    }

    private fun formatWeight(weight: Double): String {
        return if (weight % 1.0 == 0.0) {
            weight.toInt().toString()
        } else {
            String.format(java.util.Locale.US, "%.1f", weight)
        }
    }

    companion object {
        fun factory(
            repository: GymRepository,
            syncClient: PhoneSyncClient
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                AddWorkoutViewModel(
                    repository = repository,
                    syncClient = syncClient
                )
            }
        }
    }
}

