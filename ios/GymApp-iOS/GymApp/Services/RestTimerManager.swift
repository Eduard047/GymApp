import Combine
import CryptoKit
import Foundation
import UserNotifications

@MainActor
protocol RestNotificationCenterClient: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func removeAllDeliveredNotifications()
}

@MainActor
final class SystemRestNotificationCenterClient: RestNotificationCenterClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removeAllPendingNotificationRequests() {
        center.removeAllPendingNotificationRequests()
    }

    func removeAllDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
    }
}

struct RestTimerState: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let endDate: Date
    let duration: Int

    func remaining(at date: Date = Date()) -> Int {
        max(0, Int(ceil(endDate.timeIntervalSince(date))))
    }
}

private struct PersistedRestTimers: Codable {
    let version: Int
    let ownerFingerprint: String
    let timers: [String: RestTimerState]
}

@MainActor
final class RestTimerManager: ObservableObject {
    @Published private(set) var timers: [String: RestTimerState] = [:]
    @Published private(set) var now = Date()
    @Published private(set) var notificationsDenied = false

    private let notificationCenter: RestNotificationCenterClient
    private let defaults: UserDefaults
    private let currentDateProvider: () -> Date
    private let persistenceKey = "rest-timers-v1"
    private var ticker: AnyCancellable?
    private var notificationLifecycleGeneration: UInt64 = 0
    private var hasBoundAccount = false
    private var activeOwnerFingerprint: String?

    private static let persistenceVersion = 2
    private static let maxPersistedBytes = 512 * 1_024
    private static let maxPersistedTimers = 256
    private static let maxTimerIDBytes = 256
    private static let maxNotificationTitleCharacters = 160

    init(
        notificationCenter: RestNotificationCenterClient? = nil,
        defaults: UserDefaults = .standard,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter ?? SystemRestNotificationCenterClient()
        self.defaults = defaults
        self.currentDateProvider = currentDateProvider
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

    nonisolated static func ownerFingerprint(for accountStorageKey: String) -> String {
        let input = Data("gymapp-rest-timer-owner-v1:\(accountStorageKey)".utf8)
        return SHA256.hash(data: input)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func bindToAccount(
        ownerFingerprint: String?,
        discardPersistedState: Bool = false
    ) {
        if hasBoundAccount {
            guard discardPersistedState || activeOwnerFingerprint != ownerFingerprint else { return }
            activeOwnerFingerprint = ownerFingerprint
            discardAllState()
            return
        }

        hasBoundAccount = true
        activeOwnerFingerprint = ownerFingerprint
        notificationLifecycleGeneration &+= 1

        guard !discardPersistedState,
              let ownerFingerprint,
              Self.isValidOwnerFingerprint(ownerFingerprint),
              let data = defaults.data(forKey: persistenceKey),
              data.count <= Self.maxPersistedBytes,
              let persisted = try? JSONDecoder().decode(PersistedRestTimers.self, from: data),
              persisted.version == Self.persistenceVersion,
              persisted.ownerFingerprint == ownerFingerprint,
              persisted.timers.count <= Self.maxPersistedTimers,
              persisted.timers.allSatisfy({ key, state in
                  key == state.id && Self.isValidPersistedTimer(state)
              }) else {
            discardAllState(incrementGeneration: false)
            return
        }

        let activeTimers = persisted.timers.filter { $0.value.endDate > currentDateProvider() }
        timers = activeTimers
        if activeTimers.count != persisted.timers.count {
            persist()
        }
    }

    func remaining(for id: String) -> Int { timers[id]?.remaining(at: now) ?? 0 }

    @discardableResult
    func adjust(id: String, by seconds: Int, title: String) -> Task<Void, Never> {
        let currentRemaining = remaining(for: id)
        guard currentRemaining > 0 else { return Task {} }
        let adjusted = currentRemaining + seconds
        if adjusted <= 0 {
            cancel(id: id)
            return Task {}
        }
        return start(id: id, seconds: adjusted, title: title)
    }

    @discardableResult
    func start(id: String, seconds: Int, title: String) -> Task<Void, Never> {
        guard hasBoundAccount,
              let ownerFingerprint = activeOwnerFingerprint,
              Self.isValidTimerID(id),
              timers[id] != nil || timers.count < Self.maxPersistedTimers else {
            return Task {}
        }
        let safeSeconds = min(max(seconds, 5), 30 * 60)
        let state = RestTimerState(
            id: id,
            endDate: currentDateProvider().addingTimeInterval(TimeInterval(safeSeconds)),
            duration: safeSeconds
        )
        let expectedLifecycleGeneration = notificationLifecycleGeneration
        if let previousState = timers[id] {
            let identifiers = notificationIdentifiers(for: previousState)
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
            notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
        timers[id] = state
        persist()

        let safeTitle = String(title.prefix(Self.maxNotificationTitleCharacters))
        return Task { [weak self] in
            guard let self else { return }
            await self.scheduleNotification(
                for: state,
                title: safeTitle,
                lifecycleGeneration: expectedLifecycleGeneration,
                ownerFingerprint: ownerFingerprint
            )
        }
    }

    private func scheduleNotification(
        for state: RestTimerState,
        title: String,
        lifecycleGeneration: UInt64,
        ownerFingerprint: String
    ) async {
        let authorizationStatus = await notificationCenter.authorizationStatus()
        guard isCurrent(
            state,
            lifecycleGeneration: lifecycleGeneration,
            ownerFingerprint: ownerFingerprint
        ) else { return }
        var authorized = authorizationStatus == .authorized || authorizationStatus == .provisional
        if authorizationStatus == .notDetermined {
            authorized = await notificationCenter.requestAuthorization()
            guard isCurrent(
                state,
                lifecycleGeneration: lifecycleGeneration,
                ownerFingerprint: ownerFingerprint
            ) else { return }
        }
        notificationsDenied = !authorized
        guard authorized else { return }
        let remainingTime = state.endDate.timeIntervalSince(currentDateProvider())
        guard remainingTime.isFinite, remainingTime > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = gymLocalized("Rest complete")
        content.body = gymText(
            "Time for the next \(title) set.",
            "Час наступного підходу: \(title).",
            languageCode: gymCurrentLanguageCode()
        )
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: remainingTime,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: notificationID(for: state),
            content: content,
            trigger: trigger
        )
        do {
            try await notificationCenter.add(request)
        } catch {
            return
        }
        guard isCurrent(
            state,
            lifecycleGeneration: lifecycleGeneration,
            ownerFingerprint: ownerFingerprint
        ) else {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            notificationCenter.removeDeliveredNotifications(withIdentifiers: [request.identifier])
            return
        }
    }

    func cancel(id: String) {
        let state = timers.removeValue(forKey: id)
        let identifiers = state.map(notificationIdentifiers) ?? [legacyNotificationID(id)]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        persist()
    }

    func cancelAll() {
        notificationLifecycleGeneration &+= 1
        timers.removeAll()
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        persist()
    }

    private func notificationID(for state: RestTimerState) -> String {
        let deadline = String(state.endDate.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
        return "gymapp.rest.\(state.id).\(deadline)"
    }

    private func legacyNotificationID(_ id: String) -> String { "gymapp.rest.\(id)" }

    private func notificationIdentifiers(for state: RestTimerState) -> [String] {
        [notificationID(for: state), legacyNotificationID(state.id)]
    }

    private func isCurrent(
        _ state: RestTimerState,
        lifecycleGeneration: UInt64,
        ownerFingerprint: String
    ) -> Bool {
        notificationLifecycleGeneration == lifecycleGeneration &&
            activeOwnerFingerprint == ownerFingerprint &&
            timers[state.id] == state
    }

    private func persist() {
        guard let ownerFingerprint = activeOwnerFingerprint else {
            defaults.removeObject(forKey: persistenceKey)
            return
        }
        let persisted = PersistedRestTimers(
            version: Self.persistenceVersion,
            ownerFingerprint: ownerFingerprint,
            timers: timers
        )
        guard let data = try? JSONEncoder().encode(persisted),
              data.count <= Self.maxPersistedBytes else {
            defaults.removeObject(forKey: persistenceKey)
            return
        }
        defaults.set(data, forKey: persistenceKey)
    }

    private func discardAllState(incrementGeneration: Bool = true) {
        if incrementGeneration {
            notificationLifecycleGeneration &+= 1
        }
        timers.removeAll()
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        defaults.removeObject(forKey: persistenceKey)
    }

    private static func isValidOwnerFingerprint(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48 ... 57).contains($0) || (97 ... 102).contains($0)
        }
    }

    private static func isValidTimerID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= maxTimerIDBytes
    }

    private static func isValidPersistedTimer(_ state: RestTimerState) -> Bool {
        let remaining = state.endDate.timeIntervalSinceNow
        return isValidTimerID(state.id) &&
            (5 ... 30 * 60).contains(state.duration) &&
            remaining.isFinite &&
            remaining <= TimeInterval(30 * 60)
    }
}
