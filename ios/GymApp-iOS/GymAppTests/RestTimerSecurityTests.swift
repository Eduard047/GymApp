import Foundation
import UserNotifications
import XCTest
@testable import GymApp

@MainActor
final class RestTimerSecurityTests: XCTestCase {
    func testAccountCleanupRemovesNotificationsAfterExpiredTimerMetadataWasPruned() throws {
        let defaults = temporaryDefaults()
        let expired = RestTimerState(
            id: "private-exercise",
            endDate: Date().addingTimeInterval(-60),
            duration: 60
        )
        defaults.set(
            try JSONEncoder().encode([expired.id: expired]),
            forKey: "rest-timers-v1"
        )
        let notifications = RecordingRestNotificationCenter()
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: defaults
        )

        manager.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(for: "local_account-a")
        )

        XCTAssertEqual(notifications.removeAllPendingCallCount, 1)
        XCTAssertEqual(notifications.removeAllDeliveredCallCount, 1)
        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertNil(defaults.data(forKey: "rest-timers-v1"))
    }

    func testColdStartRejectsLegacyUnownedTimerAndNotificationsForActiveAccount() async throws {
        let authDefaults = temporaryDefaults()
        let auth = AuthService(
            keychain: RestTimerTestKeychainStore(),
            defaults: authDefaults
        )
        let accountB = AppAccountSession.local(id: "account-b", displayName: "Account B")
        try auth.installSessionForTesting(accountB)

        let timerDefaults = temporaryDefaults()
        let legacyTimer = RestTimerState(
            id: "account-a-exercise",
            endDate: Date().addingTimeInterval(300),
            duration: 300
        )
        timerDefaults.set(
            try JSONEncoder().encode([legacyTimer.id: legacyTimer]),
            forKey: "rest-timers-v1"
        )
        let notifications = RecordingRestNotificationCenter()
        notifications.seedPending(identifier: "gymapp.rest.legacy-account-a-pending")
        notifications.seedDelivered(identifier: "gymapp.rest.legacy-account-a-delivered")
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: timerDefaults
        )
        let appState = try AppState(
            auth: auth,
            defaults: authDefaults,
            workoutDirectoryURL: try temporaryDirectory(),
            restTimers: manager
        )

        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertTrue(notifications.pendingIdentifiers.isEmpty)
        XCTAssertTrue(notifications.deliveredIdentifiers.isEmpty)
        XCTAssertEqual(notifications.removeAllPendingCallCount, 1)
        XCTAssertEqual(notifications.removeAllDeliveredCallCount, 1)
        XCTAssertNil(timerDefaults.data(forKey: "rest-timers-v1"))
    }

    func testColdStartRejectsTimerOwnedByDifferentAccount() async throws {
        let authDefaults = temporaryDefaults()
        let auth = AuthService(
            keychain: RestTimerTestKeychainStore(),
            defaults: authDefaults
        )
        let accountA = AppAccountSession.local(id: "account-a", displayName: "Account A")
        let accountB = AppAccountSession.local(id: "account-b", displayName: "Account B")
        try auth.installSessionForTesting(accountB)

        let timerDefaults = temporaryDefaults()
        _ = await persistOwnedTimer(
            id: "account-a-exercise",
            seconds: 300,
            accountStorageKey: accountA.storageKey,
            defaults: timerDefaults
        )
        let notifications = RecordingRestNotificationCenter()
        notifications.seedPending(identifier: "gymapp.rest.account-a-pending")
        notifications.seedDelivered(identifier: "gymapp.rest.account-a-delivered")
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: timerDefaults
        )
        let appState = try AppState(
            auth: auth,
            defaults: authDefaults,
            workoutDirectoryURL: try temporaryDirectory(),
            restTimers: manager
        )

        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertTrue(notifications.pendingIdentifiers.isEmpty)
        XCTAssertTrue(notifications.deliveredIdentifiers.isEmpty)
        XCTAssertEqual(notifications.removeAllPendingCallCount, 1)
        XCTAssertEqual(notifications.removeAllDeliveredCallCount, 1)
        XCTAssertNil(timerDefaults.data(forKey: "rest-timers-v1"))
    }

    func testSameAccountActivationPreservesTimerButReplacementAccountClearsIt() async throws {
        let authDefaults = temporaryDefaults()
        let auth = AuthService(
            keychain: RestTimerTestKeychainStore(),
            defaults: authDefaults
        )
        let accountA = AppAccountSession.local(id: "account-a", displayName: "Account A")
        let accountB = AppAccountSession.local(id: "account-b", displayName: "Account B")
        try auth.installSessionForTesting(accountA)

        let timerDefaults = temporaryDefaults()
        let active = await persistOwnedTimer(
            id: "same-owner-exercise",
            seconds: 300,
            accountStorageKey: accountA.storageKey,
            defaults: timerDefaults
        )
        let persisted = try XCTUnwrap(timerDefaults.data(forKey: "rest-timers-v1"))
        XCTAssertFalse(
            String(decoding: persisted, as: UTF8.self).contains(accountA.storageKey),
            "Persisted timer ownership must not expose the raw account storage key."
        )

        let notifications = RecordingRestNotificationCenter()
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: timerDefaults
        )
        let appState = try AppState(
            auth: auth,
            defaults: authDefaults,
            workoutDirectoryURL: try temporaryDirectory(),
            restTimers: manager
        )

        let initialAccountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(initialAccountReady)
        XCTAssertNotNil(manager.timers[active.id])
        XCTAssertEqual(notifications.removeAllPendingCallCount, 0)
        XCTAssertEqual(notifications.removeAllDeliveredCallCount, 0)

        appState.retryAccountActivation()

        let retriedAccountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(retriedAccountReady)
        XCTAssertNotNil(manager.timers[active.id], "Retrying the same account must preserve its active timer.")
        XCTAssertEqual(notifications.removeAllPendingCallCount, 0)
        XCTAssertEqual(notifications.removeAllDeliveredCallCount, 0)

        try auth.installSessionForTesting(accountB)

        let replacementAccountReady = await waitUntil {
            appState.isAccountReady && appState.activeAccountStorageKey == accountB.storageKey
        }
        XCTAssertTrue(replacementAccountReady)
        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertEqual(notifications.removeAllPendingCallCount, 1)
        XCTAssertEqual(notifications.removeAllDeliveredCallCount, 1)
        XCTAssertNil(timerDefaults.data(forKey: "rest-timers-v1"))
    }

    func testAppStateSignOutClearsForgottenNotificationsAndInMemoryTimers() async throws {
        let authDefaults = temporaryDefaults()
        let auth = AuthService(
            keychain: RestTimerTestKeychainStore(),
            defaults: authDefaults
        )
        let account = AppAccountSession.local(id: "account-a", displayName: "Account A")
        try auth.installSessionForTesting(account)

        let timerDefaults = temporaryDefaults()
        let active = await persistOwnedTimer(
            id: "active-exercise",
            seconds: 300,
            accountStorageKey: account.storageKey,
            defaults: timerDefaults
        )
        let notifications = RecordingRestNotificationCenter()
        notifications.seedPending(identifier: "gymapp.rest.forgotten-pending")
        notifications.seedDelivered(identifier: "gymapp.rest.forgotten-delivered")
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: timerDefaults
        )
        let appState = try AppState(
            auth: auth,
            defaults: authDefaults,
            workoutDirectoryURL: try temporaryDirectory(),
            restTimers: manager
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        XCTAssertEqual(manager.timers[active.id], active)

        await appState.signOut()

        XCTAssertNil(auth.session)
        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertTrue(notifications.pendingIdentifiers.isEmpty)
        XCTAssertTrue(notifications.deliveredIdentifiers.isEmpty)
        XCTAssertEqual(notifications.removeAllPendingCallCount, 1)
        XCTAssertEqual(notifications.removeAllDeliveredCallCount, 1)
        XCTAssertNil(timerDefaults.data(forKey: "rest-timers-v1"))
    }

    func testCleanupInvalidatesAnInFlightOldScheduleWithoutRemovingReplacementTimer() async {
        let defaults = temporaryDefaults()
        let notifications = RecordingRestNotificationCenter()
        notifications.authorizationStatusValue = .authorized
        notifications.suspendAdds = true
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: defaults
        )
        manager.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(for: "local_account-a")
        )
        let start = manager.start(
            id: "private-exercise",
            seconds: 60,
            title: "Private Exercise"
        )
        let addSuspended = await waitUntil { notifications.addIsSuspended }
        XCTAssertTrue(addSuspended)

        manager.cancelAll()
        notifications.suspendAdds = false
        await manager.start(
            id: "private-exercise",
            seconds: 90,
            title: "Replacement Exercise"
        ).value
        let replacementIdentifiers = notifications.pendingIdentifiers
        XCTAssertEqual(replacementIdentifiers.count, 1)
        notifications.resumeAdd()
        await start.value

        XCTAssertNotNil(manager.timers["private-exercise"])
        XCTAssertEqual(notifications.pendingIdentifiers, replacementIdentifiers)
        XCTAssertTrue(notifications.deliveredIdentifiers.isEmpty)
    }

    func testAuthorizationDelaySchedulesOnlyTheRemainingTimerDuration() async throws {
        let defaults = temporaryDefaults()
        let notifications = RecordingRestNotificationCenter()
        notifications.authorizationStatusValue = .notDetermined
        notifications.requestAuthorizationResult = true
        notifications.suspendAuthorizationRequests = true
        let clock = RestTimerTestClock()
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: defaults,
            currentDateProvider: { clock.date }
        )
        manager.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(for: "local_account-a")
        )

        let start = manager.start(
            id: "delayed-permission-exercise",
            seconds: 60,
            title: "Exercise"
        )
        let authorizationSuspended = await waitUntil {
            notifications.authorizationRequestIsSuspended
        }
        XCTAssertTrue(authorizationSuspended)

        clock.advance(by: 17)
        notifications.resumeAuthorization()
        await start.value

        let interval = try XCTUnwrap(notifications.addedTriggerIntervals.single)
        XCTAssertEqual(interval, 43, accuracy: 0.001)
    }

    func testExpiredTimerIsNotScheduledAfterAuthorizationReturns() async {
        let defaults = temporaryDefaults()
        let notifications = RecordingRestNotificationCenter()
        notifications.authorizationStatusValue = .notDetermined
        notifications.requestAuthorizationResult = true
        notifications.suspendAuthorizationRequests = true
        let clock = RestTimerTestClock()
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: defaults,
            currentDateProvider: { clock.date }
        )
        manager.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(for: "local_account-a")
        )

        let start = manager.start(
            id: "expired-permission-exercise",
            seconds: 5,
            title: "Exercise"
        )
        let authorizationSuspended = await waitUntil {
            notifications.authorizationRequestIsSuspended
        }
        XCTAssertTrue(authorizationSuspended)

        clock.advance(by: 6)
        notifications.resumeAuthorization()
        await start.value

        XCTAssertTrue(notifications.addedTriggerIntervals.isEmpty)
        XCTAssertTrue(notifications.pendingIdentifiers.isEmpty)
    }

    func testStartCapturesOwnerBeforeNotificationTaskRunsAfterAccountTransition() async {
        let defaults = temporaryDefaults()
        let notifications = RecordingRestNotificationCenter()
        notifications.authorizationStatusValue = .authorized
        let manager = RestTimerManager(
            notificationCenter: notifications,
            defaults: defaults
        )
        let accountAFingerprint = RestTimerManager.ownerFingerprint(for: "local_account-a")
        let accountBFingerprint = RestTimerManager.ownerFingerprint(for: "local_account-b")
        manager.bindToAccount(ownerFingerprint: accountAFingerprint)

        // The returned task cannot enter its main-actor body until this test yields.
        let oldAccountSchedule = manager.start(
            id: "account-a-exercise",
            seconds: 60,
            title: "Account A Exercise"
        )
        manager.bindToAccount(ownerFingerprint: accountBFingerprint)
        await oldAccountSchedule.value

        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertTrue(notifications.pendingIdentifiers.isEmpty)
        XCTAssertTrue(notifications.deliveredIdentifiers.isEmpty)
        XCTAssertNil(defaults.data(forKey: "rest-timers-v1"))
    }

    func testStartBoundsPersistedTimerCountWhileAllowingReplacement() async {
        let defaults = temporaryDefaults()
        let manager = RestTimerManager(
            notificationCenter: RecordingRestNotificationCenter(),
            defaults: defaults
        )
        manager.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(for: "local_account-a")
        )

        for index in 0 ..< 256 {
            manager.start(id: "exercise-\(index)", seconds: 60, title: "Exercise")
        }
        await manager.start(id: "overflow-exercise", seconds: 60, title: "Overflow").value

        XCTAssertEqual(manager.timers.count, 256)
        XCTAssertNil(manager.timers["overflow-exercise"])
        await manager.start(id: "exercise-0", seconds: 90, title: "Replacement").value
        XCTAssertEqual(manager.timers.count, 256)
        XCTAssertEqual(manager.timers["exercise-0"]?.duration, 90)
        XCTAssertLessThanOrEqual(
            defaults.data(forKey: "rest-timers-v1")?.count ?? .max,
            512 * 1_024
        )
    }

    private func persistOwnedTimer(
        id: String,
        seconds: Int,
        accountStorageKey: String,
        defaults: UserDefaults
    ) async -> RestTimerState {
        let manager = RestTimerManager(
            notificationCenter: RecordingRestNotificationCenter(),
            defaults: defaults
        )
        manager.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(for: accountStorageKey)
        )
        await manager.start(id: id, seconds: seconds, title: "Exercise").value
        return manager.timers[id]!
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "GymAppTests.RestTimerSecurity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppTests.RestTimerSecurity.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0 ..< 300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

@MainActor
private final class RecordingRestNotificationCenter: RestNotificationCenterClient {
    var authorizationStatusValue: UNAuthorizationStatus = .denied
    var requestAuthorizationResult = false
    var suspendAuthorizationRequests = false
    var suspendAdds = false
    private(set) var removeAllPendingCallCount = 0
    private(set) var removeAllDeliveredCallCount = 0
    private(set) var pendingIdentifiers = Set<String>()
    private(set) var deliveredIdentifiers = Set<String>()
    private(set) var addedTriggerIntervals: [TimeInterval] = []
    private(set) var authorizationRequestIsSuspended = false
    private(set) var addIsSuspended = false
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var addContinuation: CheckedContinuation<Void, Never>?

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusValue
    }

    func requestAuthorization() async -> Bool {
        if suspendAuthorizationRequests {
            authorizationRequestIsSuspended = true
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
            }
            authorizationRequestIsSuspended = false
        }
        return requestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        if suspendAdds {
            addIsSuspended = true
            await withCheckedContinuation { continuation in
                addContinuation = continuation
            }
            addIsSuspended = false
        }
        pendingIdentifiers.insert(request.identifier)
        if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
            addedTriggerIntervals.append(trigger.timeInterval)
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        pendingIdentifiers.subtract(identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        deliveredIdentifiers.subtract(identifiers)
    }

    func removeAllPendingNotificationRequests() {
        removeAllPendingCallCount += 1
        pendingIdentifiers.removeAll()
    }

    func removeAllDeliveredNotifications() {
        removeAllDeliveredCallCount += 1
        deliveredIdentifiers.removeAll()
    }

    func seedPending(identifier: String) {
        pendingIdentifiers.insert(identifier)
    }

    func seedDelivered(identifier: String) {
        deliveredIdentifiers.insert(identifier)
    }

    func resumeAdd() {
        let continuation = addContinuation
        addContinuation = nil
        continuation?.resume()
    }

    func resumeAuthorization() {
        suspendAuthorizationRequests = false
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        continuation?.resume()
    }
}

@MainActor
private final class RestTimerTestClock {
    private(set) var date = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func advance(by seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

private extension Collection {
    var single: Element? { count == 1 ? first : nil }
}

private final class RestTimerTestKeychainStore: KeychainStoring {
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        values[account] = data
    }

    func read(account: String) throws -> Data? {
        values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }
}
