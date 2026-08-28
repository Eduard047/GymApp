package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.StartActiveWorkoutResult
import com.example.gymapp.data.repository.ExerciseLoadProfile
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.data.repository.WorkoutRecommendation
import com.example.gymapp.data.repository.WorkoutRecommendationEngine
import com.example.gymapp.data.repository.SmartWorkoutAlternative
import com.example.gymapp.data.repository.SmartWorkoutLaunchPlan
import com.example.gymapp.data.repository.SmartWorkoutEffort
import com.example.gymapp.data.repository.SmartWorkoutEffortAdjustment
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.SmartWorkoutVariant
import com.example.gymapp.data.repository.SharedWorkoutLink
import com.example.gymapp.data.repository.SharedWorkoutExercise
import com.example.gymapp.data.repository.SharedWorkoutPlan
import com.example.gymapp.data.repository.SharedWorkoutSet
import com.example.gymapp.data.repository.MuscleContribution
import com.example.gymapp.data.repository.defaultContributionsForExercise
import com.example.gymapp.data.repository.normalizedExerciseName
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.time.DateTimeException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject

data class SetInputState(
    val weight: String = "",
    val reps: String = ""
)

data class ExerciseInputState(
    val draftId: Long,
    val exerciseId: Long? = null,
    val sets: List<SetInputState> = listOf(SetInputState())
)

internal fun watchPlanSyncResultIsCurrent(
    capturedGeneration: Long,
    currentGeneration: Long
): Boolean = capturedGeneration == currentGeneration

internal fun buildSharedWorkoutDraftUrl(
    drafts: List<ExerciseInputState>,
    exercises: List<ExerciseEntity>
): String = SharedWorkoutLink.buildUrl(
    buildSharedWorkoutDraftPlan(drafts, exercises).exercises
)

internal fun buildSharedWorkoutDraftPlan(
    drafts: List<ExerciseInputState>,
    exercises: List<ExerciseEntity>
): SharedWorkoutPlan {
    val selectedDrafts = drafts.filter { it.exerciseId != null }
    require(selectedDrafts.size in 1..SharedWorkoutLink.MAX_EXERCISES) {
        "Shared workout exercise count is invalid."
    }
    val exercisesById = exercises.associateBy(ExerciseEntity::id)
    var totalSetCount = 0
    val sharedExercises = selectedDrafts.map { draft ->
        val exerciseId = requireNotNull(draft.exerciseId)
        val exercise = requireNotNull(exercisesById[exerciseId]) {
            "Shared workout exercise is unavailable."
        }
        require(draft.sets.size in 1..SharedWorkoutLink.MAX_SETS_PER_EXERCISE) {
            "Shared workout set count is invalid."
        }
        totalSetCount += draft.sets.size
        require(totalSetCount <= SharedWorkoutLink.MAX_TOTAL_SETS) {
            "Shared workout contains too many sets."
        }

        SharedWorkoutExercise(
            catalogKey = BuiltInExerciseCatalog.inferKey(exercise.name),
            name = exercise.name,
            sets = draft.sets.map { set ->
                val weight = parseWeightInputOrNull(set.weight)
                val repsText = set.reps.trim()
                val reps = repsText
                    .takeIf { it.length <= SHARED_WORKOUT_REPS_INPUT_MAX_LENGTH }
                    ?.toIntOrNull()
                require(
                    weight != null &&
                        reps != null &&
                        WorkoutDataLimits.isValidWeight(weight) &&
                        WorkoutDataLimits.isValidReps(reps)
                ) { "Shared workout set is invalid." }
                SharedWorkoutSet(weight = weight, reps = reps)
            }
        )
    }
    return SharedWorkoutLink.normalize(sharedExercises)
}

internal fun normalizeSharedWorkoutPlanForDraftImport(plan: SharedWorkoutPlan): SharedWorkoutPlan =
    SharedWorkoutLink.normalize(plan.exercises)

internal fun smartWorkoutWeightInput(weight: Double?): String {
    val resolved = weight ?: 0.0
    require(WorkoutDataLimits.isValidWeight(resolved))
    return if (resolved % 1.0 == 0.0) {
        resolved.toInt().toString()
    } else {
        String.format(java.util.Locale.US, "%.1f", resolved)
    }
}

private const val SHARED_WORKOUT_REPS_INPUT_MAX_LENGTH = 10

data class WorkoutTemplatePreviewUiModel(
    val sessionId: Long,
    val date: Long,
    val exerciseCount: Int,
    val setCount: Int,
    val totalVolume: Double
)

data class SmartWorkoutPlanSummaryUiModel(
    val focus: SmartWorkoutFocus,
    val variant: SmartWorkoutVariant,
    val requestedEffort: SmartWorkoutEffort,
    val appliedEffort: SmartWorkoutEffort,
    val effortAdjustment: SmartWorkoutEffortAdjustment?,
    val hardExerciseIds: Set<Long> = emptySet(),
    val trainingProfileSnapshot: TrainingProfile = TrainingProfile()
)

internal data class SmartWorkoutRecommendationPolicy(
    val effort: SmartWorkoutEffort,
    val hardExerciseIds: Set<Long>
)

internal fun smartWorkoutRecommendationPolicy(
    selectedEffort: SmartWorkoutEffort,
    currentProfile: TrainingProfile,
    generatedPlan: SmartWorkoutPlanSummaryUiModel?
): SmartWorkoutRecommendationPolicy {
    if (generatedPlan == null || generatedPlan.requestedEffort != selectedEffort ||
        generatedPlan.trainingProfileSnapshot != currentProfile
    ) {
        // Choosing a chip configures the next generated plan. It must not silently turn a
        // manually assembled draft into a hard or recovery session before generation.
        return SmartWorkoutRecommendationPolicy(
            effort = SmartWorkoutEffort.Standard,
            hardExerciseIds = emptySet()
        )
    }
    return SmartWorkoutRecommendationPolicy(
        effort = generatedPlan.appliedEffort,
        hardExerciseIds = if (generatedPlan.appliedEffort == SmartWorkoutEffort.Hard) {
            generatedPlan.hardExerciseIds
        } else {
            emptySet()
        }
    )
}

internal fun smartWorkoutPlanNeedsRefresh(
    selectedEffort: SmartWorkoutEffort,
    currentProfile: TrainingProfile,
    generatedPlan: SmartWorkoutPlanSummaryUiModel?
): Boolean = generatedPlan != null && (
    generatedPlan.requestedEffort != selectedEffort ||
        generatedPlan.trainingProfileSnapshot != currentProfile
    )

internal fun resolveWorkoutDateSelection(
    currentTimestamp: Long,
    selectedEpochDay: Long,
    nowMillis: Long = System.currentTimeMillis(),
    zoneId: ZoneId = ZoneId.systemDefault()
): Long? {
    if (!WorkoutDataLimits.isValidTimestamp(currentTimestamp) ||
        !WorkoutDataLimits.isValidTimestamp(nowMillis)
    ) {
        return null
    }
    val selectedDate = try {
        LocalDate.ofEpochDay(selectedEpochDay)
    } catch (_: DateTimeException) {
        return null
    }
    val today = Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDate()
    if (selectedDate > today) return null

    val currentTime = Instant.ofEpochMilli(currentTimestamp).atZone(zoneId).toLocalTime()
    val selectedTimestamp = try {
        selectedDate.atTime(currentTime).atZone(zoneId).toInstant().toEpochMilli()
    } catch (_: DateTimeException) {
        return null
    }
    if (!WorkoutDataLimits.isValidTimestamp(selectedTimestamp)) return null
    return if (selectedDate == today) minOf(selectedTimestamp, nowMillis) else selectedTimestamp
}

internal fun isSelectableWorkoutTimestamp(
    timestamp: Long,
    nowMillis: Long = System.currentTimeMillis(),
    zoneId: ZoneId = ZoneId.systemDefault()
): Boolean {
    if (!WorkoutDataLimits.isValidTimestamp(timestamp) ||
        !WorkoutDataLimits.isValidTimestamp(nowMillis)
    ) {
        return false
    }
    val selectedDate = Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate()
    val today = Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDate()
    return selectedDate <= today
}

data class SmartWorkoutAlternativePickerUiState(
    val draftId: Long,
    val expectedExerciseId: Long,
    val selectedExerciseIdsSnapshot: Set<Long>,
    val alternatives: List<SmartWorkoutAlternative>
)

data class AddWorkoutUiState(
    val workoutDate: Long = System.currentTimeMillis(),
    val note: String = "",
    val exercises: List<ExerciseEntity> = emptyList(),
    val frequentExerciseIds: List<Long> = emptyList(),
    val exerciseWorkoutCounts: Map<Long, Int> = emptyMap(),
    val exerciseMuscleIds: Map<String, Set<String>> = emptyMap(),
    val exerciseDrafts: List<ExerciseInputState> = emptyList(),
    val lastWeights: Map<Long, Double?> = emptyMap(),
    val workoutRecommendations: Map<Long, WorkoutRecommendation> = emptyMap(),
    val exerciseLoadProfiles: Map<Long, ExerciseLoadProfile> = emptyMap(),
    val trainingProfile: TrainingProfile = TrainingProfile(),
    val smartWorkoutEffort: SmartWorkoutEffort = SmartWorkoutEffort.Auto,
    val generatedSmartPlan: SmartWorkoutPlanSummaryUiModel? = null,
    val generatedSmartPlanNeedsRefresh: Boolean = false,
    val smartAlternativePicker: SmartWorkoutAlternativePickerUiState? = null,
    val canRepeatFromLast: Boolean = false,
    val workoutTemplates: List<WorkoutTemplatePreviewUiModel> = emptyList(),
    val isTemplatePickerOpen: Boolean = false,
    val isTemplateLoading: Boolean = false,
    val isSyncingPlanToWatch: Boolean = false,
    val didSyncPlanToWatch: Boolean? = null,
    val watchPlanSyncError: LocalizedText? = null,
    val isSaving: Boolean = false,
    val hasValidationError: Boolean = false,
    val isDirty: Boolean = false,
    val activeWorkoutStarted: Boolean = false
)

internal data class RetainedWorkoutDraftFingerprint(
    val workoutDate: Long,
    val note: String,
    val exerciseDrafts: List<ExerciseInputState>,
    val smartWorkoutEffort: SmartWorkoutEffort,
    val generatedSmartPlan: SmartWorkoutPlanSummaryUiModel?,
    val isDirty: Boolean
)

internal fun retainedWorkoutDraftFingerprint(state: AddWorkoutUiState) =
    RetainedWorkoutDraftFingerprint(
        workoutDate = state.workoutDate,
        note = state.note,
        exerciseDrafts = state.exerciseDrafts,
        smartWorkoutEffort = state.smartWorkoutEffort,
        generatedSmartPlan = state.generatedSmartPlan,
        isDirty = state.isDirty
    )

internal fun liveSendMayDiscardRetainedWorkoutDraft(
    expected: RetainedWorkoutDraftFingerprint,
    current: RetainedWorkoutDraftFingerprint
): Boolean = expected == current

internal fun RetainedWorkoutDraftFingerprint.durableDigest(): String {
    val writer = WorkoutDraftDigestWriter(MessageDigest.getInstance("SHA-256"))
    writer.string("GymAppRetainedWorkoutDraftV1")
    writer.long(workoutDate)
    writer.string(note)
    writer.int(exerciseDrafts.size)
    exerciseDrafts.forEach { draft ->
        writer.long(draft.draftId)
        writer.nullableLong(draft.exerciseId)
        writer.int(draft.sets.size)
        draft.sets.forEach { set ->
            writer.string(set.weight)
            writer.string(set.reps)
        }
    }
    writer.string(smartWorkoutEffort.name)
    writer.boolean(generatedSmartPlan != null)
    generatedSmartPlan?.let { plan ->
        writer.string(plan.focus.name)
        writer.string(plan.variant.name)
        writer.string(plan.requestedEffort.name)
        writer.string(plan.appliedEffort.name)
        writer.nullableString(plan.effortAdjustment?.name)
        writer.int(plan.hardExerciseIds.size)
        plan.hardExerciseIds.sorted().forEach(writer::long)
        writer.string(plan.trainingProfileSnapshot.split.name)
        writer.int(plan.trainingProfileSnapshot.workoutsPerWeek)
        writer.string(plan.trainingProfileSnapshot.goal.name)
        writer.string(plan.trainingProfileSnapshot.calorieMode.name)
    }
    writer.boolean(isDirty)
    return writer.finish()
}

private class WorkoutDraftDigestWriter(
    private val digest: MessageDigest
) {
    fun boolean(value: Boolean) = int(if (value) 1 else 0)

    fun int(value: Int) {
        digest.update(ByteBuffer.allocate(Int.SIZE_BYTES).putInt(value).array())
    }

    fun long(value: Long) {
        digest.update(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(value).array())
    }

    fun nullableLong(value: Long?) {
        boolean(value != null)
        value?.let(::long)
    }

    fun nullableString(value: String?) {
        boolean(value != null)
        value?.let(::string)
    }

    fun string(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        int(bytes.size)
        digest.update(bytes)
    }

    fun finish(): String = digest.digest().joinToString(separator = "") { byte ->
        "%02x".format(byte)
    }
}

internal fun hasRetainedWorkoutDraft(state: AddWorkoutUiState): Boolean =
    state.isDirty || state.exerciseDrafts.isNotEmpty() || state.note.isNotBlank()

private data class PersistedWorkoutPlanDraft(
    val workoutDate: Long,
    val note: String,
    val exerciseDrafts: List<ExerciseInputState>,
    val smartWorkoutEffort: SmartWorkoutEffort,
    val isDirty: Boolean
)

private fun JSONObject.exactKeySet(): Set<String> = keys().asSequence().toSet()

private fun PersistedWorkoutPlanDraft.toJson(): String = JSONObject()
    .put("schemaVersion", 1)
    .put("workoutDate", workoutDate)
    .put("note", note)
    .put("smartWorkoutEffort", smartWorkoutEffort.name)
    .put("isDirty", isDirty)
    .put("exercises", JSONArray().apply {
        exerciseDrafts.forEach { draft ->
            put(JSONObject()
                .put("draftId", draft.draftId)
                .put("exerciseId", draft.exerciseId)
                .put("sets", JSONArray().apply {
                    draft.sets.forEach { set ->
                        put(JSONObject().put("weight", set.weight).put("reps", set.reps))
                    }
                }))
        }
    })
    .toString()

private fun parsePersistedWorkoutPlanDraft(payload: String): PersistedWorkoutPlanDraft? =
    runCatching {
        require(payload.toByteArray(Charsets.UTF_8).size <= 256 * 1_024)
        val root = JSONObject(payload)
        require(root.exactKeySet() == setOf(
            "schemaVersion", "workoutDate", "note", "smartWorkoutEffort", "isDirty", "exercises"
        ))
        require(root.getInt("schemaVersion") == 1)
        val date = root.getLong("workoutDate")
        require(WorkoutDataLimits.isValidTimestamp(date))
        val note = root.getString("note")
        require(WorkoutDataLimits.isValidNote(note))
        val effort = SmartWorkoutEffort.valueOf(root.getString("smartWorkoutEffort"))
        val rawExercises = root.getJSONArray("exercises")
        require(rawExercises.length() <= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION)
        val usedDraftIds = hashSetOf<Long>()
        val exercises = List(rawExercises.length()) { exerciseIndex ->
            val rawExercise = rawExercises.getJSONObject(exerciseIndex)
            require(rawExercise.exactKeySet() == setOf("draftId", "exerciseId", "sets"))
            val draftId = rawExercise.getLong("draftId")
            require(draftId > 0L && usedDraftIds.add(draftId))
            val exerciseId = if (rawExercise.isNull("exerciseId")) null else {
                rawExercise.getLong("exerciseId").also { require(it > 0L) }
            }
            val rawSets = rawExercise.getJSONArray("sets")
            require(rawSets.length() in 1..WorkoutDataLimits.MAX_SETS_PER_EXERCISE)
            ExerciseInputState(
                draftId = draftId,
                exerciseId = exerciseId,
                sets = List(rawSets.length()) { setIndex ->
                    val rawSet = rawSets.getJSONObject(setIndex)
                    require(rawSet.exactKeySet() == setOf("weight", "reps"))
                    val weight = rawSet.getString("weight")
                    val reps = rawSet.getString("reps")
                    require(weight.length <= 64 && reps.length <= 10)
                    SetInputState(weight = weight, reps = reps)
                }
            )
        }
        PersistedWorkoutPlanDraft(
            workoutDate = date,
            note = note,
            exerciseDrafts = exercises,
            smartWorkoutEffort = effort,
            isDirty = root.getBoolean("isDirty")
        )
    }.getOrNull()

internal fun canHydrateLaunchPlanIntoDraft(state: AddWorkoutUiState): Boolean =
    !hasRetainedWorkoutDraft(state)

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

@OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)
class AddWorkoutViewModel internal constructor(
    private val repository: GymRepository,
    private val syncClient: PhoneSyncClient,
    private val trainingProfileManager: TrainingProfileManager,
    private val launchToken: String? = null,
    private val launchPlanHandoff: suspend (
        String,
        (SmartWorkoutLaunchPlan) -> Boolean,
        (SmartWorkoutLaunchPlan) -> Boolean
    ) -> Boolean = { _, _, _ -> false }
) : androidx.lifecycle.ViewModel() {
    private data class TransientState(
        val isSyncingPlanToWatch: Boolean,
        val didSyncPlanToWatch: Boolean?,
        val watchPlanSyncError: LocalizedText?,
        val isSaving: Boolean,
        val hasValidationError: Boolean,
        val isDirty: Boolean,
        val activeWorkoutStarted: Boolean
    )

    private data class LocalState(
        val workoutDate: Long,
        val note: String,
        val exerciseDrafts: List<ExerciseInputState>,
        val trainingProfile: TrainingProfile,
        val smartWorkoutEffort: SmartWorkoutEffort,
        val generatedSmartPlan: SmartWorkoutPlanSummaryUiModel?,
        val smartAlternativePicker: SmartWorkoutAlternativePickerUiState?,
        val isTemplatePickerOpen: Boolean,
        val isTemplateLoading: Boolean,
        val isSyncingPlanToWatch: Boolean,
        val didSyncPlanToWatch: Boolean?,
        val watchPlanSyncError: LocalizedText?,
        val isSaving: Boolean,
        val hasValidationError: Boolean,
        val isDirty: Boolean,
        val activeWorkoutStarted: Boolean
    )

    private data class EditorState(
        val workoutDate: Long,
        val note: String,
        val exerciseDrafts: List<ExerciseInputState>,
        val isTemplatePickerOpen: Boolean,
        val isTemplateLoading: Boolean,
        val smartWorkoutEffort: SmartWorkoutEffort,
        val generatedSmartPlan: SmartWorkoutPlanSummaryUiModel?,
        val smartAlternativePicker: SmartWorkoutAlternativePickerUiState?
    )

    private data class SmartCoachState(
        val effort: SmartWorkoutEffort,
        val generatedPlan: SmartWorkoutPlanSummaryUiModel?,
        val alternativePicker: SmartWorkoutAlternativePickerUiState?
    )

    private data class RecommendationRequest(
        val exerciseIds: List<Long>,
        val selectedEffort: SmartWorkoutEffort,
        val generatedPlan: SmartWorkoutPlanSummaryUiModel?
    )

    private data class ExerciseCatalogState(
        val isLoaded: Boolean,
        val exercises: List<ExerciseEntity>,
        val frequentExerciseIds: List<Long>,
        val exerciseWorkoutCounts: Map<Long, Int>,
        val exerciseMuscleIds: Map<String, Set<String>>,
        val loadProfiles: Map<Long, ExerciseLoadProfile>,
        val manualMuscleMappings: Map<String, List<MuscleContribution>>
    )

    private var nextDraftId = 1L
    private var watchPlanSyncGeneration = 0L
    private var launchHydrationGeneration = 0L
    private var lastRequestedLaunchToken: String? = null

    private val workoutDate = MutableStateFlow(System.currentTimeMillis())
    private val note = MutableStateFlow("")
    private val exerciseDrafts = MutableStateFlow(emptyList<ExerciseInputState>())
    private val isTemplatePickerOpen = MutableStateFlow(false)
    private val isTemplateLoading = MutableStateFlow(false)
    private val smartWorkoutEffort = MutableStateFlow(SmartWorkoutEffort.Auto)
    private val generatedSmartPlan = MutableStateFlow<SmartWorkoutPlanSummaryUiModel?>(null)
    private val smartAlternativePicker = MutableStateFlow<SmartWorkoutAlternativePickerUiState?>(null)
    private val isSyncingPlanToWatch = MutableStateFlow(false)
    private val didSyncPlanToWatch = MutableStateFlow<Boolean?>(null)
    private val watchPlanSyncError = MutableStateFlow<LocalizedText?>(null)
    private val isSaving = MutableStateFlow(false)
    private val hasValidationError = MutableStateFlow(false)
    private val isDirty = MutableStateFlow(false)
    private val activeWorkoutStarted = MutableStateFlow(false)
    private val durableDraftLoaded = MutableStateFlow(false)

    private val exercises = repository.observeExercises()
    private val exerciseHistory: StateFlow<List<ExerciseHistoryEntry>> = repository.observeAllExerciseHistory()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(
                stopTimeoutMillis = 5_000,
                replayExpirationMillis = 0
            ),
            initialValue = emptyList()
        )
    private val exerciseCatalogState: StateFlow<ExerciseCatalogState> = combine(
        exercises,
        exerciseHistory,
        repository.observeExerciseLoadProfiles(),
        repository.observeExerciseMuscleMappings()
    ) { exerciseList, history, loadProfiles, muscleMappings ->
        val exerciseFrequencies = exerciseFrequencyByExercise(history)
        val workoutCounts = exerciseFrequencies.mapValues { (_, frequency) ->
            frequency.workoutCount
        }
        val manualMappings = muscleMappings.toManualContributionMap()
        val frequentIds = frequentExerciseIds(exerciseFrequencies)
        ExerciseCatalogState(
            isLoaded = true,
            exercises = exerciseList,
            frequentExerciseIds = frequentIds,
            exerciseWorkoutCounts = workoutCounts,
            exerciseMuscleIds = exerciseList.associate { exercise ->
                val contributions = manualMappings[exercise.name.normalizedExerciseName()]
                    ?: defaultContributionsForExercise(exercise.name)
                exercise.name to contributions.mapTo(linkedSetOf()) { it.muscleId }
            },
            loadProfiles = loadProfiles,
            manualMuscleMappings = manualMappings
        )
    }.flowOn(Dispatchers.Default).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(
            stopTimeoutMillis = 5_000,
            replayExpirationMillis = 0
        ),
        initialValue = ExerciseCatalogState(
            isLoaded = false,
            exercises = emptyList(),
            frequentExerciseIds = emptyList(),
            exerciseWorkoutCounts = emptyMap(),
            exerciseMuscleIds = emptyMap(),
            loadProfiles = emptyMap(),
            manualMuscleMappings = emptyMap()
        )
    )

    init {
        viewModelScope.launch {
            try {
                val activeWorkoutExists = repository.getActiveWorkoutSnapshot() != null
                val restored = if (activeWorkoutExists) {
                    repository.clearWorkoutPlanDraft()
                    null
                } else {
                    repository.getWorkoutPlanDraftPayload()?.let(::parsePersistedWorkoutPlanDraft)
                }
                if (restored != null && !hasRetainedDraft()) {
                    workoutDate.value = restored.workoutDate
                    note.value = restored.note
                    exerciseDrafts.value = restored.exerciseDrafts
                    smartWorkoutEffort.value = restored.smartWorkoutEffort
                    isDirty.value = restored.isDirty
                    nextDraftId = (restored.exerciseDrafts.maxOfOrNull { it.draftId } ?: 0L) + 1L
                } else if (!activeWorkoutExists && restored == null) {
                    repository.clearWorkoutPlanDraft()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Keep the editor usable if account-local draft storage is temporarily unavailable.
            } finally {
                durableDraftLoaded.value = true
            }
        }
        viewModelScope.launch {
            combine(
                workoutDate,
                note,
                exerciseDrafts,
                smartWorkoutEffort,
                isDirty
            ) { date, noteValue, drafts, effort, dirty ->
                PersistedWorkoutPlanDraft(date, noteValue, drafts, effort, dirty)
            }
                .debounce(250L)
                .collect { draft ->
                    if (!durableDraftLoaded.value) return@collect
                    try {
                        if (draft.isDirty || draft.exerciseDrafts.isNotEmpty() || draft.note.isNotBlank()) {
                            repository.saveWorkoutPlanDraftPayload(draft.toJson())
                        } else {
                            repository.clearWorkoutPlanDraft()
                        }
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Throwable) {
                        // A later editor mutation retries the bounded account-local write.
                    }
                }
        }
        launchToken?.let { token ->
            openLaunchPlan(token, launchPlanHandoff)
        }
    }
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
        watchPlanSyncGeneration += 1L
        isSyncingPlanToWatch.value = false
        didSyncPlanToWatch.value = null
        watchPlanSyncError.value = null
    }

    private fun markDraftDirty() {
        isDirty.value = true
    }

    private val lastWeights = selectedExerciseIds.flatMapLatest { ids ->
        repository.observeLastWeights(ids)
    }

    private val smartCoachState = combine(
        smartWorkoutEffort,
        generatedSmartPlan,
        smartAlternativePicker
    ) { effort, plan, alternatives ->
        SmartCoachState(effort, plan, alternatives)
    }

    private val recommendationRequest = combine(
        selectedExerciseIds,
        smartWorkoutEffort,
        generatedSmartPlan
    ) { ids, selectedEffort, generatedPlan ->
        RecommendationRequest(ids, selectedEffort, generatedPlan)
    }

    private val workoutRecommendations = recommendationRequest.flatMapLatest { request ->
        trainingProfileManager.profile.flatMapLatest { profile ->
            val policy = smartWorkoutRecommendationPolicy(
                selectedEffort = request.selectedEffort,
                currentProfile = profile,
                generatedPlan = request.generatedPlan
            )
            repository.observeWorkoutRecommendations(
                exerciseIds = request.exerciseIds,
                trainingProfile = profile,
                effort = policy.effort,
                hardExerciseIds = policy.hardExerciseIds
            )
        }
    }

    private val workoutMetadata = combine(
        workoutDate,
        note,
    ) { date, noteValue ->
        date to noteValue
    }

    private val editorState = combine(
        workoutMetadata,
        exerciseDrafts,
        isTemplatePickerOpen,
        isTemplateLoading,
        smartCoachState
    ) { metadata, drafts, templatePickerOpen, templateLoading, smartCoach ->
        EditorState(
            workoutDate = metadata.first,
            note = metadata.second,
            exerciseDrafts = drafts,
            isTemplatePickerOpen = templatePickerOpen,
            isTemplateLoading = templateLoading,
            smartWorkoutEffort = smartCoach.effort,
            generatedSmartPlan = smartCoach.generatedPlan,
            smartAlternativePicker = smartCoach.alternativePicker
        )
    }

    private val planSyncResult = combine(
        didSyncPlanToWatch,
        watchPlanSyncError,
        isDirty
    ) { planSyncState, planSyncError, dirty ->
        Triple(planSyncState, planSyncError, dirty)
    }

    private val transientState = combine(
        isSyncingPlanToWatch,
        planSyncResult,
        isSaving,
        hasValidationError,
        activeWorkoutStarted
    ) { syncingPlan, planSyncResult, saving, validationError, workoutStarted ->
        TransientState(
            isSyncingPlanToWatch = syncingPlan,
            didSyncPlanToWatch = planSyncResult.first,
            watchPlanSyncError = planSyncResult.second,
            isSaving = saving,
            hasValidationError = validationError,
            isDirty = planSyncResult.third,
            activeWorkoutStarted = workoutStarted
        )
    }

    private val localState = combine(
        editorState,
        transientState,
        trainingProfileManager.profile
    ) { editor, transient, profile ->
        LocalState(
            workoutDate = editor.workoutDate,
            note = editor.note,
            exerciseDrafts = editor.exerciseDrafts,
            trainingProfile = profile,
            smartWorkoutEffort = editor.smartWorkoutEffort,
            generatedSmartPlan = editor.generatedSmartPlan,
            smartAlternativePicker = editor.smartAlternativePicker,
            isTemplatePickerOpen = editor.isTemplatePickerOpen,
            isTemplateLoading = editor.isTemplateLoading,
            isSyncingPlanToWatch = transient.isSyncingPlanToWatch,
            didSyncPlanToWatch = transient.didSyncPlanToWatch,
            watchPlanSyncError = transient.watchPlanSyncError,
            isSaving = transient.isSaving,
            hasValidationError = transient.hasValidationError,
            isDirty = transient.isDirty,
            activeWorkoutStarted = transient.activeWorkoutStarted
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
            workoutDate = local.workoutDate,
            note = local.note,
            exercises = catalog.exercises,
            frequentExerciseIds = catalog.frequentExerciseIds,
            exerciseWorkoutCounts = catalog.exerciseWorkoutCounts,
            exerciseMuscleIds = catalog.exerciseMuscleIds,
            exerciseDrafts = local.exerciseDrafts,
            lastWeights = lastWeightsMap,
            workoutRecommendations = recommendations,
            exerciseLoadProfiles = catalog.loadProfiles,
            trainingProfile = local.trainingProfile,
            smartWorkoutEffort = local.smartWorkoutEffort,
            generatedSmartPlan = local.generatedSmartPlan,
            generatedSmartPlanNeedsRefresh = smartWorkoutPlanNeedsRefresh(
                selectedEffort = local.smartWorkoutEffort,
                currentProfile = local.trainingProfile,
                generatedPlan = local.generatedSmartPlan
            ),
            smartAlternativePicker = local.smartAlternativePicker,
            canRepeatFromLast = templates.isNotEmpty(),
            workoutTemplates = templates,
            isTemplatePickerOpen = local.isTemplatePickerOpen,
            isTemplateLoading = local.isTemplateLoading,
            isSyncingPlanToWatch = local.isSyncingPlanToWatch,
            didSyncPlanToWatch = local.didSyncPlanToWatch,
            watchPlanSyncError = local.watchPlanSyncError,
            isSaving = local.isSaving,
            hasValidationError = local.hasValidationError,
            isDirty = local.isDirty,
            activeWorkoutStarted = local.activeWorkoutStarted
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(
            stopTimeoutMillis = 5_000,
            replayExpirationMillis = 0
        ),
        initialValue = AddWorkoutUiState()
    )

    internal suspend fun applySharedWorkoutPlan(plan: SharedWorkoutPlan): Boolean {
        if (isTemplateLoading.value || isSaving.value) return false
        isTemplateLoading.value = true
        return try {
            val normalizedPlan = normalizeSharedWorkoutPlanForDraftImport(plan)
            repository.seedBuiltInExercises()
            val exerciseIds = repository.resolveSharedWorkoutExerciseIds(normalizedPlan)
            check(exerciseIds.size == normalizedPlan.exercises.size)

            resetWatchPlanSyncResult()
            generatedSmartPlan.value = null
            smartAlternativePicker.value = null
            smartWorkoutEffort.value = SmartWorkoutEffort.Auto
            workoutDate.value = System.currentTimeMillis()
            note.value = ""
            exerciseDrafts.value = normalizedPlan.exercises.zip(exerciseIds).map { (exercise, id) ->
                ExerciseInputState(
                    draftId = nextDraftId++,
                    exerciseId = id,
                    sets = exercise.sets.map { set ->
                        SetInputState(
                            weight = formatWeight(set.weight),
                            reps = set.reps.toString()
                        )
                    }
                )
            }
            isDirty.value = false
            hasValidationError.value = false
            true
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            hasValidationError.value = true
            false
        } finally {
            isTemplateLoading.value = false
        }
    }

    internal fun openLaunchPlan(
        token: String,
        handoff: suspend (
            String,
            (SmartWorkoutLaunchPlan) -> Boolean,
            (SmartWorkoutLaunchPlan) -> Boolean
        ) -> Boolean
    ) {
        if (hasRetainedDraft()) return
        if (token == lastRequestedLaunchToken) return
        lastRequestedLaunchToken = token
        val generation = ++launchHydrationGeneration
        viewModelScope.launch {
            durableDraftLoaded.first { it }
            exerciseCatalogState.first { catalog -> catalog.isLoaded }
            if (generation != launchHydrationGeneration) return@launch
            val accepted = try {
                handoff(
                    token,
                    { plan ->
                        generation == launchHydrationGeneration &&
                            !hasRetainedDraft() &&
                            canApplyLaunchPlan(plan)
                    },
                    { plan ->
                        generation == launchHydrationGeneration &&
                            !hasRetainedDraft() &&
                            applyLaunchPlan(plan)
                    }
                )
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                false
            }
            if (generation == launchHydrationGeneration &&
                !accepted &&
                !hasRetainedDraft()
            ) {
                hasValidationError.value = true
            }
        }
    }

    private fun applyLaunchPlan(plan: SmartWorkoutLaunchPlan): Boolean {
        if (!canApplyLaunchPlan(plan)) return false
        return applyLaunchPlanUnchecked(plan)
    }

    private fun canApplyLaunchPlan(plan: SmartWorkoutLaunchPlan): Boolean {
        val catalogIds = exerciseCatalogState.value.exercises.mapTo(hashSetOf()) { it.id }
        if (plan.exercises.any { it.exerciseId !in catalogIds }) {
            hasValidationError.value = true
            return false
        }
        return true
    }

    private fun applyLaunchPlanUnchecked(plan: SmartWorkoutLaunchPlan): Boolean {
        resetWatchPlanSyncResult()
        exerciseDrafts.value = plan.exercises.map { exercise ->
            ExerciseInputState(
                draftId = nextDraftId++,
                exerciseId = exercise.exerciseId,
                sets = exercise.sets.map { set ->
                    SetInputState(
                        weight = smartWorkoutWeightInput(set.weight),
                        reps = set.reps.toString()
                    )
                }
            )
        }
        smartWorkoutEffort.value = plan.requestedEffort
        generatedSmartPlan.value = SmartWorkoutPlanSummaryUiModel(
            focus = plan.focus,
            variant = plan.variant,
            requestedEffort = plan.requestedEffort,
            appliedEffort = plan.appliedEffort,
            effortAdjustment = plan.effortAdjustment,
            hardExerciseIds = plan.exercises.asSequence()
                .filter { it.isHardSlot }
                .mapTo(linkedSetOf()) { it.exerciseId },
            trainingProfileSnapshot = plan.trainingProfile
        )
        smartAlternativePicker.value = null
        hasValidationError.value = false
        return true
    }

    fun updateNote(value: String) {
        if (!WorkoutDataLimits.isValidNote(value)) {
            hasValidationError.value = true
            return
        }
        resetWatchPlanSyncResult()
        if (note.value != value) markDraftDirty()
        note.value = value
    }

    fun updateWorkoutDate(selectedEpochDay: Long) {
        val resolved = resolveWorkoutDateSelection(
            currentTimestamp = workoutDate.value,
            selectedEpochDay = selectedEpochDay
        )
        if (resolved == null) {
            hasValidationError.value = true
            return
        }
        resetWatchPlanSyncResult()
        hasValidationError.value = false
        if (workoutDate.value != resolved) markDraftDirty()
        workoutDate.value = resolved
    }

    fun updateTrainingSplit(split: TrainingSplit) {
        resetWatchPlanSyncResult()
        smartAlternativePicker.value = null
        trainingProfileManager.updateSplit(split)
    }

    fun updateWorkoutsPerWeek(value: Int) {
        resetWatchPlanSyncResult()
        smartAlternativePicker.value = null
        trainingProfileManager.updateWorkoutsPerWeek(value)
    }

    fun updateTrainingGoal(goal: TrainingGoal) {
        resetWatchPlanSyncResult()
        smartAlternativePicker.value = null
        trainingProfileManager.updateGoal(goal)
    }

    fun updateCalorieMode(mode: CalorieMode) {
        resetWatchPlanSyncResult()
        smartAlternativePicker.value = null
        trainingProfileManager.updateCalorieMode(mode)
    }

    fun updateSmartWorkoutEffort(effort: SmartWorkoutEffort) {
        resetWatchPlanSyncResult()
        if (smartWorkoutEffort.value != effort) markDraftDirty()
        smartWorkoutEffort.value = effort
        smartAlternativePicker.value = null
    }

    fun generateSmartWorkout(defaultNote: String) {
        val catalog = exerciseCatalogState.value
        val currentProfile = trainingProfileManager.profile.value
        val selectedEffort = smartWorkoutEffort.value
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = catalog.exercises,
            history = exerciseHistory.value,
            trainingProfile = currentProfile,
            loadProfiles = catalog.loadProfiles,
            manualMuscleMappings = catalog.manualMuscleMappings,
            effort = selectedEffort
        )
        if (plan.exercises.isEmpty()) {
            hasValidationError.value = true
            return
        }

        resetWatchPlanSyncResult()
        markDraftDirty()
        hasValidationError.value = false
        exerciseDrafts.value = plan.exercises.map { plannedExercise ->
            ExerciseInputState(
                draftId = nextDraftId++,
                exerciseId = plannedExercise.exercise.id,
                sets = plannedExercise.recommendation.sets.map { set ->
                    SetInputState(
                        weight = smartWorkoutWeightInput(set.weight),
                        reps = set.reps.toString()
                    )
                }
            )
        }
        generatedSmartPlan.value = SmartWorkoutPlanSummaryUiModel(
            focus = plan.focus,
            variant = plan.variant,
            requestedEffort = plan.requestedEffort,
            appliedEffort = plan.appliedEffort,
            effortAdjustment = plan.effortAdjustment,
            hardExerciseIds = plan.exercises.asSequence()
                .filter { planned -> planned.recommendation.targetRir == 1..2 }
                .map { planned -> planned.exercise.id }
                .toSet(),
            trainingProfileSnapshot = currentProfile
        )
        smartAlternativePicker.value = null
        if (note.value.isBlank()) {
            note.value = defaultNote
        }
    }

    fun openSmartWorkoutAlternatives(draftId: Long) {
        val drafts = exerciseDrafts.value
        val catalog = exerciseCatalogState.value
        val currentProfile = trainingProfileManager.profile.value
        val draft = drafts.firstOrNull { it.draftId == draftId } ?: return
        val currentExerciseId = draft.exerciseId ?: return
        val recommendationPolicy = smartWorkoutRecommendationPolicy(
            selectedEffort = smartWorkoutEffort.value,
            currentProfile = currentProfile,
            generatedPlan = generatedSmartPlan.value
        )
        val selectedExerciseIds = drafts.mapNotNullTo(linkedSetOf()) { it.exerciseId }
        val alternatives = WorkoutRecommendationEngine.findAlternatives(
            currentExerciseId = currentExerciseId,
            selectedExerciseIds = selectedExerciseIds,
            exercises = catalog.exercises,
            history = exerciseHistory.value,
            trainingProfile = currentProfile,
            effort = recommendationPolicy.effort,
            loadProfiles = catalog.loadProfiles,
            manualMuscleMappings = catalog.manualMuscleMappings,
            hardSetEligible = currentExerciseId in recommendationPolicy.hardExerciseIds,
            limit = MAX_SMART_ALTERNATIVES
        )
        hasValidationError.value = false
        smartAlternativePicker.value = SmartWorkoutAlternativePickerUiState(
            draftId = draftId,
            expectedExerciseId = currentExerciseId,
            selectedExerciseIdsSnapshot = selectedExerciseIds,
            alternatives = alternatives
        )
    }

    fun closeSmartWorkoutAlternatives() {
        smartAlternativePicker.value = null
    }

    fun applySmartWorkoutAlternative(
        draftId: Long,
        expectedCurrentExerciseId: Long,
        replacementExerciseId: Long
    ) {
        val picker = smartAlternativePicker.value
        val draftsSnapshot = exerciseDrafts.value
        val selectedExerciseIds = draftsSnapshot.mapNotNullTo(linkedSetOf()) { it.exerciseId }
        val targetDraft = draftsSnapshot.firstOrNull { it.draftId == draftId }
        val wasOffered = picker?.alternatives?.any { candidate ->
            candidate.exercise.id == replacementExerciseId
        } == true
        if (picker == null || !wasOffered || picker.draftId != draftId ||
            picker.expectedExerciseId != expectedCurrentExerciseId ||
            picker.selectedExerciseIdsSnapshot != selectedExerciseIds ||
            targetDraft?.exerciseId != expectedCurrentExerciseId
        ) {
            hasValidationError.value = true
            return
        }
        val catalog = exerciseCatalogState.value
        val currentProfile = trainingProfileManager.profile.value
        val recommendationPolicy = smartWorkoutRecommendationPolicy(
            selectedEffort = smartWorkoutEffort.value,
            currentProfile = currentProfile,
            generatedPlan = generatedSmartPlan.value
        )
        // Recompute the bounded allowlist at apply time. History, profiles and catalog rows can
        // change while the sheet is open; a stale client-side option must not be trusted.
        val alternative = WorkoutRecommendationEngine.findAlternatives(
            currentExerciseId = expectedCurrentExerciseId,
            selectedExerciseIds = selectedExerciseIds,
            exercises = catalog.exercises,
            history = exerciseHistory.value,
            trainingProfile = currentProfile,
            effort = recommendationPolicy.effort,
            loadProfiles = catalog.loadProfiles,
            manualMuscleMappings = catalog.manualMuscleMappings,
            hardSetEligible = expectedCurrentExerciseId in recommendationPolicy.hardExerciseIds,
            limit = MAX_SMART_ALTERNATIVES
        ).firstOrNull { candidate -> candidate.exercise.id == replacementExerciseId }
        if (alternative == null || alternative.recommendation.sets.size !in 3..4) {
            hasValidationError.value = true
            return
        }
        var applied = false
        exerciseDrafts.update { current ->
            if (current.any { draft ->
                    draft.draftId != draftId && draft.exerciseId == replacementExerciseId
                }
            ) {
                return@update current
            }
            current.map { draft ->
                if (draft.draftId == draftId && draft.exerciseId == expectedCurrentExerciseId) {
                    applied = true
                    draft.copy(
                        exerciseId = replacementExerciseId,
                        sets = alternative.recommendation.sets.map { set ->
                            SetInputState(
                                weight = smartWorkoutWeightInput(set.weight),
                                reps = set.reps.toString()
                            )
                        }
                    )
                } else {
                    draft
                }
            }
        }
        if (applied) {
            markDraftDirty()
            generatedSmartPlan.value = generatedSmartPlan.value?.let { plan ->
                if (expectedCurrentExerciseId !in plan.hardExerciseIds) {
                    plan
                } else {
                    val replacementKeepsHardSlot = alternative.recommendation.targetRir == 1..2 &&
                        alternative.recommendation.sets.size == 4
                    plan.copy(
                        hardExerciseIds = (plan.hardExerciseIds - expectedCurrentExerciseId).let { remaining ->
                            if (replacementKeepsHardSlot) remaining + replacementExerciseId else remaining
                        }
                    )
                }
            }
            hasValidationError.value = false
            resetWatchPlanSyncResult()
            smartAlternativePicker.value = null
        } else {
            hasValidationError.value = true
        }
    }

    fun addExerciseDraft() {
        resetWatchPlanSyncResult()
        generatedSmartPlan.value = null
        smartAlternativePicker.value = null
        exerciseDrafts.update { current ->
            if (current.size >= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
                hasValidationError.value = true
                current
            } else {
                markDraftDirty()
                listOf(ExerciseInputState(draftId = nextDraftId++)) + current
            }
        }
    }

    fun removeExerciseDraft(draftId: Long) {
        resetWatchPlanSyncResult()
        generatedSmartPlan.value = null
        smartAlternativePicker.value = null
        exerciseDrafts.update { current ->
            if (current.none { it.draftId == draftId }) return@update current
            markDraftDirty()
            current.filterNot { it.draftId == draftId }
        }
    }

    /** Clears only the local plan draft. Account-level Coach settings and metadata stay intact. */
    fun clearWorkoutPlan(): Boolean {
        if (exerciseDrafts.value.isEmpty()) return false
        resetWatchPlanSyncResult()
        generatedSmartPlan.value = null
        smartAlternativePicker.value = null
        exerciseDrafts.value = emptyList()
        hasValidationError.value = false
        markDraftDirty()
        return true
    }

    fun updateExerciseSelection(draftId: Long, exerciseId: Long) {
        if (exerciseId <= 0L || exerciseCatalogState.value.exercises.none { it.id == exerciseId }) {
            hasValidationError.value = true
            return
        }
        hasValidationError.value = false
        resetWatchPlanSyncResult()
        generatedSmartPlan.value = null
        smartAlternativePicker.value = null
        exerciseDrafts.update { current ->
            current.map { draft ->
                if (draft.draftId == draftId && draft.exerciseId != exerciseId) {
                    markDraftDirty()
                    draft.copy(
                        exerciseId = exerciseId,
                        // A load from another movement (for example barbell bench to dumbbells)
                        // is never transferable. Keep manual selection explicit and safe.
                        sets = listOf(SetInputState())
                    )
                } else {
                    draft
                }
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
                    markDraftDirty()
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
                    markDraftDirty()
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
                    if (updatedSets.size == draft.sets.size) return@map draft
                    markDraftDirty()
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
                    if (updatedSets != draft.sets) markDraftDirty()
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
                    if (updatedSets != draft.sets) markDraftDirty()
                    draft.copy(sets = updatedSets)
                } else {
                    draft
                }
            }
        }
    }

    fun startWorkout() {
        viewModelScope.launch {
            val parsedExercises = parseDrafts(exerciseDrafts.value)
            val selectedWorkoutDate = workoutDate.value
            if (parsedExercises.isEmpty() ||
                !WorkoutDataLimits.isValidNote(note.value) ||
                !isSelectableWorkoutTimestamp(selectedWorkoutDate)
            ) {
                hasValidationError.value = true
                return@launch
            }

            isSaving.value = true
            hasValidationError.value = false

            runCatching {
                repository.startActiveWorkout(
                    date = selectedWorkoutDate,
                    note = note.value,
                    workoutExercises = parsedExercises
                )
            }.onSuccess { result ->
                if (result == StartActiveWorkoutResult.Started) {
                    resetDraftState()
                }
                if (result == StartActiveWorkoutResult.Started ||
                    result == StartActiveWorkoutResult.AlreadyActive
                ) {
                    activeWorkoutStarted.value = true
                }
            }.onFailure {
                hasValidationError.value = true
            }

            isSaving.value = false
        }
    }

    fun prepareSharedWorkoutUrl(): String? {
        val result = runCatching {
            buildSharedWorkoutDraftUrl(
                drafts = exerciseDrafts.value,
                exercises = exerciseCatalogState.value.exercises
            )
        }
        hasValidationError.value = result.isFailure
        return result.getOrNull()
    }

    internal fun prepareSharedWorkoutPlan(): SharedWorkoutPlan? {
        val result = runCatching {
            buildSharedWorkoutDraftPlan(
                drafts = exerciseDrafts.value,
                exercises = exerciseCatalogState.value.exercises
            )
        }
        hasValidationError.value = result.isFailure
        return result.getOrNull()
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
            val syncGeneration = watchPlanSyncGeneration + 1L
            watchPlanSyncGeneration = syncGeneration
            isSyncingPlanToWatch.value = true
            didSyncPlanToWatch.value = null
            watchPlanSyncError.value = null

            val result = runCatching {
                val exerciseCatalog = uiState.value.exercises.map { it.name }
                syncClient.pushWorkoutPlan(
                    sets = namedSets,
                    exerciseCatalog = exerciseCatalog,
                    trainingProfile = uiState.value.trainingProfile
                )
            }
            if (watchPlanSyncResultIsCurrent(syncGeneration, watchPlanSyncGeneration)) {
                result.onSuccess {
                    didSyncPlanToWatch.value = true
                    watchPlanSyncError.value = null
                }.onFailure { error ->
                    didSyncPlanToWatch.value = false
                    watchPlanSyncError.value = planSyncErrorText(error)
                }
                isSyncingPlanToWatch.value = false
            }
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
                    markDraftDirty()
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
            markDraftDirty()
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
                    val updatedSets = draft.sets.map { set ->
                        if (set.weight.isBlank()) set.copy(weight = formattedWeight) else set
                    }
                    if (updatedSets != draft.sets) markDraftDirty()
                    draft.copy(
                        sets = updatedSets
                    )
                } else {
                    draft
                }
            }
        }
    }

    fun consumeActiveWorkoutStarted() {
        activeWorkoutStarted.value = false
    }

    internal fun hasRetainedDraft(): Boolean =
        isDirty.value || exerciseDrafts.value.isNotEmpty() || note.value.isNotBlank()

    internal fun retainedDraftFingerprint(): RetainedWorkoutDraftFingerprint =
        RetainedWorkoutDraftFingerprint(
            workoutDate = workoutDate.value,
            note = note.value,
            exerciseDrafts = exerciseDrafts.value,
            smartWorkoutEffort = smartWorkoutEffort.value,
            generatedSmartPlan = generatedSmartPlan.value,
            isDirty = isDirty.value
        )

    internal fun retainedDraftDurableDigest(): String =
        retainedDraftFingerprint().durableDigest()

    internal fun discardDraftIfUnchanged(
        expected: RetainedWorkoutDraftFingerprint
    ): Boolean {
        if (!liveSendMayDiscardRetainedWorkoutDraft(expected, retainedDraftFingerprint())) {
            return false
        }
        resetDraftState()
        return true
    }

    internal fun discardDraftIfDigestMatches(expectedDigest: String): Boolean {
        if (retainedDraftDurableDigest() != expectedDigest) return false
        resetDraftState()
        return true
    }

    fun discardDraft() {
        resetDraftState()
    }

    private fun resetDraftState() {
        viewModelScope.launch(Dispatchers.IO + NonCancellable) {
            runCatching { repository.clearWorkoutPlanDraft() }
        }
        launchHydrationGeneration += 1L
        watchPlanSyncGeneration += 1L
        workoutDate.value = System.currentTimeMillis()
        note.value = ""
        exerciseDrafts.value = emptyList()
        isTemplatePickerOpen.value = false
        isTemplateLoading.value = false
        smartWorkoutEffort.value = SmartWorkoutEffort.Auto
        generatedSmartPlan.value = null
        smartAlternativePicker.value = null
        isSyncingPlanToWatch.value = false
        didSyncPlanToWatch.value = null
        watchPlanSyncError.value = null
        isSaving.value = false
        hasValidationError.value = false
        isDirty.value = false
        activeWorkoutStarted.value = false
    }

    private fun applyWorkoutTemplate(template: WorkoutSessionDetails) {
        generatedSmartPlan.value = null
        smartAlternativePicker.value = null
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

        exerciseDrafts.value = drafts
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
                    markDraftDirty()
                    draft.copy(
                        sets = recommendation.sets.map { set ->
                            SetInputState(
                                weight = smartWorkoutWeightInput(set.weight),
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
        private const val MAX_SMART_ALTERNATIVES = 6

        internal fun factory(
            repository: GymRepository,
            syncClient: PhoneSyncClient,
            trainingProfileManager: TrainingProfileManager,
            launchToken: String? = null,
            launchPlanHandoff: suspend (
                String,
                (SmartWorkoutLaunchPlan) -> Boolean,
                (SmartWorkoutLaunchPlan) -> Boolean
            ) -> Boolean = { _, _, _ -> false }
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                AddWorkoutViewModel(
                    repository = repository,
                    syncClient = syncClient,
                    trainingProfileManager = trainingProfileManager,
                    launchToken = launchToken,
                    launchPlanHandoff = launchPlanHandoff
                )
            }
        }
    }
}
