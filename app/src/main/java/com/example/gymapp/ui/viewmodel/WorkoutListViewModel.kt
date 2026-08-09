package com.example.gymapp.ui.viewmodel

import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.lifecycle.viewModelScope
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.DashboardStats
import com.example.gymapp.data.repository.GamificationEngine
import com.example.gymapp.data.repository.BadgeRarity
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.data.repository.MUSCLE_DEFINITIONS
import com.example.gymapp.data.repository.RANK_DEFINITIONS
import com.example.gymapp.data.repository.MuscleContribution
import com.example.gymapp.data.repository.estimatedLoad
import com.example.gymapp.data.repository.muscleContributionsForExercise
import com.example.gymapp.data.repository.normalizedExerciseName
import com.example.gymapp.data.repository.toManualContributionMap
import com.example.gymapp.util.DateTimeUtils
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
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
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

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

data class WorkoutListUiState(
    val monthOffset: Int = 0,
    val monthLabel: String = DateTimeUtils.monthLabel(0),
    val sessions: List<WorkoutSessionSummary> = emptyList(),
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

@OptIn(ExperimentalCoroutinesApi::class)
class WorkoutListViewModel(
    private val repository: GymRepository
) : ViewModel() {
    private val zoneId = ZoneId.systemDefault()
    private val monthOffset = MutableStateFlow(0)
    private val muscleMapPeriod = MutableStateFlow(MuscleMapPeriod.AllTime)
    private val selectedMuscleId = MutableStateFlow<String?>(null)
    private val manualMappingExerciseName = MutableStateFlow<String?>(null)

    private val sessionsFlow = monthOffset.flatMapLatest { offset ->
        repository.observeSessionsForMonth(offset)
    }

    private val dashboardFlow = monthOffset.flatMapLatest { offset ->
        repository.observeDashboardStatsForMonth(offset)
    }

    private val allSessionsFlow = repository.observeSessions()
    private val exerciseHistoryFlow = repository.observeAllExerciseHistory()
    private val muscleMappingsFlow = repository.observeExerciseMuscleMappings()

    private val sourceState = combine(
        monthOffset,
        sessionsFlow,
        dashboardFlow,
        allSessionsFlow,
        exerciseHistoryFlow
    ) { offset, sessions, dashboardStats, allSessions, exerciseHistory ->
        WorkoutListSourceState(
            offset = offset,
            sessions = sessions,
            dashboardStats = dashboardStats,
            allSessions = allSessions,
            exerciseHistory = exerciseHistory
        )
    }

    val uiState: StateFlow<WorkoutListUiState> = combine(
        sourceState,
        muscleMapPeriod,
        selectedMuscleId,
        manualMappingExerciseName,
        muscleMappingsFlow
    ) { source, selectedPeriod, selectedMuscle, editorExerciseName, muscleMappings ->
        val offset = source.offset
        val sessions = source.sessions
        val dashboardStats = source.dashboardStats
        val allSessions = source.allSessions
        val exerciseHistory = source.exerciseHistory
        val missionBoard = AdaptiveMissionBoardSource.build(
            sessions = allSessions,
            anchorDate = LocalDate.now(zoneId),
            zoneId = zoneId
        )
        val dailyMissions = missionBoard.daily.map(::missionUiModel)
        val weeklyMissions = missionBoard.weekly.map(::missionUiModel)
        val monthlyMissions = missionBoard.monthly.map(::missionUiModel)
        val soloProgress = buildSoloProgress(
            allSessions = allSessions,
            monthSessions = sessions,
            streakDays = dashboardStats.streakDays,
            weeklyStreakWeeks = dashboardStats.weeklyStreakWeeks
        )
        WorkoutListUiState(
            monthOffset = offset,
            monthLabel = DateTimeUtils.monthLabel(offset, currentLocale(), zoneId),
            sessions = sessions,
            dashboardStats = dashboardStats,
            soloProgress = soloProgress,
            activityHeatmap = buildHeatmap(offset, sessions),
            muscleHeatmap = buildMuscleHeatmap(
                exerciseHistory = exerciseHistory,
                period = selectedPeriod,
                selectedMuscleId = selectedMuscle,
                manualEditorExerciseName = editorExerciseName,
                muscleMappings = muscleMappings
            ),
            trainingRecommendations = buildTrainingRecommendations(
                exerciseHistory = exerciseHistory,
                muscleMappings = muscleMappings
            ),
            dailyMissions = dailyMissions,
            weeklyMissions = weeklyMissions,
            monthlyMissions = monthlyMissions,
            rankLadder = buildRankLadder(soloProgress.totalXp),
            achievements = buildAchievements(allSessions)
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WorkoutListUiState()
    )

    init {
        viewModelScope.launch {
            repository.seedDefaultExerciseMuscleMappings()
        }
    }

    fun previousMonth() {
        monthOffset.value -= 1
    }

    fun nextMonth() {
        monthOffset.value += 1
    }

    fun currentMonth() {
        monthOffset.value = 0
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

    private fun buildSoloProgress(
        allSessions: List<WorkoutSessionSummary>,
        monthSessions: List<WorkoutSessionSummary>,
        streakDays: Int,
        weeklyStreakWeeks: Int
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
                isUkrainian() -> "$weeklyStreakWeeks тиж. поспіль із 3+ тренуваннями."
                isRussian() -> "$weeklyStreakWeeks нед. подряд с 3+ тренировками."
                else -> "$weeklyStreakWeeks successful week${if (weeklyStreakWeeks == 1) "" else "s"} in a row."
            }
            monthXp > 0 -> t(
                en = "$monthXp XP earned this month.",
                uk = "За цей місяць зароблено $monthXp XP."
            )
            else -> t(
                en = "One more session keeps the streak alive.",
                uk = "Ще одна сесія допоможе зберегти серію."
            )
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
        allSessions: List<WorkoutSessionSummary>
    ): List<AchievementPreviewUiModel> {
        val snapshot = GamificationEngine.buildSnapshot(
            sessions = allSessions,
            nowMillis = System.currentTimeMillis(),
            zoneId = zoneId
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
                achievement.id.startsWith("streak_") || achievement.id == "comeback" ->
                    t(en = "days", uk = "днів")
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
        fun factory(repository: GymRepository): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                WorkoutListViewModel(repository)
            }
        }
    }
}

private data class LevelProgress(
    val level: Int,
    val currentLevelXp: Int,
    val xpForNextLevel: Int,
    val progressFraction: Float
)

private data class WorkoutListSourceState(
    val offset: Int,
    val sessions: List<WorkoutSessionSummary>,
    val dashboardStats: DashboardStats,
    val allSessions: List<WorkoutSessionSummary>,
    val exerciseHistory: List<ExerciseHistoryEntry>
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
