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
