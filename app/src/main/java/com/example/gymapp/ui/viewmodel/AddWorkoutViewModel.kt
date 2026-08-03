package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.ExerciseLoadProfile
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.data.repository.WorkoutRecommendation
import com.example.gymapp.data.repository.WorkoutRecommendationEngine
import com.example.gymapp.data.repository.MuscleContribution
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.WorkoutExerciseDraft
import com.example.gymapp.data.repository.WorkoutSetDraft
import com.example.gymapp.sync.PhoneSyncClient
import com.example.gymapp.util.CalorieMode
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingProfileManager
import com.example.gymapp.util.TrainingSplit
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
    val frequentExerciseIds: List<Long> = emptyList(),
    val exerciseDrafts: List<ExerciseInputState> = emptyList(),
    val lastWeights: Map<Long, Double?> = emptyMap(),
    val workoutRecommendations: Map<Long, WorkoutRecommendation> = emptyMap(),
    val exerciseLoadProfiles: Map<Long, ExerciseLoadProfile> = emptyMap(),
    val trainingProfile: TrainingProfile = TrainingProfile(),
    val canRepeatFromLast: Boolean = false,
    val workoutTemplates: List<WorkoutTemplatePreviewUiModel> = emptyList(),
    val isTemplatePickerOpen: Boolean = false,
    val isTemplateLoading: Boolean = false,
    val isSyncingPlanToWatch: Boolean = false,
    val didSyncPlanToWatch: Boolean? = null,
    val watchPlanSyncError: LocalizedText? = null,
    val isSaving: Boolean = false,
    val hasValidationError: Boolean = false,
    val createdSessionId: Long? = null
)

internal fun planSyncErrorText(error: Throwable): LocalizedText {
    val message = error.message.orEmpty()
    val resource = when {
        message == "Workout plan is empty" -> R.string.message_workout_plan_empty
        message == "Workout plan is outside Garmin limits" ->
            R.string.message_plan_outside_garmin_limits
        message.contains("Garmin SDK", ignoreCase = true) ->
            R.string.message_garmin_sdk_not_ready
        message == "Sign in before Garmin sync" -> R.string.message_garmin_sign_in_required
        message.contains("account changed", ignoreCase = true) ->
            R.string.message_garmin_account_changed
        message.contains("account transition", ignoreCase = true) ||
            message.contains("previous Garmin account", ignoreCase = true) ||
            message.contains("trusted-device state conflicts", ignoreCase = true) ||
            message.contains("clear old account data", ignoreCase = true) ->
            R.string.message_garmin_reconnect_account_cleanup
        message.startsWith("Cannot persist", ignoreCase = true) ||
            message.contains("local state was not saved", ignoreCase = true) ->
            R.string.message_garmin_storage_failed
        message.contains("exactly one Garmin watch", ignoreCase = true) ->
            R.string.message_garmin_pair_one_watch
        message.contains("trusted Garmin", ignoreCase = true) ||
            message.contains("watch is not paired", ignoreCase = true) ->
            R.string.message_no_trusted_garmin_watch
        message.contains("sync_ack", ignoreCase = true) ->
            R.string.message_garmin_ack_missing
        message.startsWith("Send status", ignoreCase = true) ||
            message.contains("send to Garmin", ignoreCase = true) ||
            message == "Send timeout" -> R.string.message_garmin_send_failed
        else -> R.string.message_plan_sync_failed
    }
    return LocalizedText(resource)
}

@OptIn(ExperimentalCoroutinesApi::class)
class AddWorkoutViewModel(
    private val repository: GymRepository,
    private val syncClient: PhoneSyncClient,
    private val trainingProfileManager: TrainingProfileManager
) : androidx.lifecycle.ViewModel() {
    private data class TransientState(
        val isSyncingPlanToWatch: Boolean,
        val didSyncPlanToWatch: Boolean?,
        val watchPlanSyncError: LocalizedText?,
        val isSaving: Boolean,
        val hasValidationError: Boolean,
        val createdSessionId: Long?
    )

    private data class LocalState(
        val note: String,
        val exerciseDrafts: List<ExerciseInputState>,
        val trainingProfile: TrainingProfile,
        val isTemplatePickerOpen: Boolean,
        val isTemplateLoading: Boolean,
        val isSyncingPlanToWatch: Boolean,
        val didSyncPlanToWatch: Boolean?,
        val watchPlanSyncError: LocalizedText?,
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

    private data class ExerciseCatalogState(
        val exercises: List<ExerciseEntity>,
        val frequentExerciseIds: List<Long>,
        val loadProfiles: Map<Long, ExerciseLoadProfile>,
        val manualMuscleMappings: Map<String, List<MuscleContribution>>
    )

    private var nextDraftId = 2L

    private val note = MutableStateFlow("")
    private val exerciseDrafts = MutableStateFlow(listOf(ExerciseInputState(draftId = 1L)))
    private val isTemplatePickerOpen = MutableStateFlow(false)
    private val isTemplateLoading = MutableStateFlow(false)
    private val isSyncingPlanToWatch = MutableStateFlow(false)
    private val didSyncPlanToWatch = MutableStateFlow<Boolean?>(null)
    private val watchPlanSyncError = MutableStateFlow<LocalizedText?>(null)
    private val isSaving = MutableStateFlow(false)
    private val hasValidationError = MutableStateFlow(false)
    private val createdSessionId = MutableStateFlow<Long?>(null)

    private val exercises = repository.observeExercises()
    private val exerciseHistory: StateFlow<List<ExerciseHistoryEntry>> = repository.observeAllExerciseHistory()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.Eagerly,
            initialValue = emptyList()
        )
    private val exerciseCatalogState: StateFlow<ExerciseCatalogState> = combine(
        exercises,
        exerciseHistory,
        repository.observeExerciseLoadProfiles(),
        repository.observeExerciseMuscleMappings()
    ) { exerciseList, history, loadProfiles, muscleMappings ->
        val frequentIds = history
            .groupBy { it.exerciseId }
            .map { (exerciseId, entries) ->
                Triple(
                    exerciseId,
                    entries.map { it.sessionId }.distinct().size,
                    entries.maxOfOrNull { it.sessionDate } ?: Long.MIN_VALUE
                )
            }
            .sortedWith(
                compareByDescending<Triple<Long, Int, Long>> { it.second }
                    .thenByDescending { it.third }
                    .thenBy { it.first }
            )
            .take(12)
            .map { it.first }
        ExerciseCatalogState(
            exercises = exerciseList,
            frequentExerciseIds = frequentIds,
            loadProfiles = loadProfiles,
            manualMuscleMappings = muscleMappings.toManualContributionMap()
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.Eagerly,
        initialValue = ExerciseCatalogState(
            exercises = emptyList(),
            frequentExerciseIds = emptyList(),
            loadProfiles = emptyMap(),
            manualMuscleMappings = emptyMap()
        )
    )
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
        watchPlanSyncError.value = null
    }

    private val lastWeights = selectedExerciseIds.flatMapLatest { ids ->
        repository.observeLastWeights(ids)
    }

    private val workoutRecommendations = selectedExerciseIds.flatMapLatest { ids ->
        trainingProfileManager.profile.flatMapLatest { profile ->
            repository.observeWorkoutRecommendations(ids, profile)
        }
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

    private val planSyncResult = combine(
        didSyncPlanToWatch,
        watchPlanSyncError
    ) { planSyncState, planSyncError ->
        planSyncState to planSyncError
    }

    private val transientState = combine(
        isSyncingPlanToWatch,
        planSyncResult,
        isSaving,
        hasValidationError,
        createdSessionId
    ) { syncingPlan, planSyncResult, saving, validationError, createdId ->
        TransientState(
            isSyncingPlanToWatch = syncingPlan,
            didSyncPlanToWatch = planSyncResult.first,
            watchPlanSyncError = planSyncResult.second,
            isSaving = saving,
            hasValidationError = validationError,
            createdSessionId = createdId
        )
    }

    private val localState = combine(
        editorState,
        transientState,
        trainingProfileManager.profile
    ) { editor, transient, profile ->
        LocalState(
            note = editor.note,
            exerciseDrafts = editor.exerciseDrafts,
            trainingProfile = profile,
            isTemplatePickerOpen = editor.isTemplatePickerOpen,
            isTemplateLoading = editor.isTemplateLoading,
            isSyncingPlanToWatch = transient.isSyncingPlanToWatch,
            didSyncPlanToWatch = transient.didSyncPlanToWatch,
            watchPlanSyncError = transient.watchPlanSyncError,
            isSaving = transient.isSaving,
            hasValidationError = transient.hasValidationError,
            createdSessionId = transient.createdSessionId
        )
    }

    val uiState: StateFlow<AddWorkoutUiState> = combine(
        exerciseCatalogState,
        lastWeights,
        workoutRecommendations,
        workoutTemplates,
        localState
    ) { catalog, lastWeightsMap, recommendations, templates, local ->
        AddWorkoutUiState(
            note = local.note,
            exercises = catalog.exercises,
            frequentExerciseIds = catalog.frequentExerciseIds,
            exerciseDrafts = local.exerciseDrafts,
            lastWeights = lastWeightsMap,
            workoutRecommendations = recommendations,
            exerciseLoadProfiles = catalog.loadProfiles,
            trainingProfile = local.trainingProfile,
            canRepeatFromLast = templates.isNotEmpty(),
            workoutTemplates = templates,
            isTemplatePickerOpen = local.isTemplatePickerOpen,
            isTemplateLoading = local.isTemplateLoading,
            isSyncingPlanToWatch = local.isSyncingPlanToWatch,
            didSyncPlanToWatch = local.didSyncPlanToWatch,
            watchPlanSyncError = local.watchPlanSyncError,
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
        if (!WorkoutDataLimits.isValidNote(value)) {
            hasValidationError.value = true
            return
        }
        resetWatchPlanSyncResult()
        note.value = value
    }

    fun updateTrainingSplit(split: TrainingSplit) {
        resetWatchPlanSyncResult()
        trainingProfileManager.updateSplit(split)
    }

    fun updateWorkoutsPerWeek(value: Int) {
        resetWatchPlanSyncResult()
        trainingProfileManager.updateWorkoutsPerWeek(value)
    }

    fun updateTrainingGoal(goal: TrainingGoal) {
        resetWatchPlanSyncResult()
        trainingProfileManager.updateGoal(goal)
    }

    fun updateCalorieMode(mode: CalorieMode) {
        resetWatchPlanSyncResult()
        trainingProfileManager.updateCalorieMode(mode)
    }

    fun generateSmartWorkout(defaultNote: String) {
        val currentState = uiState.value
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = currentState.exercises,
            history = exerciseHistory.value,
            trainingProfile = currentState.trainingProfile,
            loadProfiles = currentState.exerciseLoadProfiles,
            manualMuscleMappings = exerciseCatalogState.value.manualMuscleMappings
        )
        if (plan.exercises.isEmpty()) {
            hasValidationError.value = true
            return
        }

        resetWatchPlanSyncResult()
        hasValidationError.value = false
        exerciseDrafts.value = plan.exercises.map { plannedExercise ->
            ExerciseInputState(
                draftId = nextDraftId++,
                exerciseId = plannedExercise.exercise.id,
                sets = plannedExercise.recommendation.sets.map { set ->
                    SetInputState(
                        weight = set.weight?.let(::formatWeight).orEmpty(),
                        reps = set.reps.toString()
                    )
                }
            )
        }
        if (note.value.isBlank()) {
            note.value = defaultNote
        }
    }

    fun addExerciseDraft() {
        resetWatchPlanSyncResult()
        exerciseDrafts.update { current ->
            if (current.size >= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
                hasValidationError.value = true
                current
            } else {
                listOf(ExerciseInputState(draftId = nextDraftId++)) + current
            }
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
                    if (draft.sets.size >= WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                        hasValidationError.value = true
                        return@map draft
                    }
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
                    if (draft.sets.size >= WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                        hasValidationError.value = true
                        return@map draft
                    }
                    val previousSet = draft.sets.lastOrNull() ?: SetInputState()
                    val nextWeight = when {
                        previousSet.weight.isBlank() -> ""
                        weightDelta == 0.0 -> previousSet.weight
                        else -> {
                            val parsedWeight = parseWeightInputOrNull(previousSet.weight)
                            if (parsedWeight == null) {
                                previousSet.weight
                            } else {
                                val loadProfile = draft.exerciseId?.let {
                                    uiState.value.exerciseLoadProfiles[it]
                                }
                                val adjusted = when {
                                    loadProfile == null ->
                                        (parsedWeight + weightDelta).coerceAtLeast(0.0)
                                    weightDelta > 0.0 ->
                                        loadProfile.allowedWeightsKg.firstOrNull { it > parsedWeight }
                                            ?: parsedWeight
                                    else ->
                                        loadProfile.allowedWeightsKg.lastOrNull { it < parsedWeight }
                                            ?: parsedWeight
                                }
                                if (WorkoutDataLimits.isValidWeight(adjusted)) {
                                    formatWeight(adjusted)
                                } else {
                                    previousSet.weight
                                }
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
        if (value.length > MAX_WEIGHT_INPUT_LENGTH) {
            hasValidationError.value = true
            return
        }
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
        if (value.length > MAX_REPS_INPUT_LENGTH) {
            hasValidationError.value = true
            return
        }
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
            if (parsedExercises.isEmpty() || !WorkoutDataLimits.isValidNote(note.value)) {
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
                watchPlanSyncError.value = LocalizedText(R.string.message_workout_plan_empty)
                return@launch
            }

            hasValidationError.value = false
            isSyncingPlanToWatch.value = true
            didSyncPlanToWatch.value = null
            watchPlanSyncError.value = null

            runCatching {
                val exerciseCatalog = uiState.value.exercises.map { it.name }
                syncClient.pushWorkoutPlan(
                    sets = namedSets,
                    exerciseCatalog = exerciseCatalog,
                    trainingProfile = uiState.value.trainingProfile
                )
            }.onSuccess {
                didSyncPlanToWatch.value = true
                watchPlanSyncError.value = null
            }.onFailure { error ->
                didSyncPlanToWatch.value = false
                watchPlanSyncError.value = planSyncErrorText(error)
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
        if (drafts.size > WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) return emptyList()
        val result = mutableListOf<WorkoutExerciseDraft>()
        drafts.forEach { draft ->
            val exerciseId = draft.exerciseId ?: return@forEach
            if (draft.sets.isEmpty() || draft.sets.size > WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                return emptyList()
            }
            val sets = mutableListOf<WorkoutSetDraft>()
            draft.sets.forEach { set ->
                val weight = parseWeightInputOrNull(set.weight)
                val repsInput = set.reps.trim()
                val reps = repsInput.takeIf { it.length <= MAX_REPS_INPUT_LENGTH }?.toIntOrNull()
                if (weight == null || reps == null ||
                    !WorkoutDataLimits.isValidWeight(weight) || !WorkoutDataLimits.isValidReps(reps)
                ) {
                    return emptyList()
                }
                sets += WorkoutSetDraft(weight = weight, reps = reps)
            }
            result += WorkoutExerciseDraft(exerciseId = exerciseId, sets = sets)
        }
        return result
    }

    fun applyWorkoutRecommendation(draftId: Long) {
        hasValidationError.value = false
        resetWatchPlanSyncResult()
        val draftsSnapshot = uiState.value.exerciseDrafts
        val selectedExerciseId = draftsSnapshot.firstOrNull { it.draftId == draftId }?.exerciseId ?: return
        val recommendation = uiState.value.workoutRecommendations[selectedExerciseId] ?: return

        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId == draftId) {
                    draft.copy(
                        sets = recommendation.sets.map { set ->
                            SetInputState(
                                weight = set.weight?.let(::formatWeight).orEmpty(),
                                reps = set.reps.toString()
                            )
                        }
                    )
                } else {
                    draft
                }
            }
        }
    }

    private fun parseNamedDrafts(
        drafts: List<ExerciseInputState>,
        exercises: List<ExerciseEntity>
    ): List<NamedWorkoutSetDraft> {
        if (drafts.size > WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) return emptyList()
        val exerciseNameById = exercises.associate { it.id to it.name.trim() }
        val result = mutableListOf<NamedWorkoutSetDraft>()

        drafts.forEach { draft ->
            val exerciseId = draft.exerciseId ?: return@forEach
            val exerciseName = exerciseNameById[exerciseId].orEmpty()
            if (!WorkoutDataLimits.isValidExerciseName(exerciseName)) {
                return emptyList()
            }

            if (draft.sets.isEmpty() || draft.sets.size > WorkoutDataLimits.MAX_SETS_PER_EXERCISE) {
                return emptyList()
            }
            val sourceSets = draft.sets
            val parsedSets = sourceSets.map { set ->
                val parsedWeight = parseWeightInputOrNull(set.weight)
                val repsInput = set.reps.trim()
                val parsedReps = repsInput.takeIf { it.length <= MAX_REPS_INPUT_LENGTH }?.toIntOrNull()
                if (parsedWeight == null || parsedReps == null ||
                    !WorkoutDataLimits.isValidWeight(parsedWeight) ||
                    !WorkoutDataLimits.isValidReps(parsedReps)
                ) {
                    return emptyList()
                }
                NamedWorkoutSetDraft(
                    exerciseName = exerciseName,
                    weight = parsedWeight,
                    reps = parsedReps
                )
            }

            result += parsedSets
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
        private const val MAX_WEIGHT_INPUT_LENGTH = 64
        private const val MAX_REPS_INPUT_LENGTH = 10

        fun factory(
            repository: GymRepository,
            syncClient: PhoneSyncClient,
            trainingProfileManager: TrainingProfileManager
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                AddWorkoutViewModel(
                    repository = repository,
                    syncClient = syncClient,
                    trainingProfileManager = trainingProfileManager
                )
            }
        }
    }
}
