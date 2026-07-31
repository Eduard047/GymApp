import SwiftUI

@MainActor
final class AppBootstrap: ObservableObject {
    let auth: AuthService

    @Published private(set) var appState: AppState?
    @Published private(set) var startupErrorMessage: String?

    init() {
        let auth = AuthService()
        self.auth = auth
        start()
    }

    func start() {
        do {
            appState = try AppState(auth: auth)
            startupErrorMessage = nil
        } catch {
            appState = nil
            startupErrorMessage = gymErrorMessage(error)
        }
    }
}

@main
@MainActor
struct GymAppIOS: App {
    @StateObject private var bootstrap: AppBootstrap

    init() {
        _bootstrap = StateObject(wrappedValue: AppBootstrap())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let appState = bootstrap.appState {
                    AppRootView(appState: appState)
                        .environmentObject(appState)
                        .environmentObject(appState.workoutStore)
                        .environmentObject(bootstrap.auth)
                        .onOpenURL { url in
                            if !appState.garminPhoneSync.handleOpenURL(url) {
                                Task { await bootstrap.auth.handleOpenURL(url) }
                            }
                        }
                        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                            guard let url = activity.webpageURL else { return }
                            Task { await bootstrap.auth.handleOpenURL(url) }
                        }
                } else {
                    StartupFailureView(
                        message: bootstrap.startupErrorMessage,
                        retry: bootstrap.start
                    )
                }
            }
        }
    }
}

@MainActor
private struct StartupFailureView: View {
    @AppStorage("app-language") private var languageCode = AppLanguage.english.rawValue

    let message: String?
    let retry: () -> Void

    var body: some View {
        GymContentUnavailableView {
            Label(
                gymText("Storage unavailable", "Сховище недоступне", languageCode: languageCode),
                systemImage: "externaldrive.badge.exclamationmark"
            )
        } description: {
            Text(
                message ?? gymText(
                    "GymApp could not open its protected local storage. Your data was not changed.",
                    "GymApp не вдалося відкрити захищене локальне сховище. Твої дані не змінено.",
                    languageCode: languageCode
                )
            )
        } actions: {
            Button(
                gymText("Try again", "Спробувати ще раз", languageCode: languageCode),
                action: retry
            )
            .buttonStyle(.borderedProminent)
        }
        .environment(
            \.locale,
            AppLanguage(rawValue: languageCode)?.locale ?? Locale(identifier: "en")
        )
    }
}
