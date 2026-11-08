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

    /// Views that currently want the screen held, one token each. Counting holders (instead of a raw
    /// on/off) keeps an outgoing view's `onDisappear` from switching off a newer view's hold.
    @MainActor private static var holders = GymKeepAwakeHolders()

    /// Registers (`hold == true`) or drops (`hold == false`) the hold of one view instance, then
    /// updates the idle timer: it is off only while at least one view holds the screen.
    @MainActor
    static func update(hold: Bool, token: UUID) {
        if hold {
            holders.acquire(token)
        } else {
            holders.release(token)
        }
        apply(holders.isHeld)
    }

    @MainActor
    private static func apply(_ hold: Bool) {
        if UIApplication.shared.isIdleTimerDisabled != hold {
            UIApplication.shared.isIdleTimerDisabled = hold
        }
    }
}

/// The set of view tokens that hold the screen awake. Pure value type so the counting is unit-testable.
struct GymKeepAwakeHolders {
    private(set) var tokens: Set<UUID> = []

    var isHeld: Bool { !tokens.isEmpty }

    mutating func acquire(_ token: UUID) { tokens.insert(token) }

    mutating func release(_ token: UUID) { tokens.remove(token) }
}
