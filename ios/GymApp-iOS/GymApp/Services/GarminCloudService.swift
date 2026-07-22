import Combine
import Foundation
import Security

struct GarminPlanSet: Codable, Equatable, Sendable {
    let weight: Double
    let reps: Int
    let orderIndex: Int
}

struct GarminPlanExercise: Codable, Equatable, Sendable {
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

/// Ephemeral one-time credential. Deliberately not Codable: only the nonsecret
/// selected-device UUID is persisted, never the raw Garmin bearer token.
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

struct GarminPendingRevocation: Codable, Equatable, Sendable {
    let version: Int
    let userID: String
    let deviceID: String
}

struct GarminDeviceBindingStore {
    private static let bindingAccountPrefix = "selected-device-v2."
    private static let pendingRevocationAccountPrefix = "pending-revocation-v2."
    private static let maximumRecordBytes = 1_024

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
              canonicalUUID(value.deviceID) == value.deviceID else {
            throw GarminCloudError.invalidBinding
        }
        return value
    }

    func savePendingRevocation(userID: String, deviceID: String) throws {
        let userID = try canonicalUserID(userID)
        guard canonicalUUID(deviceID) == deviceID else {
            throw GarminCloudError.invalidBinding
        }
        let data = try encoder.encode(
            GarminPendingRevocation(
                version: GarminDeviceBinding.currentVersion,
                userID: userID,
                deviceID: deviceID
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
}

private func canonicalUUID(_ value: String) -> String? {
    guard value.utf8.count == 36, let uuid = UUID(uuidString: value) else { return nil }
    return uuid.uuidString.lowercased()
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

    init(
        auth: AuthService,
        urlSession: URLSession = .shared,
        bindingStore: GarminDeviceBindingStore = GarminDeviceBindingStore()
    ) {
        self.auth = auth
        self.urlSession = urlSession
        self.bindingStore = bindingStore
        reloadPublishedBinding(for: auth.session)
        sessionSubscription = auth.$session
            .removeDuplicates(by: { $0?.storageKey == $1?.storageKey })
            .sink { [weak self] session in
                MainActor.assumeIsolated {
                    self?.availableDevices = []
                    self?.availableDevicesUserID = nil
                    self?.lastMessage = nil
                    self?.reloadPublishedBinding(for: session)
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
        try bindingStore.save(binding: binding)
        selectedDevice = binding
        lastMessage = "Selected Garmin watch: \(device.displayName)."
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
        let object = try await withAuthenticationRetry(
            identity: identity,
            fallbackToken: session.accessToken
        ) { token in
            try await self.requestObject(
                path: "/functions/v1/garmin-sync",
                method: "POST",
                token: token,
                body: [
                    "action": "createDevice",
                    "displayName": cleanDisplayName,
                    "capabilityVersion": 2
                ]
            )
        }
        let result = try parsePairingCredential(object)
        try await persistCreatedDevice(
            result,
            identity: identity,
            token: session.accessToken
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
        let replacementToken = try generateDeviceToken()
        let requestBody: [String: Any] = [
            "action": "rotateDeviceToken",
            "deviceId": binding.deviceID,
            "replacementToken": replacementToken,
            "expectedTokenRevision": selectedSummary.tokenRevision,
            "capabilityVersion": 2
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
              status == "rotated" || status == "already_rotated" else {
            throw GarminCloudError.invalidResponse
        }
        let result = try parsePairingCredential(object)
        guard result.summary.id == binding.deviceID,
              result.summary.tokenRevision == selectedSummary.tokenRevision + 1,
              result.credential.deviceToken == replacementToken else {
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
        guard await bestEffortRevoke(
            deviceID: pending.deviceID,
            identity: identity,
            token: token
        ) else {
            throw GarminCloudError.pendingRevocation
        }
        try bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
        try ensureIdentityIsCurrent(identity)
    }

    private func persistCreatedDevice(
        _ result: ParsedPairingResult,
        identity: ActiveIdentity,
        token: String
    ) async throws {
        do {
            try bindingStore.savePendingRevocation(
                userID: identity.canonicalUserID,
                deviceID: result.summary.id
            )
        } catch {
            _ = await bestEffortRevoke(
                deviceID: result.summary.id,
                identity: identity,
                token: token
            )
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
                try? bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
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
            try bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
        } catch {
            try? bindingStore.deleteBinding(for: identity.canonicalUserID)
            if await bestEffortRevoke(
                deviceID: result.summary.id,
                identity: identity,
                token: token
            ) {
                try? bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
            }
            throw GarminCloudError.bindingPersistenceFailed
        }
        do {
            try ensureIdentityIsCurrent(identity)
        } catch {
            try? bindingStore.savePendingRevocation(
                userID: identity.canonicalUserID,
                deviceID: result.summary.id
            )
            if await bestEffortRevoke(
                deviceID: result.summary.id,
                identity: identity,
                token: token
            ) {
                try? bindingStore.deleteBinding(for: identity.canonicalUserID)
                try? bindingStore.clearPendingRevocation(for: identity.canonicalUserID)
            }
            throw error
        }
        selectedDevice = binding
        replaceAvailableDevice(result.summary)
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
              token.utf8.count == 64,
              token.unicodeScalars.allSatisfy({ scalar in
                  let value = Int(scalar.value)
                  return (48 ... 57).contains(value) || (97 ... 102).contains(value)
              }) else {
            throw GarminCloudError.invalidResponse
        }
        let summary = try parseDeviceSummary(raw)
        return ParsedPairingResult(
            summary: summary,
            credential: GarminPairingCredential(
                id: summary.id,
                deviceToken: token,
                displayName: summary.displayName
            )
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
        body: Any
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
