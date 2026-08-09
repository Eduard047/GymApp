package com.example.gymapp.data.repository

data class GamificationSnapshot(
    val generatedAt: Long,
    val summary: GamificationSummary,
    val progression: ProgressionSnapshot,
    val streak: StreakSnapshot,
    val comeback: ComebackSnapshot,
    val achievements: List<AchievementSnapshot>,
    val unlockedBadges: List<BadgeSnapshot>,
    val heatmap: List<HeatmapPoint>,
    val trendPoints: List<TrendPoint>
)

data class GamificationSummary(
    val workoutCount: Int,
    val workoutDayCount: Int,
    val setCount: Int,
    val totalVolume: Double
)

data class ProgressionSnapshot(
    val level: Int,
    val totalXp: Int,
    val baseXp: Int,
    val bonusXp: Int,
    val xpIntoLevel: Int,
    val xpToNextLevel: Int,
    val levelProgress: Double,
    val title: GamificationTitle,
    val nextTitle: GamificationTitle?
)

data class GamificationTitle(
    val name: String,
    val tier: TitleTier
)

enum class TitleTier {
    NOVICE,
    BUILDER,
    CONSISTENT,
    ATHLETE,
    ELITE,
    LEGEND
}

data class StreakSnapshot(
    val currentDays: Int,
    val longestDays: Int,
    val activeToday: Boolean,
    val lastWorkoutEpochDay: Long?,
    val daysSinceLastWorkout: Int?
)

data class ComebackSnapshot(
    val eligible: Boolean,
    val gapDays: Int?,
    val multiplier: Double,
    val bonusXp: Int
)

data class AchievementSnapshot(
    val id: String,
    val title: String,
    val description: String,
    val target: Double,
    val progress: Double,
    val rewardXp: Int,
    val unlocked: Boolean,
    val unlockedAtEpochDay: Long?,
    val badge: BadgeSnapshot
)

data class BadgeSnapshot(
    val id: String,
    val name: String,
    val rarity: BadgeRarity
)

enum class BadgeRarity {
    COMMON,
    UNCOMMON,
    RARE,
    EPIC,
    LEGENDARY
}

data class HeatmapPoint(
    val epochDay: Long,
    val workoutCount: Int,
    val exerciseCount: Int,
    val setCount: Int,
    val volume: Double,
    val xp: Int,
    val score: Int,
    val intensity: Int
)

data class TrendPoint(
    val epochDay: Long,
    val workoutCount: Int,
    val exerciseCount: Int,
    val setCount: Int,
    val volume: Double,
    val xp: Int
)
