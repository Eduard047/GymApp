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
        // A number of feature views resolve app strings through UserDefaults-backed helpers.
        // Recreate the presentation subtree so cached labels cannot survive a language change.
        .id(languageCode)
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
        .onChange(of: scenePhase) { phase in
            if phase == .background { appState.saveBeforeBackgrounding() }
        }
        .task {
#if DEBUG
            await appState.bootstrapDemoIfRequested()
#endif
            showsPasswordUpdate = auth.needsPasswordUpdate
            try? await Task.sleep(for: .milliseconds(1_400))
            withAnimation(.easeOut(duration: 0.28)) {
                showsIntro = false
            }
        }
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
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue

    @State private var selectedTab: Tab
    @State private var workoutPath: [WorkoutRoute] = []
    @State private var missionPath: [MissionRoute] = []
    @State private var showsAddWorkout = false

    init(appState: AppState) {
        self.appState = appState
        self.auth = appState.auth
        self.store = appState.workoutStore
        let requested = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--screenshot-tab=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)
        let initialTab = requested == "rating"
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
                    onSaved: { workoutID in
                        showsAddWorkout = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(180))
                            workoutPath.append(.summary(workoutID))
                        }
                    },
                    onCancel: { showsAddWorkout = false }
                )
            }
            .environmentObject(appState)
            .environmentObject(auth)
            .environmentObject(store)
        }
        .overlay(alignment: .top) {
            if let message = appState.statusMessage {
                Button {
                    withAnimation { appState.clearStatus() }
                } label: {
                    GymStatusBanner(message: message, isError: appState.statusIsError)
                        .frame(maxWidth: 560)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
                .accessibilityHint(gymText("Double tap to dismiss", "Торкнися двічі, щоб закрити", languageCode: languageCode))
            }
        }
    }

    private var workoutsTab: some View {
        NavigationStack(path: $workoutPath) {
            WorkoutsView(
                store: store,
                onAddWorkout: { showsAddWorkout = true },
                onOpenWorkout: { workoutPath.append(.detail($0)) },
                onOpenRanks: { workoutPath.append(.ranks) }
            )
            .navigationDestination(for: WorkoutRoute.self) { route in
                switch route {
                case .detail(let id):
                    WorkoutDetailView(
                        appState: appState,
                        workoutID: id,
                        onFinish: { workoutPath.append(.summary($0)) },
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
            ProfileView(appState: appState, auth: auth, store: store)
                .gymLanguageToolbar()
        }
    }
}
