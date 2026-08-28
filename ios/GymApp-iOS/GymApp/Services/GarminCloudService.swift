import Combine
import CryptoKit
import Foundation
import Security

struct GarminPlanSet: Codable, Hashable, Sendable {
    let weight: Double
    let reps: Int
    let orderIndex: Int
}

struct GarminPlanExercise: Codable, Hashable, Sendable {
    let name: String
    let sets: [GarminPlanSet]
}

struct GarminWorkoutPlan: Codable, Equatable, Sendable {
    let source: String
    let version: Int
    let title: String
    let createdAt: String
    let startedAt: String
    let note: String
    let exercises: [GarminPlanExercise]
}

struct GarminDeviceSummary: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let createdAt: String?
    let lastSeenAt: String?
    let bindingVersion: Int
    let tokenRevision: Int
}

/// One-time credential returned to the UI. Deliberately not Codable: pending
/// creation persists only the bounded random nonce needed for an exact retry,
/// while the returned v3 capability is never written to app storage.
struct GarminPairingCredential: Equatable, Identifiable, Sendable {
    let id: String
    let deviceToken: String
    let displayName: String
}

struct GarminDeviceBinding: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let userID: String
    let deviceID: String
}

enum GarminPendingCleanupKind: String, Codable, Sendable {
    case revoke
    case legacyRecovery = "legacy-recovery"
}

struct GarminPendingRevocation: Codable, Equatable, Sendable {
    let version: Int
    let userID: String
    let deviceID: String
    let cleanupKind: GarminPendingCleanupKind
    let creationRequestID: String?

    init(
        version: Int,
        userID: String,
        deviceID: String,
        cleanupKind: GarminPendingCleanupKind = .revoke,
        creationRequestID: String? = nil
    ) {
        self.version = version
        self.userID = userID
        self.deviceID = deviceID
        self.cleanupKind = cleanupKind
        self.creationRequestID = creationRequestID
    }

    private enum CodingKeys: String, CodingKey {
        case version, userID, deviceID, cleanupKind, creationRequestID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        userID = try container.decode(String.self, forKey: .userID)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        // Records written by versions before outcome-idempotent creation were
        // always ordinary revocations and remain backward compatible.
        cleanupKind = try container.decodeIfPresent(
            GarminPendingCleanupKind.self,
            forKey: .cleanupKind
        ) ?? .revoke
        creationRequestID = try container.decodeIfPresent(
            String.self,
            forKey: .creationRequestID
        )
    }
}

struct GarminPendingDeviceCreation: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let userID: String
    let requestID: String
    let deviceID: String
    let deviceToken: String
    let displayName: String
    let createdAt: Date
    let legacyFallbackAttempted: Bool
}

struct GarminDeviceBindingStore {
    private static let bindingAccountPrefix = "selected-device-v2."
    private static let pendingRevocationAccountPrefix = "pending-revocation-v2."
    private static let pendingCreationAccountPrefix = "pending-creation-v1."
    private static let maximumRecordBytes = 1_024
    private static let maximumPendingCreationAge: TimeInterval = 24 * 60 * 60

    private let keychain: any KeychainStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        keychain: any KeychainStoring = KeychainStore(
            service: "com.setforge.gymapp.ios.garmin-binding"
        )
    ) {
        self.keychain = keychain
    }

    func binding(for userID: String) throws -> GarminDeviceBinding? {
        let userID = try canonicalUserID(userID)
        guard let data = try keychain.read(account: bindingAccount(for: userID)) else {
            return nil
        }
        guard data.count <= Self.maximumRecordBytes,
              let binding = try? decoder.decode(GarminDeviceBinding.self, from: data),
              binding.version == GarminDeviceBinding.currentVersion,
              binding.userID == userID,
              canonicalUUID(binding.deviceID) == binding.deviceID else {
            throw GarminCloudError.invalidBinding
        }
        return binding
    }

    func save(binding: GarminDeviceBinding) throws {
        let userID = try canonicalUserID(binding.userID)
        guard binding.version == GarminDeviceBinding.currentVersion,
              binding.userID == userID,
              canonicalUUID(binding.deviceID) == binding.deviceID else {
            throw GarminCloudError.invalidBinding
        }
        let data = try encoder.encode(binding)
        guard data.count <= Self.maximumRecordBytes else {
            throw GarminCloudError.invalidBinding
        }
        try keychain.save(data, account: bindingAccount(for: userID))
    }

    func deleteBinding(for userID: String) throws {
        let userID = try canonicalUserID(userID)
        try keychain.delete(account: bindingAccount(for: userID))
    }

    func pendingRevocation(for userID: String) throws -> GarminPendingRevocation? {
        let userID = try canonicalUserID(userID)
        guard let data = try keychain.read(account: pendingAccount(for: userID)) else {
            return nil
        }
        guard data.count <= Self.maximumRecordBytes,
              let value = try? decoder.decode(GarminPendingRevocation.self, from: data),
              value.version == GarminDeviceBinding.currentVersion,
              value.userID == userID,
              canonicalUUID(value.deviceID) == value.deviceID,
              value.creationRequestID.map({
                  canonicalVersion4UUIDString($0) == $0
              }) ?? true else {
            throw GarminCloudError.invalidBinding
        }
        return value
    }

    func savePendingRevocation(
        userID: String,
        deviceID: String,
        cleanupKind: GarminPendingCleanupKind = .revoke,
        creationRequestID: String? = nil
    ) throws {
        let userID = try canonicalUserID(userID)
        guard canonicalUUID(deviceID) == deviceID,
              creationRequestID.map({
                  canonicalVersion4UUIDString($0) == $0
              }) ?? true else {
            throw GarminCloudError.invalidBinding
        }
        let data = try encoder.encode(
            GarminPendingRevocation(
                version: GarminDeviceBinding.currentVersion,
                userID: userID,
                deviceID: deviceID,
                cleanupKind: cleanupKind,
                creationRequestID: creationRequestID
            )
        )
        guard data.count <= Self.maximumRecordBytes else {
            throw GarminCloudError.invalidBinding
        }
        try keychain.save(data, account: pendingAccount(for: userID))
    }

    func clearPendingRevocation(for userID: String) throws {
        let userID = try canonicalUserID(userID)
        try keychain.delete(account: pendingAccount(for: userID))
    }

    func pendingCreation(
        for userID: String,
        now: Date = Date()
    ) throws -> GarminPendingDeviceCreation? {
        let userID = try canonicalUserID(userID)
        let account = pendingCreationAccount(for: userID)
        guard let data = try keychain.read(account: account) else { return nil }
        guard data.count <= Self.maximumRecordBytes,
              let value = try? decoder.decode(GarminPendingDeviceCreation.self, from: data),
              validPendingCreation(value, userID: userID),
              value.createdAt <= now.addingTimeInterval(5 * 60) else {
            try keychain.delete(account: account)
            throw GarminCloudError.invalidBinding
        }
        if now.timeIntervalSince(value.createdAt) > Self.maximumPendingCreationAge {
            _ = try promotePendingCreationToCleanup(for: userID, now: now)
            throw GarminCloudError.pendingRevocation
        }
        return value
    }

    @discardableResult
    func promotePendingCreationToCleanup(
        for userID: String,
        now: Date = Date()
    ) throws -> GarminPendingRevocation? {
        let userID = try canonicalUserID(userID)
        let account = pendingCreationAccount(for: userID)
        guard let data = try keychain.read(account: account) else {
            return try pendingRevocation(for: userID)
        }
        guard data.count <= Self.maximumRecordBytes,
              let creation = try? decoder.decode(GarminPendingDeviceCreation.self, from: data),
              validPendingCreation(creation, userID: userID),
              creation.createdAt <= now.addingTimeInterval(5 * 60) else {
            // Never issue a server operation for an untrusted local ID. The
            // malformed bearer is still removed before reporting the failure.
            try keychain.delete(account: account)
            throw GarminCloudError.invalidBinding
        }
        let cleanupKind: GarminPendingCleanupKind = creation.legacyFallbackAttempted
            ? .legacyRecovery
            : .revoke
        if let existing = try pendingRevocation(for: userID) {
            guard existing.deviceID == creation.deviceID,
                  existing.cleanupKind == cleanupKind else {
                // A single Keychain slot must never overwrite an older live
                // cleanup obligation. Keep the raw retry record until the
                // first cleanup is resolved.
                throw GarminCloudError.pendingRevocation
            }
        } else {
            try savePendingRevocation(
                userID: userID,
                deviceID: creation.deviceID,
                cleanupKind: cleanupKind,
                creationRequestID: creation.requestID
            )
        }
        try keychain.delete(account: account)
        return try pendingRevocation(for: userID)
    }

    func save(pendingCreation value: GarminPendingDeviceCreation) throws {
        let userID = try canonicalUserID(value.userID)
        guard validPendingCreation(value, userID: userID) else {
            throw GarminCloudError.invalidBinding
        }
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumRecordBytes else {
            throw GarminCloudError.invalidBinding
        }
        try keychain.save(data, account: pendingCreationAccount(for: userID))
    }

    func clearPendingCreation(for userID: String) throws {
        let userID = try canonicalUserID(userID)
        try keychain.delete(account: pendingCreationAccount(for: userID))
    }

    func clearPendingCreation(
        matching cleanup: GarminPendingRevocation,
        now: Date = Date()
    ) throws {
        let userID = try canonicalUserID(cleanup.userID)
        guard cleanup.version == GarminDeviceBinding.currentVersion,
              canonicalUUID(cleanup.deviceID) == cleanup.deviceID,
              cleanup.creationRequestID.map({
                  canonicalVersion4UUIDString($0) == $0
              }) ?? true else {
            throw GarminCloudError.invalidBinding
        }
        let account = pendingCreationAccount(for: userID)
        guard let data = try keychain.read(account: account) else { return }
        guard data.count <= Self.maximumRecordBytes,
              let creation = try? decoder.decode(GarminPendingDeviceCreation.self, from: data),
              validPendingCreation(creation, userID: userID),
              creation.createdAt <= now.addingTimeInterval(5 * 60) else {
            try keychain.delete(account: account)
            throw GarminCloudError.invalidBinding
        }
        let matchesCleanup: Bool
        if let requestID = cleanup.creationRequestID {
            // Legacy createDevice generated its own device ID. The original
            // CSPRNG request ID is the only exact, nonsecret correlation that
            // survives a successful response and a later Keychain delete failure.
            matchesCleanup = creation.requestID == requestID
        } else {
            let creationKind: GarminPendingCleanupKind = creation.legacyFallbackAttempted
                ? .legacyRecovery
                : .revoke
            matchesCleanup = creation.deviceID == cleanup.deviceID
                && creationKind == cleanup.cleanupKind
        }
        guard matchesCleanup else {
            throw GarminCloudError.pendingRevocation
        }
        try keychain.delete(account: account)
    }

    func deleteAll(for userID: String) throws {
        let userID = try canonicalUserID(userID)
        var firstError: Error?
        do {
            try keychain.delete(account: bindingAccount(for: userID))
        } catch {
            firstError = error
        }
        do {
            try keychain.delete(account: pendingAccount(for: userID))
        } catch {
            firstError = firstError ?? error
        }
        do {
            try keychain.delete(account: pendingCreationAccount(for: userID))
        } catch {
            firstError = firstError ?? error
        }
        if let firstError { throw firstError }
    }

    private func canonicalUserID(_ value: String) throws -> String {
        guard let canonical = canonicalUUID(value) else {
            throw GarminCloudError.invalidBinding
        }
        return canonical
    }

    private func bindingAccount(for userID: String) -> String {
        Self.bindingAccountPrefix + userID
    }

    private func pendingAccount(for userID: String) -> String {
        Self.pendingRevocationAccountPrefix + userID
    }

    private func pendingCreationAccount(for userID: String) -> String {
        Self.pendingCreationAccountPrefix + userID
    }

    private func validPendingCreation(
        _ value: GarminPendingDeviceCreation,
        userID: String
    ) -> Bool {
        value.version == GarminPendingDeviceCreation.currentVersion &&
            value.userID == userID &&
            canonicalVersion4UUIDString(value.requestID) == value.requestID &&
            canonicalVersion4UUIDString(value.deviceID) == value.deviceID &&
            isLowercaseHexToken(value.deviceToken) &&
            (1 ... 80).contains(value.displayName.count) &&
            value.displayName.utf8.count <= 320 &&
            value.displayName == value.displayName.trimmingCharacters(in: .whitespacesAndNewlines) &&
            !value.displayName.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }
}

private func canonicalUUID(_ value: String) -> String? {
    guard value.utf8.count == 36, let uuid = UUID(uuidString: value) else { return nil }
    return uuid.uuidString.lowercased()
}

private func canonicalVersion4UUIDString(_ value: String) -> String? {
    guard let canonical = canonicalUUID(value) else { return nil }
    let versionIndex = canonical.index(canonical.startIndex, offsetBy: 14)
    let variantIndex = canonical.index(canonical.startIndex, offsetBy: 19)
    guard canonical[versionIndex] == "4",
          "89ab".contains(canonical[variantIndex]) else { return nil }
    return canonical
}

private func isLowercaseHexToken(_ value: String) -> Bool {
    value.utf8.count == 64 && value.unicodeScalars.allSatisfy { scalar in
        let code = Int(scalar.value)
        return (48 ... 57).contains(code) || (97 ... 102).contains(code)
    }
}

private enum GarminPairingCapability {
    case legacyNonce(String)
    case version3(accountBinding: String, deviceID: String, nonce: String)

    var version: Int {
        switch self {
        case .legacyNonce: return 2
        case .version3: return 3
        }
    }

    var nonce: String {
        switch self {
        case .legacyNonce(let nonce), .version3(_, _, let nonce): return nonce
        }
    }

    var deviceID: String? {
        guard case .version3(_, let deviceID, _) = self else { return nil }
        return deviceID
    }

    var accountBinding: String? {
        guard case .version3(let accountBinding, _, _) = self else { return nil }
        return accountBinding
    }
}

private func parseGarminPairingCapability(_ value: String) -> GarminPairingCapability? {
    // Keep the released watch/backend token parser for the explicit legacy
    // creation fallback. New issuer paths require the v3 case at their callsite.
    if isLowercaseHexToken(value) {
        return .legacyNonce(value)
    }

    guard value.utf8.count == 234 else { return nil }
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count == 5,
          components[0] == "g3" else { return nil }

    let accountBinding = String(components[1])
    let deviceID = String(components[2])
    let nonce = String(components[3])
    let tag = String(components[4])
    guard isLowercaseHexToken(accountBinding),
          canonicalGarminCapabilityDeviceID(deviceID) == deviceID,
          isLowercaseHexToken(nonce),
          isLowercaseHexToken(tag) else { return nil }
    return .version3(
        accountBinding: accountBinding,
        deviceID: deviceID,
        nonce: nonce
    )
}

private func garminAccountBinding(for canonicalUserID: String) -> String? {
    guard canonicalGarminCapabilityDeviceID(canonicalUserID) == canonicalUserID else {
        return nil
    }
    return SHA256.hash(data: Data(canonicalUserID.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

private func canonicalGarminCapabilityDeviceID(_ value: String) -> String? {
    guard let canonical = canonicalUUID(value) else { return nil }
    let versionIndex = canonical.index(canonical.startIndex, offsetBy: 14)
    let variantIndex = canonical.index(canonical.startIndex, offsetBy: 19)
    guard "12345".contains(canonical[versionIndex]),
          "89ab".contains(canonical[variantIndex]) else { return nil }
    return canonical
}

enum GarminPlanValidator {
    static let maximumExercises = 60
    static let maximumTotalSets = 60
    static let maximumPlanBytes = 64 * 1_024
    static let maximumTitleCharacters = 120
    static let maximumTitleBytes = 480
    static let maximumNameCharacters = 160
    static let maximumNameBytes = 640
    static let maximumFlattenedPlanNameBytes = 12_000
    static let maximumNoteCharacters = 2_000
    static let maximumNoteBytes = 8_000
    static let maximumTimestampBytes = 40
    static let maximumWeight = 1_000_000.0
    static let maximumReps = 10_000

    static func validate(_ plan: GarminWorkoutPlan) throws -> Data {
        guard plan.source == "gymapp-ios",
              plan.version == 1,
              bounded(
                plan.title,
                characters: maximumTitleCharacters,
                bytes: maximumTitleBytes
              ),
              !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              bounded(plan.note, characters: maximumNoteCharacters, bytes: maximumNoteBytes),
              validTimestamp(plan.createdAt),
              validTimestamp(plan.startedAt),
              (1 ... maximumExercises).contains(plan.exercises.count) else {
            throw GarminCloudError.invalidPlan
        }

        var totalSets = 0
        var flattenedPlanNameBytes = 0
        for exercise in plan.exercises {
            guard bounded(
                    exercise.name,
                    characters: maximumNameCharacters,
                    bytes: maximumNameBytes
                  ),
                  !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !exercise.sets.isEmpty else {
                throw GarminCloudError.invalidPlan
            }
            guard exercise.sets.count <= maximumTotalSets - totalSets else {
                throw GarminCloudError.invalidPlan
            }
            let repeatedNameBytes = exercise.name.utf8.count * exercise.sets.count
            guard repeatedNameBytes <= maximumFlattenedPlanNameBytes - flattenedPlanNameBytes else {
                throw GarminCloudError.invalidPlan
            }
            totalSets += exercise.sets.count
            flattenedPlanNameBytes += repeatedNameBytes
            for (index, set) in exercise.sets.enumerated() {
                guard set.orderIndex == index,
                      set.weight.isFinite,
                      (0 ... maximumWeight).contains(set.weight),
                      (1 ... maximumReps).contains(set.reps) else {
                    throw GarminCloudError.invalidPlan
                }
            }
        }
        guard totalSets > 0 else { throw GarminCloudError.invalidPlan }

        let data = try JSONEncoder().encode(plan)
        guard data.count <= maximumPlanBytes else { throw GarminCloudError.invalidPlan }
        return data
    }

    private static func bounded(_ value: String, characters: Int, bytes: Int) -> Bool {
        guard value.utf8.prefix(bytes + 1).count <= bytes else { return false }
        return value.utf16.prefix(characters + 1).count <= characters &&
            !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    private static func validTimestamp(_ value: String) -> Bool {
        guard value.utf8.prefix(maximumTimestampBytes + 1).count <= maximumTimestampBytes else {
            return false
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) else { return false }
        return date >= .distantPast && date <= .distantFuture
    }
}

enum GarminCloudError: LocalizedError {
    case invalidPlan
    case invalidRequest
    case invalidResponse
    case invalidBinding
    case pairingRequired
    case busy
    case pendingRevocation
    case bindingPersistenceFailed
    case deviceRefreshRequired
    case deviceCreationRecoveryRequired
    case rotationConflict
    case enqueueConflict
    case requestFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidPlan: return "Add at least one valid exercise set before syncing."
        case .invalidRequest: return "The Garmin sync request is too large or malformed."
        case .invalidResponse: return "Garmin cloud sync returned an invalid response."
        case .invalidBinding: return "The selected Garmin watch binding is invalid. Select or pair the watch again."
        case .pairingRequired: return "Select or pair a Garmin watch in Account settings before queueing a plan."
        case .busy: return "Another Garmin operation is already in progress. Try again."
        case .pendingRevocation: return "A previous Garmin pairing is still awaiting secure revocation. Keep the app open and retry."
        case .bindingPersistenceFailed: return "The Garmin watch selection could not be stored securely, so its one-time token was not shown."
        case .deviceRefreshRequired: return "Refresh the Garmin watch list before rotating its token."
        case .deviceCreationRecoveryRequired: return "A Garmin watch may already have been created by an older server, but its one-time token response was lost. Refresh the list, select that watch, and rotate its token instead of creating another one."
        case .rotationConflict: return "This watch changed elsewhere. Its details were refreshed; review the selection and retry token rotation."
        case .enqueueConflict: return "This workout queue request conflicts with an earlier submission and was not duplicated."
        case .requestFailed(_, let value): return value
        }
    }
}

@MainActor
final class GarminCloudService: ObservableObject {
    private static let maximumAccessTokenBytes = 16 * 1_024
    private static let maximumRequestBodyBytes = 96 * 1_024
    private static let maximumResponseBodyBytes = 256 * 1_024
    private static let maximumErrorResponseBodyBytes = 16 * 1_024
    private static let maximumServerErrorBytes = 512

    @Published private(set) var isWorking = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var selectedDevice: GarminDeviceBinding?
    @Published private(set) var availableDevices: [GarminDeviceSummary] = []

    private let auth: AuthService
    private let urlSession: URLSession
    private let bindingStore: GarminDeviceBindingStore
    private var sessionSubscription: AnyCancellable?
    private var availableDevicesUserID: String?
    private var observedSessionUserID: String?

    init(
        auth: AuthService,
        urlSession: URLSession = .shared,
        bindingStore: GarminDeviceBindingStore = GarminDeviceBindingStore()
    ) {
        self.auth = auth
        self.urlSession = urlSession
        self.bindingStore = bindingStore
        observedSessionUserID = canonicalUUID(auth.session?.cloud?.userID ?? "")
        reloadPublishedBinding(for: auth.session)
        sessionSubscription = auth.$session
            .removeDuplicates(by: { $0?.storageKey == $1?.storageKey })
            .sink { [weak self] session in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let nextUserID = canonicalUUID(session?.cloud?.userID ?? "")
                    var transitionError: String?
                    if let previousUserID = self.observedSessionUserID,
                       previousUserID != nextUserID {
                        do {
                            _ = try self.bindingStore.promotePendingCreationToCleanup(
                                for: previousUserID
                            )
                        } catch {
                            // The normal AppState transition performs this
                            // synchronously before clearing auth. This fallback
                            // still strips valid pending bearer material when a
                            // lower-level AuthService account switch occurs.
                            transitionError = error.localizedDescription
                        }
                    }
                    self.observedSessionUserID = nextUserID
                    self.availableDevices = []
                    self.availableDevicesUserID = nil
                    self.lastMessage = transitionError
                    self.reloadPublishedBinding(for: session)
                }
            }
    }

    func refreshDevices() async throws {
        try beginOperation()
        defer { isWorking = false }

        let identity = try activeIdentity()
        let session = try await auth.validCloudSession(expectedUserID: identity.rawUserID)
        try ensureIdentityIsCurrent(identity)
        try await recoverPendingRevocation(identity: identity, token: session.accessToken)
        let object = try await withAuthenticationRetry(
            identity: identity,
            fallbackToken: session.accessToken
        ) { token in
            try await self.requestObject(
                path: "/functions/v1/garmin-sync",
                method: "POST",
                token: token,
                body: ["action": "listDevices"]
            )
        }
        try ensureIdentityIsCurrent(identity)
        try publishDevices(parseDeviceList(object), for: identity)
    }

    func selectDevice(_ device: GarminDeviceSummary) throws {
        guard !isWorking else { throw GarminCloudError.busy }
        let identity = try activeIdentity()
        guard device.bindingVersion == GarminDeviceBinding.currentVersion,
              canonicalUUID(device.id) == device.id,
              availableDevicesUserID == identity.canonicalUserID,
              availableDevices.contains(device) else {
            throw GarminCloudError.invalidBinding
        }
        let binding = GarminDeviceBinding(
            version: GarminDeviceBinding.currentVersion,
            userID: identity.canonicalUserID,
            deviceID: device.id
        )
        let pendingCleanup = try bindingStore.pendingRevocation(
            for: identity.canonicalUserID
        )
        if let pendingCleanup, pendingCleanup.cleanupKind != .legacyRecovery {
            throw GarminCloudError.pendingRevocation
        }
        // An explicit owner choice supersedes any outcome-unknown legacy
        // creation. Persist the selected binding before removing its recovery
        // material so a Keychain write failure cannot lose both.
        try bindingStore.save(binding: binding)
        try bindingStore.clearPendingCreation(for: identity.canonicalUserID)
        if pendingCleanup?.cleanupKind == .legacyRecovery {
            try bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
        }
        selectedDevice = binding
        lastMessage = "Selected Garmin watch: \(device.displayName)."
    }

    /// Removes any outcome-unknown raw creation credential before the owning
    /// cloud session can be cleared. A failed remote revoke remains as a
    /// nonsecret Keychain cleanup marker for the next same-owner session.
    func prepareForSessionEnd(expectedUserID: String) async throws {
        guard !isWorking else { throw GarminCloudError.busy }
        let identity = try activeIdentity()
        guard canonicalUUID(expectedUserID) == identity.canonicalUserID else {
            throw AuthServiceError.sessionChanged
        }
        let pending = try bindingStore.promotePendingCreationToCleanup(
            for: identity.canonicalUserID
        )
        guard let pending else { return }
        if pending.cleanupKind == .legacyRecovery {
            // The legacy endpoint generated its own device ID. The client
            // nonce was never a bearer for that result and is now gone; list
            // and explicit selection will recover it after the next sign-in.
            lastMessage = GarminCloudError.deviceCreationRecoveryRequired.errorDescription
            return
        }
        let session: CloudAccountSession
        do {
            session = try await auth.validCloudSession(expectedUserID: identity.rawUserID)
        } catch {
            // The raw one-shot Garmin credential was already replaced by a
            // nonsecret, owner-bound cleanup marker. Offline token refresh must
            // not prevent local logout; a real account transition still fails
            // closed so this operation cannot finish for a replacement owner.
            switch auth.session {
            case .some(.cloud(let cloud)) where cloud.userID == identity.rawUserID:
                lastMessage = GarminCloudError.pendingRevocation.errorDescription
                return
            case .none:
                lastMessage = GarminCloudError.pendingRevocation.errorDescription
                return
            default:
                throw AuthServiceError.sessionChanged
            }
        }
        try ensureIdentityIsCurrent(identity)
        if await bestEffortRevoke(
            deviceID: pending.deviceID,
            identity: identity,
            token: session.accessToken
        ) {
            try bindingStore.clearPendingCreation(matching: pending)
            try bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
        } else {
            lastMessage = GarminCloudError.pendingRevocation.errorDescription
        }
    }

    func createDevice(displayName: String = "Garmin watch") async throws -> GarminPairingCredential {
        let cleanDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDisplayName(cleanDisplayName) else {
            throw GarminCloudError.invalidRequest
        }
        try beginOperation()
        defer { isWorking = false }

        let identity = try activeIdentity()
        let session = try await auth.validCloudSession(expectedUserID: identity.rawUserID)
        try ensureIdentityIsCurrent(identity)
        try await recoverPendingRevocation(identity: identity, token: session.accessToken)
        var persistedCreation = try bindingStore.pendingCreation(
            for: identity.canonicalUserID
        )
        if let persistedCreation,
           persistedCreation.displayName != cleanDisplayName {
            throw GarminCloudError.deviceRefreshRequired
        }
        if let durableCreation = persistedCreation {
            let clearedAfterAuthoritativeEmpty = try await reconcilePersistedCreation(
                durableCreation,
                identity: identity,
                token: session.accessToken
            )
            if clearedAfterAuthoritativeEmpty {
                // Never reuse the one-shot legacy transition. A new request
                // starts with fresh CSPRNG material after the owner list proves
                // the earlier call created no active device.
                try ensureIdentityIsCurrent(identity)
                persistedCreation = nil
            }
        }
        let creation: GarminPendingDeviceCreation
        if let persistedCreation {
            creation = persistedCreation
        } else {
            creation = GarminPendingDeviceCreation(
                version: GarminPendingDeviceCreation.currentVersion,
                userID: identity.canonicalUserID,
                requestID: try canonicalVersion4UUID(UUID()),
                deviceID: try canonicalVersion4UUID(UUID()),
                deviceToken: try generateDeviceToken(),
                displayName: cleanDisplayName,
                createdAt: Date(),
                legacyFallbackAttempted: false
            )
            try bindingStore.save(pendingCreation: creation)
        }
        let resultObject: DeviceCreationResponse
        do {
            resultObject = try await withAuthenticationRetry(
                identity: identity,
                fallbackToken: session.accessToken
            ) { token in
                try await self.requestDeviceCreation(
                    creation,
                    identity: identity,
                    token: token
                )
            }
        } catch GarminCloudError.requestFailed(let statusCode, _)
            where statusCode == 409 {
            // A request-ID/device-ID collision is definitive and owns no row
            // for this payload. Do not persist or retry the rejected secret.
            try? bindingStore.clearPendingCreation(for: identity.canonicalUserID)
            throw GarminCloudError.deviceRefreshRequired
        }
        let result = try parsePairingCredential(resultObject.object)
        if resultObject.idempotent {
            guard let status = resultObject.object["status"] as? String,
                  status == "created" || status == "already_created",
                  exactInteger(resultObject.object["capabilityVersion"]) == 3,
                  resultObject.object["requestId"] as? String == creation.requestID,
                  result.summary.id == creation.deviceID,
                  result.summary.tokenRevision == 1,
                  result.capability.version == 3,
                  result.capability.accountBinding == garminAccountBinding(
                      for: identity.canonicalUserID
                  ),
                  result.capability.deviceID == creation.deviceID,
                  result.capability.nonce == creation.deviceToken,
                  result.credential.displayName == creation.displayName else {
                throw GarminCloudError.invalidResponse
            }
        }
        try await persistCreatedDevice(
            result,
            identity: identity,
            token: session.accessToken,
            creationRequestID: creation.requestID,
            clearPendingCreation: true
        )
        lastMessage = "Device token created. Paste it into Garmin Connect IQ settings."
        return result.credential
    }

    func rotateSelectedDeviceToken() async throws -> GarminPairingCredential {
        try beginOperation()
        defer { isWorking = false }

        let identity = try activeIdentity()
        let binding = try requiredBinding(for: identity)
        guard availableDevicesUserID == identity.canonicalUserID,
              let selectedSummary = availableDevices.first(where: { $0.id == binding.deviceID }) else {
            throw GarminCloudError.deviceRefreshRequired
        }
        guard selectedSummary.tokenRevision < Int(Int32.max) else {
            throw GarminCloudError.invalidResponse
        }
        let session = try await auth.validCloudSession(expectedUserID: identity.rawUserID)
        try ensureIdentityIsCurrent(identity)
        try await recoverPendingRevocation(identity: identity, token: session.accessToken)
        let replacementNonce = try generateDeviceToken()
        let requestBody: [String: Any] = [
            "action": "rotateDeviceToken",
            "deviceId": binding.deviceID,
            "replacementNonce": replacementNonce,
            "expectedTokenRevision": selectedSummary.tokenRevision,
            "capabilityVersion": 3
        ]
        let object: [String: Any]
        do {
            object = try await requestRotation(
                identity: identity,
                token: session.accessToken,
                body: requestBody
            )
        } catch GarminCloudError.requestFailed(let statusCode, _) where statusCode == 409 {
            await refreshAfterRotationConflict(identity: identity, token: session.accessToken)
            throw GarminCloudError.rotationConflict
        }
        guard let status = object["status"] as? String,
              status == "rotated" || status == "already_rotated",
              exactInteger(object["capabilityVersion"]) == 3 else {
            throw GarminCloudError.invalidResponse
        }
        let result = try parsePairingCredential(object)
        guard result.summary.id == binding.deviceID,
              result.summary.tokenRevision == selectedSummary.tokenRevision + 1,
              result.capability.version == 3,
              result.capability.accountBinding == garminAccountBinding(
                  for: identity.canonicalUserID
              ),
              result.capability.deviceID == binding.deviceID,
              result.capability.nonce == replacementNonce else {
            throw GarminCloudError.invalidResponse
        }
        try ensureIdentityIsCurrent(identity)
        guard try bindingStore.binding(for: identity.canonicalUserID) == binding else {
            throw GarminCloudError.invalidBinding
        }
        replaceAvailableDevice(result.summary)
        lastMessage = "Garmin token rotated. Paste the new one into the same watch now."
        return result.credential
    }

    func revokeSelectedDevice() async throws {
        try beginOperation()
        defer { isWorking = false }

        let identity = try activeIdentity()
        let binding = try requiredBinding(for: identity)
        let session = try await auth.validCloudSession(expectedUserID: identity.rawUserID)
        try ensureIdentityIsCurrent(identity)
        try await recoverPendingRevocation(identity: identity, token: session.accessToken)
        let object = try await withAuthenticationRetry(
            identity: identity,
            fallbackToken: session.accessToken
        ) { token in
            try await self.requestObject(
                path: "/functions/v1/garmin-sync",
                method: "POST",
                token: token,
                body: ["action": "revokeDevice", "deviceId": binding.deviceID]
            )
        }
        guard let status = object["status"] as? String,
              status == "revoked" || status == "already_revoked" else {
            throw GarminCloudError.invalidResponse
        }
        try bindingStore.deleteBinding(for: identity.canonicalUserID)
        try ensureIdentityIsCurrent(identity)
        selectedDevice = nil
        availableDevices.removeAll { $0.id == binding.deviceID }
        lastMessage = "Garmin watch revoked. Reset GymApp on that watch before pairing it with a new device ID."
    }

    func clearLocalBindingData(for userID: String) throws {
        guard let canonical = canonicalUUID(userID) else {
            throw GarminCloudError.invalidBinding
        }
        try bindingStore.deleteAll(for: canonical)
        if canonicalUUID(auth.session?.cloud?.userID ?? "") == canonical {
            selectedDevice = nil
            availableDevices = []
            availableDevicesUserID = nil
        }
    }

    func submit(plan: GarminWorkoutPlan, clientRequestID: UUID) async throws {
        let planData = try GarminPlanValidator.validate(plan)
        let canonicalRequestID = try canonicalVersion4UUID(clientRequestID)
        try beginOperation()
        defer { isWorking = false }

        let identity = try activeIdentity()
        let binding = try requiredBinding(for: identity)
        let session = try await auth.validCloudSession(expectedUserID: identity.rawUserID)
        try ensureIdentityIsCurrent(identity)
        try await recoverPendingRevocation(identity: identity, token: session.accessToken)
        guard let planObject = try JSONSerialization.jsonObject(with: planData) as? [String: Any] else {
            throw GarminCloudError.invalidPlan
        }
        let requestBody: [String: Any] = [
            "p_device_id": binding.deviceID,
            "p_plan": planObject,
            "p_client_request_id": canonicalRequestID
        ]
        let object = try await withAuthenticationRetry(
            identity: identity,
            fallbackToken: session.accessToken
        ) { token in
            try await self.requestIdempotently(
                identity: identity,
                path: "/rest/v1/rpc/garmin_enqueue_plan",
                token: token,
                body: requestBody
            )
        }
        try ensureIdentityIsCurrent(identity)
        guard try bindingStore.binding(for: identity.canonicalUserID) == binding else {
            throw GarminCloudError.invalidBinding
        }
        guard let status = object["status"] as? String else {
            throw GarminCloudError.invalidResponse
        }
        if status == "conflict" {
            throw GarminCloudError.enqueueConflict
        }
        guard status == "queued" || status == "already_queued",
              let rawPlanID = object["planId"] as? String,
              canonicalUUID(rawPlanID) == rawPlanID,
              let planRevision = exactInteger(object["planRevision"]),
              (1 ... Int(Int32.max)).contains(planRevision),
              let planStatus = object["planStatus"] as? String,
              ["pending", "downloaded", "completed", "invalid", "superseded"].contains(planStatus),
              status != "queued" || planStatus == "pending" else {
            throw GarminCloudError.invalidResponse
        }
        lastMessage = status == "queued"
            ? "Plan queued. Open GymApp on the Garmin watch and choose CLOUD / SYNC."
            : "This workout was already submitted to the selected Garmin watch."
    }

    private struct ActiveIdentity {
        let rawUserID: String
        let canonicalUserID: String
    }

    private struct ParsedPairingResult {
        let summary: GarminDeviceSummary
        let credential: GarminPairingCredential
        let capability: GarminPairingCapability
    }

    private struct DeviceCreationResponse {
        let object: [String: Any]
        let idempotent: Bool
    }

    private enum DeviceCreationCompatibilityError: Error {
        case unavailable
    }

    private func beginOperation() throws {
        guard !isWorking else { throw GarminCloudError.busy }
        isWorking = true
    }

    private func activeIdentity() throws -> ActiveIdentity {
        guard let rawUserID = auth.session?.cloud?.userID,
              let canonicalUserID = canonicalUUID(rawUserID) else {
            if auth.session?.cloud == nil { throw AuthServiceError.notCloudAccount }
            throw GarminCloudError.invalidBinding
        }
        return ActiveIdentity(rawUserID: rawUserID, canonicalUserID: canonicalUserID)
    }

    private func ensureIdentityIsCurrent(_ identity: ActiveIdentity) throws {
        guard auth.session?.cloud?.userID == identity.rawUserID else {
            throw AuthServiceError.sessionChanged
        }
    }

    private func requiredBinding(for identity: ActiveIdentity) throws -> GarminDeviceBinding {
        guard let binding = try bindingStore.binding(for: identity.canonicalUserID),
              binding.userID == identity.canonicalUserID else {
            selectedDevice = nil
            throw GarminCloudError.pairingRequired
        }
        selectedDevice = binding
        return binding
    }

    private func reloadPublishedBinding(for session: AppAccountSession?) {
        guard let rawUserID = session?.cloud?.userID,
              let canonicalUserID = canonicalUUID(rawUserID) else {
            selectedDevice = nil
            return
        }
        do {
            selectedDevice = try bindingStore.binding(for: canonicalUserID)
        } catch {
            selectedDevice = nil
            lastMessage = GarminCloudError.invalidBinding.errorDescription
        }
    }

    private func recoverPendingRevocation(
        identity: ActiveIdentity,
        token: String
    ) async throws {
        guard let pending = try bindingStore.pendingRevocation(
            for: identity.canonicalUserID
        ) else { return }
        try ensureIdentityIsCurrent(identity)
        if pending.cleanupKind == .legacyRecovery {
            let object = try await withAuthenticationRetry(
                identity: identity,
                fallbackToken: token
            ) { accessToken in
                try await self.requestObject(
                    path: "/functions/v1/garmin-sync",
                    method: "POST",
                    token: accessToken,
                    body: ["action": "listDevices"]
                )
            }
            let devices = try parseDeviceList(object)
            try publishDevices(devices, for: identity)
            guard devices.isEmpty else {
                throw GarminCloudError.deviceCreationRecoveryRequired
            }
            // An authoritative empty owner list proves that no active legacy
            // create remains. Scrub any partially-retained raw record before
            // removing the durable recovery obligation.
            try bindingStore.clearPendingCreation(matching: pending)
            try bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
            return
        }
        guard await bestEffortRevoke(
            deviceID: pending.deviceID,
            identity: identity,
            token: token
        ) else {
            throw GarminCloudError.pendingRevocation
        }
        // A prior marker write may have succeeded while raw-record deletion
        // failed. Never clear the marker until that exact bearer is gone.
        try bindingStore.clearPendingCreation(matching: pending)
        try bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
        try ensureIdentityIsCurrent(identity)
    }

    private func reconcilePersistedCreation(
        _ creation: GarminPendingDeviceCreation,
        identity: ActiveIdentity,
        token: String
    ) async throws -> Bool {
        guard creation.legacyFallbackAttempted else { return false }

        // The released legacy endpoint generated its own ID/token, so an
        // outcome-unknown call cannot be replayed safely. An authoritative
        // owner list lets the user select/rotate a possible result without
        // issuing a second create. Keep the retry record until that explicit
        // selection (or account cleanup/expiry) supersedes it.
        let object = try await withAuthenticationRetry(
            identity: identity,
            fallbackToken: token
        ) { accessToken in
            try await self.requestObject(
                path: "/functions/v1/garmin-sync",
                method: "POST",
                token: accessToken,
                body: ["action": "listDevices"]
            )
        }
        let devices = try parseDeviceList(object)
        try publishDevices(devices, for: identity)
        if devices.isEmpty {
            let cleanup = GarminPendingRevocation(
                version: GarminDeviceBinding.currentVersion,
                userID: identity.canonicalUserID,
                deviceID: creation.deviceID,
                cleanupKind: .legacyRecovery
            )
            try bindingStore.clearPendingCreation(matching: cleanup)
            return true
        }
        throw GarminCloudError.deviceCreationRecoveryRequired
    }

    private func requestDeviceCreation(
        _ creation: GarminPendingDeviceCreation,
        identity: ActiveIdentity,
        token: String
    ) async throws -> DeviceCreationResponse {
        let body: [String: Any] = [
            "action": "createDeviceIdempotent",
            "requestId": creation.requestID,
            "deviceId": creation.deviceID,
            "deviceNonce": creation.deviceToken,
            "displayName": creation.displayName,
            "capabilityVersion": 3
        ]

        do {
            let object = try await requestObject(
                path: "/functions/v1/garmin-sync",
                method: "POST",
                token: token,
                body: body,
                recognizeUnavailableIdempotentCreation: true
            )
            return DeviceCreationResponse(object: object, idempotent: true)
        } catch DeviceCreationCompatibilityError.unavailable {
            try ensureIdentityIsCurrent(identity)
            let durableCreation = try bindingStore.pendingCreation(
                for: identity.canonicalUserID
            )
            guard durableCreation?.requestID == creation.requestID,
                  durableCreation?.deviceID == creation.deviceID,
                  durableCreation?.deviceToken == creation.deviceToken,
                  durableCreation?.displayName == creation.displayName,
                  durableCreation?.legacyFallbackAttempted == false else {
                throw GarminCloudError.deviceCreationRecoveryRequired
            }
            let legacyCreation = GarminPendingDeviceCreation(
                version: creation.version,
                userID: creation.userID,
                requestID: creation.requestID,
                deviceID: creation.deviceID,
                deviceToken: creation.deviceToken,
                displayName: creation.displayName,
                createdAt: creation.createdAt,
                legacyFallbackAttempted: true
            )
            // Persist the irreversible compatibility transition before the
            // old endpoint. That endpoint is deliberately never retried after
            // an outcome-unknown result.
            try bindingStore.save(pendingCreation: legacyCreation)
            let object: [String: Any]
            do {
                object = try await requestObject(
                    path: "/functions/v1/garmin-sync",
                    method: "POST",
                    token: token,
                    body: [
                        "action": "createDevice",
                        "displayName": creation.displayName,
                        "capabilityVersion": 3
                    ]
                )
            } catch let error as GarminCloudError {
                if case .requestFailed(let statusCode, _) = error,
                   statusCode == 401 || statusCode == 403 {
                    // Authentication is rejected by the old Edge handler before
                    // its database creator runs, so the refreshed-auth retry may
                    // safely attempt the same compatibility transition again.
                    try? bindingStore.save(pendingCreation: creation)
                }
                throw error
            }
            return DeviceCreationResponse(object: object, idempotent: false)
        } catch let error as URLError where error.code != .cancelled {
            try ensureIdentityIsCurrent(identity)
            return try await retryExactDeviceCreation(
                body: body,
                identity: identity,
                token: token
            )
        } catch GarminCloudError.requestFailed(let statusCode, _)
            where (500 ... 599).contains(statusCode) {
            try ensureIdentityIsCurrent(identity)
            return try await retryExactDeviceCreation(
                body: body,
                identity: identity,
                token: token
            )
        }
    }

    private func retryExactDeviceCreation(
        body: [String: Any],
        identity: ActiveIdentity,
        token: String
    ) async throws -> DeviceCreationResponse {
        do {
            let object = try await requestObject(
                path: "/functions/v1/garmin-sync",
                method: "POST",
                token: token,
                body: body,
                recognizeUnavailableIdempotentCreation: true
            )
            return DeviceCreationResponse(object: object, idempotent: true)
        } catch DeviceCreationCompatibilityError.unavailable {
            // The first request had an unknown outcome; falling back to the
            // non-idempotent endpoint now could create a second watch.
            throw GarminCloudError.deviceCreationRecoveryRequired
        }
    }

    private func persistCreatedDevice(
        _ result: ParsedPairingResult,
        identity: ActiveIdentity,
        token: String,
        creationRequestID: String,
        clearPendingCreation: Bool
    ) async throws {
        do {
            try bindingStore.savePendingRevocation(
                userID: identity.canonicalUserID,
                deviceID: result.summary.id,
                creationRequestID: creationRequestID
            )
        } catch {
            if await bestEffortRevoke(
                deviceID: result.summary.id,
                identity: identity,
                token: token
            ) {
                try? clearConfirmedCreationCleanup(
                    userID: identity.canonicalUserID,
                    deviceID: result.summary.id,
                    creationRequestID: creationRequestID,
                    clearPendingCreation: clearPendingCreation
                )
            }
            throw GarminCloudError.bindingPersistenceFailed
        }

        do {
            try ensureIdentityIsCurrent(identity)
        } catch {
            if await bestEffortRevoke(
                deviceID: result.summary.id,
                identity: identity,
                token: token
            ) {
                try? clearConfirmedCreationCleanup(
                    userID: identity.canonicalUserID,
                    deviceID: result.summary.id,
                    creationRequestID: creationRequestID,
                    clearPendingCreation: clearPendingCreation
                )
            }
            throw error
        }

        let binding = GarminDeviceBinding(
            version: GarminDeviceBinding.currentVersion,
            userID: identity.canonicalUserID,
            deviceID: result.summary.id
        )
        do {
            try bindingStore.save(binding: binding)
            try clearConfirmedCreationCleanup(
                userID: identity.canonicalUserID,
                deviceID: result.summary.id,
                creationRequestID: creationRequestID,
                clearPendingCreation: clearPendingCreation
            )
        } catch {
            try? bindingStore.deleteBinding(for: identity.canonicalUserID)
            if await bestEffortRevoke(
                deviceID: result.summary.id,
                identity: identity,
                token: token
            ) {
                try? clearConfirmedCreationCleanup(
                    userID: identity.canonicalUserID,
                    deviceID: result.summary.id,
                    creationRequestID: creationRequestID,
                    clearPendingCreation: clearPendingCreation
                )
            }
            throw GarminCloudError.bindingPersistenceFailed
        }
        do {
            try ensureIdentityIsCurrent(identity)
        } catch {
            try? bindingStore.savePendingRevocation(
                userID: identity.canonicalUserID,
                deviceID: result.summary.id,
                creationRequestID: creationRequestID
            )
            if await bestEffortRevoke(
                deviceID: result.summary.id,
                identity: identity,
                token: token
            ) {
                try? bindingStore.deleteBinding(for: identity.canonicalUserID)
                try? clearConfirmedCreationCleanup(
                    userID: identity.canonicalUserID,
                    deviceID: result.summary.id,
                    creationRequestID: creationRequestID,
                    clearPendingCreation: clearPendingCreation
                )
            }
            throw error
        }
        selectedDevice = binding
        replaceAvailableDevice(result.summary)
    }

    private func clearConfirmedCreationCleanup(
        userID: String,
        deviceID: String,
        creationRequestID: String,
        clearPendingCreation: Bool
    ) throws {
        let expected = GarminPendingRevocation(
            version: GarminDeviceBinding.currentVersion,
            userID: userID,
            deviceID: deviceID,
            creationRequestID: creationRequestID
        )
        if clearPendingCreation {
            // Exact owner/request scrubbing must precede marker removal. This
            // also covers the legacy endpoint's server-generated device ID.
            try bindingStore.clearPendingCreation(matching: expected)
        }
        if let pending = try bindingStore.pendingRevocation(for: userID) {
            guard pending == expected else { throw GarminCloudError.pendingRevocation }
            try bindingStore.clearPendingRevocation(for: userID)
        }
    }

    private func bestEffortRevoke(
        deviceID: String,
        identity: ActiveIdentity,
        token: String
    ) async -> Bool {
        do {
            let object = try await withAuthenticationRetry(
                identity: identity,
                fallbackToken: token
            ) { accessToken in
                try await self.requestObject(
                    path: "/functions/v1/garmin-sync",
                    method: "POST",
                    token: accessToken,
                    body: ["action": "revokeDevice", "deviceId": deviceID]
                )
            }
            guard let status = object["status"] as? String else { return false }
            return status == "revoked" || status == "already_revoked"
        } catch {
            return false
        }
    }

    private func replaceAvailableDevice(_ device: GarminDeviceSummary) {
        if let rawUserID = auth.session?.cloud?.userID,
           let userID = canonicalUUID(rawUserID) {
            availableDevicesUserID = userID
        }
        availableDevices.removeAll { $0.id == device.id }
        availableDevices.insert(device, at: 0)
    }

    private func parseDeviceList(_ object: [String: Any]) throws -> [GarminDeviceSummary] {
        guard let rawDevices = object["devices"] as? [Any], rawDevices.count <= 5 else {
            throw GarminCloudError.invalidResponse
        }
        let devices = try rawDevices.map(parseDeviceSummary)
        guard Set(devices.map(\.id)).count == devices.count else {
            throw GarminCloudError.invalidResponse
        }
        return devices.sorted {
            if $0.createdAt != $1.createdAt {
                return ($0.createdAt ?? "") > ($1.createdAt ?? "")
            }
            return $0.id > $1.id
        }
    }

    private func publishDevices(
        _ devices: [GarminDeviceSummary],
        for identity: ActiveIdentity
    ) throws {
        try ensureIdentityIsCurrent(identity)
        availableDevices = devices
        availableDevicesUserID = identity.canonicalUserID

        let binding = try bindingStore.binding(for: identity.canonicalUserID)
        if let binding, devices.contains(where: { $0.id == binding.deviceID }) {
            selectedDevice = binding
        } else if binding != nil {
            try bindingStore.deleteBinding(for: identity.canonicalUserID)
            selectedDevice = nil
        }
    }

    private func requestRotation(
        identity: ActiveIdentity,
        token: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        try await withAuthenticationRetry(
            identity: identity,
            fallbackToken: token
        ) { accessToken in
            try await self.requestIdempotently(
                identity: identity,
                path: "/functions/v1/garmin-sync",
                token: accessToken,
                body: body
            )
        }
    }

    private func requestIdempotently(
        identity: ActiveIdentity,
        path: String,
        token: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        do {
            return try await requestObject(
                path: path,
                method: "POST",
                token: token,
                body: body
            )
        } catch let error as URLError where error.code != .cancelled {
            try ensureIdentityIsCurrent(identity)
            return try await requestObject(
                path: path,
                method: "POST",
                token: token,
                body: body
            )
        } catch GarminCloudError.requestFailed(let statusCode, _)
            where (500 ... 599).contains(statusCode) {
            // The database contracts make an identical body safe after an
            // outcome-unknown gateway/server failure. Never retry 4xx/409/429.
            try ensureIdentityIsCurrent(identity)
            return try await requestObject(
                path: path,
                method: "POST",
                token: token,
                body: body
            )
        }
    }

    private func refreshAfterRotationConflict(
        identity: ActiveIdentity,
        token: String
    ) async {
        do {
            try ensureIdentityIsCurrent(identity)
            availableDevices = []
            availableDevicesUserID = nil
            let object = try await withAuthenticationRetry(
                identity: identity,
                fallbackToken: token
            ) { accessToken in
                try await self.requestObject(
                    path: "/functions/v1/garmin-sync",
                    method: "POST",
                    token: accessToken,
                    body: ["action": "listDevices"]
                )
            }
            try publishDevices(parseDeviceList(object), for: identity)
        } catch {
            // Keep the durable selected UUID, but never retain a stale token revision.
        }
    }

    private func withAuthenticationRetry<T>(
        identity: ActiveIdentity,
        fallbackToken: String,
        operation: (String) async throws -> T
    ) async throws -> T {
        let initialSession: CloudAccountSession?
        let initialToken: String
        if let current = auth.session?.cloud,
           current.userID == identity.rawUserID {
            initialSession = current
            initialToken = current.accessToken
        } else {
            initialSession = nil
            // Late cleanup for an account that changed while a request was in
            // flight must never borrow the replacement account's bearer token.
            initialToken = fallbackToken
        }

        do {
            return try await operation(initialToken)
        } catch GarminCloudError.requestFailed(let statusCode, _)
                    where statusCode == 401 || statusCode == 403 {
            guard let initialSession,
                  auth.session?.cloud == initialSession else {
                throw AuthServiceError.sessionChanged
            }
            let refreshed = try await auth.validCloudSession(
                expectedUserID: identity.rawUserID,
                forceRefresh: true
            )
            try ensureIdentityIsCurrent(identity)
            return try await operation(refreshed.accessToken)
        }
    }

    private func generateDeviceToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw GarminCloudError.invalidRequest
        }
        let alphabet = Array("0123456789abcdef".utf8)
        var encoded = [UInt8]()
        encoded.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            encoded.append(alphabet[Int(byte >> 4)])
            encoded.append(alphabet[Int(byte & 0x0f)])
        }
        return String(decoding: encoded, as: UTF8.self)
    }

    private func canonicalVersion4UUID(_ value: UUID) throws -> String {
        let canonical = value.uuidString.lowercased()
        let versionIndex = canonical.index(canonical.startIndex, offsetBy: 14)
        let variantIndex = canonical.index(canonical.startIndex, offsetBy: 19)
        guard canonical[versionIndex] == "4",
              "89ab".contains(canonical[variantIndex]) else {
            throw GarminCloudError.invalidRequest
        }
        return canonical
    }

    private func parsePairingCredential(_ object: [String: Any]) throws -> ParsedPairingResult {
        guard let raw = object["device"] as? [String: Any],
              let token = raw["device_token"] as? String,
              let capability = parseGarminPairingCapability(token) else {
            throw GarminCloudError.invalidResponse
        }
        let summary = try parseDeviceSummary(raw)
        if let capabilityDeviceID = capability.deviceID,
           capabilityDeviceID != summary.id {
            throw GarminCloudError.invalidResponse
        }
        return ParsedPairingResult(
            summary: summary,
            credential: GarminPairingCredential(
                id: summary.id,
                deviceToken: token,
                displayName: summary.displayName
            ),
            capability: capability
        )
    }

    private func parseDeviceSummary(_ value: Any) throws -> GarminDeviceSummary {
        guard let object = value as? [String: Any],
              let rawID = object["id"] as? String,
              let id = canonicalUUID(rawID),
              rawID == id,
              let displayName = object["display_name"] as? String,
              isValidDisplayName(displayName),
              exactInteger(object["binding_version"]) == GarminDeviceBinding.currentVersion,
              let tokenRevision = exactInteger(object["token_revision"]),
              (1 ... Int(Int32.max)).contains(tokenRevision),
              validOptionalServerString(object["created_at"], maximumBytes: 64),
              validOptionalServerString(object["last_seen_at"], maximumBytes: 64) else {
            throw GarminCloudError.invalidResponse
        }
        return GarminDeviceSummary(
            id: id,
            displayName: displayName,
            createdAt: object["created_at"] as? String,
            lastSeenAt: object["last_seen_at"] as? String,
            bindingVersion: GarminDeviceBinding.currentVersion,
            tokenRevision: tokenRevision
        )
    }

    private func isValidDisplayName(_ value: String) -> Bool {
        (1 ... 80).contains(value.count) &&
            value.utf8.count <= 320 &&
            !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private func validOptionalServerString(_ value: Any?, maximumBytes: Int) -> Bool {
        guard let value, !(value is NSNull) else { return true }
        guard let text = value as? String, text.utf8.count <= maximumBytes else { return false }
        return !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private func exactInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return number.intValue
    }

    private func requestObject(
        path: String,
        method: String,
        token: String,
        prefer: String? = nil,
        body: Any,
        recognizeUnavailableIdempotentCreation: Bool = false
    ) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: GymAppConfiguration.supabaseURL) else {
            throw GarminCloudError.invalidResponse
        }
        guard !token.isEmpty,
              token.utf8.count <= Self.maximumAccessTokenBytes,
              token.unicodeScalars.allSatisfy({ (0x21 ... 0x7e).contains($0.value) }),
              JSONSerialization.isValidJSONObject(body) else {
            throw GarminCloudError.invalidRequest
        }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        guard bodyData.count <= Self.maximumRequestBodyBytes else {
            throw GarminCloudError.invalidRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(GymAppConfiguration.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = bodyData

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await BoundedURLSessionLoader.data(
                for: request,
                using: urlSession,
                successLimit: Self.maximumResponseBodyBytes,
                errorLimit: Self.maximumErrorResponseBodyBytes
            )
        } catch BoundedURLSessionError.responseTooLarge(let statusCode?)
                    where statusCode == 401 || statusCode == 403 {
            throw GarminCloudError.requestFailed(
                statusCode: statusCode,
                message: "Garmin cloud sync failed (HTTP \(statusCode))."
            )
        } catch BoundedURLSessionError.responseTooLarge(let statusCode?)
            where (500 ... 599).contains(statusCode) {
            throw GarminCloudError.requestFailed(
                statusCode: statusCode,
                message: "Garmin cloud sync failed (HTTP \(statusCode))."
            )
        } catch is BoundedURLSessionError {
            throw GarminCloudError.invalidResponse
        }

        let decodedObject = data.isEmpty
            ? nil
            : (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            if recognizeUnavailableIdempotentCreation,
               let decodedObject,
               decodedObject.count == 1,
               let error = decodedObject["error"] as? String,
               (http.statusCode == 400 && error == "Unknown action" ||
                http.statusCode == 501 && error == "Idempotent device creation unavailable") {
                throw DeviceCreationCompatibilityError.unavailable
            }
            throw GarminCloudError.requestFailed(
                statusCode: http.statusCode,
                message: decodedObject.flatMap(safeServerError) ??
                    "Garmin cloud sync failed (HTTP \(http.statusCode))."
            )
        }
        if data.isEmpty { return [:] }
        guard let decodedObject else { throw GarminCloudError.invalidResponse }
        return decodedObject
    }

    private func safeServerError(in object: [String: Any]) -> String? {
        guard let value = object["error"] as? String,
              !value.isEmpty,
              value.utf8.count <= Self.maximumServerErrorBytes,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.value >= 0x20 && scalar.value != 0x7f
              }) else {
            return nil
        }
        return value
    }
}
