import Foundation

/// The one-line status under the Profile "Watches" row: every connected source,
/// joined by " · ". Order matches Android (Garmin · Wear OS · Health data):
/// Garmin · Apple Watch · Health data. Pure so it can be unit-tested without any service.
enum WatchesStatus {
    static let separator = " · "

    /// - Parameters:
    ///   - garminPaired: a Garmin watch is paired for the active account.
    ///   - appleWatchLinked: an Apple Watch is paired and has GymApp installed.
    ///   - healthConnected: Apple Health import is enabled for the active account.
    static func summary(
        garminPaired: Bool,
        appleWatchLinked: Bool = false,
        healthConnected: Bool,
        languageCode: String
    ) -> String {
        var sources: [String] = []
        if garminPaired {
            sources.append("Garmin")
        }
        if appleWatchLinked {
            sources.append("Apple Watch")
        }
        if healthConnected {
            sources.append(gymText("Health data", "Дані про здоров’я", "Данные о здоровье", languageCode: languageCode))
        }
        if sources.isEmpty {
            return gymText("Not connected", "Не підключено", "Не подключено", languageCode: languageCode)
        }
        return sources.joined(separator: separator)
    }
}
