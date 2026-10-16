import SwiftUI

@MainActor
final class AppBootstrap: ObservableObject {
    let auth: AuthService
    let nativePush: NativePushManager

    @Published private(set) var appState: AppState?
    @Published private(set) var startupErrorMessage: String?
    @Published private(set) var hasAttemptedStart = false

    init() {
        let auth = AuthService()
        self.auth = auth
        let nativePush = NativePushManager(auth: auth)
        self.nativePush = nativePush
        NativePushAppDelegate.manager = nativePush
    }

    func start() {
        do {
            let state = try AppState(auth: auth)
            state.attachNativePushManager(nativePush)
            appState = state
            startupErrorMessage = nil
        } catch {
            appState = nil
            startupErrorMessage = gymErrorMessage(error)
        }
        hasAttemptedStart = true
    }

    /// Builds the heavy app state only after the first frame (the intro splash)
    /// has been committed, so the system launch screen hands off to drawn content
    /// instead of an empty window.
    func startIfNeeded() async {
        guard appState == nil, !hasAttemptedStart else { return }
        try? await Task.sleep(for: .milliseconds(60))
        start()
    }
}

@main
@MainActor
struct GymAppIOS: App {
    @UIApplicationDelegateAdaptor(NativePushAppDelegate.self) private var appDelegate
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue
    @StateObject private var bootstrap = AppBootstrap()
#if DEBUG
    @State private var showsIntro = !UIAuditLaunch.isActive

    init() {
        UIAuditLaunch.applyEarlyOverrides()
    }
#else
    @State private var showsIntro = true
#endif

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if let appState = bootstrap.appState {
                        AppRootView(
                            appState: appState,
                            nativePush: bootstrap.nativePush,
                            showsIntro: $showsIntro
                        )
                        .environmentObject(appState)
                        .environmentObject(appState.workoutStore)
                        .environmentObject(bootstrap.auth)
                        .environmentObject(bootstrap.nativePush)
                        .environment(appState.toasts)
                        .onOpenURL { url in
                            if !appState.handleSharedWorkoutURL(url),
                               !appState.garminPhoneSync.handleOpenURL(url) {
                                Task { await bootstrap.auth.handleOpenURL(url) }
                            }
                        }
                        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                            guard let url = activity.webpageURL else { return }
                            if !appState.handleSharedWorkoutURL(url) {
                                Task { await bootstrap.auth.handleOpenURL(url) }
                            }
                        }
                    } else if bootstrap.hasAttemptedStart {
                        StartupFailureView(
                            message: bootstrap.startupErrorMessage,
                            retry: bootstrap.start
                        )
                    }
                }

                if showsIntro {
                    IntroSplashView()
                        .environment(
                            \.locale,
                            AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en")
                        )
                        .gymTransition(.opacity.combined(with: .scale(scale: 1.015)))
                        .zIndex(20)
                }
            }
            // DESIGN.md: every button is a capsule; this covers the system
            // `.bordered` / `.borderedProminent` buttons (sheets inherit it too).
            .buttonBorderShape(.capsule)
            .task { await bootstrap.startIfNeeded() }
            .onChange(of: bootstrap.hasAttemptedStart) { _, attempted in
                if attempted, bootstrap.appState == nil { showsIntro = false }
            }
        }
    }
}

@MainActor
private struct StartupFailureView: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.firstRunDefault.rawValue

    let message: String?
    let retry: () -> Void

    var body: some View {
        GymContentUnavailableView {
            Label(
                gymText("Storage unavailable", "Сховище недоступне", "Хранилище недоступно", languageCode: languageCode),
                systemImage: "externaldrive.badge.exclamationmark"
            )
        } description: {
            Text(
                message ?? gymText(
                    "GymApp could not open its protected local storage. Your data was not changed.",
                    "GymApp не вдалося відкрити захищене локальне сховище. Твої дані не змінено.",
                    "GymApp не удалось открыть защищенное локальное хранилище. Твои данные не изменены.",
                    languageCode: languageCode
                )
            )
        } actions: {
            Button(
                gymText("Try again", "Спробувати ще раз", "Попробовать еще раз", languageCode: languageCode),
                action: retry
            )
            .gymProminentButtonStyle()
        }
        .environment(
            \.locale,
            AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en")
        )
    }
}
