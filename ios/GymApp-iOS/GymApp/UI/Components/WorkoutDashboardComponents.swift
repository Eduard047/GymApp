import SwiftUI

enum WorkoutMusclePeriod: String, CaseIterable, Identifiable {
    case allTime
    case month
    case week

    var id: Self { self }

    var title: String {
        switch self {
        case .allTime: gymLocalized("All time")
        case .month: gymLocalized("Month")
        case .week: gymLocalized("Week")
        }
    }
}

struct WorkoutMuscleMetric: Identifiable, Hashable {
    let id: String
    let label: String
    let load: Double
    let setCount: Int
    let sessionCount: Int
    let exerciseCount: Int
    let intensity: Double
    let lastTrainedAt: Date?
}

struct WorkoutExerciseContribution: Identifiable, Hashable {
    var id: String { exerciseName }

    let exerciseName: String
    let catalogKey: String?
    let load: Double
    let setCount: Int
    let sessionCount: Int
}

struct WorkoutMuscleDashboardData: Hashable {
    let totalSets: Int
    let totalLoad: Double
    let mappedExerciseCount: Int
    let totalExerciseCount: Int
    let muscles: [WorkoutMuscleMetric]
    let selectedContributions: [WorkoutExerciseContribution]
}

struct WorkoutRecommendationModel: Identifiable, Hashable {
    let id: String
    let title: String
    let supporting: String
    let priority: String
}

enum WorkoutDashboardDataBuilder {
    private struct MuscleAccumulator {
        var load = 0.0
        var setIDs: Set<UUID> = []
        var sessionIDs: Set<UUID> = []
        var exerciseKeys: Set<String> = []
        var lastTrainedAt: Date?
    }

    private struct ExerciseAccumulator {
        var catalogKey: String?
        var load = 0.0
        var setIDs: Set<UUID> = []
        var sessionIDs: Set<UUID> = []
    }

    private struct TrainingGroup {
        let id: String
        let title: String
        let supporting: String
        let priority: String
        let muscleIDs: [String]
    }

    static func filteredHistory(
        _ history: [ExerciseHistoryEntry],
        for period: WorkoutMusclePeriod,
        now: Date,
        calendar: Calendar
    ) -> [ExerciseHistoryEntry] {
        let interval: DateInterval?
        switch period {
        case .allTime:
            interval = nil
        case .month:
            interval = calendar.dateInterval(of: .month, for: now)
        case .week:
            let start = calendar.gymMondayStart(of: now)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            interval = DateInterval(start: start, end: end)
        }

        guard let interval else { return history }
        return history.filter { interval.contains($0.sessionDate) }
    }

    static func muscleData(
        history: [ExerciseHistoryEntry],
        mappings: [ExerciseMuscleMapping],
        selectedMuscleID: String?
    ) -> WorkoutMuscleDashboardData {
        let manualMappings = MuscleMappingEngine.manualContributionMap(from: mappings)
        var statsByMuscle: [String: MuscleAccumulator] = [:]
        var selectedExerciseStats: [String: ExerciseAccumulator] = [:]
        var distinctExerciseKeys: Set<String> = []
        var mappedExerciseKeys: Set<String> = []

        for entry in history {
            let exerciseKey = MuscleMappingEngine.normalizeExerciseName(entry.exerciseName)
            guard !exerciseKey.isEmpty else { continue }
            distinctExerciseKeys.insert(exerciseKey)

            let contributions = MuscleMappingEngine.contributions(
                for: entry.exerciseName,
                manualMappings: manualMappings
            )
            guard !contributions.isEmpty else { continue }
            mappedExerciseKeys.insert(exerciseKey)

            let estimatedLoad = MuscleMappingEngine.estimatedLoad(for: entry)
            for contribution in contributions {
                var muscle = statsByMuscle[contribution.muscleID, default: MuscleAccumulator()]
                let weightedLoad = estimatedLoad * contribution.weight
                muscle.load += weightedLoad
                muscle.setIDs.insert(entry.setID)
                muscle.sessionIDs.insert(entry.workoutID)
                muscle.exerciseKeys.insert(exerciseKey)
                if entry.sessionDate > (muscle.lastTrainedAt ?? .distantPast) {
                    muscle.lastTrainedAt = entry.sessionDate
                }
                statsByMuscle[contribution.muscleID] = muscle

                if contribution.muscleID == selectedMuscleID {
                    var exercise = selectedExerciseStats[
                        entry.exerciseName,
                        default: ExerciseAccumulator()
                    ]
                    exercise.catalogKey = exercise.catalogKey ?? entry.exerciseCatalogKey
                    exercise.load += weightedLoad
                    exercise.setIDs.insert(entry.setID)
                    exercise.sessionIDs.insert(entry.workoutID)
                    selectedExerciseStats[entry.exerciseName] = exercise
                }
            }
        }

        let maximumLoad = statsByMuscle.values.map(\.load).max() ?? 0
        let muscles = MuscleMappingEngine.muscleDefinitions.map { definition in
            let stats = statsByMuscle[definition.id, default: MuscleAccumulator()]
            let loadRatio = maximumLoad > 0 ? min(1, max(0, stats.load / maximumLoad)) : 0
            return WorkoutMuscleMetric(
                id: definition.id,
                label: localizedMuscleName(definition),
                load: stats.load,
                setCount: stats.setIDs.count,
                sessionCount: stats.sessionIDs.count,
                exerciseCount: stats.exerciseKeys.count,
                intensity: loadRatio.squareRoot(),
                lastTrainedAt: stats.lastTrainedAt
            )
        }
        var selectedContributions = selectedExerciseStats.map { element in
            WorkoutExerciseContribution(
                exerciseName: element.key,
                catalogKey: element.value.catalogKey,
                load: element.value.load,
                setCount: element.value.setIDs.count,
                sessionCount: element.value.sessionIDs.count
            )
        }
        selectedContributions.sort { lhs, rhs in
            if lhs.load != rhs.load { return lhs.load > rhs.load }
            let lhsName = gymExerciseName(lhs.exerciseName, catalogKey: lhs.catalogKey)
            let rhsName = gymExerciseName(rhs.exerciseName, catalogKey: rhs.catalogKey)
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        return WorkoutMuscleDashboardData(
            totalSets: history.count,
            totalLoad: history.reduce(0) { $0 + MuscleMappingEngine.estimatedLoad(for: $1) },
            mappedExerciseCount: mappedExerciseKeys.count,
            totalExerciseCount: distinctExerciseKeys.count,
            muscles: muscles,
            selectedContributions: Array(selectedContributions.prefix(8))
        )
    }

    static func recommendations(
        history: [ExerciseHistoryEntry],
        mappings: [ExerciseMuscleMapping],
        now: Date,
        calendar: Calendar
    ) -> [WorkoutRecommendationModel] {
        guard !history.isEmpty else {
            return [
                WorkoutRecommendationModel(
                    id: "start",
                    title: gymLocalized("Log a few workouts"),
                    supporting: gymLocalized("Recommendations need enough history to compare muscle groups."),
                    priority: gymLocalized("Setup")
                )
            ]
        }

        let muscleLoads = MuscleMappingEngine.muscleLoads(history: history, mappings: mappings)
        let loadsByID = Dictionary(uniqueKeysWithValues: muscleLoads.map { ($0.muscleID, $0.load) })
        let lastDateByID = Dictionary(
            uniqueKeysWithValues: muscleLoads.compactMap { load in
                load.lastTrainedAt.map { (load.muscleID, $0) }
            }
        )
        let labelByID = Dictionary(
            uniqueKeysWithValues: MuscleMappingEngine.muscleDefinitions.map {
                ($0.id, localizedMuscleName($0))
            }
        )
        var result: [WorkoutRecommendationModel] = []

        let balanceMuscleIDs = ["lats", "upperBack", "chest", "quads", "hamstrings", "glutes"]
        let stale = balanceMuscleIDs
            .map { id in
                (
                    id: id,
                    days: lastDateByID[id].map { calendar.gymDaysBetween($0, now) } ?? 999
                )
            }
            .filter { $0.days >= 8 }
            .sorted { $0.days > $1.days }
            .prefix(3)

        if !stale.isEmpty {
            let names = stale.map { labelByID[$0.id] ?? $0.id }.joined(separator: ", ")
            result.append(
                WorkoutRecommendationModel(
                    id: "stale",
                    title: "\(gymLocalized("Long gap")): \(names)",
                    supporting: gymLocalized("These groups have not had meaningful work for 8+ days."),
                    priority: gymLocalized("Balance")
                )
            )
        }

        let quadLoad = loadsByID["quads", default: 0]
        let posteriorLoad = loadsByID["hamstrings", default: 0] +
            loadsByID["glutes", default: 0] +
            loadsByID["lowerBack", default: 0]
        if quadLoad > 0, posteriorLoad > 0, quadLoad / posteriorLoad > 1.8 {
            result.append(
                WorkoutRecommendationModel(
                    id: "posterior-chain",
                    title: gymLocalized("Posterior chain is behind"),
                    supporting: gymLocalized("Quad load is much higher than hamstrings, glutes and lower back combined."),
                    priority: gymLocalized("Legs")
                )
            )
        }

        let groups = [
            TrainingGroup(
                id: "pull",
                title: gymLocalized("Pull day"),
                supporting: gymLocalized("Back, biceps and forearms have the oldest recent work."),
                priority: gymLocalized("Pull"),
                muscleIDs: ["lats", "upperBack", "biceps", "forearms"]
            ),
            TrainingGroup(
                id: "legs",
                title: gymLocalized("Leg day"),
                supporting: gymLocalized("Quads, hamstrings, glutes and calves are next in the rotation."),
                priority: gymLocalized("Legs"),
                muscleIDs: ["quads", "hamstrings", "glutes", "calves"]
            ),
            TrainingGroup(
                id: "push",
                title: gymLocalized("Push day"),
                supporting: gymLocalized("Chest, shoulders and triceps have the oldest recent work."),
                priority: gymLocalized("Push"),
                muscleIDs: ["chest", "shoulders", "triceps"]
            )
        ]
        let nextGroup = groups.min { lhs, rhs in
            mostRecentDate(in: lhs, dates: lastDateByID) < mostRecentDate(in: rhs, dates: lastDateByID)
        } ?? groups[0]
        result.append(
            WorkoutRecommendationModel(
                id: "next-\(nextGroup.id)",
                title: "\(gymLocalized("Next")): \(nextGroup.title)",
                supporting: nextGroup.supporting,
                priority: nextGroup.priority
            )
        )

        return Array(result.prefix(4))
    }

    private static func localizedMuscleName(_ definition: MuscleDefinition) -> String {
        gymCurrentLanguageCode() == "uk"
            ? definition.titleUk
            : definition.titleEn
    }

    private static func mostRecentDate(
        in group: TrainingGroup,
        dates: [String: Date]
    ) -> Date {
        group.muscleIDs.compactMap { dates[$0] }.max() ?? .distantPast
    }
}

struct WorkoutMonthSwitcher: View {
    let month: Date
    let isCurrentMonth: Bool
    let onPrevious: () -> Void
    let onCurrent: () -> Void
    let onNext: () -> Void

    var body: some View {
        GymPanel(
            contentPadding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        ) {
            HStack(spacing: 8) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Previous month")

                Button(action: onCurrent) {
                    VStack(spacing: 2) {
                        Text(month, format: .dateTime.month(.wide).year())
                            .font(.headline)
                            .foregroundStyle(GymTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text(gymLocalized(isCurrentMonth ? "Current month" : "Return to current month"))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(monthAccessibilityLabel)

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .disabled(isCurrentMonth)
                .accessibilityLabel("Next month")
                .accessibilityHint(isCurrentMonth ? gymLocalized("The current month is already selected") : "")
            }
            .buttonStyle(.borderless)
        }
    }

    private var monthAccessibilityLabel: String {
        let locale = AppLanguage(rawValue: gymCurrentLanguageCode())?.locale ?? AppLanguage.english.locale
        let formatted = month.formatted(.dateTime.month(.wide).year().locale(locale))
        return isCurrentMonth
            ? gymText("Current month, \(formatted)", "Поточний місяць, \(formatted)", languageCode: gymCurrentLanguageCode())
            : gymText("\(formatted). Return to current month", "\(formatted). Повернутися до поточного місяця", languageCode: gymCurrentLanguageCode())
    }
}

struct WorkoutProgressHero: View {
    let snapshot: GamificationSnapshot
    let monthXP: Int
    let onOpenRanks: () -> Void

    private var progression: ProgressionSnapshot { snapshot.progression }

    var body: some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("SOLO PROGRESS")
                    .font(.caption.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(Color.white.opacity(0.8))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        identity
                        xpBlock
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        identity
                        xpBlock
                    }
                }

                ProgressView(value: progression.levelProgress)
                    .tint(.white)
                    .accessibilityLabel("Level progress")
                    .accessibilityValue(
                        "\(progression.xpIntoLevel) of " +
                            "\(progression.xpIntoLevel + progression.xpToNextLevel) XP"
                    )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                    spacing: 8
                ) {
                    GymMetricTile(
                        label: "Month XP",
                        value: "\(monthXP) XP",
                        emphasized: true,
                        onHero: true
                    )
                    GymMetricTile(
                        label: "Day streak",
                        value: gymCount(
                            snapshot.streak.currentDays,
                            englishOne: "day",
                            englishMany: "days",
                            ukrainianOne: "день",
                            ukrainianFew: "дні",
                            ukrainianMany: "днів"
                        ),
                        onHero: true
                    )
                    GymMetricTile(
                        label: "Next title",
                        value: progression.nextTitle?.name ?? "Top rank",
                        onHero: true
                    )
                }

                Button(action: onOpenRanks) {
                    Label("View ranks", systemImage: "trophy.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the full rank ladder")
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(gymLocalized("LEVEL")) \(progression.level)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.13), in: Capsule())
            Text(gymLocalized(progression.title.name))
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(gymLocalized(progressSummary))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var xpBlock: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("TOTAL XP")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Text(progression.totalXP.formatted())
                .font(.title2.bold())
                .contentTransition(.numericText())
            Text("earned")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(12)
        .frame(minWidth: 110, alignment: .trailing)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total XP")
        .accessibilityValue(progression.totalXP.formatted())
    }

    private var progressSummary: String {
        if snapshot.summary.workoutCount == 0 {
            return "Log a workout to start your momentum."
        }
        if snapshot.streak.currentDays > 0 {
            return gymText(
                "A \(snapshot.streak.currentDays)-day streak is building real momentum.",
                "Серія у \(snapshot.streak.currentDays) дн. створює справжній темп.",
                languageCode: gymCurrentLanguageCode()
            )
        }
        return "One more session starts your next streak."
    }

}

struct WorkoutKPICard: View {
    let stats: DashboardStats

    var body: some View {
        GymHeroPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Monthly Snapshot")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Track consistency, output and intensity at a glance.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.86))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 128), spacing: 8)],
                    spacing: 8
                ) {
                    GymMetricTile(
                        label: "Workouts",
                        value: stats.workoutCount.formatted(),
                        emphasized: true,
                        onHero: true
                    )
                    GymMetricTile(
                        label: "Week streak",
                        value: gymCount(
                            stats.weeklyStreakWeeks,
                            englishOne: "week",
                            englishMany: "weeks",
                            ukrainianOne: "тиждень",
                            ukrainianFew: "тижні",
                            ukrainianMany: "тижнів"
                        ),
                        onHero: true
                    )
                    GymMetricTile(
                        label: "Total volume",
                        value: compactNumber(stats.totalVolume),
                        onHero: true
                    )
                    GymMetricTile(
                        label: "Avg intensity",
                        value: compactNumber(stats.averageIntensity),
                        onHero: true
                    )
                }
            }
        }
    }
}

struct WorkoutActivityHeatmapDay: Identifiable, Hashable, Sendable {
    var id: Date { date }

    let date: Date
    let sessionCount: Int
    let volume: Double
    let intensity: Double
    let isInMonth: Bool
    let isToday: Bool
}

enum WorkoutActivityHeatmapLayout {
    static func days(
        month: Date,
        sessions: [WorkoutSessionSummary],
        now: Date,
        calendar: Calendar
    ) -> [WorkoutActivityHeatmapDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else {
            return []
        }

        let firstWeekStart = calendar.gymMondayStart(of: monthInterval.start)
        let lastWeekStart = calendar.gymMondayStart(of: lastDay)
        let naturalCellCount = calendar.dateComponents(
            [.day],
            from: firstWeekStart,
            to: calendar.date(byAdding: .day, value: 7, to: lastWeekStart) ?? monthInterval.end
        ).day ?? 35
        let cellCount = max(35, ((naturalCellCount + 6) / 7) * 7)
        let visibleDates = (0 ..< cellCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstWeekStart)
        }
        let sessionsByDay = Dictionary(grouping: sessions) {
            calendar.startOfDay(for: $0.date)
        }
        let maximumLoad = visibleDates
            .filter { isInside($0, interval: monthInterval) }
            .map { date in
                let daySessions = sessionsByDay[calendar.startOfDay(for: date), default: []]
                let volume = daySessions.reduce(0) { $0 + $1.totalVolume }
                return volume > 0 ? volume : Double(daySessions.count)
            }
            .max() ?? 0

        return visibleDates.map { date in
            let isInMonth = isInside(date, interval: monthInterval)
            let daySessions = isInMonth
                ? sessionsByDay[calendar.startOfDay(for: date), default: []]
                : []
            let volume = daySessions.reduce(0) { $0 + $1.totalVolume }
            let load = volume > 0 ? volume : Double(daySessions.count)
            let intensity = maximumLoad > 0 && !daySessions.isEmpty
                ? min(1, 0.28 + (load / maximumLoad) * 0.72)
                : 0
            return WorkoutActivityHeatmapDay(
                date: date,
                sessionCount: daySessions.count,
                volume: volume,
                intensity: intensity,
                isInMonth: isInMonth,
                isToday: calendar.isDate(date, inSameDayAs: now)
            )
        }
    }

    private static func isInside(_ date: Date, interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }
}

struct WorkoutActivityHeatmap: View {

    let month: Date
    let sessions: [WorkoutSessionSummary]
    let now: Date
    let calendar: Calendar

    private var days: [WorkoutActivityHeatmapDay] {
        WorkoutActivityHeatmapLayout.days(
            month: month,
            sessions: sessions,
            now: now,
            calendar: calendar
        )
    }

    private var weekdaySymbols: [String] {
        var localizedCalendar = calendar
        localizedCalendar.locale = AppLanguage(rawValue: gymCurrentLanguageCode())?.locale
        let symbols = localizedCalendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else {
            return gymCurrentLanguageCode() == AppLanguage.ukrainian.rawValue
                ? ["П", "В", "С", "Ч", "П", "С", "Н"]
                : ["M", "T", "W", "T", "F", "S", "S"]
        }
        return Array(symbols[1...6]) + [symbols[0]]
    }

    private var monthSessions: [WorkoutSessionSummary] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return sessions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    var body: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        heatmapTitle
                        Spacer(minLength: 0)
                        activeDaysPill
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        heatmapTitle
                        activeDaysPill
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 128), spacing: 8)],
                    spacing: 8
                ) {
                    GymMetricTile(label: "Sessions", value: monthSessions.count.formatted())
                    GymMetricTile(
                        label: "Volume",
                        value: compactNumber(monthSessions.reduce(0) { $0 + $1.totalVolume })
                    )
                }

                Text("Color shows daily training volume. Orange marks the highest-load days.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                    spacing: 6
                ) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(GymTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                    ForEach(days) { day in
                        heatmapCell(day)
                    }
                }
                .frame(maxWidth: 440, alignment: .leading)

                HStack(spacing: 7) {
                    Text("Less")
                    ForEach(1 ... 4, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(heatmapColor(intensity: Double(level) / 4, isInMonth: true))
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                    }
                    Text("More")
                }
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Heatmap scale, less activity to more activity")
            }
        }
    }

    private var activeDays: Int {
        Set(monthSessions.map { calendar.startOfDay(for: $0.date) }).count
    }

    private var heatmapTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Activity Heatmap")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(month.formatted(.dateTime.month(.wide).year().locale(appLocale)))
                .font(.caption)
                .foregroundStyle(GymTheme.textSecondary)
        }
    }

    private var activeDaysPill: some View {
        GymInfoPill(
            gymCount(
                activeDays,
                englishOne: "active day",
                englishMany: "active days",
                ukrainianOne: "активний день",
                ukrainianFew: "активні дні",
                ukrainianMany: "активних днів"
            ),
            systemImage: "calendar.badge.checkmark"
        )
    }

    private var appLocale: Locale {
        AppLanguage(rawValue: gymCurrentLanguageCode())?.locale ?? AppLanguage.english.locale
    }

    private func heatmapCell(_ day: WorkoutActivityHeatmapDay) -> some View {
        Text(day.isInMonth ? calendar.component(.day, from: day.date).formatted() : "")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(day.intensity > 0.62 ? Color.white : GymTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(heatmapColor(intensity: day.intensity, isInMonth: day.isInMonth))
            )
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(GymTheme.primary, lineWidth: 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gymFormattedDate(day.date, date: .long, time: .omitted))
            .accessibilityValue(dayAccessibilityValue(day))
            .accessibilityHidden(!day.isInMonth)
    }

    private func dayAccessibilityValue(_ day: WorkoutActivityHeatmapDay) -> String {
        guard day.isInMonth else { return gymLocalized("Outside selected month") }
        guard day.sessionCount > 0 else { return gymLocalized("No workouts") }
        let workouts = gymCount(
            day.sessionCount,
            englishOne: "workout",
            englishMany: "workouts",
            ukrainianOne: "тренування",
            ukrainianFew: "тренування",
            ukrainianMany: "тренувань"
        )
        return gymText(
            "\(workouts), \(compactNumber(day.volume)) volume",
            "\(workouts), обсяг \(compactNumber(day.volume))",
            languageCode: gymCurrentLanguageCode()
        )
    }

    private func heatmapColor(intensity: Double, isInMonth: Bool) -> Color {
        guard isInMonth else { return GymTheme.surfaceVariant.opacity(0.22) }
        switch intensity {
        case ...0:
            return GymTheme.surfaceVariant.opacity(0.78)
        case ..<0.35:
            return GymTheme.secondary.opacity(0.32)
        case ..<0.7:
            return GymTheme.primary.opacity(0.54)
        default:
            return GymTheme.tertiary.opacity(0.9)
        }
    }
}

struct WorkoutMuscleLoadCard: View {
    @Binding var period: WorkoutMusclePeriod
    @Binding var selectedMuscleID: String?

    let data: WorkoutMuscleDashboardData

    private var selectedMuscle: WorkoutMuscleMetric? {
        data.muscles.first { $0.id == selectedMuscleID }
    }

    var body: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Muscle Map")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("Compare which muscle groups carried your logged training load.")
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    GymInfoPill(period.title, systemImage: "figure.strengthtraining.traditional")
                }

                Picker("Muscle load period", selection: $period) {
                    ForEach(WorkoutMusclePeriod.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                    spacing: 8
                ) {
                    GymMetricTile(label: "Sets", value: data.totalSets.formatted())
                    GymMetricTile(
                        label: "Load",
                        value: compactNumber(data.totalLoad),
                        emphasized: true
                    )
                    GymMetricTile(
                        label: "Mapped",
                        value: "\(data.mappedExerciseCount)/\(data.totalExerciseCount)"
                    )
                }

                Text("Select a muscle to see the exercises behind its load.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)

                MuscleBodyMap(
                    intensityByMuscle: intensityByMuscle,
                    selectedMuscleID: selectedMuscleID,
                    selectedMuscleLabel: selectedMuscle?.label
                ) { muscleID in
                    selectedMuscleID = selectedMuscleID == muscleID ? nil : muscleID
                }

                HStack(spacing: 8) {
                    Text("Front")
                        .frame(maxWidth: .infinity)
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(GymTheme.textSecondary)
                .accessibilityElement(children: .combine)

                MuscleBodyMapLegend()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 116), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(data.muscles) { muscle in
                        muscleButton(muscle)
                    }
                }

                if let selectedMuscle {
                    selectedMuscleDetails(selectedMuscle)
                } else if data.totalSets == 0 {
                    Label("Log sets to light up the muscle map.", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(GymTheme.textSecondary)
                }
            }
        }
    }

    private func muscleButton(_ muscle: WorkoutMuscleMetric) -> some View {
        let selected = muscle.id == selectedMuscleID
        return Button {
            selectedMuscleID = selected ? nil : muscle.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(muscle.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? GymTheme.primary : GymTheme.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(GymTheme.primary)
                            .accessibilityHidden(true)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(GymTheme.surfaceVariant)
                        Capsule()
                            .fill(muscleColor(muscle.intensity).gradient)
                            .frame(width: max(4, proxy.size.width * muscle.intensity))
                    }
                }
                .frame(height: 7)

                Text(
                    gymText(
                        "\(compactNumber(muscle.load)) load",
                        "навантаження \(compactNumber(muscle.load))",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(GymTheme.textSecondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius)
                    .fill(selected ? GymTheme.primary.opacity(0.12) : GymTheme.surface.opacity(0.52))
            )
            .overlay {
                RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius)
                    .strokeBorder(
                        selected ? GymTheme.primary.opacity(0.7) : GymTheme.outline.opacity(0.35),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(muscle.label)
        .accessibilityValue(muscleAccessibilityValue(muscle, selected: selected))
        .accessibilityHint("Shows exercise contributions for this muscle")
    }

    private var intensityByMuscle: [String: Double] {
        Dictionary(uniqueKeysWithValues: data.muscles.map { ($0.id, $0.intensity) })
    }

    private func selectedMuscleDetails(_ muscle: WorkoutMuscleMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(
                    gymText(
                        "\(muscle.label) loaded by",
                        "Навантаження для «\(muscle.label)»",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(muscleDetail(muscle))
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
            }

            if data.selectedContributions.isEmpty {
                Text("No mapped sets for this muscle in the selected period.")
                    .font(.subheadline)
                    .foregroundStyle(GymTheme.textSecondary)
            } else {
                ForEach(data.selectedContributions) { contribution in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            gymExerciseName(
                                contribution.exerciseName,
                                catalogKey: contribution.catalogKey
                            )
                        )
                            .font(.subheadline.weight(.medium))
                        Text(contributionDetail(contribution))
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GymTheme.surfaceVariant.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.top, 2)
    }

    private func muscleColor(_ intensity: Double) -> Color {
        switch intensity {
        case ..<0.34: GymTheme.secondary
        case ..<0.7: GymTheme.primary
        default: GymTheme.tertiary
        }
    }

    private func muscleDetail(_ muscle: WorkoutMuscleMetric) -> String {
        let sets = gymCount(
            muscle.setCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів"
        )
        let sessions = gymCount(
            muscle.sessionCount,
            englishOne: "session",
            englishMany: "sessions",
            ukrainianOne: "сесія",
            ukrainianFew: "сесії",
            ukrainianMany: "сесій"
        )
        return "\(sets) • \(sessions)"
    }

    private func contributionDetail(_ contribution: WorkoutExerciseContribution) -> String {
        let sets = gymCount(
            contribution.setCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів"
        )
        let sessions = gymCount(
            contribution.sessionCount,
            englishOne: "session",
            englishMany: "sessions",
            ukrainianOne: "сесія",
            ukrainianFew: "сесії",
            ukrainianMany: "сесій"
        )
        return gymText(
            "\(compactNumber(contribution.load)) load • \(sets) • \(sessions)",
            "навантаження \(compactNumber(contribution.load)) • \(sets) • \(sessions)",
            languageCode: gymCurrentLanguageCode()
        )
    }

    private func muscleAccessibilityValue(_ muscle: WorkoutMuscleMetric, selected: Bool) -> String {
        let sets = gymCount(
            muscle.setCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів"
        )
        return gymText(
            "\(compactNumber(muscle.load)) load, \(sets), \(selected ? "selected" : "not selected")",
            "навантаження \(compactNumber(muscle.load)), \(sets), \(selected ? "вибрано" : "не вибрано")",
            languageCode: gymCurrentLanguageCode()
        )
    }
}

struct WorkoutRecommendationsCard: View {
    let recommendations: [WorkoutRecommendationModel]

    var body: some View {
        GymPanel(highlighted: !recommendations.isEmpty) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recommendations")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Based on muscle load and recent training gaps.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)

                ForEach(recommendations) { recommendation in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: recommendation.id.hasPrefix("next-") ? "arrow.forward.circle.fill" : "scope")
                            .foregroundStyle(GymTheme.primary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(gymLocalized(recommendation.title))
                                .font(.subheadline.weight(.semibold))
                            Text(gymLocalized(recommendation.supporting))
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        GymInfoPill(recommendation.priority)
                    }
                    .padding(11)
                    .background(
                        GymTheme.surface.opacity(0.52),
                        in: RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: GymTheme.compactCornerRadius)
                            .strokeBorder(GymTheme.outline.opacity(0.32), lineWidth: 1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct WorkoutAchievementsCard: View {
    let achievements: [AchievementSnapshot]

    private var preview: [AchievementSnapshot] {
        let unlocked = achievements
            .filter(\.unlocked)
            .sorted { ($0.unlockedAtEpochDay ?? 0) > ($1.unlockedAtEpochDay ?? 0) }
        let locked = achievements
            .filter { !$0.unlocked }
            .sorted { progressFraction($0) > progressFraction($1) }
        return Array((unlocked + locked).prefix(4))
    }

    var body: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Achievements")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Recent unlocks and the next solo milestones.")
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)

                ForEach(preview) { achievement in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: achievement.unlocked ? "medal.fill" : "lock.fill")
                            .font(.title3)
                            .foregroundStyle(achievement.unlocked ? GymTheme.tertiary : GymTheme.textSecondary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(gymLocalized(achievement.title))
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(achievement.unlocked ? gymLocalized("Unlocked") : "+\(achievement.rewardXP) XP")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(achievement.unlocked ? GymTheme.tertiary : GymTheme.primary)
                            }
                            Text(gymLocalized(achievement.description))
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                            ProgressView(value: progressFraction(achievement))
                                .tint(achievement.unlocked ? GymTheme.tertiary : GymTheme.primary)
                            Text(achievementProgressLabel(achievement))
                                .font(.caption2)
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func progressFraction(_ achievement: AchievementSnapshot) -> Double {
        guard achievement.target > 0 else { return achievement.unlocked ? 1 : 0 }
        return min(1, max(0, achievement.progress / achievement.target))
    }

    private func achievementProgressLabel(_ achievement: AchievementSnapshot) -> String {
        let progress = min(achievement.progress, achievement.target)
        return "\(compactNumber(progress)) / \(compactNumber(achievement.target))"
    }

}

private func compactNumber(_ value: Double) -> String {
    value.formatted(
        .number
            .locale(AppLanguage(rawValue: gymCurrentLanguageCode())?.locale ?? AppLanguage.english.locale)
            .notation(.compactName)
            .precision(.fractionLength(0 ... 1))
    )
}
