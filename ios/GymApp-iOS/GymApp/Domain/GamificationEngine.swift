import Foundation

public struct GamificationSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64 { generatedAt.gymEpochMilliseconds }
    public let generatedAt: Date
    public let summary: GamificationSummary
    public let progression: ProgressionSnapshot
    public let streak: StreakSnapshot
    public let comeback: ComebackSnapshot
    public let missions: MissionBoardSnapshot
    public let achievements: [AchievementSnapshot]
    public let unlockedBadges: [BadgeSnapshot]
    public let heatmap: [HeatmapPoint]
    public let trendPoints: [TrendPoint]
}

public struct GamificationSummary: Codable, Hashable, Sendable {
    public let workoutCount: Int
    public let workoutDayCount: Int
    public let setCount: Int
    public let totalVolume: Double
}

public struct ProgressionSnapshot: Codable, Hashable, Sendable {
    public let level: Int
    public let totalXP: Int
    public let baseXP: Int
    public let bonusXP: Int
    public let xpIntoLevel: Int
    public let xpToNextLevel: Int
    public let levelProgress: Double
    public let title: GamificationTitle
    public let nextTitle: GamificationTitle?
}

public struct GamificationTitle: Codable, Hashable, Sendable {
    public let name: String
    public let tier: TitleTier
}

public enum TitleTier: String, Codable, CaseIterable, Sendable {
    case novice, builder, consistent, athlete, elite, legend
}

public struct StreakSnapshot: Codable, Hashable, Sendable {
    public let currentDays: Int
    public let longestDays: Int
    public let activeToday: Bool
    public let lastWorkoutEpochDay: Int64?
    public let daysSinceLastWorkout: Int?
}

public struct ComebackSnapshot: Codable, Hashable, Sendable {
    public let eligible: Bool
    public let gapDays: Int?
    public let multiplier: Double
    public let bonusXP: Int
}

public struct MissionBoardSnapshot: Codable, Hashable, Sendable {
    public let daily: [MissionSnapshot]
    public let weekly: [MissionSnapshot]
}

public struct MissionSnapshot: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let target: Double
    public let progress: Double
    public let rewardXP: Int
    public let completed: Bool
}

public struct AchievementSnapshot: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let target: Double
    public let progress: Double
    public let rewardXP: Int
    public let unlocked: Bool
    public let unlockedAtEpochDay: Int64?
    public let badge: BadgeSnapshot
}

public struct BadgeSnapshot: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let rarity: BadgeRarity
}

public enum BadgeRarity: String, Codable, CaseIterable, Sendable {
    case common, uncommon, rare, epic, legendary
}

public struct HeatmapPoint: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64 { epochDay }
    public let epochDay: Int64
    public let workoutCount: Int
    public let exerciseCount: Int
    public let setCount: Int
    public let volume: Double
    public let xp: Int
    public let score: Int
    public let intensity: Int
}

public struct TrendPoint: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64 { epochDay }
    public let epochDay: Int64
    public let workoutCount: Int
    public let exerciseCount: Int
    public let setCount: Int
    public let volume: Double
    public let xp: Int
}

/// Formula-for-formula Swift port of Android's gamification snapshot builder.
public enum GamificationEngine {
    private static let dailyHeatmapDays = 365
    private static let trendWindowDays = 30
    private static let maximumXPPerSession = 5_000

    private struct DayAggregate {
        var workoutCount = 0
        var exerciseCount = 0
        var setCount = 0
        var volume = 0.0
        var xp = 0
    }

    public static func buildSnapshot(
        sessions: [WorkoutSessionSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> GamificationSnapshot {
        let sessions = sessions.sorted { $0.date < $1.date }
        let today = calendar.gymEpochDay(for: now)
        let dayAggregates = buildDayAggregates(sessions, calendar: calendar)
        let workoutDays = dayAggregates.keys.sorted()
        let summary = GamificationSummary(
            workoutCount: sessions.count,
            workoutDayCount: workoutDays.count,
            setCount: sessions.reduce(0) { $0 + $1.setCount },
            totalVolume: sessions.reduce(0) { $0 + $1.totalVolume }
        )
        let streak = buildStreakSnapshot(workoutDays: workoutDays, today: today)
        let comeback = buildComebackSnapshot(workoutDays: workoutDays)
        let achievements = buildAchievements(
            sessions: sessions,
            workoutDays: workoutDays,
            summary: summary,
            streak: streak,
            calendar: calendar
        )
        let baseXP = dayAggregates.values.reduce(0) { $0 + $1.xp }
        // Permanent progression is derived only from saved workout sessions.
        // Calendar-sensitive missions, streaks, comeback state, and achievements
        // remain visible but must not make total XP change as time passes.
        let bonusXP = 0
        let totalXP = baseXP + bonusXP

        return GamificationSnapshot(
            generatedAt: now,
            summary: summary,
            progression: buildProgression(baseXP: baseXP, bonusXP: bonusXP, totalXP: totalXP),
            streak: streak,
            comeback: comeback,
            missions: buildMissionBoard(dayAggregates: dayAggregates, today: today),
            achievements: achievements,
            unlockedBadges: achievements.filter(\.unlocked).map(\.badge),
            heatmap: buildHeatmap(dayAggregates: dayAggregates, today: today),
            trendPoints: buildTrendPoints(dayAggregates: dayAggregates, today: today)
        )
    }

    public static func xpForSession(_ session: WorkoutSessionSummary) -> Int {
        let setCount = max(0, session.setCount)
        guard setCount > 0 else { return 0 }

        let safeVolume = session.totalVolume.isFinite && session.totalVolume >= 0
            ? session.totalVolume
            : 0
        let rawVolumeBonus = (safeVolume / 80).rounded()
        let volumeBonus = rawVolumeBonus >= Double(Int.max) ? Int.max : Int(rawVolumeBonus)
        let earnedXP = saturatingAdd(
            saturatingAdd(
                saturatingAdd(90, saturatingMultiply(max(0, session.exerciseCount), 16)),
                saturatingMultiply(setCount, 8)
            ),
            volumeBonus
        )
        return min(maximumXPPerSession, earnedXP)
    }

    public static func level(for totalXP: Int) -> Int {
        let target = max(0, totalXP)
        var lower = 1
        var upper = 2
        while let threshold = exactXPForLevelStart(upper), threshold <= target {
            lower = upper
            guard upper <= Int.max / 2 else { return lower }
            upper *= 2
        }
        while lower + 1 < upper {
            let midpoint = lower + (upper - lower) / 2
            if let threshold = exactXPForLevelStart(midpoint), threshold <= target {
                lower = midpoint
            } else {
                upper = midpoint
            }
        }
        return lower
    }

    public static func xpForLevelStart(_ level: Int) -> Int {
        exactXPForLevelStart(level) ?? Int.max
    }

    public static func xpForNextLevel(_ level: Int) -> Int {
        let stage = level > 1 ? level - 1 : 0
        let linear = saturatingMultiply(stage, 85)
        let quadratic = saturatingMultiply(saturatingMultiply(stage, stage), 8)
        return saturatingAdd(saturatingAdd(200, linear), quadratic)
    }

    /// Closed-form progression-v1 threshold. `nil` means the mathematical value does
    /// not fit in `Int`; callers use it as an upper-bound sentinel, never as equality.
    private static func exactXPForLevelStart(_ level: Int) -> Int? {
        guard level > 1 else { return 0 }
        let count = level - 1
        guard let twiceCount = checkedMultiply(count, 2), twiceCount > 0 else { return nil }
        let squareFactor = twiceCount - 1

        guard let base = checkedMultiply(200, count),
              let triangular = checkedDividedProduct([count, count - 1], divisor: 2),
              let linear = checkedMultiply(85, triangular),
              let squares = checkedDividedProduct(
                [count - 1, count, squareFactor],
                divisor: 6
              ),
              let quadratic = checkedMultiply(8, squares),
              let partial = checkedAdd(base, linear) else {
            return nil
        }
        return checkedAdd(partial, quadratic)
    }

    private static func checkedDividedProduct(_ values: [Int], divisor: Int) -> Int? {
        var factors = values
        var remainingDivisor = divisor
        for index in factors.indices where remainingDivisor > 1 {
            let common = greatestCommonDivisor(factors[index], remainingDivisor)
            factors[index] /= common
            remainingDivisor /= common
        }
        guard remainingDivisor == 1 else { return nil }
        return factors.reduce(Optional(1)) { partial, factor in
            guard let partial else { return nil }
            return checkedMultiply(partial, factor)
        }
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(1, a)
    }

    private static func checkedMultiply(_ lhs: Int, _ rhs: Int) -> Int? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }

    private static func checkedAdd(_ lhs: Int, _ rhs: Int) -> Int? {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }

    private static func saturatingMultiply(_ lhs: Int, _ rhs: Int) -> Int {
        checkedMultiply(lhs, rhs) ?? Int.max
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        checkedAdd(lhs, rhs) ?? Int.max
    }

    public static func title(for level: Int) -> GamificationTitle {
        switch level {
        case 50...: return GamificationTitle(name: "Legend", tier: .legend)
        case 35...: return GamificationTitle(name: "Elite", tier: .elite)
        case 20...: return GamificationTitle(name: "Athlete", tier: .athlete)
        case 10...: return GamificationTitle(name: "Consistent", tier: .consistent)
        case 5...: return GamificationTitle(name: "Builder", tier: .builder)
        default: return GamificationTitle(name: "Rookie", tier: .novice)
        }
    }

    private static func buildDayAggregates(
        _ sessions: [WorkoutSessionSummary],
        calendar: Calendar
    ) -> [Int64: DayAggregate] {
        var result: [Int64: DayAggregate] = [:]
        for session in sessions {
            let day = calendar.gymEpochDay(for: session.date)
            var aggregate = result[day, default: DayAggregate()]
            aggregate.workoutCount += 1
            aggregate.exerciseCount += session.exerciseCount
            aggregate.setCount += session.setCount
            aggregate.volume += session.totalVolume
            aggregate.xp += xpForSession(session)
            result[day] = aggregate
        }
        return result
    }

    private static func buildProgression(
        baseXP: Int,
        bonusXP: Int,
        totalXP: Int
    ) -> ProgressionSnapshot {
        let level = level(for: totalXP)
        let startXP = xpForLevelStart(level)
        let nextXP = xpForLevelStart(level + 1)
        let intoLevel = totalXP - startXP
        let toNext = nextXP - totalXP
        let progress = nextXP == startXP ? 1 : Double(intoLevel) / Double(nextXP - startXP)
        return ProgressionSnapshot(
            level: level,
            totalXP: totalXP,
            baseXP: baseXP,
            bonusXP: bonusXP,
            xpIntoLevel: intoLevel,
            xpToNextLevel: toNext,
            levelProgress: min(1, max(0, progress)),
            title: title(for: level),
            nextTitle: title(for: level + 1)
        )
    }

    private static func buildStreakSnapshot(
        workoutDays: [Int64],
        today: Int64
    ) -> StreakSnapshot {
        guard let last = workoutDays.last else {
            return StreakSnapshot(
                currentDays: 0,
                longestDays: 0,
                activeToday: false,
                lastWorkoutEpochDay: nil,
                daysSinceLastWorkout: nil
            )
        }
        let days = Set(workoutDays)
        var cursor = days.contains(today) ? today : today - 1
        var current = 0
        while days.contains(cursor) {
            current += 1
            cursor -= 1
        }
        var longest = 0
        var run = 0
        var previous: Int64?
        for day in workoutDays {
            run = previous == nil || day != previous! + 1 ? 1 : run + 1
            longest = max(longest, run)
            previous = day
        }
        return StreakSnapshot(
            currentDays: current,
            longestDays: longest,
            activeToday: days.contains(today),
            lastWorkoutEpochDay: last,
            daysSinceLastWorkout: Int(today - last)
        )
    }

    private static func buildComebackSnapshot(workoutDays: [Int64]) -> ComebackSnapshot {
        let gap = latestGapDays(workoutDays)
        let value = gap ?? 0
        let eligible = gap != nil && value >= 3
        let multiplier: Double
        switch value {
        case _ where !eligible: multiplier = 1
        case 30...: multiplier = 1.5
        case 14...: multiplier = 1.35
        case 7...: multiplier = 1.2
        default: multiplier = 1.1
        }
        return ComebackSnapshot(
            eligible: eligible,
            gapDays: gap,
            multiplier: multiplier,
            bonusXP: eligible ? min(120, 30 + value * 6) : 0
        )
    }

    private static func buildMissionBoard(
        dayAggregates: [Int64: DayAggregate],
        today: Int64
    ) -> MissionBoardSnapshot {
        let todayAggregate = dayAggregates[today, default: DayAggregate()]
        // 1970-01-01 was Thursday. Modulo maps Monday to zero.
        let daysSinceMonday = Int((today + 3).positiveModulo(7))
        let weekStart = today - Int64(daysSinceMonday)
        let week = dayAggregates.filter { $0.key >= weekStart && $0.key <= today }
        let weeklyWorkoutDays = Double(week.count)
        let weeklyWorkoutCount = Double(week.values.reduce(0) { $0 + $1.workoutCount })
        let weeklySetCount = Double(week.values.reduce(0) { $0 + $1.setCount })
        let weeklyVolume = week.values.reduce(0) { $0 + $1.volume }

        return MissionBoardSnapshot(
            daily: [
                mission("daily_workout", "Complete a workout", "Finish at least one workout today.", 1, Double(todayAggregate.workoutCount), 30),
                mission("daily_sets", "Log 8 sets", "Accumulate eight sets in a single day.", 8, Double(todayAggregate.setCount), 25),
                mission("daily_exercises", "Train 3 exercises", "Touch three different exercise entries today.", 3, Double(todayAggregate.exerciseCount), 35),
                mission("daily_volume", "Move 1,000 volume", "Reach one thousand total volume today.", 1_000, todayAggregate.volume, 40)
            ],
            weekly: [
                mission("weekly_days", "Train on 3 days", "Work out on three separate days this week.", 3, weeklyWorkoutDays, 60),
                mission("weekly_workouts", "Complete 4 workouts", "Finish four workouts this week.", 4, weeklyWorkoutCount, 70),
                mission("weekly_sets", "Log 30 sets", "Accumulate thirty sets this week.", 30, weeklySetCount, 80),
                mission("weekly_volume", "Move 5,000 volume", "Reach five thousand total volume this week.", 5_000, weeklyVolume, 100)
            ]
        )
    }

    private static func buildAchievements(
        sessions: [WorkoutSessionSummary],
        workoutDays: [Int64],
        summary: GamificationSummary,
        streak: StreakSnapshot,
        calendar: Calendar
    ) -> [AchievementSnapshot] {
        [
            achievement("first_workout", "First Workout", "Complete your first workout.", 1, Double(summary.workoutCount), 100, "First Rep", .common, unlockDayByCount(sessions, 1, calendar)),
            achievement("workout_5", "Starter Habit", "Complete five workouts.", 5, Double(summary.workoutCount), 150, "Starter Habit", .common, unlockDayByCount(sessions, 5, calendar)),
            achievement("workout_10", "Consistency Builder", "Complete ten workouts.", 10, Double(summary.workoutCount), 200, "Consistency", .uncommon, unlockDayByCount(sessions, 10, calendar)),
            achievement("workout_25", "Workhorse", "Complete twenty-five workouts.", 25, Double(summary.workoutCount), 350, "Workhorse", .rare, unlockDayByCount(sessions, 25, calendar)),
            achievement("workout_50", "Veteran", "Complete fifty workouts.", 50, Double(summary.workoutCount), 500, "Veteran", .epic, unlockDayByCount(sessions, 50, calendar)),
            achievement("workout_100", "Centurion", "Complete one hundred workouts.", 100, Double(summary.workoutCount), 900, "Centurion", .legendary, unlockDayByCount(sessions, 100, calendar)),
            achievement("streak_7", "Seven-Day Streak", "Keep a seven day streak alive.", 7, Double(streak.longestDays), 150, "Momentum", .common, unlockDayByStreak(workoutDays, 7)),
            achievement("streak_14", "Fourteen-Day Streak", "Keep a fourteen day streak alive.", 14, Double(streak.longestDays), 250, "Flow State", .uncommon, unlockDayByStreak(workoutDays, 14)),
            achievement("streak_30", "Thirty-Day Streak", "Keep a thirty day streak alive.", 30, Double(streak.longestDays), 500, "Unbroken", .epic, unlockDayByStreak(workoutDays, 30)),
            achievement("volume_10k", "Ten Thousand Volume", "Accumulate ten thousand total volume.", 10_000, summary.totalVolume, 200, "Volume Maker", .uncommon, unlockDayByVolume(sessions, 10_000, calendar)),
            achievement("volume_50k", "Fifty Thousand Volume", "Accumulate fifty thousand total volume.", 50_000, summary.totalVolume, 500, "Mountain Mover", .rare, unlockDayByVolume(sessions, 50_000, calendar)),
            achievement("comeback", "Comeback", "Return after a seven day break.", 7, Double(maxGapDays(workoutDays)), 200, "Comeback", .rare, unlockDayByComeback(workoutDays, 7))
        ]
    }

    private static func achievement(
        _ id: String,
        _ title: String,
        _ description: String,
        _ target: Double,
        _ current: Double,
        _ rewardXP: Int,
        _ badgeName: String,
        _ rarity: BadgeRarity,
        _ unlockDay: Int64?
    ) -> AchievementSnapshot {
        AchievementSnapshot(
            id: id,
            title: title,
            description: description,
            target: target,
            progress: max(0, current),
            rewardXP: rewardXP,
            unlocked: current >= target,
            unlockedAtEpochDay: unlockDay,
            badge: BadgeSnapshot(id: id, name: badgeName, rarity: rarity)
        )
    }

    private static func mission(
        _ id: String,
        _ title: String,
        _ description: String,
        _ target: Double,
        _ progress: Double,
        _ rewardXP: Int
    ) -> MissionSnapshot {
        MissionSnapshot(
            id: id,
            title: title,
            description: description,
            target: target,
            progress: max(0, progress),
            rewardXP: rewardXP,
            completed: progress >= target
        )
    }

    private static func buildHeatmap(
        dayAggregates: [Int64: DayAggregate],
        today: Int64
    ) -> [HeatmapPoint] {
        let start = today - Int64(dailyHeatmapDays - 1)
        return (0 ..< dailyHeatmapDays).map { offset in
            let day = start + Int64(offset)
            let aggregate = dayAggregates[day, default: DayAggregate()]
            let score = max(0, aggregate.workoutCount * 12 + aggregate.setCount * 2 + Int((aggregate.volume / 250).rounded()))
            let intensity: Int
            switch score {
            case 0: intensity = 0
            case 1 ..< 10: intensity = 1
            case 10 ..< 25: intensity = 2
            case 25 ..< 50: intensity = 3
            default: intensity = 4
            }
            return HeatmapPoint(
                epochDay: day,
                workoutCount: aggregate.workoutCount,
                exerciseCount: aggregate.exerciseCount,
                setCount: aggregate.setCount,
                volume: aggregate.volume,
                xp: aggregate.xp,
                score: score,
                intensity: intensity
            )
        }
    }

    private static func buildTrendPoints(
        dayAggregates: [Int64: DayAggregate],
        today: Int64
    ) -> [TrendPoint] {
        let start = today - Int64(trendWindowDays - 1)
        return (0 ..< trendWindowDays).map { offset in
            let day = start + Int64(offset)
            let aggregate = dayAggregates[day, default: DayAggregate()]
            return TrendPoint(
                epochDay: day,
                workoutCount: aggregate.workoutCount,
                exerciseCount: aggregate.exerciseCount,
                setCount: aggregate.setCount,
                volume: aggregate.volume,
                xp: aggregate.xp
            )
        }
    }

    private static func unlockDayByCount(
        _ sessions: [WorkoutSessionSummary],
        _ target: Int,
        _ calendar: Calendar
    ) -> Int64? {
        guard sessions.count >= target else { return nil }
        return calendar.gymEpochDay(for: sessions[target - 1].date)
    }

    private static func unlockDayByVolume(
        _ sessions: [WorkoutSessionSummary],
        _ target: Double,
        _ calendar: Calendar
    ) -> Int64? {
        var volume = 0.0
        for session in sessions {
            volume += session.totalVolume
            if volume >= target { return calendar.gymEpochDay(for: session.date) }
        }
        return nil
    }

    private static func unlockDayByStreak(_ days: [Int64], _ target: Int) -> Int64? {
        var run = 0
        var previous: Int64?
        for day in days {
            run = previous == nil || day != previous! + 1 ? 1 : run + 1
            if run >= target { return day }
            previous = day
        }
        return nil
    }

    private static func unlockDayByComeback(_ days: [Int64], _ target: Int) -> Int64? {
        guard days.count >= 2 else { return nil }
        for index in 1 ..< days.count where Int(days[index] - days[index - 1]) - 1 >= target {
            return days[index]
        }
        return nil
    }

    private static func maxGapDays(_ days: [Int64]) -> Int {
        guard days.count >= 2 else { return 0 }
        return (1 ..< days.count).reduce(0) {
            max($0, Int(days[$1] - days[$1 - 1]) - 1)
        }
    }

    private static func latestGapDays(_ days: [Int64]) -> Int? {
        guard days.count >= 2 else { return nil }
        return Int(days[days.count - 1] - days[days.count - 2]) - 1
    }
}

private extension Int64 {
    func positiveModulo(_ divisor: Int64) -> Int64 {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
