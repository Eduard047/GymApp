/*
THESIS: Focus Lens puts today's workout in one fluid focal form and refuses the stacked-dashboard default.
OWN-WORLD: Airy canvas, aquatic contextual color, continuous curves, solid content rows, and one Liquid Glass control layer.
STORY: See the next useful action, understand its size and weekly rhythm, start it, then review recent work without changing modes.
FIRST VIEWPORT: A large asymmetric lens leads; core facts sit inside it and the start capsule attaches near thumb reach, followed by progressive analytics.
FORM: User-selected Focus Lens from Fluid Focus; seed af1a1dee. iOS keeps native TabView, NavigationStack, Dynamic Type, Reduce Transparency, and system materials.
*/
import SwiftUI

private let maximumTodayHeroVolume = 1_000_000_000_000_000.0

struct TodayHeroMetrics: Equatable {
    let totalWorkouts: Int
    let weeklyStreakWeeks: Int
    let totalVolume: Double

    init(sessions: [WorkoutSessionSummary], weeklyStreakWeeks: Int) {
        totalWorkouts = sessions.count
        self.weeklyStreakWeeks = max(0, weeklyStreakWeeks)
        totalVolume = sessions.reduce(0.0) { running, session in
            guard session.totalVolume.isFinite, session.totalVolume >= 0 else { return running }
            return min(maximumTodayHeroVolume, running + session.totalVolume)
        }
    }
}

enum TodayFocusPlanMetrics {
    static func estimatedMinutes(exerciseCount: Int, setCount: Int) -> Int {
        min(90, max(10, exerciseCount * 3 + setCount * 2))
    }
}

struct WeeklyTrainingSummary: Equatable {
    let weekStart: Date
    let completedSessionCount: Int
    let completedTrainingDays: Set<Int64>
    let totalMinutes: Int
    let totalVolume: Double

    init(
        sessions: [WorkoutSessionSummary],
        now: Date,
        calendar: Calendar
    ) {
        let start = calendar.gymMondayStart(of: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start)
            ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        let weeklySessions = sessions.filter { session in
            session.date >= start && session.date < end && session.date <= now
        }

        weekStart = start
        completedSessionCount = weeklySessions.count
        completedTrainingDays = Set(
            weeklySessions.map { calendar.gymEpochDay(for: $0.date) }
        )
        totalMinutes = weeklySessions.reduce(0) { running, session in
            let minutes = Self.durationMinutes(for: session)
            guard running <= Int.max - minutes else { return Int.max }
            return running + minutes
        }
        totalVolume = weeklySessions.reduce(0.0) { running, session in
            guard session.totalVolume.isFinite, session.totalVolume >= 0 else { return running }
            return min(maximumTodayHeroVolume, running + session.totalVolume)
        }
    }

    func hasWorkout(on date: Date, calendar: Calendar) -> Bool {
        completedTrainingDays.contains(calendar.gymEpochDay(for: date))
    }

    func hasCompletedWorkoutToday(now: Date, calendar: Calendar) -> Bool {
        hasWorkout(on: now, calendar: calendar)
    }

    static func durationMinutes(for session: WorkoutSessionSummary) -> Int {
        if let seconds = session.durationSeconds,
           (0 ... 7 * 24 * 60 * 60).contains(seconds) {
            return Int((seconds + 59) / 60)
        }
        if let seconds = GarminWorkoutNoteParser.parse(session.note)?.durationSeconds,
           seconds > 0 {
            return Int((seconds + 59) / 60)
        }
        return TodayFocusPlanMetrics.estimatedMinutes(
            exerciseCount: session.exerciseCount,
            setCount: session.setCount
        )
    }
}

struct TodayScreenProjection {
    let accountStorageKey: String
    let trainingProfile: TrainingProfile
    let weeklyGuidance: WeeklyTrainingGuidance
    let weeklySummary: WeeklyTrainingSummary
    let launchSeed: WorkoutLaunchSeed?
    let heroMetrics: TodayHeroMetrics
    let monthWorkouts: [WorkoutSessionSummary]
}

@MainActor
final class TodayScreenProjectionCache: ObservableObject {
    private struct Key: Equatable {
        let storeIdentity: ObjectIdentifier
        let accountStorageKey: String
        let derivedDataRevision: UInt64
        let referenceDate: Date
        let calendar: Calendar
        let trainingProfile: TrainingProfile
        let monthOffset: Int
    }

    private var cached: (key: Key, projection: TodayScreenProjection)?
    private(set) var buildCount = 0

    func projection(
        store: WorkoutStore,
        referenceDate: Date,
        calendar: Calendar,
        trainingProfile: TrainingProfile,
        monthOffset: Int
    ) -> TodayScreenProjection {
        let key = Key(
            storeIdentity: ObjectIdentifier(store),
            accountStorageKey: store.accountStorageKey,
            derivedDataRevision: store.derivedDataRevision,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: trainingProfile,
            monthOffset: monthOffset
        )
        if let cached, cached.key == key {
            return cached.projection
        }

        let sessions = store.workoutSummaries
        let history = store.allExerciseHistory()
        let latestFeedback = store.latestWorkoutFeedbackContext(now: referenceDate)
        let weeklySummary = WeeklyTrainingSummary(
            sessions: sessions,
            now: referenceDate,
            calendar: calendar
        )
        let weeklyGuidance = RecommendationEngine.weeklyTrainingGuidance(
            history: history,
            trainingProfile: trainingProfile,
            latestFeedback: latestFeedback,
            now: referenceDate,
            calendar: calendar
        )
        let launchSeed: WorkoutLaunchSeed?
        if weeklySummary.hasCompletedWorkoutToday(now: referenceDate, calendar: calendar) {
            launchSeed = nil
        } else {
            let effort: SmartWorkoutEffort = weeklyGuidance.decision == .train
                ? .auto
                : .recovery
            let plan = RecommendationEngine.buildWorkoutPlan(
                exercises: store.exercises,
                history: history,
                muscleMappings: store.muscleMappings,
                trainingProfile: trainingProfile,
                effort: effort,
                latestFeedback: latestFeedback,
                now: referenceDate,
                calendar: calendar
            )
            launchSeed = plan.exercises.isEmpty ? nil : WorkoutLaunchSeed(
                accountStorageKey: store.accountStorageKey,
                profile: trainingProfile,
                requestedEffort: effort,
                plan: plan,
                catalog: store.exercises,
                history: history,
                muscleMappings: store.muscleMappings,
                createdAt: referenceDate
            )
        }

        let weeklyStreakWeeks = WeeklyStreakCalculator.current(
            sessions: sessions,
            targetTrainingDays: trainingProfile.workoutsPerWeek,
            now: referenceDate,
            calendar: calendar
        )
        let selectedMonth = calendar.date(
            byAdding: .month,
            value: monthOffset,
            to: referenceDate
        ) ?? referenceDate
        let selectedMonthInterval = calendar.dateInterval(of: .month, for: selectedMonth)
            ?? DateInterval(start: calendar.startOfDay(for: selectedMonth), duration: 1)
        let projection = TodayScreenProjection(
            accountStorageKey: store.accountStorageKey,
            trainingProfile: trainingProfile,
            weeklyGuidance: weeklyGuidance,
            weeklySummary: weeklySummary,
            launchSeed: launchSeed,
            heroMetrics: TodayHeroMetrics(
                sessions: sessions,
                weeklyStreakWeeks: weeklyStreakWeeks
            ),
            monthWorkouts: sessions.filter { selectedMonthInterval.contains($0.date) }
        )
        buildCount += 1
        cached = (key, projection)
        return projection
    }
}

@MainActor
public struct WorkoutsView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store: WorkoutStore
    @StateObject private var projectionCache = TodayScreenProjectionCache()
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    @State private var referenceDate = Date()
    @State private var monthOffset = 0
    @State private var historyReturnWorkoutID: UUID?
    @State private var activationGoal: TrainingGoal = .aestheticFatLoss
    @State private var activationDays = 4
    @State private var activationEffort: SmartWorkoutEffort = .standard
    @State private var activationDismissed: Bool
    @State private var showsFocusDetails = false
    @State private var showsActiveFocusDetails = false
    @State private var showsActiveMoreActions = false
    @State private var showsActivationOptions = false

    private let onStartPlan: (WorkoutLaunchSeed) -> Bool
    private let onAddWorkout: (WorkoutLaunchSeed?) -> Bool
    private let hasRetainedWorkoutDraft: Bool
    private let activeWorkoutDraft: ActiveWorkoutDraft?
    private let onContinueWorkout: () -> Void
    private let onDiscardWorkout: () -> Void
    private let tracksTutorialPrimaryActionFrame: Bool
    private let onTutorialPrimaryActionFrameChange: @MainActor (CGRect?) -> Void
    private let onOpenWorkout: (UUID) -> Void
    private let onOpenRanks: () -> Void

    init(
        store: WorkoutStore,
        activeWorkoutDraft: ActiveWorkoutDraft? = nil,
        hasRetainedWorkoutDraft: Bool = false,
        onStartPlan: @escaping (WorkoutLaunchSeed) -> Bool,
        onAddWorkout: @escaping (WorkoutLaunchSeed?) -> Bool,
        onContinueWorkout: @escaping () -> Void = {},
        onDiscardWorkout: @escaping () -> Void = {},
        tracksTutorialPrimaryActionFrame: Bool = false,
        onTutorialPrimaryActionFrameChange: @escaping @MainActor (CGRect?) -> Void = { _ in },
        onOpenWorkout: @escaping (UUID) -> Void,
        onOpenRanks: @escaping () -> Void
    ) {
        self.store = store
        self.activeWorkoutDraft = activeWorkoutDraft
        self.hasRetainedWorkoutDraft = hasRetainedWorkoutDraft
        self.onStartPlan = onStartPlan
        self.onAddWorkout = onAddWorkout
        self.onContinueWorkout = onContinueWorkout
        self.onDiscardWorkout = onDiscardWorkout
        self.tracksTutorialPrimaryActionFrame = tracksTutorialPrimaryActionFrame
        self.onTutorialPrimaryActionFrameChange = onTutorialPrimaryActionFrameChange
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
                        screenHeader {
                            proxy.scrollTo("workout-history", anchor: .top)
                        }
                        if activeWorkoutDraft != nil {
                            activeFocusLens
                        } else if store.workoutSummaries.isEmpty, !activationDismissed {
                            activationPanel
                        } else {
                            focusLens
                        }
                        if !store.workoutSummaries.isEmpty {
                            workoutListContent
                        }
                    }
                    .padding(.horizontal, GymTheme.screenHorizontalInset)
                    .padding(.top, GymTheme.screenVerticalInset)
                    .padding(.bottom, GymTheme.screenBottomInset)
                }
                .scrollIndicators(.hidden)
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

    private func screenHeader(onHistory: @escaping () -> Void) -> some View {
        GymScreenHeader(
            title: gymText("Today", "Сьогодні", "Сегодня", languageCode: languageCode)
        ) {
            HStack(spacing: 8) {
                if !store.workoutSummaries.isEmpty {
                    Button(action: onHistory) {
                        Label(
                            gymText("History", "Історія", "История", languageCode: languageCode),
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                AppLanguageMenu()
            }
        }
    }

    private var activationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasRetainedWorkoutDraft {
                VStack(alignment: .leading, spacing: 6) {
                    Text(gymText(
                        "Saved plan",
                        "Збережений план",
                        "Сохранённый план",
                        languageCode: languageCode
                    ))
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.76))
                    Text(gymText(
                        "Continue your plan",
                        "Продовж свій план",
                        "Продолжи свой план",
                        languageCode: languageCode
                    ))
                    .font(.title2.bold())
                    .foregroundStyle(Color.white)
                }
                continueRetainedPlanAction
                    .appTutorialPrimaryActionTarget()
                    .appTutorialPrimaryActionFrame(
                        isEnabled: tracksTutorialPrimaryActionFrame,
                        onTutorialPrimaryActionFrameChange
                    )
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text(gymText(
                        "Your first plan",
                        "Твій перший план",
                        "Твой первый план",
                        languageCode: languageCode
                    ))
                    .font(.title2.bold())
                    .foregroundStyle(Color.white)
                    Text(gymText(
                        "Use the suggestion now or build the workout yourself. You can adjust every setting.",
                        "Скористайся порадою зараз або створи тренування самостійно. Усі налаштування можна змінити.",
                        "Используй рекомендацию сейчас или собери тренировку сам. Все настройки можно изменить.",
                        languageCode: languageCode
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: startActivationPlan) {
                    Text(gymText(
                        "Use suggested plan",
                        "Використати пораду",
                        "Использовать рекомендацию",
                        languageCode: languageCode
                    ))
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.07, green: 0.21, blue: 0.38))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        Color.white,
                        in: RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius)
                    )
                }
                .buttonStyle(.plain)
                .appTutorialPrimaryActionTarget()
                .appTutorialPrimaryActionFrame(
                    isEnabled: tracksTutorialPrimaryActionFrame,
                    onTutorialPrimaryActionFrameChange
                )

                Button(action: createActivationManually) {
                    Text(gymText(
                        "Build manually",
                        "Створити вручну",
                        "Собрать вручную",
                        languageCode: languageCode
                    ))
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay {
                        RoundedRectangle(cornerRadius: GymTheme.controlCornerRadius)
                            .strokeBorder(Color.white.opacity(0.46), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)

                DisclosureGroup(
                    gymText(
                        "Adjust recommendation",
                        "Налаштувати пораду",
                        "Настроить рекомендацию",
                        languageCode: languageCode
                    ),
                    isExpanded: $showsActivationOptions
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        activationGoalChoiceGrid(
                            title: gymText("Goal", "Ціль", "Цель", languageCode: languageCode),
                            options: TrainingActivationChoices.goals,
                            selection: $activationGoal,
                            label: activationGoalLabel
                        )
                        activationChoiceRow(
                            title: gymText(
                                "Days / week", "Днів / тиждень", "Дней / неделю",
                                languageCode: languageCode
                            ),
                            options: TrainingActivationChoices.days,
                            selection: $activationDays,
                            label: { $0.formatted() }
                        )
                        activationChoiceRow(
                            title: gymText(
                                "Today’s effort", "Навантаження сьогодні", "Нагрузка сегодня",
                                languageCode: languageCode
                            ),
                            options: TrainingActivationChoices.efforts,
                            selection: $activationEffort,
                            label: \.gymDisplayName
                        )
                        Button(action: editActivationPlan) {
                            Label(
                                gymText(
                                    "Review exercises", "Переглянути вправи", "Посмотреть упражнения",
                                    languageCode: languageCode
                                ),
                                systemImage: "pencil"
                            )
                            .font(.headline)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 8)
                }
                .tint(.white)
                .foregroundStyle(Color.white)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            activationLensShape.fill(GymTheme.heroGradient)
        }
        .overlay {
            activationLensShape.strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
        }
        .clipShape(activationLensShape)
        .shadow(color: GymTheme.primary.opacity(0.18), radius: 11, x: 0, y: 8)
        .appTutorialTarget(.todayFocus)
    }

    private func createActivationManually() {
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
    }

    private var activationLensShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 28,
            bottomLeadingRadius: 28,
            bottomTrailingRadius: 28,
            topTrailingRadius: 28,
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
        commitActivationPlan(launch: onStartPlan)
    }

    private func editActivationPlan() {
        commitActivationPlan(launch: onAddWorkout)
    }

    private func commitActivationPlan(launch: (WorkoutLaunchSeed) -> Bool) {
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
            launch: launch
        )
        if committed { activationDismissed = true }
    }

    private var todayProjection: TodayScreenProjection {
        projectionCache.projection(
            store: store,
            referenceDate: referenceDate,
            calendar: calendar,
            trainingProfile: TrainingProfileStore().load(
                accountStorageKey: store.accountStorageKey
            ),
            monthOffset: monthOffset
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
        if guidance.decision == .recovery {
            return gymText(
                "Recovery plan",
                "План відновлення",
                "План восстановления",
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
        return guidance.decision != .train
            ? gymText("Train anyway", "Усе одно тренуватися", "Всё равно тренироваться", languageCode: languageCode)
            : gymText(
                "Start plan",
                "Почати план",
                "Начать план",
                languageCode: languageCode
            )
    }

    private var focusLens: some View {
        let projection = todayProjection
        let guidance = projection.weeklyGuidance
        let weeklySummary = projection.weeklySummary
        let completedToday = weeklySummary.hasCompletedWorkoutToday(
            now: referenceDate,
            calendar: calendar
        )
        let launchSeed = projection.launchSeed
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(gymText(
                    completedToday ? "Workout complete" : todayTitle(guidance: guidance, plan: launchSeed?.plan),
                    completedToday ? "Тренування завершено" : todayTitle(guidance: guidance, plan: launchSeed?.plan),
                    completedToday ? "Тренировка завершена" : todayTitle(guidance: guidance, plan: launchSeed?.plan),
                    languageCode: languageCode
                ))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                if completedToday {
                    Text(gymText(
                        "Today's work is saved in your history.",
                        "Сьогоднішнє тренування збережено в історії.",
                        "Сегодняшняя тренировка сохранена в истории.",
                        languageCode: languageCode
                    ))
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if completedToday {
                focusDetailsDisclosure(projection)
                completedTodayAction
            } else if guidance.decision == .train {
                if let plan = launchSeed?.plan {
                    todayPlanMetrics(plan)
                }
                focusDetailsDisclosure(
                    projection,
                    guidance: guidance,
                    includeManualAction: true
                )
                focusActionButtons(launchSeed: launchSeed, guidance: guidance)
            } else {
                recoverySummary(guidance)
                focusDetailsDisclosure(
                    projection,
                    guidance: guidance,
                    includeManualAction: true
                )
                focusActionButtons(launchSeed: launchSeed, guidance: guidance)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(GymTheme.heroGradient)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                topTrailingRadius: 28,
                style: .continuous
            )
        )
        .shadow(color: GymTheme.primary.opacity(0.24), radius: 24, x: 0, y: 14)
        .appTutorialTarget(.todayFocus)
    }

    private func focusDetailsDisclosure(
        _ projection: TodayScreenProjection,
        guidance: WeeklyTrainingGuidance? = nil,
        includeManualAction: Bool = false
    ) -> some View {
        DisclosureGroup(
            gymText(
                "Week and plan details",
                "Тиждень і деталі плану",
                "Неделя и детали плана",
                languageCode: languageCode
            ),
            isExpanded: $showsFocusDetails
        ) {
            VStack(alignment: .leading, spacing: 12) {
                weeklyTrainingSummaryView(
                    projection.weeklySummary,
                    targetTrainingDays: projection.trainingProfile.workoutsPerWeek
                )
                if let guidance {
                    Text(todayPlanExplanation(guidance))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.86))
                }
                todayHeroMetricsRow(projection.heroMetrics)
                if includeManualAction {
                    Button {
                        referenceDate = Date()
                        _ = onAddWorkout(nil)
                    } label: {
                        Label(
                            gymText(
                                "Build manually", "Створити вручну", "Собрать вручную",
                                languageCode: languageCode
                            ),
                            systemImage: "plus"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
        .tint(.white)
        .foregroundStyle(Color.white)
    }

    private var activeFocusLens: some View {
        let projection = todayProjection
        let draft = activeWorkoutDraft
        let currentExercise = draft?.exercises.first(where: { exercise in
            exercise.sets.contains(where: { !$0.isCompleted })
        })
        let currentSetIndex = currentExercise?.sets.firstIndex(where: { !$0.isCompleted })
        return VStack(alignment: .leading, spacing: 14) {
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

            if let draft {
                Text(
                    currentExercise.flatMap { store.exercise(id: $0.exerciseID) }
                        .map { gymExerciseName($0) } ?? gymText(
                            "Next exercise",
                            "Наступна вправа",
                            "Следующее упражнение",
                            languageCode: languageCode
                        )
                )
                .font(.title3.bold())
                .foregroundStyle(Color.white)
                Text(gymText(
                    "Set \((currentSetIndex ?? 0) + 1) · \(draft.completedSetCount) / \(draft.plannedSetCount) completed",
                    "Підхід \((currentSetIndex ?? 0) + 1) · виконано \(draft.completedSetCount) / \(draft.plannedSetCount)",
                    "Подход \((currentSetIndex ?? 0) + 1) · выполнено \(draft.completedSetCount) / \(draft.plannedSetCount)",
                    languageCode: languageCode
                ))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.88))
            }

            DisclosureGroup(
                gymText(
                    "Week and plan details",
                    "Тиждень і деталі плану",
                    "Неделя и детали плана",
                    languageCode: languageCode
                ),
                isExpanded: $showsActiveFocusDetails
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    weeklyTrainingSummaryView(
                        projection.weeklySummary,
                        targetTrainingDays: projection.trainingProfile.workoutsPerWeek
                    )
                    todayHeroMetricsRow(projection.heroMetrics)
                }
                .padding(.top, 8)
            }
            .tint(.white)
            .foregroundStyle(Color.white)

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
                .foregroundStyle(Color(red: 0.07, green: 0.21, blue: 0.38))
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
            .background(Color.white, in: Capsule())
            .appTutorialPrimaryActionTarget()
            .appTutorialPrimaryActionFrame(
                isEnabled: tracksTutorialPrimaryActionFrame,
                onTutorialPrimaryActionFrameChange
            )

            DisclosureGroup(
                gymText(
                    "More workout options",
                    "Інші дії",
                    "Другие действия",
                    languageCode: languageCode
                ),
                isExpanded: $showsActiveMoreActions
            ) {
                Button(role: .destructive, action: onDiscardWorkout) {
                    Text(gymText(
                        "Discard workout",
                        "Відкинути тренування",
                        "Удалить тренировку",
                        languageCode: languageCode
                    ))
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
            }
            .tint(.white)
            .foregroundStyle(Color.white)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { activationLensShape.fill(GymTheme.heroGradient) }
        .clipShape(activationLensShape)
        .shadow(color: GymTheme.primary.opacity(0.24), radius: 24, x: 0, y: 14)
        .appTutorialTarget(.todayFocus)
    }

    private func todayPlanMetrics(_ plan: SmartWorkoutPlan) -> some View {
        let exerciseCount = plan.exercises.count
        let setCount = plan.exercises.reduce(0) { $0 + $1.recommendation.sets.count }
        let minutes = TodayFocusPlanMetrics.estimatedMinutes(
            exerciseCount: exerciseCount,
            setCount: setCount
        )
        return HStack(spacing: 8) {
            todayPlanMetric(
                value: exerciseCount.formatted(),
                label: gymText("Exercises", "Вправи", "Упражнения", languageCode: languageCode)
            )
            todayPlanMetric(
                value: setCount.formatted(),
                label: gymText("Sets", "Підходи", "Подходы", languageCode: languageCode)
            )
            todayPlanMetric(
                value: gymText(
                    "\(minutes) min",
                    "\(minutes) хв",
                    "\(minutes) мин",
                    languageCode: languageCode
                ),
                label: gymText("Estimated", "Орієнтовно", "Примерно", languageCode: languageCode)
            )
        }
    }

    private func todayPlanMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.bold().monospacedDigit())
            Text(label).font(.caption2)
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func todayPlanExplanation(_ guidance: WeeklyTrainingGuidance) -> String {
        switch guidance.decision {
        case .train:
            gymText(
                "Built from your goal, weekly rhythm, and recent workout history.",
                "План враховує твою ціль, ритм тижня та недавню історію тренувань.",
                "План учитывает твою цель, ритм недели и недавнюю историю тренировок.",
                languageCode: languageCode
            )
        case .recovery, .rest:
            gymText(
                "Recovery is recommended from your weekly rhythm and latest workout feedback.",
                "Відновлення рекомендовано за ритмом тижня та відгуком про останнє тренування.",
                "Восстановление рекомендовано по ритму недели и отзыву о последней тренировке.",
                languageCode: languageCode
            )
        }
    }

    private func recoverySummary(_ guidance: WeeklyTrainingGuidance) -> some View {
        let nextDay: Date
        if guidance.decision == .rest {
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: referenceDate)
                ?? referenceDate.addingTimeInterval(7 * 24 * 60 * 60)
            nextDay = calendar.gymMondayStart(of: nextWeek)
        } else {
            nextDay = calendar.date(byAdding: .day, value: 1, to: referenceDate)
                ?? referenceDate.addingTimeInterval(24 * 60 * 60)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text(todayPlanExplanation(guidance))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.9))
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                Text(gymText(
                    "Next recommended day: \(gymFormattedDate(nextDay, date: .abbreviated, time: .omitted))",
                    "Наступний рекомендований день: \(gymFormattedDate(nextDay, date: .abbreviated, time: .omitted))",
                    "Следующий рекомендуемый день: \(gymFormattedDate(nextDay, date: .abbreviated, time: .omitted))",
                    languageCode: languageCode
                ))
            }
            .font(.subheadline.bold())
            .foregroundStyle(Color.white)
        }
    }

    private func weeklyTrainingSummaryView(
        _ summary: WeeklyTrainingSummary,
        targetTrainingDays: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(gymText(
                    "This week",
                    "Цього тижня",
                    "На этой неделе",
                    languageCode: languageCode
                ))
                .font(.subheadline.bold())
                Spacer(minLength: 8)
                Text(gymText(
                    "\(summary.completedTrainingDays.count) / \(targetTrainingDays) days",
                    "\(summary.completedTrainingDays.count) / \(targetTrainingDays) днів",
                    "\(summary.completedTrainingDays.count) / \(targetTrainingDays) дней",
                    languageCode: languageCode
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.76))
            }

            HStack(spacing: 8) {
                ForEach(0 ..< 7, id: \.self) { offset in
                    let day = calendar.date(
                        byAdding: .day,
                        value: offset,
                        to: summary.weekStart
                    ) ?? summary.weekStart
                    let completed = summary.hasWorkout(on: day, calendar: calendar)
                    VStack(spacing: 5) {
                        Text(weeklyDaySymbol(day))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.74))
                        Circle()
                            .fill(
                                completed
                                    ? Color(red: 0.49, green: 0.94, blue: 0.78)
                                    : Color.white.opacity(0.24)
                            )
                            .frame(width: 12, height: 12)
                            .overlay {
                                if calendar.isDate(day, inSameDayAs: referenceDate) {
                                    Circle()
                                        .stroke(Color.white.opacity(0.72), lineWidth: 2)
                                        .padding(-4)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        gymFormattedDate(day, date: .long, time: .omitted, languageCode: languageCode)
                    )
                    .accessibilityValue(
                        completed
                            ? gymText(
                                "Workout completed",
                                "Тренування виконано",
                                "Тренировка выполнена",
                                languageCode: languageCode
                            )
                            : gymText(
                                "No completed workout",
                                "Немає виконаного тренування",
                                "Нет выполненной тренировки",
                                languageCode: languageCode
                            )
                    )
                }
            }

            HStack(alignment: .top, spacing: 8) {
                weeklyTrainingMetric(
                    value: summary.completedSessionCount.formatted(),
                    label: gymText("Workouts", "Тренування", "Тренировки", languageCode: languageCode)
                )
                weeklyTrainingMetric(
                    value: summary.totalMinutes.formatted(),
                    label: gymText("Minutes", "Хвилини", "Минуты", languageCode: languageCode)
                )
                weeklyTrainingMetric(
                    value: formattedTodayHeroVolume(summary.totalVolume),
                    label: gymText("Volume", "Обсяг", "Объём", languageCode: languageCode)
                )
            }
        }
        .foregroundStyle(Color.white)
        .padding(12)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }

    private func weeklyDaySymbol(_ date: Date) -> String {
        let locale = AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale
        return date.formatted(.dateTime.weekday(.narrow).locale(locale))
    }

    private func weeklyTrainingMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.74))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var completedTodayAction: some View {
        if hasRetainedWorkoutDraft {
            continueRetainedPlanAction
        } else {
            focusActionButton(
            title: gymText(
                "Add another workout",
                "Додати ще одне тренування",
                "Добавить ещё одну тренировку",
                languageCode: languageCode
            ),
            systemImage: "plus",
            primary: false,
            accessibilityHint: gymText(
                "Opens a blank workout plan without changing the completed workout",
                "Відкриває порожній план, не змінюючи завершене тренування",
                "Открывает пустой план, не изменяя завершённую тренировку",
                languageCode: languageCode
            )
            ) {
                referenceDate = Date()
                _ = onAddWorkout(nil)
            }
        }
    }

    private var continueRetainedPlanAction: some View {
        focusActionButton(
            title: gymText(
                "Continue plan",
                "Продовжити план",
                "Продолжить план",
                languageCode: languageCode
            ),
            systemImage: "pencil",
            primary: true,
            accessibilityHint: gymText(
                "Opens your saved workout plan",
                "Відкриває збережений план тренування",
                "Открывает сохранённый план тренировки",
                languageCode: languageCode
            )
        ) {
            referenceDate = Date()
            _ = onAddWorkout(nil)
        }
    }

    private func todayHeroMetricsRow(_ metrics: TodayHeroMetrics) -> some View {
        HStack(alignment: .top, spacing: 8) {
            todayHeroMetric(
                value: formattedTodayHeroCount(metrics.totalWorkouts),
                label: gymText(
                    "Total workouts",
                    "Усього тренувань",
                    "Всего тренировок",
                    languageCode: languageCode
                ),
                accessibilityValue: metrics.totalWorkouts.formatted(
                    .number.locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                )
            )
            todayHeroMetric(
                value: gymText(
                    "\(metrics.weeklyStreakWeeks) wk",
                    "\(metrics.weeklyStreakWeeks) тиж",
                    "\(metrics.weeklyStreakWeeks) нед",
                    languageCode: languageCode
                ),
                label: gymText(
                    "Week streak",
                    "Серія тижнів",
                    "Серия недель",
                    languageCode: languageCode
                ),
                accessibilityValue: gymText(
                    "\(metrics.weeklyStreakWeeks) weeks",
                    "\(metrics.weeklyStreakWeeks) тижнів",
                    "\(metrics.weeklyStreakWeeks) недель",
                    languageCode: languageCode
                )
            )
            todayHeroMetric(
                value: formattedTodayHeroVolume(metrics.totalVolume),
                label: gymText(
                    "Total volume",
                    "Загальний обсяг",
                    "Общий объём",
                    languageCode: languageCode
                ),
                accessibilityValue: formattedTodayHeroVolumeAccessibility(metrics.totalVolume)
            )
        }
    }

    private func todayHeroMetric(
        value: String,
        label: String,
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.caption2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
    }

    private func formattedTodayHeroCount(_ value: Int) -> String {
        Double(max(0, value)).formatted(
            .number
                .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func formattedTodayHeroVolume(_ value: Double) -> String {
        let safeValue = value.isFinite && value >= 0
            ? min(value, maximumTodayHeroVolume)
            : 0
        return safeValue.formatted(
            .number
                .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                .notation(.compactName)
                .precision(.fractionLength(0 ... 1))
        )
    }

    private func formattedTodayHeroVolumeAccessibility(_ value: Double) -> String {
        let safeValue = value.isFinite && value >= 0
            ? min(value, maximumTodayHeroVolume)
            : 0
        return safeValue.formatted(
            .number
                .locale(AppLanguage(rawValue: languageCode)?.locale ?? AppLanguage.english.locale)
                .grouping(.automatic)
                .precision(.fractionLength(0 ... 1))
        )
    }

    @ViewBuilder
    private func focusActionButtons(
        launchSeed: WorkoutLaunchSeed?,
        guidance: WeeklyTrainingGuidance
    ) -> some View {
        VStack(spacing: 10) {
            if hasRetainedWorkoutDraft {
                continueRetainedPlanAction
                    .appTutorialPrimaryActionTarget()
                    .appTutorialPrimaryActionFrame(
                        isEnabled: tracksTutorialPrimaryActionFrame,
                        onTutorialPrimaryActionFrameChange
                    )
            } else if let launchSeed {
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
                .appTutorialPrimaryActionTarget()
                .appTutorialPrimaryActionFrame(
                    isEnabled: tracksTutorialPrimaryActionFrame,
                    onTutorialPrimaryActionFrameChange
                )

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
                .appTutorialPrimaryActionTarget()
                .appTutorialPrimaryActionFrame(
                    isEnabled: tracksTutorialPrimaryActionFrame,
                    onTutorialPrimaryActionFrameChange
                )
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
                .foregroundStyle(
                    primary ? Color(red: 0.07, green: 0.21, blue: 0.38) : Color.white
                )
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: primary ? 54 : 48)
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)

        if !primary {
            button
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.36), lineWidth: 1) }
        } else {
            button
                .background(Color.white, in: Capsule())
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
        .id("workout-history")

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
        let activityOnly = isActivityOnly(workout)
        return GymPanel(highlighted: true) {
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
                                activityOnly
                                    ? compactHistoryDuration(workout.durationSeconds ?? 0)
                                    : gymCount(
                                        workout.setCount,
                                        englishOne: "set",
                                        englishMany: "sets",
                                        ukrainianOne: "підхід",
                                        ukrainianFew: "підходи",
                                        ukrainianMany: "підходів"
                                    )
                            )
                        }

                        Text(activityOnly ? gymText(
                            "Garmin free workout",
                            "Вільне тренування Garmin",
                            "Свободная тренировка Garmin",
                            languageCode: languageCode
                        ) : workoutNote(workout))
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        if activityOnly {
                            Text(gymText(
                                "Time, heart rate, and calories — no exercises or sets",
                                "Час, пульс і калорії — без вправ і підходів",
                                "Время, пульс и калории — без упражнений и подходов",
                                languageCode: languageCode
                            ))
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                        } else {
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

    private var monthWorkouts: [WorkoutSessionSummary] {
        todayProjection.monthWorkouts
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
        if isActivityOnly(workout) {
            let duration = compactHistoryDuration(workout.durationSeconds ?? 0)
            return gymText(
                "Garmin free workout, \(duration), no exercises or sets",
                "Вільне тренування Garmin, \(duration), без вправ і підходів",
                "Свободная тренировка Garmin, \(duration), без упражнений и подходов",
                languageCode: languageCode
            )
        }
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

    private func isActivityOnly(_ workout: WorkoutSessionSummary) -> Bool {
        workout.exerciseCount == 0 && workout.setCount == 0 &&
            workout.durationSeconds.map { $0 > 0 } == true
    }

    private func compactHistoryDuration(_ seconds: Int) -> String {
        let minutes = max(1, max(0, seconds) / 60)
        let hours = minutes / 60
        let remaining = minutes % 60
        if hours == 0 {
            return gymText(
                "\(minutes) min", "\(minutes) хв", "\(minutes) мин",
                languageCode: languageCode
            )
        }
        if remaining == 0 {
            return gymText(
                "\(hours)h", "\(hours) год", "\(hours) ч",
                languageCode: languageCode
            )
        }
        return gymText(
            "\(hours)h \(remaining)m",
            "\(hours) год \(remaining) хв",
            "\(hours) ч \(remaining) мин",
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
