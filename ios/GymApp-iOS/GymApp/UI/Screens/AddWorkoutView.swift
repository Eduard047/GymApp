import SwiftUI

func makeWorkoutEditorDrafts(from plan: SmartWorkoutPlan) -> [WorkoutEditorExerciseDraft] {
    plan.exercises.map { item in
        WorkoutEditorExerciseDraft(
            id: item.exercise.id,
            exerciseID: item.exercise.id,
            sets: item.recommendation.sets.map {
                WorkoutEditorSetDraft(id: $0.id, recommendedSet: $0)
            },
            coachRecommendation: item.recommendation
        )
    }
}

func makeSharedWorkoutDraftURL(
    drafts: [WorkoutEditorExerciseDraft],
    exercises: [UUID: Exercise]
) throws -> URL {
    try SharedWorkoutLinkEncoder.makeURL(
        plan: makeSharedWorkoutDraftPlan(drafts: drafts, exercises: exercises)
    )
}

func makeSharedWorkoutDraftPlan(
    drafts: [WorkoutEditorExerciseDraft],
    exercises: [UUID: Exercise]
) throws -> SharedWorkoutPlan {
    guard !drafts.isEmpty,
          drafts.count <= SharedWorkoutLinkEncoder.maximumExercises else {
        throw SharedWorkoutLinkError.invalidExerciseCount
    }
    var totalSetCount = 0
    let sharedExercises = try drafts.map { draft -> SharedWorkoutPlanExercise in
        guard let exercise = exercises[draft.exerciseID] else {
            throw SharedWorkoutLinkError.missingExercise
        }
        guard !draft.sets.isEmpty,
              draft.sets.count <= SharedWorkoutLinkEncoder.maximumSetsPerExercise else {
            throw SharedWorkoutLinkError.invalidSetCount
        }
        totalSetCount += draft.sets.count
        guard totalSetCount <= SharedWorkoutLinkEncoder.maximumTotalSets else {
            throw SharedWorkoutLinkError.tooManySets
        }
        guard draft.sets.allSatisfy({
            $0.isReadyForSave && (1 ... 10_000).contains($0.reps)
        }) else { throw SharedWorkoutLinkError.invalidWeight }
        return SharedWorkoutPlanExercise(
            catalogKey: exercise.catalogKey,
            name: exercise.name,
            sets: draft.sets.map {
                SharedWorkoutPlanSet(weight: $0.weight, repetitions: $0.reps)
            }
        )
    }
    return try SharedWorkoutLinkValidator.validate(
        SharedWorkoutPlan(exercises: sharedExercises)
    )
}

struct GarminDraftSyncKey: Hashable, Sendable {
    let accountStorageKey: String
    let deviceID: String
    let title: String
    let startedAt: String
    let note: String
    let exercises: [GarminPlanExercise]
}

struct GarminDraftSubmission: Equatable, Sendable {
    let key: GarminDraftSyncKey
    let plan: GarminWorkoutPlan
    let clientRequestID: UUID
}

func makeGarminDraftSyncKey(
    accountStorageKey: String,
    deviceID: String,
    title: String,
    workoutDate: Date,
    note: String,
    drafts: [WorkoutEditorExerciseDraft],
    exercises: [UUID: Exercise]
) throws -> GarminDraftSyncKey {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let planExercises = try drafts.map { draft -> GarminPlanExercise in
        guard let exercise = exercises[draft.exerciseID] else {
            throw GarminCloudError.invalidPlan
        }
        guard !draft.sets.isEmpty,
              draft.sets.allSatisfy({
                  $0.isReadyForSave &&
                      (1 ... GarminPlanValidator.maximumReps).contains($0.reps)
              }) else {
            throw GarminCloudError.invalidPlan
        }
        return GarminPlanExercise(
            name: exercise.name,
            sets: draft.sets.enumerated().map { index, set in
                GarminPlanSet(weight: set.weight, reps: set.reps, orderIndex: index)
            }
        )
    }
    return GarminDraftSyncKey(
        accountStorageKey: accountStorageKey,
        deviceID: deviceID,
        title: title,
        startedAt: formatter.string(from: workoutDate),
        note: note,
        exercises: planExercises
    )
}

func prepareGarminDraftSubmission(
    existing: GarminDraftSubmission?,
    key: GarminDraftSyncKey,
    now: Date = Date(),
    makeRequestID: () -> UUID = UUID.init
) throws -> GarminDraftSubmission {
    if let existing, existing.key == key {
        _ = try GarminPlanValidator.validate(existing.plan)
        return existing
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plan = GarminWorkoutPlan(
        source: "gymapp-ios",
        version: 1,
        title: key.title,
        createdAt: formatter.string(from: now),
        startedAt: key.startedAt,
        note: key.note,
        exercises: key.exercises
    )
    _ = try GarminPlanValidator.validate(plan)
    return GarminDraftSubmission(
        key: key,
        plan: plan,
        clientRequestID: makeRequestID()
    )
}

@MainActor
struct AddWorkoutView: View {
    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var activeWorkoutStore: ActiveWorkoutStore
    @ObservedObject private var garminCloud: GarminCloudService

    @State private var date = Date()
    @State private var note = ""
    @State private var profile = TrainingProfile()
    @State private var selectedEffort: SmartWorkoutEffort = .auto
    @State private var latestSmartPlan: SmartWorkoutPlan?
    @State private var smartGeneratedDraftIDs = Set<UUID>()
    @State private var smartPlanIsStale = false
    @State private var drafts: [WorkoutEditorExerciseDraft] = []
    @State private var garminDraftSubmission: GarminDraftSubmission?
    @State private var showingExercisePicker = false
    @State private var showingPreviousPicker = false
    @State private var replacementRequest: SmartReplacementRequest?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isSaving = false
    @State private var showingShareChooser = false
    @State private var sharingPlan: SharedWorkoutPlan?
    @State private var shareFriends: [SocialFriendSummary] = []
    @State private var shareFriendsAreLoading = false
    @State private var sharingFriendID: String?
    @State private var shareChooserMessage: String?
    @State private var shareChooserMessageIsError = false
    @State private var secondaryOptionsExpanded = false
    @State private var showingDiscardConfirmation = false
    @State private var showingClearPlanConfirmation = false

    private let baselinePlanSnapshot: PlanEditorSnapshot

    private let isCloudAccount: Bool
    private let onStarted: (UUID) -> Void
    private let onSaved: (UUID) -> Void
    private let onCancel: () -> Void
    private let reportStatus: (String, Bool) -> Void
    private let loadSocialDashboard: (() async throws -> SocialDashboard)?
    private let sendSocialWorkoutInvite: ((String, SharedWorkoutPlan) async throws -> Void)?
    private let sendLiveWorkoutInvite: ((String, SharedWorkoutPlan) async throws -> Void)?
    private let refreshSocialWorkoutInbox: (() async throws -> Void)?
    private let rejectsLaunchSeed: Bool

    init(
        appState: AppState,
        activeWorkoutStore: ActiveWorkoutStore,
        liveWorkoutCoordinator: LiveWorkoutCoordinator? = nil,
        initialDrafts: [WorkoutExerciseDraft] = [],
        launchSeed: WorkoutLaunchSeed? = nil,
        launchSeedConsumerID: UUID? = nil,
        launchSeedDrafts: [WorkoutEditorExerciseDraft]? = nil,
        onStarted: @escaping (UUID) -> Void,
        onSaved: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.init(
            store: appState.workoutStore,
            activeWorkoutStore: activeWorkoutStore,
            garminCloud: appState.garminCloud,
            isCloudAccount: appState.auth.session?.cloud != nil,
            initialDrafts: initialDrafts,
            launchSeed: launchSeed,
            launchSeedConsumerID: launchSeedConsumerID,
            launchSeedDrafts: launchSeedDrafts,
            onStarted: onStarted,
            onSaved: onSaved,
            onCancel: onCancel,
            onStatus: { [weak appState] message, isError in
                appState?.show(message: message, isError: isError)
            },
            loadSocialDashboard: { try await appState.refreshSocialDashboard() },
            sendSocialWorkoutInvite: { profileID, plan in
                try await appState.sendWorkoutInvite(to: profileID, plan: plan)
            },
            sendLiveWorkoutInvite: liveWorkoutCoordinator.map { coordinator in
                { profileID, plan in
                    try await coordinator.sendInvite(to: profileID, plan: plan)
                }
            },
            refreshSocialWorkoutInbox: {
                _ = try await appState.refreshSocialWorkoutInbox()
            }
        )
    }

    init(
        store: WorkoutStore,
        activeWorkoutStore: ActiveWorkoutStore,
        garminCloud: GarminCloudService,
        isCloudAccount: Bool,
        initialDrafts: [WorkoutExerciseDraft] = [],
        launchSeed: WorkoutLaunchSeed? = nil,
        launchSeedConsumerID: UUID? = nil,
        launchSeedDrafts: [WorkoutEditorExerciseDraft]? = nil,
        onStarted: @escaping (UUID) -> Void,
        onSaved: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void = {},
        onStatus: @escaping (String, Bool) -> Void = { _, _ in },
        loadSocialDashboard: (() async throws -> SocialDashboard)? = nil,
        sendSocialWorkoutInvite: ((String, SharedWorkoutPlan) async throws -> Void)? = nil,
        sendLiveWorkoutInvite: ((String, SharedWorkoutPlan) async throws -> Void)? = nil,
        refreshSocialWorkoutInbox: (() async throws -> Void)? = nil
    ) {
        _store = ObservedObject(wrappedValue: store)
        _activeWorkoutStore = ObservedObject(wrappedValue: activeWorkoutStore)
        _garminCloud = ObservedObject(wrappedValue: garminCloud)
        let storedProfile = TrainingProfileStore().load(
            accountStorageKey: store.accountStorageKey
        )
        let requestedLaunchSeed = launchSeed
        let launchSeed: WorkoutLaunchSeed? = requestedLaunchSeed.flatMap { seed -> WorkoutLaunchSeed? in
            guard WorkoutLaunchSeedUseGate.accepts(
                seed,
                consumerID: launchSeedConsumerID
            ), let launchSeedDrafts,
               !launchSeedDrafts.isEmpty,
               launchSeedDrafts == makeWorkoutEditorDrafts(from: seed.plan) else {
                return nil
            }
            return seed
        }
        let profile = launchSeed?.profile ?? storedProfile
        let seededDrafts = launchSeed.map { _ in launchSeedDrafts ?? [] }
        let initialDate = Date()
        let initialEffort = launchSeed?.requestedEffort ?? .auto
        let initialEditorDrafts = seededDrafts ?? initialDrafts.map { exercise in
            WorkoutEditorExerciseDraft(
                exerciseID: exercise.exerciseID,
                sets: exercise.sets.map {
                    WorkoutEditorSetDraft(weight: $0.weight, reps: $0.reps)
                }
            )
        }
        _date = State(initialValue: initialDate)
        _profile = State(initialValue: profile)
        _selectedEffort = State(initialValue: initialEffort)
        _latestSmartPlan = State(initialValue: launchSeed?.plan)
        _drafts = State(initialValue: initialEditorDrafts)
        _garminDraftSubmission = State(initialValue: nil)
        _smartGeneratedDraftIDs = State(
            initialValue: Set((seededDrafts ?? []).map(\.id))
        )
        self.isCloudAccount = isCloudAccount
        self.onStarted = onStarted
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.reportStatus = onStatus
        self.loadSocialDashboard = loadSocialDashboard
        self.sendSocialWorkoutInvite = sendSocialWorkoutInvite
        self.sendLiveWorkoutInvite = sendLiveWorkoutInvite
        self.refreshSocialWorkoutInbox = refreshSocialWorkoutInbox
        rejectsLaunchSeed = requestedLaunchSeed != nil && launchSeed == nil
        baselinePlanSnapshot = PlanEditorSnapshot(
            date: initialDate,
            note: "",
            effort: initialEffort,
            drafts: initialEditorDrafts
        )
    }

    var body: some View {
        GymBackground {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        Color.clear
                            .frame(height: 0)
                            .id("workout-plan-editor-top")

                        if let statusMessage {
                            GymStatusBanner(message: statusMessage, isError: statusIsError)
                        }

                        profilePanel
                        smartCoachPanel
                        editorSection
                        startWorkoutButton
                        secondaryOptions
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: drafts.isEmpty) { isEmpty in
                    guard isEmpty else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollProxy.scrollTo("workout-plan-editor-top", anchor: .top)
                        }
                    }
                }
            }
        }
        .navigationTitle(
            gymText(
                "Workout plan",
                "План тренування",
                "План тренировки",
                languageCode: gymCurrentLanguageCode()
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(
                    gymText(
                        "Cancel",
                        "Скасувати",
                        "Отмена",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    action: requestCancel
                )
            }
        }
        .interactiveDismissDisabled(hasUnsavedPlanChanges)
        .confirmationDialog(
            gymText(
                "Discard plan changes?",
                "Відкинути зміни плану?",
                "Отменить изменения плана?",
                languageCode: gymCurrentLanguageCode()
            ),
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                gymText(
                    "Discard changes",
                    "Відкинути зміни",
                    "Отменить изменения",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .destructive,
                action: onCancel
            )
            Button(
                gymText(
                    "Keep editing",
                    "Продовжити редагування",
                    "Продолжить редактирование",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .cancel
            ) {}
        } message: {
            Text(gymText(
                "Your edits will be lost.",
                "Зміни буде втрачено.",
                "Изменения будут потеряны.",
                languageCode: gymCurrentLanguageCode()
            ))
        }
        .confirmationDialog(
            gymText(
                "Clear workout plan?",
                "Очистити план тренування?",
                "Очистить план тренировки?",
                languageCode: gymCurrentLanguageCode()
            ),
            isPresented: $showingClearPlanConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                gymText(
                    "Clear plan",
                    "Очистити план",
                    "Очистить план",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .destructive,
                action: clearPlan
            )
            Button(
                gymText(
                    "Keep plan",
                    "Залишити план",
                    "Оставить план",
                    languageCode: gymCurrentLanguageCode()
                ),
                role: .cancel
            ) {}
        } message: {
            Text(gymText(
                "All exercises and sets will be removed.",
                "Усі вправи й підходи буде видалено.",
                "Все упражнения и подходы будут удалены.",
                languageCode: gymCurrentLanguageCode()
            ))
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(
                exercises: store.exercises,
                selectedExerciseIDs: Set(drafts.map(\.exerciseID)),
                exerciseMediaOwnerKey: store.accountStorageKey,
                muscleMappings: store.muscleMappings,
                sessionCounts: exerciseSessionCounts,
                onSelect: addExercise,
                onCreate: { try store.addExercise(name: $0) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingPreviousPicker) {
            PreviousWorkoutPicker(
                workouts: store.workouts.sorted { $0.date > $1.date },
                exerciseName: exerciseName,
                onSelect: applyPreviousWorkout
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $replacementRequest) { request in
            SmartExerciseAlternativesSheet(
                alternatives: request.alternatives,
                exerciseMediaOwnerKey: store.accountStorageKey,
                onSelect: { applyAlternative($0, request: request) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingShareChooser) {
            workoutShareChooser
                .presentationDetents([.medium, .large])
        }
        .onChange(of: profile) { newProfile in
            smartPlanIsStale = smartPlanIsStale || !smartGeneratedDraftIDs.isEmpty
            TrainingProfileStore().save(newProfile, accountStorageKey: store.accountStorageKey)
        }
        .onChange(of: selectedEffort) { _ in
            smartPlanIsStale = smartPlanIsStale || !smartGeneratedDraftIDs.isEmpty
        }
        .task {
            guard !rejectsLaunchSeed else {
                onCancel()
                return
            }
            try? await refreshSocialWorkoutInbox?()
        }
    }

    private var sessionDetails: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: "Date and notes"
                )

                DatePicker(
                    "Workout date",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                    .datePickerStyle(.compact)

                TextField("Notes (optional)", text: $note, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .gymTextFieldChrome()
                    .accessibilityHint("Add context such as energy, technique, or the training plan")
            }
        }
    }

    private var templatePanel: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 13) {
                GymSectionTitle(
                    title: "Choose a training day"
                )

                ScrollView(.horizontal) {
                    HStack(spacing: 9) {
                        ForEach(WorkoutTemplatePreset.allCases) { preset in
                            Button {
                                applyTemplate(preset)
                            } label: {
                                Label(preset.title, systemImage: preset.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(GymTheme.primary.opacity(0.1), in: Capsule())
                            }
                            .accessibilityHint(
                                gymText(
                                    "Replaces the current editor with a \(preset.title) template",
                                    "Замінює вміст редактора шаблоном «\(preset.title)»",
                                    "Заменяет содержимое редактора шаблоном «\(preset.title)»",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { previousActions }
                    VStack(spacing: 10) { previousActions }
                }
            }
        }
    }

    @ViewBuilder
    private var previousActions: some View {
        Button {
            guard let latest = store.latestWorkoutTemplate else {
                show("No previous workout is available yet.", error: true)
                return
            }
            applyPreviousWorkout(latest)
        } label: {
            Label("Repeat latest", systemImage: "repeat")
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .disabled(store.latestWorkoutTemplate == nil)

        Button {
            showingPreviousPicker = true
        } label: {
            Label("Copy previous", systemImage: "doc.on.doc")
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .disabled(store.workouts.isEmpty)
    }

    private var profilePanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 14) {
                GymSectionTitle(
                    title: "Coach settings"
                )

                profilePicker(
                    gymText(
                        "Program",
                        "Програма",
                        "Программа",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    selection: $profile.split,
                    label: trainingSplitLabel
                )
                profilePicker(
                    gymText(
                        "Goal",
                        "Ціль",
                        "Цель",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    selection: $profile.goal,
                    label: trainingGoalLabel
                )
                profilePicker(
                    gymText(
                        "Calories",
                        "Калорії",
                        "Калории",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    selection: $profile.calorieMode,
                    label: calorieModeLabel
                )

                Stepper(value: $profile.workoutsPerWeek, in: 2 ... 6) {
                    HStack {
                        Text(gymText(
                            "Training days",
                            "Тренувальні дні",
                            "Тренировочные дни",
                            languageCode: gymCurrentLanguageCode()
                        ))
                        Spacer()
                        Text(profile.workoutsPerWeek.formatted())
                            .font(.body.monospacedDigit().weight(.bold))
                            .foregroundStyle(GymTheme.primary)
                    }
                }
                .accessibilityValue(
                    gymCount(
                        profile.workoutsPerWeek,
                        englishOne: "workout per week",
                        englishMany: "workouts per week",
                        ukrainianOne: "тренування на тиждень",
                        ukrainianFew: "тренування на тиждень",
                        ukrainianMany: "тренувань на тиждень"
                    )
                )
            }
        }
    }

    private func profilePicker<Value: Hashable & CaseIterable>(
        _ title: String,
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View where Value.AllCases: RandomAccessCollection {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func trainingSplitLabel(_ split: TrainingSplit) -> String {
        switch split {
        case .upperLower:
            gymText("Upper / Lower", "Верх / низ", "Верх/низ", languageCode: gymCurrentLanguageCode())
        case .fullBody:
            gymText("Full Body", "Все тіло", "Все тело", languageCode: gymCurrentLanguageCode())
        case .pushPullLegs:
            gymText("Push Pull Legs", "Жим / тяга / ноги", "Жим/тяга/ноги", languageCode: gymCurrentLanguageCode())
        case .custom:
            gymText("Custom", "Своя", "Своя", languageCode: gymCurrentLanguageCode())
        }
    }

    private func trainingGoalLabel(_ goal: TrainingGoal) -> String {
        switch goal {
        case .aestheticFatLoss:
            gymText("Aesthetic Cut", "Естетика / сушка", "Эстетика/сушка", languageCode: gymCurrentLanguageCode())
        case .muscleGain:
            gymText("Muscle Gain", "Набір мʼязів", "Набор мышц", languageCode: gymCurrentLanguageCode())
        case .strength:
            gymText("Strength", "Сила", "Сила", languageCode: gymCurrentLanguageCode())
        case .balanced:
            gymText("Balanced", "Баланс", "Баланс", languageCode: gymCurrentLanguageCode())
        }
    }

    private func calorieModeLabel(_ mode: CalorieMode) -> String {
        switch mode {
        case .deficit:
            gymText("Deficit", "Дефіцит", "Дефицит", languageCode: gymCurrentLanguageCode())
        case .maintenance:
            gymText("Maintenance", "Підтримка", "Поддержание", languageCode: gymCurrentLanguageCode())
        case .surplus:
            gymText("Surplus", "Профіцит", "Профицит", languageCode: gymCurrentLanguageCode())
        }
    }

    private var smartCoachPanel: some View {
        GymPanel(highlighted: true) {
            VStack(alignment: .leading, spacing: 12) {
                GymSectionTitle(
                    title: "Smart Coach",
                    supporting: nil
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(SmartWorkoutEffort.allCases) { effort in
                        Button {
                            selectedEffort = effort
                        } label: {
                            Text(effort.displayName)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 8)
                                .foregroundStyle(
                                    selectedEffort == effort ? Color.white : GymTheme.primary
                                )
                                .background(
                                    selectedEffort == effort
                                        ? GymTheme.primary
                                        : GymTheme.primary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedEffort == effort ? .isSelected : [])
                    }
                }

                if let latestSmartPlan {
                    VStack(alignment: .leading, spacing: 5) {
                        if smartPlanIsStale {
                            Label(
                                gymText(
                                    "Profile or effort changed. Regenerate before starting for updated targets.",
                                    "Профіль або зусилля змінено. Перегенеруй план перед стартом.",
                                    "Профиль или нагрузка изменены. Пересоздай план перед стартом.",
                                    languageCode: gymCurrentLanguageCode()
                                ),
                                systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GymTheme.tertiary)
                        }
                        Text(
                            gymText(
                                "Focus: \(latestSmartPlan.focus.displayName) · RIR \(latestSmartPlan.rirSummary)",
                                "Фокус: \(latestSmartPlan.focus.displayName) · RIR \(latestSmartPlan.rirSummary)",
                                "Фокус: \(latestSmartPlan.focus.displayName) · RIR \(latestSmartPlan.rirSummary)",
                                languageCode: gymCurrentLanguageCode()
                            )
                        )
                        .font(.subheadline.weight(.semibold))
                        if latestSmartPlan.requestedEffort != latestSmartPlan.appliedEffort {
                            Text(
                                gymText(
                                    "Requested: \(latestSmartPlan.requestedEffort.displayName). Applied: \(latestSmartPlan.appliedEffort.displayName).",
                                    "Запитано: \(latestSmartPlan.requestedEffort.displayName). Застосовано: \(latestSmartPlan.appliedEffort.displayName).",
                                    "Запрошено: \(latestSmartPlan.requestedEffort.displayName). Применено: \(latestSmartPlan.appliedEffort.displayName).",
                                    languageCode: gymCurrentLanguageCode()
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(GymTheme.textSecondary)
                        }
                        if let adjustment = latestSmartPlan.effortAdjustment {
                            Text(adjustment.displayText)
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                        }
                    }
                    .padding(10)
                    .background(GymTheme.surfaceVariant.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                }
                Button(action: applySmartCoach) {
                    Label(
                        smartPlanIsStale
                            ? gymText(
                                "Regenerate smart plan",
                                "Оновити розумний план",
                                "Обновить умный план",
                                languageCode: gymCurrentLanguageCode()
                            )
                            : gymText(
                                "Build smart workout",
                                "Створити розумне тренування",
                                "Создать умную тренировку",
                                languageCode: gymCurrentLanguageCode()
                            ),
                        systemImage: smartPlanIsStale ? "arrow.triangle.2.circlepath" : "sparkles"
                    )
                }
                .buttonStyle(GymPrimaryButtonStyle())
                .disabled(store.exercises.isEmpty)
                .accessibilityHint(
                    smartPlanIsStale
                        ? gymText(
                            "Updates generated rows while preserving rows you edited manually",
                            "Оновлює згенеровані рядки, зберігаючи внесені вручну зміни",
                            "Обновляет созданные строки, сохраняя внесённые вручную изменения",
                            languageCode: gymCurrentLanguageCode()
                        )
                        : gymText(
                            "Builds recommended exercises and sets",
                            "Створює рекомендовані вправи й підходи",
                            "Создаёт рекомендованные упражнения и подходы",
                            languageCode: gymCurrentLanguageCode()
                        )
                )
            }
        }
    }

    @ViewBuilder
    private var editorSection: some View {
        HStack {
            GymSectionTitle(
                title: "Exercises"
            )
            Spacer(minLength: 8)
            if !drafts.isEmpty {
                Button(role: .destructive) {
                    showingClearPlanConfirmation = true
                } label: {
                    Label(
                        gymText(
                            "Clear plan",
                            "Очистити план",
                            "Очистить план",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityHint(gymText(
                    "Removes exercises and sets from this editor only",
                    "Видаляє вправи й підходи лише з цього редактора",
                    "Удаляет упражнения и подходы только из этого редактора",
                    languageCode: gymCurrentLanguageCode()
                ))
            }
            if !drafts.isEmpty {
                Button {
                    showingExercisePicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add exercise")
            }
        }
        .padding(.horizontal, 4)

        if drafts.isEmpty {
            Button {
                showingExercisePicker = true
            } label: {
                Label(
                    gymText(
                        "Add exercise",
                        "Додати вправу",
                        "Добавить упражнение",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    systemImage: "plus"
                )
            }
            .buttonStyle(GymPrimaryButtonStyle())
        } else {
            ForEach(drafts) { item in
                if let exercise = store.exercise(id: item.exerciseID) {
                    WorkoutDraftExerciseCard(
                        draft: binding(for: item.id),
                        exerciseID: exercise.id,
                        exerciseMediaOwnerKey: store.accountStorageKey,
                        rawExerciseName: exercise.name,
                        exerciseCatalogKey: exercise.catalogKey,
                        lastWeight: store.lastWeight(exerciseID: exercise.id),
                        onShowSimilar: { showAlternatives(for: item.id) },
                        onDeleteExercise: {
                            smartGeneratedDraftIDs.remove(item.id)
                            latestSmartPlan = nil
                            drafts.removeAll { $0.id == item.id }
                        }
                    )
                }
            }
        }
    }

    private var garminPanel: some View {
        GymPanel {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: syncPlanToGarmin) {
                    Label(
                        gymText(
                            "Sync plan to Garmin",
                            "Синхронізувати план із Garmin",
                            "Синхронизировать план с Garmin",
                            languageCode: gymCurrentLanguageCode()
                        ),
                        systemImage: "applewatch.radiowaves.left.and.right"
                    )
                }
                .buttonStyle(GymSecondaryButtonStyle())
                .disabled(
                    drafts.isEmpty || garminCloud.isWorking || garminCloud.selectedDevice == nil
                )
                Text(
                    garminCloud.selectedDevice == nil
                        ? gymText(
                            "Select or pair a Garmin watch in Account settings before syncing a plan.",
                            "Вибери або під’єднай годинник Garmin у налаштуваннях облікового запису перед синхронізацією плану.",
                            "Выбери или подключи часы Garmin в настройках аккаунта перед синхронизацией плана.",
                            languageCode: gymCurrentLanguageCode()
                        )
                        : gymText(
                            "The current edited plan is sent to the selected watch. No workout is saved or started.",
                            "Поточний відредагований план буде надіслано на вибраний годинник. Тренування не буде збережено чи розпочато.",
                            "Текущий отредактированный план будет отправлен на выбранные часы. Тренировка не будет сохранена или начата.",
                            languageCode: gymCurrentLanguageCode()
                        )
                )
                    .font(.caption)
                    .foregroundStyle(GymTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if garminCloud.isWorking {
                    ProgressView(gymText(
                        "Syncing plan…",
                        "Синхронізація плану…",
                        "Синхронизация плана…",
                        languageCode: gymCurrentLanguageCode()
                    ))
                }
            }
        }
    }

    private var startWorkoutButton: some View {
        Button(action: startWorkout) {
            Label(
                gymText(
                    "Start workout",
                    "Почати тренування",
                    "Начать тренировку",
                    languageCode: gymCurrentLanguageCode()
                ),
                systemImage: "play.circle.fill"
            )
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .disabled(isSaving || drafts.isEmpty || activeWorkoutStore.draft != nil)
        .accessibilityHint(
            gymText(
                "Saves this plan locally so sets can be recorded one by one",
                "Зберігає цей план локально, щоб записувати підходи по одному",
                "Сохраняет этот план локально, чтобы записывать подходы по одному",
                languageCode: gymCurrentLanguageCode()
            )
        )
    }

    private var secondaryOptions: some View {
        GymPanel {
            DisclosureGroup(isExpanded: $secondaryOptionsExpanded) {
                LazyVStack(spacing: 12) {
                    sessionDetails
                    templatePanel

                    if isCloudAccount {
                        garminPanel
                    }

                    shareDraftButton

                    Button(action: saveCompletedWorkout) {
                        if isSaving {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Saving…")
                            }
                        } else {
                            Label("Save as completed workout", systemImage: "checkmark.circle.fill")
                        }
                    }
                    .buttonStyle(GymSecondaryButtonStyle())
                    .disabled(isSaving || drafts.isEmpty)
                    .accessibilityHint("Adds every planned row to history and summaries as completed")
                }
                .padding(.top, 12)
            } label: {
                Label(
                    gymText(
                        "More options",
                        "Додаткові параметри",
                        "Дополнительные параметры",
                        languageCode: gymCurrentLanguageCode()
                    ),
                    systemImage: "slider.horizontal.3"
                )
                .font(.headline)
            }
        }
    }

    @ViewBuilder
    private var shareDraftButton: some View {
        let languageCode = gymCurrentLanguageCode()
        Button(action: openWorkoutShareChooser) {
            Label(
                GarminWorkoutDetailCopy.shareWorkout(languageCode: languageCode),
                systemImage: "square.and.arrow.up"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GymSecondaryButtonStyle())
        .disabled(isSaving || drafts.isEmpty)
        .accessibilityHint(
            t(
                "Choose a link, a separate copy, or a live workout with a friend",
                "Обери посилання, окрему копію або живе тренування з другом",
                "Выбери ссылку, отдельную копию или живую тренировку с другом"
            )
        )

        Text(GarminWorkoutDetailCopy.sharePrivacy(languageCode: languageCode))
            .font(.caption)
            .foregroundStyle(GymTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var workoutShareChooser: some View {
        NavigationStack {
            GymBackground {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        GymHeroPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(
                                    t("Share workout", "Поділитися тренуванням", "Поделиться тренировкой"),
                                    systemImage: "person.2.wave.2.fill"
                                )
                                .font(.title2.bold())
                                Text(
                                    t(
                                        "Share a link, send an editable copy, or invite a friend to train live.",
                                        "Поділися посиланням, надішли редаговану копію або запроси друга тренуватися наживо.",
                                        "Поделись ссылкой, отправь редактируемую копию или пригласи друга тренироваться вживую."
                                    )
                                )
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.84))
                            }
                        }

                        if let shareChooserMessage {
                            GymStatusBanner(
                                message: shareChooserMessage,
                                isError: shareChooserMessageIsError
                            )
                        }

                        GymPanel(highlighted: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                GymSectionTitle(
                                    title: t("Use another app", "Надіслати через інший застосунок", "Отправить через другое приложение"),
                                    supporting: t(
                                        "The existing GymApp link works without adding the recipient as a friend.",
                                        "Звичайне посилання GymApp працює без додавання отримувача в друзі.",
                                        "Обычная ссылка GymApp работает без добавления получателя в друзья."
                                    )
                                )
                                if let shareURL = sharingPlanURL {
                                    ShareLink(
                                        item: shareURL,
                                        subject: Text(gymLocalized("GymApp workout")),
                                        message: Text(
                                            GarminWorkoutDetailCopy.shareMessage(
                                                languageCode: gymCurrentLanguageCode()
                                            )
                                        )
                                    ) {
                                        Label(
                                            t("Share link", "Поділитися посиланням", "Поделиться ссылкой"),
                                            systemImage: "link"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(GymSecondaryButtonStyle())
                                }
                            }
                        }

                        GymPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                GymSectionTitle(
                                    title: t("Copy or live", "Копія або наживо", "Копия или вживую"),
                                    supporting: t(
                                        "A copy stays independent. Live freezes the plan for two people and shows each person's set progress.",
                                        "Копія залишається незалежною. Наживо фіксує план для двох і показує прогрес підходів кожного.",
                                        "Копия остаётся независимой. Живой режим фиксирует план для двоих и показывает прогресс подходов каждого."
                                    )
                                )

                                if !isCloudAccount || loadSocialDashboard == nil || sendSocialWorkoutInvite == nil {
                                    Text(
                                        t(
                                            "Sign in to a cloud account to send workouts directly to friends.",
                                            "Увійди в хмарний акаунт, щоб надсилати тренування друзям напряму.",
                                            "Войди в облачный аккаунт, чтобы отправлять тренировки друзьям напрямую."
                                        )
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(GymTheme.textSecondary)
                                } else if shareFriendsAreLoading {
                                    HStack(spacing: 10) {
                                        ProgressView()
                                        Text(t("Loading friends…", "Завантажуємо друзів…", "Загружаем друзей…"))
                                    }
                                } else if shareFriends.isEmpty {
                                    Text(
                                        t(
                                            "No accepted friends yet. Add a friend from Profile, or use the link above.",
                                            "Ще немає прийнятих друзів. Додай друга у Профілі або скористайся посиланням вище.",
                                            "Принятых друзей пока нет. Добавь друга в Профиле или используй ссылку выше."
                                        )
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(GymTheme.textSecondary)
                                } else {
                                    ForEach(shareFriends) { friend in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 10) {
                                                Image(systemName: "person.crop.circle.fill")
                                                Text(friend.displayName)
                                                    .lineLimit(1)
                                                Spacer()
                                                if sharingFriendID == friend.profileID {
                                                    ProgressView()
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            HStack(spacing: 8) {
                                                Button {
                                                    Task { await sendWorkoutInvite(to: friend, live: false) }
                                                } label: {
                                                    Label(
                                                        t("Send copy", "Надіслати копію", "Отправить копию"),
                                                        systemImage: "doc.on.doc"
                                                    )
                                                }
                                                .buttonStyle(.bordered)

                                                Button {
                                                    Task { await sendWorkoutInvite(to: friend, live: true) }
                                                } label: {
                                                    Label(
                                                        t("Invite live", "Запросити наживо", "Пригласить вживую"),
                                                        systemImage: "wave.3.right.circle.fill"
                                                    )
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(sendLiveWorkoutInvite == nil)
                                            }
                                        }
                                        .padding(10)
                                        .background(GymTheme.surfaceVariant.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                                        .disabled(sharingFriendID != nil)
                                    }
                                }

                                if isCloudAccount, !shareFriendsAreLoading {
                                    Button {
                                        Task { await loadShareFriends(force: true) }
                                    } label: {
                                        Label(
                                            t("Refresh friends", "Оновити друзів", "Обновить друзей"),
                                            systemImage: "arrow.clockwise"
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(sharingFriendID != nil)
                                }
                            }
                        }

                        Text(
                            t(
                                "Only the plan is sent before acceptance. In live mode, completed set values and live progress are visible only to the two participants. Notes, Health data and account secrets stay private.",
                                "До прийняття надсилається лише план. У живому режимі значення виконаних підходів і прогрес бачать лише двоє учасників. Нотатки, дані Health і секрети акаунта залишаються приватними.",
                                "До принятия отправляется только план. В живом режиме значения выполненных подходов и прогресс видят только двое участников. Заметки, данные Health и секреты аккаунта остаются приватными."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(t("Share workout", "Поділитися", "Поделиться"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Done", "Готово", "Готово")) {
                        showingShareChooser = false
                    }
                }
            }
        }
    }

    private var sharingPlanURL: URL? {
        guard let sharingPlan else { return nil }
        return try? SharedWorkoutLinkEncoder.makeURL(plan: sharingPlan)
    }

    private var sharedWorkoutExercisesByID: [UUID: Exercise] {
        var exercisesByID: [UUID: Exercise] = [:]
        for exercise in store.exercises {
            exercisesByID[exercise.id] = exercise
        }
        return exercisesByID
    }

    private func showDraftShareError() {
        do {
            _ = try makeSharedWorkoutDraftURL(
                drafts: drafts,
                exercises: sharedWorkoutExercisesByID
            )
        } catch SharedWorkoutLinkError.missingExercise {
            show(gymLocalized("One selected exercise no longer exists."), error: true)
        } catch SharedWorkoutLinkError.invalidWeight {
            show(
                gymText(
                    "Choose a working weight before sharing.",
                    "Обери робочу вагу перед поширенням.",
                    "Выбери рабочий вес перед отправкой.",
                    languageCode: gymCurrentLanguageCode()
                ),
                error: true
            )
        } catch SharedWorkoutLinkError.invalidRepetitions {
            show(gymLocalized("Repetitions must be at least one."), error: true)
        } catch {
            show(
                gymText(
                    "This plan cannot be shared. Use no more than 20 exercises, 12 sets per exercise, and 120 sets total.",
                    "Цим планом не можна поділитися. Використай не більше 20 вправ, 12 підходів на вправу та 120 підходів загалом.",
                    "Этим планом нельзя поделиться. Используй не больше 20 упражнений, 12 подходов на упражнение и 120 подходов всего.",
                    languageCode: gymCurrentLanguageCode()
                ),
                error: true
            )
        }
    }

    private func openWorkoutShareChooser() {
        do {
            sharingPlan = try makeSharedWorkoutDraftPlan(
                drafts: drafts,
                exercises: sharedWorkoutExercisesByID
            )
            shareChooserMessage = nil
            shareChooserMessageIsError = false
            showingShareChooser = true
            Task { await loadShareFriends(force: false) }
        } catch {
            showDraftShareError()
        }
    }

    private func loadShareFriends(force: Bool) async {
        guard isCloudAccount, let loadSocialDashboard else {
            shareFriends = []
            return
        }
        guard !shareFriendsAreLoading, force || shareFriends.isEmpty else { return }
        shareFriendsAreLoading = true
        if force {
            shareChooserMessage = nil
            shareChooserMessageIsError = false
        }
        defer { shareFriendsAreLoading = false }
        do {
            let dashboard = try await loadSocialDashboard()
            shareFriends = dashboard.friends.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        } catch {
            shareFriends = []
            shareChooserMessage = t(
                "Friends could not be loaded safely. You can still share a link.",
                "Не вдалося безпечно завантажити друзів. Посиланням усе ще можна поділитися.",
                "Не удалось безопасно загрузить друзей. Ссылкой всё ещё можно поделиться."
            )
            shareChooserMessageIsError = true
        }
    }

    private func sendWorkoutInvite(to friend: SocialFriendSummary, live: Bool) async {
        guard sharingFriendID == nil,
              let plan = sharingPlan,
              let sender = live ? sendLiveWorkoutInvite : sendSocialWorkoutInvite else { return }
        sharingFriendID = friend.profileID
        shareChooserMessage = nil
        shareChooserMessageIsError = false
        defer { sharingFriendID = nil }
        do {
            try await sender(friend.profileID, plan)
            shareChooserMessage = live
                ? t(
                    "Live invitation sent. The plan is frozen; your friend joins the lobby before you start.",
                    "Живе запрошення надіслано. План зафіксовано; друг приєднається до лобі до твого старту.",
                    "Живое приглашение отправлено. План зафиксирован; друг присоединится к лобби до твоего старта."
                )
                : t(
                    "Copy invitation submitted. If this friend is available, it will appear in their workout inbox.",
                    "Запрошення з копією надіслано. Якщо друг доступний, воно з’явиться у вхідних тренуваннях.",
                    "Приглашение с копией отправлено. Если друг доступен, оно появится во входящих тренировках."
                )
        } catch {
            shareChooserMessage = t(
                "The invitation could not be submitted safely. Refresh friends and try again.",
                "Не вдалося безпечно надіслати запрошення. Онови друзів і спробуй ще раз.",
                "Не удалось безопасно отправить приглашение. Обнови друзей и попробуй ещё раз."
            )
            shareChooserMessageIsError = true
        }
    }

    private func t(_ english: String, _ ukrainian: String, _ russian: String) -> String {
        gymText(english, ukrainian, russian, languageCode: gymCurrentLanguageCode())
    }

    private func binding(for id: UUID) -> Binding<WorkoutEditorExerciseDraft> {
        Binding(
            get: { drafts.first(where: { $0.id == id }) ?? WorkoutEditorExerciseDraft(exerciseID: UUID()) },
            set: { value in
                guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
                var editedValue = value
                editedValue.coachRecommendation = nil
                if smartGeneratedDraftIDs.remove(id) != nil {
                    smartPlanIsStale = true
                }
                latestSmartPlan = nil
                drafts[index] = editedValue
            }
        )
    }

    private func exerciseName(_ exerciseID: UUID) -> String {
        store.exercise(id: exerciseID).map { gymExerciseName($0) } ?? gymLocalized("Deleted exercise")
    }

    private var exerciseSessionCounts: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: store.exercises.map { exercise in
                (exercise.id, store.progressStats(exerciseID: exercise.id).sessionCount)
            }
        )
    }

    private func addExercise(_ exercise: Exercise) {
        guard !drafts.contains(where: { $0.exerciseID == exercise.id }) else { return }
        latestSmartPlan = nil
        smartPlanIsStale = !smartGeneratedDraftIDs.isEmpty
        drafts.insert(
            WorkoutEditorExerciseDraft(
                exerciseID: exercise.id,
                sets: [
                    WorkoutEditorSetDraft(
                        weight: store.lastWeight(exerciseID: exercise.id) ?? 0,
                        reps: 10
                    )
                ]
            ),
            at: 0
        )
    }

    private func applyPreviousWorkout(_ workout: WorkoutSession) {
        latestSmartPlan = nil
        smartGeneratedDraftIDs.removeAll()
        smartPlanIsStale = false
        drafts = workout.exercises.map { block in
            WorkoutEditorExerciseDraft(
                exerciseID: block.exerciseID,
                sets: block.sets.map { WorkoutEditorSetDraft(weight: $0.weight, reps: $0.reps) }
            )
        }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            note = workout.note ?? ""
        }
        show(gymLocalized("Previous workout copied. Adjust any set before saving."), error: false)
    }

    private func applyTemplate(_ preset: WorkoutTemplatePreset) {
        latestSmartPlan = nil
        smartGeneratedDraftIDs.removeAll()
        smartPlanIsStale = false
        if preset == .deload {
            guard let latest = store.latestWorkoutTemplate else {
                show(gymLocalized("A deload template needs a previous workout."), error: true)
                return
            }
            drafts = latest.exercises.map { block in
                WorkoutEditorExerciseDraft(
                    exerciseID: block.exerciseID,
                    sets: block.sets.map {
                        WorkoutEditorSetDraft(
                            weight: (($0.weight * 0.9) * 2).rounded() / 2,
                            reps: min(10_000, $0.reps + 1)
                        )
                    }
                )
            }
            note = note.isEmpty ? gymLocalized("Deload") : note
            show(gymLocalized("Deload uses 90% of the latest weights with one extra repetition."), error: false)
            return
        }

        let candidates = store.exercises
            .map { exercise in
                (
                    exercise,
                    Set(MuscleMappingEngine.defaultContributions(for: exercise.name).map(\.muscleID))
                        .intersection(preset.targetMuscles).count,
                    store.exerciseHistory(exerciseID: exercise.id).first?.sessionDate ?? .distantPast
                )
            }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.2 != $1.2 { return $0.2 < $1.2 }
                return gymExerciseName($0.0).localizedCaseInsensitiveCompare(gymExerciseName($1.0)) == .orderedAscending
            }
            .prefix(preset == .upper ? 6 : 5)

        guard !candidates.isEmpty else {
            show(gymLocalized("No matching exercises are in your catalog. Add exercises first."), error: true)
            return
        }
        let history = store.allExerciseHistory()
        drafts = candidates.map { exercise, _, _ in
            let recommendation = RecommendationEngine.buildForExercise(
                exerciseID: exercise.id,
                history: history,
                exerciseCatalogKey: exercise.catalogKey,
                exerciseName: exercise.name,
                machineLoadProfile: exercise.machineLoadProfile,
                trainingProfile: profile
            )
            return WorkoutEditorExerciseDraft(
                exerciseID: exercise.id,
                sets: recommendation.sets.map {
                    WorkoutEditorSetDraft(
                        weight: $0.weight ?? store.lastWeight(exerciseID: exercise.id) ?? 0,
                        reps: $0.reps
                    )
                }
            )
        }
        show(
            gymText(
                "\(preset.title) template loaded from your exercise catalog.",
                "Шаблон «\(preset.title)» завантажено з каталогу вправ.",
                "Шаблон «\(preset.title)» загружен из каталога упражнений.",
                languageCode: gymCurrentLanguageCode()
            ),
            error: false
        )
    }

    private func applySmartCoach() {
        let plan = RecommendationEngine.buildWorkoutPlan(
            exercises: store.exercises,
            history: store.allExerciseHistory(),
            muscleMappings: store.muscleMappings,
            trainingProfile: profile,
            effort: selectedEffort,
            latestFeedback: store.latestWorkoutFeedbackContext()
        )
        guard !plan.exercises.isEmpty else {
            show(gymLocalized("Smart Coach needs exercises in your catalog."), error: true)
            return
        }
        let generatedDrafts = makeWorkoutEditorDrafts(from: plan)
        if smartPlanIsStale {
            let manualDrafts = drafts.filter { !smartGeneratedDraftIDs.contains($0.id) }
            let manualExerciseIDs = Set(manualDrafts.map(\.exerciseID))
            let nonDuplicateGenerated = generatedDrafts.filter {
                !manualExerciseIDs.contains($0.exerciseID)
            }
            drafts = manualDrafts + nonDuplicateGenerated
            smartGeneratedDraftIDs = Set(nonDuplicateGenerated.map(\.id))
        } else {
            drafts = generatedDrafts
            smartGeneratedDraftIDs = Set(generatedDrafts.map(\.id))
        }
        smartPlanIsStale = false
        latestSmartPlan = plan
        show(
            gymText(
                "Smart Coach built a \(plan.focus.displayName.lowercased()) workout.",
                "Розумний тренер створив тренування «\(plan.focus.displayName.lowercased())».",
                "Умный тренер создал тренировку «\(plan.focus.displayName.lowercased())».",
                languageCode: gymCurrentLanguageCode()
            ),
            error: false
        )
    }

    private func showAlternatives(for draftID: UUID) {
        guard let draft = drafts.first(where: { $0.id == draftID }),
              let currentExercise = store.exercise(id: draft.exerciseID) else {
            show(gymLocalized("This exercise is no longer available."), error: true)
            return
        }
        let appliedEffort = latestSmartPlan?.appliedEffort ??
            (selectedEffort == .auto ? .standard : selectedEffort)
        let alternatives = RecommendationEngine.findAlternatives(
            currentExercise: currentExercise,
            selectedExerciseIDs: Set(drafts.map(\.exerciseID)),
            exercises: store.exercises,
            history: store.allExerciseHistory(),
            muscleMappings: store.muscleMappings,
            trainingProfile: profile,
            effort: appliedEffort,
            allowsHardSetBoost: appliedEffort == .hard && draft.sets.count == 4
        )
        replacementRequest = SmartReplacementRequest(
            draftID: draft.id,
            expectedExerciseID: draft.exerciseID,
            alternatives: alternatives
        )
    }

    private func applyAlternative(
        _ alternative: SmartWorkoutAlternative,
        request: SmartReplacementRequest
    ) {
        guard let draftIndex = drafts.firstIndex(where: {
            $0.id == request.draftID && $0.exerciseID == request.expectedExerciseID
        }), let currentExercise = store.exercise(id: request.expectedExerciseID),
            store.exercise(id: alternative.exercise.id) != nil else {
            show(gymLocalized("The workout changed. Open similar exercises again."), error: true)
            return
        }
        let appliedEffort = latestSmartPlan?.appliedEffort ??
            (selectedEffort == .auto ? .standard : selectedEffort)
        let refreshedAlternatives = RecommendationEngine.findAlternatives(
            currentExercise: currentExercise,
            selectedExerciseIDs: Set(drafts.map(\.exerciseID)),
            exercises: store.exercises,
            history: store.allExerciseHistory(),
            muscleMappings: store.muscleMappings,
            trainingProfile: profile,
            effort: appliedEffort,
            allowsHardSetBoost: appliedEffort == .hard && drafts[draftIndex].sets.count == 4
        )
        guard let refreshedAlternative = refreshedAlternatives.first(where: {
            $0.exercise.id == alternative.exercise.id
        }) else {
            show(gymLocalized("The workout changed. Open similar exercises again."), error: true)
            return
        }
        let alternativeIdentity = exerciseDraftIdentity(refreshedAlternative.exercise)
        let duplicateExists = drafts.enumerated().contains { index, draft in
            guard index != draftIndex, let exercise = store.exercise(id: draft.exerciseID) else { return false }
            return exerciseDraftIdentity(exercise) == alternativeIdentity
        }
        guard !duplicateExists else {
            show(gymLocalized("That exercise is already in this workout."), error: true)
            return
        }

        drafts[draftIndex].exerciseID = refreshedAlternative.exercise.id
        drafts[draftIndex].sets = refreshedAlternative.recommendation.sets.map {
            WorkoutEditorSetDraft(recommendedSet: $0)
        }
        drafts[draftIndex].coachRecommendation = refreshedAlternative.recommendation
        if let plan = latestSmartPlan,
           let planIndex = plan.exercises.firstIndex(where: {
               $0.exercise.id == request.expectedExerciseID
           }) {
            var updatedExercises = plan.exercises
            updatedExercises[planIndex] = SmartWorkoutExercise(
                exercise: refreshedAlternative.exercise,
                recommendation: refreshedAlternative.recommendation
            )
            latestSmartPlan = SmartWorkoutPlan(
                focus: plan.focus,
                exercises: updatedExercises,
                variant: plan.variant,
                requestedEffort: plan.requestedEffort,
                appliedEffort: plan.appliedEffort,
                effortAdjustment: plan.effortAdjustment
            )
        } else if latestSmartPlan != nil {
            latestSmartPlan = nil
        }
        show(
            gymText(
                "Replaced with \(gymExerciseName(refreshedAlternative.exercise)). Its own history and machine settings were applied.",
                "Замінено на «\(gymExerciseName(refreshedAlternative.exercise))». Застосовано історію та налаштування тренажера саме цієї вправи.",
                "Заменено на «\(gymExerciseName(refreshedAlternative.exercise))». Применены история и настройки тренажёра именно этого упражнения.",
                languageCode: gymCurrentLanguageCode()
            ),
            error: false
        )
    }

    private func exerciseDraftIdentity(_ exercise: Exercise) -> String {
        if let key = BuiltInExerciseCatalog.resolvedKey(
            catalogKey: exercise.catalogKey,
            name: exercise.name
        ) {
            return "catalog:\(key)"
        }
        return "custom:\(MuscleMappingEngine.normalizeExerciseName(exercise.name))"
    }

    private func validationMessage() -> String? {
        guard !drafts.isEmpty else { return gymLocalized("Add at least one exercise.") }
        guard date <= Date() else {
            return gymText(
                "Workout date cannot be in the future.",
                "Дата тренування не може бути в майбутньому.",
                "Дата тренировки не может быть в будущем.",
                languageCode: gymCurrentLanguageCode()
            )
        }
        for draft in drafts {
            guard store.exercise(id: draft.exerciseID) != nil else {
                return gymLocalized("One selected exercise no longer exists.")
            }
            guard !draft.sets.isEmpty else {
                return gymLocalized("Every exercise needs at least one set.")
            }
            for set in draft.sets {
                guard set.isReadyForSave else {
                    return gymText(
                        "Weight must be a finite number from 0 to 1,000,000.",
                        "Вага має бути скінченним числом від 0 до 1 000 000.",
                        "Вес должен быть конечным числом от 0 до 1 000 000.",
                        languageCode: gymCurrentLanguageCode()
                    )
                }
                guard (1 ... 10_000).contains(set.reps) else {
                    return gymLocalized("Repetitions must be at least one.")
                }
            }
        }
        return nil
    }

    private func startWorkout() {
        if let message = validationMessage() {
            show(message, error: true)
            return
        }
        do {
            let active = try activeWorkoutStore.start(
                workoutDate: date,
                note: note,
                exercises: drafts.map { exercise in
                    ActiveWorkoutExercise(
                        id: exercise.id,
                        exerciseID: exercise.exerciseID,
                        sets: exercise.sets.map { set in
                            ActiveWorkoutSet(
                                id: set.id,
                                weight: set.weight,
                                reps: set.reps
                            )
                        }
                    )
                },
                workoutStore: store
            )
            reportStatus(
                gymText(
                    "Workout started. Record each set when it is complete.",
                    "Тренування розпочато. Записуй кожен підхід після виконання.",
                    "Тренировка начата. Записывай каждый подход после выполнения.",
                    languageCode: gymCurrentLanguageCode()
                ),
                false
            )
            onStarted(active.id)
        } catch {
            show(gymErrorMessage(error), error: true)
        }
    }

    private func saveCompletedWorkout() {
        if let message = validationMessage() {
            show(message, error: true)
            return
        }
        isSaving = true
        statusMessage = nil

        do {
            let workout = try store.createWorkout(
                date: date,
                note: note,
                exercises: drafts.map(\.storeDraft)
            )
            Task { @MainActor in
                reportStatus(gymLocalized("Workout saved."), false)
                isSaving = false
                onSaved(workout.id)
            }
        } catch {
            isSaving = false
            show(gymErrorMessage(error), error: true)
        }
    }

    private var hasUnsavedPlanChanges: Bool {
        PlanEditorSnapshot(
            date: date,
            note: note,
            effort: selectedEffort,
            drafts: drafts
        ) != baselinePlanSnapshot
    }

    private func clearPlan() {
        guard !drafts.isEmpty else { return }
        drafts.removeAll()
        latestSmartPlan = nil
        smartGeneratedDraftIDs.removeAll()
        smartPlanIsStale = false
        replacementRequest = nil
        garminDraftSubmission = nil
        sharingPlan = nil
        showingShareChooser = false
        shareChooserMessage = nil
        shareChooserMessageIsError = false
        statusMessage = nil
        statusIsError = false
    }

    private func requestCancel() {
        if hasUnsavedPlanChanges {
            showingDiscardConfirmation = true
        } else {
            onCancel()
        }
    }

    private var exercisesByID: [UUID: Exercise] {
        Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0) })
    }

    private func currentGarminSyncKey(binding: GarminDeviceBinding) throws -> GarminDraftSyncKey {
        try makeGarminDraftSyncKey(
            accountStorageKey: store.accountStorageKey,
            deviceID: binding.deviceID,
            title: gymText(
                "Workout plan",
                "План тренування",
                "План тренировки",
                languageCode: gymCurrentLanguageCode()
            ),
            workoutDate: date,
            note: note,
            drafts: drafts,
            exercises: exercisesByID
        )
    }

    private func syncPlanToGarmin() {
        if let message = validationMessage() {
            show(message, error: true)
            return
        }
        guard isCloudAccount, let binding = garminCloud.selectedDevice else {
            show(gymLocalized("Select or pair a Garmin watch in Account settings before syncing a plan."), error: true)
            return
        }
        do {
            let key = try currentGarminSyncKey(binding: binding)
            let submission = try prepareGarminDraftSubmission(
                existing: garminDraftSubmission,
                key: key
            )
            garminDraftSubmission = submission
            Task { @MainActor in
                do {
                    try await garminCloud.submit(
                        plan: submission.plan,
                        clientRequestID: submission.clientRequestID
                    )
                    guard garminDraftSubmission == submission,
                          store.accountStorageKey == submission.key.accountStorageKey,
                          garminCloud.selectedDevice?.deviceID == submission.key.deviceID,
                          try currentGarminSyncKey(binding: binding) == submission.key else {
                        throw AuthServiceError.sessionChanged
                    }
                    show(
                        gymLocalized(
                            garminCloud.lastMessage
                                ?? "Plan queued. Open GymApp on the Garmin watch and choose CLOUD / SYNC."
                        ),
                        error: false
                    )
                } catch {
                    guard garminDraftSubmission == submission else { return }
                    show(gymErrorMessage(error), error: true)
                }
            }
        } catch {
            show(gymErrorMessage(error), error: true)
        }
    }

    private func show(_ message: String, error: Bool) {
        statusMessage = message
        statusIsError = error
    }

}

private struct PlanEditorSnapshot: Equatable {
    let date: Date
    let note: String
    let effort: SmartWorkoutEffort
    let drafts: [WorkoutEditorExerciseDraft]
}

private struct SmartReplacementRequest: Identifiable {
    let id = UUID()
    let draftID: UUID
    let expectedExerciseID: UUID
    let alternatives: [SmartWorkoutAlternative]
}

private struct PreviousWorkoutPicker: View {
    @Environment(\.dismiss) private var dismiss

    let workouts: [WorkoutSession]
    let exerciseName: (UUID) -> String
    let onSelect: (WorkoutSession) -> Void

    var body: some View {
        NavigationStack {
            List(workouts) { workout in
                Button {
                    onSelect(workout)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(gymFormattedDate(workout.date, date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text(workout.exercises.map { exerciseName($0.exerciseID) }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(workoutCounts(workout))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityHint("Copies this workout into the editor")
            }
            .navigationTitle("Copy workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func workoutCounts(_ workout: WorkoutSession) -> String {
        let exercises = gymCount(
            workout.exercises.count,
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
        return "\(exercises) · \(sets)"
    }
}

private extension SmartWorkoutEffort {
    var displayName: String {
        gymDisplayName
    }

    var rirText: String {
        switch self {
        case .auto, .standard: "2–3"
        case .recovery: "3–4"
        case .hard: "1–2"
        }
    }
}

private extension SmartWorkoutPlan {
    var rirSummary: String {
        let ranges = Set(exercises.map {
            "\($0.recommendation.targetRIR.lowerBound)–\($0.recommendation.targetRIR.upperBound)"
        })
        if ranges.count == 1 { return ranges.first ?? appliedEffort.rirText }
        return ["1–2", "2–3", "3–4"].filter(ranges.contains).joined(separator: " · ")
    }
}

private extension SmartWorkoutEffortAdjustment {
    var displayText: String {
        switch self {
        case .autoRecovery:
            gymText(
                "Auto selected Recovery because at least half of the target muscles were trained in the last two days.",
                "Авто вибрав відновлення, бо щонайменше половина цільових м’язів тренувалася протягом останніх двох днів.",
                "Авто выбрал восстановление, потому что как минимум половина целевых мышц тренировалась в последние два дня.",
                languageCode: gymCurrentLanguageCode()
            )
        case .autoFeedbackRecovery:
            gymText(
                "Auto selected Recovery after your latest workout felt hard.",
                "Авто вибрав відновлення, бо останнє тренування було важким.",
                "Авто выбрал восстановление, потому что последняя тренировка была тяжёлой.",
                languageCode: gymCurrentLanguageCode()
            )
        case .feedbackEasyExtraSet:
            gymText(
                "One safe set was added after your latest feedback.",
                "Після останнього відгуку додано один безпечний підхід.",
                "После последнего отзыва добавлен один безопасный подход.",
                languageCode: gymCurrentLanguageCode()
            )
        case .hardInsufficientHistory:
            gymText(
                "Hard was changed to Standard because fewer than two workouts are available.",
                "Важкий режим змінено на стандартний, бо доступно менше двох тренувань.",
                "Тяжёлый режим изменён на стандартный, потому что доступно меньше двух тренировок.",
                languageCode: gymCurrentLanguageCode()
            )
        case .hardLongBreak:
            gymText(
                "Hard was changed to Standard after a long training break.",
                "Важкий режим змінено на стандартний після тривалої перерви.",
                "Тяжёлый режим изменён на стандартный после длительного перерыва.",
                languageCode: gymCurrentLanguageCode()
            )
        case .hardTargetNotRecovered:
            gymText(
                "Hard was changed to Standard because at least half of the target muscles are still recovering.",
                "Важкий режим змінено на стандартний, бо щонайменше половина цільових м’язів ще відновлюється.",
                "Тяжёлый режим изменён на стандартный, потому что как минимум половина целевых мышц ещё восстанавливается.",
                languageCode: gymCurrentLanguageCode()
            )
        }
    }
}
