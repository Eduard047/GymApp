import Foundation

/// The Live Activity / Dynamic Island `widgetURL`. Tapping it must land on the
/// active workout screen, so it is recognized before any other URL handler.
enum ActiveWorkoutDeepLink {
    static let scheme = "com.setforge.gymapp.ios"
    static let host = "active-workout"

    /// Exact match only: this scheme, this host, no path/query/fragment/credentials/port.
    static func isActiveWorkoutURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil else { return false }
        return true
    }

    /// How long a tap waits for the active draft to load (cold launch) before it is dropped.
    static let pendingOpenTimeout: TimeInterval = 4

    /// Identifier prefix of the local "Rest complete" notification (`RestTimerManager`).
    static let restNotificationIdentifierPrefix = "gymapp.rest."
    static let notificationTapRequested = Notification.Name("GymApp.activeWorkoutNotificationTapRequested")
    /// A stashed notification tap older than this is dropped (account never became ready).
    static let notificationTapTimeout: TimeInterval = 15

    static func isRestNotification(identifier: String) -> Bool {
        identifier.hasPrefix(restNotificationIdentifierPrefix)
    }

    /// A request is only raised when there is an active draft, or an account is still
    /// being prepared (the draft is not loaded yet); otherwise the tap is a normal open.
    static func shouldRequestOpen(hasDraft: Bool, isPreparingAccount: Bool) -> Bool {
        hasDraft || isPreparingAccount
    }

    @MainActor private static var pendingNotificationTapSince: Date?

    /// Stashes a rest-notification tap (cold launch: the UI does not exist yet) and wakes any listener.
    @MainActor static func noteNotificationTap(now: Date = Date()) {
        pendingNotificationTapSince = now
        NotificationCenter.default.post(name: notificationTapRequested, object: nil)
    }

    /// Returns true once for a fresh stashed tap and clears it.
    @MainActor static func takeNotificationTap(now: Date = Date()) -> Bool {
        defer { pendingNotificationTapSince = nil }
        guard let since = pendingNotificationTapSince else { return false }
        let age = now.timeIntervalSince(since)
        return age >= 0 && age <= notificationTapTimeout
    }

    enum PendingOpenAction: Equatable {
        case none, open, wait, drop
    }

    /// Decision for a pending Live Activity open request: open as soon as the draft
    /// exists, keep waiting while it has not loaded, drop it once the wait timed out.
    static func pendingOpenAction(requestPending: Bool, hasDraft: Bool, timedOut: Bool) -> PendingOpenAction {
        guard requestPending else { return .none }
        if hasDraft { return .open }
        return timedOut ? .drop : .wait
    }
}
