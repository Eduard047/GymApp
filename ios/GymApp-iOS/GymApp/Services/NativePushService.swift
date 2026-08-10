import Combine
import CryptoKit
import Foundation
import Security
import UIKit
import UserNotifications

enum NativePushEnvironment: String, Codable, Sendable {
    case sandbox
    case production

    static var current: Self {
#if DEBUG
        .sandbox
#else
        .production
#endif
    }
}

enum NativePushPermissionState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var permitsNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: true
        case .notDetermined, .denied: false
        }
    }
}

enum NativePushStatus: Equatable, Sendable {
    case disabled
    case requestingPermission
    case waitingForDeviceToken
    case registering
    case active
    case denied
    case unavailable
    case failed
}

enum NativePushDestination: String, Equatable, Sendable {
    case social
    case live
}

struct NativePushRoute: Identifiable, Equatable, Sendable {
    let id: UUID
    let destination: NativePushDestination

    init(id: UUID = UUID(), destination: NativePushDestination) {
        self.id = id
        self.destination = destination
    }
}

enum NativePushFetchOutcome: Equatable, Sendable {
    case noData
    case newData
    case failed

    var backgroundFetchResult: UIBackgroundFetchResult {
        switch self {
        case .noData: .noData
        case .newData: .newData
        case .failed: .failed
        }
    }
}

struct NativePushRemoteEvent: Equatable, Sendable {
    enum EventType: String, CaseIterable, Sendable {
        case friendRequestReceived = "friend_request_received"
        case friendRequestAccepted = "friend_request_accepted"
        case workoutInviteReceived = "workout_invite_received"
        case workoutInviteAccepted = "workout_invite_accepted"
        case liveInviteReceived = "live_invite_received"
        case liveInviteAccepted = "live_invite_accepted"
        case liveRoomStarted = "live_room_started"
        case liveParticipantFinished = "live_participant_finished"
        case liveRoomClosed = "live_room_closed"

        var destination: NativePushDestination {
            rawValue.hasPrefix("live_") ? .live : .social
        }
    }

    let bindingID: UUID
    let eventType: EventType
    let objectID: String
    let objectRevision: Int
}

enum NativePushPayloadParser {
    private static let liveKinds: [String: NativePushRemoteEvent.EventType] = [
        "invite": .liveInviteReceived,
        "joined": .liveInviteAccepted,
        "started": .liveRoomStarted,
        "participant_finished": .liveParticipantFinished,
        "room_closed": .liveRoomClosed
    ]

    static func remoteEvent(from userInfo: [AnyHashable: Any]) -> NativePushRemoteEvent? {
        guard let aps = stringDictionary(userInfo["aps"]),
              Set(aps.keys) == ["content-available"],
              exactInteger(aps["content-available"]) == 1,
              let payload = stringDictionary(userInfo["gymapp"]),
              exactInteger(payload["version"]) == 1,
              let bindingString = boundedString(payload["bindingId"], maximumBytes: 36),
              let bindingID = versionFourUUID(bindingString) else {
            return nil
        }

        if let kind = boundedString(payload["kind"], maximumBytes: 32) {
            guard Set(payload.keys) == [
                "version", "bindingId", "kind", "roomId", "roomRevision"
            ], let eventType = liveKinds[kind],
               let roomID = boundedString(payload["roomId"], maximumBytes: 35),
               roomID.range(of: "^lr_[0-9a-f]{32}$", options: .regularExpression) != nil,
               let revision = boundedRevision(payload["roomRevision"]) else {
                return nil
            }
            return NativePushRemoteEvent(
                bindingID: bindingID,
                eventType: eventType,
                objectID: roomID,
                objectRevision: revision
            )
        }

        guard Set(payload.keys) == [
            "version", "bindingId", "type", "objectId", "objectRevision"
        ], let typeString = boundedString(payload["type"], maximumBytes: 32),
           let eventType = NativePushRemoteEvent.EventType(rawValue: typeString),
           eventType.destination == .social,
           let objectID = boundedString(payload["objectId"], maximumBytes: 35),
           let revision = boundedRevision(payload["objectRevision"]) else {
            return nil
        }
        let expectedPattern = typeString.hasPrefix("friend_")
            ? "^f_[0-9a-f]{32}$"
            : "^wi_[0-9a-f]{32}$"
        guard objectID.range(of: expectedPattern, options: .regularExpression) != nil else {
            return nil
        }
        return NativePushRemoteEvent(
            bindingID: bindingID,
            eventType: eventType,
            objectID: objectID,
            objectRevision: revision
        )
    }

    static func localDestination(
        from userInfo: [AnyHashable: Any],
        expectedBindingID: UUID
    ) -> NativePushDestination? {
        guard Set(userInfo.keys.compactMap { $0 as? String }) == ["gymappLocal"],
              userInfo.keys.count == 1,
              let payload = stringDictionary(userInfo["gymappLocal"]),
              Set(payload.keys) == ["version", "bindingId", "destination"],
              exactInteger(payload["version"]) == 1,
              let bindingString = boundedString(payload["bindingId"], maximumBytes: 36),
              versionFourUUID(bindingString) == expectedBindingID,
              let destinationString = boundedString(
                payload["destination"],
                maximumBytes: 16
              ) else {
            return nil
        }
        return NativePushDestination(rawValue: destinationString)
    }

    private static func stringDictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        guard let dictionary = value as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            guard let key = key as? String, result[key] == nil else { return nil }
            result[key] = value
        }
        return result
    }

    private static func boundedString(_ value: Any?, maximumBytes: Int) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.prefix(maximumBytes + 1).count <= maximumBytes else {
            return nil
        }
        return value
    }

    private static func exactInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              double >= Double(Int.min),
              double <= Double(Int.max) else {
            return nil
        }
        return Int(double)
    }

    private static func boundedRevision(_ value: Any?) -> Int? {
        guard let revision = exactInteger(value),
              (0 ... 2_147_483_647).contains(revision) else {
            return nil
        }
        return revision
    }

    private static func versionFourUUID(_ value: String) -> UUID? {
        guard value.utf8.count == 36,
              value.range(
                of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
                options: .regularExpression
              ) != nil else {
            return nil
        }
        return UUID(uuidString: value)
    }
}

struct NativePushBinding: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let installationID: UUID
    let userID: String
    let bindingID: UUID
    let environment: NativePushEnvironment
    let tokenDigest: String
    let registrationRevision: Int
}

protocol NativePushBindingStoring {
    func installationID() throws -> UUID
    func loadBinding() throws -> NativePushBinding?
    func saveBinding(_ binding: NativePushBinding) throws
    func clearBinding() throws
}

struct NativePushBindingStore: NativePushBindingStoring {
    private let keychain: KeychainStoring
    private let installationAccount = "native-push-installation-v1"
    private let bindingAccount = "native-push-binding-v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        keychain: KeychainStoring = NativePushKeychainStore(
            service: "com.setforge.gymapp.ios.native-push"
        )
    ) {
        self.keychain = keychain
    }

    func installationID() throws -> UUID {
        if let data = try keychain.read(account: installationAccount),
           data.count == 36,
           let value = String(data: data, encoding: .utf8),
           let stored = UUID(uuidString: value) {
            return stored
        }
        let created = UUID()
        try keychain.save(
            Data(created.uuidString.lowercased().utf8),
            account: installationAccount
        )
        return created
    }

    func loadBinding() throws -> NativePushBinding? {
        guard let data = try keychain.read(account: bindingAccount) else { return nil }
        guard data.count <= 2_048,
              let binding = try? decoder.decode(NativePushBinding.self, from: data),
              binding.version == NativePushBinding.currentVersion,
              binding.userID.utf8.count == 36,
              UUID(uuidString: binding.userID) != nil,
              binding.tokenDigest.range(
                of: "^[0-9a-f]{64}$",
                options: .regularExpression
              ) != nil,
              (1 ... 2_147_483_647).contains(binding.registrationRevision) else {
            try keychain.delete(account: bindingAccount)
            return nil
        }
        return binding
    }

    func saveBinding(_ binding: NativePushBinding) throws {
        guard binding.version == NativePushBinding.currentVersion,
              binding.userID.utf8.count == 36,
              UUID(uuidString: binding.userID) != nil,
              binding.tokenDigest.range(
                of: "^[0-9a-f]{64}$",
                options: .regularExpression
              ) != nil,
              (1 ... 2_147_483_647).contains(binding.registrationRevision) else {
            throw NativePushError.invalidState
        }
        let data = try encoder.encode(binding)
        guard data.count <= 2_048 else { throw NativePushError.invalidState }
        try keychain.save(data, account: bindingAccount)
    }

    func clearBinding() throws {
        try keychain.delete(account: bindingAccount)
    }
}

/// Account-bound push metadata must be readable during a background wake while the
/// phone is locked. These opaque, noncredential records remain device-only and become
/// available only after the first unlock following a reboot.
struct NativePushKeychainStore: KeychainStoring {
    let service: String

    func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(insertStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        return result as? Data
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}

struct NativePushRegistrationResponse: Equatable, Sendable {
    let installationID: UUID
    let bindingID: UUID
    let environment: NativePushEnvironment
    let registrationRevision: Int
}

protocol NativePushBackendServing: AnyObject {
    func register(
        installationID: UUID,
        environment: NativePushEnvironment,
        token: String,
        locale: String?,
        appVersion: String?,
        expectedUserID: String
    ) async throws -> NativePushRegistrationResponse

    func revoke(installationID: UUID, expectedUserID: String) async throws
}

enum NativePushError: LocalizedError {
    case invalidState
    case invalidResponse
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidState: "Notification registration is not available."
        case .invalidResponse: "The notification service returned an invalid response."
        case .requestFailed: "Notification registration could not be completed."
        }
    }
}

@MainActor
final class SupabaseNativePushBackendClient: NativePushBackendServing {
    private enum RequestFailure: Error {
        case http(Int)
    }

    private let auth: AuthService
    private let urlSession: URLSession

    private static let maximumRequestBytes = 8 * 1_024
    private static let maximumResponseBytes = 16 * 1_024
    private static let maximumErrorBytes = 8 * 1_024
    private static let maximumTokenBytes = 16 * 1_024

    init(auth: AuthService, urlSession: URLSession = .shared) {
        self.auth = auth
        self.urlSession = urlSession
    }

    func register(
        installationID: UUID,
        environment: NativePushEnvironment,
        token: String,
        locale: String?,
        appVersion: String?,
        expectedUserID: String
    ) async throws -> NativePushRegistrationResponse {
        guard token.range(of: "^[0-9a-f]{32,200}$", options: .regularExpression) != nil,
              token.utf8.count.isMultiple(of: 2) else {
            throw NativePushError.invalidState
        }
        var body: [String: Any] = [
            "p_installation_id": installationID.uuidString.lowercased(),
            "p_platform": "ios",
            "p_provider": "apns",
            "p_environment": environment.rawValue,
            "p_provider_token": token,
            "p_web_push_p256dh": NSNull(),
            "p_web_push_auth": NSNull()
        ]
        body["p_locale"] = locale ?? NSNull()
        body["p_app_version"] = appVersion ?? NSNull()
        let data = try await authenticatedRequest(
            path: "/rest/v1/rpc/notification_register_installation",
            body: body,
            expectedUserID: expectedUserID
        )
        return try Self.parseRegistration(
            data,
            expectedInstallationID: installationID,
            expectedEnvironment: environment
        )
    }

    func revoke(installationID: UUID, expectedUserID: String) async throws {
        let data = try await authenticatedRequest(
            path: "/rest/v1/rpc/notification_revoke_installation",
            body: ["p_installation_id": installationID.uuidString.lowercased()],
            expectedUserID: expectedUserID
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["version", "installationId", "revoked"],
              Self.exactInteger(object["version"]) == 1,
              let returnedID = object["installationId"] as? String,
              UUID(uuidString: returnedID) == installationID,
              object["revoked"] is Bool else {
            throw NativePushError.invalidResponse
        }
    }

    private func authenticatedRequest(
        path: String,
        body: [String: Any],
        expectedUserID: String
    ) async throws -> Data {
        let initial = try await auth.validCloudSession(expectedUserID: expectedUserID)
        do {
            let data = try await requestOnce(path: path, body: body, token: initial.accessToken)
            guard auth.session?.cloud?.userID == expectedUserID else {
                throw AuthServiceError.sessionChanged
            }
            return data
        } catch RequestFailure.http(let status) where status == 401 || status == 403 {
            guard auth.session?.cloud == initial else { throw AuthServiceError.sessionChanged }
            let refreshed = try await auth.validCloudSession(
                expectedUserID: expectedUserID,
                forceRefresh: true
            )
            let data = try await requestOnce(path: path, body: body, token: refreshed.accessToken)
            guard auth.session?.cloud?.userID == expectedUserID else {
                throw AuthServiceError.sessionChanged
            }
            return data
        } catch let authError as AuthServiceError {
            throw authError
        } catch {
            throw NativePushError.requestFailed
        }
    }

    private func requestOnce(
        path: String,
        body: [String: Any],
        token: String
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: GymAppConfiguration.supabaseURL),
              !token.isEmpty,
              token.utf8.prefix(Self.maximumTokenBytes + 1).count <= Self.maximumTokenBytes,
              token.unicodeScalars.allSatisfy({ (0x21 ... 0x7e).contains($0.value) }) else {
            throw NativePushError.invalidState
        }
        let encoded = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        guard encoded.count <= Self.maximumRequestBytes else { throw NativePushError.invalidState }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.httpBody = encoded
        request.setValue(GymAppConfiguration.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await BoundedURLSessionLoader.data(
                for: request,
                using: urlSession,
                successLimit: Self.maximumResponseBytes,
                errorLimit: Self.maximumErrorBytes
            )
        } catch {
            throw NativePushError.requestFailed
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw RequestFailure.http(response.statusCode)
        }
        return data
    }

    private static func parseRegistration(
        _ data: Data,
        expectedInstallationID: UUID,
        expectedEnvironment: NativePushEnvironment
    ) throws -> NativePushRegistrationResponse {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == [
                "version", "installationId", "provider", "environment", "bindingId",
                "registrationRevision", "registeredAt"
              ],
              exactInteger(object["version"]) == 1,
              let installationString = object["installationId"] as? String,
              UUID(uuidString: installationString) == expectedInstallationID,
              object["provider"] as? String == "apns",
              object["environment"] as? String == expectedEnvironment.rawValue,
              let bindingString = object["bindingId"] as? String,
              bindingString.range(
                of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
                options: .regularExpression
              ) != nil,
              let bindingID = UUID(uuidString: bindingString),
              let revision = exactInteger(object["registrationRevision"]),
              (1 ... 2_147_483_647).contains(revision),
              let registeredAt = object["registeredAt"] as? String,
              !registeredAt.isEmpty,
              registeredAt.utf8.count <= 64 else {
            throw NativePushError.invalidResponse
        }
        return NativePushRegistrationResponse(
            installationID: expectedInstallationID,
            bindingID: bindingID,
            environment: expectedEnvironment,
            registrationRevision: revision
        )
    }

    private static func exactInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let double = number.doubleValue
        guard double.isFinite,
              double.rounded(.towardZero) == double,
              double >= 0,
              double <= Double(Int.max) else {
            return nil
        }
        return Int(double)
    }
}

struct NativePushLocalNotification: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let bindingID: UUID
    let destination: NativePushDestination
}

@MainActor
protocol NativePushSystemControlling: AnyObject {
    func configure()
    func permissionState() async -> NativePushPermissionState
    func requestPermission() async throws -> NativePushPermissionState
    func registerForRemoteNotifications()
    func unregisterForRemoteNotifications()
    func schedule(_ notification: NativePushLocalNotification) async throws
    func removeNotification(identifier: String) async
    func removeAllAccountBoundNotifications() async
}

@MainActor
final class NativePushSystemController: NativePushSystemControlling {
    static let categoryIdentifier = "gymapp.account-bound.v1"
    static let notificationIdentifierPrefix = "gymapp.push.v1."

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func configure() {
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func permissionState() async -> NativePushPermissionState {
        let settings = await center.notificationSettings()
        return Self.permissionState(settings.authorizationStatus)
    }

    func requestPermission() async throws -> NativePushPermissionState {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await permissionState()
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func unregisterForRemoteNotifications() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    func schedule(_ notification: NativePushLocalNotification) async throws {
        await removeNotification(identifier: notification.identifier)
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "gymappLocal": [
                "version": 1,
                "bindingId": notification.bindingID.uuidString.lowercased(),
                "destination": notification.destination.rawValue
            ]
        ]
        // The short delay leaves an account transition enough time to remove a newly
        // scheduled notification if the authenticated owner changes during `add`.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try await center.add(
            UNNotificationRequest(
                identifier: notification.identifier,
                content: content,
                trigger: trigger
            )
        )
    }

    func removeNotification(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func removeAllAccountBoundNotifications() async {
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.notificationIdentifierPrefix) }
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(Self.notificationIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    private static func permissionState(
        _ status: UNAuthorizationStatus
    ) -> NativePushPermissionState {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .denied
        }
    }
}

@MainActor
final class NativePushManager: ObservableObject {
    @Published private(set) var status: NativePushStatus = .disabled
    @Published private(set) var permissionState: NativePushPermissionState = .notDetermined
    @Published private(set) var pendingRoute: NativePushRoute?

    private let auth: AuthService
    private let defaults: UserDefaults
    private let store: NativePushBindingStoring
    private let backend: NativePushBackendServing
    private let system: NativePushSystemControlling
    private let environment: NativePushEnvironment
    private var installationID: UUID?

    private var binding: NativePushBinding?
    private var deviceToken: Data?
    private var currentUserID: String?
    private var lifecycleGeneration: UInt64 = 0
    private var isFenced = true
    private var sessionEndUserID: String?
    private var authSubscription: AnyCancellable?
    private var backendTail: Task<Void, Never>?
    private var pendingRegistrationKey: String?

    private static let enabledDefaultsKey = "gymapp.native-push.enabled.v1"

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledDefaultsKey) }

    init(
        auth: AuthService,
        defaults: UserDefaults = .standard,
        store: NativePushBindingStoring = NativePushBindingStore(),
        backend: NativePushBackendServing? = nil,
        system: NativePushSystemControlling? = nil,
        environment: NativePushEnvironment = .current
    ) {
        self.auth = auth
        self.defaults = defaults
        self.store = store
        self.backend = backend ?? SupabaseNativePushBackendClient(auth: auth)
        self.system = system ?? NativePushSystemController()
        self.environment = environment
        self.currentUserID = auth.session?.cloud?.userID

        do {
            let installationID = try store.installationID()
            self.installationID = installationID
            if let stored = try store.loadBinding(),
               stored.installationID == installationID,
               stored.userID == currentUserID,
               stored.environment == environment {
                binding = stored
                isFenced = currentUserID == nil
                status = isEnabled && !isFenced ? .active : .disabled
            } else {
                binding = nil
                try? store.clearBinding()
                isFenced = currentUserID == nil
            }
        } catch {
            installationID = nil
            binding = nil
            isFenced = true
            status = .unavailable
        }

        self.system.configure()
        authSubscription = auth.$session.sink { [weak self] session in
            self?.authSessionWillChange(to: session?.cloud?.userID)
        }
    }

    deinit {
        backendTail?.cancel()
    }

    func activateIfNeeded() async {
        guard installationID != nil, let userID = auth.session?.cloud?.userID else {
            if installationID == nil { status = .unavailable }
            return
        }
        guard currentUserID == userID, sessionEndUserID != userID else { return }
        if isFenced {
            isFenced = false
        }
        permissionState = await system.permissionState()
        guard isEnabled else {
            status = permissionState == .denied ? .denied : .disabled
            return
        }
        guard permissionState.permitsNotifications else {
            status = permissionState == .denied ? .denied : .disabled
            return
        }
        status = binding == nil ? .waitingForDeviceToken : .active
        system.registerForRemoteNotifications()
        if let deviceToken {
            enqueueRegistration(token: deviceToken, expectedUserID: userID)
        }
    }

    func enable() async {
        guard installationID != nil, auth.session?.cloud != nil else {
            status = .unavailable
            return
        }
        status = .requestingPermission
        do {
            permissionState = try await system.requestPermission()
        } catch {
            status = .failed
            return
        }
        guard permissionState.permitsNotifications else {
            defaults.set(false, forKey: Self.enabledDefaultsKey)
            status = .denied
            return
        }
        defaults.set(true, forKey: Self.enabledDefaultsKey)
        status = .waitingForDeviceToken
        await activateIfNeeded()
    }

    func disable() async {
        defaults.set(false, forKey: Self.enabledDefaultsKey)
        let userID = auth.session?.cloud?.userID
        await fenceAndRevoke(expectedUserID: userID)
        status = permissionState == .denied ? .denied : .disabled
    }

    /// Called before logout/account deletion while the caller still owns a valid token.
    /// The local fence is immediate; a best-effort server revoke is serialized behind any
    /// in-flight registration so a late register can never become the final operation.
    func prepareForSessionEnd(expectedUserID: String) async {
        guard auth.session?.cloud?.userID == expectedUserID else { return }
        sessionEndUserID = expectedUserID
        await fenceAndRevoke(expectedUserID: expectedUserID)
    }

    func resumeAfterFailedSessionEnd(expectedUserID: String) async {
        guard auth.session?.cloud?.userID == expectedUserID,
              currentUserID == expectedUserID else {
            return
        }
        sessionEndUserID = nil
        isFenced = false
        await activateIfNeeded()
    }

    func didReceiveDeviceToken(_ token: Data) {
        guard (16 ... 100).contains(token.count) else {
            status = .failed
            return
        }
        deviceToken = token
        guard isEnabled,
              !isFenced,
              let userID = auth.session?.cloud?.userID,
              userID == currentUserID else {
            return
        }
        enqueueRegistration(token: token, expectedUserID: userID)
    }

    func didFailToRegisterForRemoteNotifications() {
        guard isEnabled else { return }
        status = .failed
    }

    func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> NativePushFetchOutcome {
        guard isEnabled,
              !isFenced,
              let event = NativePushPayloadParser.remoteEvent(from: userInfo),
              let binding,
              binding.bindingID == event.bindingID,
              binding.environment == environment,
              binding.installationID == installationID,
              binding.userID == currentUserID,
              auth.session?.cloud?.userID == binding.userID else {
            return .noData
        }
        let generation = lifecycleGeneration
        let local = localNotification(for: event)
        do {
            try await system.schedule(local)
        } catch {
            return .failed
        }
        guard lifecycleGeneration == generation,
              !isFenced,
              self.binding == binding,
              auth.session?.cloud?.userID == binding.userID else {
            await system.removeNotification(identifier: local.identifier)
            return .noData
        }
        return .newData
    }

    func handleLocalNotificationTap(
        identifier: String,
        userInfo: [AnyHashable: Any]
    ) {
        guard identifier.hasPrefix(NativePushSystemController.notificationIdentifierPrefix),
              !isFenced,
              let binding,
              binding.userID == currentUserID,
              auth.session?.cloud?.userID == binding.userID,
              let destination = NativePushPayloadParser.localDestination(
                from: userInfo,
                expectedBindingID: binding.bindingID
              ) else {
            return
        }
        pendingRoute = NativePushRoute(destination: destination)
    }

    func consumePendingRoute() -> NativePushRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    private func authSessionWillChange(to userID: String?) {
        guard userID != currentUserID else { return }
        let previousUserID = currentUserID
        lifecycleGeneration &+= 1
        isFenced = true
        currentUserID = userID
        sessionEndUserID = nil
        binding = nil
        pendingRoute = nil
        pendingRegistrationKey = nil
        try? store.clearBinding()
        if userID == nil {
            deviceToken = nil
            system.unregisterForRemoteNotifications()
        } else if previousUserID == nil {
            // `activateIfNeeded` below asks APNs for a fresh token. Do not reuse a
            // token that was invalidated by an earlier unregister operation.
            deviceToken = nil
        }
        Task { [weak self] in
            guard let self else { return }
            await self.system.removeAllAccountBoundNotifications()
            await Task.yield()
            guard self.auth.session?.cloud?.userID == userID,
                  self.currentUserID == userID else {
                return
            }
            self.isFenced = userID == nil
            if userID != nil { await self.activateIfNeeded() }
        }
    }

    private func fenceAndRevoke(expectedUserID: String?) async {
        lifecycleGeneration &+= 1
        isFenced = true
        binding = nil
        pendingRoute = nil
        pendingRegistrationKey = nil
        try? store.clearBinding()
        deviceToken = nil
        system.unregisterForRemoteNotifications()
        await system.removeAllAccountBoundNotifications()
        guard let installationID, let expectedUserID else { return }
        let task = enqueueBackendOperation { [weak self] in
            guard let self,
                  self.auth.session?.cloud?.userID == expectedUserID else {
                return
            }
            try? await self.backend.revoke(
                installationID: installationID,
                expectedUserID: expectedUserID
            )
        }
        await task.value
    }

    private func enqueueRegistration(token: Data, expectedUserID: String) {
        guard let installationID else { return }
        let tokenHex = token.map { String(format: "%02x", $0) }.joined()
        let digest = Self.tokenDigest(token)
        let generation = lifecycleGeneration
        let key = "\(generation):\(expectedUserID):\(environment.rawValue):\(digest)"
        if pendingRegistrationKey == key { return }
        if let binding,
           binding.userID == expectedUserID,
           binding.environment == environment,
           binding.tokenDigest == digest {
            status = .active
            return
        }
        pendingRegistrationKey = key
        status = .registering
        _ = enqueueBackendOperation { [weak self] in
            guard let self,
                  self.lifecycleGeneration == generation,
                  !self.isFenced,
                  self.isEnabled,
                  self.currentUserID == expectedUserID,
                  self.auth.session?.cloud?.userID == expectedUserID,
                  self.deviceToken == token else {
                if self?.pendingRegistrationKey == key {
                    self?.pendingRegistrationKey = nil
                }
                return
            }
            do {
                let response = try await self.backend.register(
                    installationID: installationID,
                    environment: self.environment,
                    token: tokenHex,
                    locale: self.validLocale,
                    appVersion: self.validAppVersion,
                    expectedUserID: expectedUserID
                )
                guard self.lifecycleGeneration == generation,
                      !self.isFenced,
                      self.isEnabled,
                      self.currentUserID == expectedUserID,
                      self.auth.session?.cloud?.userID == expectedUserID,
                      self.deviceToken == token else {
                    return
                }
                let stored = NativePushBinding(
                    version: NativePushBinding.currentVersion,
                    installationID: installationID,
                    userID: expectedUserID,
                    bindingID: response.bindingID,
                    environment: response.environment,
                    tokenDigest: digest,
                    registrationRevision: response.registrationRevision
                )
                do {
                    try self.store.saveBinding(stored)
                } catch {
                    self.isFenced = true
                    try? await self.backend.revoke(
                        installationID: installationID,
                        expectedUserID: expectedUserID
                    )
                    self.status = .unavailable
                    return
                }
                self.binding = stored
                self.status = .active
            } catch {
                guard self.lifecycleGeneration == generation,
                      self.currentUserID == expectedUserID else {
                    return
                }
                self.status = .failed
            }
            if self.pendingRegistrationKey == key {
                self.pendingRegistrationKey = nil
            }
        }
    }

    private func enqueueBackendOperation(
        _ operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let previous = backendTail
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
        backendTail = task
        return task
    }

    private func localNotification(
        for event: NativePushRemoteEvent
    ) -> NativePushLocalNotification {
        let copy = Self.copy(
            for: event.eventType,
            languageCode: defaults.string(forKey: "app-language")
                ?? AppLanguage.english.rawValue
        )
        let identity = "\(event.eventType.rawValue):\(event.objectID):\(event.objectRevision)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return NativePushLocalNotification(
            identifier: NativePushSystemController.notificationIdentifierPrefix + digest,
            title: copy.title,
            body: copy.body,
            bindingID: event.bindingID,
            destination: event.eventType.destination
        )
    }

    private var validLocale: String? {
        let raw = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        guard raw.utf8.count <= 35,
              raw.range(
                of: "^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8}){0,2}$",
                options: .regularExpression
              ) != nil else {
            return nil
        }
        return raw
    }

    private var validAppVersion: String? {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        value.range(of: "^[A-Za-z0-9._+-]{1,32}$", options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func tokenDigest(_ token: Data) -> String {
        SHA256.hash(data: token).map { String(format: "%02x", $0) }.joined()
    }

    private static func copy(
        for eventType: NativePushRemoteEvent.EventType,
        languageCode: String
    ) -> (title: String, body: String) {
        switch eventType {
        case .friendRequestReceived:
            return (
                gymText("New friend request", "Новий запит у друзі", "Новая заявка в друзья", languageCode: languageCode),
                gymText("Open GymApp to respond.", "Відкрий GymApp, щоб відповісти.", "Открой GymApp, чтобы ответить.", languageCode: languageCode)
            )
        case .friendRequestAccepted:
            return (
                gymText("Friend request accepted", "Запит у друзі прийнято", "Заявка в друзья принята", languageCode: languageCode),
                gymText("Your friend is now in GymApp.", "Друг тепер доступний у GymApp.", "Друг теперь доступен в GymApp.", languageCode: languageCode)
            )
        case .workoutInviteReceived:
            return (
                gymText("Workout invitation", "Запрошення на тренування", "Приглашение на тренировку", languageCode: languageCode),
                gymText("A friend shared a workout with you.", "Друг поділився з тобою тренуванням.", "Друг поделился с тобой тренировкой.", languageCode: languageCode)
            )
        case .workoutInviteAccepted:
            return (
                gymText("Workout accepted", "Тренування прийнято", "Тренировка принята", languageCode: languageCode),
                gymText("Your friend accepted the workout.", "Друг прийняв твоє тренування.", "Друг принял твою тренировку.", languageCode: languageCode)
            )
        case .liveInviteReceived:
            return (
                gymText("Live workout invitation", "Запрошення на спільне тренування", "Приглашение на совместную тренировку", languageCode: languageCode),
                gymText("Open GymApp to join the workout.", "Відкрий GymApp, щоб приєднатися.", "Открой GymApp, чтобы присоединиться.", languageCode: languageCode)
            )
        case .liveInviteAccepted:
            return (
                gymText("Friend joined", "Друг приєднався", "Друг присоединился", languageCode: languageCode),
                gymText("Your live workout is ready.", "Спільне тренування готове до старту.", "Совместная тренировка готова к старту.", languageCode: languageCode)
            )
        case .liveRoomStarted:
            return (
                gymText("Workout started", "Тренування почалося", "Тренировка началась", languageCode: languageCode),
                gymText("Your shared live workout has started.", "Спільне тренування вже розпочато.", "Совместная тренировка уже началась.", languageCode: languageCode)
            )
        case .liveParticipantFinished:
            return (
                gymText("Friend finished", "Друг завершив тренування", "Друг закончил тренировку", languageCode: languageCode),
                gymText("Open GymApp to view the latest state.", "Переглянь актуальний стан у GymApp.", "Посмотри актуальное состояние в GymApp.", languageCode: languageCode)
            )
        case .liveRoomClosed:
            return (
                gymText("Live workout ended", "Спільне тренування завершено", "Совместная тренировка завершена", languageCode: languageCode),
                gymText("Open GymApp to view the latest state.", "Відкрий GymApp, щоб переглянути стан.", "Открой GymApp, чтобы посмотреть состояние.", languageCode: languageCode)
            )
        }
    }
}
