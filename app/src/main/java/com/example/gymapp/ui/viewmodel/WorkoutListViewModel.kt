package com.example.gymapp.ui.viewmodel

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
import kotlin.math.roundToInt

data class SoloProgressUiModel(
    val totalXp: Int = 0,
    val monthXp: Int = 0,
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
    val progressFraction: Float = 0f,
    val isComplete: Boolean = false
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
    val achievements: List<AchievementPreviewUiModel> = emptyList()
)

@OptIn(ExperimentalCoroutinesApi::class)
class WorkoutListViewModel(
    private val repository: GymRepository
) : ViewModel() {
    private val zoneId = ZoneId.systemDefault()
    private val locale = Locale.getDefault()
    private val isUkrainian = locale.language.equals("uk", ignoreCase = true)
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
        val soloProgress = buildSoloProgress(
            allSessions = allSessions,
            monthSessions = sessions,
            streakDays = dashboardStats.streakDays,
            weeklyStreakWeeks = dashboardStats.weeklyStreakWeeks
        )
        WorkoutListUiState(
            monthOffset = offset,
            monthLabel = DateTimeUtils.monthLabel(offset),
            sessions = sessions,
            dashboardStats = dashboardStats,
            soloProgress = soloProgress,
            activityHeatmap = buildHeatmap(offset, sessions),
            dailyMissions = buildDailyMissions(allSessions),
            weeklyMissions = buildWeeklyMissions(allSessions),
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
        weeklyStreakWeeks: Int
    ): SoloProgressUiModel {
        val totalXp = allSessions.sumOf(::sessionXp)
        val monthXp = monthSessions.sumOf(::sessionXp)
        val levelInfo = calculateLevelProgress(totalXp)
        val currentTitle = titleForLevel(levelInfo.level)
        val nextTitle = nextTitleAfter(levelInfo.level)
        val summary = when {
            allSessions.isEmpty() -> t(
                en = "Log a workout to start your momentum.",
                uk = "Запиши тренування, щоб запустити свій темп."
            )
            weeklyStreakWeeks > 0 -> if (isUkrainian) {
                "$weeklyStreakWeeks тиж. поспіль із 3+ тренуваннями."
            } else {
                "$weeklyStreakWeeks successful week${if (weeklyStreakWeeks == 1) "" else "s"} in a row."
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

    private fun buildDailyMissions(allSessions: List<WorkoutSessionSummary>): List<MissionProgressUiModel> {
        val today = LocalDate.now(zoneId)
        val todaySessions = allSessions.filter { it.session.date.toLocalDate() == today }
        val workoutCount = todaySessions.size
        val totalVolume = todaySessions.sumOf { it.totalVolume }.roundToInt()

        return listOf(
            MissionProgressUiModel(
                id = "daily-check-in",
                title = t(en = "Daily check-in", uk = "Щоденний чек-ін"),
                cadenceLabel = t(en = "Today", uk = "Сьогодні"),
                summary = t(
                    en = "Complete one workout today.",
                    uk = "Заверши одне тренування сьогодні."
                ),
                progressLabel = if (isUkrainian) {
                    "$workoutCount / 1 тренування"
                } else {
                    "$workoutCount / 1 workout"
                },
                progress = workoutCount,
                goal = 1,
                progressFraction = progressFraction(workoutCount, 1),
                isComplete = workoutCount >= 1
            ),
            MissionProgressUiModel(
                id = "daily-volume",
                title = t(en = "Power push", uk = "Силовий ривок"),
                cadenceLabel = t(en = "Today", uk = "Сьогодні"),
                summary = t(
                    en = "Reach 1200 volume in a single day.",
                    uk = "Набери 1200 обсягу за один день."
                ),
                progressLabel = if (isUkrainian) {
                    "${totalVolume.coerceAtMost(1_200)} / 1200 обсягу"
                } else {
                    "${totalVolume.coerceAtMost(1_200)} / 1200 volume"
                },
                progress = totalVolume,
                goal = 1_200,
                progressFraction = progressFraction(totalVolume, 1_200),
                isComplete = totalVolume >= 1_200
            )
        )
    }

    private fun buildWeeklyMissions(allSessions: List<WorkoutSessionSummary>): List<MissionProgressUiModel> {
        val today = LocalDate.now(zoneId)
        val weekStart = today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val weekEnd = weekStart.plusDays(6)
        val weekSessions = allSessions.filter { session ->
            val sessionDate = session.session.date.toLocalDate()
            !sessionDate.isBefore(weekStart) && !sessionDate.isAfter(weekEnd)
        }
        val workoutCount = weekSessions.size
        val totalSets = weekSessions.sumOf { it.setCount }

        return listOf(
            MissionProgressUiModel(
                id = "weekly-workouts",
                title = t(en = "Consistency week", uk = "Стабільний тиждень"),
                cadenceLabel = t(en = "This week", uk = "Цього тижня"),
                summary = t(
                    en = "Train three times before Sunday.",
                    uk = "Потренуйся 3 рази до неділі."
                ),
                progressLabel = if (isUkrainian) {
                    "${workoutCount.coerceAtMost(3)} / 3 тренування"
                } else {
                    "${workoutCount.coerceAtMost(3)} / 3 workouts"
                },
                progress = workoutCount,
                goal = 3,
                progressFraction = progressFraction(workoutCount, 3),
                isComplete = workoutCount >= 3
            ),
            MissionProgressUiModel(
                id = "weekly-sets",
                title = t(en = "Set streak", uk = "Серія підходів"),
                cadenceLabel = t(en = "This week", uk = "Цього тижня"),
                summary = t(
                    en = "Finish 18 total sets this week.",
                    uk = "Виконай 18 підходів за тиждень."
                ),
                progressLabel = if (isUkrainian) {
                    "${totalSets.coerceAtMost(18)} / 18 підходів"
                } else {
                    "${totalSets.coerceAtMost(18)} / 18 sets"
                },
                progress = totalSets,
                goal = 18,
                progressFraction = progressFraction(totalSets, 18),
                isComplete = totalSets >= 18
            )
        )
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

    private fun xpRequirementForLevel(level: Int): Int = 180 + ((level - 1) * 70)

    private fun titleForLevel(level: Int): String = when {
        level >= 16 -> t(en = "Titan", uk = "Титан")
        level >= 12 -> t(en = "Elite", uk = "Еліта")
        level >= 8 -> t(en = "Ironclad", uk = "Незламний")
        level >= 5 -> t(en = "Driven", uk = "Вмотивований")
        level >= 3 -> t(en = "Steady", uk = "Стабільний")
        else -> t(en = "Rookie", uk = "Новачок")
    }

    private fun nextTitleAfter(level: Int): String = when {
        level < 3 -> t(en = "Steady", uk = "Стабільний")
        level < 5 -> t(en = "Driven", uk = "Вмотивований")
        level < 8 -> t(en = "Ironclad", uk = "Незламний")
        level < 12 -> t(en = "Elite", uk = "Еліта")
        level < 16 -> t(en = "Titan", uk = "Титан")
        else -> t(en = "Legend", uk = "Легенда")
    }

    private fun progressFraction(progress: Int, goal: Int): Float {
        if (goal <= 0) return 0f
        return (progress.toFloat() / goal.toFloat()).coerceIn(0f, 1f)
    }

    private fun t(en: String, uk: String): String = if (isUkrainian) uk else en

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

