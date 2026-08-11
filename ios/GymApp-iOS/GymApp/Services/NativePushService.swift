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
    case revocationPending
    case failed
}

enum NativePushDestination: String, Equatable, Sendable {
    case social
    case live
}

enum NativePushRouteTarget: Equatable, Sendable {
    case social
    case live(roomID: String?)

    var destination: NativePushDestination {
        switch self {
        case .social: .social
        case .live: .live
        }
    }

    var roomID: String? {
        guard case let .live(roomID) = self else { return nil }
        return roomID
    }
}

struct NativePushRoute: Identifiable, Equatable, Sendable {
    let id: UUID
    let target: NativePushRouteTarget
    let bindingID: UUID
    let lifecycleGeneration: UInt64

    init(
        id: UUID = UUID(),
        target: NativePushRouteTarget,
        bindingID: UUID,
        lifecycleGeneration: UInt64
    ) {
        self.id = id
        self.target = target
        self.bindingID = bindingID
        self.lifecycleGeneration = lifecycleGeneration
    }

    var destination: NativePushDestination { target.destination }
    var roomID: String? { target.roomID }
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

    var deliveryKey: String {
        "\(eventType.destination.rawValue):\(objectID)"
    }

    var routeTarget: NativePushRouteTarget {
        switch eventType.destination {
        case .social: .social
        case .live: .live(roomID: objectID)
        }
    }
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

    static func localTarget(
        from userInfo: [AnyHashable: Any],
        expectedBindingID: UUID
    ) -> NativePushRouteTarget? {
        guard Set(userInfo.keys.compactMap { $0 as? String }) == ["gymappLocal"],
              userInfo.keys.count == 1,
              let payload = stringDictionary(userInfo["gymappLocal"]),
              let version = exactInteger(payload["version"]),
              version == 1 || version == 2,
              let bindingString = boundedString(payload["bindingId"], maximumBytes: 36),
              versionFourUUID(bindingString) == expectedBindingID,
              let destinationString = boundedString(
                payload["destination"],
                maximumBytes: 16
              ),
              let destination = NativePushDestination(rawValue: destinationString) else {
            return nil
        }

        let baseKeys = Set(["version", "bindingId", "destination"])
        if version == 1 {
            guard Set(payload.keys) == baseKeys else { return nil }
            // Notifications delivered before route v2 did not retain a live room ID.
            // Keep their safe generic fallback while all newly scheduled live routes
            // carry the exact opaque room identifier.
            return destination == .social ? .social : .live(roomID: nil)
        }

        switch destination {
        case .social:
            guard Set(payload.keys) == baseKeys else { return nil }
            return .social
        case .live:
            guard Set(payload.keys) == baseKeys.union(["roomId"]),
                  let roomID = boundedString(payload["roomId"], maximumBytes: 35),
                  roomID.range(
                    of: "^lr_[0-9a-f]{32}$",
                    options: .regularExpression
                  ) != nil else {
                return nil
            }
            return .live(roomID: roomID)
        }
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

enum NativePushAuthSessionIdentity {
    private static let maximumTokenBytes = 16 * 1_024

    static func sessionID(from cloud: CloudAccountSession?) -> String? {
        guard let cloud else { return nil }
        return sessionID(fromAccessToken: cloud.accessToken)
    }

    static func sessionID(fromAccessToken token: String) -> String? {
        guard !token.isEmpty,
              token.utf8.prefix(maximumTokenBytes + 1).count <= maximumTokenBytes else {
            return nil
        }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = base64URLData(String(segments[1])),
              payload.count <= 8 * 1_024,
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let rawSessionID = object["session_id"] as? String,
              rawSessionID.utf8.count == 36,
              let sessionID = UUID(uuidString: rawSessionID) else {
            return nil
        }
        return sessionID.uuidString.lowercased()
    }

    private static func base64URLData(_ value: String) -> Data? {
        guard !value.isEmpty,
              value.utf8.count <= 12 * 1_024,
              value.unicodeScalars.allSatisfy({
                  (0x30 ... 0x39).contains($0.value)
                      || (0x41 ... 0x5a).contains($0.value)
                      || (0x61 ... 0x7a).contains($0.value)
                      || $0.value == 0x2d || $0.value == 0x5f
              }) else {
            return nil
        }
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: normalized, options: [])
    }
}

struct NativePushBinding: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let installationID: UUID
    let userID: String
    let authSessionID: String
    let bindingID: UUID
    let environment: NativePushEnvironment
    let tokenDigest: String
    let registrationRevision: Int
    let supersededRevocationBindingID: UUID?
}

/// Version 1 bindings predate auth-session binding. They are decoded only so an
/// authenticated matching owner can revoke the server row, or a new registration can
/// durably prove supersession. A legacy binding is never eligible for local delivery.
struct NativePushLegacyBinding: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let installationID: UUID
    let userID: String
    let bindingID: UUID
    let environment: NativePushEnvironment
    let tokenDigest: String
    let registrationRevision: Int
}

struct NativePushPendingRevocation: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let installationID: UUID
    let userID: String
    let authSessionID: String
    let bindingID: UUID
    let registrationRevision: Int
}

/// Restart-safe proof that an installation may have been registered for this exact
/// account session even when the registration response was fenced before a binding
/// could be stored. Provider tokens never enter this record.
struct NativePushInstallationCleanupIntent: Codable, Equatable, Hashable, Sendable {
    static let currentVersion = 1

    let version: Int
    let installationID: UUID
    let userID: String
    let authSessionID: String
}

private struct NativePushDeliveryRecord: Codable, Equatable, Sendable {
    let key: String
    let revision: Int
}

private struct NativePushDeliveryState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let installationID: UUID
    let userID: String
    let authSessionID: String
    let bindingID: UUID
    var records: [NativePushDeliveryRecord]
}

protocol NativePushBindingStoring {
    func installationID() throws -> UUID
    func loadBinding() throws -> NativePushBinding?
    func loadLegacyBinding() throws -> NativePushLegacyBinding?
    func saveBinding(_ binding: NativePushBinding) throws
    func clearBinding() throws
    func clearBinding(_ expected: NativePushBinding) throws -> Bool
    func clearLegacyBinding(_ expected: NativePushLegacyBinding) throws -> Bool
    func clearDeliveryState() throws
    func loadPendingRevocation() throws -> NativePushPendingRevocation?
    func savePendingRevocation(_ pending: NativePushPendingRevocation) throws
    func clearPendingRevocation(_ expected: NativePushPendingRevocation) throws -> Bool
    func loadInstallationCleanupIntents() throws -> [NativePushInstallationCleanupIntent]
    func saveInstallationCleanupIntent(_ intent: NativePushInstallationCleanupIntent) throws
    func clearInstallationCleanupIntent(
        _ expected: NativePushInstallationCleanupIntent
    ) throws -> Bool
    func canDisplay(_ event: NativePushRemoteEvent, binding: NativePushBinding) throws -> Bool
    func commitDisplayed(_ event: NativePushRemoteEvent, binding: NativePushBinding) throws -> Bool
}

struct NativePushBindingStore: NativePushBindingStoring {
    private let keychain: KeychainStoring
    private let installationAccount = "native-push-installation-v1"
    private let bindingAccount = "native-push-binding-v1"
    private let pendingRevocationAccount = "native-push-pending-revocation-v1"
    private let installationCleanupAccount = "native-push-installation-cleanup-v1"
    private let deliveryStateAccount = "native-push-delivery-state-v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let maximumBindingBytes = 2 * 1_024
    private static let maximumPendingRevocationBytes = 2 * 1_024
    private static let maximumInstallationCleanupBytes = 8 * 1_024
    private static let maximumInstallationCleanupIntents = 8
    private static let maximumDeliveryStateBytes = 32 * 1_024
    private static let maximumDeliveryRecords = 128

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
        guard data.count <= Self.maximumBindingBytes else {
            try clearBinding()
            return nil
        }
        if let binding = try? decoder.decode(NativePushBinding.self, from: data),
           Self.isValid(binding) {
            return binding
        }
        if let legacy = try? decoder.decode(NativePushLegacyBinding.self, from: data),
           Self.isValid(legacy) {
            return nil
        }
        try clearBinding()
        return nil
    }

    func loadLegacyBinding() throws -> NativePushLegacyBinding? {
        guard let data = try keychain.read(account: bindingAccount),
              data.count <= Self.maximumBindingBytes,
              let legacy = try? decoder.decode(NativePushLegacyBinding.self, from: data),
              Self.isValid(legacy) else {
            return nil
        }
        return legacy
    }

    func saveBinding(_ binding: NativePushBinding) throws {
        guard Self.isValid(binding) else {
            throw NativePushError.invalidState
        }
        let data = try encoder.encode(binding)
        guard data.count <= Self.maximumBindingBytes else { throw NativePushError.invalidState }
        try keychain.save(data, account: bindingAccount)
    }

    func clearBinding() throws {
        var firstError: Error?
        do {
            try keychain.delete(account: bindingAccount)
        } catch {
            firstError = error
        }
        do {
            try keychain.delete(account: deliveryStateAccount)
        } catch {
            if firstError == nil { firstError = error }
        }
        if let firstError { throw firstError }
    }

    func clearBinding(_ expected: NativePushBinding) throws -> Bool {
        guard let current = try loadBinding() else { return true }
        guard current == expected else { return false }
        try clearBinding()
        return true
    }

    func clearLegacyBinding(_ expected: NativePushLegacyBinding) throws -> Bool {
        guard let data = try keychain.read(account: bindingAccount) else { return true }
        guard data.count <= Self.maximumBindingBytes,
              let current = try? decoder.decode(NativePushLegacyBinding.self, from: data),
              Self.isValid(current),
              current == expected else {
            return false
        }
        try clearBinding()
        return true
    }

    func clearDeliveryState() throws {
        try keychain.delete(account: deliveryStateAccount)
    }

    func loadPendingRevocation() throws -> NativePushPendingRevocation? {
        guard let data = try keychain.read(account: pendingRevocationAccount) else { return nil }
        guard data.count <= Self.maximumPendingRevocationBytes,
              let pending = try? decoder.decode(NativePushPendingRevocation.self, from: data),
              Self.isValid(pending) else {
            try keychain.delete(account: pendingRevocationAccount)
            return nil
        }
        return pending
    }

    func savePendingRevocation(_ pending: NativePushPendingRevocation) throws {
        guard Self.isValid(pending) else { throw NativePushError.invalidState }
        let data = try encoder.encode(pending)
        guard data.count <= Self.maximumPendingRevocationBytes else {
            throw NativePushError.invalidState
        }
        try keychain.save(data, account: pendingRevocationAccount)
    }

    func clearPendingRevocation(_ expected: NativePushPendingRevocation) throws -> Bool {
        guard let current = try loadPendingRevocation() else { return true }
        guard current == expected else { return false }
        try keychain.delete(account: pendingRevocationAccount)
        return true
    }

    func loadInstallationCleanupIntents() throws -> [NativePushInstallationCleanupIntent] {
        guard let data = try keychain.read(account: installationCleanupAccount) else { return [] }
        guard data.count <= Self.maximumInstallationCleanupBytes,
              let intents = try? decoder.decode(
                  [NativePushInstallationCleanupIntent].self,
                  from: data
              ),
              intents.count <= Self.maximumInstallationCleanupIntents,
              Set(intents).count == intents.count,
              intents.allSatisfy(Self.isValid) else {
            throw NativePushError.invalidState
        }
        return intents
    }

    func saveInstallationCleanupIntent(
        _ intent: NativePushInstallationCleanupIntent
    ) throws {
        guard Self.isValid(intent) else { throw NativePushError.invalidState }
        var intents = try loadInstallationCleanupIntents()
        if !intents.contains(intent) {
            guard intents.count < Self.maximumInstallationCleanupIntents else {
                throw NativePushError.invalidState
            }
            intents.append(intent)
        }
        try saveInstallationCleanupIntents(intents)
    }

    func clearInstallationCleanupIntent(
        _ expected: NativePushInstallationCleanupIntent
    ) throws -> Bool {
        var intents = try loadInstallationCleanupIntents()
        guard let index = intents.firstIndex(of: expected) else { return true }
        intents.remove(at: index)
        if intents.isEmpty {
            try keychain.delete(account: installationCleanupAccount)
        } else {
            try saveInstallationCleanupIntents(intents)
        }
        return true
    }

    private func saveInstallationCleanupIntents(
        _ intents: [NativePushInstallationCleanupIntent]
    ) throws {
        guard !intents.isEmpty,
              intents.count <= Self.maximumInstallationCleanupIntents,
              Set(intents).count == intents.count,
              intents.allSatisfy(Self.isValid) else {
            throw NativePushError.invalidState
        }
        let data = try encoder.encode(intents)
        guard data.count <= Self.maximumInstallationCleanupBytes else {
            throw NativePushError.invalidState
        }
        try keychain.save(data, account: installationCleanupAccount)
    }

    func canDisplay(
        _ event: NativePushRemoteEvent,
        binding: NativePushBinding
    ) throws -> Bool {
        guard Self.isValid(binding), event.bindingID == binding.bindingID else { return false }
        let state = try deliveryState(for: binding)
        guard let currentRevision = state.records.first(where: {
            $0.key == event.deliveryKey
        })?.revision else {
            return true
        }
        return event.objectRevision > currentRevision
    }

    func commitDisplayed(
        _ event: NativePushRemoteEvent,
        binding: NativePushBinding
    ) throws -> Bool {
        guard Self.isValid(binding), event.bindingID == binding.bindingID else { return false }
        var state = try deliveryState(for: binding)
        if let current = state.records.first(where: { $0.key == event.deliveryKey }),
           event.objectRevision <= current.revision {
            return false
        }
        state.records.removeAll { $0.key == event.deliveryKey }
        state.records.append(
            NativePushDeliveryRecord(key: event.deliveryKey, revision: event.objectRevision)
        )
        if state.records.count > Self.maximumDeliveryRecords {
            state.records.removeFirst(state.records.count - Self.maximumDeliveryRecords)
        }
        try saveDeliveryState(state)
        return true
    }

    private func deliveryState(for binding: NativePushBinding) throws -> NativePushDeliveryState {
        let empty = NativePushDeliveryState(
            version: NativePushDeliveryState.currentVersion,
            installationID: binding.installationID,
            userID: binding.userID,
            authSessionID: binding.authSessionID,
            bindingID: binding.bindingID,
            records: []
        )
        guard let data = try keychain.read(account: deliveryStateAccount) else { return empty }
        guard data.count <= Self.maximumDeliveryStateBytes,
              let state = try? decoder.decode(NativePushDeliveryState.self, from: data),
              Self.isValid(state) else {
            try keychain.delete(account: deliveryStateAccount)
            throw NativePushError.invalidState
        }
        guard state.installationID == binding.installationID,
              state.userID == binding.userID,
              state.authSessionID == binding.authSessionID,
              state.bindingID == binding.bindingID else {
            try keychain.delete(account: deliveryStateAccount)
            return empty
        }
        return state
    }

    private func saveDeliveryState(_ state: NativePushDeliveryState) throws {
        guard Self.isValid(state) else { throw NativePushError.invalidState }
        let data = try encoder.encode(state)
        guard data.count <= Self.maximumDeliveryStateBytes else {
            throw NativePushError.invalidState
        }
        try keychain.save(data, account: deliveryStateAccount)
    }

    private static func isValid(_ binding: NativePushBinding) -> Bool {
        binding.version == NativePushBinding.currentVersion
            && isVersionFourUUID(binding.installationID)
            && canonicalUUID(binding.userID) != nil
            && canonicalUUID(binding.authSessionID) != nil
            && isVersionFourUUID(binding.bindingID)
            && binding.tokenDigest.range(
                of: "^[0-9a-f]{64}$",
                options: .regularExpression
            ) != nil
            && (1 ... 2_147_483_647).contains(binding.registrationRevision)
            && (binding.supersededRevocationBindingID.map {
                isVersionFourUUID($0) && $0 != binding.bindingID
            } ?? true)
    }

    private static func isValid(_ binding: NativePushLegacyBinding) -> Bool {
        binding.version == NativePushLegacyBinding.currentVersion
            && binding.userID.utf8.count == 36
            && UUID(uuidString: binding.userID) != nil
            && binding.tokenDigest.range(
                of: "^[0-9a-f]{64}$",
                options: .regularExpression
            ) != nil
            && (1 ... 2_147_483_647).contains(binding.registrationRevision)
    }

    private static func isValid(_ pending: NativePushPendingRevocation) -> Bool {
        pending.version == NativePushPendingRevocation.currentVersion
            && isVersionFourUUID(pending.installationID)
            && canonicalUUID(pending.userID) != nil
            && canonicalUUID(pending.authSessionID) != nil
            && isVersionFourUUID(pending.bindingID)
            && (1 ... 2_147_483_647).contains(pending.registrationRevision)
    }

    private static func isValid(_ intent: NativePushInstallationCleanupIntent) -> Bool {
        intent.version == NativePushInstallationCleanupIntent.currentVersion
            && isVersionFourUUID(intent.installationID)
            && canonicalUUID(intent.userID) != nil
            && canonicalUUID(intent.authSessionID) != nil
    }

    private static func isValid(_ state: NativePushDeliveryState) -> Bool {
        guard state.version == NativePushDeliveryState.currentVersion,
              isVersionFourUUID(state.installationID),
              canonicalUUID(state.userID) != nil,
              canonicalUUID(state.authSessionID) != nil,
              isVersionFourUUID(state.bindingID),
              state.records.count <= maximumDeliveryRecords else {
            return false
        }
        var keys = Set<String>()
        return state.records.allSatisfy { record in
            keys.insert(record.key).inserted
                && isValidDeliveryKey(record.key)
                && (0 ... 2_147_483_647).contains(record.revision)
        }
    }

    private static func canonicalUUID(_ value: String) -> UUID? {
        guard value.utf8.count == 36,
              value == value.lowercased(),
              let uuid = UUID(uuidString: value),
              uuid.uuidString.lowercased() == value else {
            return nil
        }
        return uuid
    }

    private static func isVersionFourUUID(_ uuid: UUID) -> Bool {
        uuid.uuidString.lowercased().range(
            of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
            options: .regularExpression
        ) != nil
    }

    private static func isValidDeliveryKey(_ key: String) -> Bool {
        guard key.utf8.count <= 42,
              let separator = key.firstIndex(of: ":"),
              let destination = NativePushDestination(
                rawValue: String(key[..<separator])
              ) else {
            return false
        }
        let objectID = String(key[key.index(after: separator)...])
        switch destination {
        case .live:
            return objectID.range(
                of: "^lr_[0-9a-f]{32}$",
                options: .regularExpression
            ) != nil
        case .social:
            return objectID.range(
                of: "^(f|wi)_[0-9a-f]{32}$",
                options: .regularExpression
            ) != nil
        }
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

    func revoke(installationID: UUID, expectedUserID: String) async throws -> Bool
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

    func revoke(installationID: UUID, expectedUserID: String) async throws -> Bool {
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
              let revoked = Self.exactBoolean(object["revoked"]) else {
            throw NativePushError.invalidResponse
        }
        return revoked
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

    private static func exactBoolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }
}

struct NativePushLocalNotification: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let bindingID: UUID
    let target: NativePushRouteTarget

    var destination: NativePushDestination { target.destination }
    var roomID: String? { target.roomID }
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
        content.userInfo = Self.localUserInfo(for: notification)
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

    static func localUserInfo(
        for notification: NativePushLocalNotification
    ) -> [AnyHashable: Any] {
        var routePayload: [String: Any] = [
            "version": 2,
            "bindingId": notification.bindingID.uuidString.lowercased(),
            "destination": notification.destination.rawValue
        ]
        if let roomID = notification.roomID {
            routePayload["roomId"] = roomID
        }
        return ["gymappLocal": routePayload]
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
    private var pendingRevocation: NativePushPendingRevocation?
    private var installationCleanupIntents: [NativePushInstallationCleanupIntent] = []
    private var legacyRevocationSource: NativePushLegacyBinding?
    private var deviceToken: Data?
    private var currentUserID: String?
    private var currentAuthSessionID: String?
    private var lifecycleGeneration: UInt64 = 0
    private var isFenced = true
    private var sessionEndUserID: String?
    private var authSubscription: AnyCancellable?
    private var backendTail: Task<Void, Never>?
    private var lifecycleTail: Task<Void, Never>?
    private var lifecycleCleanupPending = false
    private var deliveryTail: Task<NativePushFetchOutcome, Never>?
    private var deliverySequence: UInt64 = 0
    private var pendingRegistrationKey: String?

    private static let enabledDefaultsKey = "gymapp.native-push.enabled.v1"
    private static let revocationFenceBindingDefaultsKey =
        "gymapp.native-push.revocation-fence-binding.v1"
    private static let maximumInstallationCleanupIntents = 8

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
        let initialCloud = auth.session?.cloud
        self.currentUserID = initialCloud?.userID
        self.currentAuthSessionID = NativePushAuthSessionIdentity.sessionID(from: initialCloud)

        do {
            let installationID = try store.installationID()
            self.installationID = installationID
            var pending = try store.loadPendingRevocation()
            let installationCleanupIntents = try store.loadInstallationCleanupIntents()
            self.installationCleanupIntents = installationCleanupIntents
            let stored = try store.loadBinding()
            let legacy = stored == nil ? try store.loadLegacyBinding() : nil
            var fenceBindingID = try revocationFenceBindingID()
            var storageUnavailable = false
            if let pending, pending.installationID != installationID {
                throw NativePushError.invalidState
            }
            if installationCleanupIntents.contains(where: {
                $0.installationID != installationID
            }) {
                throw NativePushError.invalidState
            }
            if let stored, stored.installationID != installationID {
                throw NativePushError.invalidState
            }
            if let legacy, legacy.installationID != installationID {
                throw NativePushError.invalidState
            }
            // A valid pending v2 marker is the authoritative cleanup source when a
            // replacement registration was accepted but deleting the superseded v1
            // record failed. The legacy record must never be reactivated in this mixed
            // restart state; the pending branch below keeps delivery disarmed until the
            // replacement is revoked or safely superseded.

            if let pendingValue = pending,
               let stored,
               Self.provesSupersession(stored, of: pendingValue) {
                guard try store.clearPendingRevocation(pendingValue) else {
                    throw NativePushError.invalidState
                }
                pending = nil
                guard clearRevocationFence() else { throw NativePushError.invalidState }
                fenceBindingID = nil
            } else if pending == nil,
                      let stored,
                      let fencedBindingID = fenceBindingID,
                      stored.supersededRevocationBindingID == fencedBindingID {
                guard clearRevocationFence() else { throw NativePushError.invalidState }
                fenceBindingID = nil
            }

            if let pending {
                pendingRevocation = pending
                binding = nil
                if fenceBindingID != pending.bindingID {
                    if persistRevocationFence(bindingID: pending.bindingID) {
                        fenceBindingID = pending.bindingID
                    } else {
                        storageUnavailable = true
                    }
                }
                do {
                    try store.clearDeliveryState()
                } catch {
                    storageUnavailable = true
                }
            } else if let stored {
                let matchesCurrentOwner = stored.userID == currentUserID
                    && stored.authSessionID == currentAuthSessionID
                    && stored.environment == environment
                if !installationCleanupIntents.isEmpty {
                    binding = nil
                    do {
                        try store.clearDeliveryState()
                    } catch {
                        storageUnavailable = true
                    }
                } else if !isEnabled || fenceBindingID != nil || !matchesCurrentOwner {
                    let recovered = Self.pendingRevocation(for: stored)
                    pendingRevocation = recovered
                    binding = nil
                    if !persistRevocationFence(bindingID: stored.bindingID) {
                        storageUnavailable = true
                    }
                    do {
                        try store.savePendingRevocation(recovered)
                    } catch {
                        // The fenced binding itself remains the durable revoke source.
                        storageUnavailable = true
                    }
                    do {
                        try store.clearDeliveryState()
                    } catch {
                        storageUnavailable = true
                    }
                } else {
                    binding = stored
                }
            } else if let legacy {
                guard fenceBindingID == nil || fenceBindingID == legacy.bindingID else {
                    throw NativePushError.invalidState
                }
                legacyRevocationSource = legacy
                binding = nil
                if !persistRevocationFence(bindingID: legacy.bindingID) {
                    storageUnavailable = true
                }
                do {
                    try store.clearDeliveryState()
                } catch {
                    storageUnavailable = true
                }
            } else if fenceBindingID != nil, installationCleanupIntents.isEmpty {
                // UserDefaults can be restored while this-device-only Keychain records
                // cannot. With no durable source, the opaque fence cannot authorize a
                // revoke and must not permanently brick future registration.
                guard clearRevocationFence() else { throw NativePushError.invalidState }
                fenceBindingID = nil
                do {
                    try store.clearDeliveryState()
                } catch {
                    storageUnavailable = true
                }
            }
            isFenced = currentUserID == nil
                || currentAuthSessionID == nil
                || !installationCleanupIntents.isEmpty
            if storageUnavailable {
                status = .unavailable
            } else if !installationCleanupIntents.isEmpty
                        || pendingRevocation?.userID == currentUserID
                        || legacyRevocationSource.map({
                            Self.sameUserID($0.userID, currentUserID)
                        }) == true {
                status = .revocationPending
            } else if isFenced && currentUserID != nil {
                status = .unavailable
            } else {
                status = isEnabled && binding != nil && !isFenced ? .active : .disabled
            }
        } catch {
            installationID = nil
            binding = nil
            pendingRevocation = nil
            installationCleanupIntents = []
            legacyRevocationSource = nil
            isFenced = true
            status = .unavailable
        }

        self.system.configure()
        authSubscription = auth.$session.sink { [weak self] session in
            self?.authSessionWillChange(to: session?.cloud)
        }
    }

    private static func pendingRevocation(
        for binding: NativePushBinding
    ) -> NativePushPendingRevocation {
        NativePushPendingRevocation(
            version: NativePushPendingRevocation.currentVersion,
            installationID: binding.installationID,
            userID: binding.userID,
            authSessionID: binding.authSessionID,
            bindingID: binding.bindingID,
            registrationRevision: binding.registrationRevision
        )
    }

    private static func installationCleanupIntent(
        installationID: UUID,
        userID: String,
        authSessionID: String
    ) -> NativePushInstallationCleanupIntent {
        NativePushInstallationCleanupIntent(
            version: NativePushInstallationCleanupIntent.currentVersion,
            installationID: installationID,
            userID: userID,
            authSessionID: authSessionID
        )
    }

    private static func provesSupersession(
        _ binding: NativePushBinding,
        of pending: NativePushPendingRevocation
    ) -> Bool {
        guard binding.installationID == pending.installationID,
              binding.supersededRevocationBindingID == pending.bindingID else {
            return false
        }
        return binding.userID != pending.userID
            || binding.registrationRevision > pending.registrationRevision
    }

    private static func provesSupersession(
        _ binding: NativePushBinding,
        of legacy: NativePushLegacyBinding
    ) -> Bool {
        guard binding.installationID == legacy.installationID,
              binding.supersededRevocationBindingID == legacy.bindingID else {
            return false
        }
        return !sameUserID(binding.userID, legacy.userID)
            || binding.registrationRevision > legacy.registrationRevision
    }

    private static func sameUserID(_ lhs: String, _ rhs: String?) -> Bool {
        guard let rhs,
              lhs.utf8.count == 36,
              rhs.utf8.count == 36,
              let left = UUID(uuidString: lhs),
              let right = UUID(uuidString: rhs) else {
            return false
        }
        return left == right
    }

    private static func binding(
        _ binding: NativePushBinding,
        matches intent: NativePushInstallationCleanupIntent
    ) -> Bool {
        binding.installationID == intent.installationID
            && binding.userID == intent.userID
            && binding.authSessionID == intent.authSessionID
    }

    private static func binding(
        _ binding: NativePushBinding,
        matches pending: NativePushPendingRevocation
    ) -> Bool {
        binding.installationID == pending.installationID
            && binding.userID == pending.userID
            && binding.authSessionID == pending.authSessionID
            && binding.bindingID == pending.bindingID
    }

    private func clearRevocationFenceIfNoDurableSources() throws {
        let storedBinding = try store.loadBinding()
        let storedLegacy = storedBinding == nil ? try store.loadLegacyBinding() : nil
        guard storedBinding == nil,
              storedLegacy == nil,
              try store.loadPendingRevocation() == nil,
              try store.loadInstallationCleanupIntents().isEmpty else {
            return
        }
        guard clearRevocationFence() else { throw NativePushError.invalidState }
    }

    private func revocationFenceBindingID() throws -> UUID? {
        guard let raw = defaults.string(
            forKey: Self.revocationFenceBindingDefaultsKey
        ) else {
            return nil
        }
        guard raw.utf8.count == 36,
              raw == raw.lowercased(),
              raw.range(
                of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
                options: .regularExpression
              ) != nil,
              let bindingID = UUID(uuidString: raw) else {
            throw NativePushError.invalidState
        }
        return bindingID
    }

    @discardableResult
    private func persistRevocationFence(bindingID: UUID) -> Bool {
        let raw = bindingID.uuidString.lowercased()
        defaults.set(raw, forKey: Self.revocationFenceBindingDefaultsKey)
        return defaults.string(forKey: Self.revocationFenceBindingDefaultsKey) == raw
    }

    @discardableResult
    private func clearRevocationFence() -> Bool {
        defaults.removeObject(forKey: Self.revocationFenceBindingDefaultsKey)
        return defaults.object(forKey: Self.revocationFenceBindingDefaultsKey) == nil
    }

    deinit {
        backendTail?.cancel()
        lifecycleTail?.cancel()
        deliveryTail?.cancel()
    }

    func activateIfNeeded() async {
        guard !lifecycleCleanupPending,
              installationID != nil,
              let cloud = auth.session?.cloud,
              let authSessionID = NativePushAuthSessionIdentity.sessionID(from: cloud) else {
            if installationID == nil { status = .unavailable }
            return
        }
        let userID = cloud.userID
        guard currentUserID == userID,
              currentAuthSessionID == authSessionID,
              sessionEndUserID != userID else {
            return
        }
        guard await retryInstallationCleanupIntentsIfPossible(
            expectedUserID: userID,
            expectedAuthSessionID: authSessionID
        ) else {
            status = .revocationPending
            return
        }
        guard await retryPendingRevocationIfPossible(
            expectedUserID: userID,
            expectedAuthSessionID: authSessionID
        ) else {
            status = .revocationPending
            return
        }
        guard await retryLegacyRevocationIfPossible(
            expectedUserID: userID,
            expectedAuthSessionID: authSessionID
        ) else {
            status = .revocationPending
            return
        }
        guard ensureForeignRevocationSourceIsDurable(expectedUserID: userID) else {
            isFenced = true
            status = .unavailable
            return
        }
        guard ensureInstallationCleanupIntentsAreDurable(
            expectedUserID: userID,
            expectedAuthSessionID: authSessionID
        ) else {
            isFenced = true
            status = .unavailable
            return
        }
        guard currentUserID == userID,
              currentAuthSessionID == authSessionID,
              authIdentityMatches(userID: userID, authSessionID: authSessionID) else {
            return
        }
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
            enqueueRegistration(
                token: deviceToken,
                expectedUserID: userID,
                expectedAuthSessionID: authSessionID
            )
        }
    }

    func enable() async {
        guard installationID != nil,
              NativePushAuthSessionIdentity.sessionID(from: auth.session?.cloud) != nil else {
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
        status = installationCleanupIntents.isEmpty
            && pendingRevocation == nil
            && legacyRevocationSource == nil
            ? (permissionState == .denied ? .denied : .disabled)
            : .revocationPending
    }

    /// Called before logout/account deletion while the caller still owns a valid token.
    /// The local fence is immediate. A durable marker survives a transport failure so the
    /// idempotent server revoke can be retried without retaining any provider token.
    func prepareForSessionEnd(expectedUserID: String) async {
        guard auth.session?.cloud?.userID == expectedUserID else { return }
        sessionEndUserID = expectedUserID
        await fenceAndRevoke(expectedUserID: expectedUserID)
    }

    func resumeAfterFailedSessionEnd(expectedUserID: String) async {
        guard let cloud = auth.session?.cloud,
              cloud.userID == expectedUserID,
              let authSessionID = NativePushAuthSessionIdentity.sessionID(from: cloud),
              currentUserID == expectedUserID,
              currentAuthSessionID == authSessionID else {
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
              let cloud = auth.session?.cloud,
              let authSessionID = NativePushAuthSessionIdentity.sessionID(from: cloud),
              cloud.userID == currentUserID,
              authSessionID == currentAuthSessionID else {
            return
        }
        enqueueRegistration(
            token: token,
            expectedUserID: cloud.userID,
            expectedAuthSessionID: authSessionID
        )
    }

    func didFailToRegisterForRemoteNotifications() {
        guard isEnabled else { return }
        status = .failed
    }

    func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) async -> NativePushFetchOutcome {
        let previous = deliveryTail
        deliverySequence &+= 1
        let sequence = deliverySequence
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard !Task.isCancelled, let self else { return NativePushFetchOutcome.noData }
            return await self.handleRemoteNotificationSerial(userInfo)
        }
        deliveryTail = task
        let outcome = await task.value
        if deliverySequence == sequence {
            deliveryTail = nil
        }
        return outcome
    }

    private func handleRemoteNotificationSerial(
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
              binding.authSessionID == currentAuthSessionID,
              authIdentityMatches(
                userID: binding.userID,
                authSessionID: binding.authSessionID
              ) else {
            return .noData
        }
        do {
            guard try store.canDisplay(event, binding: binding) else { return .noData }
        } catch {
            return .failed
        }
        let generation = lifecycleGeneration
        let local = localNotification(for: event, binding: binding)
        do {
            try await system.schedule(local)
        } catch {
            return .failed
        }
        guard lifecycleGeneration == generation,
              !isFenced,
              self.binding == binding,
              currentAuthSessionID == binding.authSessionID,
              authIdentityMatches(
                userID: binding.userID,
                authSessionID: binding.authSessionID
              ) else {
            await system.removeNotification(identifier: local.identifier)
            return .noData
        }
        do {
            guard try store.commitDisplayed(event, binding: binding) else {
                await system.removeNotification(identifier: local.identifier)
                return .noData
            }
        } catch {
            await system.removeNotification(identifier: local.identifier)
            return .failed
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
              binding.authSessionID == currentAuthSessionID,
              authIdentityMatches(
                userID: binding.userID,
                authSessionID: binding.authSessionID
              ),
              let target = NativePushPayloadParser.localTarget(
                from: userInfo,
                expectedBindingID: binding.bindingID
              ) else {
            return
        }
        pendingRoute = NativePushRoute(
            target: target,
            bindingID: binding.bindingID,
            lifecycleGeneration: lifecycleGeneration
        )
    }

    func consumePendingRoute() -> NativePushRoute? {
        guard let route = pendingRoute,
              isRouteBoundToCurrentSession(route) else {
            pendingRoute = nil
            return nil
        }
        pendingRoute = nil
        return route
    }

    func isRouteBoundToCurrentSession(_ route: NativePushRoute) -> Bool {
        guard !isFenced,
              route.lifecycleGeneration == lifecycleGeneration,
              let binding,
              route.bindingID == binding.bindingID,
              binding.userID == currentUserID,
              binding.authSessionID == currentAuthSessionID else {
            return false
        }
        return authIdentityMatches(
            userID: binding.userID,
            authSessionID: binding.authSessionID
        )
    }

    private func authSessionWillChange(to cloud: CloudAccountSession?) {
        let userID = cloud?.userID
        let authSessionID = NativePushAuthSessionIdentity.sessionID(from: cloud)
        guard userID != currentUserID || authSessionID != currentAuthSessionID else { return }
        let previousUserID = currentUserID
        let previousAuthSessionID = currentAuthSessionID
        let hasPossiblePreviousRegistration = pendingRegistrationKey != nil
            || binding.map({
                $0.userID == previousUserID && $0.authSessionID == previousAuthSessionID
            }) == true
            || pendingRevocation.map({
                $0.userID == previousUserID && $0.authSessionID == previousAuthSessionID
            }) == true
            || legacyRevocationSource.map({
                Self.sameUserID($0.userID, previousUserID)
            }) == true
        if hasPossiblePreviousRegistration,
           let previousUserID,
           let previousAuthSessionID {
            _ = prepareInstallationCleanupIntent(
                expectedUserID: previousUserID,
                expectedAuthSessionID: previousAuthSessionID
            )
        }
        if let binding {
            _ = persistPendingRevocation(for: binding)
        }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        lifecycleCleanupPending = true
        deliveryTail?.cancel()
        isFenced = true
        currentUserID = userID
        currentAuthSessionID = authSessionID
        sessionEndUserID = nil
        binding = nil
        pendingRoute = nil
        pendingRegistrationKey = nil
        do {
            try store.clearDeliveryState()
        } catch {
            status = .unavailable
        }
        if userID == nil {
            deviceToken = nil
            system.unregisterForRemoteNotifications()
        } else if previousUserID == nil {
            // `activateIfNeeded` below asks APNs for a fresh token. Do not reuse a
            // token that was invalidated by an earlier unregister operation.
            deviceToken = nil
        }
        enqueueLifecycleCleanup(
            generation: generation,
            expectedUserID: userID,
            expectedAuthSessionID: authSessionID,
            reactivate: true
        )
    }

    private func fenceAndRevoke(expectedUserID: String?) async {
        let expectedAuthSessionID = currentAuthSessionID
        let hasPossibleRegistration = pendingRegistrationKey != nil
            || binding.map({
                expectedUserID == nil || $0.userID == expectedUserID
            }) == true
            || pendingRevocation.map({
                expectedUserID == nil || $0.userID == expectedUserID
            }) == true
            || legacyRevocationSource.map({
                expectedUserID == nil || Self.sameUserID($0.userID, expectedUserID)
            }) == true
        let installationCleanupIntent: NativePushInstallationCleanupIntent?
        if hasPossibleRegistration,
           let expectedUserID,
           let expectedAuthSessionID,
           currentUserID == expectedUserID {
            installationCleanupIntent = prepareInstallationCleanupIntent(
                expectedUserID: expectedUserID,
                expectedAuthSessionID: expectedAuthSessionID
            )
        } else {
            installationCleanupIntent = nil
        }
        if let binding,
           expectedUserID == nil || binding.userID == expectedUserID {
            _ = persistPendingRevocation(for: binding)
        }
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        lifecycleCleanupPending = true
        deliveryTail?.cancel()
        isFenced = true
        binding = nil
        pendingRoute = nil
        pendingRegistrationKey = nil
        do {
            try store.clearDeliveryState()
        } catch {
            status = .unavailable
        }
        deviceToken = nil
        system.unregisterForRemoteNotifications()
        let cleanup = enqueueLifecycleCleanup(
            generation: generation,
            expectedUserID: currentUserID,
            expectedAuthSessionID: expectedAuthSessionID,
            reactivate: false
        )
        let serverCleanup = installationCleanupIntent.map {
            enqueueInstallationCleanup($0)
        }
        await cleanup.value
        await serverCleanup?.value
        guard lifecycleGeneration == generation else { return }
        if let installationCleanupIntent,
           installationCleanupIntents.contains(installationCleanupIntent) {
            return
        }
        guard let expectedUserID,
              let authSessionID = expectedAuthSessionID,
              currentAuthSessionID == authSessionID,
              authIdentityMatches(
                userID: expectedUserID,
                authSessionID: authSessionID
              ) else {
            return
        }
        guard await retryPendingRevocationIfPossible(
            expectedUserID: expectedUserID,
            expectedAuthSessionID: authSessionID
        ) else {
            return
        }
        _ = await retryLegacyRevocationIfPossible(
            expectedUserID: expectedUserID,
            expectedAuthSessionID: authSessionID
        )
    }

    @discardableResult
    private func enqueueLifecycleCleanup(
        generation: UInt64,
        expectedUserID: String?,
        expectedAuthSessionID: String?,
        reactivate: Bool
    ) -> Task<Void, Never> {
        let previous = lifecycleTail
        let task = Task { @MainActor [weak self] in
            _ = await previous?.value
            guard !Task.isCancelled,
                  let self,
                  self.lifecycleGeneration == generation,
                  self.currentUserID == expectedUserID,
                  self.currentAuthSessionID == expectedAuthSessionID else {
                return
            }
            await self.system.removeAllAccountBoundNotifications()
            guard self.lifecycleGeneration == generation,
                  self.currentUserID == expectedUserID,
                  self.currentAuthSessionID == expectedAuthSessionID else {
                return
            }
            self.lifecycleCleanupPending = false
            guard reactivate else { return }
            self.isFenced = expectedUserID == nil || expectedAuthSessionID == nil
            if expectedUserID != nil, expectedAuthSessionID != nil {
                await self.activateIfNeeded()
            } else if expectedUserID != nil {
                self.status = .unavailable
            }
        }
        lifecycleTail = task
        return task
    }

    private func persistPendingRevocation(for binding: NativePushBinding) -> Bool {
        let pending = Self.pendingRevocation(for: binding)
        guard pendingRevocation == nil || pendingRevocation == pending else {
            status = .unavailable
            return false
        }
        pendingRevocation = pending
        guard persistRevocationFence(bindingID: binding.bindingID) else {
            status = .unavailable
            return false
        }
        do {
            try store.savePendingRevocation(pending)
            guard try store.loadPendingRevocation() == pending else {
                status = .unavailable
                return false
            }
            return true
        } catch {
            status = .unavailable
            return false
        }
    }

    /// Persists a provider-token-free cleanup source before delivery is fenced. The
    /// returned value is also queued for an immediate best-effort revoke when a write
    /// fails, while the manager remains unavailable rather than rearming delivery.
    private func prepareInstallationCleanupIntent(
        expectedUserID: String,
        expectedAuthSessionID: String
    ) -> NativePushInstallationCleanupIntent? {
        guard let installationID else {
            status = .unavailable
            return nil
        }
        let intent = Self.installationCleanupIntent(
            installationID: installationID,
            userID: expectedUserID,
            authSessionID: expectedAuthSessionID
        )
        do {
            try store.saveInstallationCleanupIntent(intent)
            let durable = try store.loadInstallationCleanupIntents()
            guard durable.contains(intent),
                  durable.allSatisfy({ $0.installationID == installationID }) else {
                throw NativePushError.invalidState
            }
            installationCleanupIntents = durable
        } catch {
            if !installationCleanupIntents.contains(intent),
               installationCleanupIntents.count < Self.maximumInstallationCleanupIntents {
                installationCleanupIntents.append(intent)
            }
            status = .unavailable
        }
        return intent
    }

    /// Re-commit every unresolved foreign-owner intent before a replacement account
    /// is allowed to contact registration. A successful replacement can then clear
    /// only the exact snapshot it durably superseded.
    private func ensureInstallationCleanupIntentsAreDurable(
        expectedUserID: String,
        expectedAuthSessionID: String
    ) -> Bool {
        guard !installationCleanupIntents.contains(where: {
            $0.userID == expectedUserID && $0.authSessionID == expectedAuthSessionID
        }) else {
            return false
        }
        do {
            for intent in installationCleanupIntents {
                try store.saveInstallationCleanupIntent(intent)
            }
            let durable = try store.loadInstallationCleanupIntents()
            guard Set(installationCleanupIntents).isSubset(of: Set(durable)),
                  durable.allSatisfy({ $0.installationID == installationID }) else {
                throw NativePushError.invalidState
            }
            installationCleanupIntents = durable
            return true
        } catch {
            status = .unavailable
            return false
        }
    }

    /// A different account can replace a server binding only after the previous
    /// owner's cleanup source is known to survive a process restart. Rewriting and
    /// reading the marker back avoids treating an in-memory value from a failed
    /// Keychain write as durable proof.
    private func ensureForeignRevocationSourceIsDurable(expectedUserID: String) -> Bool {
        if let pending = pendingRevocation, pending.userID != expectedUserID {
            do {
                try store.savePendingRevocation(pending)
                guard try store.loadPendingRevocation() == pending,
                      persistRevocationFence(bindingID: pending.bindingID) else {
                    status = .unavailable
                    return false
                }
            } catch {
                status = .unavailable
                return false
            }
        }
        if let legacy = legacyRevocationSource,
           !Self.sameUserID(legacy.userID, expectedUserID) {
            do {
                guard try store.loadLegacyBinding() == legacy,
                      persistRevocationFence(bindingID: legacy.bindingID) else {
                    status = .unavailable
                    return false
                }
            } catch {
                status = .unavailable
                return false
            }
        }
        return true
    }

    /// The registration RPC atomically supersedes the previous owner. If the
    /// replacement binding cannot be stored, retain the returned binding as the
    /// current owner's durable revoke source before attempting best-effort cleanup.
    private func persistReplacementRevocation(
        for replacement: NativePushBinding,
        previousPending: NativePushPendingRevocation?,
        previousLegacy: NativePushLegacyBinding?
    ) -> Bool {
        let expectedSupersededBindingID = previousPending?.bindingID
            ?? previousLegacy?.bindingID
        guard replacement.supersededRevocationBindingID == expectedSupersededBindingID else {
            status = .unavailable
            return false
        }
        let pending = Self.pendingRevocation(for: replacement)
        do {
            try store.savePendingRevocation(pending)
            guard try store.loadPendingRevocation() == pending else {
                status = .unavailable
                return false
            }
            pendingRevocation = pending
            if let previousLegacy {
                guard try store.clearLegacyBinding(previousLegacy) else {
                    status = .unavailable
                    return false
                }
                legacyRevocationSource = nil
            }
            guard persistRevocationFence(bindingID: replacement.bindingID) else {
                status = .unavailable
                return false
            }
            return true
        } catch {
            status = .unavailable
            return false
        }
    }

    private func clearInstallationCleanupIntentsSupersededByRegistration(
        _ intents: [NativePushInstallationCleanupIntent],
        replacement: NativePushBinding
    ) throws {
        guard try store.loadBinding() == replacement,
              intents.allSatisfy({ $0.installationID == replacement.installationID }) else {
            throw NativePushError.invalidState
        }
        for intent in intents {
            guard try store.clearInstallationCleanupIntent(intent) else {
                throw NativePushError.invalidState
            }
            installationCleanupIntents.removeAll { $0 == intent }
        }
    }

    private func retryInstallationCleanupIntentsIfPossible(
        expectedUserID: String,
        expectedAuthSessionID: String
    ) async -> Bool {
        guard currentUserID == expectedUserID,
              currentAuthSessionID == expectedAuthSessionID,
              authIdentityMatches(
                  userID: expectedUserID,
                  authSessionID: expectedAuthSessionID
              ) else {
            return false
        }
        let matching = installationCleanupIntents.filter {
            $0.userID == expectedUserID
        }
        for intent in matching {
            let task = enqueueInstallationCleanup(intent)
            await task.value
            if installationCleanupIntents.contains(intent) {
                return false
            }
        }
        return true
    }

    /// This operation deliberately has no lifecycle-generation guard. It is appended
    /// to `backendTail`, so an earlier registration finishes first and the revoke is
    /// still attempted even when that registration response is no longer eligible to
    /// mutate local state.
    private func enqueueInstallationCleanup(
        _ intent: NativePushInstallationCleanupIntent
    ) -> Task<Void, Never> {
        enqueueBackendOperation { [weak self] in
            guard let self else { return }
            let revoked: Bool
            do {
                revoked = try await self.backend.revoke(
                    installationID: intent.installationID,
                    expectedUserID: intent.userID
                )
            } catch {
                if self.installationCleanupIntents.contains(intent),
                   self.currentUserID == intent.userID {
                    self.status = .revocationPending
                }
                return
            }

            do {
                let storedPending = try self.store.loadPendingRevocation()
                let pendingMatchesIntent = storedPending.map {
                    $0.installationID == intent.installationID
                        && $0.userID == intent.userID
                        && $0.authSessionID == intent.authSessionID
                } == true
                let canClearWholeInstallation = revoked && pendingMatchesIntent
                if canClearWholeInstallation {
                    // A durable post-registration marker proves this owner replaced
                    // any older installation row. A `true` response additionally
                    // proves that this owner was the current server row, so every
                    // older local source for the same installation is stale.
                    try self.store.clearBinding()
                    self.binding = nil
                    self.legacyRevocationSource = nil
                } else if let stored = try self.store.loadBinding(),
                          Self.binding(stored, matches: intent) {
                    guard try self.store.clearBinding(stored) else {
                        throw NativePushError.invalidState
                    }
                    if self.binding == stored { self.binding = nil }
                }
                if let pending = storedPending,
                   pendingMatchesIntent {
                    guard try self.store.clearPendingRevocation(pending) else {
                        throw NativePushError.invalidState
                    }
                    if self.pendingRevocation == pending {
                        self.pendingRevocation = nil
                    }
                }
                if !canClearWholeInstallation,
                   let legacy = try self.store.loadLegacyBinding(),
                   legacy.installationID == intent.installationID,
                   Self.sameUserID(legacy.userID, intent.userID) {
                    guard try self.store.clearLegacyBinding(legacy) else {
                        throw NativePushError.invalidState
                    }
                    if self.legacyRevocationSource == legacy {
                        self.legacyRevocationSource = nil
                    }
                }
                let intentsToClear: [NativePushInstallationCleanupIntent]
                if canClearWholeInstallation {
                    let durable = try self.store.loadInstallationCleanupIntents()
                    intentsToClear = Array(Set(
                        durable.filter { $0.installationID == intent.installationID }
                            + self.installationCleanupIntents.filter {
                                $0.installationID == intent.installationID
                            }
                    ))
                } else {
                    intentsToClear = [intent]
                }
                for cleanupIntent in intentsToClear {
                    guard try self.store.clearInstallationCleanupIntent(cleanupIntent) else {
                        throw NativePushError.invalidState
                    }
                }
                self.installationCleanupIntents = try self.store
                    .loadInstallationCleanupIntents()
                try self.clearRevocationFenceIfNoDurableSources()
            } catch {
                if self.currentUserID == intent.userID {
                    self.status = .unavailable
                }
            }
        }
    }

    private func retryPendingRevocationIfPossible(
        expectedUserID: String,
        expectedAuthSessionID: String
    ) async -> Bool {
        guard let pending = pendingRevocation else { return true }
        guard pending.userID == expectedUserID else {
            // A new owner can safely supersede this marker only after its registration is
            // durably stored. Never authorize the new owner's token to revoke the old row.
            return true
        }
        guard pending.installationID == installationID else {
            status = .unavailable
            return false
        }
        let generation = lifecycleGeneration
        let task = enqueueBackendOperation { [weak self] in
            guard let self,
                  self.lifecycleGeneration == generation,
                  self.pendingRevocation == pending,
                  self.currentUserID == expectedUserID,
                  self.currentAuthSessionID == expectedAuthSessionID,
                  self.authIdentityMatches(
                    userID: expectedUserID,
                    authSessionID: expectedAuthSessionID
                  ) else {
                return
            }
            let revoked: Bool
            do {
                revoked = try await self.backend.revoke(
                    installationID: pending.installationID,
                    expectedUserID: expectedUserID
                )
            } catch {
                guard self.lifecycleGeneration == generation,
                      self.pendingRevocation == pending,
                      self.currentUserID == expectedUserID,
                      self.currentAuthSessionID == expectedAuthSessionID else {
                    return
                }
                self.status = .revocationPending
                return
            }
            guard self.lifecycleGeneration == generation,
                  self.pendingRevocation == pending,
                  self.currentUserID == expectedUserID,
                  self.currentAuthSessionID == expectedAuthSessionID,
                  self.authIdentityMatches(
                    userID: expectedUserID,
                    authSessionID: expectedAuthSessionID
                  ) else {
                return
            }
            do {
                if revoked {
                    try self.store.clearBinding()
                    self.binding = nil
                    self.legacyRevocationSource = nil
                } else if let stored = try self.store.loadBinding(),
                          Self.binding(stored, matches: pending) {
                    guard try self.store.clearBinding(stored) else {
                        throw NativePushError.invalidState
                    }
                    if self.binding == stored { self.binding = nil }
                }
                if !revoked,
                   let legacy = try self.store.loadLegacyBinding(),
                   legacy.installationID == pending.installationID,
                   Self.sameUserID(legacy.userID, pending.userID),
                   legacy.bindingID == pending.bindingID {
                    guard try self.store.clearLegacyBinding(legacy) else {
                        throw NativePushError.invalidState
                    }
                    if self.legacyRevocationSource == legacy {
                        self.legacyRevocationSource = nil
                    }
                }
                guard try self.store.clearPendingRevocation(pending) else {
                    self.status = .unavailable
                    return
                }
                if self.pendingRevocation == pending {
                    self.pendingRevocation = nil
                }
                try self.clearRevocationFenceIfNoDurableSources()
            } catch {
                self.status = .unavailable
            }
        }
        await task.value
        return pendingRevocation != pending
    }

    private func retryLegacyRevocationIfPossible(
        expectedUserID: String,
        expectedAuthSessionID: String
    ) async -> Bool {
        guard let legacy = legacyRevocationSource else { return true }
        guard Self.sameUserID(legacy.userID, expectedUserID) else {
            // Only the legacy owner may revoke. A different owner must replace it via a
            // durably stored v2 registration carrying the exact superseded binding ID.
            return true
        }
        guard legacy.installationID == installationID else {
            status = .unavailable
            return false
        }
        let generation = lifecycleGeneration
        let task = enqueueBackendOperation { [weak self] in
            guard let self,
                  self.lifecycleGeneration == generation,
                  self.legacyRevocationSource == legacy,
                  self.currentUserID == expectedUserID,
                  self.currentAuthSessionID == expectedAuthSessionID,
                  self.authIdentityMatches(
                    userID: expectedUserID,
                    authSessionID: expectedAuthSessionID
                  ) else {
                return
            }
            do {
                _ = try await self.backend.revoke(
                    installationID: legacy.installationID,
                    expectedUserID: expectedUserID
                )
            } catch {
                guard self.lifecycleGeneration == generation,
                      self.legacyRevocationSource == legacy,
                      self.currentUserID == expectedUserID,
                      self.currentAuthSessionID == expectedAuthSessionID else {
                    return
                }
                self.status = .revocationPending
                return
            }
            guard self.lifecycleGeneration == generation,
                  self.legacyRevocationSource == legacy,
                  self.currentUserID == expectedUserID,
                  self.currentAuthSessionID == expectedAuthSessionID,
                  self.authIdentityMatches(
                    userID: expectedUserID,
                    authSessionID: expectedAuthSessionID
                  ) else {
                return
            }
            do {
                guard try self.store.clearLegacyBinding(legacy) else {
                    self.status = .unavailable
                    return
                }
                if self.legacyRevocationSource == legacy {
                    self.legacyRevocationSource = nil
                }
                try self.clearRevocationFenceIfNoDurableSources()
            } catch {
                self.status = .unavailable
            }
        }
        await task.value
        return legacyRevocationSource != legacy
    }

    private func authIdentityMatches(userID: String, authSessionID: String) -> Bool {
        guard let cloud = auth.session?.cloud else { return false }
        return cloud.userID == userID
            && NativePushAuthSessionIdentity.sessionID(from: cloud) == authSessionID
    }

    private func enqueueRegistration(
        token: Data,
        expectedUserID: String,
        expectedAuthSessionID: String
    ) {
        guard let installationID else { return }
        let tokenHex = token.map { String(format: "%02x", $0) }.joined()
        let digest = Self.tokenDigest(token)
        let generation = lifecycleGeneration
        let pendingBeforeRegistration = pendingRevocation
        let legacyBeforeRegistration = legacyRevocationSource
        let cleanupIntentsBeforeRegistration = installationCleanupIntents
        let key = "\(generation):\(expectedUserID):\(expectedAuthSessionID):\(environment.rawValue):\(digest)"
        if pendingRegistrationKey == key { return }
        if let binding,
           binding.userID == expectedUserID,
           binding.authSessionID == expectedAuthSessionID,
           binding.environment == environment,
           binding.tokenDigest == digest {
            status = .active
            return
        }
        pendingRegistrationKey = key
        status = .registering
        _ = enqueueBackendOperation { [weak self] in
            guard let self else { return }
            defer {
                if self.pendingRegistrationKey == key {
                    self.pendingRegistrationKey = nil
                }
            }
            guard self.lifecycleGeneration == generation,
                  !self.isFenced,
                  self.isEnabled,
                  self.currentUserID == expectedUserID,
                  self.currentAuthSessionID == expectedAuthSessionID,
                  self.pendingRevocation == pendingBeforeRegistration,
                  self.legacyRevocationSource == legacyBeforeRegistration,
                  self.installationCleanupIntents == cleanupIntentsBeforeRegistration,
                  self.authIdentityMatches(
                    userID: expectedUserID,
                    authSessionID: expectedAuthSessionID
                  ),
                  self.deviceToken == token else { return }
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
                      self.currentAuthSessionID == expectedAuthSessionID,
                      self.pendingRevocation == pendingBeforeRegistration,
                      self.legacyRevocationSource == legacyBeforeRegistration,
                      self.installationCleanupIntents == cleanupIntentsBeforeRegistration,
                      self.authIdentityMatches(
                        userID: expectedUserID,
                        authSessionID: expectedAuthSessionID
                      ),
                      self.deviceToken == token else {
                    return
                }
                let stored = NativePushBinding(
                    version: NativePushBinding.currentVersion,
                    installationID: installationID,
                    userID: expectedUserID,
                    authSessionID: expectedAuthSessionID,
                    bindingID: response.bindingID,
                    environment: response.environment,
                    tokenDigest: digest,
                    registrationRevision: response.registrationRevision,
                    supersededRevocationBindingID: pendingBeforeRegistration?.bindingID
                        ?? legacyBeforeRegistration?.bindingID
                )
                do {
                    try self.store.saveBinding(stored)
                    guard try self.store.loadBinding() == stored else {
                        throw NativePushError.invalidState
                    }
                    if let pending = pendingBeforeRegistration {
                        guard Self.provesSupersession(stored, of: pending),
                              self.clearRevocationFence(),
                              try self.store.clearPendingRevocation(pending) else {
                            throw NativePushError.invalidState
                        }
                        self.pendingRevocation = nil
                    } else if let legacy = legacyBeforeRegistration {
                        guard Self.provesSupersession(stored, of: legacy),
                              self.clearRevocationFence() else {
                            throw NativePushError.invalidState
                        }
                        self.legacyRevocationSource = nil
                    }
                    try self.clearInstallationCleanupIntentsSupersededByRegistration(
                        cleanupIntentsBeforeRegistration,
                        replacement: stored
                    )
                } catch {
                    self.isFenced = true
                    self.binding = nil
                    try? self.store.clearDeliveryState()
                    _ = self.persistReplacementRevocation(
                        for: stored,
                        previousPending: pendingBeforeRegistration,
                        previousLegacy: legacyBeforeRegistration
                    )
                    do {
                        let revoked = try await self.backend.revoke(
                            installationID: installationID,
                            expectedUserID: expectedUserID
                        )
                        if self.lifecycleGeneration == generation,
                           self.currentUserID == expectedUserID,
                           self.currentAuthSessionID == expectedAuthSessionID {
                            if revoked {
                                try self.store.clearBinding()
                                self.binding = nil
                                self.legacyRevocationSource = nil
                            } else if let exact = try self.store.loadBinding(),
                                      exact == stored {
                                guard try self.store.clearBinding(exact) else {
                                    throw NativePushError.invalidState
                                }
                                if self.binding == exact { self.binding = nil }
                            }
                            let storedPending = try self.store.loadPendingRevocation()
                            let replacementPending = Self.pendingRevocation(for: stored)
                            if let pending = storedPending,
                               revoked || pending == replacementPending {
                                guard try self.store.clearPendingRevocation(pending) else {
                                    throw NativePushError.invalidState
                                }
                                if self.pendingRevocation == pending {
                                    self.pendingRevocation = nil
                                }
                            }
                            try self.clearRevocationFenceIfNoDurableSources()
                        }
                    } catch {
                        // The durable marker remains for an authenticated retry.
                    }
                    if self.lifecycleGeneration == generation,
                       self.currentUserID == expectedUserID,
                       self.currentAuthSessionID == expectedAuthSessionID {
                        self.status = .unavailable
                    }
                    return
                }
                self.binding = stored
                self.status = .active
            } catch {
                guard self.lifecycleGeneration == generation,
                      self.currentUserID == expectedUserID,
                      self.currentAuthSessionID == expectedAuthSessionID else {
                    return
                }
                self.status = self.pendingRevocation?.userID == expectedUserID
                    || self.legacyRevocationSource.map({
                        Self.sameUserID($0.userID, expectedUserID)
                    }) == true
                    ? .revocationPending
                    : .failed
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
        for event: NativePushRemoteEvent,
        binding: NativePushBinding
    ) -> NativePushLocalNotification {
        let copy = Self.copy(
            for: event.eventType,
            languageCode: defaults.string(forKey: "app-language")
                ?? AppLanguage.english.rawValue
        )
        let identity = "\(binding.bindingID.uuidString.lowercased()):\(event.deliveryKey)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return NativePushLocalNotification(
            identifier: NativePushSystemController.notificationIdentifierPrefix + digest,
            title: copy.title,
            body: copy.body,
            bindingID: event.bindingID,
            target: event.routeTarget
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
