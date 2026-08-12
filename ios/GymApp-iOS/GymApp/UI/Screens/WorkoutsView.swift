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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var store: WorkoutStore
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    @State private var referenceDate = Date()
    @State private var monthOffset = 0
    @State private var section: Section = .overview
    @State private var musclePeriod: WorkoutMusclePeriod = .allTime
    @State private var selectedMuscleID: String?
    @State private var historyReturnWorkoutID: UUID?
    @State private var activationGoal: TrainingGoal = .aestheticFatLoss
    @State private var activationDays = 4
    @State private var activationEffort: SmartWorkoutEffort = .standard
    @State private var activationDismissed: Bool

    private let onStartPlan: (WorkoutLaunchSeed) -> Bool
    private let onAddWorkout: (WorkoutLaunchSeed?) -> Bool
    private let hasActiveWorkout: Bool
    private let onContinueWorkout: () -> Void
    private let onOpenWorkout: (UUID) -> Void
    private let onOpenRanks: () -> Void

    public init(
        store: WorkoutStore,
        hasActiveWorkout: Bool = false,
        onStartPlan: @escaping (WorkoutLaunchSeed) -> Bool,
        onAddWorkout: @escaping (WorkoutLaunchSeed?) -> Bool,
        onContinueWorkout: @escaping () -> Void = {},
        onOpenWorkout: @escaping (UUID) -> Void,
        onOpenRanks: @escaping () -> Void
    ) {
        self.store = store
        self.hasActiveWorkout = hasActiveWorkout
        self.onStartPlan = onStartPlan
        self.onAddWorkout = onAddWorkout
        self.onContinueWorkout = onContinueWorkout
        self.onOpenWorkout = onOpenWorkout
        self.onOpenRanks = onOpenRanks
        _activationDismissed = State(
            initialValue: TrainingProfileStore().activationDismissed(
                accountStorageKey: store.accountStorageKey
            )
        )
    }

    public var body: some View {
        GymBackground {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: GymTheme.contentSpacing) {
                        if store.workoutSummaries.isEmpty {
                            screenHeader
                            if hasActiveWorkout {
                                activeFocusLens
                            } else if activationDismissed {
                                focusLens
                            } else {
                                activationPanel
                            }
                        } else {
                            screenHeader
                            if hasActiveWorkout {
                                activeFocusLens
                            } else {
                                focusLens
                            }
                            WorkoutMonthSwitcher(
                                month: selectedMonth,
                                isCurrentMonth: monthOffset == 0,
                                onPrevious: { monthOffset -= 1 },
                                onCurrent: { monthOffset = 0 },
                                onNext: { monthOffset = min(0, monthOffset + 1) }
                            )
                            sectionPicker
                            overviewContent.id(Section.overview)
                            workoutListContent.id(Section.workouts)
                        }
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
        .onAppear { referenceDate = Date() }
        .onReceive(store.objectWillChange) { _ in referenceDate = Date() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { referenceDate = Date() }
        }
    }

    private var screenHeader: some View {
        GymScreenHeader(
            title: gymText("Today", "Сьогодні", "Сегодня", languageCode: languageCode)
        ) {
            AppLanguageMenu()
        }
    }

    private var activationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            activationGoalChoiceGrid(
                title: gymText(
                    "Goal",
                    "Ціль",
                    "Цель",
                    languageCode: languageCode
                ),
                options: TrainingActivationChoices.goals,
                selection: $activationGoal,
                label: activationGoalLabel
            )

            activationChoiceRow(
                title: gymText(
                    "Days / week",
                    "Днів / тиждень",
                    "Дней / неделю",
                    languageCode: languageCode
                ),
                options: TrainingActivationChoices.days,
                selection: $activationDays,
                label: { $0.formatted() }
            )

            activationChoiceRow(
                title: gymText(
                    "Today’s effort",
                    "Навантаження сьогодні",
                    "Нагрузка сегодня",
                    languageCode: languageCode
                ),
                options: TrainingActivationChoices.efforts,
                selection: $activationEffort,
                label: \.gymDisplayName
            )

            Button(action: startActivationPlan) {
                Text(gymText(
                    "Start plan",
                    "Почати план",
                    "Начать план",
                    languageCode: languageCode
                ))
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    Color.white.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius)
                        .strokeBorder(Color.white.opacity(0.46), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Button {
                let profileStore = TrainingProfileStore()
                guard profileStore.setActivationDismissed(
                    true,
                    accountStorageKey: store.accountStorageKey
                ) else { return }
                guard onAddWorkout(nil) else {
                    profileStore.setActivationDismissed(
                        false,
                        accountStorageKey: store.accountStorageKey
                    )
                    return
                }
                activationDismissed = true
            } label: {
                Text(gymText(
                    "Skip",
                    "Пропустити",
                    "Пропустить",
                    languageCode: languageCode
                ))
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            activationLensShape.fill(GymTheme.heroGradient)
        }
        .overlay {
            activationLensShape.strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
        }
        .clipShape(activationLensShape)
        .shadow(color: GymTheme.primary.opacity(0.18), radius: 11, x: 0, y: 8)
    }

    private var activationLensShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 44,
            bottomLeadingRadius: 32,
            bottomTrailingRadius: 60,
            topTrailingRadius: 76,
            style: .continuous
        )
    }

    private func activationGoalLabel(_ goal: TrainingGoal) -> String {
        switch goal {
        case .aestheticFatLoss:
            gymText("Aesthetic Cut", "Естетика / сушка", "Эстетика/сушка", languageCode: languageCode)
        case .muscleGain:
            gymText("Muscle Gain", "Набір мʼязів", "Набор мышц", languageCode: languageCode)
        case .strength:
            gymText("Strength", "Сила", "Сила", languageCode: languageCode)
        case .balanced:
            gymText("Balanced", "Баланс", "Баланс", languageCode: languageCode)
        }
    }

    private func activationChoiceRow<Value: Hashable>(
        title: String,
        options: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.86))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        let isSelected = selection.wrappedValue == option
                        Button {
                            selection.wrappedValue = option
                        } label: {
                            Text(label(option))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(ActivationChipButtonStyle(isSelected: isSelected))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func activationGoalChoiceGrid(
        title: String,
        options: [TrainingGoal],
        selection: Binding<TrainingGoal>,
        label: @escaping (TrainingGoal) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.86))

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(label(option))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActivationChipButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func startActivationPlan() {
        let now = Date()
        referenceDate = now
        let profile = TrainingProfile.activationProfile(
            goal: activationGoal,
            workoutsPerWeek: activationDays
        )
        let plan = RecommendationEngine.buildWorkoutPlan(
            exercises: store.exercises,
            history: [],
            muscleMappings: store.muscleMappings,
            trainingProfile: profile,
            effort: activationEffort,
            now: now,
            calendar: calendar
        )
        let seed = WorkoutLaunchSeed(
            accountStorageKey: store.accountStorageKey,
            profile: profile,
            requestedEffort: activationEffort,
            plan: plan,
            catalog: store.exercises,
            history: [],
            muscleMappings: store.muscleMappings,
            createdAt: now
        )
        let committed = FirstWorkoutActivation.commit(
            seed: seed,
            accountStorageKey: store.accountStorageKey,
            catalog: store.exercises,
            muscleMappings: store.muscleMappings,
            profileStore: TrainingProfileStore(),
            now: now,
            launch: onStartPlan
        )
        if committed { activationDismissed = true }
    }

    private var trainingProfile: TrainingProfile {
        TrainingProfileStore().load(accountStorageKey: store.accountStorageKey)
    }

    private func weeklyGuidance(at now: Date) -> WeeklyTrainingGuidance {
        RecommendationEngine.weeklyTrainingGuidance(
            history: store.allExerciseHistory(),
            trainingProfile: trainingProfile,
            latestFeedback: store.latestWorkoutFeedbackContext(now: now),
            now: now,
            calendar: calendar
        )
    }

    private func makeTodayLaunchSeed(
        guidance: WeeklyTrainingGuidance,
        now: Date
    ) -> WorkoutLaunchSeed? {
        let effort: SmartWorkoutEffort = guidance.decision == .train ? .auto : .recovery
        let history = store.allExerciseHistory()
        let plan = RecommendationEngine.buildWorkoutPlan(
            exercises: store.exercises,
            history: history,
            muscleMappings: store.muscleMappings,
            trainingProfile: trainingProfile,
            effort: effort,
            latestFeedback: store.latestWorkoutFeedbackContext(now: now),
            now: now,
            calendar: calendar
        )
        guard !plan.exercises.isEmpty else { return nil }
        return WorkoutLaunchSeed(
            accountStorageKey: store.accountStorageKey,
            profile: trainingProfile,
            requestedEffort: effort,
            plan: plan,
            catalog: store.exercises,
            history: history,
            muscleMappings: store.muscleMappings,
            createdAt: now
        )
    }

    private func todayTitle(
        guidance: WeeklyTrainingGuidance,
        plan: SmartWorkoutPlan?
    ) -> String {
        if guidance.decision == .rest {
            return gymText(
                "Rest today",
                "Сьогодні відпочинок",
                "Сегодня отдых",
                languageCode: languageCode
            )
        }
        return plan?.focus.displayName ?? gymText(
            "Start workout",
            "Почати тренування",
            "Начать тренировку",
            languageCode: languageCode
        )
    }

    private func todayPrimaryActionTitle(
        guidance: WeeklyTrainingGuidance,
        hasRecommendedPlan: Bool
    ) -> String {
        guard hasRecommendedPlan else {
            return gymText(
                "Start workout",
                "Почати тренування",
                "Начать тренировку",
                languageCode: languageCode
            )
        }
        return guidance.decision == .rest
            ? gymText("Train anyway", "Усе одно тренуватися", "Всё равно тренироваться", languageCode: languageCode)
            : gymText(
                "Start plan",
                "Почати план",
                "Начать план",
                languageCode: languageCode
            )
    }

    private var focusLens: some View {
        let guidance = weeklyGuidance(at: referenceDate)
        let launchSeed = makeTodayLaunchSeed(guidance: guidance, now: referenceDate)
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(gymText(
                    todayTitle(guidance: guidance, plan: launchSeed?.plan),
                    todayTitle(guidance: guidance, plan: launchSeed?.plan),
                    todayTitle(guidance: guidance, plan: launchSeed?.plan),
                    languageCode: languageCode
                ))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            }

            weeklyRhythmMetric(guidance)

            focusActionButtons(launchSeed: launchSeed, guidance: guidance)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .leading)
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

    private var activeFocusLens: some View {
        let guidance = weeklyGuidance(at: referenceDate)
        return VStack(alignment: .leading, spacing: 22) {
            Text(gymText(
                "Continue workout",
                "Продовжити тренування",
                "Продолжить тренировку",
                languageCode: languageCode
            ))
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .tracking(-0.8)
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

            weeklyRhythmMetric(guidance)

            Button(action: onContinueWorkout) {
                Label(
                    gymText(
                        "Continue workout",
                        "Продовжити тренування",
                        "Продолжить тренировку",
                        languageCode: languageCode
                    ),
                    systemImage: "play.fill"
                )
                .font(.subheadline.bold())
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.2), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.36), lineWidth: 1) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background { activationLensShape.fill(GymTheme.heroGradient) }
        .clipShape(activationLensShape)
        .shadow(color: GymTheme.primary.opacity(0.24), radius: 24, x: 0, y: 14)
    }

    private func weeklyRhythmMetric(_ guidance: WeeklyTrainingGuidance) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(gymText(
                "\(guidance.completedTrainingDays) / \(guidance.targetTrainingDays) days",
                "\(guidance.completedTrainingDays) / \(guidance.targetTrainingDays) днів",
                "\(guidance.completedTrainingDays) / \(guidance.targetTrainingDays) дней",
                languageCode: languageCode
            ))
            .font(.title3.bold().monospacedDigit())
            Text(gymText(
                "Weekly rhythm",
                "Ритм тижня",
                "Ритм недели",
                languageCode: languageCode
            ))
            .font(.caption)
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func focusActionButtons(
        launchSeed: WorkoutLaunchSeed?,
        guidance: WeeklyTrainingGuidance
    ) -> some View {
        VStack(spacing: 10) {
            if let launchSeed {
                focusActionButton(
                    title: todayPrimaryActionTitle(
                        guidance: guidance,
                        hasRecommendedPlan: true
                    ),
                    systemImage: "play.fill",
                    primary: true,
                    accessibilityHint: gymText(
                        "Starts this exact plan now",
                        "Одразу починає цей точний план",
                        "Сразу начинает этот точный план",
                        languageCode: languageCode
                    )
                ) {
                    referenceDate = Date()
                    _ = onStartPlan(launchSeed)
                }

                focusActionButton(
                    title: gymText(
                        "Edit plan",
                        "Редагувати план",
                        "Редактировать план",
                        languageCode: languageCode
                    ),
                    systemImage: "pencil",
                    primary: false,
                    accessibilityHint: gymText(
                        "Opens this plan in the editor",
                        "Відкриває цей план у редакторі",
                        "Открывает этот план в редакторе",
                        languageCode: languageCode
                    )
                ) {
                    referenceDate = Date()
                    _ = onAddWorkout(launchSeed)
                }
            } else {
                focusActionButton(
                    title: todayPrimaryActionTitle(
                        guidance: guidance,
                        hasRecommendedPlan: false
                    ),
                    systemImage: "plus",
                    primary: true,
                    accessibilityHint: gymText(
                        "Opens a blank workout plan",
                        "Відкриває порожній план тренування",
                        "Открывает пустой план тренировки",
                        languageCode: languageCode
                    )
                ) {
                    referenceDate = Date()
                    _ = onAddWorkout(nil)
                }
            }
        }
    }

    @ViewBuilder
    private func focusActionButton(
        title: String,
        systemImage: String,
        primary: Bool,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: primary ? 54 : 48)
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)

        if !primary {
            button
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.36), lineWidth: 1) }
        } else if reduceTransparency {
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
            weeklyStreakWeeks: weeklyStreakWeeks,
            weeklyTarget: trainingProfile.workoutsPerWeek,
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

    }

    @ViewBuilder
    private var workoutListContent: some View {
        GymPanel(highlighted: true) {
            HStack(alignment: .center, spacing: 12) {
                Text("Saved workouts")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
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
                    Button("Add workout") { _ = onAddWorkout(nil) }
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

    private var gamification: GamificationSnapshot {
        store.gamificationSnapshot(now: referenceDate, calendar: calendar)
    }

    private var monthXP: Int {
        monthWorkouts.reduce(0) { $0 + GamificationEngine.xpForSession($1) }
    }

    private var weeklyStreakWeeks: Int {
        WeeklyStreakCalculator.current(
            sessions: store.workoutSummaries,
            targetTrainingDays: trainingProfile.workoutsPerWeek,
            now: referenceDate,
            calendar: calendar
        )
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

private struct ActivationChipButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color(red: 0.04, green: 0.15, blue: 0.29) : Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                isSelected ? Color(red: 0.88, green: 0.98, blue: 0.96) : Color.clear,
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    isSelected ? Color(red: 0.88, green: 0.98, blue: 0.96) : Color.white.opacity(0.58),
                    lineWidth: 1
                )
            }
            .brightness(configuration.isPressed ? -0.04 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
    }
}
