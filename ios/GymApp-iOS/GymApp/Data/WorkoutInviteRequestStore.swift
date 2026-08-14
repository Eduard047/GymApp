import CoreFoundation
import Foundation

enum WorkoutInviteRequestStoreError: LocalizedError, Equatable, Sendable {
    case storageUnavailable
    case invalidState
    case capacityReached

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Workout invitation retry state could not be saved safely. No invitation was sent."
        case .invalidState:
            "Workout invitation retry state is invalid and was not replayed."
        case .capacityReached:
            "Too many workout invitation attempts are awaiting a confirmed outcome."
        }
    }
}

/// Durable, account-bound idempotency journal for workout invitations whose network
/// outcome is unknown. It intentionally stores only a canonical payload digest and
/// opaque identifiers, never the workout payload, access token, or friend display data.
final class WorkoutInviteRequestStore {
    private struct Entry: Codable, Equatable {
        let profileID: String
        let canonicalWorkoutDigest: Data
        let clientRequestID: UUID
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let accountStorageKey: String
        let userID: String
        var entries: [Entry]
    }

    static let maximumEntries = 25
    private static let schemaVersion = 1
    private static let maximumFileBytes = 32 * 1_024

    let storageURL: URL
    private var envelope: Envelope

    init(
        accountStorageKey: String,
        userID: String,
        workoutStorageURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let resolvedStorageURL = Self.storageURL(forWorkoutStorageURL: workoutStorageURL)
        let loadedEnvelope: Envelope
        do {
            try fileManager.createDirectory(
                at: resolvedStorageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.excludeFromBackup(resolvedStorageURL.deletingLastPathComponent())
            if fileManager.fileExists(atPath: resolvedStorageURL.path) {
                loadedEnvelope = try Self.load(
                    accountStorageKey: accountStorageKey,
                    userID: userID,
                    storageURL: resolvedStorageURL
                )
            } else {
                loadedEnvelope = Envelope(
                    schemaVersion: Self.schemaVersion,
                    accountStorageKey: accountStorageKey,
                    userID: userID,
                    entries: []
                )
            }
        } catch let error as WorkoutInviteRequestStoreError {
            throw error
        } catch {
            throw WorkoutInviteRequestStoreError.storageUnavailable
        }
        self.storageURL = resolvedStorageURL
        self.envelope = loadedEnvelope
    }

    static func storageURL(forWorkoutStorageURL workoutStorageURL: URL) -> URL {
        workoutStorageURL
            .deletingPathExtension()
            .appendingPathExtension("workout-invite-journal.json")
    }

    func requestID(profileID: String, canonicalWorkoutDigest: Data) throws -> UUID {
        try Self.validateFingerprint(
            profileID: profileID,
            canonicalWorkoutDigest: canonicalWorkoutDigest
        )
        if let existing = envelope.entries.first(where: {
            $0.profileID == profileID &&
                $0.canonicalWorkoutDigest == canonicalWorkoutDigest
        }) {
            return existing.clientRequestID
        }
        guard envelope.entries.count < Self.maximumEntries else {
            throw WorkoutInviteRequestStoreError.capacityReached
        }
        let entry = Entry(
            profileID: profileID,
            canonicalWorkoutDigest: canonicalWorkoutDigest,
            clientRequestID: UUID()
        )
        var candidate = envelope
        candidate.entries.append(entry)
        try persist(candidate)
        envelope = candidate
        return entry.clientRequestID
    }

    func confirm(profileID: String, canonicalWorkoutDigest: Data, clientRequestID: UUID) throws {
        guard let index = envelope.entries.firstIndex(where: {
            $0.profileID == profileID &&
                $0.canonicalWorkoutDigest == canonicalWorkoutDigest &&
                $0.clientRequestID == clientRequestID
        }) else { return }
        var candidate = envelope
        candidate.entries.remove(at: index)
        try persist(candidate)
        envelope = candidate
    }

    private func persist(_ candidate: Envelope) throws {
        do {
            try Self.validate(candidate)
            let data = try Self.encoder().encode(candidate)
            guard data.count <= Self.maximumFileBytes else {
                throw WorkoutInviteRequestStoreError.invalidState
            }
            try data.write(
                to: storageURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            try Self.excludeFromBackup(storageURL)
        } catch let error as WorkoutInviteRequestStoreError {
            throw error
        } catch {
            throw WorkoutInviteRequestStoreError.storageUnavailable
        }
    }

    private static func load(
        accountStorageKey: String,
        userID: String,
        storageURL: URL
    ) throws -> Envelope {
        do {
            let values = try storageURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            )
            guard values.isRegularFile == true,
                  let size = values.fileSize,
                  size > 0,
                  size <= maximumFileBytes else {
                throw WorkoutInviteRequestStoreError.invalidState
            }
            let data = try Data(contentsOf: storageURL, options: [.mappedIfSafe])
            try StrictLiveWorkoutJSONScanner.validate(data)
            try validateShape(data)
            let decoded = try decoder().decode(Envelope.self, from: data)
            guard decoded.accountStorageKey == accountStorageKey,
                  decoded.userID == userID else {
                throw WorkoutInviteRequestStoreError.invalidState
            }
            try validate(decoded)
            return decoded
        } catch let error as WorkoutInviteRequestStoreError {
            throw error
        } catch {
            throw WorkoutInviteRequestStoreError.invalidState
        }
    }

    private static func validate(_ value: Envelope) throws {
        guard value.schemaVersion == schemaVersion,
              !value.accountStorageKey.isEmpty,
              value.accountStorageKey.count <= 200,
              UUID(uuidString: value.userID) != nil,
              value.entries.count <= maximumEntries else {
            throw WorkoutInviteRequestStoreError.invalidState
        }
        var fingerprints = Set<String>()
        var requestIDs = Set<UUID>()
        for entry in value.entries {
            try validateFingerprint(
                profileID: entry.profileID,
                canonicalWorkoutDigest: entry.canonicalWorkoutDigest
            )
            let fingerprint = entry.profileID + ":" + entry.canonicalWorkoutDigest.base64EncodedString()
            guard fingerprints.insert(fingerprint).inserted,
                  requestIDs.insert(entry.clientRequestID).inserted else {
                throw WorkoutInviteRequestStoreError.invalidState
            }
        }
    }

    private static func validateFingerprint(
        profileID: String,
        canonicalWorkoutDigest: Data
    ) throws {
        guard SocialPayloadParser.isValidProfileID(profileID),
              canonicalWorkoutDigest.count == 32 else {
            throw WorkoutInviteRequestStoreError.invalidState
        }
    }

    private static func validateShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["schemaVersion", "accountStorageKey", "userID", "entries"]),
              strictInteger(root["schemaVersion"]) == schemaVersion,
              root["accountStorageKey"] is String,
              root["userID"] is String,
              let entries = root["entries"] as? [[String: Any]],
              entries.allSatisfy({
                  Set($0.keys) == Set([
                      "profileID", "canonicalWorkoutDigest", "clientRequestID"
                  ]) &&
                      $0["profileID"] is String &&
                      $0["canonicalWorkoutDigest"] is String &&
                      $0["clientRequestID"] is String
              }) else {
            throw WorkoutInviteRequestStoreError.invalidState
        }
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite,
              value.rounded(.towardZero) == value,
              value >= Double(Int.min),
              value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    private static func excludeFromBackup(_ url: URL) throws {
        try (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
    }
}
