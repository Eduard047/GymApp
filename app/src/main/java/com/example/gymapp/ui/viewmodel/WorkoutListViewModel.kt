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
import com.example.gymapp.data.repository.GymRepository
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
import java.time.format.TextStyle
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

data class SoloProgressUiModel(
    val totalXp: Int = 0,
    val monthXp: Int = 0,
    val missionXp: Int = 0,
    val level: Int = 1,
    val title: String = "--",
    val currentLevelXp: Int = 0,
    val xpForNextLevel: Int = 180,
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
    val xpReward: Int = 0,
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
        val historyStats = buildMissionHistoryStats(allSessions)
        val dailyMissions = buildDailyMissions(allSessions, historyStats)
        val weeklyMissions = buildWeeklyMissions(allSessions, historyStats)
        val monthlyMissions = buildMonthlyMissions(allSessions, historyStats)
        val missionXp = missionXpFor(dailyMissions, weeklyMissions, monthlyMissions)
        val soloProgress = buildSoloProgress(
            allSessions = allSessions,
            monthSessions = sessions,
            streakDays = dashboardStats.streakDays,
            weeklyStreakWeeks = dashboardStats.weeklyStreakWeeks,
            missionXpBonus = missionXp,
            includeMissionXpInMonth = offset == 0
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
            achievements = buildAchievements(allSessions, dashboardStats.streakDays)
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = WorkoutListUiState()
    )

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

    private fun buildSoloProgress(
        allSessions: List<WorkoutSessionSummary>,
        monthSessions: List<WorkoutSessionSummary>,
        streakDays: Int,
        weeklyStreakWeeks: Int,
        missionXpBonus: Int,
        includeMissionXpInMonth: Boolean
    ): SoloProgressUiModel {
        val workoutXp = allSessions.sumOf(::sessionXp)
        val monthWorkoutXp = monthSessions.sumOf(::sessionXp)
        val totalXp = workoutXp + missionXpBonus
        val monthXp = monthWorkoutXp + if (includeMissionXpInMonth) missionXpBonus else 0
        val levelInfo = calculateLevelProgress(totalXp)
        val currentTitle = titleForLevel(levelInfo.level)
        val nextTitle = nextTitleAfter(levelInfo.level)
        val summary = when {
            allSessions.isEmpty() -> t(
                en = "Log a workout to start your momentum.",
                uk = "Запиши тренування, щоб запустити свій темп."
            )
            weeklyStreakWeeks > 0 -> if (isUkrainian()) {
                "$weeklyStreakWeeks тиж. поспіль із 3+ тренуваннями."
            } else {
                "$weeklyStreakWeeks successful week${if (weeklyStreakWeeks == 1) "" else "s"} in a row."
            }
            monthXp > 0 && missionXpBonus > 0 -> t(
                en = "$monthXp XP earned this month ($missionXpBonus from missions).",
                uk = "За цей місяць зароблено $monthXp XP ($missionXpBonus з місій)."
            )
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
            missionXp = missionXpBonus,
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
        val maxSessionsInDay = sessionsByDay.values.maxOfOrNull { it.size } ?: 0

        val cells = mutableListOf<ActivityHeatmapDayUiModel>()
        repeat(firstDay.dayOfWeek.value - DayOfWeek.MONDAY.value) { index ->
            cells += ActivityHeatmapDayUiModel(id = "leading-$index")
        }

        var cursor = firstDay
        while (!cursor.isAfter(lastDay)) {
            val daySessions = sessionsByDay[cursor].orEmpty()
            val sessionCount = daySessions.size
            val totalVolume = daySessions.sumOf { it.totalVolume }
            val intensity = when {
                sessionCount == 0 || maxSessionsInDay == 0 -> 0f
                else -> (0.28f + (sessionCount.toFloat() / maxSessionsInDay.toFloat()) * 0.72f)
                    .coerceIn(0f, 1f)
            }
            cells += ActivityHeatmapDayUiModel(
                id = cursor.toString(),
                dayNumber = cursor.dayOfMonth,
                dayLabel = cursor.dayOfWeek.getDisplayName(TextStyle.SHORT, locale),
                sessionCount = sessionCount,
                totalVolume = totalVolume,
                intensity = intensity,
                isCurrentMonth = true,
                isToday = cursor == today
            )
            cursor = cursor.plusDays(1)
        }

        while (cells.size % 7 != 0) {
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

        historyEntries.forEach { entry ->
            val exerciseKey = entry.exerciseName.normalizedExerciseName()
            val contributions = muscleContributionsForExercise(entry.exerciseName, manualMap)
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

    private fun List<ExerciseMuscleMappingEntity>.toManualContributionMap(): Map<String, List<MuscleContribution>> {
        return groupBy { it.exerciseNameKey }
            .mapValues { (_, mappings) ->
                mappings
                    .filter { mapping -> MUSCLE_DEFINITIONS.any { it.id == mapping.muscleId } }
                    .map { mapping ->
                        MuscleContribution(
                            muscleId = mapping.muscleId,
                            weight = mapping.weight.coerceIn(0.0, 1.0)
                        )
                    }
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

    private fun buildDailyMissions(
        allSessions: List<WorkoutSessionSummary>,
        historyStats: MissionHistoryStats
    ): List<MissionProgressUiModel> {
        val stats = buildDailyMissionStats(allSessions)
        val seed = LocalDate.now(zoneId).toEpochDay()
        val selectedTemplates = selectMissionTemplates(
            templates = dailyMissionCatalog(),
            count = ACTIVE_DAILY_MISSIONS,
            seed = seed,
            requiredFamilies = setOf("workouts"),
            scoreSelector = { template ->
                missionSelectionScore(
                    goal = template.goal,
                    target = missionTargetForFamily(MissionCadence.Daily, template.family, historyStats),
                    seed = seed
                )
            }
        )

        return selectedTemplates.map { template ->
            val target = missionTargetForFamily(MissionCadence.Daily, template.family, historyStats)
            mission(
                id = template.id,
                title = t(en = template.titleEn, uk = template.titleUk),
                cadenceLabel = t(en = "Today", uk = "Сьогодні"),
                summary = t(en = template.summaryEn, uk = template.summaryUk),
                progress = template.progressSelector(stats),
                goal = template.goal,
                xpReward = missionXpReward(MissionCadence.Daily, template.goal, target),
                unitEn = template.unitEn,
                unitUk = template.unitUk
            )
        }
    }

    private fun buildWeeklyMissions(
        allSessions: List<WorkoutSessionSummary>,
        historyStats: MissionHistoryStats
    ): List<MissionProgressUiModel> {
        val stats = buildWeeklyMissionStats(allSessions)
        val weekStart = LocalDate.now(zoneId).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val seed = weekStart.toEpochDay()
        val selectedTemplates = selectMissionTemplates(
            templates = weeklyMissionCatalog(),
            count = ACTIVE_WEEKLY_MISSIONS,
            seed = seed,
            requiredFamilies = setOf("workouts"),
            scoreSelector = { template ->
                missionSelectionScore(
                    goal = template.goal,
                    target = missionTargetForFamily(MissionCadence.Weekly, template.family, historyStats),
                    seed = seed
                )
            }
        )

        return selectedTemplates.map { template ->
            val target = missionTargetForFamily(MissionCadence.Weekly, template.family, historyStats)
            mission(
                id = template.id,
                title = t(en = template.titleEn, uk = template.titleUk),
                cadenceLabel = t(en = "This week", uk = "Цього тижня"),
                summary = t(en = template.summaryEn, uk = template.summaryUk),
                progress = template.progressSelector(stats),
                goal = template.goal,
                xpReward = missionXpReward(MissionCadence.Weekly, template.goal, target),
                unitEn = template.unitEn,
                unitUk = template.unitUk
            )
        }
    }

    private fun buildMonthlyMissions(
        allSessions: List<WorkoutSessionSummary>,
        historyStats: MissionHistoryStats
    ): List<MissionProgressUiModel> {
        val stats = buildMonthlyMissionStats(allSessions)
        val monthSeed = YearMonth.now(zoneId).atDay(1).toEpochDay()
        val selectedTemplates = selectMissionTemplates(
            templates = monthlyMissionCatalog(),
            count = ACTIVE_MONTHLY_MISSIONS,
            seed = monthSeed,
            requiredFamilies = setOf("workouts"),
            scoreSelector = { template ->
                missionSelectionScore(
                    goal = template.goal,
                    target = missionTargetForFamily(MissionCadence.Monthly, template.family, historyStats),
                    seed = monthSeed
                )
            }
        )

        return selectedTemplates.map { template ->
            val target = missionTargetForFamily(MissionCadence.Monthly, template.family, historyStats)
            mission(
                id = template.id,
                title = t(en = template.titleEn, uk = template.titleUk),
                cadenceLabel = t(en = "This month", uk = "Цього місяця"),
                summary = t(en = template.summaryEn, uk = template.summaryUk),
                progress = template.progressSelector(stats),
                goal = template.goal,
                xpReward = missionXpReward(MissionCadence.Monthly, template.goal, target),
                unitEn = template.unitEn,
                unitUk = template.unitUk
            )
        }
    }

    private fun dailyMissionCatalog(): List<DailyMissionTemplate> = buildList {
        addAll(
            createDailyTemplates(
                family = "workouts",
                goals = listOf(1),
                idForGoal = { "daily-check-in" },
                unitEn = "workout",
                unitUk = "тренування",
                titleEn = { "Daily check-in" },
                titleUk = { "Щоденний чек-ін" },
                summaryEn = { "Complete 1 workout today." },
                summaryUk = { "Заверши 1 тренування сьогодні." },
                progressSelector = { it.workoutCount }
            )
        )
        addAll(
            createDailyTemplates(
                family = "exercises",
                goals = intSeries(3, 1, 10),
                idForGoal = { goal -> "daily-exercises-$goal" },
                unitEn = "exercises",
                unitUk = "вправ",
                titleEn = { goal -> "$goal exercises today" },
                titleUk = { goal -> "$goal вправ за день" },
                summaryEn = { goal -> "Log $goal exercise entries today." },
                summaryUk = { goal -> "Занеси $goal вправ сьогодні." },
                progressSelector = { it.exerciseCount }
            )
        )
        addAll(
            createDailyTemplates(
                family = "sets",
                goals = intSeries(8, 2, 9),
                idForGoal = { goal -> "daily-sets-$goal" },
                unitEn = "sets",
                unitUk = "підходів",
                titleEn = { goal -> "$goal-set target" },
                titleUk = { goal -> "Ціль: $goal підходів" },
                summaryEn = { goal -> "Reach $goal total sets today." },
                summaryUk = { goal -> "Набери $goal підходів за день." },
                progressSelector = { it.setCount }
            )
        )
        addAll(
            createDailyTemplates(
                family = "volume",
                goals = scaledSeries(
                    base = 1_800,
                    factors = listOf(0.8, 1.0, 1.2, 1.4, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.5, 3.9, 4.3)
                ),
                idForGoal = { goal -> "daily-volume-$goal" },
                unitEn = "volume",
                unitUk = "обсягу",
                titleEn = { goal -> "Volume target $goal" },
                titleUk = { goal -> "Ціль обсягу $goal" },
                summaryEn = { goal -> "Reach $goal total volume today." },
                summaryUk = { goal -> "Набери $goal обсягу сьогодні." },
                progressSelector = { it.totalVolume }
            )
        )
        addAll(
            createDailyTemplates(
                family = "max-session-volume",
                goals = scaledSeries(
                    base = 1_300,
                    factors = listOf(0.8, 1.0, 1.2, 1.4, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.5, 3.9, 4.4, 4.9, 5.5)
                ),
                idForGoal = { goal -> "daily-max-session-volume-$goal" },
                unitEn = "volume",
                unitUk = "обсягу",
                titleEn = { goal -> "Best session $goal volume" },
                titleUk = { goal -> "Краща сесія: $goal обсягу" },
                summaryEn = { goal -> "Push one session to $goal volume today." },
                summaryUk = { goal -> "Доведи одну сесію до $goal обсягу сьогодні." },
                progressSelector = { it.maxSessionVolume }
            )
        )
        addAll(
            createDailyTemplates(
                family = "max-session-exercises",
                goals = intSeries(3, 1, 8),
                idForGoal = { goal -> "daily-max-session-exercises-$goal" },
                unitEn = "exercises",
                unitUk = "вправ",
                titleEn = { goal -> "Session breadth $goal" },
                titleUk = { goal -> "Ширина сесії $goal" },
                summaryEn = { goal -> "Fit $goal exercises into one session today." },
                summaryUk = { goal -> "Збери $goal вправ в одній сесії сьогодні." },
                progressSelector = { it.maxSessionExercises }
            )
        )
        addAll(
            createDailyTemplates(
                family = "max-session-sets",
                goals = intSeries(8, 2, 8),
                idForGoal = { goal -> "daily-max-session-sets-$goal" },
                unitEn = "sets",
                unitUk = "підходів",
                titleEn = { goal -> "Session sets $goal" },
                titleUk = { goal -> "Підходи в сесії: $goal" },
                summaryEn = { goal -> "Build one session to $goal sets today." },
                summaryUk = { goal -> "Збери одну сесію до $goal підходів сьогодні." },
                progressSelector = { it.maxSessionSets }
            )
        )
    }

    private fun weeklyMissionCatalog(): List<WeeklyMissionTemplate> = buildList {
        addAll(
            createWeeklyTemplates(
                family = "workouts",
                goals = intSeries(2, 1, 2),
                idForGoal = { goal -> "weekly-workouts-$goal" },
                unitEn = "workouts",
                unitUk = "тренування",
                titleEn = { goal -> "$goal-workout week" },
                titleUk = { goal -> "Тиждень на $goal тренувань" },
                summaryEn = { goal -> "Complete $goal workouts this week." },
                summaryUk = { goal -> "Заверши $goal тренувань цього тижня." },
                progressSelector = { it.workoutCount }
            )
        )
        addAll(
            createWeeklyTemplates(
                family = "active-days",
                goals = intSeries(2, 1, 2),
                idForGoal = { goal -> "weekly-active-days-$goal" },
                unitEn = "days",
                unitUk = "днів",
                titleEn = { goal -> "$goal active days" },
                titleUk = { goal -> "$goal активних днів" },
                summaryEn = { goal -> "Train on $goal separate days this week." },
                summaryUk = { goal -> "Потренуйся у $goal різні дні цього тижня." },
                progressSelector = { it.activeDays }
            )
        )
        addAll(
            createWeeklyTemplates(
                family = "sets",
                goals = intSeries(24, 4, 10),
                idForGoal = { goal -> "weekly-sets-$goal" },
                unitEn = "sets",
                unitUk = "підходів",
                titleEn = { goal -> "$goal-set week" },
                titleUk = { goal -> "Тиждень на $goal підходів" },
                summaryEn = { goal -> "Reach $goal sets this week." },
                summaryUk = { goal -> "Набери $goal підходів цього тижня." },
                progressSelector = { it.setCount }
            )
        )
        addAll(
            createWeeklyTemplates(
                family = "volume",
                goals = scaledSeries(
                    base = 8_000,
                    factors = listOf(0.8, 0.95, 1.1, 1.25, 1.4, 1.55, 1.75, 1.95, 2.2, 2.5, 2.8, 3.1)
                ),
                idForGoal = { goal -> "weekly-volume-$goal" },
                unitEn = "volume",
                unitUk = "обсягу",
                titleEn = { goal -> "Weekly volume $goal" },
                titleUk = { goal -> "Тижневий обсяг $goal" },
                summaryEn = { goal -> "Reach $goal total volume this week." },
                summaryUk = { goal -> "Набери $goal обсягу цього тижня." },
                progressSelector = { it.totalVolume }
            )
        )
        addAll(
            createWeeklyTemplates(
                family = "exercises",
                goals = intSeries(14, 3, 12),
                idForGoal = { goal -> "weekly-exercises-$goal" },
                unitEn = "exercises",
                unitUk = "вправ",
                titleEn = { goal -> "$goal exercises this week" },
                titleUk = { goal -> "$goal вправ за тиждень" },
                summaryEn = { goal -> "Log $goal exercise entries this week." },
                summaryUk = { goal -> "Занеси $goal вправ цього тижня." },
                progressSelector = { it.exerciseCount }
            )
        )
        addAll(
            createWeeklyTemplates(
                family = "days-10-sets",
                goals = intSeries(1, 1, 3),
                idForGoal = { goal -> "weekly-days-10-sets-$goal" },
                unitEn = "days",
                unitUk = "днів",
                titleEn = { goal -> "High-output days $goal" },
                titleUk = { goal -> "Потужних днів: $goal" },
                summaryEn = { goal -> "Hit 10 sets on $goal different days this week." },
                summaryUk = { goal -> "Зроби 10 підходів у $goal дні цього тижня." },
                progressSelector = { it.daysWithTenPlusSets }
            )
        )
        addAll(
            createWeeklyTemplates(
                family = "days-1000-volume",
                goals = intSeries(1, 1, 3),
                idForGoal = { goal -> "weekly-days-1000-volume-$goal" },
                unitEn = "days",
                unitUk = "днів",
                titleEn = { goal -> "Volume days $goal" },
                titleUk = { goal -> "Днів обсягу: $goal" },
                summaryEn = { goal -> "Reach 1,000 volume on $goal days this week." },
                summaryUk = { goal -> "Набери 1 000 обсягу у $goal дні цього тижня." },
                progressSelector = { it.daysWithThousandVolume }
            )
        )
        addAll(
            createWeeklyTemplates(
                family = "sessions-8-sets",
                goals = intSeries(1, 1, 3),
                idForGoal = { goal -> "weekly-sessions-8-sets-$goal" },
                unitEn = "sessions",
                unitUk = "сесій",
                titleEn = { goal -> "Strong sessions $goal" },
                titleUk = { goal -> "Сильних сесій: $goal" },
                summaryEn = { goal -> "Finish $goal sessions with eight or more sets this week." },
                summaryUk = { goal -> "Заверши $goal сесій з вісьмома або більше підходами цього тижня." },
                progressSelector = { it.sessionsWithEightPlusSets }
            )
        )
        addAll(
            createWeeklyTemplates(
                family = "sessions-3-exercises",
                goals = intSeries(1, 1, 3),
                idForGoal = { goal -> "weekly-sessions-3-exercises-$goal" },
                unitEn = "sessions",
                unitUk = "сесій",
                titleEn = { goal -> "Wide sessions $goal" },
                titleUk = { goal -> "Широких сесій: $goal" },
                summaryEn = { goal -> "Finish $goal sessions with three or more exercises this week." },
                summaryUk = { goal -> "Заверши $goal сесій з трьома або більше вправами цього тижня." },
                progressSelector = { it.sessionsWithThreePlusExercises }
            )
        )
    }

    private fun monthlyMissionCatalog(): List<MonthlyMissionTemplate> = buildList {
        addAll(
            createMonthlyTemplates(
                family = "workouts",
                goals = intSeries(8, 1, 7),
                idForGoal = { goal -> "monthly-workouts-$goal" },
                unitEn = "workouts",
                unitUk = "тренування",
                titleEn = { goal -> "$goal-workout month" },
                titleUk = { goal -> "Місяць на $goal тренувань" },
                summaryEn = { goal -> "Complete $goal workouts this month." },
                summaryUk = { goal -> "Заверши $goal тренувань цього місяця." },
                progressSelector = { it.workoutCount }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "active-days",
                goals = intSeries(8, 1, 7),
                idForGoal = { goal -> "monthly-active-days-$goal" },
                unitEn = "days",
                unitUk = "днів",
                titleEn = { goal -> "$goal active days" },
                titleUk = { goal -> "$goal активних днів" },
                summaryEn = { goal -> "Train on $goal separate days this month." },
                summaryUk = { goal -> "Потренуйся у $goal різні дні цього місяця." },
                progressSelector = { it.activeDays }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "sets",
                goals = intSeries(70, 10, 12),
                idForGoal = { goal -> "monthly-sets-$goal" },
                unitEn = "sets",
                unitUk = "підходів",
                titleEn = { goal -> "$goal-set month" },
                titleUk = { goal -> "Місяць на $goal підходів" },
                summaryEn = { goal -> "Reach $goal sets this month." },
                summaryUk = { goal -> "Набери $goal підходів цього місяця." },
                progressSelector = { it.setCount }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "volume",
                goals = scaledSeries(
                    base = 45_000,
                    factors = listOf(0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.55, 1.7, 1.85, 2.0)
                ),
                idForGoal = { goal -> "monthly-volume-$goal" },
                unitEn = "volume",
                unitUk = "обсягу",
                titleEn = { goal -> "Monthly volume $goal" },
                titleUk = { goal -> "Місячний обсяг $goal" },
                summaryEn = { goal -> "Reach $goal total volume this month." },
                summaryUk = { goal -> "Набери $goal обсягу цього місяця." },
                progressSelector = { it.totalVolume }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "exercises",
                goals = intSeries(45, 7, 14),
                idForGoal = { goal -> "monthly-exercises-$goal" },
                unitEn = "exercises",
                unitUk = "вправ",
                titleEn = { goal -> "$goal exercises this month" },
                titleUk = { goal -> "$goal вправ за місяць" },
                summaryEn = { goal -> "Log $goal exercise entries this month." },
                summaryUk = { goal -> "Занеси $goal вправ цього місяця." },
                progressSelector = { it.exerciseCount }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "days-10-sets",
                goals = intSeries(4, 1, 9),
                idForGoal = { goal -> "monthly-days-10-sets-$goal" },
                unitEn = "days",
                unitUk = "днів",
                titleEn = { goal -> "High-output days $goal" },
                titleUk = { goal -> "Потужних днів: $goal" },
                summaryEn = { goal -> "Hit 10 sets on $goal days this month." },
                summaryUk = { goal -> "Зроби 10 підходів у $goal дні цього місяця." },
                progressSelector = { it.daysWithTenPlusSets }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "days-1000-volume",
                goals = intSeries(4, 1, 9),
                idForGoal = { goal -> "monthly-days-1000-volume-$goal" },
                unitEn = "days",
                unitUk = "днів",
                titleEn = { goal -> "Volume days $goal" },
                titleUk = { goal -> "Днів обсягу: $goal" },
                summaryEn = { goal -> "Reach 1,000 volume on $goal days this month." },
                summaryUk = { goal -> "Набери 1 000 обсягу у $goal дні цього місяця." },
                progressSelector = { it.daysWithThousandVolume }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "sessions-8-sets",
                goals = intSeries(5, 1, 9),
                idForGoal = { goal -> "monthly-sessions-8-sets-$goal" },
                unitEn = "sessions",
                unitUk = "сесій",
                titleEn = { goal -> "Strong sessions $goal" },
                titleUk = { goal -> "Сильних сесій: $goal" },
                summaryEn = { goal -> "Finish $goal sessions with eight or more sets this month." },
                summaryUk = { goal -> "Заверши $goal сесій з вісьмома або більше підходами цього місяця." },
                progressSelector = { it.sessionsWithEightPlusSets }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "sessions-3-exercises",
                goals = intSeries(5, 1, 9),
                idForGoal = { goal -> "monthly-sessions-3-exercises-$goal" },
                unitEn = "sessions",
                unitUk = "сесій",
                titleEn = { goal -> "Wide sessions $goal" },
                titleUk = { goal -> "Широких сесій: $goal" },
                summaryEn = { goal -> "Finish $goal sessions with three or more exercises this month." },
                summaryUk = { goal -> "Заверши $goal сесій з трьома або більше вправами цього місяця." },
                progressSelector = { it.sessionsWithThreePlusExercises }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "max-session-volume",
                goals = scaledSeries(
                    base = 1_400,
                    factors = listOf(1.0, 1.15, 1.3, 1.45, 1.6, 1.8, 2.0, 2.25, 2.5, 2.8, 3.1, 3.5, 3.9, 4.3, 4.8, 5.3)
                ),
                idForGoal = { goal -> "monthly-max-session-volume-$goal" },
                unitEn = "volume",
                unitUk = "обсягу",
                titleEn = { goal -> "Best session $goal volume" },
                titleUk = { goal -> "Краща сесія: $goal обсягу" },
                summaryEn = { goal -> "Push one session to $goal volume this month." },
                summaryUk = { goal -> "Доведи одну сесію до $goal обсягу цього місяця." },
                progressSelector = { it.maxSessionVolume }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "max-session-sets",
                goals = intSeries(10, 2, 11),
                idForGoal = { goal -> "monthly-max-session-sets-$goal" },
                unitEn = "sets",
                unitUk = "підходів",
                titleEn = { goal -> "Best session $goal sets" },
                titleUk = { goal -> "Краща сесія: $goal підходів" },
                summaryEn = { goal -> "Build one session to $goal sets this month." },
                summaryUk = { goal -> "Збери одну сесію до $goal підходів цього місяця." },
                progressSelector = { it.maxSessionSets }
            )
        )
        addAll(
            createMonthlyTemplates(
                family = "max-session-exercises",
                goals = intSeries(4, 1, 9),
                idForGoal = { goal -> "monthly-max-session-exercises-$goal" },
                unitEn = "exercises",
                unitUk = "вправ",
                titleEn = { goal -> "Best session $goal exercises" },
                titleUk = { goal -> "Краща сесія: $goal вправ" },
                summaryEn = { goal -> "Fit $goal exercises into one session this month." },
                summaryUk = { goal -> "Збери $goal вправ в одній сесії цього місяця." },
                progressSelector = { it.maxSessionExercises }
            )
        )
    }

    private fun intSeries(start: Int, step: Int, count: Int): List<Int> {
        return List(count) { index -> start + (index * step) }
    }

    private fun scaledSeries(base: Int, factors: List<Double>): List<Int> {
        return factors
            .map { factor -> (base * factor).roundToInt().coerceAtLeast(1) }
            .distinct()
            .sorted()
    }

    private fun createDailyTemplates(
        family: String,
        goals: List<Int>,
        idForGoal: (Int) -> String,
        unitEn: String,
        unitUk: String,
        titleEn: (Int) -> String,
        titleUk: (Int) -> String,
        summaryEn: (Int) -> String,
        summaryUk: (Int) -> String,
        progressSelector: (DailyMissionStats) -> Int
    ): List<DailyMissionTemplate> {
        return goals.map { goal ->
            DailyMissionTemplate(
                id = idForGoal(goal),
                family = family,
                titleEn = titleEn(goal),
                titleUk = titleUk(goal),
                summaryEn = summaryEn(goal),
                summaryUk = summaryUk(goal),
                goal = goal,
                unitEn = unitEn,
                unitUk = unitUk,
                progressSelector = progressSelector
            )
        }
    }

    private fun createWeeklyTemplates(
        family: String,
        goals: List<Int>,
        idForGoal: (Int) -> String,
        unitEn: String,
        unitUk: String,
        titleEn: (Int) -> String,
        titleUk: (Int) -> String,
        summaryEn: (Int) -> String,
        summaryUk: (Int) -> String,
        progressSelector: (WeeklyMissionStats) -> Int
    ): List<WeeklyMissionTemplate> {
        return goals.map { goal ->
            WeeklyMissionTemplate(
                id = idForGoal(goal),
                family = family,
                titleEn = titleEn(goal),
                titleUk = titleUk(goal),
                summaryEn = summaryEn(goal),
                summaryUk = summaryUk(goal),
                goal = goal,
                unitEn = unitEn,
                unitUk = unitUk,
                progressSelector = progressSelector
            )
        }
    }

    private fun createMonthlyTemplates(
        family: String,
        goals: List<Int>,
        idForGoal: (Int) -> String,
        unitEn: String,
        unitUk: String,
        titleEn: (Int) -> String,
        titleUk: (Int) -> String,
        summaryEn: (Int) -> String,
        summaryUk: (Int) -> String,
        progressSelector: (MonthlyMissionStats) -> Int
    ): List<MonthlyMissionTemplate> {
        return goals.map { goal ->
            MonthlyMissionTemplate(
                id = idForGoal(goal),
                family = family,
                titleEn = titleEn(goal),
                titleUk = titleUk(goal),
                summaryEn = summaryEn(goal),
                summaryUk = summaryUk(goal),
                goal = goal,
                unitEn = unitEn,
                unitUk = unitUk,
                progressSelector = progressSelector
            )
        }
    }

    private fun buildDailyMissionStats(allSessions: List<WorkoutSessionSummary>): DailyMissionStats {
        val today = LocalDate.now(zoneId)
        val todaySessions = allSessions.filter { it.session.date.toLocalDate() == today }

        return DailyMissionStats(
            workoutCount = todaySessions.size,
            exerciseCount = todaySessions.sumOf { it.exerciseCount },
            setCount = todaySessions.sumOf { it.setCount },
            totalVolume = todaySessions.sumOf { it.totalVolume }.roundToInt(),
            maxSessionVolume = todaySessions.maxOfOrNull { it.totalVolume }?.roundToInt() ?: 0,
            maxSessionExercises = todaySessions.maxOfOrNull { it.exerciseCount } ?: 0,
            maxSessionSets = todaySessions.maxOfOrNull { it.setCount } ?: 0
        )
    }

    private fun buildWeeklyMissionStats(allSessions: List<WorkoutSessionSummary>): WeeklyMissionStats {
        val today = LocalDate.now(zoneId)
        val weekStart = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val weekEnd = weekStart.plusDays(6)
        val weekSessions = allSessions.filter { session ->
            val sessionDate = session.session.date.toLocalDate()
            !sessionDate.isBefore(weekStart) && !sessionDate.isAfter(weekEnd)
        }
        val sessionsByDay = weekSessions.groupBy { it.session.date.toLocalDate() }
        val dayAggregates = sessionsByDay.mapValues { (_, sessions) ->
            sessions.fold(WeeklyDayAggregate()) { acc, session ->
                acc.copy(
                    workoutCount = acc.workoutCount + 1,
                    exerciseCount = acc.exerciseCount + session.exerciseCount,
                    setCount = acc.setCount + session.setCount,
                    totalVolume = acc.totalVolume + session.totalVolume
                )
            }
        }

        return WeeklyMissionStats(
            workoutCount = weekSessions.size,
            activeDays = sessionsByDay.size,
            exerciseCount = weekSessions.sumOf { it.exerciseCount },
            setCount = weekSessions.sumOf { it.setCount },
            totalVolume = weekSessions.sumOf { it.totalVolume }.roundToInt(),
            daysWithTenPlusSets = dayAggregates.values.count { it.setCount >= 10 },
            daysWithThousandVolume = dayAggregates.values.count { it.totalVolume >= 1_000.0 },
            sessionsWithEightPlusSets = weekSessions.count { it.setCount >= 8 },
            sessionsWithThreePlusExercises = weekSessions.count { it.exerciseCount >= 3 }
        )
    }

    private fun buildMonthlyMissionStats(allSessions: List<WorkoutSessionSummary>): MonthlyMissionStats {
        val currentMonth = YearMonth.now(zoneId)
        val monthStart = currentMonth.atDay(1)
        val monthEnd = currentMonth.atEndOfMonth()
        val monthSessions = allSessions.filter { session ->
            val sessionDate = session.session.date.toLocalDate()
            !sessionDate.isBefore(monthStart) && !sessionDate.isAfter(monthEnd)
        }
        val sessionsByDay = monthSessions.groupBy { it.session.date.toLocalDate() }
        val dayAggregates = sessionsByDay.mapValues { (_, sessions) ->
            sessions.fold(WeeklyDayAggregate()) { acc, session ->
                acc.copy(
                    workoutCount = acc.workoutCount + 1,
                    exerciseCount = acc.exerciseCount + session.exerciseCount,
                    setCount = acc.setCount + session.setCount,
                    totalVolume = acc.totalVolume + session.totalVolume
                )
            }
        }

        return MonthlyMissionStats(
            workoutCount = monthSessions.size,
            activeDays = sessionsByDay.size,
            exerciseCount = monthSessions.sumOf { it.exerciseCount },
            setCount = monthSessions.sumOf { it.setCount },
            totalVolume = monthSessions.sumOf { it.totalVolume }.roundToInt(),
            daysWithTenPlusSets = dayAggregates.values.count { it.setCount >= 10 },
            daysWithThousandVolume = dayAggregates.values.count { it.totalVolume >= 1_000.0 },
            sessionsWithEightPlusSets = monthSessions.count { it.setCount >= 8 },
            sessionsWithThreePlusExercises = monthSessions.count { it.exerciseCount >= 3 },
            maxSessionVolume = monthSessions.maxOfOrNull { it.totalVolume }?.roundToInt() ?: 0,
            maxSessionSets = monthSessions.maxOfOrNull { it.setCount } ?: 0,
            maxSessionExercises = monthSessions.maxOfOrNull { it.exerciseCount } ?: 0
        )
    }

    private fun buildMissionHistoryStats(allSessions: List<WorkoutSessionSummary>): MissionHistoryStats {
        if (allSessions.isEmpty()) {
            return MissionHistoryStats()
        }

        val dayAggregates = allSessions
            .groupBy { it.session.date.toLocalDate() }
            .mapValues { (_, sessions) ->
                sessions.fold(WeeklyDayAggregate()) { acc, session ->
                    acc.copy(
                        workoutCount = acc.workoutCount + 1,
                        exerciseCount = acc.exerciseCount + session.exerciseCount,
                        setCount = acc.setCount + session.setCount,
                        totalVolume = acc.totalVolume + session.totalVolume
                    )
                }
            }

        val weekAggregates = allSessions
            .groupBy { it.session.date.toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)) }
            .mapValues { (_, sessions) ->
                val weeklyDays = sessions
                    .groupBy { it.session.date.toLocalDate() }
                    .mapValues { (_, daySessions) ->
                        daySessions.fold(WeeklyDayAggregate()) { acc, session ->
                            acc.copy(
                                workoutCount = acc.workoutCount + 1,
                                exerciseCount = acc.exerciseCount + session.exerciseCount,
                                setCount = acc.setCount + session.setCount,
                                totalVolume = acc.totalVolume + session.totalVolume
                            )
                        }
                    }

                PeriodAggregate(
                    workoutCount = sessions.size,
                    activeDays = weeklyDays.size,
                    exerciseCount = sessions.sumOf { it.exerciseCount },
                    setCount = sessions.sumOf { it.setCount },
                    totalVolume = sessions.sumOf { it.totalVolume }.roundToInt(),
                    daysWithTenPlusSets = weeklyDays.values.count { it.setCount >= 10 },
                    daysWithThousandVolume = weeklyDays.values.count { it.totalVolume >= 1_000.0 },
                    sessionsWithEightPlusSets = sessions.count { it.setCount >= 8 },
                    sessionsWithThreePlusExercises = sessions.count { it.exerciseCount >= 3 },
                    maxSessionVolume = sessions.maxOfOrNull { it.totalVolume }?.roundToInt() ?: 0,
                    maxSessionSets = sessions.maxOfOrNull { it.setCount } ?: 0,
                    maxSessionExercises = sessions.maxOfOrNull { it.exerciseCount } ?: 0
                )
            }

        val monthAggregates = allSessions
            .groupBy { YearMonth.from(it.session.date.toLocalDate()) }
            .mapValues { (_, sessions) ->
                val monthlyDays = sessions
                    .groupBy { it.session.date.toLocalDate() }
                    .mapValues { (_, daySessions) ->
                        daySessions.fold(WeeklyDayAggregate()) { acc, session ->
                            acc.copy(
                                workoutCount = acc.workoutCount + 1,
                                exerciseCount = acc.exerciseCount + session.exerciseCount,
                                setCount = acc.setCount + session.setCount,
                                totalVolume = acc.totalVolume + session.totalVolume
                            )
                        }
                    }

                PeriodAggregate(
                    workoutCount = sessions.size,
                    activeDays = monthlyDays.size,
                    exerciseCount = sessions.sumOf { it.exerciseCount },
                    setCount = sessions.sumOf { it.setCount },
                    totalVolume = sessions.sumOf { it.totalVolume }.roundToInt(),
                    daysWithTenPlusSets = monthlyDays.values.count { it.setCount >= 10 },
                    daysWithThousandVolume = monthlyDays.values.count { it.totalVolume >= 1_000.0 },
                    sessionsWithEightPlusSets = sessions.count { it.setCount >= 8 },
                    sessionsWithThreePlusExercises = sessions.count { it.exerciseCount >= 3 },
                    maxSessionVolume = sessions.maxOfOrNull { it.totalVolume }?.roundToInt() ?: 0,
                    maxSessionSets = sessions.maxOfOrNull { it.setCount } ?: 0,
                    maxSessionExercises = sessions.maxOfOrNull { it.exerciseCount } ?: 0
                )
            }

        return MissionHistoryStats(
            maxDayWorkouts = dayAggregates.values.maxOfOrNull { it.workoutCount } ?: 0,
            maxDayExercises = dayAggregates.values.maxOfOrNull { it.exerciseCount } ?: 0,
            maxDaySets = dayAggregates.values.maxOfOrNull { it.setCount } ?: 0,
            maxDayVolume = dayAggregates.values.maxOfOrNull { it.totalVolume.roundToInt() } ?: 0,
            maxWeekWorkouts = weekAggregates.values.maxOfOrNull { it.workoutCount } ?: 0,
            maxWeekActiveDays = weekAggregates.values.maxOfOrNull { it.activeDays } ?: 0,
            maxWeekExercises = weekAggregates.values.maxOfOrNull { it.exerciseCount } ?: 0,
            maxWeekSets = weekAggregates.values.maxOfOrNull { it.setCount } ?: 0,
            maxWeekVolume = weekAggregates.values.maxOfOrNull { it.totalVolume } ?: 0,
            maxWeekDaysWithTenPlusSets = weekAggregates.values.maxOfOrNull { it.daysWithTenPlusSets } ?: 0,
            maxWeekDaysWithThousandVolume = weekAggregates.values.maxOfOrNull { it.daysWithThousandVolume } ?: 0,
            maxWeekSessionsWithEightPlusSets = weekAggregates.values.maxOfOrNull { it.sessionsWithEightPlusSets } ?: 0,
            maxWeekSessionsWithThreePlusExercises = weekAggregates.values.maxOfOrNull { it.sessionsWithThreePlusExercises } ?: 0,
            maxMonthWorkouts = monthAggregates.values.maxOfOrNull { it.workoutCount } ?: 0,
            maxMonthActiveDays = monthAggregates.values.maxOfOrNull { it.activeDays } ?: 0,
            maxMonthExercises = monthAggregates.values.maxOfOrNull { it.exerciseCount } ?: 0,
            maxMonthSets = monthAggregates.values.maxOfOrNull { it.setCount } ?: 0,
            maxMonthVolume = monthAggregates.values.maxOfOrNull { it.totalVolume } ?: 0,
            maxMonthDaysWithTenPlusSets = monthAggregates.values.maxOfOrNull { it.daysWithTenPlusSets } ?: 0,
            maxMonthDaysWithThousandVolume = monthAggregates.values.maxOfOrNull { it.daysWithThousandVolume } ?: 0,
            maxMonthSessionsWithEightPlusSets = monthAggregates.values.maxOfOrNull { it.sessionsWithEightPlusSets } ?: 0,
            maxMonthSessionsWithThreePlusExercises = monthAggregates.values.maxOfOrNull { it.sessionsWithThreePlusExercises } ?: 0,
            maxSessionVolume = allSessions.maxOfOrNull { it.totalVolume }?.roundToInt() ?: 0,
            maxSessionExercises = allSessions.maxOfOrNull { it.exerciseCount } ?: 0,
            maxSessionSets = allSessions.maxOfOrNull { it.setCount } ?: 0
        )
    }

    private fun <T : BaseMissionTemplate> selectMissionTemplates(
        templates: List<T>,
        count: Int,
        seed: Long,
        requiredFamilies: Set<String> = emptySet(),
        scoreSelector: (T) -> Long
    ): List<T> {
        if (templates.isEmpty() || count <= 0) {
            return emptyList()
        }

        val targetCount = count.coerceAtMost(templates.size)
        val ranked = templates.sortedWith(
            compareBy<T> { scoreSelector(it) }
                .thenBy { missionOrderScore(it.id, seed) }
        )

        val selected = mutableListOf<T>()
        val selectedIds = mutableSetOf<String>()
        val selectedFamilies = mutableSetOf<String>()

        requiredFamilies.forEach { family ->
            val template = ranked.firstOrNull { it.family == family && it.id !in selectedIds } ?: return@forEach
            selected += template
            selectedIds += template.id
            selectedFamilies += template.family
        }

        ranked.forEach { template ->
            if (selected.size >= targetCount) return@forEach
            if (template.family !in selectedFamilies) {
                selected += template
                selectedIds += template.id
                selectedFamilies += template.family
            }
        }

        ranked.forEach { template ->
            if (selected.size >= targetCount) return@forEach
            if (template.id !in selectedIds) {
                selected += template
                selectedIds += template.id
            }
        }

        return selected
    }

    private fun missionOrderScore(id: String, seed: Long): Long {
        var mixed = id.hashCode().toLong() xor (seed * 1_000_003L)
        mixed = mixed xor (mixed shl 21)
        mixed = mixed xor (mixed ushr 35)
        mixed = mixed xor (mixed shl 4)
        return mixed
    }

    private fun missionSelectionScore(goal: Int, target: Int, seed: Long): Long {
        val adjustedTarget = target.coerceAtLeast(1)
        val distance = abs(goal - adjustedTarget).toLong()
        val underTargetDistance = (adjustedTarget - goal).coerceAtLeast(0).toLong()
        val overTargetDistance = (goal - adjustedTarget).coerceAtLeast(0).toLong()
        val jitter = abs(missionOrderScore(goal.toString(), seed) % 31L)
        return (distance * 100L) +
            (underTargetDistance * 40L) +
            (overTargetDistance * 120L) +
            jitter
    }

    private fun missionTargetForFamily(
        cadence: MissionCadence,
        family: String,
        history: MissionHistoryStats
    ): Int {
        return when (cadence) {
            MissionCadence.Daily -> when (family) {
                "workouts" -> 1
                "exercises" -> boundedTarget(history.maxDayExercises, fallback = 8, min = 5, max = 12)
                "sets" -> boundedTarget(history.maxDaySets, fallback = 14, min = 10, max = 24)
                "volume" -> boundedTarget(history.maxDayVolume, fallback = 4_800, min = 3_000, max = 8_000)
                "max-session-volume" -> boundedTarget(history.maxSessionVolume, fallback = 4_000, min = 2_500, max = 7_500)
                "max-session-exercises" -> boundedTarget(history.maxSessionExercises, fallback = 6, min = 4, max = 10)
                "max-session-sets" -> boundedTarget(history.maxSessionSets, fallback = 12, min = 8, max = 22)
                else -> 1
            }

            MissionCadence.Weekly -> when (family) {
                "workouts" -> boundedTarget(history.maxWeekWorkouts, fallback = 3, min = 2, max = 3)
                "active-days" -> boundedTarget(history.maxWeekActiveDays, fallback = 3, min = 2, max = 3)
                "exercises" -> boundedTarget(history.maxWeekExercises, fallback = 28, min = 18, max = 48)
                "sets" -> boundedTarget(history.maxWeekSets, fallback = 40, min = 24, max = 64)
                "volume" -> boundedTarget(history.maxWeekVolume, fallback = 16_000, min = 9_000, max = 24_000)
                "days-10-sets" -> boundedTarget(history.maxWeekDaysWithTenPlusSets, fallback = 2, min = 1, max = 3)
                "days-1000-volume" -> boundedTarget(history.maxWeekDaysWithThousandVolume, fallback = 2, min = 1, max = 3)
                "sessions-8-sets" -> boundedTarget(history.maxWeekSessionsWithEightPlusSets, fallback = 2, min = 1, max = 3)
                "sessions-3-exercises" -> boundedTarget(history.maxWeekSessionsWithThreePlusExercises, fallback = 2, min = 1, max = 3)
                else -> 1
            }

            MissionCadence.Monthly -> when (family) {
                "workouts" -> boundedTarget(history.maxMonthWorkouts, fallback = 12, min = 8, max = 14)
                "active-days" -> boundedTarget(history.maxMonthActiveDays, fallback = 12, min = 8, max = 14)
                "exercises" -> boundedTarget(history.maxMonthExercises, fallback = 90, min = 45, max = 140)
                "sets" -> boundedTarget(history.maxMonthSets, fallback = 130, min = 70, max = 200)
                "volume" -> boundedTarget(history.maxMonthVolume, fallback = 65_000, min = 35_000, max = 95_000)
                "days-10-sets" -> boundedTarget(history.maxMonthDaysWithTenPlusSets, fallback = 8, min = 4, max = 12)
                "days-1000-volume" -> boundedTarget(history.maxMonthDaysWithThousandVolume, fallback = 8, min = 4, max = 12)
                "sessions-8-sets" -> boundedTarget(history.maxMonthSessionsWithEightPlusSets, fallback = 8, min = 4, max = 12)
                "sessions-3-exercises" -> boundedTarget(history.maxMonthSessionsWithThreePlusExercises, fallback = 8, min = 4, max = 12)
                "max-session-volume" -> boundedTarget(history.maxSessionVolume, fallback = 5_000, min = 2_500, max = 8_000)
                "max-session-sets" -> boundedTarget(history.maxSessionSets, fallback = 18, min = 10, max = 30)
                "max-session-exercises" -> boundedTarget(history.maxSessionExercises, fallback = 8, min = 4, max = 12)
                else -> 1
            }
        }
    }

    private fun boundedTarget(observed: Int, fallback: Int, min: Int, max: Int): Int {
        val baseline = if (observed > 0) observed else fallback
        return baseline.coerceIn(min, max)
    }

    private fun missionXpReward(cadence: MissionCadence, goal: Int, target: Int): Int {
        val base = when (cadence) {
            MissionCadence.Daily -> 90
            MissionCadence.Weekly -> 220
            MissionCadence.Monthly -> 420
        }
        val ratio = goal.toDouble() / target.coerceAtLeast(1).toDouble()
        val difficultyMultiplier = when {
            ratio >= 1.35 -> 1.9
            ratio >= 1.2 -> 1.65
            ratio >= 1.05 -> 1.45
            ratio >= 0.9 -> 1.25
            ratio >= 0.75 -> 1.05
            else -> 0.9
        }
        return (base * difficultyMultiplier).roundToInt().coerceAtLeast((base * 0.8).roundToInt())
    }

    private fun mission(
        id: String,
        title: String,
        cadenceLabel: String,
        summary: String,
        progress: Int,
        goal: Int,
        xpReward: Int,
        unitEn: String,
        unitUk: String
    ): MissionProgressUiModel {
        val progressLabel = if (isUkrainian()) {
            "${progress.coerceAtMost(goal)} / $goal $unitUk"
        } else {
            "${progress.coerceAtMost(goal)} / $goal $unitEn"
        }

        return MissionProgressUiModel(
            id = id,
            title = title,
            cadenceLabel = cadenceLabel,
            summary = summary,
            progressLabel = progressLabel,
            progress = progress,
            goal = goal,
            xpReward = xpReward,
            progressFraction = progressFraction(progress, goal),
            isComplete = progress >= goal
        )
    }

    private fun missionXpFor(
        dailyMissions: List<MissionProgressUiModel>,
        weeklyMissions: List<MissionProgressUiModel>,
        monthlyMissions: List<MissionProgressUiModel>
    ): Int {
        return (dailyMissions + weeklyMissions + monthlyMissions).sumOf { mission ->
            if (mission.isComplete) mission.xpReward else 0
        }
    }

    private fun buildAchievements(
        allSessions: List<WorkoutSessionSummary>,
        streakDays: Int
    ): List<AchievementPreviewUiModel> {
        val totalWorkouts = allSessions.size
        val totalSets = allSessions.sumOf { it.setCount }
        val totalVolume = allSessions.sumOf { it.totalVolume }.roundToInt()

        val definitions = listOf(
            achievement(
                id = "first-session",
                title = t(en = "First session", uk = "Перша сесія"),
                description = t(
                    en = "Log your first workout.",
                    uk = "Запиши своє перше тренування."
                ),
                value = totalWorkouts,
                goal = 1,
                unit = t(en = "workout", uk = "тренування")
            ),
            achievement(
                id = "ten-sessions",
                title = t(en = "Ten sessions", uk = "Десять сесій"),
                description = t(
                    en = "Reach ten logged workouts.",
                    uk = "Набери 10 записаних тренувань."
                ),
                value = totalWorkouts,
                goal = 10,
                unit = t(en = "workouts", uk = "тренувань")
            ),
            achievement(
                id = "seven-day-streak",
                title = t(en = "Streak keeper", uk = "Тримай серію"),
                description = t(
                    en = "Hold a 7-day streak.",
                    uk = "Втримай серію 7 днів."
                ),
                value = streakDays,
                goal = 7,
                unit = t(en = "days", uk = "днів")
            ),
            achievement(
                id = "set-century",
                title = t(en = "Set century", uk = "Сотня підходів"),
                description = t(
                    en = "Finish 100 total sets.",
                    uk = "Виконай загалом 100 підходів."
                ),
                value = totalSets,
                goal = 100,
                unit = t(en = "sets", uk = "підходів")
            ),
            achievement(
                id = "volume-builder",
                title = t(en = "Volume builder", uk = "Будівник обсягу"),
                description = t(
                    en = "Accumulate 10000 total volume.",
                    uk = "Накопич загалом 10000 обсягу."
                ),
                value = totalVolume,
                goal = 10_000,
                unit = t(en = "volume", uk = "обсягу")
            )
        )

        return definitions
            .sortedWith(
                compareByDescending<AchievementPreviewUiModel> { it.isUnlocked }
                    .thenByDescending { it.progressFraction }
                    .thenBy { it.goal }
            )
            .take(4)
    }

    private fun achievement(
        id: String,
        title: String,
        description: String,
        value: Int,
        goal: Int,
        unit: String
    ): AchievementPreviewUiModel {
        val unlocked = value >= goal
        return AchievementPreviewUiModel(
            id = id,
            title = title,
            description = description,
            progressLabel = "${value.coerceAtMost(goal)} / $goal $unit",
            statusLabel = if (unlocked) {
                t(en = "Unlocked", uk = "Відкрито")
            } else {
                t(en = "In progress", uk = "У процесі")
            },
            progress = value,
            goal = goal,
            progressFraction = progressFraction(value, goal),
            isUnlocked = unlocked
        )
    }

    private fun sessionXp(session: WorkoutSessionSummary): Int {
        return 90 +
            session.exerciseCount * 16 +
            session.setCount * 8 +
            (session.totalVolume / 80.0).roundToInt()
    }

    private fun calculateLevelProgress(totalXp: Int): LevelProgress {
        var level = 1
        var remainingXp = totalXp
        var xpForNextLevel = xpRequirementForLevel(level)

        while (remainingXp >= xpForNextLevel) {
            remainingXp -= xpForNextLevel
            level += 1
            xpForNextLevel = xpRequirementForLevel(level)
        }

        return LevelProgress(
            level = level,
            currentLevelXp = remainingXp,
            xpForNextLevel = xpForNextLevel,
            progressFraction = progressFraction(remainingXp, xpForNextLevel)
        )
    }

    private fun xpRequirementForLevel(level: Int): Int {
        val stage = (level - 1).coerceAtLeast(0)
        return 200 + (stage * 85) + ((stage * stage) * 8)
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
        if (level <= 1) return 0
        var total = 0
        for (current in 1 until level) {
            total += xpRequirementForLevel(current)
        }
        return total
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

    private fun t(en: String, uk: String): String = if (isUkrainian()) uk else en

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

private const val ACTIVE_DAILY_MISSIONS = 5
private const val ACTIVE_WEEKLY_MISSIONS = 10
private const val ACTIVE_MONTHLY_MISSIONS = 10

private interface BaseMissionTemplate {
    val id: String
    val family: String
    val titleEn: String
    val titleUk: String
    val summaryEn: String
    val summaryUk: String
    val goal: Int
    val unitEn: String
    val unitUk: String
}

private data class DailyMissionStats(
    val workoutCount: Int,
    val exerciseCount: Int,
    val setCount: Int,
    val totalVolume: Int,
    val maxSessionVolume: Int,
    val maxSessionExercises: Int,
    val maxSessionSets: Int
)

private data class WeeklyMissionStats(
    val workoutCount: Int,
    val activeDays: Int,
    val exerciseCount: Int,
    val setCount: Int,
    val totalVolume: Int,
    val daysWithTenPlusSets: Int,
    val daysWithThousandVolume: Int,
    val sessionsWithEightPlusSets: Int,
    val sessionsWithThreePlusExercises: Int
)

private data class MonthlyMissionStats(
    val workoutCount: Int,
    val activeDays: Int,
    val exerciseCount: Int,
    val setCount: Int,
    val totalVolume: Int,
    val daysWithTenPlusSets: Int,
    val daysWithThousandVolume: Int,
    val sessionsWithEightPlusSets: Int,
    val sessionsWithThreePlusExercises: Int,
    val maxSessionVolume: Int,
    val maxSessionSets: Int,
    val maxSessionExercises: Int
)

private data class DailyMissionTemplate(
    override val id: String,
    override val family: String,
    override val titleEn: String,
    override val titleUk: String,
    override val summaryEn: String,
    override val summaryUk: String,
    override val goal: Int,
    override val unitEn: String,
    override val unitUk: String,
    val progressSelector: (DailyMissionStats) -> Int
) : BaseMissionTemplate

private data class WeeklyMissionTemplate(
    override val id: String,
    override val family: String,
    override val titleEn: String,
    override val titleUk: String,
    override val summaryEn: String,
    override val summaryUk: String,
    override val goal: Int,
    override val unitEn: String,
    override val unitUk: String,
    val progressSelector: (WeeklyMissionStats) -> Int
) : BaseMissionTemplate

private data class MonthlyMissionTemplate(
    override val id: String,
    override val family: String,
    override val titleEn: String,
    override val titleUk: String,
    override val summaryEn: String,
    override val summaryUk: String,
    override val goal: Int,
    override val unitEn: String,
    override val unitUk: String,
    val progressSelector: (MonthlyMissionStats) -> Int
) : BaseMissionTemplate

private data class WeeklyDayAggregate(
    val workoutCount: Int = 0,
    val exerciseCount: Int = 0,
    val setCount: Int = 0,
    val totalVolume: Double = 0.0
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

private enum class MissionCadence {
    Daily,
    Weekly,
    Monthly
}

private data class PeriodAggregate(
    val workoutCount: Int = 0,
    val activeDays: Int = 0,
    val exerciseCount: Int = 0,
    val setCount: Int = 0,
    val totalVolume: Int = 0,
    val daysWithTenPlusSets: Int = 0,
    val daysWithThousandVolume: Int = 0,
    val sessionsWithEightPlusSets: Int = 0,
    val sessionsWithThreePlusExercises: Int = 0,
    val maxSessionVolume: Int = 0,
    val maxSessionSets: Int = 0,
    val maxSessionExercises: Int = 0
)

private data class MissionHistoryStats(
    val maxDayWorkouts: Int = 0,
    val maxDayExercises: Int = 0,
    val maxDaySets: Int = 0,
    val maxDayVolume: Int = 0,
    val maxWeekWorkouts: Int = 0,
    val maxWeekActiveDays: Int = 0,
    val maxWeekExercises: Int = 0,
    val maxWeekSets: Int = 0,
    val maxWeekVolume: Int = 0,
    val maxWeekDaysWithTenPlusSets: Int = 0,
    val maxWeekDaysWithThousandVolume: Int = 0,
    val maxWeekSessionsWithEightPlusSets: Int = 0,
    val maxWeekSessionsWithThreePlusExercises: Int = 0,
    val maxMonthWorkouts: Int = 0,
    val maxMonthActiveDays: Int = 0,
    val maxMonthExercises: Int = 0,
    val maxMonthSets: Int = 0,
    val maxMonthVolume: Int = 0,
    val maxMonthDaysWithTenPlusSets: Int = 0,
    val maxMonthDaysWithThousandVolume: Int = 0,
    val maxMonthSessionsWithEightPlusSets: Int = 0,
    val maxMonthSessionsWithThreePlusExercises: Int = 0,
    val maxSessionVolume: Int = 0,
    val maxSessionExercises: Int = 0,
    val maxSessionSets: Int = 0
)

data class MuscleDefinition(
    val id: String,
    val titleEn: String,
    val titleUk: String
)

data class MuscleContribution(
    val muscleId: String,
    val weight: Double
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

private const val BODYWEIGHT_LOAD_PROXY = 72.0
private const val SET_COMPLETION_LOAD = 35.0

val MUSCLE_DEFINITIONS = listOf(
    MuscleDefinition("chest", "Chest", "Груди"),
    MuscleDefinition("shoulders", "Shoulders", "Плечі"),
    MuscleDefinition("biceps", "Biceps", "Біцепс"),
    MuscleDefinition("triceps", "Triceps", "Трицепс"),
    MuscleDefinition("forearms", "Forearms", "Передпліччя"),
    MuscleDefinition("abs", "Abs", "Прес"),
    MuscleDefinition("obliques", "Obliques", "Косі мʼязи"),
    MuscleDefinition("lats", "Lats", "Широчайші"),
    MuscleDefinition("upperBack", "Upper back", "Верх спини"),
    MuscleDefinition("lowerBack", "Lower back", "Поперек"),
    MuscleDefinition("glutes", "Glutes", "Сідниці"),
    MuscleDefinition("quads", "Quads", "Квадрицепси"),
    MuscleDefinition("hamstrings", "Hamstrings", "Біцепс стегна"),
    MuscleDefinition("adductors", "Adductors", "Привідні"),
    MuscleDefinition("calves", "Calves", "Ікри")
)

private val EXACT_MUSCLE_MAP = mapOf(
    "нахили в сторони на гіперекстензії" to muscles("obliques" to 0.9, "abs" to 0.35, "lowerBack" to 0.25),
    "присід зі штангою" to muscles("quads" to 1.0, "glutes" to 0.7, "hamstrings" to 0.45, "lowerBack" to 0.25, "abs" to 0.2),
    "бокові нахили" to muscles("obliques" to 0.9, "abs" to 0.3),
    "брусья" to muscles("triceps" to 0.85, "chest" to 0.75, "shoulders" to 0.35),
    "біцепс з гантелями сидячи" to muscles("biceps" to 1.0, "forearms" to 0.25),
    "гантеля над головою" to muscles("triceps" to 1.0, "shoulders" to 0.3),
    "гантелі лежачи" to muscles("chest" to 0.9, "triceps" to 0.55, "shoulders" to 0.45),
    "горизонтальна важільна тяга" to muscles("upperBack" to 1.0, "lats" to 0.75, "biceps" to 0.45, "forearms" to 0.25),
    "гіперекстензія" to muscles("lowerBack" to 1.0, "glutes" to 0.55, "hamstrings" to 0.45),
    "жим лежачи" to muscles("chest" to 1.0, "triceps" to 0.6, "shoulders" to 0.5),
    "жим ногами" to muscles("quads" to 1.0, "glutes" to 0.55, "hamstrings" to 0.35, "calves" to 0.15),
    "жим сидячи" to muscles("shoulders" to 1.0, "triceps" to 0.55, "chest" to 0.2),
    "журавель" to muscles("abs" to 0.75, "obliques" to 0.45),
    "зведення ніг" to muscles("adductors" to 1.0, "quads" to 0.25),
    "згибання ніг" to muscles("hamstrings" to 1.0, "calves" to 0.2),
    "махи в сторони" to muscles("shoulders" to 1.0),
    "метелик в середину" to muscles("chest" to 1.0, "shoulders" to 0.25),
    "метелик в сторони" to muscles("shoulders" to 0.75, "upperBack" to 0.65),
    "прес з диском в сторони" to muscles("obliques" to 0.85, "abs" to 0.45),
    "прес звичайний з диском" to muscles("abs" to 1.0, "obliques" to 0.25),
    "прес(підйом ніг)" to muscles("abs" to 1.0, "hipFlexors" to 0.25),
    "протяжка" to muscles("shoulders" to 0.85, "upperBack" to 0.55, "biceps" to 0.25),
    "підйом на носки" to muscles("calves" to 1.0),
    "підтягування в гравітроні" to muscles("lats" to 1.0, "upperBack" to 0.65, "biceps" to 0.55, "forearms" to 0.3),
    "підтягування з резинкою" to muscles("lats" to 1.0, "upperBack" to 0.65, "biceps" to 0.55, "forearms" to 0.3),
    "розгинання ніг" to muscles("quads" to 1.0),
    "румунська тяга" to muscles("hamstrings" to 1.0, "glutes" to 0.85, "lowerBack" to 0.65, "upperBack" to 0.2),
    "станова тяга" to muscles("lowerBack" to 0.9, "glutes" to 0.85, "hamstrings" to 0.8, "upperBack" to 0.45, "quads" to 0.35, "forearms" to 0.3),
    "тренажер скота(біцепс)" to muscles("biceps" to 1.0, "forearms" to 0.25),
    "трицепс трикутник" to muscles("triceps" to 1.0),
    "французький жим" to muscles("triceps" to 1.0, "shoulders" to 0.15),
    "фронтальна тяга" to muscles("lats" to 1.0, "upperBack" to 0.7, "biceps" to 0.5, "forearms" to 0.25),
    "штанга на біцепс" to muscles("biceps" to 1.0, "forearms" to 0.35)
)

fun ExerciseHistoryEntry.estimatedLoad(): Double {
    val repsValue = reps.coerceAtLeast(0)
    val trackedLoad = weight.coerceAtLeast(0.0) * repsValue
    val exerciseLoad = if (trackedLoad > 0.0) {
        trackedLoad
    } else {
        BODYWEIGHT_LOAD_PROXY * repsValue
    }
    return exerciseLoad + SET_COMPLETION_LOAD
}

fun muscleContributionsForExercise(
    exerciseName: String,
    manualMappings: Map<String, List<MuscleContribution>> = emptyMap()
): List<MuscleContribution> {
    val normalizedName = exerciseName.normalizedExerciseName()
    manualMappings[normalizedName]?.takeIf { it.isNotEmpty() }?.let { return it }
    EXACT_MUSCLE_MAP[normalizedName]?.let { return it }

    val inferred = linkedMapOf<String, Double>()
    fun add(muscleId: String, weight: Double) {
        inferred[muscleId] = (inferred[muscleId] ?: 0.0).coerceAtLeast(weight.coerceIn(0.0, 1.0))
    }

    if (normalizedName.containsAny("біцепс", "bicep", "curl")) {
        add("biceps", 1.0)
        add("forearms", 0.25)
    }
    if (normalizedName.containsAny("трицепс", "tricep", "француз")) {
        add("triceps", 1.0)
    }
    if (normalizedName.contains("жим") && normalizedName.containsAny("ног", "leg press")) {
        add("quads", 1.0)
        add("glutes", 0.55)
        add("hamstrings", 0.35)
    }
    if (normalizedName.contains("жим") && !normalizedName.containsAny("ног", "leg press")) {
        add("chest", 0.85)
        add("triceps", 0.55)
        add("shoulders", 0.45)
    }
    if (normalizedName.containsAny("плеч", "дельт", "махи", "shoulder", "press overhead")) {
        add("shoulders", 1.0)
    }
    if (normalizedName.containsAny("підтяг", "pull up", "pulldown")) {
        add("lats", 1.0)
        add("upperBack", 0.65)
        add("biceps", 0.55)
        add("forearms", 0.3)
    }
    if (normalizedName.contains("тяга") && normalizedName.containsAny("румун", "станов", "deadlift")) {
        add("hamstrings", 0.9)
        add("glutes", 0.85)
        add("lowerBack", 0.75)
        add("upperBack", 0.3)
        add("forearms", 0.25)
    }
    if (normalizedName.contains("тяга") && !normalizedName.containsAny("румун", "станов", "deadlift")) {
        add("lats", 0.9)
        add("upperBack", 0.85)
        add("biceps", 0.45)
        add("forearms", 0.25)
    }
    if (normalizedName.containsAny("прис", "squat")) {
        add("quads", 1.0)
        add("glutes", 0.7)
        add("hamstrings", 0.45)
        add("lowerBack", 0.25)
    }
    if (normalizedName.containsAny("розгинання ніг", "leg extension")) {
        add("quads", 1.0)
    }
    if (normalizedName.containsAny("згибання ніг", "leg curl")) {
        add("hamstrings", 1.0)
    }
    if (normalizedName.containsAny("підйом на носки", "calf")) {
        add("calves", 1.0)
    }
    if (normalizedName.containsAny("прес", "crunch", "sit up", "leg raise")) {
        add("abs", 1.0)
    }
    if (normalizedName.containsAny("нахил", "сторони", "side bend")) {
        add("obliques", 0.85)
    }
    if (normalizedName.containsAny("гіперекстензі", "hyperextension")) {
        add("lowerBack", 1.0)
        add("glutes", 0.55)
        add("hamstrings", 0.45)
    }
    if (normalizedName.containsAny("зведення ніг", "adductor")) {
        add("adductors", 1.0)
    }

    return inferred.map { (muscleId, weight) ->
        MuscleContribution(muscleId = muscleId, weight = weight)
    }
}

private fun muscles(vararg values: Pair<String, Double>): List<MuscleContribution> {
    return values
        .filter { (muscleId, _) -> MUSCLE_DEFINITIONS.any { it.id == muscleId } }
        .map { (muscleId, weight) ->
            MuscleContribution(
                muscleId = muscleId,
                weight = weight.coerceIn(0.0, 1.0)
            )
        }
}

fun String.normalizedExerciseName(): String {
    return lowercase(Locale.ROOT)
        .replace('ʼ', '\'')
        .replace('’', '\'')
        .replace(Regex("\\s+"), " ")
        .trim()
}

private fun String.containsAny(vararg tokens: String): Boolean {
    return tokens.any { token -> contains(token) }
}

private data class RankDefinition(
    val id: String,
    val levelRequirement: Int,
    val titleEn: String,
    val titleUk: String
)

private val RANK_DEFINITIONS = listOf(
    RankDefinition("rookie", 1, "Rookie", "Новачок"),
    RankDefinition("starter", 3, "Starter", "Стартовий"),
    RankDefinition("steady", 5, "Steady", "Стабільний"),
    RankDefinition("driven", 7, "Driven", "Вмотивований"),
    RankDefinition("striker", 9, "Striker", "Ударний"),
    RankDefinition("ironclad", 11, "Ironclad", "Незламний"),
    RankDefinition("vanguard", 13, "Vanguard", "Авангард"),
    RankDefinition("challenger", 15, "Challenger", "Претендент"),
    RankDefinition("dominator", 17, "Dominator", "Домінатор"),
    RankDefinition("elite", 19, "Elite", "Еліта"),
    RankDefinition("titan", 21, "Titan", "Титан"),
    RankDefinition("colossus", 23, "Colossus", "Колос"),
    RankDefinition("warborn", 25, "Warborn", "Воїн"),
    RankDefinition("apex", 27, "Apex", "Апекс"),
    RankDefinition("mythic", 29, "Mythic", "Міфічний"),
    RankDefinition("legend", 31, "Legend", "Легенда"),
    RankDefinition("eternal", 33, "Eternal", "Вічний"),
    RankDefinition("immortal", 35, "Immortal", "Безсмертний"),
    RankDefinition("paragon", 37, "Paragon", "Парагон"),
    RankDefinition("overlord", 39, "Overlord", "Володар"),
    RankDefinition("ascendant", 41, "Ascendant", "Вознесений"),
    RankDefinition("conqueror", 43, "Conqueror", "Завойовник"),
    RankDefinition("sovereign", 45, "Sovereign", "Суверен"),
    RankDefinition("prime", 47, "Prime", "Прайм"),
    RankDefinition("omni", 49, "Omni", "Омні"),
    RankDefinition("galactic", 51, "Galactic", "Галактичний"),
    RankDefinition("nova", 53, "Nova", "Нова"),
    RankDefinition("singularity", 55, "Singularity", "Сингулярність"),
    RankDefinition("omega", 57, "Omega", "Омега"),
    RankDefinition("transcendent", 60, "Transcendent", "Трансцендентний"),
    RankDefinition("celestial", 64, "Celestial", "Небесний"),
    RankDefinition("empyrean", 68, "Empyrean", "Емпірей"),
    RankDefinition("infinite", 72, "Infinite", "Нескінченний"),
    RankDefinition("beyond", 76, "Beyond", "Понадмежний"),
    RankDefinition("cosmic-warlord", 80, "Cosmic Warlord", "Космічний воєвода")
)

