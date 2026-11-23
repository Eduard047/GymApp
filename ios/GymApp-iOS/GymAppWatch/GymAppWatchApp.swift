import SwiftUI
import WatchKit

@main
struct GymAppWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var model = WatchAppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { model.launch() }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Activates WatchConnectivity on background launches too, so queued acks and
    /// contexts are handled without waiting for the first scene.
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            WatchAppModel.shared.launch()
        }
    }

    /// The system relaunched the app with a workout session still active.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            await WatchAppModel.shared.recoverHealthSession()
        }
    }
}
