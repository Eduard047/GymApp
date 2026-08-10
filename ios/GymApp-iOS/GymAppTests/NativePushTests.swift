import Foundation
import XCTest
@testable import GymApp

@MainActor
final class NativePushTests: XCTestCase {
    private let userA = "10000000-0000-4000-8000-000000000001"
    private let userB = "20000000-0000-4000-8000-000000000002"
    private let bindingA = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let bindingB = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let installationID = UUID(uuidString: "12345678-1234-4abc-8def-1234567890ab")!

    func testParserAcceptsOnlyExactDataOnlySocialAndLivePayloads() throws {
        let social = socialPayload(bindingID: bindingA)
        let parsedSocial = try XCTUnwrap(NativePushPayloadParser.remoteEvent(from: social))
        XCTAssertEqual(parsedSocial.bindingID, bindingA)
        XCTAssertEqual(parsedSocial.eventType, .friendRequestReceived)
        XCTAssertEqual(parsedSocial.objectID, "f_0123456789abcdef0123456789abcdef")
        XCTAssertEqual(parsedSocial.objectRevision, 7)

        let live: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "gymapp": [
                "version": 1,
                "bindingId": bindingA.uuidString.lowercased(),
                "kind": "started",
                "roomId": "lr_0123456789abcdef0123456789abcdef",
                "roomRevision": 9
            ]
        ]
        let parsedLive = try XCTUnwrap(NativePushPayloadParser.remoteEvent(from: live))
        XCTAssertEqual(parsedLive.eventType, .liveRoomStarted)
        XCTAssertEqual(parsedLive.eventType.destination, .live)

        var alert = social
        alert["aps"] = ["content-available": 1, "alert": ["title": "unsafe"]]
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: alert))

        var sound = social
        sound["aps"] = ["content-available": 1, "sound": "default"]
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: sound))

        var booleanVersion = social
        var booleanObject = try XCTUnwrap(booleanVersion["gymapp"] as? [String: Any])
        booleanObject["version"] = true
        booleanVersion["gymapp"] = booleanObject
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: booleanVersion))

        var unknown = social
        var unknownObject = try XCTUnwrap(unknown["gymapp"] as? [String: Any])
        unknownObject["profileName"] = "private"
        unknown["gymapp"] = unknownObject
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: unknown))

        var mismatchedObject = social
        var mismatchObject = try XCTUnwrap(mismatchedObject["gymapp"] as? [String: Any])
        mismatchObject["objectId"] = "wi_0123456789abcdef0123456789abcdef"
        mismatchedObject["gymapp"] = mismatchObject
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: mismatchedObject))
    }

    func testBindingStoreKeepsStableInstallationIDAndRejectsMalformedBinding() throws {
        let keychain = PushTestKeychain()
        let first = NativePushBindingStore(keychain: keychain)
        let installation = try first.installationID()
        XCTAssertEqual(try NativePushBindingStore(keychain: keychain).installationID(), installation)

        let binding = NativePushBinding(
            version: 1,
            installationID: installation,
            userID: userA,
            bindingID: bindingA,
            environment: .sandbox,
            tokenDigest: String(repeating: "a", count: 64),
            registrationRevision: 2
        )
        try first.saveBinding(binding)
        XCTAssertEqual(try first.loadBinding(), binding)

        try keychain.save(Data(#"{"version":999}"#.utf8), account: "native-push-binding-v1")
        XCTAssertNil(try first.loadBinding())
        XCTAssertNil(try keychain.read(account: "native-push-binding-v1"))
    }

    func testRegistrationBindsPayloadBeforeLocalDisplayAndTapRouting() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }

        await harness.manager.activateIfNeeded()
        XCTAssertEqual(harness.system.registerCallCount, 1)
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x41, count: 32))
        let becameActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(becameActive)
        XCTAssertEqual(harness.backend.operations, ["register:\(userA)"])
        XCTAssertEqual(harness.store.binding?.bindingID, bindingA)

        let wrongBindingOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: UUID())
        )
        XCTAssertEqual(wrongBindingOutcome, .noData)
        XCTAssertTrue(harness.system.scheduled.isEmpty)

        let acceptedOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(acceptedOutcome, .newData)
        let scheduled = try XCTUnwrap(harness.system.scheduled.last)
        XCTAssertEqual(scheduled.destination, .social)
        XCTAssertFalse(scheduled.title.contains(userA))
        XCTAssertFalse(scheduled.body.contains("f_"))

        harness.manager.handleLocalNotificationTap(
            identifier: scheduled.identifier,
            userInfo: localTapPayload(bindingID: bindingA, destination: .social)
        )
        XCTAssertEqual(harness.manager.consumePendingRoute()?.destination, .social)

        harness.manager.handleLocalNotificationTap(
            identifier: scheduled.identifier,
            userInfo: localTapPayload(bindingID: bindingB, destination: .live)
        )
        XCTAssertNil(harness.manager.consumePendingRoute())
    }

    func testAccountSwitchImmediatelyFencesOldBindingAndSerializesNewOwner() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x42, count: 32))
        let firstRegistrationFinished = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(firstRegistrationFinished)

        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        let oldOwnerOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(oldOwnerOutcome, .noData)
        let secondRegistrationFinished = await waitUntil {
            harness.store.binding?.userID == self.userB
                && harness.manager.status == .active
        }
        XCTAssertTrue(secondRegistrationFinished)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "register:\(userB)"
        ])
        XCTAssertGreaterThanOrEqual(harness.system.removeAllCallCount, 1)

        let newOwnerOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingB)
        )
        XCTAssertEqual(newOwnerOutcome, .newData)
    }

    func testSessionEndClearsLocalBindingAndRevokesAfterRegistration() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x43, count: 32))
        let becameActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(becameActive)

        await harness.manager.prepareForSessionEnd(expectedUserID: userA)
        XCTAssertNil(harness.store.binding)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)"
        ])
        let postRevokeOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(postRevokeOutcome, .noData)
        XCTAssertGreaterThanOrEqual(harness.system.unregisterCallCount, 1)
    }

    func testAccountSwitchDuringInFlightRegisterCannotLeaveOldOwnerLast() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        harness.backend.suspendRegistration(for: userA)
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x44, count: 32))
        let firstStarted = await waitUntil {
            harness.backend.operations == ["register:\(self.userA)"]
        }
        XCTAssertTrue(firstStarted)

        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        XCTAssertEqual(harness.backend.operations, ["register:\(userA)"])
        harness.backend.resumeSuspendedRegistration()

        let switched = await waitUntil {
            harness.store.binding?.userID == self.userB
                && harness.manager.status == .active
        }
        XCTAssertTrue(switched)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "register:\(userB)"
        ])
        XCTAssertEqual(harness.store.binding?.bindingID, bindingB)
    }

    func testAccountSwitchDuringLocalSchedulingRemovesLateNotification() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x45, count: 32))
        let active = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(active)
        harness.system.suspendNextSchedule()

        let delivery = Task { @MainActor in
            await harness.manager.handleRemoteNotification(
                self.socialPayload(bindingID: self.bindingA)
            )
        }
        let schedulingStarted = await waitUntil { harness.system.scheduleIsSuspended }
        XCTAssertTrue(schedulingStarted)
        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        harness.system.resumeSuspendedSchedule()

        let outcome = await delivery.value
        XCTAssertEqual(outcome, .noData)
        XCTAssertTrue(harness.system.scheduled.isEmpty)
    }

    func testSessionEndLatchPreventsForegroundReactivationBeforeLogout() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x46, count: 32))
        let active = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(active)
        harness.backend.suspendNextRevoke()

        let ending = Task { @MainActor in
            await harness.manager.prepareForSessionEnd(expectedUserID: self.userA)
        }
        let revokeStarted = await waitUntil {
            harness.backend.operations.last == "revoke:\(self.userA)"
        }
        XCTAssertTrue(revokeStarted)
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x46, count: 32))
        harness.backend.resumeSuspendedRevoke()
        await ending.value

        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)"
        ])
        XCTAssertNil(harness.store.binding)
    }

    func testSupabaseBackendUsesExactBoundedRegisterAndRevokeContracts() async throws {
        let suiteName = "NativePushBackendTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativePushURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer {
            NativePushURLProtocolStub.handler = nil
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let auth = AuthService(
            keychain: PushTestKeychain(),
            urlSession: session,
            defaults: defaults
        )
        try auth.installSessionForTesting(cloudSession(userID: userA))
        let requests = PushRequestRecorder()
        NativePushURLProtocolStub.handler = { request in
            requests.append(request)
            let body: String
            switch request.url?.path {
            case "/rest/v1/rpc/notification_register_installation":
                body = """
                {"version":1,"installationId":"\(self.installationID.uuidString.lowercased())","provider":"apns","environment":"sandbox","bindingId":"\(self.bindingA.uuidString.lowercased())","registrationRevision":3,"registeredAt":"2026-08-10T08:00:00Z"}
                """
            case "/rest/v1/rpc/notification_revoke_installation":
                body = """
                {"version":1,"installationId":"\(self.installationID.uuidString.lowercased())","revoked":true}
                """
            default:
                body = #"{"message":"not found"}"#
            }
            let status = request.url?.path.hasPrefix("/rest/v1/rpc/notification_") == true
                ? 200
                : 404
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data(body.utf8))
        }

        let client = SupabaseNativePushBackendClient(auth: auth, urlSession: session)
        let registered = try await client.register(
            installationID: installationID,
            environment: .sandbox,
            token: String(repeating: "ab", count: 32),
            locale: "en-US",
            appVersion: "3.0.4",
            expectedUserID: userA
        )
        XCTAssertEqual(registered.bindingID, bindingA)
        try await client.revoke(installationID: installationID, expectedUserID: userA)

        XCTAssertEqual(requests.requests.map { $0.url?.path }, [
            "/rest/v1/rpc/notification_register_installation",
            "/rest/v1/rpc/notification_revoke_installation"
        ])
        XCTAssertTrue(requests.requests.allSatisfy { request in
            request.httpMethod == "POST"
                && request.value(forHTTPHeaderField: "apikey") ==
                    GymAppConfiguration.supabasePublishableKey
                && request.value(forHTTPHeaderField: "Authorization") ==
                    "Bearer synthetic-access-token"
        })
        let registerBody = try requestObject(requests.requests[0])
        XCTAssertEqual(Set(registerBody.keys), [
            "p_installation_id", "p_platform", "p_provider", "p_environment",
            "p_provider_token", "p_web_push_p256dh", "p_web_push_auth", "p_locale",
            "p_app_version"
        ])
        XCTAssertEqual(registerBody["p_platform"] as? String, "ios")
        XCTAssertEqual(registerBody["p_provider"] as? String, "apns")
        XCTAssertEqual(registerBody["p_environment"] as? String, "sandbox")
        XCTAssertTrue(registerBody["p_web_push_p256dh"] is NSNull)
        XCTAssertTrue(registerBody["p_web_push_auth"] is NSNull)
        XCTAssertEqual(
            Set(try requestObject(requests.requests[1]).keys),
            ["p_installation_id"]
        )
    }

    func testDeniedPermissionNeverRegistersOrStoresBinding() async throws {
        let harness = try makeHarness(userID: userA, enabled: false, permission: .denied)
        defer { harness.cleanup() }

        await harness.manager.enable()
        XCTAssertEqual(harness.manager.status, .denied)
        XCTAssertFalse(harness.manager.isEnabled)
        XCTAssertEqual(harness.system.registerCallCount, 0)
        XCTAssertNil(harness.store.binding)
        XCTAssertTrue(harness.backend.operations.isEmpty)
    }

    private func makeHarness(
        userID: String,
        enabled: Bool = true,
        permission: NativePushPermissionState = .authorized
    ) throws -> PushHarness {
        let suiteName = "NativePushTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(enabled, forKey: "gymapp.native-push.enabled.v1")
        let auth = AuthService(keychain: PushTestKeychain(), defaults: defaults)
        try auth.installSessionForTesting(cloudSession(userID: userID))
        let store = PushBindingMemoryStore(installationID: installationID)
        let backend = PushBackendFake(bindings: [userA: bindingA, userB: bindingB])
        let system = PushSystemFake(permission: permission)
        let manager = NativePushManager(
            auth: auth,
            defaults: defaults,
            store: store,
            backend: backend,
            system: system,
            environment: .sandbox
        )
        return PushHarness(
            suiteName: suiteName,
            defaults: defaults,
            auth: auth,
            store: store,
            backend: backend,
            system: system,
            manager: manager
        )
    }

    private func cloudSession(userID: String) -> AppAccountSession {
        .cloud(CloudAccountSession(
            userID: userID,
            email: "push@example.invalid",
            displayName: "Push Tester",
            accessToken: "synthetic-access-token",
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        ))
    }

    private func socialPayload(bindingID: UUID) -> [AnyHashable: Any] {
        [
            "aps": ["content-available": 1],
            "gymapp": [
                "version": 1,
                "bindingId": bindingID.uuidString.lowercased(),
                "type": "friend_request_received",
                "objectId": "f_0123456789abcdef0123456789abcdef",
                "objectRevision": 7
            ]
        ]
    }

    private func localTapPayload(
        bindingID: UUID,
        destination: NativePushDestination
    ) -> [AnyHashable: Any] {
        [
            "gymappLocal": [
                "version": 1,
                "bindingId": bindingID.uuidString.lowercased(),
                "destination": destination.rawValue
            ]
        ]
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func requestObject(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 1_024)
                if count < 0 { throw NativePushError.invalidResponse }
                if count == 0 { break }
                result.append(buffer, count: count)
            }
            data = result
        } else {
            throw NativePushError.invalidResponse
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
private struct PushHarness {
    let suiteName: String
    let defaults: UserDefaults
    let auth: AuthService
    let store: PushBindingMemoryStore
    let backend: PushBackendFake
    let system: PushSystemFake
    let manager: NativePushManager

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class PushTestKeychain: KeychainStoring {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        lock.withLock { values[account] = data }
    }

    func read(account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func delete(account: String) throws {
        lock.withLock { _ = values.removeValue(forKey: account) }
    }
}

private final class PushBindingMemoryStore: NativePushBindingStoring {
    let fixedInstallationID: UUID
    private(set) var binding: NativePushBinding?

    init(installationID: UUID, binding: NativePushBinding? = nil) {
        fixedInstallationID = installationID
        self.binding = binding
    }

    func installationID() throws -> UUID { fixedInstallationID }
    func loadBinding() throws -> NativePushBinding? { binding }
    func saveBinding(_ binding: NativePushBinding) throws { self.binding = binding }
    func clearBinding() throws { binding = nil }
}

@MainActor
private final class PushBackendFake: NativePushBackendServing {
    private let bindings: [String: UUID]
    private(set) var operations: [String] = []
    private var suspendedUserID: String?
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendRevoke = false
    private var revokeContinuation: CheckedContinuation<Void, Never>?

    init(bindings: [String: UUID]) {
        self.bindings = bindings
    }

    func register(
        installationID: UUID,
        environment: NativePushEnvironment,
        token: String,
        locale: String?,
        appVersion: String?,
        expectedUserID: String
    ) async throws -> NativePushRegistrationResponse {
        operations.append("register:\(expectedUserID)")
        if suspendedUserID == expectedUserID {
            await withCheckedContinuation { continuation in
                suspendedContinuation = continuation
            }
            suspendedUserID = nil
        }
        guard let binding = bindings[expectedUserID], token.utf8.count == 64 else {
            throw NativePushError.invalidState
        }
        return NativePushRegistrationResponse(
            installationID: installationID,
            bindingID: binding,
            environment: environment,
            registrationRevision: operations.count
        )
    }

    func revoke(installationID: UUID, expectedUserID: String) async throws {
        operations.append("revoke:\(expectedUserID)")
        if shouldSuspendRevoke {
            shouldSuspendRevoke = false
            await withCheckedContinuation { continuation in
                revokeContinuation = continuation
            }
        }
    }

    func suspendRegistration(for userID: String) {
        suspendedUserID = userID
    }

    func resumeSuspendedRegistration() {
        suspendedContinuation?.resume()
        suspendedContinuation = nil
    }

    func suspendNextRevoke() {
        shouldSuspendRevoke = true
    }

    func resumeSuspendedRevoke() {
        revokeContinuation?.resume()
        revokeContinuation = nil
    }
}

@MainActor
private final class PushSystemFake: NativePushSystemControlling {
    var permission: NativePushPermissionState
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var removeAllCallCount = 0
    private(set) var scheduled: [NativePushLocalNotification] = []
    private var scheduleContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendSchedule = false

    var scheduleIsSuspended: Bool { scheduleContinuation != nil }

    init(permission: NativePushPermissionState) {
        self.permission = permission
    }

    func configure() {}
    func permissionState() async -> NativePushPermissionState { permission }
    func requestPermission() async throws -> NativePushPermissionState { permission }
    func registerForRemoteNotifications() { registerCallCount += 1 }
    func unregisterForRemoteNotifications() { unregisterCallCount += 1 }
    func schedule(_ notification: NativePushLocalNotification) async throws {
        if shouldSuspendSchedule {
            shouldSuspendSchedule = false
            await withCheckedContinuation { continuation in
                scheduleContinuation = continuation
            }
        }
        scheduled.removeAll { $0.identifier == notification.identifier }
        scheduled.append(notification)
    }
    func removeNotification(identifier: String) async {
        scheduled.removeAll { $0.identifier == identifier }
    }
    func removeAllAccountBoundNotifications() async {
        removeAllCallCount += 1
        scheduled.removeAll()
    }


    func suspendNextSchedule() {
        shouldSuspendSchedule = true
    }

    func resumeSuspendedSchedule() {
        scheduleContinuation?.resume()
        scheduleContinuation = nil
    }
}

private final class PushRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { stored } }

    func append(_ request: URLRequest) {
        lock.withLock { stored.append(request) }
    }
}

private final class NativePushURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handler }
        do {
            guard let handler else { throw NativePushError.requestFailed }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
