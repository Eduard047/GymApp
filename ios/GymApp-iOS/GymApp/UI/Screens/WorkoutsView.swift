/*
THESIS: Focus Lens puts today's workout in one fluid focal form and refuses the stacked-dashboard default.
OWN-WORLD: Airy canvas, aquatic contextual color, continuous curves, solid content rows, and one Liquid Glass control layer.
STORY: See the next useful action, understand its size and weekly rhythm, start it, then review recent work without changing modes.
FIRST VIEWPORT: A large asymmetric lens leads; core facts sit inside it and the start capsule attaches near thumb reach, followed by progressive analytics.
FORM: User-selected Focus Lens from Fluid Focus; seed af1a1dee. iOS keeps native TabView, NavigationStack, Dynamic Type, Reduce Transparency, and system materials.
*/
import SwiftUI

@MainActor
public struct WorkoutsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case workouts = "Workout list"

        var id: Self { self }
    }

    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var store: WorkoutStore
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue

    @State private var referenceDate = Date()
    @State private var monthOffset = 0
    @State private var section: Section = .overview
    @State private var musclePeriod: WorkoutMusclePeriod = .allTime
    @State private var selectedMuscleID: String?
    @State private var historyReturnWorkoutID: UUID?

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
                    LazyVStack(spacing: GymTheme.contentSpacing) {
                        screenHeader

                        focusLens

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
                    .padding(.horizontal, GymTheme.screenHorizontalInset)
                    .padding(.top, GymTheme.screenVerticalInset)
                    .padding(.bottom, GymTheme.screenBottomInset)
                }
                .scrollIndicators(.hidden)
                .onChange(of: section) { newSection in
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
                        proxy.scrollTo(newSection, anchor: .top)
                    }
                }
                .onAppear {
                    guard let historyReturnWorkoutID else { return }
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(historyReturnWorkoutID, anchor: .center)
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
    }

    private var screenHeader: some View {
        GymScreenHeader(
            title: "Workouts",
            supporting: "Your training history and next best move."
        ) {
            AppLanguageMenu()
        }
    }

    private var focusLens: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(gymText(
                    "YOUR NEXT MOVE",
                    "ТВІЙ НАСТУПНИЙ КРОК",
                    "ТВОЙ СЛЕДУЮЩИЙ ШАГ",
                    languageCode: languageCode
                ))
                .font(.caption2.bold())
                .tracking(0.9)
                .foregroundStyle(Color.white.opacity(0.74))

                Text(gymText(
                    "Build today’s session",
                    "Склади тренування на сьогодні",
                    "Составь тренировку на сегодня",
                    languageCode: languageCode
                ))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

                Text(gymText(
                    "Ready when you are. Start simple and shape the workout as you go.",
                    "Починай, коли готовий. Складай тренування поступово, у своєму темпі.",
                    "Начинай, когда будешь готов. Собирай тренировку постепенно, в своём темпе.",
                    languageCode: languageCode
                ))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 14) {
                focusMetric(
                    value: "\(dashboardStats.workoutCount)",
                    label: gymText("Workouts", "Тренувань", "Тренировок", languageCode: languageCode)
                )
                focusMetric(
                    value: "\(dashboardStats.weeklyStreakWeeks)",
                    label: gymText("Week streak", "Тижні серії", "Серия недель", languageCode: languageCode)
                )
                focusMetric(
                    value: formattedMetric(dashboardStats.totalVolume),
                    label: gymText("Volume", "Обсяг", "Объём", languageCode: languageCode)
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: GymTheme.Spacing.medium) {
                    focusRhythmSummary
                    Spacer(minLength: GymTheme.Spacing.small)
                    focusActionButton
                }

                VStack(alignment: .leading, spacing: GymTheme.Spacing.large) {
                    focusRhythmSummary
                    focusActionButton
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 350, alignment: .leading)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 44,
                bottomLeadingRadius: 30,
                bottomTrailingRadius: 60,
                topTrailingRadius: 76,
                style: .continuous
            )
            .fill(GymTheme.heroGradient)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 44,
                bottomLeadingRadius: 30,
                bottomTrailingRadius: 60,
                topTrailingRadius: 76,
                style: .continuous
            )
        )
        .shadow(color: GymTheme.primary.opacity(0.24), radius: 24, x: 0, y: 14)
    }

    private var focusRhythmSummary: some View {
        VStack(alignment: .leading, spacing: GymTheme.Spacing.small) {
            Text(
                selectedMonth.formatted(
                    .dateTime
                        .month(.wide)
                        .year()
                        .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                )
            )
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.72))
            weeklyRhythm
        }
    }

    private func focusMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var weeklyRhythm: some View {
        let today = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let activeDays = Set(store.workoutSummaries.map { calendar.startOfDay(for: $0.date) })
        return HStack(spacing: 7) {
            ForEach(0 ..< 7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                Circle()
                    .fill(activeDays.contains(day) ? Color(red: 0.49, green: 0.94, blue: 0.78) : Color.white.opacity(0.28))
                    .frame(width: 9, height: 9)
                    .overlay {
                        if calendar.isDate(day, inSameDayAs: today) {
                            Circle().stroke(Color.white.opacity(0.42), lineWidth: 2).padding(-3)
                        }
                    }
                    .accessibilityLabel(gymFormattedDate(day, date: .long, time: .omitted))
                    .accessibilityValue(
                        activeDays.contains(day)
                            ? gymText(
                                "Workout completed",
                                "Тренування завершено",
                                "Тренировка завершена",
                                languageCode: languageCode
                            )
                            : gymText(
                                "No workout",
                                "Немає тренування",
                                "Нет тренировки",
                                languageCode: languageCode
                            )
                    )
            }
        }
    }

    @ViewBuilder
    private var focusActionButton: some View {
        let button = Button(action: onAddWorkout) {
            Label(
                gymText("Start workout", "Почати тренування", "Начать тренировку", languageCode: languageCode),
                systemImage: "plus"
            )
            .font(.subheadline.bold())
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityHint(gymLocalized("Starts a new workout entry"))

        if reduceTransparency {
            button
                .background(Color.white.opacity(0.24), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.36), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            button.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            button
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.32), lineWidth: 1) }
        }
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
                GymContentUnavailableView {
                    Label("No workouts this month", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Use Add workout when you are ready to log your first session.")
                } actions: {
                    Button("Add workout", action: onAddWorkout)
                        .buttonStyle(GymPrimaryButtonStyle())
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
                    historyReturnWorkoutID = workout.workoutID
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
                        "Тренировка за \(gymFormattedDate(workout.date, date: .long, time: .omitted))",
                        languageCode: languageCode
                    )
                )
                .accessibilityValue(
                    workoutAccessibilityValue(workout)
                )
                .accessibilityHint("Opens workout details")

            }
        }
        .id(workout.workoutID)
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
                .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
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
            "\(exercises), \(sets), объём \(formattedMetric(workout.totalVolume))",
            languageCode: languageCode
        )
    }
}
