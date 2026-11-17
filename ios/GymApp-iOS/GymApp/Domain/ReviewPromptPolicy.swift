import Foundation

/// Decides whether the app may ask for an App Store rating after a workout.
/// Pure and shared in spirit with Android: identical constants on both platforms.
enum ReviewPromptPolicy {
    static let minDaysBetweenRequests = 90
    static let maxRequests = 3
    static let minLoggedSets = 1

    static func isEligible(
        savedWorkoutCount: Int,
        loggedSetsInWorkout: Int,
        lastRequestAt: Date?,
        requestCount: Int,
        now: Date,
        isDemo: Bool
    ) -> Bool {
        guard !isDemo else { return false }
        guard savedWorkoutCount >= 1 else { return false }
        guard loggedSetsInWorkout >= minLoggedSets else { return false }
        guard requestCount < maxRequests else { return false }
        if let lastRequestAt {
            let interval = TimeInterval(minDaysBetweenRequests) * 86_400
            guard now.timeIntervalSince(lastRequestAt) >= interval else { return false }
        }
        return true
    }

    /// True for `--demo-mode`, any `-uiAudit*` / `--screenshot*` launch argument, or an XCTest host process.
    static var isDemoOrAutomation: Bool {
        let info = ProcessInfo.processInfo
        return info.arguments.contains("--demo-mode")
            || info.arguments.contains { $0.hasPrefix("-uiAudit") || $0.hasPrefix("--screenshot") }
            || info.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// Per-install record of review requests (UserDefaults; never synced, never tied to consent).
struct ReviewPromptStore {
    static let lastRequestKey = "last_review_request_at"
    static let countKey = "review_request_count"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastRequestAt: Date? {
        let value = defaults.double(forKey: Self.lastRequestKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    var requestCount: Int {
        defaults.integer(forKey: Self.countKey)
    }

    /// Records an attempt. The system decides whether a prompt is actually shown.
    func recordRequest(at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastRequestKey)
        defaults.set(requestCount + 1, forKey: Self.countKey)
    }
}
