import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @ObservedObject private var appState: AppState
    @ObservedObject private var auth: AuthService
    @ObservedObject private var nativePush: NativePushManager

    @State private var showsIntro = true
    @State private var showsPasswordUpdate = false

    init(appState: AppState, nativePush: NativePushManager) {
        self.appState = appState
        self.auth = appState.auth
        self.nativePush = nativePush
    }

    var body: some View {
        Group {
            if auth.session == nil {
                AuthView(authService: auth)
            } else if let conflict = appState.cloudSyncConflict {
                CloudSyncConflictView(
                    summary: conflict,
                    isWorking: appState.isResolvingCloudSyncConflict,
                    message: appState.accountPreparationError,
                    backupData: appState.cloudSyncConflictBackupData,
                    keepIPhone: {
                        appState.resolveCloudSyncConflict(useCloudVersion: false)
                    },
                    useCloud: {
                        appState.resolveCloudSyncConflict(useCloudVersion: true)
                    },
                    signOut: { Task { _ = await appState.signOut() } }
                )
            } else if appState.isAccountReady {
                MainTabShell(appState: appState, nativePush: nativePush)
                    .environmentObject(appState.workoutStore)
                    .id(appState.activeAccountStorageKey)
            } else {
                AccountPreparationView(
                    isWorking: appState.isPreparingAccount,
                    message: appState.accountPreparationError,
                    retry: appState.retryAccountActivation,
                    signOut: { Task { _ = await appState.signOut() } }
                )
            }
        }
        // Keep presentations alive while the in-app language changes. MainTabShell and
        // active workout surfaces observe the same AppStorage value and redraw in place.
        .environment(\.locale, AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en"))
        .allowsHitTesting(!appState.isSigningOut)
        .overlay {
            if appState.isSigningOut {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel("Please wait…")
                }
                .zIndex(30)
            }
        }
        .overlay {
            if showsIntro {
                IntroSplashView()
                    .environment(
                        \.locale,
                        AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en")
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(20)
            }
        }
        .sheet(isPresented: $showsPasswordUpdate) {
            PasswordUpdateView(auth: auth) {
                showsPasswordUpdate = false
            }
        }
        .onChange(of: auth.needsPasswordUpdate) { needsUpdate in
            showsPasswordUpdate = needsUpdate
        }
        .onChange(of: appState.isAccountReady) { isReady in
            guard isReady, auth.session?.cloud != nil else { return }
            Task {
                await nativePush.activateIfNeeded()
                await refreshSocialSurfaces()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                appState.saveBeforeBackgrounding()
            } else if phase == .active, appState.isAccountReady, auth.session?.cloud != nil {
                Task {
                    await nativePush.activateIfNeeded()
                    await refreshSocialSurfaces()
                }
            }
        }
        .task {
#if DEBUG
            await appState.bootstrapDemoIfRequested()
#endif
            if appState.isAccountReady, auth.session?.cloud != nil {
                await nativePush.activateIfNeeded()
                await refreshSocialSurfaces()
            }
            showsPasswordUpdate = auth.needsPasswordUpdate
            try? await Task.sleep(for: .milliseconds(1_400))
            withAnimation(.easeOut(duration: 0.28)) {
                showsIntro = false
            }
        }
    }

    private func refreshSocialSurfaces() async {
        _ = try? await appState.refreshSocialDashboard()
        _ = try? await appState.refreshSocialWorkoutInbox()
    }
}

private struct CloudSyncConflictView: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    let summary: AppState.CloudSyncConflictSummary
    let isWorking: Bool
    let message: String?
    let backupData: () throws -> Data
    let keepIPhone: () -> Void
    let useCloud: () -> Void
    let signOut: () -> Void

    @State private var exportDocument: CloudSyncConflictExportDocument?
    @State private var showsExporter = false
    @State private var exportError: String?

    var body: some View {
        GymBackground {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GymSectionTitle(
                        eyebrow: gymText(
                            "Workout sync",
                            "Синхронізація тренувань",
                            languageCode: languageCode
                        ),
                        title: gymText(
                            "Which workout history should GymApp keep?",
                            "Яку історію тренувань зберегти?",
                            languageCode: languageCode
                        ),
                        supporting: gymText(
                            "This iPhone and the cloud contain different changes. Nothing has been deleted or overwritten.",
                            "На цьому iPhone та в хмарі різні зміни. Поки що нічого не видалено й не перезаписано.",
                            languageCode: languageCode
                        )
                    )

                    GymPanel(highlighted: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            conflictCount(
                                title: gymText(
                                    "On this iPhone",
                                    "На цьому iPhone",
                                    languageCode: languageCode
                                ),
                                count: summary.localWorkoutCount,
                                systemImage: "iphone"
                            )
                            conflictCount(
                                title: gymText(
                                    "In the cloud",
                                    "У хмарі",
                                    languageCode: languageCode
                                ),
                                count: summary.cloudWorkoutCount,
                                systemImage: "icloud"
                            )
                        }
                    }

                    if let visibleMessage = exportError ?? message {
                        GymStatusBanner(message: visibleMessage, isError: true)
                    }

                    GymPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(
                                gymText(
                                    "Choose this if your latest workouts were recorded on this iPhone. This history will replace the cloud copy.",
                                    "Вибери це, якщо останні тренування записував на цьому iPhone. Ця історія замінить хмарну копію.",
                                    languageCode: languageCode
                                )
                            )
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)

                            Button(action: keepIPhone) {
                                Label(
                                    gymText(
                                        "Keep workouts from this iPhone",
                                        "Зберегти тренування з цього iPhone",
                                        languageCode: languageCode
                                    ),
                                    systemImage: "iphone.and.arrow.forward"
                                )
                                .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWorking)

                            Text(
                                gymText(
                                    "Choose this if your latest workouts were recorded on another device or in the PWA. The cloud history will replace workouts on this iPhone.",
                                    "Вибери це, якщо останні тренування записував на іншому пристрої або в PWA. Хмарна історія замінить тренування на цьому iPhone.",
                                    languageCode: languageCode
                                )
                            )
                            .font(.subheadline)
                            .foregroundStyle(GymTheme.textSecondary)

                            Button(action: useCloud) {
                                Label(
                                    gymText(
                                        "Use workouts from the cloud",
                                        "Завантажити тренування з хмари",
                                        languageCode: languageCode
                                    ),
                                    systemImage: "icloud.and.arrow.down"
                                )
                                .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(isWorking)

                            Button(action: prepareBackup) {
                                Label(
                                    gymText(
                                        "Back up this iPhone first",
                                        "Спочатку зробити копію цього iPhone",
                                        languageCode: languageCode
                                    ),
                                    systemImage: "square.and.arrow.up"
                                )
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isWorking)

                            Button(action: signOut) {
                                Text(
                                    gymText(
                                        "Sign out without changes",
                                        "Вийти без змін",
                                        languageCode: languageCode
                                    )
                                )
                                .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                        }
                    }

                    if isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(
                                gymText(
                                    "Checking both histories again…",
                                    "Знову перевіряємо обидві історії…",
                                    languageCode: languageCode
                                )
                            )
                            .foregroundStyle(GymTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "GymApp-iPhone-backup"
        ) { result in
            exportDocument = nil
            if case let .failure(error) = result {
                exportError = gymErrorMessage(error)
            }
        }
    }

    private func conflictCount(
        title: String,
        count: Int,
        systemImage: String
    ) -> some View {
        let savedWorkouts = gymText(
            "Saved workouts",
            "Збережено тренувань",
            languageCode: languageCode
        )
        return HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(GymTheme.primary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("\(savedWorkouts): \(count)")
                .font(.subheadline)
                .foregroundStyle(GymTheme.textSecondary)
            }
        }
    }

    private func prepareBackup() {
        do {
            exportError = nil
            exportDocument = CloudSyncConflictExportDocument(data: try backupData())
            showsExporter = true
        } catch {
            exportError = gymErrorMessage(error)
        }
    }
}

private struct CloudSyncConflictExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct AccountPreparationView: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    let isWorking: Bool
    let message: String?
    let retry: () -> Void
    let signOut: () -> Void

    var body: some View {
        GymContentUnavailableView {
            Label(
                gymText("Preparing account", "Підготовка акаунта", languageCode: languageCode),
                systemImage: isWorking ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.exclamationmark"
            )
        } description: {
            Text(
                message ?? gymText(
                    "Opening this account's protected workout data.",
                    "Відкриваємо захищені дані тренувань цього акаунта.",
                    languageCode: languageCode
                )
            )
        } actions: {
            if isWorking {
                ProgressView()
            } else {
                Button(
                    gymText("Try again", "Спробувати ще раз", languageCode: languageCode),
                    action: retry
                )
                .buttonStyle(.borderedProminent)
                Button(
                    gymText("Sign out", "Вийти", languageCode: languageCode),
                    action: signOut
                )
                .buttonStyle(.bordered)
            }
        }
    }
}

enum NativePushProfileFocus: Hashable, Sendable {
    case friends
    case friendRequest(String)
    case workoutInvite(String)
    case liveWorkouts
    case liveRoom(String)
}

struct NativePushProfileRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let focus: NativePushProfileFocus
}

func makeNativePushProfileRequest(for route: NativePushRoute) -> NativePushProfileRequest {
    let focus: NativePushProfileFocus
    switch route.target {
    case .social:
        focus = .friends
    case let .socialObject(object):
        switch object.eventType {
        case .friendRequestReceived, .friendRequestAccepted:
            focus = .friendRequest(object.objectID)
        case .workoutInviteReceived, .workoutInviteAccepted:
            focus = .workoutInvite(object.objectID)
        case .liveInviteReceived, .liveInviteAccepted, .liveRoomStarted,
             .liveParticipantFinished, .liveRoomClosed:
            focus = .friends
        }
    case let .live(roomID):
        focus = roomID.map(NativePushProfileFocus.liveRoom) ?? .liveWorkouts
    }
    return NativePushProfileRequest(id: route.id, focus: focus)
}

@MainActor
private struct MainTabShell: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case workouts, exercises, progress, profile
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .workouts: "calendar"
            case .exercises: "dumbbell.fill"
            case .progress: "chart.xyaxis.line"
            case .profile: "person.crop.circle.fill"
            }
        }

        func title(_ language: String) -> String {
            switch self {
            case .workouts: gymText("Today", "Сьогодні", "Сегодня", languageCode: language)
            case .exercises: gymText("Exercises", "Вправи", languageCode: language)
            case .progress: gymText("Progress", "Прогрес", languageCode: language)
            case .profile: gymText("Profile", "Профіль", languageCode: language)
            }
        }
    }

    private enum WorkoutRoute: Hashable {
        case detail(UUID)
        case summary(UUID)
        case ranks
    }

    private enum MissionRoute: Hashable {
        case ranks
    }

    @ObservedObject var appState: AppState
    @ObservedObject private var auth: AuthService
    @ObservedObject private var store: WorkoutStore
    @ObservedObject private var nativePush: NativePushManager
    @StateObject private var activeWorkoutStore: ActiveWorkoutStore
    @StateObject private var liveWorkoutCoordinator: LiveWorkoutCoordinator
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @Environment(\.openURL) private var openURL

    @State private var selectedTab: Tab
    @State private var workoutPath: [WorkoutRoute] = []
    @State private var missionPath: [MissionRoute] = []
    @State private var showsAddWorkout = false
    @State private var showsActiveWorkout = false
    @State private var showsSharedWorkoutPreview = false
    @State private var sharedWorkoutDraftSeed: [WorkoutExerciseDraft] = []
    @State private var workoutLaunchSeed: WorkoutLaunchSeed?
    @State private var workoutLaunchConsumerID: UUID?
    @State private var workoutLaunchDrafts: [WorkoutEditorExerciseDraft]?
    @State private var workoutEditorDraft: WorkoutPlanEditorDraftState?
    @State private var workoutEditorLiveRecipient: SocialFriendSummary?
    @State private var profileNavigationID = UUID()
    @State private var sharedWorkoutDraftTransitionID: UUID?
    @State private var showingActiveDraftDiscardConfirmation = false
    @State private var nativePushProfileRequest: NativePushProfileRequest?
    @State private var isResolvingNativePushRoute = false
    @State private var resolvingNativePushRouteID: UUID?
    @State private var tutorialStepIndex: Int?
    @State private var tutorialIsManualReplay = false
    @State private var tutorialAutomaticPresentationSuppressedForSession = false
    @State private var tutorialTask: Task<Void, Never>?
    @State private var tutorialPrimaryActionGlobalFrame: CGRect?

    init(appState: AppState, nativePush: NativePushManager) {
        self.appState = appState
        self.auth = appState.auth
        self.nativePush = nativePush
        let currentStore = appState.workoutStore
        self.store = currentStore
        let activeStore = ActiveWorkoutStore(
            accountStorageKey: currentStore.accountStorageKey,
            workoutStorageURL: currentStore.storageURL
        )
        try? activeStore.rebindExercises(to: currentStore)
        let planDraftStore = WorkoutPlanEditorDraftStore()
        let persistedPlanDraft: WorkoutPlanEditorDraftState?
        if activeStore.draft == nil {
            persistedPlanDraft = planDraftStore.load(
                accountStorageKey: currentStore.accountStorageKey
            )
        } else {
            planDraftStore.clear(accountStorageKey: currentStore.accountStorageKey)
            persistedPlanDraft = nil
        }
        _workoutEditorDraft = State(initialValue: persistedPlanDraft)
        _activeWorkoutStore = StateObject(
            wrappedValue: activeStore
        )
        _liveWorkoutCoordinator = StateObject(
            wrappedValue: LiveWorkoutCoordinator(
                auth: appState.auth,
                workoutStore: currentStore,
                activeWorkoutStore: activeStore
            )
        )
        let requested = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--screenshot-tab=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
        let tutorialScreenshotIndex = appTutorialScreenshotStepIndex(
            arguments: ProcessInfo.processInfo.arguments
        )
        let tutorialTab: Tab?
        switch tutorialScreenshotIndex {
        case 0, 1: tutorialTab = .workouts
        case 2: tutorialTab = .exercises
        case 3: tutorialTab = .progress
        case 4: tutorialTab = .profile
        default: tutorialTab = nil
        }
        let requestedTab = requested == "rating" || requested == "friends"
            ? Tab.profile
            : requested.flatMap(Tab.init(rawValue:))
        _selectedTab = State(initialValue: tutorialTab ?? requestedTab ?? .workouts)
        _tutorialStepIndex = State(initialValue: tutorialScreenshotIndex)
        _tutorialIsManualReplay = State(initialValue: tutorialScreenshotIndex != nil)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            workoutsTab
                .tabItem { Label(Tab.workouts.title(languageCode), systemImage: Tab.workouts.icon) }
                .tag(Tab.workouts)
                .accessibilityIdentifier("tab-workouts")

            exercisesTab
                .tabItem { Label(Tab.exercises.title(languageCode), systemImage: Tab.exercises.icon) }
                .tag(Tab.exercises)
                .accessibilityIdentifier("tab-exercises")

            progressTab
                .tabItem { Label(Tab.progress.title(languageCode), systemImage: Tab.progress.icon) }
                .tag(Tab.progress)
                .accessibilityIdentifier("tab-progress")

            profileTab
                .tabItem { Label(Tab.profile.title(languageCode), systemImage: Tab.profile.icon) }
                .badge(
                    (appState.socialWorkoutInbox?.pendingIncomingCount ?? 0) +
                        liveWorkoutCoordinator.pendingInvitationCount
                )
                .tag(Tab.profile)
                .accessibilityIdentifier("tab-profile")
        }
        .tint(GymTheme.primary)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $showsAddWorkout) {
            NavigationStack {
                AddWorkoutView(
                    appState: appState,
                    activeWorkoutStore: activeWorkoutStore,
                    liveWorkoutCoordinator: liveWorkoutCoordinator,
                    initialDrafts: sharedWorkoutDraftSeed,
                    launchSeed: workoutLaunchSeed,
                    launchSeedConsumerID: workoutLaunchConsumerID,
                    launchSeedDrafts: workoutLaunchDrafts,
                    restoredDraft: workoutEditorDraft,
                    liveInviteRecipient: workoutEditorLiveRecipient,
                    onStarted: { _ in
                        workoutEditorDraft = nil
                        workoutEditorLiveRecipient = nil
                        sharedWorkoutDraftSeed = []
                        workoutLaunchSeed = nil
                        workoutLaunchConsumerID = nil
                        workoutLaunchDrafts = nil
                        showsAddWorkout = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            showsActiveWorkout = true
                        }
                    },
                    onSaved: { workoutID in
                        workoutEditorDraft = nil
                        workoutEditorLiveRecipient = nil
                        sharedWorkoutDraftSeed = []
                        workoutLaunchSeed = nil
                        workoutLaunchConsumerID = nil
                        workoutLaunchDrafts = nil
                        showsAddWorkout = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            workoutPath.append(.summary(workoutID))
                        }
                    },
                    onClose: {
                        showsAddWorkout = false
                    },
                    onDiscard: {
                        workoutEditorDraft = nil
                        workoutEditorLiveRecipient = nil
                        sharedWorkoutDraftSeed = []
                        workoutLaunchSeed = nil
                        workoutLaunchConsumerID = nil
                        workoutLaunchDrafts = nil
                        showsAddWorkout = false
                    },
                    onDraftChange: { draft in
                        guard activeWorkoutStore.draft == nil,
                              draft.belongs(to: store.accountStorageKey) else { return }
                        workoutEditorDraft = draft
                    },
                    onLiveInviteSent: {
                        reconcileConfirmedLiveDraftConsumption()
                    }
                )
            }
            .environmentObject(appState)
            .environmentObject(auth)
            .environmentObject(store)
        }
        .sheet(
            isPresented: $showsSharedWorkoutPreview,
            onDismiss: dismissSharedWorkoutPreviewIfNeeded
        ) {
            if let pending = appState.pendingSharedWorkout {
                SharedWorkoutPreviewView(
                    pending: pending,
                    languageCode: languageCode,
                    canOpenAsDraft: activeWorkoutStore.draft == nil
                        && workoutEditorDraft == nil
                        && !showsAddWorkout,
                    onOpenAsDraft: { openSharedWorkoutAsDraft(pending) },
                    onOpenWebsite: { openSharedWorkoutOnWebsite(pending) },
                    onCancel: {
                        appState.dismissPendingSharedWorkout(id: pending.id)
                        showsSharedWorkoutPreview = false
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showsActiveWorkout) {
            NavigationStack {
                if let activeDraft = activeWorkoutStore.draft {
                    ActiveWorkoutView(
                        workoutStore: store,
                        activeWorkoutStore: activeWorkoutStore,
                        liveWorkoutCoordinator: liveWorkoutCoordinator,
                        restTimers: appState.restTimers,
                        draftID: activeDraft.id,
                        onFinished: { workoutID in
                            showsActiveWorkout = false
                            selectedTab = .workouts
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(180))
                                workoutPath.removeAll()
                                workoutPath.append(.summary(workoutID))
                            }
                        },
                        onClose: { showsActiveWorkout = false },
                        onDiscarded: { showsActiveWorkout = false },
                        onStatus: { message, isError in
                            appState.show(message: message, isError: isError)
                        }
                    )
                } else {
                    GymBackground {
                        GymContentUnavailableView {
                            Label(
                                gymText(
                                    "No active workout",
                                    "Немає активного тренування",
                                    "Нет активной тренировки",
                                    languageCode: languageCode
                                ),
                                systemImage: "figure.strengthtraining.traditional"
                            )
                        } description: {
                            Button(
                                gymText(
                                    "Close",
                                    "Закрити",
                                    "Закрыть",
                                    languageCode: languageCode
                                )
                            ) {
                                showsActiveWorkout = false
                            }
                        }
                    }
                }
            }
            .environmentObject(appState)
            .environmentObject(auth)
            .environmentObject(store)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let message = appState.statusMessage {
                    Button {
                        withAnimation { appState.clearStatus() }
                    } label: {
                        GymStatusBanner(message: message, isError: appState.statusIsError)
                            .frame(maxWidth: 560)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .accessibilityHint(
                        gymText(
                            "Double tap to dismiss",
                            "Торкнися двічі, щоб закрити",
                            languageCode: languageCode
                        )
                    )
                }

                if (appState.socialWorkoutInbox?.pendingIncomingCount ?? 0) > 0,
                   selectedTab != .profile {
                    Button {
                        selectedTab = .profile
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.badge.fill")
                                .foregroundStyle(GymTheme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    gymText(
                                        "Workout invitation waiting",
                                        "Очікує запрошення на тренування",
                                        "Ожидает приглашение на тренировку",
                                        languageCode: languageCode
                                    )
                                )
                                .font(.subheadline.bold())
                                Text(
                                    gymText(
                                        "Open Friends to review it. This is an in-app notice, not a push notification.",
                                        "Відкрий Друзів, щоб переглянути його. Це сповіщення в застосунку, а не push-повідомлення.",
                                        "Открой Друзей, чтобы посмотреть его. Это уведомление в приложении, а не push-уведомление.",
                                        languageCode: languageCode
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(.regularMaterial)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        gymText(
                            "Opens Friends in Profile",
                            "Відкриває Друзів у Профілі",
                            "Открывает Друзей в Профиле",
                            languageCode: languageCode
                        )
                    )
                }

                if liveWorkoutCoordinator.pendingInvitationCount > 0,
                   selectedTab != .profile {
                    Button {
                        selectedTab = .profile
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .foregroundStyle(GymTheme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    gymText(
                                        "Live workout invitation",
                                        "Запрошення на живе тренування",
                                        "Приглашение на живую тренировку",
                                        languageCode: languageCode
                                    )
                                )
                                .font(.subheadline.bold())
                                Text(
                                    gymText(
                                        "Open Friends to review it. Accepting starts the workout for both immediately.",
                                        "Відкрий Друзів, щоб переглянути. Прийняття одразу запускає тренування для обох.",
                                        "Открой Друзей, чтобы посмотреть. Принятие сразу запускает тренировку для обоих.",
                                        languageCode: languageCode
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(GymTheme.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(.regularMaterial)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                    .buttonStyle(.plain)
                }

                if let activeDraft = activeWorkoutStore.draft, !showsActiveWorkout {
                    HStack(spacing: 10) {
                        Image(systemName: "play.circle.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                gymText(
                                    "Workout in progress",
                                    "Тренування триває",
                                    "Тренировка идёт",
                                    languageCode: languageCode
                                )
                            )
                            .font(.subheadline.bold())
                            Text("\(activeDraft.completedSetCount) / \(activeDraft.plannedSetCount)")
                                .font(.caption.monospacedDigit())
                        }
                        Spacer(minLength: 8)
                        Button {
                            showsAddWorkout = false
                            showsActiveWorkout = true
                        } label: {
                            Text(
                                gymText(
                                    "Continue",
                                    "Продовжити",
                                    "Продолжить",
                                    languageCode: languageCode
                                )
                            )
                            .font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        if !liveWorkoutCoordinator.isAttachedToCurrentDraft {
                            Button(role: .destructive) {
                                showingActiveDraftDiscardConfirmation = true
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(
                                gymText(
                                    "Discard active workout",
                                    "Відкинути активне тренування",
                                    "Удалить активную тренировку",
                                    languageCode: languageCode
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(.regularMaterial)
                    .overlay(alignment: .bottom) { Divider() }
                }
            }
        }
        .alert(
            gymText(
                "Discard active workout?",
                "Відкинути активне тренування?",
                "Удалить активную тренировку?",
                languageCode: languageCode
            ),
            isPresented: $showingActiveDraftDiscardConfirmation
        ) {
            Button(
                gymText("Discard", "Відкинути", "Удалить", languageCode: languageCode),
                role: .destructive,
                action: discardActiveDraft
            )
            Button(
                gymText("Cancel", "Скасувати", "Отмена", languageCode: languageCode),
                role: .cancel
            ) {}
        } message: {
            Text(
                gymText(
                    "Recorded and planned sets in this active draft will be removed.",
                    "Записані й заплановані підходи цієї чернетки буде видалено.",
                    "Записанные и запланированные подходы этого черновика будут удалены.",
                    languageCode: languageCode
                )
            )
        }
        .appTutorialOverlay(
            step: currentTutorialStep,
            stepNumber: (tutorialStepIndex ?? -1) + 1,
            stepCount: tutorialSteps.count,
            languageCode: languageCode,
            canGoBack: (tutorialStepIndex ?? 0) > 0,
            primaryActionGlobalFrame: tutorialPrimaryActionGlobalFrame,
            onBack: moveTutorialBack,
            onNext: moveTutorialForward,
            onSkip: { finishTutorial(.skipped) }
        )
        .task {
            liveWorkoutCoordinator.startMonitoring()
            openPendingPushRouteIfNeeded()
            if activeWorkoutStore.recoveryMessage != nil {
                appState.show(
                    message: gymText(
                        "Active workout storage could not be opened safely. Existing progress was not exposed or overwritten.",
                        "Сховище активного тренування не вдалося безпечно відкрити. Наявний прогрес не розкрито й не перезаписано.",
                        "Хранилище активной тренировки не удалось безопасно открыть. Имеющийся прогресс не раскрыт и не перезаписан.",
                        languageCode: languageCode
                    ),
                    isError: true
                )
            }
            reconcilePersistedActiveRest()
            presentSharedWorkoutPreviewIfPossible()
            scheduleAutomaticTutorial()
        }
        .onDisappear {
            tutorialTask?.cancel()
            liveWorkoutCoordinator.stopMonitoring()
            workoutLaunchSeed = nil
            workoutLaunchConsumerID = nil
            workoutLaunchDrafts = nil
        }
        .onChange(of: appState.pendingSharedWorkout?.id) { _ in
            if appState.pendingSharedWorkout != nil {
                yieldTutorialToExternalNavigation()
            }
            presentSharedWorkoutPreviewIfPossible()
            scheduleAutomaticTutorial()
        }
        .onChange(of: showsAddWorkout) { isPresented in
            if !isPresented {
                sharedWorkoutDraftSeed = []
                workoutLaunchSeed = nil
                workoutLaunchConsumerID = nil
                workoutLaunchDrafts = nil
                workoutEditorLiveRecipient = nil
                presentSharedWorkoutPreviewIfPossible()
                scheduleAutomaticTutorial()
            }
        }
        .onChange(of: workoutEditorDraft) { draft in
            WorkoutPlanEditorDraftStore().save(
                draft,
                accountStorageKey: store.accountStorageKey
            )
        }
        .onChange(of: showsActiveWorkout) { isPresented in
            if !isPresented {
                presentSharedWorkoutPreviewIfPossible()
                scheduleAutomaticTutorial()
            }
        }
        .onChange(of: liveWorkoutCoordinator.sidecar.attachment?.localDraftID) { draftID in
            guard let draftID, activeWorkoutStore.draft?.id == draftID else { return }
            workoutEditorDraft = nil
            workoutEditorLiveRecipient = nil
            showsAddWorkout = false
            showsActiveWorkout = true
        }
        .onChange(of: liveWorkoutCoordinator.confirmedDraftConsumption) { _ in
            reconcileConfirmedLiveDraftConsumption()
        }
        .onChange(of: nativePush.pendingRoute?.id) { _ in
            if nativePush.pendingRoute != nil {
                yieldTutorialToExternalNavigation()
            }
            openPendingPushRouteIfNeeded()
            scheduleAutomaticTutorial()
        }
        .onReceive(activeWorkoutStore.objectWillChange) { _ in scheduleAutomaticTutorial() }
        .onReceive(liveWorkoutCoordinator.objectWillChange) { _ in scheduleAutomaticTutorial() }
    }

    private func reconcileConfirmedLiveDraftConsumption() {
        guard let consumption = liveWorkoutCoordinator.confirmedDraftConsumption,
              let cloud = auth.session?.cloud,
              let sessionID = NativePushAuthSessionIdentity.sessionID(from: cloud),
              cloud.userID.lowercased() == consumption.userID,
              sessionID == consumption.sessionID,
              appState.activeAccountStorageKey == store.accountStorageKey,
              auth.session?.storageKey == store.accountStorageKey else { return }

        let resolution = resolveConfirmedLiveWorkoutDraft(
            consumption,
            draft: workoutEditorDraft,
            accountStorageKey: store.accountStorageKey,
            userID: cloud.userID.lowercased(),
            sessionID: sessionID
        )
        switch resolution {
        case .consume:
            workoutEditorDraft = nil
            workoutEditorLiveRecipient = nil
            sharedWorkoutDraftSeed = []
            workoutLaunchSeed = nil
            workoutLaunchConsumerID = nil
            workoutLaunchDrafts = nil
            showsAddWorkout = false
            profileNavigationID = UUID()
            selectedTab = .profile
        case .preserveUnbound(let newerDraft):
            workoutEditorDraft = newerDraft
            workoutEditorLiveRecipient = nil
            sharedWorkoutDraftSeed = []
            workoutLaunchSeed = nil
            workoutLaunchConsumerID = nil
            workoutLaunchDrafts = nil
            showsAddWorkout = false
            profileNavigationID = UUID()
            selectedTab = .profile
        case .unrelated:
            break
        }

        guard resolution.shouldAcknowledge else { return }
        // The draft compare-and-swap is complete before the durable marker is removed.
        // A failed local write leaves the marker available for a later startup retry.
        try? liveWorkoutCoordinator.acknowledgeConfirmedDraftConsumption(consumption)
    }

    private var tutorialSteps: [AppTutorialStep] {
        AppTutorialStep.all(languageCode: languageCode)
    }

    private var currentTutorialStep: AppTutorialStep? {
        guard let tutorialStepIndex,
              tutorialSteps.indices.contains(tutorialStepIndex) else {
            return nil
        }
        return tutorialSteps[tutorialStepIndex]
    }

    private var tutorialPresentationIsDeferred: Bool {
        !appState.isAccountReady
            || appState.activeAccountStorageKey != store.accountStorageKey
            || appState.workoutStore !== store
            || nativePush.pendingRoute != nil
            || isResolvingNativePushRoute
            || appState.pendingSharedWorkout != nil
            || showsSharedWorkoutPreview
            || showsAddWorkout
            || showsActiveWorkout
            || activeWorkoutStore.draft != nil
            || showingActiveDraftDiscardConfirmation
            || liveWorkoutCoordinator.hasBlockingLiveWorkout
    }

    private func scheduleAutomaticTutorial() {
        tutorialTask?.cancel()
        guard tutorialStepIndex == nil,
              !tutorialAutomaticPresentationSuppressedForSession,
              AppTutorialStore().needsAutomaticPresentation(
                accountStorageKey: store.accountStorageKey
              ) else {
            return
        }
        let accountStorageKey = store.accountStorageKey
        tutorialTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled,
                  tutorialStepIndex == nil,
                  appState.activeAccountStorageKey == accountStorageKey,
                  !tutorialPresentationIsDeferred,
                  AppTutorialStore().needsAutomaticPresentation(
                    accountStorageKey: accountStorageKey
                  ) else {
                return
            }
            beginTutorial(manualReplay: false)
        }
    }

    private func requestTutorialReplay() {
        guard !tutorialPresentationIsDeferred else {
            appState.show(
                message: gymText(
                    "Finish the current action, import, or live workout before showing the tutorial.",
                    "Заверши поточну дію, імпорт або живе тренування, перш ніж показувати навчання.",
                    "Заверши текущее действие, импорт или живую тренировку перед показом обучения.",
                    languageCode: languageCode
                ),
                isError: false
            )
            return
        }
        tutorialAutomaticPresentationSuppressedForSession = false
        beginTutorial(manualReplay: true)
    }

    private func beginTutorial(manualReplay: Bool) {
        guard tutorialStepIndex == nil, !tutorialPresentationIsDeferred else { return }
        tutorialTask?.cancel()
        tutorialIsManualReplay = manualReplay
        tutorialStepIndex = 0
        selectTab(for: tutorialSteps[0].target)
    }

    private func moveTutorialBack() {
        guard let tutorialStepIndex, tutorialStepIndex > 0 else { return }
        let previous = tutorialStepIndex - 1
        self.tutorialStepIndex = previous
        selectTab(for: tutorialSteps[previous].target)
    }

    private func moveTutorialForward() {
        guard let tutorialStepIndex else { return }
        let next = tutorialStepIndex + 1
        guard tutorialSteps.indices.contains(next) else {
            finishTutorial(.completed)
            return
        }
        self.tutorialStepIndex = next
        selectTab(for: tutorialSteps[next].target)
    }

    private func finishTutorial(_ completion: AppTutorialCompletion) {
        guard let currentTutorialStep else { return }
        let tutorialStore = AppTutorialStore()
        let needsAutomaticPresentation = tutorialStore.needsAutomaticPresentation(
            accountStorageKey: store.accountStorageKey
        )
        if appTutorialShouldRecordCompletion(
            isManualReplay: tutorialIsManualReplay,
            needsAutomaticPresentation: needsAutomaticPresentation
        ), !tutorialStore.record(
            completion,
            accountStorageKey: store.accountStorageKey
        ) {
            appState.show(
                message: gymText(
                    "The tutorial result could not be saved. Try again.",
                    "Не вдалося зберегти результат навчання. Спробуй ще раз.",
                    "Не удалось сохранить результат обучения. Попробуй ещё раз.",
                    languageCode: languageCode
                ),
                isError: true
            )
            return
        }
        let finishRoute = appTutorialFinishRoute(
            currentTarget: currentTutorialStep.target,
            externalTargetOwnsNavigation: tutorialPresentationIsDeferred
        )
        tutorialStepIndex = nil
        tutorialIsManualReplay = false
        if case .keep(let target) = finishRoute {
            selectTab(for: target)
        }
    }

    private func selectTab(for target: AppTutorialTarget) {
        switch target {
        case .todayFocus, .todayPrimaryAction: selectedTab = .workouts
        case .exercises: selectedTab = .exercises
        case .progress: selectedTab = .progress
        case .profile: selectedTab = .profile
        }
    }

    private func yieldTutorialToExternalNavigation() {
        let interruption = appTutorialExternalInterruption(
            currentStepIndex: tutorialStepIndex,
            isManualReplay: tutorialIsManualReplay
        )
        tutorialTask?.cancel()
        tutorialStepIndex = interruption.stepIndex
        tutorialIsManualReplay = interruption.isManualReplay
        tutorialAutomaticPresentationSuppressedForSession =
            interruption.suppressAutomaticPresentationForSession
    }

    private func openPendingPushRouteIfNeeded() {
        if nativePush.pendingRoute != nil {
            yieldTutorialToExternalNavigation()
        }
        guard let route = nativePush.consumePendingRoute() else { return }
        nativePushProfileRequest = nil
        selectedTab = .profile
        resolvingNativePushRouteID = route.id
        isResolvingNativePushRoute = true
        Task { @MainActor in
            defer {
                if resolvingNativePushRouteID == route.id {
                    resolvingNativePushRouteID = nil
                    isResolvingNativePushRoute = false
                    scheduleAutomaticTutorial()
                }
            }
            guard resolvingNativePushRouteID == route.id,
                  nativePush.isRouteBoundToCurrentSession(route) else { return }
            switch route.target {
            case .social:
                _ = try? await appState.refreshSocialDashboard()
                guard resolvingNativePushRouteID == route.id,
                      nativePush.isRouteBoundToCurrentSession(route) else { return }
                _ = try? await appState.refreshSocialWorkoutInbox()
                guard resolvingNativePushRouteID == route.id,
                      nativePush.isRouteBoundToCurrentSession(route) else { return }
                nativePushProfileRequest = NativePushProfileRequest(
                    id: route.id,
                    focus: .friends
                )
            case let .socialObject(object):
                _ = try? await appState.refreshSocialDashboard()
                guard resolvingNativePushRouteID == route.id,
                      nativePush.isRouteBoundToCurrentSession(route) else { return }
                _ = try? await appState.refreshSocialWorkoutInbox()
                guard resolvingNativePushRouteID == route.id,
                      nativePush.isRouteBoundToCurrentSession(route) else { return }
                var exactWorkoutInviteUnavailable = false
                switch object.eventType {
                case .workoutInviteReceived, .workoutInviteAccepted:
                    exactWorkoutInviteUnavailable = (try? await appState.resolveSocialWorkoutInvite(
                        inviteID: object.objectID,
                        minimumRevision: object.objectRevision
                    )) != true
                    guard resolvingNativePushRouteID == route.id,
                          nativePush.isRouteBoundToCurrentSession(route) else { return }
                default:
                    break
                }
                if exactWorkoutInviteUnavailable {
                    appState.show(
                        message: gymText(
                            "This workout invitation is no longer available.",
                            "Це запрошення на тренування більше недоступне.",
                            "Это приглашение на тренировку больше недоступно.",
                            languageCode: languageCode
                        ),
                        isError: false
                    )
                }
                nativePushProfileRequest = NativePushProfileRequest(
                    id: route.id,
                    focus: resolvedSocialFocus(for: object)
                )
            case let .live(roomID):
                if let roomID {
                    // Open the room named by the authenticated, bounded payload.
                    // The coordinator rechecks the account/session around its network
                    // boundary and materializes an active room only for that owner.
                    let opened = (try? await liveWorkoutCoordinator.openRoom(roomID)) != nil
                    guard resolvingNativePushRouteID == route.id,
                          nativePush.isRouteBoundToCurrentSession(route) else { return }
                    nativePushProfileRequest = NativePushProfileRequest(
                        id: route.id,
                        focus: opened && liveWorkoutCoordinator.snapshot?.room.roomID == roomID
                            ? .liveRoom(roomID)
                            : .liveWorkouts
                    )
                } else {
                    // Compatibility for already-delivered route-v1 notifications.
                    await liveWorkoutCoordinator.refreshAll(showErrors: false)
                    guard resolvingNativePushRouteID == route.id,
                          nativePush.isRouteBoundToCurrentSession(route) else { return }
                    nativePushProfileRequest = NativePushProfileRequest(
                        id: route.id,
                        focus: .liveWorkouts
                    )
                }
            }
        }
    }

    private func resolvedSocialFocus(
        for object: NativePushSocialObjectTarget
    ) -> NativePushProfileFocus {
        switch object.eventType {
        case .friendRequestReceived, .friendRequestAccepted:
            let dashboard = appState.socialDashboard
            let revision = dashboard?.incoming.first(where: {
                $0.friendshipID == object.objectID
            })?.friendshipRevision
                ?? dashboard?.outgoing.first(where: {
                    $0.friendshipID == object.objectID
                })?.friendshipRevision
                ?? dashboard?.friends.first(where: {
                    $0.friendshipID == object.objectID
                })?.friendshipRevision
            guard let revision, revision >= object.objectRevision else { return .friends }
            return .friendRequest(object.objectID)
        case .workoutInviteReceived, .workoutInviteAccepted:
            let inbox = appState.socialWorkoutInbox
            let revision = inbox?.incoming.first(where: {
                $0.inviteID == object.objectID
            })?.inviteRevision
                ?? inbox?.outgoing.first(where: {
                    $0.inviteID == object.objectID
                })?.inviteRevision
            guard let revision, revision >= object.objectRevision else { return .friends }
            return .workoutInvite(object.objectID)
        case .liveInviteReceived, .liveInviteAccepted, .liveRoomStarted,
             .liveParticipantFinished, .liveRoomClosed:
            return .friends
        }
    }

    private func reconcilePersistedActiveRest() {
        guard let draft = activeWorkoutStore.draft else { return }
        let title: String
        if let latestID = draft.undoableSetID,
           let exercise = draft.exercises.first(where: {
               $0.sets.contains { $0.id == latestID }
           }) {
            title = store.exercise(id: exercise.exerciseID).map { gymExerciseName($0) } ??
                exercise.exerciseName ??
                gymText("Workout", "Тренування", "Тренировка", languageCode: languageCode)
        } else {
            title = gymText("Workout", "Тренування", "Тренировка", languageCode: languageCode)
        }

        do {
            let outcome = try ActiveWorkoutRestReconciler.reconcile(
                draft: draft,
                store: activeWorkoutStore,
                manager: appState.restTimers,
                title: title
            )
            guard outcome != .synchronized else { return }
            appState.show(
                message: gymText(
                    "Workout progress was restored, but rest-timer recovery was incomplete. Rest was stopped safely.",
                    "Прогрес тренування відновлено, але відновлення таймера відпочинку не завершено. Відпочинок безпечно зупинено.",
                    "Прогресс тренировки восстановлен, но восстановление таймера отдыха не завершено. Отдых безопасно остановлен.",
                    languageCode: languageCode
                ),
                isError: true
            )
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private func presentSharedWorkoutPreviewIfPossible() {
        if appState.pendingSharedWorkout != nil {
            yieldTutorialToExternalNavigation()
        }
        guard appState.pendingSharedWorkout != nil,
              !showsAddWorkout,
              !showsActiveWorkout else { return }
        showsSharedWorkoutPreview = true
    }

    private func dismissSharedWorkoutPreviewIfNeeded() {
        if let transitionID = sharedWorkoutDraftTransitionID {
            sharedWorkoutDraftTransitionID = nil
            finishOpeningSharedWorkoutAsDraft(id: transitionID)
            return
        }
        guard let pending = appState.pendingSharedWorkout else { return }
        appState.dismissPendingSharedWorkout(id: pending.id)
    }

    private func openSharedWorkoutAsDraft(_ pending: PendingSharedWorkout) {
        guard appState.pendingSharedWorkout?.id == pending.id,
              activeWorkoutStore.draft == nil,
              workoutEditorDraft == nil,
              !showsAddWorkout else {
            appState.show(
                message: gymText(
                    "Finish the current workout or draft before opening this shared plan.",
                    "Заверши поточне тренування або чернетку, перш ніж відкривати цей спільний план.",
                    "Заверши текущую тренировку или черновик, прежде чем открывать этот общий план.",
                    languageCode: languageCode
                ),
                isError: true
            )
            return
        }
        // Dismiss the preview first. Its onDismiss callback completes the handoff
        // synchronously, so exercise materialization is never separated from the
        // editor presentation by an arbitrary timer or a late state guard.
        sharedWorkoutDraftTransitionID = pending.id
        showsSharedWorkoutPreview = false
    }

    private func finishOpeningSharedWorkoutAsDraft(id: UUID) {
        guard let pending = appState.pendingSharedWorkout,
              pending.id == id,
              appState.workoutStore === store,
              appState.activeAccountStorageKey == store.accountStorageKey,
              activeWorkoutStore.draft == nil,
              workoutEditorDraft == nil,
              !showsAddWorkout else {
            presentSharedWorkoutPreviewIfPossible()
            return
        }
        do {
            let seed = try store.materializeSharedWorkoutDraft(pending.plan)
            sharedWorkoutDraftSeed = seed
            workoutLaunchSeed = nil
            workoutLaunchConsumerID = nil
            workoutLaunchDrafts = nil
            appState.dismissPendingSharedWorkout(id: pending.id)
            showsAddWorkout = true
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
            presentSharedWorkoutPreviewIfPossible()
        }
    }

    private func openSharedWorkoutOnWebsite(_ pending: PendingSharedWorkout) {
        guard appState.pendingSharedWorkout?.id == pending.id else { return }
        do {
            let url = try SharedWorkoutLinkEncoder.makeWebsiteURL(plan: pending.plan)
            appState.dismissPendingSharedWorkout(id: pending.id)
            showsSharedWorkoutPreview = false
            openURL(url)
        } catch {
            appState.show(
                message: gymText(
                    "The website link could not be created.",
                    "Не вдалося створити посилання на сайт.",
                    "Не удалось создать ссылку на сайт.",
                    languageCode: languageCode
                ),
                isError: true
            )
        }
    }

    private func discardActiveDraft() {
        guard let draft = activeWorkoutStore.draft else { return }
        guard !liveWorkoutCoordinator.isAttachedToCurrentDraft else {
            appState.show(
                message: gymText(
                    "A live workout cannot be discarded silently. Cancel or leave its room from Friends.",
                    "Живе тренування не можна непомітно відкинути. Скасуй кімнату або вийди з неї у Друзях.",
                    "Живую тренировку нельзя незаметно удалить. Отмени комнату или выйди из неё в Друзьях.",
                    languageCode: languageCode
                ),
                isError: true
            )
            return
        }
        do {
            try activeWorkoutStore.discard(
                draftID: draft.id,
                expectedRevision: draft.revision
            )
            appState.restTimers.cancel(
                id: "active-workout-\(draft.id.uuidString)-rest"
            )
            appState.show(
                message: gymText(
                    "Active workout discarded.",
                    "Активне тренування відкинуто.",
                    "Активная тренировка удалена.",
                    languageCode: languageCode
                ),
                isError: false
            )
        } catch {
            appState.show(message: gymErrorMessage(error), isError: true)
        }
    }

    private var workoutsTab: some View {
        NavigationStack(path: $workoutPath) {
            WorkoutsView(
                store: store,
                activeWorkoutDraft: activeWorkoutStore.draft,
                hasRetainedWorkoutDraft:
                    workoutEditorDraft?.belongs(to: store.accountStorageKey) == true
                    || workoutEditorLiveRecipient != nil,
                onStartPlan: { launchSeed in
                    guard activeWorkoutStore.draft == nil,
                          !showsAddWorkout,
                          !showsActiveWorkout else {
                        return false
                    }
                    if workoutEditorDraft?.belongs(to: store.accountStorageKey) == true {
                        sharedWorkoutDraftSeed = []
                        workoutLaunchSeed = nil
                        workoutLaunchConsumerID = nil
                        workoutLaunchDrafts = nil
                        showsAddWorkout = true
                        return true
                    }
                    let currentProfile = TrainingProfileStore().load(
                        accountStorageKey: store.accountStorageKey
                    )
                    guard DirectWorkoutPlanStarter.start(
                        seed: launchSeed,
                        currentProfile: currentProfile,
                        workoutStore: store,
                        activeWorkoutStore: activeWorkoutStore
                    ) != nil else {
                        return false
                    }
                    workoutEditorDraft = nil
                    workoutEditorLiveRecipient = nil
                    sharedWorkoutDraftSeed = []
                    workoutLaunchSeed = nil
                    workoutLaunchConsumerID = nil
                    workoutLaunchDrafts = nil
                    showsAddWorkout = false
                    showsActiveWorkout = true
                    return true
                },
                onAddWorkout: { launchSeed in
                    if activeWorkoutStore.draft != nil {
                        showsActiveWorkout = true
                        return false
                    } else {
                        if workoutEditorDraft?.belongs(to: store.accountStorageKey) == true {
                            sharedWorkoutDraftSeed = []
                            workoutLaunchSeed = nil
                            workoutLaunchConsumerID = nil
                            workoutLaunchDrafts = nil
                            showsAddWorkout = true
                            return true
                        }
                        let currentProfile = TrainingProfileStore().load(
                            accountStorageKey: store.accountStorageKey
                        )
                        if let launchSeed {
                            let consumerID = UUID()
                            let launchDrafts = makeWorkoutEditorDrafts(from: launchSeed.plan)
                            guard launchSeed.isValid(
                                accountStorageKey: store.accountStorageKey,
                                currentProfile: currentProfile,
                                catalog: store.exercises,
                                history: store.allExerciseHistory(),
                                muscleMappings: store.muscleMappings
                            ), !launchDrafts.isEmpty,
                               WorkoutLaunchSeedUseGate.claim(
                                launchSeed,
                                consumerID: consumerID
                            ) else {
                                workoutLaunchSeed = nil
                                workoutLaunchConsumerID = nil
                                workoutLaunchDrafts = nil
                                return false
                            }
                            workoutLaunchConsumerID = consumerID
                            workoutLaunchDrafts = launchDrafts
                        } else {
                            workoutLaunchConsumerID = nil
                            workoutLaunchDrafts = nil
                        }
                        sharedWorkoutDraftSeed = []
                        workoutEditorLiveRecipient = nil
                        workoutLaunchSeed = launchSeed
                        showsAddWorkout = true
                        return true
                    }
                },
                onContinueWorkout: {
                    showsAddWorkout = false
                    showsActiveWorkout = true
                },
                onDiscardWorkout: {
                    showingActiveDraftDiscardConfirmation = true
                },
                onTutorialPrimaryActionFrameChange: { frame in
                    tutorialPrimaryActionGlobalFrame = frame
                },
                onOpenWorkout: { workoutPath.append(.detail($0)) },
                onOpenRanks: { workoutPath.append(.ranks) }
            )
            .navigationDestination(for: WorkoutRoute.self) { route in
                switch route {
                case .detail(let id):
                    WorkoutDetailView(
                        appState: appState,
                        workoutID: id,
                        liveWorkoutCoordinator: liveWorkoutCoordinator,
                        onDeleted: {
                            if !workoutPath.isEmpty { workoutPath.removeLast() }
                        }
                    )
                case .summary(let id):
                    PostWorkoutSummaryView(
                        appState: appState,
                        workoutID: id,
                        onOpenDetail: { workoutID in
                            if !workoutPath.isEmpty { workoutPath.removeLast() }
                            workoutPath.append(.detail(workoutID))
                        },
                        onDone: { workoutPath.removeAll() }
                    )
                case .ranks:
                    RanksView(store: store)
                }
            }
        }
    }

    private var exercisesTab: some View {
        NavigationStack {
            ExercisesView()
                .gymLanguageToolbar()
        }
    }

    private var progressTab: some View {
        NavigationStack(path: $missionPath) {
            ProgressHubView(
                store: store,
                onOpenRanks: { missionPath.append(.ranks) }
            )
                .gymLanguageToolbar()
                .navigationDestination(for: MissionRoute.self) { route in
                    switch route {
                    case .ranks: RanksView(store: store)
                    }
                }
        }
    }

    private var profileTab: some View {
        NavigationStack {
            ProfileView(
                appState: appState,
                auth: auth,
                store: store,
                canAcceptWorkoutInvites: activeWorkoutStore.draft == nil
                    && workoutEditorDraft == nil,
                liveWorkoutCoordinator: liveWorkoutCoordinator,
                nativePushRequest: nativePushProfileRequest,
                onShowTutorial: requestTutorialReplay,
                onCreateLiveWorkout: openDirectLiveWorkoutEditor,
                onOpenLiveWorkout: {
                    showsAddWorkout = false
                    showsActiveWorkout = true
                }
            )
                .gymLanguageToolbar()
        }
        .id(profileNavigationID)
    }

    private func openDirectLiveWorkoutEditor(with friend: SocialFriendSummary) {
        guard appState.activeAccountStorageKey == store.accountStorageKey,
              appState.auth.session?.cloud != nil,
              appState.socialDashboard?.friends.contains(where: {
                  $0.profileID == friend.profileID
                      && $0.friendshipID == friend.friendshipID
                      && $0.friendshipRevision == friend.friendshipRevision
              }) == true,
              activeWorkoutStore.draft == nil,
              workoutEditorDraft == nil
                || workoutEditorDraft?.belongs(to: store.accountStorageKey) == true,
              !liveWorkoutCoordinator.hasBlockingLiveWorkout,
              !showsAddWorkout,
              !showsActiveWorkout else {
            appState.show(
                message: gymText(
                    "Finish or discard the current workout, draft, or live room before creating another live workout.",
                    "Заверши або відкинь поточне тренування, чернетку чи живу кімнату перед створенням нового живого тренування.",
                    "Заверши или удали текущую тренировку, черновик или live-комнату перед созданием новой живой тренировки.",
                    languageCode: languageCode
                ),
                isError: true
            )
            return
        }
        sharedWorkoutDraftSeed = []
        workoutLaunchSeed = nil
        workoutLaunchConsumerID = nil
        workoutLaunchDrafts = nil
        workoutEditorLiveRecipient = friend
        selectedTab = .workouts
        showsAddWorkout = true
    }
}

private struct SharedWorkoutPreviewView: View {
    let pending: PendingSharedWorkout
    let languageCode: String
    let canOpenAsDraft: Bool
    let onOpenAsDraft: () -> Void
    let onOpenWebsite: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Label(
                            "\(pending.plan.exercises.count)",
                            systemImage: "dumbbell.fill"
                        )
                        Spacer()
                        Label(
                            "\(pending.plan.totalSetCount)",
                            systemImage: "list.number"
                        )
                    }
                    .font(.headline.monospacedDigit())
                } header: {
                    Text(
                        gymText(
                            "Shared workout preview",
                            "Перегляд спільного тренування",
                            "Просмотр общей тренировки",
                            languageCode: languageCode
                        )
                    )
                } footer: {
                    Text(
                        gymText(
                            "Nothing is saved until you choose an action. Opening as a draft lets you review and edit every set first.",
                            "Нічого не зберігається, доки ти не вибереш дію. Після відкриття як чернетки можна перевірити й змінити кожен підхід.",
                            "Ничего не сохраняется, пока ты не выберешь действие. После открытия как черновика можно проверить и изменить каждый подход.",
                            languageCode: languageCode
                        )
                    )
                }

                Section(
                    gymText(
                        "Exercises",
                        "Вправи",
                        "Упражнения",
                        languageCode: languageCode
                    )
                ) {
                    ForEach(Array(pending.plan.exercises.enumerated()), id: \.offset) { _, exercise in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(
                                gymExerciseName(
                                    exercise.name,
                                    catalogKey: exercise.catalogKey,
                                    languageCode: languageCode
                                )
                            )
                            .foregroundStyle(GymTheme.textPrimary)
                            Spacer(minLength: 8)
                            Text(
                                gymText(
                                    "\(exercise.sets.count) sets",
                                    "\(exercise.sets.count) підх.",
                                    "\(exercise.sets.count) подх.",
                                    languageCode: languageCode
                                )
                            )
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(GymTheme.textSecondary)
                        }
                    }
                }

                Section {
                    Button(action: onOpenAsDraft) {
                        Label(
                            gymText(
                                "Open as draft",
                                "Відкрити як чернетку",
                                "Открыть как черновик",
                                languageCode: languageCode
                            ),
                            systemImage: "square.and.pencil"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canOpenAsDraft)

                    if !canOpenAsDraft {
                        Text(
                            gymText(
                                "Finish the active workout first. Its progress will not be replaced.",
                                "Спочатку заверши активне тренування. Його прогрес не буде замінено.",
                                "Сначала заверши активную тренировку. Её прогресс не будет заменён.",
                                languageCode: languageCode
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(GymTheme.textSecondary)
                    }

                    Button(action: onOpenWebsite) {
                        Label(
                            gymText(
                                "Open on website",
                                "Відкрити на сайті",
                                "Открыть на сайте",
                                languageCode: languageCode
                            ),
                            systemImage: "safari"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .cancel, action: onCancel) {
                        Text(
                            gymText(
                                "Cancel",
                                "Скасувати",
                                "Отмена",
                                languageCode: languageCode
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(
                gymText(
                    "Shared workout",
                    "Спільне тренування",
                    "Общая тренировка",
                    languageCode: languageCode
                )
            )
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
