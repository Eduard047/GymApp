import UIKit

/// Home-screen quick action "Start workout" (static `UIApplicationShortcutItems`).
/// The request is process-local: stashed here by the app/scene delegates (cold launch and
/// warm action) and consumed by `MainTabShell` once an account is ready.
enum StartWorkoutShortcut {
    static let itemType = "com.setforge.gymapp.ios.shortcut.start-workout"
    static let requestedNotification = Notification.Name("GymApp.startWorkoutShortcutRequested")

    /// A request older than this is dropped (signed out, or the account never became ready).
    static let pendingTimeout: TimeInterval = 4
    /// Time the active draft gets to load before the shortcut falls back to the plan editor.
    static let settleDelay: TimeInterval = 0.7

    static func isStartWorkout(_ item: UIApplicationShortcutItem) -> Bool {
        item.type == itemType
    }

    enum Action: Equatable {
        case none, wait, drop, openActiveWorkout, openWorkoutEditor
    }

    /// Routing decision: no account -> plain launch (drop); active draft -> active workout;
    /// otherwise the plan editor behind the Today "Start workout" button (never auto-creates).
    static func action(
        requestPending: Bool,
        hasAccount: Bool,
        hasDraft: Bool,
        age: TimeInterval
    ) -> Action {
        guard requestPending else { return .none }
        guard hasAccount, age <= pendingTimeout else { return .drop }
        if hasDraft { return .openActiveWorkout }
        return age >= settleDelay ? .openWorkoutEditor : .wait
    }

    @MainActor private(set) static var pendingSince: Date?

    @MainActor static var pendingAge: TimeInterval {
        pendingSince.map { Date().timeIntervalSince($0) } ?? 0
    }

    /// A cold launch delivers the same item to the app delegate and to the scene delegate; a
    /// request that is already pending (and not stale) is that same request, so it is kept as is.
    static func isDuplicate(pendingAge: TimeInterval?) -> Bool {
        guard let pendingAge else { return false }
        return pendingAge >= 0 && pendingAge <= pendingTimeout
    }

    /// Returns whether the item was a Start workout shortcut (and stashes the request).
    /// Idempotent: handling the same cold-launch item twice stashes one request.
    @MainActor @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard isStartWorkout(item) else { return false }
        if isDuplicate(pendingAge: pendingSince.map { Date().timeIntervalSince($0) }) {
            return true
        }
        pendingSince = Date()
        NotificationCenter.default.post(name: requestedNotification, object: nil)
        return true
    }

    /// Connection-time entry point shared by both delegates (nil when launched normally).
    @MainActor static func handleConnection(shortcutItem: UIApplicationShortcutItem?) {
        guard let shortcutItem else { return }
        handle(shortcutItem)
    }

    @MainActor static func consume() {
        pendingSince = nil
    }
}

/// Receives quick actions while the app is already running (warm launch).
@MainActor
final class StartWorkoutShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch from a quick action: the item arrives in the connection options. Only this
    /// method is implemented for scene lifecycle; URLs and user activities stay with SwiftUI.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        StartWorkoutShortcut.handleConnection(shortcutItem: connectionOptions.shortcutItem)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(StartWorkoutShortcut.handle(shortcutItem))
    }
}
