import CoreFoundation
import Foundation

enum LiveWorkoutSlotReservationError: LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case invalidState
    case accountMismatch
    case sessionMismatch
    case slotReserved

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "The reserved live-workout slot could not be opened safely."
        case .invalidState:
            "The reserved live-workout slot is invalid."
        case .accountMismatch, .sessionMismatch:
            "This live-workout slot belongs to another signed-in session."
        case .slotReserved:
            "Resolve the pending live workout before starting another workout."
        }
    }
}

enum LiveWorkoutSlotPhase: String, Codable, Sendable {
    case preparing
    case waiting
    case active
}

struct LiveWorkoutSlotReservation: Codable, Equatable, Sendable {
    let version: Int
    let userID: String
    let sessionID: String
    let role: LiveWorkoutRole
    let operationID: UUID
    let roomID: String?
    let phase: LiveWorkoutSlotPhase
    let createdAt: Date
    let expiresAt: Date
}

@MainActor
final class LiveWorkoutSlotReservationStore {
    private(set) var reservation: LiveWorkoutSlotReservation?

    let accountStorageKey: String
    let storageURL: URL

    private let fileManager: FileManager
    private let envelopeWriter: (Data, URL) throws -> Void
    private var writesBlocked = false

    private struct Envelope: Codable {
        let schemaVersion: Int
        let accountStorageKey: String
        let savedAt: Date
        let reservation: LiveWorkoutSlotReservation?
    }

    private static let schemaVersion = 1
    private static let maximumFileBytes = 2 * 1_024
    private static let maximumDuration: TimeInterval = 9 * 24 * 60 * 60
    private static let roomPattern = try! NSRegularExpression(pattern: #"^lr_[0-9a-f]{32}$"#)
    private static let uuidPattern = try! NSRegularExpression(
        pattern: #"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
        options: [.caseInsensitive]
    )

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
            reservation = try Self.load(
                accountStorageKey: accountStorageKey,
                storageURL: storageURL,
                fileManager: fileManager
            )
        } catch {
            reservation = nil
            writesBlocked = true
        }
    }

    static func storageURL(forWorkoutStorageURL workoutStorageURL: URL) -> URL {
        workoutStorageURL
            .deletingPathExtension()
            .appendingPathExtension("live-slot.json")
    }

    func bind(to context: LiveWorkoutSessionContext) throws {
        guard !writesBlocked else { throw LiveWorkoutSlotReservationError.storageUnavailable }
        guard let current = reservation else { return }
        guard current.userID == context.userID else {
            throw LiveWorkoutSlotReservationError.accountMismatch
        }
        guard current.sessionID == context.sessionID else {
            throw LiveWorkoutSlotReservationError.sessionMismatch
        }
    }

    func assertOrdinaryStartAllowed(now: Date = Date()) throws {
        guard !writesBlocked else { throw LiveWorkoutSlotReservationError.storageUnavailable }
        try discardExpired(now: now)
        guard reservation == nil else { throw LiveWorkoutSlotReservationError.slotReserved }
    }

    func current(
        context: LiveWorkoutSessionContext,
        now: Date = Date()
    ) throws -> LiveWorkoutSlotReservation? {
        try bind(to: context)
        try discardExpired(now: now)
        return reservation
    }

    func reserve(
        _ candidate: LiveWorkoutSlotReservation,
        context: LiveWorkoutSessionContext,
        now: Date = Date(),
        canReserve: () -> Bool
    ) throws {
        guard !writesBlocked else { throw LiveWorkoutSlotReservationError.storageUnavailable }
        try bind(to: context)
        try discardExpired(now: now)
        try Self.validate(candidate)
        guard candidate.userID == context.userID,
              candidate.sessionID == context.sessionID,
              candidate.expiresAt > now,
              canReserve() else {
            throw LiveWorkoutSlotReservationError.slotReserved
        }
        if let current = reservation, current.operationID != candidate.operationID {
            throw LiveWorkoutSlotReservationError.slotReserved
        }
        if reservation == candidate { return }
        try persist(candidate)
        reservation = candidate
    }

    func replace(
        operationID: UUID,
        with candidate: LiveWorkoutSlotReservation,
        context: LiveWorkoutSessionContext,
        now: Date = Date()
    ) throws {
        guard !writesBlocked else { throw LiveWorkoutSlotReservationError.storageUnavailable }
        try bind(to: context)
        try discardExpired(now: now)
        guard reservation?.operationID == operationID,
              candidate.operationID == operationID,
              candidate.userID == context.userID,
              candidate.sessionID == context.sessionID,
              candidate.expiresAt > now else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        try Self.validate(candidate)
        try persist(candidate)
        reservation = candidate
    }

    func assertLiveStartAllowed(
        roomID: String,
        context: LiveWorkoutSessionContext,
        now: Date = Date()
    ) throws {
        guard !writesBlocked else { throw LiveWorkoutSlotReservationError.storageUnavailable }
        try bind(to: context)
        try discardExpired(now: now)
        guard let current = reservation,
              current.roomID == roomID,
              current.phase != .preparing else {
            throw LiveWorkoutSlotReservationError.slotReserved
        }
    }

    func clear(
        operationID: UUID,
        roomID: String? = nil,
        context: LiveWorkoutSessionContext
    ) throws {
        guard !writesBlocked else { throw LiveWorkoutSlotReservationError.storageUnavailable }
        try bind(to: context)
        guard let current = reservation else { return }
        guard current.operationID == operationID,
              roomID == nil || current.roomID == roomID else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        try persist(nil)
        reservation = nil
    }

    func reconcileAfterSessionChange(
        expectedOperationID: UUID,
        with candidate: LiveWorkoutSlotReservation?,
        context: LiveWorkoutSessionContext
    ) throws {
        guard !writesBlocked else { throw LiveWorkoutSlotReservationError.storageUnavailable }
        guard let current = reservation,
              current.operationID == expectedOperationID,
              current.userID == context.userID,
              current.sessionID != context.sessionID else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        if let candidate {
            try Self.validate(candidate)
            guard candidate.operationID == current.operationID,
                  candidate.userID == current.userID,
                  candidate.sessionID == context.sessionID else {
                throw LiveWorkoutSlotReservationError.invalidState
            }
        }
        try persist(candidate)
        reservation = candidate
    }

    private func discardExpired(now: Date) throws {
        guard let current = reservation, current.expiresAt <= now else { return }
        try persist(nil)
        reservation = nil
    }

    private func persist(_ value: LiveWorkoutSlotReservation?) throws {
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            accountStorageKey: accountStorageKey,
            savedAt: Date(),
            reservation: value
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumFileBytes else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        do {
            try envelopeWriter(data, storageURL)
            try Self.excludeFromBackup(storageURL)
        } catch {
            writesBlocked = true
            throw LiveWorkoutSlotReservationError.storageUnavailable
        }
    }

    private static func load(
        accountStorageKey: String,
        storageURL: URL,
        fileManager: FileManager
    ) throws -> LiveWorkoutSlotReservation? {
        guard fileManager.fileExists(atPath: storageURL.path) else { return nil }
        let values = try storageURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= maximumFileBytes else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        let data = try Data(contentsOf: storageURL, options: [.mappedIfSafe])
        try validateJSONShape(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.schemaVersion == schemaVersion,
              envelope.accountStorageKey == accountStorageKey else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        if let reservation = envelope.reservation { try validate(reservation) }
        return envelope.reservation
    }

    private static func validateJSONShape(_ data: Data) throws {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let root = raw as? [String: Any],
              Set(root.keys) == Set(["schemaVersion", "accountStorageKey", "savedAt", "reservation"]),
              strictInteger(root["schemaVersion"]) == schemaVersion,
              root["accountStorageKey"] is String,
              strictFiniteNumber(root["savedAt"]) != nil else {
            throw LiveWorkoutSlotReservationError.invalidState
        }
        if root["reservation"] is NSNull { return }
        guard let reservation = root["reservation"] as? [String: Any],
              Set(reservation.keys) == Set([
                "version", "userID", "sessionID", "role", "operationID", "roomID",
                "phase", "createdAt", "expiresAt"
              ]),
              strictInteger(reservation["version"]) == 1,
              reservation["userID"] is String,
              reservation["sessionID"] is String,
              reservation["role"] is String,
              reservation["operationID"] is String,
              reservation["roomID"] is String || reservation["roomID"] is NSNull,
              reservation["phase"] is String,
              strictFiniteNumber(reservation["createdAt"]) != nil,
              strictFiniteNumber(reservation["expiresAt"]) != nil else {
            throw LiveWorkoutSlotReservationError.invalidState
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

    private static func validate(_ value: LiveWorkoutSlotReservation) throws {
        guard value.version == 1,
              matches(uuidPattern, value.userID),
              matches(uuidPattern, value.sessionID),
              value.expiresAt > value.createdAt,
              value.expiresAt.timeIntervalSince(value.createdAt) <= maximumDuration,
              (value.phase == .preparing
                ? value.role == .owner && value.roomID == nil
                : value.roomID.map { matches(roomPattern, $0) } == true) else {
            throw LiveWorkoutSlotReservationError.invalidState
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
