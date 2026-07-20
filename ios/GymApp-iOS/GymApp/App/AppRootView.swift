import SwiftUI

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
            } else if appState.isAccountReady {
                MainTabShell(appState: appState)
                    .environmentObject(appState.workoutStore)
                    .id(appState.activeAccountStorageKey)
            } else {
                AccountPreparationView(
                    isWorking: appState.isPreparingAccount,
                    message: appState.accountPreparationError,
                    retry: appState.retryAccountActivation,
                    signOut: { Task { await auth.signOut() } }
                )
            }
        }
        .environment(\.locale, AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en"))
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
        .onChange(of: auth.needsPasswordUpdate) { _, needsUpdate in
            showsPasswordUpdate = needsUpdate
        }
        .onChange(of: scenePhase) { _, phase in
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

private struct AccountPreparationView: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue

    let isWorking: Bool
    let message: String?
    let retry: () -> Void
    let signOut: () -> Void

    var body: some View {
        ContentUnavailableView {
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
        case workouts, missions, exercises, progress, rating
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .workouts: "figure.strengthtraining.traditional"
            case .missions: "scope"
            case .exercises: "dumbbell.fill"
            case .progress: "chart.xyaxis.line"
            case .rating: "trophy.fill"
            }
        }

        func title(_ language: String) -> String {
            switch self {
            case .workouts: gymText("Workouts", "Тренування", languageCode: language)
            case .missions: gymText("Missions", "Місії", languageCode: language)
            case .exercises: gymText("Exercises", "Вправи", languageCode: language)
            case .progress: gymText("Progress", "Прогрес", languageCode: language)
            case .rating: gymText("Rating", "Рейтинг", languageCode: language)
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
        _selectedTab = State(initialValue: requested.flatMap(Tab.init(rawValue:)) ?? .workouts)
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

            ratingTab
                .tabItem { Label(Tab.rating.title(languageCode), systemImage: Tab.rating.icon) }
                .tag(Tab.rating)
                .accessibilityIdentifier("tab-rating")
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

    private var ratingTab: some View {
        NavigationStack {
            LeaderboardView(store: store, appState: appState, auth: auth)
                .gymLanguageToolbar()
        }
    }
}
