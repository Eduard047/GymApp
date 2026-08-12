package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.WorkoutSessionSummary
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import kotlin.math.max
import kotlin.math.roundToInt

object GamificationEngine {
    internal const val MAX_SESSION_XP = 5_000
    private const val DAILY_HEATMAP_DAYS = 365
    private const val TREND_WINDOW_DAYS = 30

    fun buildSnapshot(
        sessions: List<WorkoutSessionSummary>,
        nowMillis: Long,
        zoneId: ZoneId = ZoneId.systemDefault(),
        targetWorkoutsPerWeek: Int = 4
    ): GamificationSnapshot {
        require(targetWorkoutsPerWeek in 2..6) {
            "Weekly training target is outside the supported bounds."
        }
        val sortedSessions = sessions.sortedBy { it.session.date }
        val today = Instant.ofEpochMilli(nowMillis).atZone(zoneId).toLocalDate()
        val todayEpochDay = today.toEpochDay()
        val dayAggregates = buildDayAggregates(sortedSessions, zoneId)
        val workoutDays = dayAggregates.keys.sorted()
        val summary = buildSummary(sortedSessions, workoutDays)
        val streak = buildStreakSnapshot(workoutDays, todayEpochDay)
        val weeklyAdherence = buildWeeklyAdherence(
            workoutDays = sortedSessions
                .asSequence()
                .filter { it.session.date <= nowMillis }
                .map { epochDay(it.session.date, zoneId) }
                .distinct()
                .sorted()
                .toList(),
            targetWorkoutsPerWeek = targetWorkoutsPerWeek
        )
        val comeback = buildComebackSnapshot(workoutDays)
        val achievements = buildAchievements(
            sessions = sortedSessions,
            workoutDays = workoutDays,
            summary = summary,
            weeklyAdherence = weeklyAdherence,
            comeback = comeback,
            zoneId = zoneId
        )
        val baseXp = dayAggregates.values.fold(0) { total, aggregate ->
            saturatedXpAdd(total, aggregate.xp)
        }
        // Permanent progression is derived only from saved workout sessions.
        // Streaks, comeback status, missions, and achievements remain useful UI
        // signals, but recomputing them into total XP would make XP decrease or
        // change when a calendar period rolls over.
        val bonusXp = 0
        val totalXp = saturatedXpAdd(baseXp, bonusXp)
        val progression = buildProgression(baseXp, bonusXp, totalXp)
        return GamificationSnapshot(
            generatedAt = nowMillis,
            summary = summary,
            progression = progression,
            streak = streak,
            comeback = comeback,
            achievements = achievements,
            unlockedBadges = achievements.filter { it.unlocked }.map { it.badge },
            heatmap = buildHeatmap(dayAggregates, today),
            trendPoints = buildTrendPoints(dayAggregates, today)
        )
    }

    private data class DayAggregate(
        val workoutCount: Int = 0,
        val exerciseCount: Int = 0,
        val setCount: Int = 0,
        val volume: Double = 0.0,
        val xp: Int = 0
    )

    private data class WeeklyAdherenceSnapshot(
        val longestCompletedWeeks: Int,
        val completionDayByWeekStart: Map<Long, Long>
    ) {
        fun unlockDayFor(consecutiveWeeks: Int): Long? {
            require(consecutiveWeeks > 0)
            var previousWeekStart: Long? = null
            var run = 0
            completionDayByWeekStart.toSortedMap().forEach { (weekStart, completionDay) ->
                run = if (previousWeekStart?.plus(7L) == weekStart) run + 1 else 1
                if (run >= consecutiveWeeks) return completionDay
                previousWeekStart = weekStart
            }
            return null
        }
    }

    private fun buildDayAggregates(
        sessions: List<WorkoutSessionSummary>,
        zoneId: ZoneId
    ): Map<Long, DayAggregate> {
        val aggregates = linkedMapOf<Long, DayAggregate>()

        sessions.forEach { session ->
            val day = epochDay(session.session.date, zoneId)
            val current = aggregates[day] ?: DayAggregate()
            aggregates[day] = current.copy(
                workoutCount = current.workoutCount + 1,
                exerciseCount = current.exerciseCount + session.exerciseCount,
                setCount = current.setCount + session.setCount,
                volume = current.volume + session.totalVolume,
                xp = saturatedXpAdd(current.xp, xpForSession(session))
            )
        }

        return aggregates
    }

    private fun buildSummary(
        sessions: List<WorkoutSessionSummary>,
        workoutDays: List<Long>
    ): GamificationSummary {
        return GamificationSummary(
            workoutCount = sessions.size,
            workoutDayCount = workoutDays.size,
            setCount = sessions.sumOf { it.setCount },
            totalVolume = sessions.sumOf { it.totalVolume }
        )
    }

    private fun buildProgression(
        baseXp: Int,
        bonusXp: Int,
        totalXp: Int
    ): ProgressionSnapshot {
        val level = levelForXp(totalXp)
        val levelStartXp = xpForLevelStart(level)
        val nextLevelXp = xpForLevelStart(level + 1)
        val xpIntoLevel = totalXp - levelStartXp
        val xpToNextLevel = nextLevelXp - totalXp
        val progress = if (nextLevelXp == levelStartXp) 1.0 else xpIntoLevel.toDouble() / (nextLevelXp - levelStartXp).toDouble()

        return ProgressionSnapshot(
            level = level,
            totalXp = totalXp,
            baseXp = baseXp,
            bonusXp = bonusXp,
            xpIntoLevel = xpIntoLevel,
            xpToNextLevel = xpToNextLevel,
            levelProgress = progress.coerceIn(0.0, 1.0),
            title = titleForLevel(level),
            nextTitle = nextTitleAfter(level)
        )
    }

    private fun buildStreakSnapshot(
        workoutDays: List<Long>,
        todayEpochDay: Long
    ): StreakSnapshot {
        if (workoutDays.isEmpty()) {
            return StreakSnapshot(
                currentDays = 0,
                longestDays = 0,
                activeToday = false,
                lastWorkoutEpochDay = null,
                daysSinceLastWorkout = null
            )
        }

        val daySet = workoutDays.toHashSet()
        var currentCursor = if (daySet.contains(todayEpochDay)) todayEpochDay else todayEpochDay - 1
        var currentStreak = 0
        while (daySet.contains(currentCursor)) {
            currentStreak += 1
            currentCursor -= 1
        }

        var longestStreak = 0
        var run = 0
        var previousDay: Long? = null
        workoutDays.forEach { day ->
            run = if (previousDay == null || day != previousDay!! + 1) 1 else run + 1
            longestStreak = max(longestStreak, run)
            previousDay = day
        }

        val lastWorkoutDay = workoutDays.last()

        return StreakSnapshot(
            currentDays = currentStreak,
            longestDays = longestStreak,
            activeToday = daySet.contains(todayEpochDay),
            lastWorkoutEpochDay = lastWorkoutDay,
            daysSinceLastWorkout = (todayEpochDay - lastWorkoutDay).toInt()
        )
    }

    private fun buildComebackSnapshot(workoutDays: List<Long>): ComebackSnapshot {
        val gapDays = latestGapDays(workoutDays)
        val gap = gapDays ?: 0
        val eligible = gapDays != null && gapDays >= 3
        val multiplier = when {
            !eligible -> 1.0
            gap >= 30 -> 1.5
            gap >= 14 -> 1.35
            gap >= 7 -> 1.2
            else -> 1.1
        }
        val bonusXp = if (!eligible) 0 else (30 + gap * 6).coerceAtMost(120)

        return ComebackSnapshot(
            eligible = eligible,
            gapDays = gapDays,
            multiplier = multiplier,
            bonusXp = bonusXp
        )
    }

    private fun buildWeeklyAdherence(
        workoutDays: List<Long>,
        targetWorkoutsPerWeek: Int
    ): WeeklyAdherenceSnapshot {
        val completionDayByWeekStart = workoutDays
            .distinct()
            .groupBy(::mondayEpochDay)
            .mapNotNull { (weekStart, days) ->
                val sortedDays = days.sorted()
                sortedDays.getOrNull(targetWorkoutsPerWeek - 1)?.let { completionDay ->
                    weekStart to completionDay
                }
            }
            .toMap()

        var longest = 0
        var run = 0
        var previousWeekStart: Long? = null
        completionDayByWeekStart.keys.sorted().forEach { weekStart ->
            run = if (previousWeekStart?.plus(7L) == weekStart) run + 1 else 1
            longest = max(longest, run)
            previousWeekStart = weekStart
        }
        return WeeklyAdherenceSnapshot(
            longestCompletedWeeks = longest,
            completionDayByWeekStart = completionDayByWeekStart
        )
    }

    private fun buildAchievements(
        sessions: List<WorkoutSessionSummary>,
        workoutDays: List<Long>,
        summary: GamificationSummary,
        weeklyAdherence: WeeklyAdherenceSnapshot,
        comeback: ComebackSnapshot,
        zoneId: ZoneId
    ): List<AchievementSnapshot> {
        val maxHistoricalGapDays = maxGapDays(workoutDays)

        return listOf(
            countAchievement(
                id = "first_workout",
                title = "First Workout",
                description = "Complete your first workout.",
                target = 1.0,
                current = summary.workoutCount.toDouble(),
                rewardXp = 100,
                badgeName = "First Rep",
                rarity = BadgeRarity.COMMON,
                unlockDay = unlockDayByCount(sessions, 1, zoneId)
            ),
            countAchievement(
                id = "workout_5",
                title = "Starter Habit",
                description = "Complete five workouts.",
                target = 5.0,
                current = summary.workoutCount.toDouble(),
                rewardXp = 150,
                badgeName = "Starter Habit",
                rarity = BadgeRarity.COMMON,
                unlockDay = unlockDayByCount(sessions, 5, zoneId)
            ),
            countAchievement(
                id = "workout_10",
                title = "Consistency Builder",
                description = "Complete ten workouts.",
                target = 10.0,
                current = summary.workoutCount.toDouble(),
                rewardXp = 200,
                badgeName = "Consistency",
                rarity = BadgeRarity.UNCOMMON,
                unlockDay = unlockDayByCount(sessions, 10, zoneId)
            ),
            countAchievement(
                id = "workout_25",
                title = "Workhorse",
                description = "Complete twenty-five workouts.",
                target = 25.0,
                current = summary.workoutCount.toDouble(),
                rewardXp = 350,
                badgeName = "Workhorse",
                rarity = BadgeRarity.RARE,
                unlockDay = unlockDayByCount(sessions, 25, zoneId)
            ),
            countAchievement(
                id = "workout_50",
                title = "Veteran",
                description = "Complete fifty workouts.",
                target = 50.0,
                current = summary.workoutCount.toDouble(),
                rewardXp = 500,
                badgeName = "Veteran",
                rarity = BadgeRarity.EPIC,
                unlockDay = unlockDayByCount(sessions, 50, zoneId)
            ),
            countAchievement(
                id = "workout_100",
                title = "Centurion",
                description = "Complete one hundred workouts.",
                target = 100.0,
                current = summary.workoutCount.toDouble(),
                rewardXp = 900,
                badgeName = "Centurion",
                rarity = BadgeRarity.LEGENDARY,
                unlockDay = unlockDayByCount(sessions, 100, zoneId)
            ),
            streakAchievement(
                id = "streak_7",
                title = "Two-Week Rhythm",
                description = "Meet your weekly target for two weeks in a row.",
                target = 2.0,
                current = weeklyAdherence.longestCompletedWeeks.toDouble(),
                rewardXp = 150,
                badgeName = "Momentum",
                rarity = BadgeRarity.COMMON,
                unlockDay = weeklyAdherence.unlockDayFor(2)
            ),
            streakAchievement(
                id = "streak_14",
                title = "Four-Week Rhythm",
                description = "Meet your weekly target for four weeks in a row.",
                target = 4.0,
                current = weeklyAdherence.longestCompletedWeeks.toDouble(),
                rewardXp = 250,
                badgeName = "Flow State",
                rarity = BadgeRarity.UNCOMMON,
                unlockDay = weeklyAdherence.unlockDayFor(4)
            ),
            streakAchievement(
                id = "streak_30",
                title = "Eight-Week Rhythm",
                description = "Meet your weekly target for eight weeks in a row.",
                target = 8.0,
                current = weeklyAdherence.longestCompletedWeeks.toDouble(),
                rewardXp = 500,
                badgeName = "Unbroken",
                rarity = BadgeRarity.EPIC,
                unlockDay = weeklyAdherence.unlockDayFor(8)
            ),
            volumeAchievement(
                id = "volume_10k",
                title = "Ten Thousand Volume",
                description = "Accumulate ten thousand total volume.",
                target = 10_000.0,
                current = summary.totalVolume,
                rewardXp = 200,
                badgeName = "Volume Maker",
                rarity = BadgeRarity.UNCOMMON,
                unlockDay = unlockDayByVolume(sessions, 10_000.0, zoneId)
            ),
            volumeAchievement(
                id = "volume_50k",
                title = "Fifty Thousand Volume",
                description = "Accumulate fifty thousand total volume.",
                target = 50_000.0,
                current = summary.totalVolume,
                rewardXp = 500,
                badgeName = "Mountain Mover",
                rarity = BadgeRarity.RARE,
                unlockDay = unlockDayByVolume(sessions, 50_000.0, zoneId)
            ),
            comebackAchievement(
                currentGapDays = maxHistoricalGapDays,
                unlockedAtEpochDay = unlockDayByComeback(workoutDays, 7)
            )
        )
    }

    private fun countAchievement(
        id: String,
        title: String,
        description: String,
        target: Double,
        current: Double,
        rewardXp: Int,
        badgeName: String,
        rarity: BadgeRarity,
        unlockDay: Long?
    ): AchievementSnapshot {
        return achievement(
            id = id,
            title = title,
            description = description,
            target = target,
            current = current,
            rewardXp = rewardXp,
            badgeName = badgeName,
            rarity = rarity,
            unlockDay = unlockDay
        )
    }

    private fun streakAchievement(
        id: String,
        title: String,
        description: String,
        target: Double,
        current: Double,
        rewardXp: Int,
        badgeName: String,
        rarity: BadgeRarity,
        unlockDay: Long?
    ): AchievementSnapshot {
        return achievement(
            id = id,
            title = title,
            description = description,
            target = target,
            current = current,
            rewardXp = rewardXp,
            badgeName = badgeName,
            rarity = rarity,
            unlockDay = unlockDay
        )
    }

    private fun volumeAchievement(
        id: String,
        title: String,
        description: String,
        target: Double,
        current: Double,
        rewardXp: Int,
        badgeName: String,
        rarity: BadgeRarity,
        unlockDay: Long?
    ): AchievementSnapshot {
        return achievement(
            id = id,
            title = title,
            description = description,
            target = target,
            current = current,
            rewardXp = rewardXp,
            badgeName = badgeName,
            rarity = rarity,
            unlockDay = unlockDay
        )
    }

    private fun comebackAchievement(
        currentGapDays: Int,
        unlockedAtEpochDay: Long?
    ): AchievementSnapshot {
        return achievement(
            id = "comeback",
            title = "Comeback",
            description = "Return after a seven day break.",
            target = 7.0,
            current = currentGapDays.toDouble(),
            rewardXp = 200,
            badgeName = "Comeback",
            rarity = BadgeRarity.RARE,
            unlockDay = unlockedAtEpochDay
        )
    }

    private fun achievement(
        id: String,
        title: String,
        description: String,
        target: Double,
        current: Double,
        rewardXp: Int,
        badgeName: String,
        rarity: BadgeRarity,
        unlockDay: Long?
    ): AchievementSnapshot {
        return AchievementSnapshot(
            id = id,
            title = title,
            description = description,
            target = target,
            progress = current.coerceAtLeast(0.0),
            rewardXp = rewardXp,
            unlocked = current >= target,
            unlockedAtEpochDay = unlockDay,
            badge = BadgeSnapshot(
                id = id,
                name = badgeName,
                rarity = rarity
            )
        )
    }

    private fun mondayEpochDay(epochDay: Long): Long = LocalDate.ofEpochDay(epochDay)
        .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        .toEpochDay()

    private fun buildHeatmap(
        dayAggregates: Map<Long, DayAggregate>,
        today: LocalDate
    ): List<HeatmapPoint> {
        val startDay = today.minusDays((DAILY_HEATMAP_DAYS - 1).toLong())
        return (0 until DAILY_HEATMAP_DAYS).map { offset ->
            val day = startDay.plusDays(offset.toLong())
            val epochDay = day.toEpochDay()
            val aggregate = dayAggregates[epochDay] ?: DayAggregate()
            val score = heatmapScore(aggregate)
            HeatmapPoint(
                epochDay = epochDay,
                workoutCount = aggregate.workoutCount,
                exerciseCount = aggregate.exerciseCount,
                setCount = aggregate.setCount,
                volume = aggregate.volume,
                xp = aggregate.xp,
                score = score,
                intensity = heatmapIntensity(score)
            )
        }
    }

    private fun buildTrendPoints(
        dayAggregates: Map<Long, DayAggregate>,
        today: LocalDate
    ): List<TrendPoint> {
        val startDay = today.minusDays((TREND_WINDOW_DAYS - 1).toLong())
        return (0 until TREND_WINDOW_DAYS).map { offset ->
            val day = startDay.plusDays(offset.toLong())
            val epochDay = day.toEpochDay()
            val aggregate = dayAggregates[epochDay] ?: DayAggregate()
            TrendPoint(
                epochDay = epochDay,
                workoutCount = aggregate.workoutCount,
                exerciseCount = aggregate.exerciseCount,
                setCount = aggregate.setCount,
                volume = aggregate.volume,
                xp = aggregate.xp
            )
        }
    }

    fun xpForSession(session: WorkoutSessionSummary): Int {
        if (session.setCount <= 0) return 0
        val safeVolume = session.totalVolume.takeIf { it.isFinite() && it >= 0.0 } ?: 0.0
        val volumeBonus = (safeVolume / 80.0)
            .coerceAtMost(Int.MAX_VALUE.toDouble())
            .roundToInt()
            .toLong()
        val total = 90L +
            session.exerciseCount.coerceAtLeast(0).toLong() * 16L +
            session.setCount.coerceAtLeast(0).toLong() * 8L +
            volumeBonus
        return total.coerceIn(0L, MAX_SESSION_XP.toLong()).toInt()
    }

    fun levelForXp(totalXp: Int): Int {
        val safeXp = totalXp.coerceAtLeast(0).toLong()
        var lower = 1
        var upper = MAX_LEVEL_FOR_INT_XP

        // Fixed-cost binary search: unlike the old XP-controlled loop this
        // always completes in twelve comparisons for the complete Int range.
        repeat(LEVEL_SEARCH_STEPS) {
            if (lower < upper) {
                val candidate = (lower + upper + 1) / 2
                if (exactXpForLevelStart(candidate) <= safeXp) {
                    lower = candidate
                } else {
                    upper = candidate - 1
                }
            }
        }
        return lower
    }

    fun xpForLevelStart(level: Int): Int {
        if (level <= 1) {
            return 0
        }
        if (level > MAX_LEVEL_FOR_INT_XP) return Int.MAX_VALUE
        return exactXpForLevelStart(level).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    fun xpForNextLevel(level: Int): Int {
        val stage = (level.toLong() - 1L).coerceAtLeast(0L)
        val square = stage * stage
        if (square > (Long.MAX_VALUE - 200L - stage * 85L) / 8L) {
            return Int.MAX_VALUE
        }
        return (200L + stage * 85L + square * 8L)
            .coerceAtMost(Int.MAX_VALUE.toLong())
            .toInt()
    }

    private fun exactXpForLevelStart(level: Int): Long {
        val completedLevels = (level - 1).coerceAtLeast(0).toLong()
        val linear = 200L * completedLevels
        val arithmetic = 85L * completedLevels * (completedLevels - 1L) / 2L
        val quadratic = 8L * completedLevels * (completedLevels - 1L) *
            (2L * completedLevels - 1L) / 6L
        return linear + arithmetic + quadratic
    }

    private fun saturatedXpAdd(left: Int, right: Int): Int =
        (left.toLong() + right.toLong()).coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()

    private const val MAX_LEVEL_FOR_INT_XP = 4_096
    private const val LEVEL_SEARCH_STEPS = 12

    private fun titleForLevel(level: Int): GamificationTitle {
        return GamificationTitle(
            name = rankDefinitionForLevel(level).titleEn,
            tier = titleTierForLevel(level)
        )
    }

    private fun nextTitleAfter(level: Int): GamificationTitle? {
        val next = nextRankDefinitionAfter(level) ?: return null
        return GamificationTitle(
            name = next.titleEn,
            tier = titleTierForLevel(next.levelRequirement)
        )
    }

    private fun titleTierForLevel(level: Int): TitleTier {
        return when {
            level >= 50 -> TitleTier.LEGEND
            level >= 35 -> TitleTier.ELITE
            level >= 20 -> TitleTier.ATHLETE
            level >= 10 -> TitleTier.CONSISTENT
            level >= 5 -> TitleTier.BUILDER
            else -> TitleTier.NOVICE
        }
    }

    private fun heatmapScore(aggregate: DayAggregate): Int {
        val rawScore = aggregate.workoutCount * 12 + aggregate.setCount * 2 + (aggregate.volume / 250.0).roundToInt()
        return rawScore.coerceAtLeast(0)
    }

    private fun heatmapIntensity(score: Int): Int {
        return when {
            score <= 0 -> 0
            score < 10 -> 1
            score < 25 -> 2
            score < 50 -> 3
            else -> 4
        }
    }

    private fun unlockDayByCount(
        sessions: List<WorkoutSessionSummary>,
        target: Int,
        zoneId: ZoneId
    ): Long? {
        var count = 0
        sessions.forEach { session ->
            count += 1
            if (count >= target) {
                return epochDay(session.session.date, zoneId)
            }
        }
        return null
    }

    private fun unlockDayByVolume(
        sessions: List<WorkoutSessionSummary>,
        target: Double,
        zoneId: ZoneId
    ): Long? {
        var volume = 0.0
        sessions.forEach { session ->
            volume += session.totalVolume
            if (volume >= target) {
                return epochDay(session.session.date, zoneId)
            }
        }
        return null
    }

    private fun unlockDayByComeback(
        workoutDays: List<Long>,
        targetGapDays: Int
    ): Long? {
        if (workoutDays.size < 2) {
            return null
        }

        for (index in 1 until workoutDays.size) {
            val gapDays = (workoutDays[index] - workoutDays[index - 1]).toInt() - 1
            if (gapDays >= targetGapDays) {
                return workoutDays[index]
            }
        }

        return null
    }

    private fun maxGapDays(workoutDays: List<Long>): Int {
        if (workoutDays.size < 2) {
            return 0
        }

        var maxGap = 0
        for (index in 1 until workoutDays.size) {
            val gapDays = (workoutDays[index] - workoutDays[index - 1]).toInt() - 1
            maxGap = max(maxGap, gapDays)
        }
        return maxGap
    }

    private fun latestGapDays(workoutDays: List<Long>): Int? {
        if (workoutDays.size < 2) {
            return null
        }
        return (workoutDays.last() - workoutDays[workoutDays.lastIndex - 1]).toInt() - 1
    }

    private fun epochDay(timestamp: Long, zoneId: ZoneId): Long {
        return Instant.ofEpochMilli(timestamp).atZone(zoneId).toLocalDate().toEpochDay()
    }
}
