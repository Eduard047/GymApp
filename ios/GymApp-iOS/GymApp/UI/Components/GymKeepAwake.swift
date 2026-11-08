import SwiftUI
import UIKit

/// The in-app "Keep screen on during workouts" switch (Settings, default on, stored on this device
/// only). The active workout screen holds the idle timer off while it is visible and the app is active.
enum GymKeepAwake {
    static let preferenceKey = "app-keep-screen-on-during-workouts"

    /// Defaults to on when the preference was never written.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: preferenceKey) as? Bool ?? true
    }

    /// Whether the screen may be held awake right now: the switch is on and the app is in the foreground.
    static func shouldHoldScreen(enabled: Bool, scenePhase: ScenePhase) -> Bool {
        enabled && scenePhase == .active
    }

    @MainActor
    static func apply(_ hold: Bool) {
        if UIApplication.shared.isIdleTimerDisabled != hold {
            UIApplication.shared.isIdleTimerDisabled = hold
        }
    }
}
