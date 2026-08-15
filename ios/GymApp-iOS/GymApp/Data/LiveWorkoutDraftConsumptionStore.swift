import CoreFoundation
import Foundation

enum LiveWorkoutDraftConsumptionError: LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case invalidState
    case accountMismatch
    case sessionMismatch
    case pendingConsumption

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "The pending live-workout draft could not be opened safely."
        case .invalidState:
            "The pending live-workout draft state is invalid."
        case .accountMismatch, .sessionMismatch:
            "This pending live-workout draft belongs to another signed-in session."
        case .pendingConsumption:
            "Resolve the pending live-workout draft before sending another one."
        }
    }
}

enum LiveWorkoutDraftConsumptionPhase: String, Codable, Sendable {
    case preparing
    case confirmed
}

struct LiveWorkoutDraftSendRequest: Equatable, Sendable {
    let recipientProfileID: String
    let friendshipID: String
    let friendshipRevision: Int
    let draftFingerprint: String
}

struct LiveWorkoutDraftConsumption: Codable, Equatable, Sendable {
    let version: Int
    let userID: String
    let sessionID: String
    let operationID: UUID
    let roomID: String?
    let phase: LiveWorkoutDraftConsumptionPhase
    let recipientProfileID: String
    let friendshipID: String
    let friendshipRevision: Int
    let draftFingerprint: String
    let createdAt: Date
    let expiresAt: Date

    private enum CodingKeys: String, CodingKey {
        case version
        case userID
        case sessionID
        case operationID
        case roomID
        case phase
        case recipientProfileID
        case friendshipID
        case friendshipRevision
        case draftFingerprint
        case createdAt
        case expiresAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(userID, forKey: .userID)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(operationID, forKey: .operationID)
        if let roomID {
            try container.encode(roomID, forKey: .roomID)
        } else {
            try container.encodeNil(forKey: .roomID)
        }
        try container.encode(phase, forKey: .phase)
        try container.encode(recipientProfileID, forKey: .recipientProfileID)
        try container.encode(friendshipID, forKey: .friendshipID)
        try container.encode(friendshipRevision, forKey: .friendshipRevision)
        try container.encode(draftFingerprint, forKey: .draftFingerprint)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(expiresAt, forKey: .expiresAt)
    }
}

@MainActor
final class LiveWorkoutDraftConsumptionStore {
    private(set) var consumption: LiveWorkoutDraftConsumption?

    let accountStorageKey: String
    let storageURL: URL

    private let fileManager: FileManager
    private let envelopeWriter: (Data, URL) throws -> Void
    private var writesBlocked = false

    private struct Envelope: Codable {
        let schemaVersion: Int
        let accountStorageKey: String
        let savedAt: Date
        let consumption: LiveWorkoutDraftConsumption?

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case accountStorageKey
            case savedAt
            case consumption
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(accountStorageKey, forKey: .accountStorageKey)
            try container.encode(savedAt, forKey: .savedAt)
            if let consumption {
                try container.encode(consumption, forKey: .consumption)
            } else {
                try container.encodeNil(forKey: .consumption)
            }
        }
    }

    private static let schemaVersion = 1
    private static let maximumFileBytes = 4 * 1_024
    private static let maximumDuration: TimeInterval = 9 * 24 * 60 * 60
    private static let uuidPattern = try! NSRegularExpression(
        pattern: #"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
        options: [.caseInsensitive]
    )
    private static let roomPattern = try! NSRegularExpression(pattern: #"^lr_[0-9a-f]{32}$"#)
    private static let fingerprintPattern = try! NSRegularExpression(pattern: #"^[0-9a-f]{64}$"#)

    init(
        accountStorageKey: String,
        workoutStorageURL: URL,
        fileManager: FileManager = .default,
        envelopeWriter: ((Data, URL) throws -> Void)? = nil
    ) {
        self.accountStorageKey = accountStorageKey
        self.storageURL = Self.storageURL(forWorkoutStorageURL: workoutStorageURL)
        self.fileManager = fileManager
        self.envelopeWriter = envelopeWriter ?? Self.writeEnvelopeAtomically
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.excludeFromBackup(storageURL.deletingLastPathComponent())
            consumption = try Self.load(
                accountStorageKey: accountStorageKey,
                storageURL: storageURL,
                fileManager: fileManager
            )
        } catch {
            consumption = nil
            writesBlocked = true
        }
    }

    static func storageURL(forWorkoutStorageURL workoutStorageURL: URL) -> URL {
        workoutStorageURL
            .deletingPathExtension()
            .appendingPathExtension("live-draft-consumption.json")
    }

    func bind(to context: LiveWorkoutSessionContext) throws {
        guard !writesBlocked else { throw LiveWorkoutDraftConsumptionError.storageUnavailable }
        guard let current = consumption else { return }
        guard current.userID == context.userID else {
            throw LiveWorkoutDraftConsumptionError.accountMismatch
        }
        guard current.sessionID == context.sessionID else {
            throw LiveWorkoutDraftConsumptionError.sessionMismatch
        }
    }

    func current(
        context: LiveWorkoutSessionContext,
        now: Date = Date()
    ) throws -> LiveWorkoutDraftConsumption? {
        try bind(to: context)
        try discardExpired(now: now)
        return consumption
    }

    func prepare(
        _ candidate: LiveWorkoutDraftConsumption,
        context: LiveWorkoutSessionContext,
        now: Date = Date()
    ) throws {
        guard !writesBlocked else { throw LiveWorkoutDraftConsumptionError.storageUnavailable }
        try bind(to: context)
        try discardExpired(now: now)
        try Self.validate(candidate)
        guard candidate.userID == context.userID,
              candidate.sessionID == context.sessionID,
              candidate.phase == .preparing,
              candidate.roomID == nil,
              candidate.expiresAt > now else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
        if let current = consumption {
            guard current.operationID == candidate.operationID,
                  current.phase == .preparing,
                  current.recipientProfileID == candidate.recipientProfileID,
                  current.friendshipID == candidate.friendshipID,
                  current.friendshipRevision == candidate.friendshipRevision,
                  current.draftFingerprint == candidate.draftFingerprint else {
                throw LiveWorkoutDraftConsumptionError.pendingConsumption
            }
            // Retrying the same in-memory idempotency key must retain the first durable
            // timestamp and expiry rather than moving the recovery window forward.
            return
        }
        try persist(candidate)
        consumption = candidate
    }

    @discardableResult
    func confirm(
        operationID: UUID,
        roomID: String,
        context: LiveWorkoutSessionContext,
        now: Date = Date()
    ) throws -> LiveWorkoutDraftConsumption {
        guard !writesBlocked else { throw LiveWorkoutDraftConsumptionError.storageUnavailable }
        try bind(to: context)
        try discardExpired(now: now)
        guard let current = consumption,
              current.operationID == operationID,
              current.userID == context.userID,
              current.sessionID == context.sessionID,
              current.expiresAt > now else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
        let confirmed = LiveWorkoutDraftConsumption(
            version: current.version,
            userID: current.userID,
            sessionID: current.sessionID,
            operationID: current.operationID,
            roomID: roomID,
            phase: .confirmed,
            recipientProfileID: current.recipientProfileID,
            friendshipID: current.friendshipID,
            friendshipRevision: current.friendshipRevision,
            draftFingerprint: current.draftFingerprint,
            createdAt: current.createdAt,
            expiresAt: current.expiresAt
        )
        try Self.validate(confirmed)
        if current != confirmed {
            try persist(confirmed)
            consumption = confirmed
        }
        return confirmed
    }

    func clear(
        operationID: UUID,
        roomID: String? = nil,
        context: LiveWorkoutSessionContext
    ) throws {
        guard !writesBlocked else { throw LiveWorkoutDraftConsumptionError.storageUnavailable }
        try bind(to: context)
        guard let current = consumption else { return }
        guard current.operationID == operationID,
              roomID == nil || current.roomID == roomID else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
        try persist(nil)
        consumption = nil
    }

    func clearAfterSessionChange(
        _ previous: LiveWorkoutDraftConsumption,
        context: LiveWorkoutSessionContext
    ) throws {
        guard !writesBlocked else { throw LiveWorkoutDraftConsumptionError.storageUnavailable }
        guard previous.userID == context.userID,
              previous.sessionID != context.sessionID,
              consumption == previous else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
        // Never apply an old session's marker to the new session's editor. Removing only
        // the journal entry leaves every draft untouched while allowing future sends.
        try persist(nil)
        consumption = nil
    }

    private func discardExpired(now: Date) throws {
        guard let current = consumption, current.expiresAt <= now else { return }
        try persist(nil)
        consumption = nil
    }

    private func persist(_ value: LiveWorkoutDraftConsumption?) throws {
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            accountStorageKey: accountStorageKey,
            savedAt: Date(),
            consumption: value
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumFileBytes else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
        do {
            try envelopeWriter(data, storageURL)
            try Self.excludeFromBackup(storageURL)
        } catch {
            writesBlocked = true
            throw LiveWorkoutDraftConsumptionError.storageUnavailable
        }
    }

    private static func load(
        accountStorageKey: String,
        storageURL: URL,
        fileManager: FileManager
    ) throws -> LiveWorkoutDraftConsumption? {
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        let values = try storageURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= maximumFileBytes else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
        let data = try Data(contentsOf: storageURL, options: [.mappedIfSafe])
        try validateJSONShape(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.schemaVersion == schemaVersion,
              envelope.accountStorageKey == accountStorageKey else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
        if let consumption = envelope.consumption { try validate(consumption) }
        return envelope.consumption
    }

    private static func validateJSONShape(_ data: Data) throws {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let root = raw as? [String: Any],
              Set(root.keys) == Set(["schemaVersion", "accountStorageKey", "savedAt", "consumption"]),
              strictInteger(root["schemaVersion"]) == schemaVersion,
              root["accountStorageKey"] is String,
              strictFiniteNumber(root["savedAt"]) != nil else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
        if root["consumption"] is NSNull { return }
        guard let consumption = root["consumption"] as? [String: Any],
              Set(consumption.keys) == Set([
                "version", "userID", "sessionID", "operationID", "roomID", "phase",
                "recipientProfileID", "friendshipID", "friendshipRevision",
                "draftFingerprint", "createdAt", "expiresAt"
              ]),
              strictInteger(consumption["version"]) == 1,
              consumption["userID"] is String,
              consumption["sessionID"] is String,
              consumption["operationID"] is String,
              consumption["roomID"] is String || consumption["roomID"] is NSNull,
              consumption["phase"] is String,
              consumption["recipientProfileID"] is String,
              consumption["friendshipID"] is String,
              strictInteger(consumption["friendshipRevision"]) != nil,
              consumption["draftFingerprint"] is String,
              strictFiniteNumber(consumption["createdAt"]) != nil,
              strictFiniteNumber(consumption["expiresAt"]) != nil else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    private static func strictFiniteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func validate(_ value: LiveWorkoutDraftConsumption) throws {
        guard value.version == 1,
              matches(uuidPattern, value.userID),
              matches(uuidPattern, value.sessionID),
              SocialPayloadParser.isValidProfileID(value.recipientProfileID),
              SocialPayloadParser.isValidFriendshipID(value.friendshipID),
              (1 ... Int(Int32.max)).contains(value.friendshipRevision),
              matches(fingerprintPattern, value.draftFingerprint),
              value.expiresAt > value.createdAt,
              value.expiresAt.timeIntervalSince(value.createdAt) <= maximumDuration,
              (value.phase == .preparing
                ? value.roomID == nil
                : value.roomID.map { matches(roomPattern, $0) } == true) else {
            throw LiveWorkoutDraftConsumptionError.invalidState
        }
    }

    private static func matches(_ pattern: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        return pattern.firstMatch(in: value, range: range)?.range == range
    }

    private static func writeEnvelopeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    private static func excludeFromBackup(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
