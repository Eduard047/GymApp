package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.WorkoutSessionSummary
import com.example.gymapp.data.repository.WorkoutDataLimits
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlin.math.abs
import kotlin.math.roundToInt

internal data class AdaptiveMissionBoard(
    val daily: List<AdaptiveMission>,
    val weekly: List<AdaptiveMission>,
    val monthly: List<AdaptiveMission>
)

internal data class AdaptiveMission(
    val id: String,
    val cadence: MissionCadence,
    val family: String,
    val titleEn: String,
    val titleUk: String,
    val summaryEn: String,
    val summaryUk: String,
    val goal: Int,
    val unitEn: String,
    val unitUk: String,
    val unitRu: String,
    val progress: Int
) {
    val completed: Boolean
        get() = progress >= goal
}

internal enum class MissionCadence {
    Daily,
    Weekly,
    Monthly
}

internal object AdaptiveMissionBoardSource {
    fun build(
        sessions: List<WorkoutSessionSummary>,
        anchorDate: LocalDate,
        zoneId: ZoneId
    ): AdaptiveMissionBoard {
        val boundedSessions = sessions.asSequence()
            .mapNotNull { session ->
                val sessionDate = session.session.date.toMissionLocalDate(zoneId)
                if (sessionDate.isAfter(anchorDate)) {
                    return@mapNotNull null
                }
                session.copy(
                    exerciseCount = session.exerciseCount.coerceIn(
                        minimumValue = 0,
                        maximumValue = WorkoutDataLimits.MAX_EXERCISES_PER_SESSION
                    ),
                    setCount = session.setCount.coerceIn(
                        minimumValue = 0,
                        maximumValue = MAX_MISSION_SETS_PER_SESSION
                    ),
                    totalVolume = session.totalVolume
                        .takeIf { it.isFinite() && it > 0.0 }
                        ?.coerceAtMost(MAX_MISSION_VOLUME)
                        ?: 0.0
                )
            }
            .sortedWith(
                compareByDescending<WorkoutSessionSummary> { it.session.date }
                    .thenByDescending { it.session.id }
            )
            .take(WorkoutDataLimits.MAX_SESSIONS)
            .toList()
        val history = buildMissionHistoryStats(
            allSessions = boundedSessions,
            anchorDate = anchorDate,
            zoneId = zoneId
        )
        val dailyStats = buildDailyMissionStats(boundedSessions, anchorDate, zoneId)
        val weeklyStats = buildWeeklyMissionStats(boundedSessions, anchorDate, zoneId)
        val monthlyStats = buildMonthlyMissionStats(boundedSessions, anchorDate, zoneId)
        val dailySeed = anchorDate.toEpochDay()
        val weekSeed = anchorDate
            .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
            .toEpochDay()
        val monthSeed = YearMonth.from(anchorDate).atDay(1).toEpochDay()

        val daily = selectMissionTemplates(
            templates = dailyMissionCatalog(),
            count = ACTIVE_DAILY_MISSIONS,
            seed = dailySeed,
            requiredFamilies = linkedSetOf("workouts", "sets", "exercises"),
            scoreSelector = { template ->
                missionSelectionScore(
                    goal = template.goal,
                    target = missionTargetForFamily(MissionCadence.Daily, template.family, history),
                    seed = dailySeed
                )
            }
        ).map { template ->
            template.toAdaptiveMission(
                cadence = MissionCadence.Daily,
                progress = template.progressSelector(dailyStats)
            )
        }
        val weekly = selectMissionTemplates(
            templates = weeklyMissionCatalog(),
            count = ACTIVE_WEEKLY_MISSIONS,
            seed = weekSeed,
            requiredFamilies = linkedSetOf("workouts", "active-days", "sets"),
            scoreSelector = { template ->
                missionSelectionScore(
                    goal = template.goal,
                    target = missionTargetForFamily(MissionCadence.Weekly, template.family, history),
                    seed = weekSeed
                )
            }
        ).map { template ->
            template.toAdaptiveMission(
                cadence = MissionCadence.Weekly,
                progress = template.progressSelector(weeklyStats)
            )
        }
        val monthly = selectMissionTemplates(
            templates = monthlyMissionCatalog(),
            count = ACTIVE_MONTHLY_MISSIONS,
            seed = monthSeed,
            requiredFamilies = linkedSetOf("workouts", "sets"),
            scoreSelector = { template ->
                missionSelectionScore(
                    goal = template.goal,
                    target = missionTargetForFamily(MissionCadence.Monthly, template.family, history),
                    seed = monthSeed
                )
            }
        ).map { template ->
            template.toAdaptiveMission(
                cadence = MissionCadence.Monthly,
                progress = template.progressSelector(monthlyStats)
            )
        }

        return AdaptiveMissionBoard(daily = daily, weekly = weekly, monthly = monthly)
    }

    fun newlyCompleted(
        before: AdaptiveMissionBoard,
        after: AdaptiveMissionBoard
    ): List<AdaptiveMission> {
        return newlyCompleted(before.daily, after.daily) +
            newlyCompleted(before.weekly, after.weekly) +
            newlyCompleted(before.monthly, after.monthly)
    }

    internal fun allCatalogMissions(): List<AdaptiveMission> =
        dailyMissionCatalog().map { it.toAdaptiveMission(MissionCadence.Daily, progress = 0) } +
            weeklyMissionCatalog().map { it.toAdaptiveMission(MissionCadence.Weekly, progress = 0) } +
            monthlyMissionCatalog().map { it.toAdaptiveMission(MissionCadence.Monthly, progress = 0) }

    private fun newlyCompleted(
        before: List<AdaptiveMission>,
        after: List<AdaptiveMission>
    ): List<AdaptiveMission> {
        val beforeById = before.associateBy { it.id }
        return after.filter { mission ->
            val previous = beforeById[mission.id]
            previous != null &&
                previous.goal == mission.goal &&
                !previous.completed &&
                mission.completed
        }
    }
}

private fun <T : BaseMissionTemplate> T.toAdaptiveMission(
    cadence: MissionCadence,
    progress: Int
): AdaptiveMission = AdaptiveMission(
    id = id,
    cadence = cadence,
    family = family,
    titleEn = titleEn,
    titleUk = titleUk,
    summaryEn = summaryEn,
    summaryUk = summaryUk,
    goal = goal,
    unitEn = missionUnitEn(unitEn, goal),
    unitUk = missionUnitUk(unitUk, goal),
    unitRu = missionUnitRu(unitEn, goal),
    progress = progress.coerceAtLeast(0)
)

private fun dailyMissionCatalog(): List<DailyMissionTemplate> = buildList {
    addAll(
        createDailyTemplates(
            family = "workouts",
            goals = listOf(1),
            idForGoal = { "daily-check-in" },
            unitEn = "workout",
            unitUk = "тренування",
            titleEn = { "Show up" },
            titleUk = { "Прийди на тренування" },
            summaryEn = { "Complete one workout today." },
            summaryUk = { "Заверши одне тренування сьогодні." },
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
            titleEn = { "Balanced session" },
            titleUk = { "Збалансована сесія" },
            summaryEn = { "Train a realistic number of exercises today." },
            summaryUk = { "Виконай реалістичну кількість вправ сьогодні." },
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
            titleEn = { "Quality sets" },
            titleUk = { "Якісні підходи" },
            summaryEn = { "Complete a sustainable number of working sets today." },
            summaryUk = { "Виконай реалістичну кількість робочих підходів сьогодні." },
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
            titleUk = { goal -> "Вправ у сесії: $goal" },
            summaryEn = { goal -> "Fit $goal exercises into one session today." },
            summaryUk = { goal -> "Збери ${ukCount(goal, "вправу", "вправи", "вправ")} в одній сесії сьогодні." },
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
            titleUk = { goal -> "Підходів у сесії: $goal" },
            summaryEn = { goal -> "Build one session to $goal sets today." },
            summaryUk = { goal -> "Збери одну сесію до ${ukCount(goal, "підходу", "підходів", "підходів")} сьогодні." },
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
            titleEn = { "Weekly rhythm" },
            titleUk = { "Ритм тижня" },
            summaryEn = { "Match a sustainable recent workout rhythm this week." },
            summaryUk = { "Підтримай цього тижня сталий ритм недавніх тренувань." },
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
            titleEn = { "Active days" },
            titleUk = { "Активні дні" },
            summaryEn = { "Train on a realistic number of separate days this week." },
            summaryUk = { "Тренуйся реалістичну кількість окремих днів цього тижня." },
            progressSelector = { it.activeDays }
        )
    )
    addAll(
        createWeeklyTemplates(
            family = "sets",
            goals = intSeries(16, 4, 10),
            idForGoal = { goal -> "weekly-sets-$goal" },
            unitEn = "sets",
            unitUk = "підходів",
            titleEn = { "Steady sets" },
            titleUk = { "Сталі підходи" },
            summaryEn = { "Build a typical recent week's number of working sets." },
            summaryUk = { "Виконай типову для недавнього тижня кількість робочих підходів." },
            progressSelector = { it.setCount }
        )
    )
    addAll(
        createWeeklyTemplates(
            family = "volume",
            goals = scaledSeries(
                base = 6_000,
                factors = listOf(0.75, 0.9, 1.0, 1.15, 1.3, 1.5, 1.7, 1.9, 2.2, 2.5, 2.8, 3.2)
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
            goals = intSeries(8, 2, 12),
            idForGoal = { goal -> "weekly-exercises-$goal" },
            unitEn = "exercises",
            unitUk = "вправ",
            titleEn = { goal -> "$goal exercises this week" },
            titleUk = { goal -> "Вправ за тиждень: $goal" },
            summaryEn = { goal -> "Log $goal exercise entries this week." },
            summaryUk = { goal -> "Занеси ${ukCount(goal, "вправу", "вправи", "вправ")} цього тижня." },
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
            titleEn = { goal -> "High-output days: $goal" },
            titleUk = { goal -> "Потужних днів: $goal" },
            summaryEn = { goal -> "Hit 10 sets on ${enCount(goal, "day", "different days")} this week." },
            summaryUk = { goal -> "Зроби 10 підходів у ${ukCount(goal, "день", "дні", "днів")} цього тижня." },
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
            titleEn = { goal -> "Volume days: $goal" },
            titleUk = { goal -> "Днів обсягу: $goal" },
            summaryEn = { goal -> "Reach 1,000 volume on ${enCount(goal, "day", "days")} this week." },
            summaryUk = { goal -> "Набери 1 000 обсягу у ${ukCount(goal, "день", "дні", "днів")} цього тижня." },
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
            titleEn = { goal -> "Strong sessions: $goal" },
            titleUk = { goal -> "Сильних сесій: $goal" },
            summaryEn = { goal -> "Finish ${enCount(goal, "session", "sessions")} with eight or more sets this week." },
            summaryUk = { goal -> "Заверши ${ukCount(goal, "сесію", "сесії", "сесій")} з вісьмома або більше підходами цього тижня." },
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
            titleEn = { goal -> "Wide sessions: $goal" },
            titleUk = { goal -> "Широких сесій: $goal" },
            summaryEn = { goal -> "Finish ${enCount(goal, "session", "sessions")} with three or more exercises this week." },
            summaryUk = { goal -> "Заверши ${ukCount(goal, "сесію", "сесії", "сесій")} з трьома або більше вправами цього тижня." },
            progressSelector = { it.sessionsWithThreePlusExercises }
        )
    )
}

private fun monthlyMissionCatalog(): List<MonthlyMissionTemplate> = buildList {
    addAll(
        createMonthlyTemplates(
            family = "workouts",
            goals = intSeries(6, 1, 9),
            idForGoal = { goal -> "monthly-workouts-$goal" },
            unitEn = "workouts",
            unitUk = "тренування",
            titleEn = { "Monthly base" },
            titleUk = { "Основа місяця" },
            summaryEn = { "Build on a sustainable recent month of workouts." },
            summaryUk = { "Спирайся на сталий ритм тренувань недавнього місяця." },
            progressSelector = { it.workoutCount }
        )
    )
    addAll(
        createMonthlyTemplates(
            family = "active-days",
            goals = intSeries(6, 1, 9),
            idForGoal = { goal -> "monthly-active-days-$goal" },
            unitEn = "days",
            unitUk = "днів",
            titleEn = { goal -> "$goal active days" },
            titleUk = { goal -> "Активних днів за місяць: $goal" },
            summaryEn = { goal -> "Train on $goal separate days this month." },
            summaryUk = { goal -> "Потренуйся ${ukCount(goal, "день", "дні", "днів")} цього місяця." },
            progressSelector = { it.activeDays }
        )
    )
    addAll(
        createMonthlyTemplates(
            family = "sets",
            goals = intSeries(48, 8, 14),
            idForGoal = { goal -> "monthly-sets-$goal" },
            unitEn = "sets",
            unitUk = "підходів",
            titleEn = { "Sustainable sets" },
            titleUk = { "Сталий обсяг підходів" },
            summaryEn = { "Accumulate a realistic number of working sets this month." },
            summaryUk = { "Набери реалістичну кількість робочих підходів цього місяця." },
            progressSelector = { it.setCount }
        )
    )
    addAll(
        createMonthlyTemplates(
            family = "volume",
            goals = scaledSeries(
                base = 24_000,
                factors = listOf(0.75, 0.9, 1.0, 1.15, 1.3, 1.5, 1.7, 1.9, 2.2, 2.5, 2.8, 3.2)
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
            goals = intSeries(24, 4, 16),
            idForGoal = { goal -> "monthly-exercises-$goal" },
            unitEn = "exercises",
            unitUk = "вправ",
            titleEn = { goal -> "$goal exercises this month" },
            titleUk = { goal -> "Вправ за місяць: $goal" },
            summaryEn = { goal -> "Log $goal exercise entries this month." },
            summaryUk = { goal -> "Занеси ${ukCount(goal, "вправу", "вправи", "вправ")} цього місяця." },
            progressSelector = { it.exerciseCount }
        )
    )
    addAll(
        createMonthlyTemplates(
            family = "days-10-sets",
            goals = intSeries(2, 1, 11),
            idForGoal = { goal -> "monthly-days-10-sets-$goal" },
            unitEn = "days",
            unitUk = "днів",
            titleEn = { goal -> "High-output days: $goal" },
            titleUk = { goal -> "Потужних днів: $goal" },
            summaryEn = { goal -> "Hit 10 sets on ${enCount(goal, "day", "days")} this month." },
            summaryUk = { goal -> "Зроби 10 підходів у ${ukCount(goal, "день", "дні", "днів")} цього місяця." },
            progressSelector = { it.daysWithTenPlusSets }
        )
    )
    addAll(
        createMonthlyTemplates(
            family = "days-1000-volume",
            goals = intSeries(2, 1, 11),
            idForGoal = { goal -> "monthly-days-1000-volume-$goal" },
            unitEn = "days",
            unitUk = "днів",
            titleEn = { goal -> "Volume days: $goal" },
            titleUk = { goal -> "Днів обсягу: $goal" },
            summaryEn = { goal -> "Reach 1,000 volume on ${enCount(goal, "day", "days")} this month." },
            summaryUk = { goal -> "Набери 1 000 обсягу у ${ukCount(goal, "день", "дні", "днів")} цього місяця." },
            progressSelector = { it.daysWithThousandVolume }
        )
    )
    addAll(
        createMonthlyTemplates(
            family = "sessions-8-sets",
            goals = intSeries(2, 1, 12),
            idForGoal = { goal -> "monthly-sessions-8-sets-$goal" },
            unitEn = "sessions",
            unitUk = "сесій",
            titleEn = { goal -> "Strong sessions: $goal" },
            titleUk = { goal -> "Сильних сесій: $goal" },
            summaryEn = { goal -> "Finish ${enCount(goal, "session", "sessions")} with eight or more sets this month." },
            summaryUk = { goal -> "Заверши ${ukCount(goal, "сесію", "сесії", "сесій")} з вісьмома або більше підходами цього місяця." },
            progressSelector = { it.sessionsWithEightPlusSets }
        )
    )
    addAll(
        createMonthlyTemplates(
            family = "sessions-3-exercises",
            goals = intSeries(2, 1, 12),
            idForGoal = { goal -> "monthly-sessions-3-exercises-$goal" },
            unitEn = "sessions",
            unitUk = "сесій",
            titleEn = { goal -> "Wide sessions: $goal" },
            titleUk = { goal -> "Широких сесій: $goal" },
            summaryEn = { goal -> "Finish ${enCount(goal, "session", "sessions")} with three or more exercises this month." },
            summaryUk = { goal -> "Заверши ${ukCount(goal, "сесію", "сесії", "сесій")} з трьома або більше вправами цього місяця." },
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
            titleUk = { goal -> "Підходів у кращій сесії: $goal" },
            summaryEn = { goal -> "Build one session to $goal sets this month." },
            summaryUk = { goal -> "Збери одну сесію до ${ukCount(goal, "підходу", "підходів", "підходів")} цього місяця." },
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
            titleUk = { goal -> "Вправ у кращій сесії: $goal" },
            summaryEn = { goal -> "Fit $goal exercises into one session this month." },
            summaryUk = { goal -> "Збери ${ukCount(goal, "вправу", "вправи", "вправ")} в одній сесії цього місяця." },
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

private fun enCount(count: Int, singular: String, plural: String): String =
    "$count ${if (count == 1) singular else plural}"

private fun ukCount(count: Int, one: String, few: String, many: String): String {
    val normalized = kotlin.math.abs(count.toLong())
    val lastTwo = normalized % 100L
    val form = when {
        lastTwo in 11L..14L -> many
        normalized % 10L == 1L -> one
        normalized % 10L in 2L..4L -> few
        else -> many
    }
    return "$count $form"
}

private fun missionUnitEn(unit: String, goal: Int): String = when (unit) {
    "workouts" -> if (goal == 1) "workout" else unit
    "days" -> if (goal == 1) "day" else unit
    "sets" -> if (goal == 1) "set" else unit
    "exercises" -> if (goal == 1) "exercise" else unit
    "sessions" -> if (goal == 1) "session" else unit
    else -> unit
}

private fun missionUnitUk(unit: String, goal: Int): String = when (unit) {
    "тренування" -> ukCount(goal, "тренування", "тренування", "тренувань").substringAfter(' ')
    "днів" -> ukCount(goal, "день", "дні", "днів").substringAfter(' ')
    "підходів" -> ukCount(goal, "підхід", "підходи", "підходів").substringAfter(' ')
    "вправ" -> ukCount(goal, "вправа", "вправи", "вправ").substringAfter(' ')
    "сесій" -> ukCount(goal, "сесія", "сесії", "сесій").substringAfter(' ')
    else -> unit
}

private fun missionUnitRu(unit: String, goal: Int): String = when (unit) {
    "workout", "workouts" -> ruCountForm(goal, "тренировка", "тренировки", "тренировок")
    "day", "days" -> ruCountForm(goal, "день", "дня", "дней")
    "set", "sets" -> ruCountForm(goal, "подход", "подхода", "подходов")
    "exercise", "exercises" -> ruCountForm(goal, "упражнение", "упражнения", "упражнений")
    "session", "sessions" -> ruCountForm(goal, "сессия", "сессии", "сессий")
    "volume" -> "объёма"
    else -> unit
}

private fun ruCountForm(count: Int, one: String, few: String, many: String): String {
    val normalized = kotlin.math.abs(count.toLong())
    val lastTwo = normalized % 100L
    return when {
        lastTwo in 11L..14L -> many
        normalized % 10L == 1L -> one
        normalized % 10L in 2L..4L -> few
        else -> many
    }
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

private fun buildDailyMissionStats(
    allSessions: List<WorkoutSessionSummary>,
    anchorDate: LocalDate,
    zoneId: ZoneId
): DailyMissionStats {
    val todaySessions = allSessions.filter {
        it.session.date.toMissionLocalDate(zoneId) == anchorDate
    }

    return DailyMissionStats(
        workoutCount = todaySessions.size,
        exerciseCount = todaySessions.saturatedExerciseCount(),
        setCount = todaySessions.saturatedSetCount(),
        totalVolume = todaySessions.saturatedVolumeTotal(),
        maxSessionVolume = todaySessions.maxOfOrNull { it.totalVolume }?.roundToInt() ?: 0,
        maxSessionExercises = todaySessions.maxOfOrNull { it.exerciseCount } ?: 0,
        maxSessionSets = todaySessions.maxOfOrNull { it.setCount } ?: 0
    )
}

private fun buildWeeklyMissionStats(
    allSessions: List<WorkoutSessionSummary>,
    anchorDate: LocalDate,
    zoneId: ZoneId
): WeeklyMissionStats {
    val weekStart = anchorDate.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    val weekSessions = allSessions.filter { session ->
        val sessionDate = session.session.date.toMissionLocalDate(zoneId)
        !sessionDate.isBefore(weekStart) && !sessionDate.isAfter(anchorDate)
    }
    val sessionsByDay = weekSessions.groupBy { it.session.date.toMissionLocalDate(zoneId) }
    val dayAggregates = sessionsByDay.mapValues { (_, sessions) ->
        sessions.fold(WeeklyDayAggregate()) { acc, session ->
            acc.copy(
                workoutCount = saturatedIntAdd(acc.workoutCount, 1),
                exerciseCount = saturatedIntAdd(acc.exerciseCount, session.exerciseCount),
                setCount = saturatedIntAdd(acc.setCount, session.setCount),
                totalVolume = saturatedVolumeAdd(acc.totalVolume, session.totalVolume)
            )
        }
    }

    return WeeklyMissionStats(
        workoutCount = weekSessions.size,
        activeDays = sessionsByDay.size,
        exerciseCount = weekSessions.saturatedExerciseCount(),
        setCount = weekSessions.saturatedSetCount(),
        totalVolume = weekSessions.saturatedVolumeTotal(),
        daysWithTenPlusSets = dayAggregates.values.count { it.setCount >= 10 },
        daysWithThousandVolume = dayAggregates.values.count { it.totalVolume >= 1_000.0 },
        sessionsWithEightPlusSets = weekSessions.count { it.setCount >= 8 },
        sessionsWithThreePlusExercises = weekSessions.count { it.exerciseCount >= 3 }
    )
}

private fun buildMonthlyMissionStats(
    allSessions: List<WorkoutSessionSummary>,
    anchorDate: LocalDate,
    zoneId: ZoneId
): MonthlyMissionStats {
    val currentMonth = YearMonth.from(anchorDate)
    val monthStart = currentMonth.atDay(1)
    val monthSessions = allSessions.filter { session ->
        val sessionDate = session.session.date.toMissionLocalDate(zoneId)
        !sessionDate.isBefore(monthStart) && !sessionDate.isAfter(anchorDate)
    }
    val sessionsByDay = monthSessions.groupBy { it.session.date.toMissionLocalDate(zoneId) }
    val dayAggregates = sessionsByDay.mapValues { (_, sessions) ->
        sessions.fold(WeeklyDayAggregate()) { acc, session ->
            acc.copy(
                workoutCount = saturatedIntAdd(acc.workoutCount, 1),
                exerciseCount = saturatedIntAdd(acc.exerciseCount, session.exerciseCount),
                setCount = saturatedIntAdd(acc.setCount, session.setCount),
                totalVolume = saturatedVolumeAdd(acc.totalVolume, session.totalVolume)
            )
        }
    }

    return MonthlyMissionStats(
        workoutCount = monthSessions.size,
        activeDays = sessionsByDay.size,
        exerciseCount = monthSessions.saturatedExerciseCount(),
        setCount = monthSessions.saturatedSetCount(),
        totalVolume = monthSessions.saturatedVolumeTotal(),
        daysWithTenPlusSets = dayAggregates.values.count { it.setCount >= 10 },
        daysWithThousandVolume = dayAggregates.values.count { it.totalVolume >= 1_000.0 },
        sessionsWithEightPlusSets = monthSessions.count { it.setCount >= 8 },
        sessionsWithThreePlusExercises = monthSessions.count { it.exerciseCount >= 3 },
        maxSessionVolume = monthSessions.maxOfOrNull { it.totalVolume }?.roundToInt() ?: 0,
        maxSessionSets = monthSessions.maxOfOrNull { it.setCount } ?: 0,
        maxSessionExercises = monthSessions.maxOfOrNull { it.exerciseCount } ?: 0
    )
}

private fun buildMissionHistoryStats(
    allSessions: List<WorkoutSessionSummary>,
    anchorDate: LocalDate,
    zoneId: ZoneId
): MissionHistoryStats {
    if (allSessions.isEmpty()) {
        return MissionHistoryStats()
    }

    val dayAggregates = allSessions
        .groupBy { it.session.date.toMissionLocalDate(zoneId) }
        .mapValues { (_, sessions) ->
            sessions.fold(WeeklyDayAggregate()) { acc, session ->
                acc.copy(
                    workoutCount = saturatedIntAdd(acc.workoutCount, 1),
                    exerciseCount = saturatedIntAdd(acc.exerciseCount, session.exerciseCount),
                    setCount = saturatedIntAdd(acc.setCount, session.setCount),
                    totalVolume = saturatedVolumeAdd(acc.totalVolume, session.totalVolume)
                )
            }
        }

    val weekAggregates = allSessions
        .groupBy {
            it.session.date
                .toMissionLocalDate(zoneId)
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        }
        .mapValues { (_, sessions) ->
            val weeklyDays = sessions
                .groupBy { it.session.date.toMissionLocalDate(zoneId) }
                .mapValues { (_, daySessions) ->
                    daySessions.fold(WeeklyDayAggregate()) { acc, session ->
                        acc.copy(
                            workoutCount = saturatedIntAdd(acc.workoutCount, 1),
                            exerciseCount = saturatedIntAdd(acc.exerciseCount, session.exerciseCount),
                            setCount = saturatedIntAdd(acc.setCount, session.setCount),
                            totalVolume = saturatedVolumeAdd(acc.totalVolume, session.totalVolume)
                        )
                    }
                }

            PeriodAggregate(
                workoutCount = sessions.size,
                activeDays = weeklyDays.size,
                exerciseCount = sessions.saturatedExerciseCount(),
                setCount = sessions.saturatedSetCount(),
                totalVolume = sessions.saturatedVolumeTotal(),
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
        .groupBy { YearMonth.from(it.session.date.toMissionLocalDate(zoneId)) }
        .mapValues { (_, sessions) ->
            val monthlyDays = sessions
                .groupBy { it.session.date.toMissionLocalDate(zoneId) }
                .mapValues { (_, daySessions) ->
                    daySessions.fold(WeeklyDayAggregate()) { acc, session ->
                        acc.copy(
                            workoutCount = saturatedIntAdd(acc.workoutCount, 1),
                            exerciseCount = saturatedIntAdd(acc.exerciseCount, session.exerciseCount),
                            setCount = saturatedIntAdd(acc.setCount, session.setCount),
                            totalVolume = saturatedVolumeAdd(acc.totalVolume, session.totalVolume)
                        )
                    }
                }

            PeriodAggregate(
                workoutCount = sessions.size,
                activeDays = monthlyDays.size,
                exerciseCount = sessions.saturatedExerciseCount(),
                setCount = sessions.saturatedSetCount(),
                totalVolume = sessions.saturatedVolumeTotal(),
                daysWithTenPlusSets = monthlyDays.values.count { it.setCount >= 10 },
                daysWithThousandVolume = monthlyDays.values.count { it.totalVolume >= 1_000.0 },
                sessionsWithEightPlusSets = sessions.count { it.setCount >= 8 },
                sessionsWithThreePlusExercises = sessions.count { it.exerciseCount >= 3 },
                maxSessionVolume = sessions.maxOfOrNull { it.totalVolume }?.roundToInt() ?: 0,
                maxSessionSets = sessions.maxOfOrNull { it.setCount } ?: 0,
                maxSessionExercises = sessions.maxOfOrNull { it.exerciseCount } ?: 0
            )
        }

    val windows = missionCalendarWindows(anchorDate)
    val recentDays = dayAggregates.entries
        .filter { (day, _) -> windows.containsRecentDay(day) }
        .sortedByDescending { it.key }
        .map { it.value }
    val recentWeeks = weekAggregates.entries
        .filter { (weekStart, _) -> windows.containsCompletedWeek(weekStart) }
        .sortedByDescending { it.key }
        .map { it.value }
    val recentMonths = monthAggregates.entries
        .filter { (month, _) -> windows.containsCompletedMonth(month) }
        .sortedByDescending { it.key }
        .map { it.value }
    val recentSessions = allSessions
        .filter { session ->
            windows.containsRecentSession(session.session.date.toMissionLocalDate(zoneId))
        }
        .sortedByDescending { it.session.date }
        .take(12)

    return MissionHistoryStats(
        typicalDayWorkouts = realisticMissionBaseline(recentDays.map { it.workoutCount }, fallback = 1),
        typicalDayExercises = realisticMissionBaseline(recentDays.map { it.exerciseCount }, fallback = 3),
        typicalDaySets = realisticMissionBaseline(recentDays.map { it.setCount }, fallback = 8),
        typicalDayVolume = realisticMissionBaseline(
            recentDays.map { it.totalVolume.roundToInt() },
            fallback = 1_800
        ),
        typicalWeekWorkouts = realisticMissionBaseline(recentWeeks.map { it.workoutCount }, fallback = 3),
        typicalWeekActiveDays = realisticMissionBaseline(recentWeeks.map { it.activeDays }, fallback = 2),
        typicalWeekExercises = realisticMissionBaseline(recentWeeks.map { it.exerciseCount }, fallback = 12),
        typicalWeekSets = realisticMissionBaseline(recentWeeks.map { it.setCount }, fallback = 24),
        typicalWeekVolume = realisticMissionBaseline(recentWeeks.map { it.totalVolume }, fallback = 7_500),
        typicalWeekDaysWithTenPlusSets = realisticMissionBaseline(
            recentWeeks.map { it.daysWithTenPlusSets },
            fallback = 1
        ),
        typicalWeekDaysWithThousandVolume = realisticMissionBaseline(
            recentWeeks.map { it.daysWithThousandVolume },
            fallback = 1
        ),
        typicalWeekSessionsWithEightPlusSets = realisticMissionBaseline(
            recentWeeks.map { it.sessionsWithEightPlusSets },
            fallback = 2
        ),
        typicalWeekSessionsWithThreePlusExercises = realisticMissionBaseline(
            recentWeeks.map { it.sessionsWithThreePlusExercises },
            fallback = 2
        ),
        typicalMonthWorkouts = realisticMissionBaseline(recentMonths.map { it.workoutCount }, fallback = 8),
        typicalMonthActiveDays = realisticMissionBaseline(recentMonths.map { it.activeDays }, fallback = 8),
        typicalMonthExercises = realisticMissionBaseline(recentMonths.map { it.exerciseCount }, fallback = 32),
        typicalMonthSets = realisticMissionBaseline(recentMonths.map { it.setCount }, fallback = 64),
        typicalMonthVolume = realisticMissionBaseline(recentMonths.map { it.totalVolume }, fallback = 24_000),
        typicalMonthDaysWithTenPlusSets = realisticMissionBaseline(
            recentMonths.map { it.daysWithTenPlusSets },
            fallback = 4
        ),
        typicalMonthDaysWithThousandVolume = realisticMissionBaseline(
            recentMonths.map { it.daysWithThousandVolume },
            fallback = 4
        ),
        typicalMonthSessionsWithEightPlusSets = realisticMissionBaseline(
            recentMonths.map { it.sessionsWithEightPlusSets },
            fallback = 4
        ),
        typicalMonthSessionsWithThreePlusExercises = realisticMissionBaseline(
            recentMonths.map { it.sessionsWithThreePlusExercises },
            fallback = 4
        ),
        typicalSessionVolume = realisticMissionBaseline(
            recentSessions.map { it.totalVolume.roundToInt() },
            fallback = 1_800
        ),
        typicalSessionExercises = realisticMissionBaseline(
            recentSessions.map { it.exerciseCount },
            fallback = 4
        ),
        typicalSessionSets = realisticMissionBaseline(recentSessions.map { it.setCount }, fallback = 10)
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
        selectedFamilies += missionSelectionMetric(template.family)
    }

    ranked.forEach { template ->
        if (selected.size >= targetCount) return@forEach
        val selectionMetric = missionSelectionMetric(template.family)
        if (selectionMetric !in selectedFamilies) {
            selected += template
            selectedIds += template.id
            selectedFamilies += selectionMetric
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
            "exercises" -> boundedTarget(history.typicalDayExercises, fallback = 3, min = 3, max = 10)
            "sets" -> boundedTarget(history.typicalDaySets, fallback = 8, min = 8, max = 22)
            "volume" -> boundedTarget(history.typicalDayVolume, fallback = 1_800, min = 1_200, max = 7_000)
            "max-session-volume" -> boundedTarget(history.typicalSessionVolume, fallback = 1_800, min = 1_000, max = 7_000)
            "max-session-exercises" -> boundedTarget(history.typicalSessionExercises, fallback = 4, min = 3, max = 9)
            "max-session-sets" -> boundedTarget(history.typicalSessionSets, fallback = 10, min = 8, max = 22)
            else -> 1
        }

        MissionCadence.Weekly -> when (family) {
            "workouts" -> boundedTarget(history.typicalWeekWorkouts, fallback = 3, min = 2, max = 3)
            "active-days" -> boundedTarget(history.typicalWeekActiveDays, fallback = 2, min = 2, max = 3)
            "exercises" -> boundedTarget(history.typicalWeekExercises, fallback = 12, min = 8, max = 30)
            "sets" -> boundedTarget(history.typicalWeekSets, fallback = 24, min = 16, max = 48)
            "volume" -> boundedTarget(history.typicalWeekVolume, fallback = 7_500, min = 4_500, max = 20_000)
            "days-10-sets" -> boundedTarget(history.typicalWeekDaysWithTenPlusSets, fallback = 1, min = 1, max = 3)
            "days-1000-volume" -> boundedTarget(history.typicalWeekDaysWithThousandVolume, fallback = 1, min = 1, max = 3)
            "sessions-8-sets" -> boundedTarget(history.typicalWeekSessionsWithEightPlusSets, fallback = 2, min = 1, max = 3)
            "sessions-3-exercises" -> boundedTarget(history.typicalWeekSessionsWithThreePlusExercises, fallback = 2, min = 1, max = 3)
            else -> 1
        }

        MissionCadence.Monthly -> when (family) {
            "workouts" -> boundedTarget(history.typicalMonthWorkouts, fallback = 8, min = 6, max = 14)
            "active-days" -> boundedTarget(history.typicalMonthActiveDays, fallback = 8, min = 6, max = 14)
            "exercises" -> boundedTarget(history.typicalMonthExercises, fallback = 32, min = 24, max = 96)
            "sets" -> boundedTarget(history.typicalMonthSets, fallback = 64, min = 48, max = 160)
            "volume" -> boundedTarget(history.typicalMonthVolume, fallback = 24_000, min = 18_000, max = 70_000)
            "days-10-sets" -> boundedTarget(history.typicalMonthDaysWithTenPlusSets, fallback = 4, min = 2, max = 12)
            "days-1000-volume" -> boundedTarget(history.typicalMonthDaysWithThousandVolume, fallback = 4, min = 2, max = 12)
            "sessions-8-sets" -> boundedTarget(history.typicalMonthSessionsWithEightPlusSets, fallback = 4, min = 2, max = 12)
            "sessions-3-exercises" -> boundedTarget(history.typicalMonthSessionsWithThreePlusExercises, fallback = 4, min = 2, max = 12)
            "max-session-volume" -> boundedTarget(history.typicalSessionVolume, fallback = 2_000, min = 1_000, max = 7_000)
            "max-session-sets" -> boundedTarget(history.typicalSessionSets, fallback = 10, min = 8, max = 26)
            "max-session-exercises" -> boundedTarget(history.typicalSessionExercises, fallback = 4, min = 3, max = 10)
            else -> 1
        }
    }
}

private fun boundedTarget(observed: Int, fallback: Int, min: Int, max: Int): Int {
    val baseline = if (observed > 0) observed else fallback
    return baseline.coerceIn(min, max)
}

private fun Long.toMissionLocalDate(zoneId: ZoneId): LocalDate =
    Instant.ofEpochMilli(this).atZone(zoneId).toLocalDate()

private fun List<WorkoutSessionSummary>.saturatedExerciseCount(): Int =
    fold(0) { total, session -> saturatedIntAdd(total, session.exerciseCount) }

private fun List<WorkoutSessionSummary>.saturatedSetCount(): Int =
    fold(0) { total, session -> saturatedIntAdd(total, session.setCount) }

private fun List<WorkoutSessionSummary>.saturatedVolumeTotal(): Int {
    val total = fold(0.0) { accumulated, session ->
        saturatedVolumeAdd(accumulated, session.totalVolume)
    }
    return total.roundToInt()
}

private fun saturatedIntAdd(left: Int, right: Int): Int =
    (left.toLong() + right.toLong())
        .coerceIn(0L, Int.MAX_VALUE.toLong())
        .toInt()

private fun saturatedVolumeAdd(left: Double, right: Double): Double =
    (left + right).coerceIn(0.0, MAX_MISSION_VOLUME)

private const val ACTIVE_DAILY_MISSIONS = 3
private const val ACTIVE_WEEKLY_MISSIONS = 3
private const val ACTIVE_MONTHLY_MISSIONS = 2
private const val MAX_MISSION_SETS_PER_SESSION =
    WorkoutDataLimits.MAX_EXERCISES_PER_SESSION * WorkoutDataLimits.MAX_SETS_PER_EXERCISE
private const val MAX_MISSION_VOLUME = 2_147_483_647.0

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
    val typicalDayWorkouts: Int = 0,
    val typicalDayExercises: Int = 0,
    val typicalDaySets: Int = 0,
    val typicalDayVolume: Int = 0,
    val typicalWeekWorkouts: Int = 0,
    val typicalWeekActiveDays: Int = 0,
    val typicalWeekExercises: Int = 0,
    val typicalWeekSets: Int = 0,
    val typicalWeekVolume: Int = 0,
    val typicalWeekDaysWithTenPlusSets: Int = 0,
    val typicalWeekDaysWithThousandVolume: Int = 0,
    val typicalWeekSessionsWithEightPlusSets: Int = 0,
    val typicalWeekSessionsWithThreePlusExercises: Int = 0,
    val typicalMonthWorkouts: Int = 0,
    val typicalMonthActiveDays: Int = 0,
    val typicalMonthExercises: Int = 0,
    val typicalMonthSets: Int = 0,
    val typicalMonthVolume: Int = 0,
    val typicalMonthDaysWithTenPlusSets: Int = 0,
    val typicalMonthDaysWithThousandVolume: Int = 0,
    val typicalMonthSessionsWithEightPlusSets: Int = 0,
    val typicalMonthSessionsWithThreePlusExercises: Int = 0,
    val typicalSessionVolume: Int = 0,
    val typicalSessionExercises: Int = 0,
    val typicalSessionSets: Int = 0
)
