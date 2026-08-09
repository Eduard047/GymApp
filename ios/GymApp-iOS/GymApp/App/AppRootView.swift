import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue
    @ObservedObject private var appState: AppState
    @ObservedObject private var auth: AuthService

    @State private var showsIntro = true
    @State private var showsPasswordUpdate = false

    init(appState: AppState) {
        self.appState = appState
        self.auth = appState.auth
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
                MainTabShell(appState: appState)
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
            Task { await refreshSocialSurfaces() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                appState.saveBeforeBackgrounding()
            } else if phase == .active, appState.isAccountReady, auth.session?.cloud != nil {
                Task { await refreshSocialSurfaces() }
            }
        }
        .task {
#if DEBUG
            await appState.bootstrapDemoIfRequested()
#endif
            if appState.isAccountReady, auth.session?.cloud != nil {
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
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue

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
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue

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

@MainActor
private struct MainTabShell: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case workouts, missions, exercises, progress, profile
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .workouts: "figure.strengthtraining.traditional"
            case .missions: "scope"
            case .exercises: "dumbbell.fill"
            case .progress: "chart.xyaxis.line"
            case .profile: "person.crop.circle.fill"
            }
        }

        func title(_ language: String) -> String {
            switch self {
            case .workouts: gymText("Workouts", "Тренування", languageCode: language)
            case .missions: gymText("Missions", "Місії", languageCode: language)
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
    @StateObject private var activeWorkoutStore: ActiveWorkoutStore
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue
    @Environment(\.openURL) private var openURL

    @State private var selectedTab: Tab
    @State private var workoutPath: [WorkoutRoute] = []
    @State private var missionPath: [MissionRoute] = []
    @State private var showsAddWorkout = false
    @State private var showsActiveWorkout = false
    @State private var showsSharedWorkoutPreview = false
    @State private var sharedWorkoutDraftSeed: [WorkoutExerciseDraft] = []
    @State private var sharedWorkoutDraftTransitionID: UUID?
    @State private var showingActiveDraftDiscardConfirmation = false

    init(appState: AppState) {
        self.appState = appState
        self.auth = appState.auth
        let currentStore = appState.workoutStore
        self.store = currentStore
        let activeStore = ActiveWorkoutStore(
            accountStorageKey: currentStore.accountStorageKey,
            workoutStorageURL: currentStore.storageURL
        )
        try? activeStore.rebindExercises(to: currentStore)
        _activeWorkoutStore = StateObject(
            wrappedValue: activeStore
        )
        let requested = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--screenshot-tab=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
        let initialTab = requested == "rating" || requested == "friends"
            ? Tab.profile
            : requested.flatMap(Tab.init(rawValue:))
        _selectedTab = State(initialValue: initialTab ?? .workouts)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            workoutsTab
                .tabItem { Label(Tab.workouts.title(languageCode), systemImage: Tab.workouts.icon) }
                .tag(Tab.workouts)
                .accessibilityIdentifier("tab-workouts")

            missionsTab
                .tabItem { Label(Tab.missions.title(languageCode), systemImage: Tab.missions.icon) }
                .tag(Tab.missions)
                .accessibilityIdentifier("tab-missions")

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
                .badge(appState.socialWorkoutInbox?.pendingIncomingCount ?? 0)
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
                    initialDrafts: sharedWorkoutDraftSeed,
                    onStarted: { _ in
                        sharedWorkoutDraftSeed = []
                        showsAddWorkout = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            showsActiveWorkout = true
                        }
                    },
                    onSaved: { workoutID in
                        sharedWorkoutDraftSeed = []
                        showsAddWorkout = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            workoutPath.append(.summary(workoutID))
                        }
                    },
                    onCancel: {
                        sharedWorkoutDraftSeed = []
                        showsAddWorkout = false
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
                    canOpenAsDraft: activeWorkoutStore.draft == nil && !showsAddWorkout,
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
        .task {
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
        }
        .onChange(of: appState.pendingSharedWorkout?.id) { _ in
            presentSharedWorkoutPreviewIfPossible()
        }
        .onChange(of: showsAddWorkout) { isPresented in
            if !isPresented {
                presentSharedWorkoutPreviewIfPossible()
            }
        }
        .onChange(of: showsActiveWorkout) { isPresented in
            if !isPresented {
                presentSharedWorkoutPreviewIfPossible()
            }
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
              !showsAddWorkout else {
            presentSharedWorkoutPreviewIfPossible()
            return
        }
        do {
            let seed = try store.materializeSharedWorkoutDraft(pending.plan)
            sharedWorkoutDraftSeed = seed
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
                onAddWorkout: {
                    if activeWorkoutStore.draft != nil {
                        showsActiveWorkout = true
                    } else {
                        sharedWorkoutDraftSeed = []
                        showsAddWorkout = true
                    }
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

    private var missionsTab: some View {
        NavigationStack(path: $missionPath) {
            MissionsView(store: store) { missionPath.append(.ranks) }
                .gymLanguageToolbar()
                .navigationDestination(for: MissionRoute.self) { route in
                    switch route {
                    case .ranks: RanksView(store: store)
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
        NavigationStack {
            ExerciseProgressView(store: store)
                .gymLanguageToolbar()
        }
    }

    private var profileTab: some View {
        NavigationStack {
            ProfileView(
                appState: appState,
                auth: auth,
                store: store,
                canAcceptWorkoutInvites: activeWorkoutStore.draft == nil
            )
                .gymLanguageToolbar()
        }
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
