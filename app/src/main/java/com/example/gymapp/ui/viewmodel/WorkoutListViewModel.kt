package com.example.gymapp.ui.viewmodel

import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.lifecycle.viewModelScope
import com.example.gymapp.R
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.DashboardStats
import com.example.gymapp.data.repository.GamificationEngine
import com.example.gymapp.data.repository.BadgeRarity
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.data.repository.RANK_DEFINITIONS
import com.example.gymapp.data.repository.MuscleContribution
import com.example.gymapp.data.repository.ExerciseLoadProfile
import com.example.gymapp.data.repository.FirstWorkoutEffort
import com.example.gymapp.data.repository.FirstWorkoutActivationCommitter
import com.example.gymapp.data.repository.FirstWorkoutActivationDirectStarter
import com.example.gymapp.data.repository.PendingFirstWorkoutActivation
import com.example.gymapp.data.repository.PendingFirstWorkoutActivationCodec
import com.example.gymapp.data.repository.SmartCoachFeedback
import com.example.gymapp.data.repository.SmartWorkoutEffort
import com.example.gymapp.data.repository.SmartWorkoutEffortAdjustment
import com.example.gymapp.data.repository.SmartWorkoutFocus
import com.example.gymapp.data.repository.SmartWorkoutLaunchOrigin
import com.example.gymapp.data.repository.SmartWorkoutLaunchPlan
import com.example.gymapp.data.repository.SmartWorkoutLaunchPlanCodec
import com.example.gymapp.data.repository.SmartWorkoutLaunchStateFingerprint
import com.example.gymapp.data.repository.SmartWorkoutLaunchUseRegistry
import com.example.gymapp.data.repository.RecommendedWorkoutStartCommitter
import com.example.gymapp.data.repository.WeeklyTrainingDecision
import com.example.gymapp.data.repository.WeeklyTrainingRhythm
import com.example.gymapp.data.repository.WeeklyTrainingRhythmCalculator
import com.example.gymapp.data.repository.WeeklyStreakCalculator
import com.example.gymapp.data.repository.WorkoutFeedbackRecord
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.WorkoutRecommendationEngine
import com.example.gymapp.data.repository.estimatedLoad
import com.example.gymapp.data.repository.muscleContributionsForExercise
import com.example.gymapp.data.repository.normalizedExerciseName
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.util.DateTimeUtils
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.util.TrainingGoal
import com.example.gymapp.util.TrainingGuidanceManager
import com.example.gymapp.util.TrainingProfile
import com.example.gymapp.util.TrainingProfileManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import com.example.gymapp.util.RussianText
import com.example.gymapp.data.repository.toSmartWorkoutEffort
import com.example.gymapp.data.repository.trainingProfileForActivation
import com.example.gymapp.garmin.MAX_GARMIN_DURATION_SECONDS
import com.example.gymapp.garmin.parseGarminWorkoutMetrics
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

private const val MAX_TODAY_HERO_VOLUME = 1_000_000_000_000_000.0
internal const val MAX_ESTIMATED_WORKOUT_MINUTES = 90
private val EMPTY_DASHBOARD_STATS = DashboardStats(
    workoutCount = 0,
    totalVolume = 0.0,
    averageIntensity = 0.0,
    streakDays = 0,
    weeklyStreakWeeks = 0
)

data class SoloProgressUiModel(
    val totalXp: Int = 0,
    val monthXp: Int = 0,
    val level: Int = 1,
    val title: String = "--",
    val currentLevelXp: Int = 0,
    val xpForNextLevel: Int = 200,
    val progressFraction: Float = 0f,
    val streakDays: Int = 0,
    val weeklyStreakWeeks: Int = 0,
    val weeklyTarget: Int = 4,
    val summary: String = "",
    val nextTitle: String = "--"
)

data class ActivityHeatmapDayUiModel(
    val id: String,
    val dayNumber: Int? = null,
    val dayLabel: String = "",
    val sessionCount: Int = 0,
    val totalVolume: Double = 0.0,
    val intensity: Float = 0f,
    val isCurrentMonth: Boolean = false,
    val isToday: Boolean = false
)

data class ActivityHeatmapUiModel(
    val monthLabel: String = DateTimeUtils.monthLabel(0),
    val activeDays: Int = 0,
    val sessionCount: Int = 0,
    val totalVolume: Double = 0.0,
    val weeks: List<List<ActivityHeatmapDayUiModel>> = emptyList()
)

data class MuscleProgressUiModel(
    val id: String,
    val label: String,
    val load: Int = 0,
    val sets: Int = 0,
    val sessions: Int = 0,
    val exercises: Int = 0,
    val intensity: Float = 0f
)

enum class MuscleMapPeriod {
    AllTime,
    Month,
    Week
}

data class MuscleMapPeriodOptionUiModel(
    val period: MuscleMapPeriod,
    val label: String,
    val isSelected: Boolean = false
)

data class MuscleExerciseContributionUiModel(
    val exerciseName: String,
    val load: Int = 0,
    val sets: Int = 0,
    val sessions: Int = 0
)

data class UnmappedExerciseUiModel(
    val exerciseName: String,
    val sets: Int = 0,
    val sessions: Int = 0
)

data class ExerciseMappingUiModel(
    val exerciseName: String,
    val muscleLabels: String,
    val sets: Int = 0,
    val sessions: Int = 0,
    val isMapped: Boolean = false
)

data class MuscleOptionUiModel(
    val id: String,
    val label: String,
    val isSelected: Boolean = false
)

data class MuscleHeatmapUiModel(
    val periodLabel: String = DateTimeUtils.monthLabel(0),
    val period: MuscleMapPeriod = MuscleMapPeriod.AllTime,
    val periodOptions: List<MuscleMapPeriodOptionUiModel> = emptyList(),
    val totalSets: Int = 0,
    val totalLoad: Int = 0,
    val mappedExerciseCount: Int = 0,
    val totalExerciseCount: Int = 0,
    val muscles: List<MuscleProgressUiModel> = emptyList(),
    val topMuscles: List<MuscleProgressUiModel> = emptyList(),
    val selectedMuscleId: String? = null,
    val selectedMuscleLabel: String? = null,
    val selectedMuscleExercises: List<MuscleExerciseContributionUiModel> = emptyList(),
    val unmappedExercises: List<UnmappedExerciseUiModel> = emptyList(),
    val exerciseMappings: List<ExerciseMappingUiModel> = emptyList(),
    val manualEditorExerciseName: String? = null,
    val manualMuscles: List<MuscleOptionUiModel> = emptyList()
)

data class TrainingRecommendationUiModel(
    val id: String,
    val title: String,
    val supporting: String,
    val priorityLabel: String
)

data class MissionProgressUiModel(
    val id: String,
    val title: String,
    val cadenceLabel: String,
    val summary: String,
    val progressLabel: String,
    val progress: Int,
    val goal: Int,
    val progressFraction: Float = 0f,
    val isComplete: Boolean = false
)

data class RankProgressUiModel(
    val id: String,
    val levelRequirement: Int,
    val title: String,
    val requiredXp: Int,
    val xpRemaining: Int,
    val progressFraction: Float = 0f,
    val isCurrent: Boolean = false,
    val isUnlocked: Boolean = false
)

data class AchievementPreviewUiModel(
    val id: String,
    val title: String,
    val description: String,
    val badgeName: String,
    val badgeRarity: BadgeRarity,
    val rewardXp: Int,
    val progressLabel: String,
    val statusLabel: String,
    val progress: Int,
    val goal: Int,
    val progressFraction: Float = 0f,
    val isUnlocked: Boolean = false
)

data class TodayPlanUiModel(
    val focus: SmartWorkoutFocus,
    val rhythm: WeeklyTrainingRhythm,
    val exerciseCount: Int,
    val setCount: Int,
    val estimatedDurationMinutes: Int,
    val effortAdjustment: SmartWorkoutEffortAdjustment? = null,
    val recommendedLaunchToken: String? = null,
    val trainAnywayLaunchToken: String? = null
)

data class TodayHeroMetricsUiModel(
    val totalWorkouts: Int = 0,
    val weeklyStreakWeeks: Int = 0,
    val totalVolume: Double = 0.0
)

data class WeeklyTrainingDayUiModel(
    val date: LocalDate,
    val isCompleted: Boolean,
    val isToday: Boolean
)

data class WeeklyTrainingSummaryUiModel(
    val days: List<WeeklyTrainingDayUiModel> = emptyList(),
    val workouts: List<WorkoutSessionSummary> = emptyList(),
    val completedWorkoutCount: Int = 0,
    val completedTrainingDays: Int = 0,
    val targetTrainingDays: Int = 0,
    val estimatedMinutes: Int = 0,
    val totalVolume: Double = 0.0
)

data class WorkoutListUiState(
    val isLoading: Boolean = false,
    val loadError: LocalizedText? = null,
    val monthOffset: Int = 0,
    val weekOffset: Int = 0,
    val monthLabel: String = DateTimeUtils.monthLabel(0),
    val sessions: List<WorkoutSessionSummary> = emptyList(),
    val hasAnyWorkout: Boolean = false,
    val showFirstWorkoutActivation: Boolean = false,
    val todayPlan: TodayPlanUiModel? = null,
    val hasCompletedWorkoutToday: Boolean = false,
    val weeklyTrainingSummary: WeeklyTrainingSummaryUiModel = WeeklyTrainingSummaryUiModel(),
    val todayHeroMetrics: TodayHeroMetricsUiModel = TodayHeroMetricsUiModel(),
    val dashboardStats: DashboardStats = DashboardStats(
        workoutCount = 0,
        totalVolume = 0.0,
        averageIntensity = 0.0,
        streakDays = 0,
        weeklyStreakWeeks = 0
    ),
    val soloProgress: SoloProgressUiModel = SoloProgressUiModel(),
    val activityHeatmap: ActivityHeatmapUiModel = ActivityHeatmapUiModel(),
    val muscleHeatmap: MuscleHeatmapUiModel = MuscleHeatmapUiModel(),
    val trainingRecommendations: List<TrainingRecommendationUiModel> = emptyList(),
    val dailyMissions: List<MissionProgressUiModel> = emptyList(),
    val weeklyMissions: List<MissionProgressUiModel> = emptyList(),
    val monthlyMissions: List<MissionProgressUiModel> = emptyList(),
    val rankLadder: List<RankProgressUiModel> = emptyList(),
    val achievements: List<AchievementPreviewUiModel> = emptyList()
)

/**
 * Each destination owns a separate [WorkoutListViewModel]. Keep its Room subscriptions and
 * derived projections limited to the content that destination can actually render.
 */
enum class WorkoutListSurface {
    Today,
    Progress,
    Missions,
    Ranks;

    val needsTodayPlan: Boolean get() = this == Today
    val needsProgressInsights: Boolean get() = this == Progress
    val needsMissions: Boolean get() = this == Progress || this == Missions
    val needsSoloProgress: Boolean get() = this != Today
    val needsRankLadder: Boolean get() = this == Ranks
    val needsMuscleMappings: Boolean get() = needsTodayPlan || needsProgressInsights
}

@OptIn(ExperimentalCoroutinesApi::class)
class WorkoutListViewModel(
    private val repository: GymRepository,
    private val trainingProfileManager: TrainingProfileManager,
    private val trainingGuidanceManager: TrainingGuidanceManager,
    private val savedStateHandle: SavedStateHandle,
    private val surface: WorkoutListSurface = WorkoutListSurface.Today
) : ViewModel() {
    private val accountBinding = trainingGuidanceManager.activeBinding
    private val profileAccountBinding = trainingProfileManager.activeBinding
    private val zoneId = ZoneId.systemDefault()
    private val monthOffset = MutableStateFlow(0)
    private val weekOffset = MutableStateFlow(0)
    private val muscleMapPeriod = MutableStateFlow(MuscleMapPeriod.AllTime)
    private val selectedMuscleId = MutableStateFlow<String?>(null)
    private val manualMappingExerciseName = MutableStateFlow<String?>(null)
    private val recommendationRefresh = MutableStateFlow(0L)
    private val loadGeneration = MutableStateFlow(0L)
    @Volatile
    private var latestRecommendationContext = WorkoutRecommendationContext()
    private val activationLaunchLock = Any()
    private val recommendedLaunchMutationMutex = Mutex()
    private val activationLaunchMutationMutex = Mutex()

    private val sessionsFlow = monthOffset.flatMapLatest { offset ->
        repository.observeSessionsForMonth(offset).map { sessions ->
            WorkoutMonthSessions(offset = offset, sessions = sessions)
        }
    }

    private val allSessionsFlow = repository.observeSessions()
        .let { sessions ->
            if (surface.needsTodayPlan) {
                sessions.onEach { summaries ->
                    accountBinding?.let { expectedBinding ->
                        trainingGuidanceManager.pruneFeedback(
                            ownedSessions = summaries.associate {
                                it.session.id to it.session.date
                            },
                            expectedAccountBinding = expectedBinding
                        )
                    }
                }.flowOn(Dispatchers.Default)
            } else {
                sessions
            }
        }

    private val exerciseHistoryFlow: Flow<List<ExerciseHistoryEntry>> =
        if (surface.needsProgressInsights) {
            repository.observeAllExerciseHistory()
        } else {
            flowOf(emptyList())
        }
    private val muscleMappingsFlow: Flow<List<ExerciseMuscleMappingEntity>> =
        if (surface.needsProgressInsights) {
            repository.observeExerciseMuscleMappings()
        } else {
            flowOf(emptyList())
        }

    private val recommendationContextLoad: Flow<WorkoutRecommendationContextLoad> =
        if (surface.needsTodayPlan) {
            generationScopedRecommendationContext(
                loadGeneration = loadGeneration,
                exercisesSource = repository::observeExercises,
                historySource = repository::observeAllExerciseHistory,
                loadProfilesSource = repository::observeExerciseLoadProfiles,
                muscleMappingsSource = repository::observeExerciseMuscleMappings
            )
        } else {
            flowOf(WorkoutRecommendationContextLoad.Loaded(WorkoutRecommendationContext()))
        }

    private val sourceState = combine(
        sessionsFlow,
        allSessionsFlow,
        exerciseHistoryFlow,
        weekOffset
    ) { month, allSessions, exerciseHistory, selectedWeekOffset ->
        WorkoutListSourceState(
            offset = month.offset,
            weekOffset = selectedWeekOffset,
            sessions = month.sessions,
            allSessions = allSessions,
            exerciseHistory = exerciseHistory
        )
    }

    private val muscleSelection: Flow<WorkoutMuscleSelection> =
        if (surface.needsProgressInsights) {
            combine(
                muscleMapPeriod,
                selectedMuscleId,
                manualMappingExerciseName,
                muscleMappingsFlow
            ) { period, muscleId, editorName, mappings ->
                WorkoutMuscleSelection(period, muscleId, editorName, mappings)
            }
        } else {
            flowOf(
                WorkoutMuscleSelection(
                    period = MuscleMapPeriod.AllTime,
                    muscleId = null,
                    editorName = null,
                    mappings = emptyList()
                )
            )
        }

    private val experienceInputs: Flow<WorkoutExperienceState> =
        if (surface.needsTodayPlan) {
            combine(
                trainingProfileManager.profile,
                trainingGuidanceManager.activationDismissed,
                trainingGuidanceManager.feedback,
                recommendationContextLoad
            ) { profile, activationDismissed, feedback, contextLoad ->
                val context = when (contextLoad) {
                    is WorkoutRecommendationContextLoad.Loaded -> contextLoad.context.also {
                        latestRecommendationContext = it
                    }
                    is WorkoutRecommendationContextLoad.Failed -> {
                        latestRecommendationContext = WorkoutRecommendationContext()
                        throw contextLoad.error
                    }
                }
                WorkoutExperienceState(profile, activationDismissed, feedback, context)
            }
        } else {
            trainingProfileManager.profile.map { profile ->
                WorkoutExperienceState(
                    profile = profile,
                    activationDismissed = false,
                    feedback = emptyMap(),
                    context = WorkoutRecommendationContext()
                )
            }
        }
    private val experienceState: Flow<WorkoutExperienceState> =
        if (surface.needsTodayPlan) {
            combine(experienceInputs, recommendationRefresh) { state, _ -> state }
        } else {
            experienceInputs
        }

    val uiState: StateFlow<WorkoutListUiState> = loadGeneration.flatMapLatest {
        combine(
            sourceState,
            muscleSelection,
            experienceState
        ) { source, selection, experience ->
        val offset = source.offset
        val selectedWeekOffset = source.weekOffset
        val sessions = source.sessions
        val allSessions = source.allSessions
        val exerciseHistory = source.exerciseHistory
        val muscleMappings = selection.mappings
        val nowMillis = System.currentTimeMillis()
        val dashboardStats = if (surface.needsSoloProgress) {
            buildDashboardStatsForMonth(
                monthOffset = offset,
                targetWorkoutsPerWeek = experience.profile.workoutsPerWeek.coerceIn(2, 6),
                monthSessions = sessions,
                allSessions = allSessions,
                nowMillis = nowMillis,
                zoneId = zoneId
            )
        } else {
            EMPTY_DASHBOARD_STATS
        }
        val missionBoard = if (surface.needsMissions) {
            AdaptiveMissionBoardSource.build(
                sessions = allSessions,
                anchorDate = LocalDate.now(zoneId),
                zoneId = zoneId
            )
        } else {
            AdaptiveMissionBoard(
                daily = emptyList(),
                weekly = emptyList(),
                monthly = emptyList()
            )
        }
        val dailyMissions = missionBoard.daily.map(::missionUiModel)
        val weeklyMissions = missionBoard.weekly.map(::missionUiModel)
        val monthlyMissions = missionBoard.monthly.map(::missionUiModel)
        val soloProgress = if (surface.needsSoloProgress) {
            buildSoloProgress(
                allSessions = allSessions,
                monthSessions = sessions,
                streakDays = dashboardStats.streakDays,
                weeklyStreakWeeks = dashboardStats.weeklyStreakWeeks,
                weeklyTarget = experience.profile.workoutsPerWeek
            )
        } else {
            SoloProgressUiModel()
        }
        val todayPlan = if (surface.needsTodayPlan) {
            buildTodayPlan(
                allSessions = allSessions,
                profile = experience.profile,
                feedback = experience.feedback,
                context = experience.context
            )
        } else {
            null
        }
        val todayHeroMetrics = if (surface.needsTodayPlan) {
            buildTodayHeroMetrics(
                sessions = allSessions,
                weeklyStreakWeeks = WeeklyStreakCalculator.current(
                    sessionTimestamps = allSessions.map { it.session.date },
                    targetWorkoutsPerWeek = experience.profile.workoutsPerWeek,
                    nowMillis = nowMillis,
                    zoneId = zoneId
                )
            )
        } else {
            TodayHeroMetricsUiModel()
        }
        val weeklyTrainingSummary = if (surface.needsTodayPlan) {
            buildWeeklyTrainingSummary(
                sessions = allSessions,
                targetTrainingDays = experience.profile.workoutsPerWeek,
                nowMillis = nowMillis,
                zoneId = zoneId,
                weekOffset = selectedWeekOffset
            )
        } else {
            WeeklyTrainingSummaryUiModel()
        }
        WorkoutListUiState(
            isLoading = false,
            monthOffset = offset,
            weekOffset = selectedWeekOffset,
            monthLabel = DateTimeUtils.monthLabel(offset, currentLocale(), zoneId),
            sessions = sessions,
            hasAnyWorkout = allSessions.isNotEmpty(),
            showFirstWorkoutActivation = surface.needsTodayPlan &&
                allSessions.isEmpty() && !experience.activationDismissed,
            todayPlan = todayPlan,
            hasCompletedWorkoutToday = surface.needsTodayPlan &&
                hasCompletedWorkoutToday(
                    sessions = allSessions,
                    nowMillis = nowMillis,
                    zoneId = zoneId
                ),
            weeklyTrainingSummary = weeklyTrainingSummary,
            todayHeroMetrics = todayHeroMetrics,
            dashboardStats = dashboardStats,
            soloProgress = soloProgress,
            activityHeatmap = if (surface.needsProgressInsights) {
                buildHeatmap(offset, sessions)
            } else {
                ActivityHeatmapUiModel()
            },
            muscleHeatmap = if (surface.needsProgressInsights) {
                buildMuscleHeatmap(
                    exerciseHistory = exerciseHistory,
                    period = selection.period,
                    selectedMuscleId = selection.muscleId,
                    manualEditorExerciseName = selection.editorName,
                    muscleMappings = muscleMappings
                )
            } else {
                MuscleHeatmapUiModel()
            },
            trainingRecommendations = if (surface.needsProgressInsights) {
                buildTrainingRecommendations(
                    exerciseHistory = exerciseHistory,
                    muscleMappings = muscleMappings
                )
            } else {
                emptyList()
            },
            dailyMissions = dailyMissions,
            weeklyMissions = weeklyMissions,
            monthlyMissions = monthlyMissions,
            rankLadder = if (surface.needsRankLadder) {
                buildRankLadder(soloProgress.totalXp)
            } else {
                emptyList()
            },
            achievements = if (surface.needsMissions) {
                buildAchievements(
                    allSessions = allSessions,
                    targetWorkoutsPerWeek = experience.profile.workoutsPerWeek
                )
            } else {
                emptyList()
            }
        )
        }.catch { error ->
            if (error is CancellationException) throw error
            emit(
                WorkoutListUiState(
                    isLoading = false,
                    loadError = LocalizedText(R.string.workouts_load_failed)
                )
            )
        }
    }.flowOn(Dispatchers.Default).stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WorkoutListUiState(isLoading = true)
    )

    init {
        if (surface.needsMuscleMappings) {
            viewModelScope.launch {
                repository.seedDefaultExerciseMuscleMappings()
            }
        }
    }

    fun buildFirstWorkoutLaunch(
        goal: TrainingGoal,
        workoutsPerWeek: Int,
        effort: FirstWorkoutEffort
    ): String? {
        val profile = runCatching {
            trainingProfileForActivation(goal, workoutsPerWeek)
        }.getOrNull() ?: return null
        val expectedAccountBinding = accountBinding ?: return null
        if (trainingGuidanceManager.activeBinding != expectedAccountBinding) return null
        val expectedProfileAccountBinding = profileAccountBinding ?: return null
        if (trainingProfileManager.activeBinding != expectedProfileAccountBinding) return null
        val context = latestRecommendationContext
        val token = buildLaunchToken(
            profile = profile,
            effort = effort.toSmartWorkoutEffort(),
            context = context,
            origin = SmartWorkoutLaunchOrigin.Activation,
            feedback = null,
            accountBinding = expectedAccountBinding
        ) ?: return null
        val previousProfile = trainingProfileManager.profile.value
        val previousDismissed = trainingGuidanceManager.activationDismissed.value
        val fingerprint = runCatching {
            context.fingerprint(profile)
        }.getOrNull() ?: return null
        val exactPlan = runCatching {
            SmartWorkoutLaunchPlanCodec.decode(
                encoded = token,
                expectedAccountBinding = expectedAccountBinding,
                expectedTrainingProfile = profile,
                expectedStateFingerprint = fingerprint
            )
        }.getOrNull()?.takeIf { decoded ->
            decoded.origin == SmartWorkoutLaunchOrigin.Activation &&
                decoded.trainingProfile == profile &&
                decoded.exercises.isNotEmpty()
        } ?: return null
        if (exactPlan.exercises.isEmpty()) return null

        return synchronized(activationLaunchLock) {
            if (trainingGuidanceManager.activeBinding != expectedAccountBinding ||
                trainingProfileManager.activeBinding != expectedProfileAccountBinding ||
                trainingProfileManager.profile.value != previousProfile ||
                trainingGuidanceManager.activationDismissed.value != previousDismissed
            ) {
                return@synchronized null
            }
            savedStateHandle[PENDING_ACTIVATION_KEY] = PendingFirstWorkoutActivationCodec.encode(
                PendingFirstWorkoutActivation(
                    token = token,
                    targetProfile = profile,
                    previousProfile = previousProfile,
                    previousDismissed = previousDismissed
                )
            )
            token
        }
    }

    fun cancelFirstWorkoutLaunch(token: String) {
        synchronized(activationLaunchLock) {
            val pending = pendingFirstWorkoutActivation()
            if (pending?.token == token) {
                savedStateHandle.remove<String>(PENDING_ACTIVATION_KEY)
            }
        }
    }

    fun refreshTodayPlan() {
        recommendationRefresh.value += 1L
    }

    fun retryLoad() {
        latestRecommendationContext = WorkoutRecommendationContext()
        loadGeneration.value += 1L
    }

    internal suspend fun resolveLaunchPlan(encoded: String): SmartWorkoutLaunchPlan? {
        if (!SmartWorkoutLaunchPlanCodec.isTokenShapeValid(encoded)) return null
        val expectedAccountBinding = accountBinding ?: return null
        if (trainingGuidanceManager.activeBinding != expectedAccountBinding) return null
        val expectedProfileAccountBinding = profileAccountBinding ?: return null
        if (trainingProfileManager.activeBinding != expectedProfileAccountBinding) return null
        val pendingBeforeLoad = synchronized(activationLaunchLock) {
            pendingFirstWorkoutActivation()?.takeIf { it.token == encoded }
        }
        val expectedProfile = pendingBeforeLoad?.targetProfile
            ?: trainingProfileManager.profile.value
        val context = latestRecommendationContext
        if (context.exercises.isEmpty()) {
            return rejectPendingActivation(encoded, pendingBeforeLoad)
        }
        val fingerprint = runCatching { context.fingerprint(expectedProfile) }.getOrNull()
            ?: return rejectPendingActivation(encoded, pendingBeforeLoad)
        val decoded = runCatching {
            SmartWorkoutLaunchPlanCodec.decode(
                encoded = encoded,
                expectedAccountBinding = expectedAccountBinding,
                expectedTrainingProfile = expectedProfile,
                expectedStateFingerprint = fingerprint
            )
        }.getOrNull() ?: return rejectPendingActivation(encoded, pendingBeforeLoad)

        return when (decoded.origin) {
            SmartWorkoutLaunchOrigin.Recommended -> {
                if (pendingBeforeLoad != null ||
                    trainingGuidanceManager.activeBinding != expectedAccountBinding ||
                    trainingProfileManager.activeBinding != expectedProfileAccountBinding ||
                    trainingProfileManager.profile.value != expectedProfile ||
                    SmartWorkoutLaunchUseRegistry.isConsumed(
                        encoded = savedStateHandle[CONSUMED_LAUNCHES_KEY],
                        launchId = decoded.launchId,
                        nowMillis = System.currentTimeMillis()
                    )
                ) {
                    null
                } else {
                    decoded
                }
            }
            SmartWorkoutLaunchOrigin.Activation -> synchronized(activationLaunchLock) {
                val pending = pendingFirstWorkoutActivation()
                if (pending == null || pending != pendingBeforeLoad ||
                    pending.token != encoded ||
                    trainingGuidanceManager.activeBinding != expectedAccountBinding ||
                    trainingProfileManager.activeBinding != expectedProfileAccountBinding ||
                    trainingProfileManager.profile.value != pending.previousProfile ||
                    trainingGuidanceManager.activationDismissed.value != pending.previousDismissed
                ) {
                    savedStateHandle.remove<String>(PENDING_ACTIVATION_KEY)
                    return@synchronized null
                }
                decoded
            }
        }
    }

    internal suspend fun handOffLaunchPlan(
        encoded: String,
        validate: (SmartWorkoutLaunchPlan) -> Boolean,
        accept: (SmartWorkoutLaunchPlan) -> Boolean
    ): Boolean {
        val expectedAccountBinding = accountBinding ?: return false
        if (trainingGuidanceManager.activeBinding != expectedAccountBinding) return false
        val expectedProfileAccountBinding = profileAccountBinding ?: return false
        if (trainingProfileManager.activeBinding != expectedProfileAccountBinding) return false
        val decoded = resolveLaunchPlan(encoded) ?: return false
        if (!runCatching { validate(decoded) }.getOrDefault(false)) {
            cancelFirstWorkoutLaunch(encoded)
            return false
        }
        if (decoded.origin == SmartWorkoutLaunchOrigin.Recommended) {
            return recommendedLaunchMutationMutex.withLock {
                val current = resolveLaunchPlan(encoded) ?: return@withLock false
                if (current != decoded ||
                    !runCatching { validate(current) }.getOrDefault(false)
                ) {
                    return@withLock false
                }
                val nowMillis = System.currentTimeMillis()
                val consumed = SmartWorkoutLaunchUseRegistry.consume(
                    encoded = savedStateHandle[CONSUMED_LAUNCHES_KEY],
                    launchId = decoded.launchId,
                    createdAtMillis = decoded.createdAtMillis,
                    nowMillis = nowMillis
                ) ?: return@withLock false
                if (!runCatching { accept(current) }.getOrDefault(false)) {
                    return@withLock false
                }
                savedStateHandle[CONSUMED_LAUNCHES_KEY] = consumed
                true
            }
        }

        return synchronized(activationLaunchLock) {
            val pending = pendingFirstWorkoutActivation()
            if (pending == null || pending.token != encoded ||
                trainingGuidanceManager.activeBinding != decoded.accountBinding ||
                trainingProfileManager.activeBinding != expectedProfileAccountBinding ||
                trainingProfileManager.profile.value != pending.previousProfile ||
                trainingGuidanceManager.activationDismissed.value != pending.previousDismissed
            ) {
                savedStateHandle.remove<String>(PENDING_ACTIVATION_KEY)
                return@synchronized false
            }
                val accepted = FirstWorkoutActivationCommitter.commit(
                    candidateToken = encoded,
                    targetProfile = pending.targetProfile,
                    previousProfile = pending.previousProfile,
                    previousDismissed = pending.previousDismissed,
                    isExactPlan = { candidate -> candidate == encoded },
                    persistProfile = { profile ->
                        trainingProfileManager.updateProfile(
                            profile,
                            expectedProfileAccountBinding
                        )
                    },
                    persistDismissed = { dismissed ->
                        trainingGuidanceManager.setActivationDismissed(
                            dismissed,
                            expectedAccountBinding
                        )
                    },
                    acknowledgeHandoff = { candidate ->
                        if (pendingFirstWorkoutActivation()?.token != candidate ||
                            trainingGuidanceManager.activeBinding != expectedAccountBinding ||
                            trainingProfileManager.activeBinding != expectedProfileAccountBinding
                        ) {
                            false
                        } else if (!runCatching { accept(decoded) }.getOrDefault(false)) {
                            savedStateHandle.remove<String>(PENDING_ACTIVATION_KEY)
                            false
                        } else {
                            savedStateHandle.remove<String>(PENDING_ACTIVATION_KEY)
                            trainingGuidanceManager.activeBinding == expectedAccountBinding &&
                                trainingProfileManager.activeBinding == expectedProfileAccountBinding
                        }
                    },
                    restoreProfile = { profile ->
                        trainingProfileManager.restoreProfileForBinding(
                            profile,
                            expectedProfileAccountBinding
                        )
                    },
                    restoreDismissed = { dismissed ->
                        trainingGuidanceManager.restoreActivationDismissedForBinding(
                            dismissed,
                            expectedAccountBinding
                        )
                    }
                )
            accepted == encoded
        }
    }

    /** Starts the exact Today snapshot without routing through the editor or touching history/Garmin. */
    internal suspend fun startRecommendedPlan(encoded: String): Boolean =
        recommendedLaunchMutationMutex.withLock {
            val expectedAccountBinding = accountBinding ?: return@withLock false
            val expectedProfileAccountBinding = profileAccountBinding ?: return@withLock false
            val decoded = resolveLaunchPlan(encoded)?.takeIf {
                it.origin == SmartWorkoutLaunchOrigin.Recommended
            } ?: return@withLock false
            if (trainingGuidanceManager.activeBinding != expectedAccountBinding ||
                trainingProfileManager.activeBinding != expectedProfileAccountBinding ||
                trainingProfileManager.profile.value != decoded.trainingProfile
            ) {
                return@withLock false
            }
            val started = try {
                RecommendedWorkoutStartCommitter.start(
                    plan = decoded,
                    claimAndPersist = {
                        if (trainingGuidanceManager.activeBinding != expectedAccountBinding ||
                            trainingProfileManager.activeBinding != expectedProfileAccountBinding ||
                            trainingProfileManager.profile.value != decoded.trainingProfile
                        ) {
                            false
                        } else {
                            val consumed = SmartWorkoutLaunchUseRegistry.consume(
                                encoded = savedStateHandle[CONSUMED_LAUNCHES_KEY],
                                launchId = decoded.launchId,
                                createdAtMillis = decoded.createdAtMillis,
                                nowMillis = System.currentTimeMillis()
                            )
                            if (consumed == null) {
                                false
                            } else {
                                savedStateHandle[CONSUMED_LAUNCHES_KEY] = consumed
                                savedStateHandle.get<String>(CONSUMED_LAUNCHES_KEY) == consumed
                            }
                        }
                    },
                    startActiveWorkout = { drafts ->
                        repository.startActiveWorkout(
                            date = System.currentTimeMillis(),
                            note = null,
                            workoutExercises = drafts
                        )
                    }
                )
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: Throwable) {
                false
            }
            started &&
                trainingGuidanceManager.activeBinding == expectedAccountBinding &&
                trainingProfileManager.activeBinding == expectedProfileAccountBinding
        }

    /** Applies the first-workout profile and starts the exact plan as one acknowledged action. */
    internal suspend fun startFirstWorkoutPlan(encoded: String): Boolean =
        activationLaunchMutationMutex.withLock {
            val expectedAccountBinding = accountBinding ?: return@withLock false
            val expectedProfileAccountBinding = profileAccountBinding ?: return@withLock false
            val decoded = resolveLaunchPlan(encoded)?.takeIf {
                it.origin == SmartWorkoutLaunchOrigin.Activation
            } ?: return@withLock false
            val pending = synchronized(activationLaunchLock) {
                pendingFirstWorkoutActivation()?.takeIf { it.token == encoded }
            } ?: return@withLock false

            try {
                val started = FirstWorkoutActivationDirectStarter.start(
                    plan = decoded,
                    token = encoded,
                    previousProfile = pending.previousProfile,
                    previousDismissed = pending.previousDismissed,
                    claimAndPersist = {
                        val stillPending = synchronized(activationLaunchLock) {
                            pendingFirstWorkoutActivation() == pending
                        }
                        if (!stillPending ||
                            trainingGuidanceManager.activeBinding != expectedAccountBinding ||
                            trainingProfileManager.activeBinding != expectedProfileAccountBinding ||
                            trainingProfileManager.profile.value != pending.previousProfile ||
                            trainingGuidanceManager.activationDismissed.value != pending.previousDismissed
                        ) {
                            false
                        } else {
                            val consumed = SmartWorkoutLaunchUseRegistry.consume(
                                encoded = savedStateHandle[CONSUMED_LAUNCHES_KEY],
                                launchId = decoded.launchId,
                                createdAtMillis = decoded.createdAtMillis,
                                nowMillis = System.currentTimeMillis()
                            )
                            if (consumed == null) {
                                false
                            } else {
                                savedStateHandle[CONSUMED_LAUNCHES_KEY] = consumed
                                savedStateHandle.get<String>(CONSUMED_LAUNCHES_KEY) == consumed
                            }
                        }
                    },
                    persistProfile = { profile ->
                        trainingProfileManager.updateProfile(
                            profile,
                            expectedProfileAccountBinding
                        )
                    },
                    persistDismissed = { dismissed ->
                        trainingGuidanceManager.setActivationDismissed(
                            dismissed,
                            expectedAccountBinding
                        )
                    },
                    restoreProfile = { profile ->
                        trainingProfileManager.restoreProfileForBinding(
                            profile,
                            expectedProfileAccountBinding
                        )
                    },
                    restoreDismissed = { dismissed ->
                        trainingGuidanceManager.restoreActivationDismissedForBinding(
                            dismissed,
                            expectedAccountBinding
                        )
                    },
                    startActiveWorkout = { drafts ->
                        val result = repository.startActiveWorkout(
                            date = System.currentTimeMillis(),
                            note = null,
                            workoutExercises = drafts
                        )
                        if (trainingGuidanceManager.activeBinding == expectedAccountBinding &&
                            trainingProfileManager.activeBinding == expectedProfileAccountBinding
                        ) {
                            result
                        } else {
                            com.example.gymapp.data.repository.StartActiveWorkoutResult.AlreadyActive
                        }
                    }
                )
                started &&
                    trainingGuidanceManager.activeBinding == expectedAccountBinding &&
                    trainingProfileManager.activeBinding == expectedProfileAccountBinding
            } finally {
                synchronized(activationLaunchLock) {
                    if (pendingFirstWorkoutActivation()?.token == encoded) {
                        savedStateHandle.remove<String>(PENDING_ACTIVATION_KEY)
                    }
                }
            }
        }

    private fun rejectPendingActivation(
        encoded: String,
        pending: PendingFirstWorkoutActivation?
    ): SmartWorkoutLaunchPlan? {
        if (pending?.token == encoded) cancelFirstWorkoutLaunch(encoded)
        return null
    }

    private fun pendingFirstWorkoutActivation(): PendingFirstWorkoutActivation? =
        PendingFirstWorkoutActivationCodec.decode(savedStateHandle[PENDING_ACTIVATION_KEY])

    fun dismissFirstWorkoutActivation(): Boolean {
        val expectedAccountBinding = accountBinding ?: return false
        return trainingGuidanceManager.dismissActivation(expectedAccountBinding)
    }

    fun restoreFirstWorkoutActivationDismissal(dismissed: Boolean): Boolean {
        val expectedAccountBinding = accountBinding ?: return false
        return trainingGuidanceManager.restoreActivationDismissedForBinding(
            dismissed,
            expectedAccountBinding
        )
    }

    fun isFirstWorkoutActivationDismissed(): Boolean =
        trainingGuidanceManager.activationDismissed.value

    fun previousMonth() {
        monthOffset.value -= 1
    }

    fun nextMonth() {
        monthOffset.value += 1
    }

    fun currentMonth() {
        monthOffset.value = 0
    }

    fun previousWeek() {
        weekOffset.value = (weekOffset.value - 1).coerceAtLeast(-5_200)
    }

    fun nextWeek() {
        weekOffset.value = (weekOffset.value + 1).coerceAtMost(0)
    }

    fun currentWeek() {
        weekOffset.value = 0
    }

    fun selectMuscleMapPeriod(period: MuscleMapPeriod) {
        muscleMapPeriod.value = period
    }

    fun selectMuscle(muscleId: String) {
        selectedMuscleId.value = if (selectedMuscleId.value == muscleId) null else muscleId
    }

    fun openManualMuscleMapping(exerciseName: String) {
        manualMappingExerciseName.value = exerciseName
    }

    fun closeManualMuscleMapping() {
        manualMappingExerciseName.value = null
    }

    fun saveManualMuscleMapping(exerciseName: String, muscleIds: List<String>) {
        viewModelScope.launch {
            repository.saveExerciseMuscleMapping(
                exerciseName = exerciseName,
                muscleIds = muscleIds
            )
            manualMappingExerciseName.value = null
        }
    }

    fun deleteSession(sessionId: Long) {
        viewModelScope.launch {
            repository.deleteWorkoutSessionById(sessionId)
        }
    }

    private fun buildTodayPlan(
        allSessions: List<WorkoutSessionSummary>,
        profile: TrainingProfile,
        feedback: Map<Long, WorkoutFeedbackRecord>,
        context: WorkoutRecommendationContext
    ): TodayPlanUiModel? {
        if (context.exercises.isEmpty()) return null
        val nowMillis = System.currentTimeMillis()
        val latestSession = allSessions
            .asSequence()
            .filter { it.session.date <= nowMillis }
            .maxWithOrNull(
            compareBy<WorkoutSessionSummary> { it.session.date }.thenBy { it.session.id }
        )
        val feedbackSignal = latestSession?.let { session ->
            feedback[session.session.id]
                ?.takeIf { it.sessionStartedAtMillis == session.session.date }
                ?.let { record ->
                SmartCoachFeedback(
                    sessionId = session.session.id,
                    sessionDateMillis = session.session.date,
                    feedback = record.feedback
                )
            }
        }
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = context.exercises,
            history = context.history,
            trainingProfile = profile,
            loadProfiles = context.loadProfiles,
            manualMuscleMappings = context.muscleMappings.toManualContributionMap(),
            effort = SmartWorkoutEffort.Auto,
            latestFeedback = feedbackSignal,
            nowMillis = nowMillis
        )
        if (plan.exercises.isEmpty()) return null
        val rhythm = WeeklyTrainingRhythmCalculator.calculate(
            sessionTimestamps = allSessions.map { it.session.date },
            targetTrainingDays = profile.workoutsPerWeek.coerceIn(2, 6),
            recoveryRecommended = plan.appliedEffort == SmartWorkoutEffort.Recovery,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
        val recommendedToken = encodeLaunchPlan(
            plan = plan,
            profile = profile,
            origin = SmartWorkoutLaunchOrigin.Recommended,
            context = context,
            createdAtMillis = nowMillis
        ).takeIf { rhythm.decision == WeeklyTrainingDecision.Train }
            ?: if (rhythm.decision == WeeklyTrainingDecision.Recovery) {
                buildLaunchToken(
                    profile = profile,
                    effort = SmartWorkoutEffort.Recovery,
                    context = context,
                    origin = SmartWorkoutLaunchOrigin.Recommended,
                    feedback = feedbackSignal,
                    nowMillis = nowMillis
                )
            } else {
                null
            }
        val trainAnywayToken = if (rhythm.decision == WeeklyTrainingDecision.Rest) {
            buildLaunchToken(
                profile = profile,
                effort = SmartWorkoutEffort.Recovery,
                context = context,
                origin = SmartWorkoutLaunchOrigin.Recommended,
                feedback = feedbackSignal,
                nowMillis = nowMillis
            )
        } else {
            null
        }
        return TodayPlanUiModel(
            focus = plan.focus,
            rhythm = rhythm,
            exerciseCount = plan.exercises.size,
            setCount = plan.exercises.sumOf { it.recommendation.sets.size },
            estimatedDurationMinutes = estimateWorkoutMinutes(
                exerciseCount = plan.exercises.size,
                setCount = plan.exercises.sumOf { it.recommendation.sets.size }
            ),
            effortAdjustment = plan.effortAdjustment,
            recommendedLaunchToken = recommendedToken,
            trainAnywayLaunchToken = trainAnywayToken
        )
    }

    private fun buildLaunchToken(
        profile: TrainingProfile,
        effort: SmartWorkoutEffort,
        context: WorkoutRecommendationContext,
        origin: SmartWorkoutLaunchOrigin,
        feedback: SmartCoachFeedback?,
        accountBinding: String? = this.accountBinding,
        nowMillis: Long = System.currentTimeMillis()
    ): String? {
        if (context.exercises.isEmpty()) return null
        val plan = WorkoutRecommendationEngine.buildWorkoutPlan(
            exercises = context.exercises,
            history = context.history,
            trainingProfile = profile,
            loadProfiles = context.loadProfiles,
            manualMuscleMappings = context.muscleMappings.toManualContributionMap(),
            effort = effort,
            latestFeedback = feedback,
            nowMillis = nowMillis
        )
        if (plan.exercises.isEmpty()) return null
        return encodeLaunchPlan(
            plan,
            profile,
            origin,
            context,
            accountBinding,
            createdAtMillis = nowMillis
        )
    }

    private fun encodeLaunchPlan(
        plan: com.example.gymapp.data.repository.SmartWorkoutPlan,
        profile: TrainingProfile,
        origin: SmartWorkoutLaunchOrigin,
        context: WorkoutRecommendationContext,
        accountBinding: String? = this.accountBinding,
        createdAtMillis: Long = System.currentTimeMillis()
    ): String? {
        val safeAccountBinding = accountBinding ?: return null
        if (trainingGuidanceManager.activeBinding != safeAccountBinding) return null
        return runCatching {
            SmartWorkoutLaunchPlanCodec.encode(
                SmartWorkoutLaunchPlanCodec.fromPlan(
                    plan = plan,
                    profile = profile,
                    origin = origin,
                    accountBinding = safeAccountBinding,
                    stateFingerprint = context.fingerprint(profile),
                    createdAtMillis = createdAtMillis
                )
            )
        }.getOrNull()
    }

    private fun buildSoloProgress(
        allSessions: List<WorkoutSessionSummary>,
        monthSessions: List<WorkoutSessionSummary>,
        streakDays: Int,
        weeklyStreakWeeks: Int,
        weeklyTarget: Int
    ): SoloProgressUiModel {
        val workoutXp = allSessions.sumOf(::sessionXp)
        val monthWorkoutXp = monthSessions.sumOf(::sessionXp)
        val totalXp = workoutXp
        val monthXp = monthWorkoutXp
        val levelInfo = calculateLevelProgress(totalXp)
        val currentTitle = titleForLevel(levelInfo.level)
        val nextTitle = nextTitleAfter(levelInfo.level)
        val summary = when {
            allSessions.isEmpty() -> t(
                en = "Log a workout to start your momentum.",
                uk = "Запиши тренування, щоб запустити свій темп."
            )
            weeklyStreakWeeks > 0 -> when {
                isUkrainian() -> "$weeklyStreakWeeks тиж. поспіль із $weeklyTarget тренуваннями."
                isRussian() -> "$weeklyStreakWeeks нед. подряд с $weeklyTarget тренировками."
                else -> "$weeklyStreakWeeks successful week${if (weeklyStreakWeeks == 1) "" else "s"} in a row."
            }
            monthXp > 0 -> t(
                en = "$monthXp XP earned this month.",
                uk = "За цей місяць зароблено $monthXp XP."
            )
            isUkrainian() -> "Тижнева ціль: $weeklyTarget"
            isRussian() -> "Недельная цель: $weeklyTarget"
            else -> "Weekly target: $weeklyTarget"
        }

        return SoloProgressUiModel(
            totalXp = totalXp,
            monthXp = monthXp,
            level = levelInfo.level,
            title = currentTitle,
            currentLevelXp = levelInfo.currentLevelXp,
            xpForNextLevel = levelInfo.xpForNextLevel,
            progressFraction = levelInfo.progressFraction,
            streakDays = streakDays,
            weeklyStreakWeeks = weeklyStreakWeeks,
            weeklyTarget = weeklyTarget,
            summary = summary,
            nextTitle = nextTitle
        )
    }

    private fun buildHeatmap(
        monthOffset: Int,
        sessions: List<WorkoutSessionSummary>
    ): ActivityHeatmapUiModel {
        val locale = currentLocale()
        val targetMonth = YearMonth.now(zoneId).plusMonths(monthOffset.toLong())
        val firstDay = targetMonth.atDay(1)
        val lastDay = targetMonth.atEndOfMonth()
        val today = LocalDate.now(zoneId)

        val sessionsByDay = sessions.groupBy { session ->
            Instant.ofEpochMilli(session.session.date).atZone(zoneId).toLocalDate()
        }
        val dailyLoads = sessionsByDay.mapValues { (_, daySessions) ->
            val volume = daySessions.sumOf { it.totalVolume }
            if (volume > 0.0) volume else daySessions.size.toDouble()
        }
        val maxDailyLoad = dailyLoads.values.maxOrNull() ?: 0.0

        val cells = mutableListOf<ActivityHeatmapDayUiModel>()
        repeat(firstDay.dayOfWeek.value - DayOfWeek.MONDAY.value) { index ->
            cells += ActivityHeatmapDayUiModel(id = "leading-$index")
        }

        var cursor = firstDay
        while (!cursor.isAfter(lastDay)) {
            val daySessions = sessionsByDay[cursor].orEmpty()
            val sessionCount = daySessions.size
            val totalVolume = daySessions.sumOf { it.totalVolume }
            val dailyLoad = dailyLoads[cursor] ?: 0.0
            val intensity = when {
                sessionCount == 0 || maxDailyLoad <= 0.0 -> 0f
                else -> (0.28f + (dailyLoad.toFloat() / maxDailyLoad.toFloat()) * 0.72f)
                    .coerceIn(0f, 1f)
            }
            cells += ActivityHeatmapDayUiModel(
                id = cursor.toString(),
                dayNumber = cursor.dayOfMonth,
                dayLabel = cursor.format(
                    DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(locale)
                ),
                sessionCount = sessionCount,
                totalVolume = totalVolume,
                intensity = intensity,
                isCurrentMonth = true,
                isToday = cursor == today
            )
            cursor = cursor.plusDays(1)
        }

        while (cells.size < 35 || cells.size % 7 != 0) {
            cells += ActivityHeatmapDayUiModel(id = "trailing-${cells.size}")
        }

        return ActivityHeatmapUiModel(
            monthLabel = DateTimeUtils.monthLabel(monthOffset, locale, zoneId),
            activeDays = sessionsByDay.size,
            sessionCount = sessions.size,
            totalVolume = sessions.sumOf { it.totalVolume },
            weeks = cells.chunked(7)
        )
    }

    private fun buildMuscleHeatmap(
        exerciseHistory: List<ExerciseHistoryEntry>,
        period: MuscleMapPeriod,
        selectedMuscleId: String?,
        manualEditorExerciseName: String?,
        muscleMappings: List<ExerciseMuscleMappingEntity>
    ): MuscleHeatmapUiModel {
        val manualMap = muscleMappings.toManualContributionMap()
        val historyEntries = exerciseHistory.filterForMusclePeriod(period)
        val distinctExerciseKeys = historyEntries
            .map { it.exerciseName.normalizedExerciseName() }
            .filter { it.isNotBlank() }
            .toSet()
        val statsByMuscle = MUSCLE_DEFINITIONS.associate { definition ->
            definition.id to MutableMuscleProgress()
        }.toMutableMap()
        val mappedExerciseKeys = linkedSetOf<String>()
        val unmappedExerciseStats = linkedMapOf<String, MutableExerciseContribution>()
        val selectedExerciseStats = linkedMapOf<String, MutableExerciseContribution>()
        val exerciseMappingStats = linkedMapOf<String, MutableExerciseMapping>()

        historyEntries.forEach { entry ->
            val exerciseKey = entry.exerciseName.normalizedExerciseName()
            val contributions = muscleContributionsForExercise(entry.exerciseName, manualMap)
            val exerciseMapping = exerciseMappingStats.getOrPut(entry.exerciseName) {
                MutableExerciseMapping(contributions = contributions)
            }
            exerciseMapping.setIds += entry.setId
            exerciseMapping.sessionIds += entry.sessionId
            if (contributions.isEmpty()) {
                val stats = unmappedExerciseStats.getOrPut(entry.exerciseName) {
                    MutableExerciseContribution()
                }
                stats.load += entry.estimatedLoad()
                stats.setIds += entry.setId
                stats.sessionIds += entry.sessionId
                return@forEach
            }

            mappedExerciseKeys += exerciseKey
            val setLoad = entry.estimatedLoad()
            contributions.forEach { contribution ->
                val stats = statsByMuscle.getOrPut(contribution.muscleId) {
                    MutableMuscleProgress()
                }
                stats.load += setLoad * contribution.weight
                stats.setIds += entry.setId
                stats.sessionIds += entry.sessionId
                stats.exerciseKeys += exerciseKey

                if (contribution.muscleId == selectedMuscleId) {
                    val exerciseStats = selectedExerciseStats.getOrPut(entry.exerciseName) {
                        MutableExerciseContribution()
                    }
                    exerciseStats.load += setLoad * contribution.weight
                    exerciseStats.setIds += entry.setId
                    exerciseStats.sessionIds += entry.sessionId
                }
            }
        }

        val muscleLabelById = MUSCLE_DEFINITIONS.associate { definition ->
            definition.id to t(en = definition.titleEn, uk = definition.titleUk)
        }
        val maxLoad = statsByMuscle.values.maxOfOrNull { it.load } ?: 0.0
        val muscles = MUSCLE_DEFINITIONS.map { definition ->
            val stats = statsByMuscle[definition.id] ?: MutableMuscleProgress()
            val loadRatio = if (maxLoad <= 0.0) {
                0.0
            } else {
                (stats.load / maxLoad).coerceIn(0.0, 1.0)
            }
            MuscleProgressUiModel(
                id = definition.id,
                label = t(en = definition.titleEn, uk = definition.titleUk),
                load = stats.load.roundToInt(),
                sets = stats.setIds.size,
                sessions = stats.sessionIds.size,
                exercises = stats.exerciseKeys.size,
                intensity = loadRatio.pow(0.72).toFloat().coerceIn(0f, 1f)
            )
        }
        val topMuscles = muscles
            .filter { it.load > 0 }
            .sortedByDescending { it.load }
            .take(5)
        val selectedLabel = selectedMuscleId
            ?.let { id -> MUSCLE_DEFINITIONS.firstOrNull { it.id == id } }
            ?.let { definition -> t(en = definition.titleEn, uk = definition.titleUk) }
        val selectedExercises = selectedExerciseStats
            .map { (exerciseName, stats) ->
                MuscleExerciseContributionUiModel(
                    exerciseName = exerciseName,
                    load = stats.load.roundToInt(),
                    sets = stats.setIds.size,
                    sessions = stats.sessionIds.size
                )
            }
            .sortedByDescending { it.load }
            .take(8)
        val unmappedExercises = unmappedExerciseStats
            .map { (exerciseName, stats) ->
                UnmappedExerciseUiModel(
                    exerciseName = exerciseName,
                    sets = stats.setIds.size,
                    sessions = stats.sessionIds.size
                )
            }
            .sortedWith(compareByDescending<UnmappedExerciseUiModel> { it.sets }.thenBy { it.exerciseName })
            .take(8)
        val exerciseMappings = exerciseMappingStats
            .map { (exerciseName, stats) ->
                val labels = stats.contributions
                    .mapNotNull { muscleLabelById[it.muscleId] }
                    .distinct()
                ExerciseMappingUiModel(
                    exerciseName = exerciseName,
                    muscleLabels = labels.joinToString(", "),
                    sets = stats.setIds.size,
                    sessions = stats.sessionIds.size,
                    isMapped = labels.isNotEmpty()
                )
            }
            .sortedWith(
                compareBy<ExerciseMappingUiModel> { it.isMapped }
                    .thenByDescending { it.sets }
                    .thenBy { it.exerciseName.lowercase(Locale.ROOT) }
            )
            .take(12)
        val manualEditorSelectedIds = manualEditorExerciseName
            ?.let { exerciseName ->
                manualMap[exerciseName.normalizedExerciseName()]
                    ?: muscleContributionsForExercise(exerciseName).takeIf { it.isNotEmpty() }
            }
            .orEmpty()
            .map { it.muscleId }
            .toSet()
        val manualMuscles = MUSCLE_DEFINITIONS.map { definition ->
            MuscleOptionUiModel(
                id = definition.id,
                label = t(en = definition.titleEn, uk = definition.titleUk),
                isSelected = definition.id in manualEditorSelectedIds
            )
        }

        return MuscleHeatmapUiModel(
            periodLabel = period.label(),
            period = period,
            periodOptions = MuscleMapPeriod.values().map { option ->
                MuscleMapPeriodOptionUiModel(
                    period = option,
                    label = option.label(),
                    isSelected = option == period
                )
            },
            totalSets = historyEntries.size,
            totalLoad = historyEntries.sumOf { it.estimatedLoad() }.roundToInt(),
            mappedExerciseCount = mappedExerciseKeys.size,
            totalExerciseCount = distinctExerciseKeys.size,
            muscles = muscles,
            topMuscles = topMuscles,
            selectedMuscleId = selectedMuscleId,
            selectedMuscleLabel = selectedLabel,
            selectedMuscleExercises = selectedExercises,
            unmappedExercises = unmappedExercises,
            exerciseMappings = exerciseMappings,
            manualEditorExerciseName = manualEditorExerciseName,
            manualMuscles = manualMuscles
        )
    }

    private fun List<ExerciseHistoryEntry>.filterForMusclePeriod(
        period: MuscleMapPeriod
    ): List<ExerciseHistoryEntry> {
        if (period == MuscleMapPeriod.AllTime) {
            return this
        }

        val today = LocalDate.now(zoneId)
        val startDate = when (period) {
            MuscleMapPeriod.AllTime -> LocalDate.MIN
            MuscleMapPeriod.Month -> today.withDayOfMonth(1)
            MuscleMapPeriod.Week -> today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        }
        val endDateExclusive = when (period) {
            MuscleMapPeriod.AllTime -> LocalDate.MAX
            MuscleMapPeriod.Month -> startDate.plusMonths(1)
            MuscleMapPeriod.Week -> startDate.plusWeeks(1)
        }
        val startMillis = startDate.atStartOfDay(zoneId).toInstant().toEpochMilli()
        val endMillis = endDateExclusive.atStartOfDay(zoneId).toInstant().toEpochMilli()
        return filter { entry -> entry.sessionDate in startMillis until endMillis }
    }

    private fun MuscleMapPeriod.label(): String {
        return when (this) {
            MuscleMapPeriod.AllTime -> t(en = "All time", uk = "За весь час")
            MuscleMapPeriod.Month -> t(en = "Month", uk = "Місяць")
            MuscleMapPeriod.Week -> t(en = "Week", uk = "Тиждень")
        }
    }

    private fun buildTrainingRecommendations(
        exerciseHistory: List<ExerciseHistoryEntry>,
        muscleMappings: List<ExerciseMuscleMappingEntity>
    ): List<TrainingRecommendationUiModel> {
        if (exerciseHistory.isEmpty()) {
            return listOf(
                TrainingRecommendationUiModel(
                    id = "start",
                    title = t(en = "Log a few workouts", uk = "Запиши кілька тренувань"),
                    supporting = t(
                        en = "Recommendations need enough history to compare muscle groups.",
                        uk = "Рекомендаціям потрібна історія, щоб порівнювати групи мʼязів."
                    ),
                    priorityLabel = t(en = "Setup", uk = "Старт")
                )
            )
        }

        val manualMap = muscleMappings.toManualContributionMap()
        val today = LocalDate.now(zoneId)
        val lastDateByMuscle = mutableMapOf<String, LocalDate>()
        val loadByMuscle = mutableMapOf<String, Double>()

        exerciseHistory.forEach { entry ->
            val entryDate = entry.sessionDate.toLocalDate()
            val setLoad = entry.estimatedLoad()
            muscleContributionsForExercise(entry.exerciseName, manualMap).forEach { contribution ->
                val previousDate = lastDateByMuscle[contribution.muscleId]
                if (previousDate == null || entryDate.isAfter(previousDate)) {
                    lastDateByMuscle[contribution.muscleId] = entryDate
                }
                loadByMuscle[contribution.muscleId] =
                    (loadByMuscle[contribution.muscleId] ?: 0.0) + setLoad * contribution.weight
            }
        }

        val recommendations = mutableListOf<TrainingRecommendationUiModel>()
        val staleMuscles = listOf("lats", "upperBack", "chest", "quads", "hamstrings", "glutes")
            .mapNotNull { muscleId ->
                val lastDate = lastDateByMuscle[muscleId] ?: return@mapNotNull muscleId to 999L
                muscleId to java.time.temporal.ChronoUnit.DAYS.between(lastDate, today)
            }
            .filter { (_, days) -> days >= 8 }
            .sortedByDescending { (_, days) -> days }
            .take(3)

        if (staleMuscles.isNotEmpty()) {
            val names = staleMuscles.joinToString(", ") { (muscleId, _) -> muscleLabel(muscleId) }
            recommendations += TrainingRecommendationUiModel(
                id = "stale",
                title = t(en = "Long gap: $names", uk = "Давно не було: $names"),
                supporting = t(
                    en = "These groups have not had meaningful work for 8+ days.",
                    uk = "Ці групи не отримували помітного навантаження 8+ днів."
                ),
                priorityLabel = t(en = "Balance", uk = "Баланс")
            )
        }

        val quadLoad = loadByMuscle["quads"] ?: 0.0
        val posteriorLoad = (loadByMuscle["hamstrings"] ?: 0.0) +
            (loadByMuscle["glutes"] ?: 0.0) +
            (loadByMuscle["lowerBack"] ?: 0.0)
        if (quadLoad > 0.0 && posteriorLoad > 0.0 && quadLoad / posteriorLoad > 1.8) {
            recommendations += TrainingRecommendationUiModel(
                id = "posterior-chain",
                title = t(en = "Posterior chain is behind", uk = "Задня лінія відстає"),
                supporting = t(
                    en = "Quad load is much higher than hamstrings, glutes and lower back combined.",
                    uk = "Квадрицепси сильно випереджають біцепс стегна, сідниці та поперек разом."
                ),
                priorityLabel = t(en = "Legs", uk = "Ноги")
            )
        }

        recommendations += nextWorkoutRecommendation(lastDateByMuscle)

        return recommendations.distinctBy { it.id }.take(4)
    }

    private fun nextWorkoutRecommendation(
        lastDateByMuscle: Map<String, LocalDate>
    ): TrainingRecommendationUiModel {
        val groups = listOf(
            TrainingGroup(
                id = "pull",
                titleEn = "Pull day",
                titleUk = "Тяговий день",
                supportingEn = "Back, biceps and forearms have the oldest recent work.",
                supportingUk = "Спина, біцепс і передпліччя найдовше не були в роботі.",
                priorityEn = "Pull",
                priorityUk = "Тяга",
                muscleIds = listOf("lats", "upperBack", "biceps", "forearms")
            ),
            TrainingGroup(
                id = "legs",
                titleEn = "Leg day",
                titleUk = "День ніг",
                supportingEn = "Quads, hamstrings, glutes and calves are next in the rotation.",
                supportingUk = "Квадрицепси, біцепс стегна, сідниці та ікри наступні в черзі.",
                priorityEn = "Legs",
                priorityUk = "Ноги",
                muscleIds = listOf("quads", "hamstrings", "glutes", "calves")
            ),
            TrainingGroup(
                id = "push",
                titleEn = "Push day",
                titleUk = "Жимовий день",
                supportingEn = "Chest, shoulders and triceps have the oldest recent work.",
                supportingUk = "Груди, плечі й трицепс найдовше не були в роботі.",
                priorityEn = "Push",
                priorityUk = "Жим",
                muscleIds = listOf("chest", "shoulders", "triceps")
            )
        )
        val nextGroup = groups.minByOrNull { group ->
            group.muscleIds
                .mapNotNull { lastDateByMuscle[it] }
                .maxOrNull()
                ?.toEpochDay()
                ?: Long.MIN_VALUE
        } ?: groups.first()

        return TrainingRecommendationUiModel(
            id = "next-${nextGroup.id}",
            title = t(
                en = "Next: ${nextGroup.titleEn}",
                uk = "Наступне: ${nextGroup.titleUk}"
            ),
            supporting = t(
                en = nextGroup.supportingEn,
                uk = nextGroup.supportingUk
            ),
            priorityLabel = t(en = nextGroup.priorityEn, uk = nextGroup.priorityUk)
        )
    }

    private fun muscleLabel(muscleId: String): String {
        val definition = MUSCLE_DEFINITIONS.firstOrNull { it.id == muscleId }
        return definition?.let { t(en = it.titleEn, uk = it.titleUk) } ?: muscleId
    }

    private fun missionUiModel(mission: AdaptiveMission): MissionProgressUiModel {
        val progress = mission.progress
        val goal = mission.goal
        val progressLabel = when {
            isUkrainian() -> "${progress.coerceAtMost(goal)} / $goal ${mission.unitUk}"
            isRussian() -> "${progress.coerceAtMost(goal)} / $goal ${mission.unitRu}"
            else -> "${progress.coerceAtMost(goal)} / $goal ${mission.unitEn}"
        }
        val cadenceLabel = when (mission.cadence) {
            MissionCadence.Daily -> t(en = "Today", uk = "Сьогодні")
            MissionCadence.Weekly -> t(en = "This week", uk = "Цього тижня")
            MissionCadence.Monthly -> t(en = "This month", uk = "Цього місяця")
        }

        return MissionProgressUiModel(
            id = mission.id,
            title = t(en = mission.titleEn, uk = mission.titleUk),
            cadenceLabel = cadenceLabel,
            summary = t(en = mission.summaryEn, uk = mission.summaryUk),
            progressLabel = progressLabel,
            progress = progress,
            goal = goal,
            progressFraction = progressFraction(progress, goal),
            isComplete = progress >= goal
        )
    }

    private fun buildAchievements(
        allSessions: List<WorkoutSessionSummary>,
        targetWorkoutsPerWeek: Int
    ): List<AchievementPreviewUiModel> {
        val snapshot = GamificationEngine.buildSnapshot(
            sessions = allSessions,
            nowMillis = System.currentTimeMillis(),
            zoneId = zoneId,
            targetWorkoutsPerWeek = targetWorkoutsPerWeek.coerceIn(2, 6)
        )
        return snapshot.achievements.map { achievement ->
            val translation = POST_WORKOUT_ACHIEVEMENT_UK[achievement.id]
            val progress = achievement.progress
                .coerceAtLeast(0.0)
                .coerceAtMost(Int.MAX_VALUE.toDouble())
                .roundToInt()
            val goal = achievement.target
                .coerceAtLeast(1.0)
                .coerceAtMost(Int.MAX_VALUE.toDouble())
                .roundToInt()
            val unit = when {
                achievement.id.startsWith("streak_") -> t(en = "weeks", uk = "тижнів")
                achievement.id == "comeback" -> t(en = "days", uk = "днів")
                achievement.id.startsWith("volume_") ->
                    t(en = "volume", uk = "обсягу")
                else -> t(en = "workouts", uk = "тренувань")
            }
            AchievementPreviewUiModel(
                id = achievement.id,
                title = t(
                    en = achievement.title,
                    uk = translation?.title ?: achievement.title
                ),
                description = t(
                    en = achievement.description,
                    uk = translation?.description ?: achievement.description
                ),
                badgeName = t(
                    en = achievement.badge.name,
                    uk = translation?.badgeName ?: achievement.badge.name
                ),
                badgeRarity = achievement.badge.rarity,
                rewardXp = achievement.rewardXp,
                progressLabel = "${progress.coerceAtMost(goal)} / $goal $unit",
                statusLabel = if (achievement.unlocked) {
                    t(en = "Unlocked", uk = "Відкрито")
                } else {
                    t(en = "In progress", uk = "У процесі")
                },
                progress = progress,
                goal = goal,
                progressFraction = (achievement.progress / achievement.target)
                    .takeIf(Double::isFinite)
                    ?.coerceIn(0.0, 1.0)
                    ?.toFloat()
                    ?: 0f,
                isUnlocked = achievement.unlocked
            )
        }
    }

    private fun sessionXp(session: WorkoutSessionSummary): Int {
        return GamificationEngine.xpForSession(session)
    }

    private fun calculateLevelProgress(totalXp: Int): LevelProgress {
        val level = GamificationEngine.levelForXp(totalXp)
        val remainingXp = totalXp - GamificationEngine.xpForLevelStart(level)
        val xpForNextLevel = GamificationEngine.xpForNextLevel(level)

        return LevelProgress(
            level = level,
            currentLevelXp = remainingXp,
            xpForNextLevel = xpForNextLevel,
            progressFraction = progressFraction(remainingXp, xpForNextLevel)
        )
    }

    private fun xpRequirementForLevel(level: Int): Int {
        return GamificationEngine.xpForNextLevel(level)
    }

    private fun titleForLevel(level: Int): String {
        val definition = RANK_DEFINITIONS.lastOrNull { level >= it.levelRequirement } ?: RANK_DEFINITIONS.first()
        return t(en = definition.titleEn, uk = definition.titleUk)
    }

    private fun nextTitleAfter(level: Int): String {
        val next = RANK_DEFINITIONS.firstOrNull { level < it.levelRequirement } ?: RANK_DEFINITIONS.last()
        return t(en = next.titleEn, uk = next.titleUk)
    }

    private fun cumulativeXpForLevel(level: Int): Int {
        return GamificationEngine.xpForLevelStart(level)
    }

    private fun buildRankLadder(totalXp: Int): List<RankProgressUiModel> {
        val currentRankId = RANK_DEFINITIONS
            .lastOrNull { totalXp >= cumulativeXpForLevel(it.levelRequirement) }
            ?.id

        return RANK_DEFINITIONS.mapIndexed { index, definition ->
            val requiredXp = cumulativeXpForLevel(definition.levelRequirement)
            val previousXp = if (index == 0) 0 else cumulativeXpForLevel(RANK_DEFINITIONS[index - 1].levelRequirement)
            val segment = (requiredXp - previousXp).coerceAtLeast(1)
            val progressInTier = (totalXp - previousXp).coerceIn(0, segment)
            RankProgressUiModel(
                id = definition.id,
                levelRequirement = definition.levelRequirement,
                title = t(en = definition.titleEn, uk = definition.titleUk),
                requiredXp = requiredXp,
                xpRemaining = (requiredXp - totalXp).coerceAtLeast(0),
                progressFraction = progressInTier.toFloat() / segment.toFloat(),
                isCurrent = definition.id == currentRankId,
                isUnlocked = totalXp >= requiredXp
            )
        }
    }

    private fun progressFraction(progress: Int, goal: Int): Float {
        if (goal <= 0) return 0f
        return (progress.toFloat() / goal.toFloat()).coerceIn(0f, 1f)
    }

    private fun t(en: String, uk: String): String = when (currentLocale().language.lowercase(Locale.ROOT)) {
        "uk" -> uk
        "ru" -> RussianText.translate(en)
        else -> en
    }

    private fun currentLocale(): Locale {
        val appLocales = AppCompatDelegate.getApplicationLocales()
        return if (appLocales.isEmpty) {
            Locale.getDefault()
        } else {
            appLocales[0] ?: Locale.getDefault()
        }
    }

    private fun isUkrainian(): Boolean {
        return currentLocale().language.equals("uk", ignoreCase = true)
    }

    private fun isRussian(): Boolean {
        return currentLocale().language.equals("ru", ignoreCase = true)
    }

    private fun Long.toLocalDate(): LocalDate {
        return Instant.ofEpochMilli(this).atZone(zoneId).toLocalDate()
    }

    companion object {
        private const val PENDING_ACTIVATION_KEY = "pending_first_workout_activation_v1"
        private const val CONSUMED_LAUNCHES_KEY = "consumed_smart_launches_v1"

        fun factory(
            repository: GymRepository,
            trainingProfileManager: TrainingProfileManager,
            trainingGuidanceManager: TrainingGuidanceManager,
            surface: WorkoutListSurface = WorkoutListSurface.Today
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                WorkoutListViewModel(
                    repository = repository,
                    trainingProfileManager = trainingProfileManager,
                    trainingGuidanceManager = trainingGuidanceManager,
                    savedStateHandle = createSavedStateHandle(),
                    surface = surface
                )
            }
        }
    }
}

internal fun buildTodayHeroMetrics(
    sessions: List<WorkoutSessionSummary>,
    weeklyStreakWeeks: Int
): TodayHeroMetricsUiModel {
    val totalVolume = sessions.fold(0.0) { running, session ->
        val value = session.totalVolume.takeIf { it.isFinite() && it >= 0.0 } ?: 0.0
        (running + value).coerceAtMost(MAX_TODAY_HERO_VOLUME)
    }
    return TodayHeroMetricsUiModel(
        totalWorkouts = sessions.size,
        weeklyStreakWeeks = weeklyStreakWeeks.coerceAtLeast(0),
        totalVolume = totalVolume
    )
}

internal fun buildDashboardStatsForMonth(
    monthOffset: Int,
    targetWorkoutsPerWeek: Int,
    monthSessions: List<WorkoutSessionSummary>,
    allSessions: List<WorkoutSessionSummary>,
    nowMillis: Long,
    zoneId: ZoneId
): DashboardStats {
    require(targetWorkoutsPerWeek in 2..6)
    val totalVolume = monthSessions.sumOf { it.totalVolume }
    val totalSets = monthSessions.sumOf { it.setCount }
    val workoutDays = allSessions.asSequence()
        .map { session ->
            Instant.ofEpochMilli(session.session.date)
                .atZone(zoneId)
                .toLocalDate()
                .toEpochDay()
        }
        .toSet()
    var cursorDay = Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDate().toEpochDay()
    if (cursorDay !in workoutDays) cursorDay -= 1
    var streakDays = 0
    while (cursorDay in workoutDays) {
        streakDays += 1
        cursorDay -= 1
    }
    val sessionTimestamps = allSessions.map { it.session.date }
    val weeklyStreakWeeks = if (monthOffset == 0) {
        WeeklyStreakCalculator.current(
            sessionTimestamps = sessionTimestamps,
            targetWorkoutsPerWeek = targetWorkoutsPerWeek,
            nowMillis = nowMillis,
            zoneId = zoneId
        )
    } else {
        val (periodStartMillis, periodEndMillis) = DateTimeUtils.monthBounds(monthOffset, zoneId)
        WeeklyStreakCalculator.bestDuringPeriod(
            sessionTimestamps = sessionTimestamps,
            targetWorkoutsPerWeek = targetWorkoutsPerWeek,
            periodStartMillis = periodStartMillis,
            periodEndMillis = periodEndMillis,
            zoneId = zoneId
        )
    }
    return DashboardStats(
        workoutCount = monthSessions.size,
        totalVolume = totalVolume,
        averageIntensity = if (totalSets == 0) 0.0 else totalVolume / totalSets,
        streakDays = streakDays,
        weeklyStreakWeeks = weeklyStreakWeeks
    )
}

/**
 * Prefer a measured, bounded duration and round it up to a whole minute. Historical
 * rows without measured time use the shared fallback: three minutes per exercise plus two minutes
 * per set, clamped to 10...90 minutes.
 */
internal fun estimateWorkoutMinutes(
    exerciseCount: Int,
    setCount: Int,
    measuredDurationSeconds: Long? = null
): Int {
    measuredDurationSeconds
        ?.takeIf { it in 0L..MAX_GARMIN_DURATION_SECONDS }
        ?.let { duration -> return ((duration + 59L) / 60L).toInt() }
    val estimated = exerciseCount.coerceAtLeast(0).toLong() * 3L +
        setCount.coerceAtLeast(0).toLong() * 2L
    return estimated.coerceIn(10L, MAX_ESTIMATED_WORKOUT_MINUTES.toLong()).toInt()
}

internal fun hasCompletedWorkoutToday(
    sessions: List<WorkoutSessionSummary>,
    nowMillis: Long,
    zoneId: ZoneId
): Boolean {
    val today = Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDate()
    return sessions.asSequence()
        .take(WorkoutDataLimits.MAX_SESSIONS)
        .filter {
            WorkoutDataLimits.isValidTimestamp(it.session.date) &&
                it.session.date <= nowMillis
        }
        .any { Instant.ofEpochMilli(it.session.date).atZone(zoneId).toLocalDate() == today }
}

internal fun buildWeeklyTrainingSummary(
    sessions: List<WorkoutSessionSummary>,
    targetTrainingDays: Int,
    nowMillis: Long,
    zoneId: ZoneId,
    weekOffset: Int = 0
): WeeklyTrainingSummaryUiModel {
    val today = Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDate()
    val selectedDate = today.plusWeeks(weekOffset.coerceIn(-5_200, 0).toLong())
    val weekStart = selectedDate.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val weekEndExclusive = weekStart.plusDays(7)
    val currentWeekSessions = sessions.asSequence()
        .take(WorkoutDataLimits.MAX_SESSIONS)
        .filter {
            WorkoutDataLimits.isValidTimestamp(it.session.date) &&
                it.session.date <= nowMillis
        }
        .mapNotNull { session ->
            val date = runCatching {
                Instant.ofEpochMilli(session.session.date).atZone(zoneId).toLocalDate()
            }.getOrNull() ?: return@mapNotNull null
            session.takeIf { date >= weekStart && date < weekEndExclusive }?.let { date to it }
        }
        .toList()
    val completedDates = currentWeekSessions.mapTo(linkedSetOf()) { it.first }
    val estimatedMinutes = currentWeekSessions.fold(0L) { total, (_, session) ->
        val measuredDurationSeconds = session.session.durationSeconds
            ?: session.session.note?.let(::parseGarminWorkoutMetrics)?.durationSeconds
        (total + estimateWorkoutMinutes(
            exerciseCount = session.exerciseCount,
            setCount = session.setCount,
            measuredDurationSeconds = measuredDurationSeconds
        ))
            .coerceAtMost(Int.MAX_VALUE.toLong())
    }.toInt()
    val totalVolume = currentWeekSessions.fold(0.0) { total, (_, session) ->
        val volume = session.totalVolume.takeIf { it.isFinite() && it >= 0.0 } ?: 0.0
        (total + volume).coerceAtMost(MAX_TODAY_HERO_VOLUME)
    }
    return WeeklyTrainingSummaryUiModel(
        days = (0L..6L).map { offset ->
            val date = weekStart.plusDays(offset)
            WeeklyTrainingDayUiModel(
                date = date,
                isCompleted = date in completedDates,
                isToday = date == today
            )
        },
        workouts = currentWeekSessions
            .map { it.second }
            .sortedByDescending { it.session.date },
        completedWorkoutCount = currentWeekSessions.size,
        completedTrainingDays = completedDates.size,
        targetTrainingDays = targetTrainingDays.coerceIn(2, 6),
        estimatedMinutes = estimatedMinutes,
        totalVolume = totalVolume
    )
}

private data class LevelProgress(
    val level: Int,
    val currentLevelXp: Int,
    val xpForNextLevel: Int,
    val progressFraction: Float
)

private data class WorkoutMonthSessions(
    val offset: Int,
    val sessions: List<WorkoutSessionSummary>
)

private data class WorkoutListSourceState(
    val offset: Int,
    val weekOffset: Int,
    val sessions: List<WorkoutSessionSummary>,
    val allSessions: List<WorkoutSessionSummary>,
    val exerciseHistory: List<ExerciseHistoryEntry>
)

internal data class WorkoutRecommendationContext(
    val exercises: List<ExerciseEntity> = emptyList(),
    val history: List<ExerciseHistoryEntry> = emptyList(),
    val loadProfiles: Map<Long, ExerciseLoadProfile> = emptyMap(),
    val muscleMappings: List<ExerciseMuscleMappingEntity> = emptyList()
)

internal sealed interface WorkoutRecommendationContextLoad {
    data class Loaded(
        val context: WorkoutRecommendationContext
    ) : WorkoutRecommendationContextLoad

    data class Failed(
        val error: Throwable
    ) : WorkoutRecommendationContextLoad
}

@OptIn(ExperimentalCoroutinesApi::class)
internal fun generationScopedRecommendationContext(
    loadGeneration: Flow<Long>,
    exercisesSource: () -> Flow<List<ExerciseEntity>>,
    historySource: () -> Flow<List<ExerciseHistoryEntry>>,
    loadProfilesSource: () -> Flow<Map<Long, ExerciseLoadProfile>>,
    muscleMappingsSource: () -> Flow<List<ExerciseMuscleMappingEntity>>
): Flow<WorkoutRecommendationContextLoad> = loadGeneration.flatMapLatest {
    combine(
        exercisesSource(),
        historySource(),
        loadProfilesSource(),
        muscleMappingsSource()
    ) { exercises, history, loadProfiles, muscleMappings ->
        WorkoutRecommendationContext(
            exercises = exercises,
            history = history,
            loadProfiles = loadProfiles,
            muscleMappings = muscleMappings
        )
    }.map<WorkoutRecommendationContext, WorkoutRecommendationContextLoad> { context ->
        WorkoutRecommendationContextLoad.Loaded(context)
    }.catch { error ->
        if (error is CancellationException) throw error
        emit(WorkoutRecommendationContextLoad.Failed(error))
    }
}

private fun WorkoutRecommendationContext.fingerprint(
    profile: TrainingProfile
): String = SmartWorkoutLaunchStateFingerprint.compute(
    profile = profile,
    exercises = exercises,
    history = history,
    loadProfiles = loadProfiles,
    muscleMappings = muscleMappings
)

private data class WorkoutMuscleSelection(
    val period: MuscleMapPeriod,
    val muscleId: String?,
    val editorName: String?,
    val mappings: List<ExerciseMuscleMappingEntity>
)

private data class WorkoutExperienceState(
    val profile: TrainingProfile,
    val activationDismissed: Boolean,
    val feedback: Map<Long, WorkoutFeedbackRecord>,
    val context: WorkoutRecommendationContext
)

private data class TrainingGroup(
    val id: String,
    val titleEn: String,
    val titleUk: String,
    val supportingEn: String,
    val supportingUk: String,
    val priorityEn: String,
    val priorityUk: String,
    val muscleIds: List<String>
)

private data class MutableMuscleProgress(
    var load: Double = 0.0,
    val setIds: MutableSet<Long> = linkedSetOf(),
    val sessionIds: MutableSet<Long> = linkedSetOf(),
    val exerciseKeys: MutableSet<String> = linkedSetOf()
)

private data class MutableExerciseContribution(
    var load: Double = 0.0,
    val setIds: MutableSet<Long> = linkedSetOf(),
    val sessionIds: MutableSet<Long> = linkedSetOf()
)

private data class MutableExerciseMapping(
    val contributions: List<MuscleContribution>,
    val setIds: MutableSet<Long> = linkedSetOf(),
    val sessionIds: MutableSet<Long> = linkedSetOf()
)
