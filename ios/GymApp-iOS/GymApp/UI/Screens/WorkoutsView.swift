import SwiftUI

@MainActor
public struct WorkoutsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case workouts = "Workout list"

        var id: Self { self }
    }

    private enum ActiveAlert: Identifiable {
        case delete(WorkoutSessionSummary)
        case error(String)

        var id: String {
            switch self {
            case let .delete(workout): "delete-\(workout.id.uuidString)"
            case let .error(message): "error-\(message)"
            }
        }
    }

    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store: WorkoutStore

    @State private var referenceDate = Date()
    @State private var monthOffset = 0
    @State private var section: Section = .overview
    @State private var musclePeriod: WorkoutMusclePeriod = .allTime
    @State private var selectedMuscleID: String?
    @State private var activeAlert: ActiveAlert?

    private let onAddWorkout: () -> Void
    private let onOpenWorkout: (UUID) -> Void
    private let onOpenRanks: () -> Void

    public init(
        store: WorkoutStore,
        onAddWorkout: @escaping () -> Void,
        onOpenWorkout: @escaping (UUID) -> Void,
        onOpenRanks: @escaping () -> Void
    ) {
        self.store = store
        self.onAddWorkout = onAddWorkout
        self.onOpenWorkout = onOpenWorkout
        self.onOpenRanks = onOpenRanks
    }

    public var body: some View {
        GymBackground {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        screenHeader

                        WorkoutMonthSwitcher(
                            month: selectedMonth,
                            isCurrentMonth: monthOffset == 0,
                            onPrevious: { monthOffset -= 1 },
                            onCurrent: { monthOffset = 0 },
                            onNext: { monthOffset = min(0, monthOffset + 1) }
                        )

                        sectionPicker

                            overviewContent
                                .id(Section.overview)

                            workoutListContent
                                .id(Section.workouts)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .onChange(of: section) { _, newSection in
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
                        proxy.scrollTo(newSection, anchor: .top)
                    }
                }
                .task {
#if DEBUG
                    guard let anchor = screenshotSectionAnchor else { return }
                    await Task.yield()
                    proxy.scrollTo(anchor, anchor: .top)
#endif
                }
            }
        }
        .alert(item: $activeAlert, content: makeAlert)
    }

    private var screenHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                headerCopy
                Spacer(minLength: 8)
                addWorkoutButton
                    .fixedSize(horizontal: true, vertical: false)
                AppLanguageMenu()
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    headerCopy
                    Spacer(minLength: 8)
                    AppLanguageMenu()
                }
                addWorkoutButton
            }
        }
        .padding(.top, 8)
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Workouts")
                .font(.largeTitle.bold())
                .foregroundStyle(GymTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Your training history and next best move.")
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
        }
    }

    private var addWorkoutButton: some View {
        Button(action: onAddWorkout) {
            Label("Add workout", systemImage: "plus")
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .accessibilityHint("Starts a new workout entry")
    }

    private var sectionPicker: some View {
        GymPanel(
            contentPadding: EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        ) {
            Picker("Workout section", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(sectionLabel(section)).tag(section)
                }
            }
            .pickerStyle(.segmented)
        }
    }

#if DEBUG
    private var screenshotSectionAnchor: String? {
        let requested = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--screenshot-section=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
        switch requested {
        case "heatmap": return "activity-heatmap"
        case "muscles": return "muscle-map"
        default: return nil
        }
    }
#endif

    @ViewBuilder
    private var overviewContent: some View {
        WorkoutProgressHero(
            snapshot: gamification,
            monthXP: monthXP,
            onOpenRanks: onOpenRanks
        )

        WorkoutKPICard(stats: dashboardStats)

        WorkoutActivityHeatmap(
            month: selectedMonth,
            sessions: store.workoutSummaries,
            now: referenceDate,
            calendar: calendar
        )
        .id("activity-heatmap")

        WorkoutMuscleLoadCard(
            period: $musclePeriod,
            selectedMuscleID: $selectedMuscleID,
            data: muscleDashboardData
        )
        .id("muscle-map")

        WorkoutRecommendationsCard(recommendations: trainingRecommendations)

        WorkoutAchievementsCard(achievements: gamification.achievements)
    }

    @ViewBuilder
    private var workoutListContent: some View {
        GymPanel(highlighted: true) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved workouts")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        gymLocalized(monthWorkouts.isEmpty
                            ? "Add a session to start this month."
                            : "Open a workout for its exercises and sets.")
                    )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                }
                Spacer(minLength: 8)
                GymInfoPill(
                    gymCount(
                        monthWorkouts.count,
                        englishOne: "session",
                        englishMany: "sessions",
                        ukrainianOne: "сесія",
                        ukrainianFew: "сесії",
                        ukrainianMany: "сесій"
                    ),
                    systemImage: "list.bullet"
                )
            }
        }

        if monthWorkouts.isEmpty {
            GymPanel {
                ContentUnavailableView {
                    Label("No workouts this month", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Use Add workout when you are ready to log your first session.")
                } actions: {
                    Button("Add workout", action: onAddWorkout)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ForEach(monthWorkouts) { workout in
                workoutCard(workout)
            }
        }
    }

    private func workoutCard(_ workout: WorkoutSessionSummary) -> some View {
        GymPanel(highlighted: true) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    onOpenWorkout(workout.workoutID)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(gymFormattedDate(workout.date, date: .abbreviated, time: .omitted))
                                .font(.headline)
                                .foregroundStyle(GymTheme.textPrimary)
                            Spacer(minLength: 4)
                            GymInfoPill(
                                gymCount(
                                    workout.setCount,
                                    englishOne: "set",
                                    englishMany: "sets",
                                    ukrainianOne: "підхід",
                                    ukrainianFew: "підходи",
                                    ukrainianMany: "підходів"
                                )
                            )
                        }

                        Text(workoutNote(workout))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                workoutStat(
                                    label: "Exercises",
                                    value: workout.exerciseCount.formatted()
                                )
                                workoutStat(label: "Sets", value: workout.setCount.formatted())
                                workoutStat(
                                    label: "Volume",
                                    value: formattedMetric(workout.totalVolume)
                                )
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                workoutStat(
                                    label: "Exercises",
                                    value: workout.exerciseCount.formatted()
                                )
                                workoutStat(label: "Sets", value: workout.setCount.formatted())
                                workoutStat(
                                    label: "Volume",
                                    value: formattedMetric(workout.totalVolume)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    gymText(
                        "Workout on \(gymFormattedDate(workout.date, date: .long, time: .omitted))",
                        "Тренування за \(gymFormattedDate(workout.date, date: .long, time: .omitted))",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
                .accessibilityValue(
                    workoutAccessibilityValue(workout)
                )
                .accessibilityHint("Opens workout details")

                Button(role: .destructive) {
                    activeAlert = .delete(workout)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 38, height: 38)
                        .background(GymTheme.error.opacity(0.1), in: Circle())
                }
                .foregroundStyle(GymTheme.error)
                .accessibilityLabel(
                    gymText(
                        "Delete workout from \(gymFormattedDate(workout.date, date: .long, time: .omitted))",
                        "Видалити тренування за \(gymFormattedDate(workout.date, date: .long, time: .omitted))",
                        languageCode: gymCurrentLanguageCode()
                    )
                )
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                activeAlert = .delete(workout)
            } label: {
                Label("Delete workout", systemImage: "trash")
            }
        }
    }

    private func workoutStat(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(gymLocalized(label))
                .foregroundStyle(GymTheme.textSecondary)
            Text(value)
                .foregroundStyle(GymTheme.textPrimary)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var selectedMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: referenceDate) ?? referenceDate
    }

    private var selectedMonthInterval: DateInterval {
        calendar.dateInterval(of: .month, for: selectedMonth) ??
            DateInterval(start: calendar.startOfDay(for: selectedMonth), duration: 1)
    }

    private var monthWorkouts: [WorkoutSessionSummary] {
        store.workoutSummaries.filter { selectedMonthInterval.contains($0.date) }
    }

    private var dashboardStats: DashboardStats {
        store.dashboardStats(
            from: selectedMonthInterval.start,
            through: selectedMonthInterval.end.addingTimeInterval(-0.001),
            now: referenceDate,
            calendar: calendar
        )
    }

    private var gamification: GamificationSnapshot {
        store.gamificationSnapshot(now: referenceDate, calendar: calendar)
    }

    private var monthXP: Int {
        monthWorkouts.reduce(0) { $0 + GamificationEngine.xpForSession($1) }
    }

    private var periodHistory: [ExerciseHistoryEntry] {
        WorkoutDashboardDataBuilder.filteredHistory(
            store.allExerciseHistory(),
            for: musclePeriod,
            now: referenceDate,
            calendar: calendar
        )
    }

    private var muscleDashboardData: WorkoutMuscleDashboardData {
        WorkoutDashboardDataBuilder.muscleData(
            history: periodHistory,
            mappings: store.muscleMappings,
            selectedMuscleID: selectedMuscleID
        )
    }

    private var trainingRecommendations: [WorkoutRecommendationModel] {
        WorkoutDashboardDataBuilder.recommendations(
            history: store.allExerciseHistory(),
            mappings: store.muscleMappings,
            now: referenceDate,
            calendar: calendar
        )
    }

    private func sectionLabel(_ section: Section) -> String {
        switch section {
        case .overview:
            return gymLocalized("Overview")
        case .workouts:
            return gymText(
                "List (\(monthWorkouts.count))",
                "Список (\(monthWorkouts.count))",
                languageCode: gymCurrentLanguageCode()
            )
        }
    }

    private func workoutNote(_ workout: WorkoutSessionSummary) -> String {
        guard let note = workout.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else {
            return gymLocalized("No note")
        }
        return note
    }

    private func formattedMetric(_ value: Double) -> String {
        value.formatted(
            .number
                .locale(AppLanguage(rawValue: gymCurrentLanguageCode())?.locale ?? AppLanguage.english.locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func makeAlert(_ alert: ActiveAlert) -> Alert {
        switch alert {
        case let .delete(workout):
            return Alert(
                title: Text("Delete workout?"),
                message: Text(
                    gymCurrentLanguageCode() == "ru"
                        ? "Тренировка за \(gymFormattedDate(workout.date, date: .long, time: .omitted)) и все её подходы будут удалены с этого устройства."
                        : gymText(
                            "The workout from \(gymFormattedDate(workout.date, date: .long, time: .omitted)) and all of its sets will be removed from this device.",
                            "Тренування за \(gymFormattedDate(workout.date, date: .long, time: .omitted)) і всі його підходи буде видалено з цього пристрою.",
                            languageCode: gymCurrentLanguageCode()
                        )
                ),
                primaryButton: .destructive(Text("Delete")) {
                    deleteWorkout(workout)
                },
                secondaryButton: .cancel()
            )
        case let .error(message):
            return Alert(
                title: Text("Couldn’t delete workout"),
                message: Text(gymLocalized(message)),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func deleteWorkout(_ workout: WorkoutSessionSummary) {
        do {
            try store.deleteWorkout(id: workout.workoutID)
        } catch {
            activeAlert = .error(gymErrorMessage(error))
        }
    }

    private func workoutAccessibilityValue(_ workout: WorkoutSessionSummary) -> String {
        let exercises = gymCount(
            workout.exerciseCount,
            englishOne: "exercise",
            englishMany: "exercises",
            ukrainianOne: "вправа",
            ukrainianFew: "вправи",
            ukrainianMany: "вправ"
        )
        let sets = gymCount(
            workout.setCount,
            englishOne: "set",
            englishMany: "sets",
            ukrainianOne: "підхід",
            ukrainianFew: "підходи",
            ukrainianMany: "підходів"
        )
        return gymText(
            "\(exercises), \(sets), \(formattedMetric(workout.totalVolume)) volume",
            "\(exercises), \(sets), обсяг \(formattedMetric(workout.totalVolume))",
            languageCode: gymCurrentLanguageCode()
        )
    }
}
