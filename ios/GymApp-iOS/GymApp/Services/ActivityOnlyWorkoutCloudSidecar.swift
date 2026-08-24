import CoreFoundation
import Foundation

struct ActivityOnlyWorkoutCloudItem: Codable, Equatable, Hashable, Sendable {
    let workoutStartedAt: Int64
    let durationSeconds: Int
    let gymCalories: Double
    let garminCalories: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let endingHeartRateZone: Int?
    let note: String?

    init(
        workoutStartedAt: Int64,
        durationSeconds: Int,
        gymCalories: Double,
        garminCalories: Int? = nil,
        averageHeartRate: Int? = nil,
        maximumHeartRate: Int? = nil,
        endingHeartRateZone: Int? = nil,
        note: String? = nil
    ) throws {
        self.workoutStartedAt = workoutStartedAt
        self.durationSeconds = durationSeconds
        self.gymCalories = gymCalories
        self.garminCalories = garminCalories
        self.averageHeartRate = averageHeartRate
        self.maximumHeartRate = maximumHeartRate
        self.endingHeartRateZone = endingHeartRateZone
        self.note = note
        guard ActivityOnlyWorkoutCloudCodec.isValid(self) else {
            throw CloudSyncError.invalidPayload
        }
    }

    fileprivate init(validatedObject object: [String: Any]) throws {
        let garminCalories = try ActivityOnlyWorkoutCloudCodec.optionalInteger(
            object,
            key: "garminCalories",
            range: 0 ... Int64(ActivityOnlyWorkoutCloudCodec.maximumCalories)
        )
        let averageHeartRate = try ActivityOnlyWorkoutCloudCodec.optionalInteger(
            object,
            key: "averageHeartRate",
            range: 0 ... Int64(ActivityOnlyWorkoutCloudCodec.maximumHeartRate)
        )
        let maximumHeartRate = try ActivityOnlyWorkoutCloudCodec.optionalInteger(
            object,
            key: "maximumHeartRate",
            range: 0 ... Int64(ActivityOnlyWorkoutCloudCodec.maximumHeartRate)
        )
        let endingHeartRateZone = try ActivityOnlyWorkoutCloudCodec.optionalInteger(
            object,
            key: "endingHeartRateZone",
            range: 0 ... Int64(ActivityOnlyWorkoutCloudCodec.maximumHeartRateZone)
        )
        let note = try ActivityOnlyWorkoutCloudCodec.optionalNote(object)
        guard let workoutStartedAt = ActivityOnlyWorkoutCloudCodec.exactInteger(
            object["workoutStartedAt"],
            range: ActivityOnlyWorkoutCloudCodec.timestampRange
        ),
        let duration = ActivityOnlyWorkoutCloudCodec.exactInteger(
            object["durationSeconds"],
            range: Int64(1) ... Int64(ActivityOnlyWorkoutCloudCodec.maximumDurationSeconds)
        ),
        let gymCalories = ActivityOnlyWorkoutCloudCodec.calories(object["gymCalories"]) else {
            throw CloudSyncError.invalidResponse
        }
        do {
            try self.init(
                workoutStartedAt: workoutStartedAt,
                durationSeconds: Int(duration),
                gymCalories: gymCalories,
                garminCalories: garminCalories.map(Int.init),
                averageHeartRate: averageHeartRate.map(Int.init),
                maximumHeartRate: maximumHeartRate.map(Int.init),
                endingHeartRateZone: endingHeartRateZone.map(Int.init),
                note: note
            )
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    var jsonObject: [String: Any] {
        var object: [String: Any] = [
            "workoutStartedAt": workoutStartedAt,
            "durationSeconds": durationSeconds,
            "gymCalories": gymCalories
        ]
        if let garminCalories { object["garminCalories"] = garminCalories }
        if let averageHeartRate { object["averageHeartRate"] = averageHeartRate }
        if let maximumHeartRate { object["maximumHeartRate"] = maximumHeartRate }
        if let endingHeartRateZone { object["endingHeartRateZone"] = endingHeartRateZone }
        if let note { object["note"] = note }
        return object
    }

    func matchesMaterializedWorkout(_ workout: WorkoutSession) -> Bool {
        workout.exercises.isEmpty &&
            workout.date.gymEpochMilliseconds == workoutStartedAt &&
            workout.durationSeconds == durationSeconds &&
            ActivityOnlyWorkoutCloudCodec.boundedNote(workout.note) == note
    }

    static func localItems(from workouts: [WorkoutSession]) throws -> [Self] {
        guard workouts.count <= ActivityOnlyWorkoutCloudCodec.maximumItemCount else {
            throw CloudSyncError.invalidPayload
        }
        var seen = Set<Int64>()
        var result: [Self] = []
        result.reserveCapacity(workouts.count)
        for workout in workouts where workout.exercises.isEmpty {
            guard let duration = workout.durationSeconds,
                  (1 ... ActivityOnlyWorkoutCloudCodec.maximumDurationSeconds).contains(duration),
                  seen.insert(workout.date.gymEpochMilliseconds).inserted else {
                throw CloudSyncError.invalidPayload
            }
            let summary = GarminWorkoutNoteParser.parse(workout.note)
            result.append(try Self(
                workoutStartedAt: workout.date.gymEpochMilliseconds,
                durationSeconds: duration,
                gymCalories: Double(summary?.gymCalories ?? 0),
                garminCalories: summary?.garminCalories,
                averageHeartRate: summary?.averageHeartRate,
                maximumHeartRate: summary?.maximumHeartRate,
                endingHeartRateZone: summary?.endingHeartRateZone,
                note: ActivityOnlyWorkoutCloudCodec.boundedNote(workout.note)
            ))
        }
        return result.sorted { $0.workoutStartedAt < $1.workoutStartedAt }
    }
}

struct ActivityOnlyWorkoutCloudSnapshot: Equatable, Sendable {
    let revision: Int64
    let items: [ActivityOnlyWorkoutCloudItem]
}

enum ActivityOnlyWorkoutCloudReadResult: Equatable, Sendable {
    case unavailable
    case snapshot(ActivityOnlyWorkoutCloudSnapshot)
}

enum ActivityOnlyWorkoutCloudSyncResult: Equatable, Sendable {
    case unavailable
    case synced(
        revision: Int64,
        syncedCount: Int,
        changedCount: Int,
        replayed: Bool
    )
    case conflict(revision: Int64)
    case requestConflict(revision: Int64)
    case rateLimited(retryAfter: Int)
    case invalidPayload
    case revisionExhausted(revision: Int64)
}

enum ActivityOnlyWorkoutCloudCodec {
    static let maximumRevision: Int64 = 9_007_199_254_740_991
    static let timestampRange: ClosedRange<Int64> =
        -62_135_769_600_000 ... 64_092_211_200_000
    static let maximumDurationSeconds = 604_800
    static let maximumCalories = 100_000
    static let maximumHeartRate = 240
    static let maximumHeartRateZone = 5
    static let maximumNoteCharacters = 512
    static let maximumNoteBytes = 2_048
    static let maximumItemCount = 5_000
    static let maximumItemsBytes = 1_048_576
    static let maximumResponseBytes = 2 * 1_024 * 1_024

    private static let itemKeys: Set<String> = [
        "workoutStartedAt", "durationSeconds", "gymCalories", "garminCalories",
        "averageHeartRate", "maximumHeartRate", "endingHeartRateZone", "note"
    ]
    private static let requiredItemKeys: Set<String> = [
        "workoutStartedAt", "durationSeconds", "gymCalories"
    ]

    static func parseReadResponse(_ data: Data) throws -> ActivityOnlyWorkoutCloudSnapshot {
        guard data.count <= maximumResponseBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["version", "revision", "items"],
              exactInteger(object["version"], range: 1 ... 1) == 1,
              let revision = exactInteger(object["revision"], range: 0 ... maximumRevision),
              let rawItems = object["items"] as? [Any] else {
            throw CloudSyncError.invalidResponse
        }
        return ActivityOnlyWorkoutCloudSnapshot(
            revision: revision,
            items: try parseItems(rawItems)
        )
    }

    static func parseSyncResponse(_ data: Data) throws -> ActivityOnlyWorkoutCloudSyncResult {
        guard data.count <= maximumResponseBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              exactInteger(object["version"], range: 1 ... 1) == 1,
              let status = object["status"] as? String else {
            throw CloudSyncError.invalidResponse
        }
        switch status {
        case "synced":
            guard Set(object.keys) == [
                "version", "status", "revision", "syncedCount", "changedCount", "replayed"
            ],
            let revision = exactInteger(object["revision"], range: 0 ... maximumRevision),
            let syncedCount = exactInteger(
                object["syncedCount"], range: 0 ... Int64(maximumItemCount)
            ),
            let changedCount = exactInteger(object["changedCount"], range: 0 ... 10_000),
            let replayed = jsonBoolean(object["replayed"]) else {
                throw CloudSyncError.invalidResponse
            }
            return .synced(
                revision: revision,
                syncedCount: Int(syncedCount),
                changedCount: Int(changedCount),
                replayed: replayed
            )
        case "conflict", "request_conflict", "revision_exhausted":
            guard Set(object.keys) == ["version", "status", "revision"],
                  let revision = exactInteger(
                    object["revision"], range: 0 ... maximumRevision
                  ) else {
                throw CloudSyncError.invalidResponse
            }
            if status == "conflict" { return .conflict(revision: revision) }
            if status == "request_conflict" { return .requestConflict(revision: revision) }
            return .revisionExhausted(revision: revision)
        case "rate_limited":
            guard Set(object.keys) == ["version", "status", "retryAfter"],
                  let retryAfter = exactInteger(
                    object["retryAfter"], range: 1 ... 600
                  ) else {
                throw CloudSyncError.invalidResponse
            }
            return .rateLimited(retryAfter: Int(retryAfter))
        case "invalid_payload":
            guard Set(object.keys) == ["version", "status"] else {
                throw CloudSyncError.invalidResponse
            }
            return .invalidPayload
        default:
            throw CloudSyncError.invalidResponse
        }
    }

    static func validate(_ items: [ActivityOnlyWorkoutCloudItem]) throws {
        guard items.count <= maximumItemCount else { throw CloudSyncError.invalidPayload }
        var previous: Int64?
        for item in items {
            guard isValid(item),
                  previous.map({ item.workoutStartedAt > $0 }) ?? true else {
                throw CloudSyncError.invalidPayload
            }
            previous = item.workoutStartedAt
        }
        let encoded = try JSONSerialization.data(
            withJSONObject: items.map(\.jsonObject),
            options: [.sortedKeys]
        )
        guard encoded.count <= maximumItemsBytes else { throw CloudSyncError.invalidPayload }
    }

    static func requestItems(_ items: [ActivityOnlyWorkoutCloudItem]) throws -> [[String: Any]] {
        try validate(items)
        return items.map(\.jsonObject)
    }

    static func syncRequestData(
        expectedRevision: Int64,
        requestID: UUID,
        items: [ActivityOnlyWorkoutCloudItem]
    ) throws -> Data {
        guard (0 ... maximumRevision).contains(expectedRevision) else {
            throw CloudSyncError.invalidPayload
        }
        let data = try JSONSerialization.data(
            withJSONObject: [
                "p_expected_revision": expectedRevision,
                "p_request_id": requestID.uuidString.lowercased(),
                "p_items": try requestItems(items)
            ],
            options: [.sortedKeys]
        )
        guard data.count <= maximumItemsBytes + 4_096 else {
            throw CloudSyncError.invalidPayload
        }
        return data
    }

    static func reconciledItems(
        base: [ActivityOnlyWorkoutCloudItem],
        remote: [ActivityOnlyWorkoutCloudItem],
        local: [ActivityOnlyWorkoutCloudItem],
        coreWorkoutTimestamps: Set<Int64>
    ) throws -> (
        outbound: [ActivityOnlyWorkoutCloudItem],
        materialize: [ActivityOnlyWorkoutCloudItem]
    ) {
        try validate(base)
        try validate(remote)
        try validate(local)
        let baseByTimestamp = Dictionary(uniqueKeysWithValues: base.map {
            ($0.workoutStartedAt, $0)
        })
        let remoteByTimestamp = Dictionary(uniqueKeysWithValues: remote.map {
            ($0.workoutStartedAt, $0)
        })
        let localByTimestamp = Dictionary(uniqueKeysWithValues: local.map {
            ($0.workoutStartedAt, $0)
        })
        let timestamps = Set(baseByTimestamp.keys)
            .union(remoteByTimestamp.keys)
            .union(localByTimestamp.keys)
            .sorted()
        var outbound: [ActivityOnlyWorkoutCloudItem] = []
        var materialize: [ActivityOnlyWorkoutCloudItem] = []

        for timestamp in timestamps {
            let baseItem = baseByTimestamp[timestamp]
            let localItem = localByTimestamp[timestamp]
            let remoteItem = remoteByTimestamp[timestamp]
            let mergedItem: ActivityOnlyWorkoutCloudItem?
            if localItem == remoteItem {
                mergedItem = localItem
            } else if localItem == baseItem {
                mergedItem = remoteItem
            } else if remoteItem == baseItem {
                mergedItem = localItem
            } else {
                // This includes delete-vs-edit, divergent edits and divergent
                // same-identity additions. Exact optional nil/zero values participate
                // in Equatable and are never normalized before this decision.
                throw CloudSyncError.requestFailed(
                    "An activity-only workout changed on another device. Both copies remain preserved; resolve the timestamp conflict before syncing."
                )
            }
            guard let mergedItem else { continue }
            outbound.append(mergedItem)
            if localItem != mergedItem,
               !coreWorkoutTimestamps.contains(timestamp) {
                materialize.append(mergedItem)
            }
        }
        try validate(outbound)
        return (
            outbound: outbound,
            materialize: materialize
        )
    }

    static func coreWorkoutTimestamps(_ workouts: [WorkoutSession]) -> Set<Int64> {
        Set(workouts.lazy.filter { !$0.exercises.isEmpty }.map { $0.date.gymEpochMilliseconds })
    }

    static func boundedNote(_ note: String?) -> String? {
        guard let note,
              note.unicodeScalars.count <= maximumNoteCharacters,
              note.utf8.count <= maximumNoteBytes else { return nil }
        return note
    }

    fileprivate static func isValid(_ item: ActivityOnlyWorkoutCloudItem) -> Bool {
        guard timestampRange.contains(item.workoutStartedAt),
              (1 ... maximumDurationSeconds).contains(item.durationSeconds),
              item.gymCalories.isFinite,
              (0 ... Double(maximumCalories)).contains(item.gymCalories),
              hasAtMostThreeDecimalPlaces(item.gymCalories),
              item.garminCalories.map({ (0 ... maximumCalories).contains($0) }) ?? true,
              item.averageHeartRate.map({ (0 ... maximumHeartRate).contains($0) }) ?? true,
              item.maximumHeartRate.map({ (0 ... maximumHeartRate).contains($0) }) ?? true,
              item.endingHeartRateZone.map({ (0 ... maximumHeartRateZone).contains($0) }) ?? true,
              item.averageHeartRate == nil || item.maximumHeartRate == nil ||
                item.averageHeartRate! <= item.maximumHeartRate!,
              item.note == boundedNote(item.note) else { return false }
        return true
    }

    static func exactInteger(
        _ raw: Any?,
        range: ClosedRange<Int64>
    ) -> Int64? {
        guard let number = jsonNumber(raw),
              let decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        var source = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard rounded == decimal else { return nil }
        let value = NSDecimalNumber(decimal: decimal).int64Value
        guard Decimal(value) == decimal, range.contains(value) else { return nil }
        return value
    }

    fileprivate static func calories(_ raw: Any?) -> Double? {
        guard let number = jsonNumber(raw),
              let decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0,
              decimal <= Decimal(maximumCalories) else { return nil }
        var scaled = decimal * 1_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled else { return nil }
        let result = NSDecimalNumber(decimal: decimal).doubleValue
        return result.isFinite ? result : nil
    }

    fileprivate static func optionalInteger(
        _ object: [String: Any],
        key: String,
        range: ClosedRange<Int64>
    ) throws -> Int64? {
        guard let raw = object[key], !(raw is NSNull) else { return nil }
        guard let value = exactInteger(raw, range: range) else {
            throw CloudSyncError.invalidResponse
        }
        return value
    }

    fileprivate static func optionalNote(_ object: [String: Any]) throws -> String? {
        guard let raw = object["note"], !(raw is NSNull) else { return nil }
        guard let note = raw as? String, boundedNote(note) == note else {
            throw CloudSyncError.invalidResponse
        }
        return note
    }

    private static func parseItems(_ rawItems: [Any]) throws -> [ActivityOnlyWorkoutCloudItem] {
        guard rawItems.count <= maximumItemCount else { throw CloudSyncError.invalidResponse }
        var result: [ActivityOnlyWorkoutCloudItem] = []
        var previous: Int64?
        result.reserveCapacity(rawItems.count)
        for raw in rawItems {
            guard let object = raw as? [String: Any],
                  requiredItemKeys.isSubset(of: Set(object.keys)),
                  Set(object.keys).isSubset(of: itemKeys) else {
                throw CloudSyncError.invalidResponse
            }
            let item = try ActivityOnlyWorkoutCloudItem(validatedObject: object)
            guard previous.map({ item.workoutStartedAt > $0 }) ?? true else {
                throw CloudSyncError.invalidResponse
            }
            result.append(item)
            previous = item.workoutStartedAt
        }
        return result
    }

    private static func jsonNumber(_ raw: Any?) -> NSNumber? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }

    private static func jsonBoolean(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func hasAtMostThreeDecimalPlaces(_ value: Double) -> Bool {
        guard value.isFinite,
              let decimal = Decimal(
                string: String(value), locale: Locale(identifier: "en_US_POSIX")
              ) else { return false }
        var scaled = decimal * 1_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return rounded == scaled
    }
}

struct PendingActivityOnlyWorkoutCloudSync: Codable, Equatable, Sendable {
    let version: Int
    let ownerUserID: String
    let requestID: String
    let expectedRevision: Int64
    let items: [ActivityOnlyWorkoutCloudItem]
    /// Canonical request bytes are persisted with the idempotency key. Replays after
    /// a relaunch or token refresh never rebuild an outcome-unknown request body.
    let requestBody: Data

    private enum CodingKeys: String, CodingKey {
        case version
        case ownerUserID
        case requestID
        case expectedRevision
        case items
        case requestBody
    }

    init(
        ownerUserID: String,
        requestID: UUID = UUID(),
        expectedRevision: Int64,
        items: [ActivityOnlyWorkoutCloudItem]
    ) throws {
        guard UUID(uuidString: ownerUserID) != nil,
              (0 ... ActivityOnlyWorkoutCloudCodec.maximumRevision).contains(expectedRevision)
        else { throw CloudSyncError.invalidPayload }
        try ActivityOnlyWorkoutCloudCodec.validate(items)
        self.version = 1
        self.ownerUserID = ownerUserID.lowercased()
        self.requestID = requestID.uuidString.lowercased()
        self.expectedRevision = expectedRevision
        self.items = items
        self.requestBody = try ActivityOnlyWorkoutCloudCodec.syncRequestData(
            expectedRevision: expectedRevision,
            requestID: requestID,
            items: items
        )
    }

    var requestUUID: UUID? { UUID(uuidString: requestID) }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let ownerUserID = try container.decode(String.self, forKey: .ownerUserID)
        let requestID = try container.decode(String.self, forKey: .requestID)
        let expectedRevision = try container.decode(Int64.self, forKey: .expectedRevision)
        let items = try container.decode(
            [ActivityOnlyWorkoutCloudItem].self,
            forKey: .items
        )
        guard version == 1, let uuid = UUID(uuidString: requestID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .requestID,
                in: container,
                debugDescription: "Invalid pending activity-only request identity."
            )
        }
        let rebuilt = try Self(
            ownerUserID: ownerUserID,
            requestID: uuid,
            expectedRevision: expectedRevision,
            items: items
        )
        if let storedBody = try container.decodeIfPresent(Data.self, forKey: .requestBody),
           storedBody != rebuilt.requestBody {
            throw DecodingError.dataCorruptedError(
                forKey: .requestBody,
                in: container,
                debugDescription: "Pending activity-only request bytes do not match its fields."
            )
        }
        self = rebuilt
    }
}

enum LegacyPendingActivityOnlyWorkoutCloudSyncPreferences {
    static let keyPrefix = "gymapp.activity-only-cloud-pending.v1."
    private static let maximumBytes = 2 * 1_024 * 1_024

    static func loadForMigration(
        defaults: UserDefaults,
        storageKey: String,
        ownerUserID: String
    ) -> PendingActivityOnlyWorkoutCloudSync? {
        let key = keyPrefix + storageKey
        guard let data = defaults.data(forKey: key),
              data.count <= maximumBytes,
              let pending = try? JSONDecoder().decode(
                PendingActivityOnlyWorkoutCloudSync.self,
                from: data
              ),
              pending.version == 1,
              pending.ownerUserID == ownerUserID.lowercased(),
              pending.requestUUID != nil,
              (try? ActivityOnlyWorkoutCloudCodec.validate(pending.items)) != nil else {
            return nil
        }
        return pending
    }

    static func clearAndVerify(defaults: UserDefaults, storageKey: String) -> Bool {
        let key = keyPrefix + storageKey
        defaults.removeObject(forKey: key)
        return defaults.object(forKey: key) == nil
    }
}

struct ActivityOnlyWorkoutCloudBaseline: Codable, Equatable, Sendable {
    let version: Int
    let ownerUserID: String
    let items: [ActivityOnlyWorkoutCloudItem]

    init(ownerUserID: String, items: [ActivityOnlyWorkoutCloudItem]) throws {
        guard let ownerUUID = UUID(uuidString: ownerUserID) else {
            throw CloudSyncError.invalidPayload
        }
        try ActivityOnlyWorkoutCloudCodec.validate(items)
        version = 1
        self.ownerUserID = ownerUUID.uuidString.lowercased()
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let ownerUserID = try container.decode(String.self, forKey: .ownerUserID)
        let items = try container.decode(
            [ActivityOnlyWorkoutCloudItem].self,
            forKey: .items
        )
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported activity-only baseline version."
            )
        }
        self = try Self(ownerUserID: ownerUserID, items: items)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case ownerUserID
        case items
    }
}

enum LegacyActivityOnlyWorkoutCloudBaselinePreferences {
    static let keyPrefix = "gymapp.activity-only-cloud-baseline.v1."
    private static let maximumBytes = 2 * 1_024 * 1_024

    static func loadForMigration(
        defaults: UserDefaults,
        storageKey: String,
        ownerUserID: String
    ) -> ActivityOnlyWorkoutCloudBaseline? {
        let key = keyPrefix + storageKey
        guard let data = defaults.data(forKey: key),
              data.count <= maximumBytes,
              let baseline = try? JSONDecoder().decode(
                ActivityOnlyWorkoutCloudBaseline.self,
                from: data
              ),
              baseline.ownerUserID == ownerUserID.lowercased(),
              (try? ActivityOnlyWorkoutCloudCodec.validate(baseline.items)) != nil else {
            return nil
        }
        return baseline
    }

    static func clearAndVerify(defaults: UserDefaults, storageKey: String) -> Bool {
        let key = keyPrefix + storageKey
        defaults.removeObject(forKey: key)
        return defaults.object(forKey: key) == nil
    }
}
