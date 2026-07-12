import Combine
import Foundation
import UserNotifications

struct RestTimerState: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let endDate: Date
    let duration: Int

    func remaining(at date: Date = Date()) -> Int {
        max(0, Int(ceil(endDate.timeIntervalSince(date))))
    }
}

@MainActor
final class RestTimerManager: ObservableObject {
    @Published private(set) var timers: [String: RestTimerState] = [:]
    @Published private(set) var now = Date()
    @Published private(set) var notificationsDenied = false

    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let persistenceKey = "rest-timers-v1"
    private var ticker: AnyCancellable?

    init(notificationCenter: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        if let data = defaults.data(forKey: persistenceKey),
           let values = try? JSONDecoder().decode([String: RestTimerState].self, from: data) {
            self.timers = values.filter { $0.value.endDate > Date() }
        }
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                self.now = date
                let expired = self.timers.filter { $0.value.endDate <= date }.map(\.key)
                if !expired.isEmpty {
                    expired.forEach { self.timers.removeValue(forKey: $0) }
                    self.persist()
                }
            }
    }

    func remaining(for id: String) -> Int { timers[id]?.remaining(at: now) ?? 0 }

    func start(id: String, seconds: Int, title: String) async {
        let safeSeconds = min(max(seconds, 5), 30 * 60)
        let state = RestTimerState(id: id, endDate: Date().addingTimeInterval(TimeInterval(safeSeconds)), duration: safeSeconds)
        timers[id] = state
        persist()

        let settings = await notificationCenter.notificationSettings()
        var authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            authorized = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) == true
        }
        notificationsDenied = !authorized
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = gymLocalized("Rest complete")
        content.body = gymText(
            "Time for the next \(title) set.",
            "Час наступного підходу: \(title).",
            languageCode: gymCurrentLanguageCode()
        )
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(safeSeconds), repeats: false)
        let request = UNNotificationRequest(identifier: notificationID(id), content: content, trigger: trigger)
        try? await notificationCenter.add(request)
    }

    func cancel(id: String) {
        timers.removeValue(forKey: id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationID(id)])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [notificationID(id)])
        persist()
    }

    func cancelAll() {
        let ids = timers.keys.map(notificationID)
        timers.removeAll()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ids)
        persist()
    }

    private func notificationID(_ id: String) -> String { "gymapp.rest.\(id)" }

    private func persist() {
        if let data = try? JSONEncoder().encode(timers) {
            defaults.set(data, forKey: persistenceKey)
        }
    }
}
