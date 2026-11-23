import Foundation

/// The one-line status under the Profile "Watches" row: every connected source,
/// joined by " · ". Pure so it can be unit-tested without any service.
enum WatchesStatus {
    static let separator = " · "

    /// - Parameters:
    ///   - garminPaired: a Garmin watch is paired for the active account.
    ///   - healthConnected: Apple Health import is enabled for the active account.
    static func summary(garminPaired: Bool, healthConnected: Bool, languageCode: String) -> String {
        var sources: [String] = []
        if garminPaired {
            sources.append("Garmin")
        }
        if healthConnected {
            sources.append(gymText("Health data", "Дані здоров’я", "Данные здоровья", languageCode: languageCode))
        }
        if sources.isEmpty {
            return gymText("Not connected", "Не підключено", "Не подключено", languageCode: languageCode)
        }
        return sources.joined(separator: separator)
    }
}
