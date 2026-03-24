package com.example.gymapp.ui.viewmodel

import androidx.appcompat.app.AppCompatDelegate
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.lifecycle.viewModelScope
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
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.TextStyle
import java.time.temporal.TemporalAdjusters
import java.util.Locale
import kotlin.math.abs
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

    private val sessionsFlow = monthOffset.flatMapLatest { offset ->
        repository.observeSessionsForMonth(offset)
    }

    private val dashboardFlow = monthOffset.flatMapLatest { offset ->
        repository.observeDashboardStatsForMonth(offset)
    }

    private val allSessionsFlow = repository.observeSessions()

    val uiState: StateFlow<WorkoutListUiState> = combine(
        monthOffset,
        sessionsFlow,
        dashboardFlow,
        allSessionsFlow
    ) { offset, sessions, dashboardStats, allSessions ->
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

    private fun buildDailyMissions(
        allSessions: List<WorkoutSessionSummary>,
        historyStats: MissionHistoryStats
    ): List<MissionProgressUiModel> {
        val stats = buildDailyMissionStats(allSessions)
        val seed = LocalDate.now(zoneId).toEpochDay()
        val requiredFamilies = if (historyStats.maxDayVolume >= 3_500) {
            setOf("volume")
        } else {
            setOf("workouts")
        }
        val selectedTemplates = selectMissionTemplates(
            templates = dailyMissionCatalog(),
            count = ACTIVE_DAILY_MISSIONS,
            seed = seed,
            requiredFamilies = requiredFamilies,
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
        val requiredFamilies = if (historyStats.maxWeekVolume >= 12_000) {
            setOf("volume")
        } else {
            setOf("workouts")
        }
        val selectedTemplates = selectMissionTemplates(
            templates = weeklyMissionCatalog(),
            count = ACTIVE_WEEKLY_MISSIONS,
            seed = seed,
            requiredFamilies = requiredFamilies,
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
        val requiredFamilies = if (historyStats.maxMonthVolume >= 45_000) {
            setOf("volume")
        } else {
            setOf("workouts")
        }
        val selectedTemplates = selectMissionTemplates(
            templates = monthlyMissionCatalog(),
            count = ACTIVE_MONTHLY_MISSIONS,
            seed = monthSeed,
            requiredFamilies = requiredFamilies,
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
                goals = intSeries(3, 1, 20),
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
                goals = intSeries(8, 2, 18),
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
                    base = 900,
                    factors = listOf(1.0, 1.15, 1.3, 1.5, 1.75, 2.0, 2.4, 2.8, 3.2, 3.7, 4.3, 5.0, 5.8, 6.7, 7.7, 8.8, 10.0, 11.5, 13.0, 15.0, 17.5, 20.0)
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
                    base = 600,
                    factors = listOf(1.0, 1.25, 1.5, 1.8, 2.1, 2.5, 3.0, 3.6, 4.3, 5.1, 6.0, 7.0, 8.2, 9.5, 11.0, 13.0, 15.0)
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
                goals = intSeries(4, 1, 18),
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
                goals = intSeries(8, 2, 18),
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
                goals = intSeries(3, 1, 24),
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
                goals = intSeries(3, 1, 12),
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
                goals = intSeries(18, 6, 20),
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
                    base = 5_000,
                    factors = listOf(1.0, 1.15, 1.3, 1.5, 1.75, 2.0, 2.3, 2.6, 3.0, 3.5, 4.0, 4.6, 5.3, 6.1, 7.0, 8.0, 9.2, 10.5, 12.0, 13.5, 15.0, 17.0, 19.0, 21.5, 24.0, 27.0)
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
                goals = intSeries(12, 4, 20),
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
                goals = intSeries(2, 1, 12),
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
                goals = intSeries(2, 1, 12),
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
                goals = intSeries(3, 1, 16),
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
                goals = intSeries(2, 1, 16),
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
                goals = intSeries(12, 2, 30),
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
                goals = intSeries(10, 1, 22),
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
                goals = intSeries(80, 10, 28),
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
                    base = 15_000,
                    factors = listOf(1.0, 1.2, 1.45, 1.75, 2.1, 2.5, 3.0, 3.6, 4.3, 5.1, 6.0, 7.1, 8.3, 9.6, 11.0, 12.6, 14.3, 16.2, 18.2, 20.5)
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
                goals = intSeries(35, 5, 20),
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
                goals = intSeries(6, 1, 16),
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
                goals = intSeries(6, 1, 16),
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
                goals = intSeries(10, 2, 20),
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
                goals = intSeries(8, 2, 16),
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
                    base = 1_200,
                    factors = listOf(1.0, 1.2, 1.45, 1.75, 2.1, 2.5, 3.0, 3.6, 4.3, 5.1, 6.1, 7.3, 8.6, 10.0, 11.6, 13.3)
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
                goals = intSeries(12, 2, 20),
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
                goals = intSeries(5, 1, 16),
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
        // Penalize easier-than-target goals, so strong users receive harder missions first.
        val underTargetPenalty = if (goal < adjustedTarget) (adjustedTarget - goal).toLong() * 3L else 0L
        val jitter = abs(missionOrderScore(goal.toString(), seed) % 31L)
        return (distance * 100L) + (underTargetPenalty * 100L) + jitter
    }

    private fun missionTargetForFamily(
        cadence: MissionCadence,
        family: String,
        history: MissionHistoryStats
    ): Int {
        return when (cadence) {
            MissionCadence.Daily -> when (family) {
                "workouts" -> 1
                "exercises" -> maxOf(8, history.maxDayExercises)
                "sets" -> maxOf(16, history.maxDaySets)
                "volume" -> maxOf(6_000, history.maxDayVolume)
                "max-session-volume" -> maxOf(2_500, history.maxSessionVolume)
                "max-session-exercises" -> maxOf(6, history.maxSessionExercises)
                "max-session-sets" -> maxOf(12, history.maxSessionSets)
                else -> 1
            }

            MissionCadence.Weekly -> when (family) {
                "workouts" -> maxOf(6, history.maxWeekWorkouts)
                "active-days" -> maxOf(4, history.maxWeekActiveDays)
                "exercises" -> maxOf(28, history.maxWeekExercises)
                "sets" -> maxOf(60, history.maxWeekSets)
                "volume" -> maxOf(20_000, history.maxWeekVolume)
                "days-10-sets" -> maxOf(3, history.maxWeekDaysWithTenPlusSets)
                "days-1000-volume" -> maxOf(3, history.maxWeekDaysWithThousandVolume)
                "sessions-8-sets" -> maxOf(4, history.maxWeekSessionsWithEightPlusSets)
                "sessions-3-exercises" -> maxOf(4, history.maxWeekSessionsWithThreePlusExercises)
                else -> 1
            }

            MissionCadence.Monthly -> when (family) {
                "workouts" -> maxOf(20, history.maxMonthWorkouts)
                "active-days" -> maxOf(14, history.maxMonthActiveDays)
                "exercises" -> maxOf(70, history.maxMonthExercises)
                "sets" -> maxOf(180, history.maxMonthSets)
                "volume" -> maxOf(70_000, history.maxMonthVolume)
                "days-10-sets" -> maxOf(10, history.maxMonthDaysWithTenPlusSets)
                "days-1000-volume" -> maxOf(10, history.maxMonthDaysWithThousandVolume)
                "sessions-8-sets" -> maxOf(16, history.maxMonthSessionsWithEightPlusSets)
                "sessions-3-exercises" -> maxOf(14, history.maxMonthSessionsWithThreePlusExercises)
                "max-session-volume" -> maxOf(3_500, history.maxSessionVolume)
                "max-session-sets" -> maxOf(16, history.maxSessionSets)
                "max-session-exercises" -> maxOf(7, history.maxSessionExercises)
                else -> 1
            }
        }
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

