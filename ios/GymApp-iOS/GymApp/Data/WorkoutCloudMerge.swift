import Foundation

/// Per-workout three-way merge of the shared cloud workout row, as specified by
/// `shared/workout-sync-merge-v1.json`.
///
/// The shared v2 row must stay readable by released 2.2.9 clients, which rewrite
/// it whole and drop unknown fields, so it cannot carry per-workout revisions or
/// deletion markers. Instead each client keeps the exact canonical core it last
/// agreed with the cloud (the base) and compares every workout by start time:
/// a change on one side applies, additions and deletions on both sides combine,
/// and divergent changes to one workout go to the newer side. The local change
/// time comes from the per-workout journal; the remote change time is the
/// fetched row's `updated_at`, because the row has no per-workout edit time. A
/// tie or a missing local time keeps the remote copy.
enum WorkoutCloudMerge {
    struct Core: Codable, Equatable, Sendable {
        /// Custom (non built-in) catalog entries.
        var configuredExercises: [BackupExercise]
        /// Canonical workouts: `date` set, `startedAt` and `durationSeconds` nil.
        var sessions: [BackupSession]

        static let empty = Core(configuredExercises: [], sessions: [])
    }

    struct Result: Equatable, Sendable {
        let merged: Core
        /// Start times of divergent workouts that the newer local copy decided.
        let localWins: Set<Int64>
        /// Start times of divergent workouts that the newer remote copy decided.
        let remoteWins: Set<Int64>
    }

    enum MergeError: Error, Equatable {
        case missingStartTime
        case duplicateStartTime(Int64)
        case duplicateExercise(String)
    }

    static func sessionIdentity(_ session: BackupSession) -> Int64? {
        session.date ?? session.startedAt
    }

    static func exerciseIdentity(_ exercise: BackupExercise) -> String {
        WorkoutStore.backupExerciseIdentity(name: exercise.name, catalogKey: exercise.catalogKey)
    }

    /// Start times of workouts that were added, removed, or changed between two cores.
    static func changedSessionStarts(before: Core, after: Core) -> Set<Int64> {
        var beforeByStart: [Int64: BackupSession] = [:]
        for session in before.sessions {
            if let start = sessionIdentity(session) { beforeByStart[start] = session }
        }
        var afterByStart: [Int64: BackupSession] = [:]
        for session in after.sessions {
            if let start = sessionIdentity(session) { afterByStart[start] = session }
        }
        var changed = Set<Int64>()
        for start in Set(beforeByStart.keys).union(afterByStart.keys) where beforeByStart[start] != afterByStart[start] {
            changed.insert(start)
        }
        return changed
    }

    static func merge(
        base: Core,
        local: Core,
        remote: Core,
        localChangedAt: [Int64: Int64],
        remoteRowUpdatedAt: Int64
    ) throws -> Result {
        let baseSessions = try sessionsByIdentity(base.sessions)
        let localSessions = try sessionsByIdentity(local.sessions)
        let remoteSessions = try sessionsByIdentity(remote.sessions)

        var mergedSessions: [Int64: BackupSession] = [:]
        var localWins = Set<Int64>()
        var remoteWins = Set<Int64>()
        let sessionKeys = Set(baseSessions.keys)
            .union(localSessions.keys)
            .union(remoteSessions.keys)
        for key in sessionKeys {
            let baseSession = baseSessions[key]
            let localSession = localSessions[key]
            let remoteSession = remoteSessions[key]
            let chosen: BackupSession?
            if localSession == remoteSession {
                chosen = localSession
            } else if localSession == baseSession {
                chosen = remoteSession
            } else if remoteSession == baseSession {
                chosen = localSession
            } else if let localTime = localChangedAt[key], localTime > remoteRowUpdatedAt {
                chosen = localSession
                localWins.insert(key)
            } else {
                chosen = remoteSession
                remoteWins.insert(key)
            }
            if let chosen {
                mergedSessions[key] = chosen
            }
        }

        let baseExercises = try exercisesByIdentity(base.configuredExercises)
        let localExercises = try exercisesByIdentity(local.configuredExercises)
        let remoteExercises = try exercisesByIdentity(remote.configuredExercises)
        var mergedExercises: [String: BackupExercise] = [:]
        let exerciseKeys = Set(baseExercises.keys)
            .union(localExercises.keys)
            .union(remoteExercises.keys)
        for key in exerciseKeys {
            let baseExercise = baseExercises[key]
            let localExercise = localExercises[key]
            let remoteExercise = remoteExercises[key]
            // Catalog entries only appear or disappear; when both sides still have
            // one with different details (a load profile), the local copy is kept.
            let chosen: BackupExercise?
            if localExercise == remoteExercise {
                chosen = localExercise
            } else if localExercise == baseExercise {
                chosen = remoteExercise
            } else if remoteExercise == baseExercise {
                chosen = localExercise
            } else {
                chosen = localExercise ?? remoteExercise
            }
            if let chosen {
                mergedExercises[key] = chosen
            }
        }

        // A workout that survives the merge keeps every custom exercise it uses.
        for session in mergedSessions.values {
            for block in session.exercises ?? [] {
                guard BuiltInExerciseCatalog.resolvedKey(catalogKey: block.catalogKey, name: block.name) == nil else {
                    continue
                }
                let key = WorkoutStore.backupExerciseIdentity(name: block.name, catalogKey: block.catalogKey)
                guard mergedExercises[key] == nil else { continue }
                mergedExercises[key] = localExercises[key]
                    ?? remoteExercises[key]
                    ?? BackupExercise(name: block.name, catalogKey: block.catalogKey)
            }
        }

        let sortedSessionKeys = mergedSessions.keys.sorted()
        var sessions: [BackupSession] = []
        for key in sortedSessionKeys {
            if let session = mergedSessions[key] {
                sessions.append(session)
            }
        }
        let exercises = mergedExercises.values.sorted(by: BackupExercisePortableWireOrder.precedes)
        return Result(
            merged: Core(configuredExercises: exercises, sessions: sessions),
            localWins: localWins,
            remoteWins: remoteWins
        )
    }

    private static func sessionsByIdentity(_ sessions: [BackupSession]) throws -> [Int64: BackupSession] {
        var result: [Int64: BackupSession] = [:]
        for session in sessions {
            guard let key = sessionIdentity(session) else { throw MergeError.missingStartTime }
            guard result[key] == nil else { throw MergeError.duplicateStartTime(key) }
            result[key] = session
        }
        return result
    }

    private static func exercisesByIdentity(_ exercises: [BackupExercise]) throws -> [String: BackupExercise] {
        var result: [String: BackupExercise] = [:]
        for exercise in exercises {
            let key = exerciseIdentity(exercise)
            guard result[key] == nil else { throw MergeError.duplicateExercise(key) }
            result[key] = exercise
        }
        return result
    }
}

/// Owner-bound per-workout sync state kept in the protected account envelope:
/// the exact core last agreed with the cloud and when each workout last changed
/// on this device.
struct WorkoutCloudSyncState: Codable, Equatable, Sendable {
    static let maximumJournalEntries = 10_000

    let version: Int
    let ownerUserID: String
    var baseline: WorkoutCloudMerge.Core?
    /// Epoch milliseconds of the latest local change, keyed by workout start time.
    var localChangedAt: [Int64: Int64]

    init(
        ownerUserID: String,
        baseline: WorkoutCloudMerge.Core?,
        localChangedAt: [Int64: Int64]
    ) throws {
        guard let ownerUUID = UUID(uuidString: ownerUserID),
              localChangedAt.count <= Self.maximumJournalEntries else {
            throw CloudSyncError.invalidPayload
        }
        if let baseline, baseline.sessions.count > BackupImportLimits.standard.maximumSessions {
            throw CloudSyncError.invalidPayload
        }
        version = 1
        self.ownerUserID = ownerUUID.uuidString.lowercased()
        self.baseline = baseline
        self.localChangedAt = localChangedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported workout sync state version."
            )
        }
        self = try Self(
            ownerUserID: try container.decode(String.self, forKey: .ownerUserID),
            baseline: try container.decodeIfPresent(WorkoutCloudMerge.Core.self, forKey: .baseline),
            localChangedAt: try container.decode([Int64: Int64].self, forKey: .localChangedAt)
        )
    }

    func isOwned(by userID: String) -> Bool {
        UUID(uuidString: userID)?.uuidString.lowercased() == ownerUserID
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case ownerUserID
        case baseline
        case localChangedAt
    }
}
