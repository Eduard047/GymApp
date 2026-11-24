import Foundation

/// iPhone <-> Apple Watch sync contract (shared/watch-sync-v1.json).
/// Foundation-only: compiled into the iPhone app and the watch app.
/// Every inbound value is untrusted: unknown keys, wrong types, non-finite
/// numbers and out-of-range values are rejected.
enum WatchSync {
    static let protocolVersion = 1
    static let envelopeKey = "gymappWatchSync"
    static let maximumEnvelopeBytes = 65_536
    static let languages: Set<String> = ["en", "uk", "ru"]

    static let maximumExerciseCharacters = 160
    static let maximumExerciseBytes = 640
    static let maximumTotalExerciseBytes = 12_000
    static let maximumPlanExercises = 30
    static let maximumPlanSets = 100
    static let maximumSetsPerExercise = 20
    static let maximumCatalogNames = 100
    static let maximumWorkoutSets = 100
    static let weightRange: ClosedRange<Double> = 0 ... 1_000_000
    static let maximumWeightDecimals = 2
    static let repsRange: ClosedRange<Int> = 1 ... 10_000
    static let restSecondsRange: ClosedRange<Int> = 0 ... 3_600
    static let defaultRestSeconds = 90
    static let planRevisionRange: ClosedRange<Int64> = 1 ... 9_007_199_254_740_991
    static let minimumStartedAtMillis: Int64 = 946_684_800_000
    static let maximumFutureSkewMillis: Int64 = 86_400_000
    static let durationSecondsRange: ClosedRange<Int64> = 1 ... 604_800
    static let setTimeToleranceMillis: Int64 = 60_000
    static let heartRateRange: ClosedRange<Int> = 25 ... 240
    static let activeKilocaloriesRange: ClosedRange<Double> = 0 ... 100_000
    static let maximumOutboxItems = 50
    static let maximumReceiptsPerHour = 60
    static let maximumReceiptRecords = 256
    static let maximumSafeInteger: Int64 = 9_007_199_254_740_991

    /// `aw-` + lower-case UUID v4.
    static func makeRequestID() -> String {
        "aw-" + UUID().uuidString.lowercased()
    }

    static func isValidRequestID(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count == 39, value.hasPrefix("aw-") else { return false }
        let body = Array(scalars.dropFirst(3))
        for (index, scalar) in body.enumerated() {
            switch index {
            case 8, 13, 18, 23:
                guard scalar == "-" else { return false }
            case 14:
                guard scalar == "4" else { return false }
            case 19:
                guard "89ab".unicodeScalars.contains(scalar) else { return false }
            default:
                guard isLowerHex(scalar) else { return false }
            }
        }
        return true
    }

    /// 64 lower-case hex characters (account binding, digest).
    static func isValidHash(_ value: String) -> Bool {
        value.unicodeScalars.count == 64 && value.unicodeScalars.allSatisfy(isLowerHex)
    }

    private static func isLowerHex(_ scalar: Unicode.Scalar) -> Bool {
        ("0" ... "9").contains(scalar) || ("a" ... "f").contains(scalar)
    }

    /// Trimmed, non-empty, no Unicode Cc, within the character and byte limits.
    static func isValidExerciseName(_ name: String) -> Bool {
        !name.isEmpty &&
            name == name.trimmingCharacters(in: .whitespacesAndNewlines) &&
            name.unicodeScalars.count <= maximumExerciseCharacters &&
            name.utf8.count <= maximumExerciseBytes &&
            !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
    }

    static func isValidWeight(_ weight: Double) -> Bool {
        guard weight.isFinite, weightRange.contains(weight) else { return false }
        let scaled = weight * 100
        return abs(scaled - scaled.rounded()) < 1e-6
    }
}

// MARK: - Messages

struct WatchPlanSet: Codable, Equatable, Sendable {
    let weight: Double
    let reps: Int
}

struct WatchPlanExercise: Codable, Equatable, Sendable {
    let name: String
    let restSeconds: Int
    let sets: [WatchPlanSet]
}

struct WatchBoundContext: Codable, Equatable, Sendable {
    let accountBinding: String
    let language: String
    let planRevision: Int64
    let plan: [WatchPlanExercise]
    let exercises: [String]
}

/// Phone -> watch application context. `bound == nil` means `unbound`.
struct WatchContextMessage: Equatable, Sendable {
    let sentAtMillis: Int64
    let bound: WatchBoundContext?
}

enum WatchWorkoutMode: String, Codable, Sendable {
    case plan
    case free
}

enum WatchHealthKitStatus: String, Codable, Sendable {
    case saved
    case off
    case failed
}

struct WatchWorkoutSet: Codable, Equatable, Sendable {
    let exerciseName: String
    let weight: Double
    let reps: Int
    let completedAtMillis: Int64
}

/// Watch -> phone finished workout.
struct WatchWorkoutMessage: Equatable, Sendable {
    let requestId: String
    let accountBinding: String
    let mode: WatchWorkoutMode
    let planRevision: Int64?
    let startedAtMillis: Int64
    let endedAtMillis: Int64
    let durationSeconds: Int64
    let sets: [WatchWorkoutSet]
    let healthKit: WatchHealthKitStatus
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let activeKilocalories: Double?
}

enum WatchAckStatus: String, Sendable {
    case committed
    case duplicate
}

struct WatchAckMessage: Equatable, Sendable {
    let requestId: String
    let accountBinding: String
    let status: WatchAckStatus
}

enum WatchNackGroup: String, Sendable {
    /// Keep queued, retry with backoff.
    case transient
    /// Keep, do not send until the matching context arrives.
    case hold
    /// Keep as failed; only an explicit user Discard deletes it.
    case deterministic
}

enum WatchNackReason: String, CaseIterable, Sendable {
    case notReady = "not-ready"
    case storage
    case rateLimited = "rate-limited"
    case foreignAccount = "foreign-account"
    case unsupportedVersion = "unsupported-version"
    case malformed
    case conflict
    case invalid

    var group: WatchNackGroup {
        switch self {
        case .notReady, .storage, .rateLimited: return .transient
        case .foreignAccount, .unsupportedVersion: return .hold
        case .malformed, .conflict, .invalid: return .deterministic
        }
    }
}

struct WatchNackMessage: Equatable, Sendable {
    let requestId: String
    let reason: WatchNackReason
}

/// Result of decoding an inbound workout on the phone, in the contract's decision order.
enum WatchWorkoutDecodeResult: Equatable, Sendable {
    case valid(WatchWorkoutMessage)
    /// Over the size limit, not JSON or no valid requestId: cannot be correlated.
    case drop
    case unsupportedVersion(requestId: String)
    case malformed(requestId: String)
}

/// What the watch can read from a context of any protocol version.
struct WatchContextHeader: Equatable, Sendable {
    let protocolVersion: Int
    /// nil means `unbound`.
    let accountBinding: String?
}

/// Phone reply as seen by the watch.
enum WatchReply: Equatable, Sendable {
    case ack(WatchAckMessage)
    case nack(WatchNackMessage)
}

// MARK: - Codec

enum WatchSyncCodec {
    enum EncodeError: Error {
        case invalid
        case tooLarge
    }

    // MARK: Envelope

    /// The single-key WatchConnectivity dictionary carrying the JSON bytes.
    static func envelope(_ bytes: Data) -> [String: Any] {
        [WatchSync.envelopeKey: bytes]
    }

    /// Bytes of a single-key envelope within the size limit, else nil.
    static func envelopeBytes(from dictionary: [String: Any]) -> Data? {
        guard dictionary.count == 1,
              let bytes = dictionary[WatchSync.envelopeKey] as? Data,
              !bytes.isEmpty,
              bytes.count <= WatchSync.maximumEnvelopeBytes else {
            return nil
        }
        return bytes
    }

    /// Message `type` of an envelope payload, without validating the rest.
    static func messageType(of bytes: Data) -> String? {
        guard bytes.count <= WatchSync.maximumEnvelopeBytes,
              let object = jsonObject(bytes) else { return nil }
        return object["type"] as? String
    }

    // MARK: Encode

    static func encode(_ context: WatchContextMessage) throws -> Data {
        var object: [String: Any] = [
            "type": "context",
            "protocolVersion": WatchSync.protocolVersion,
            "sentAtMillis": NSNumber(value: context.sentAtMillis)
        ]
        if let bound = context.bound {
            object["state"] = "bound"
            object["accountBinding"] = bound.accountBinding
            object["language"] = bound.language
            object["planRevision"] = NSNumber(value: bound.planRevision)
            object["plan"] = bound.plan.map { exercise -> [String: Any] in
                [
                    "name": exercise.name,
                    "restSeconds": exercise.restSeconds,
                    "sets": exercise.sets.map { ["weight": $0.weight, "reps": $0.reps] as [String: Any] }
                ]
            }
            object["exercises"] = bound.exercises
        } else {
            object["state"] = "unbound"
        }
        let data = try serialize(object)
        guard case .success = decodeContextResult(data) else { throw EncodeError.invalid }
        return data
    }

    static func encode(_ workout: WatchWorkoutMessage, nowMillis: Int64) throws -> Data {
        var object: [String: Any] = [
            "type": "workout",
            "protocolVersion": WatchSync.protocolVersion,
            "requestId": workout.requestId,
            "accountBinding": workout.accountBinding,
            "mode": workout.mode.rawValue,
            "startedAtMillis": NSNumber(value: workout.startedAtMillis),
            "endedAtMillis": NSNumber(value: workout.endedAtMillis),
            "durationSeconds": NSNumber(value: workout.durationSeconds),
            "sets": workout.sets.map { set -> [String: Any] in
                [
                    "exerciseName": set.exerciseName,
                    "weight": set.weight,
                    "reps": set.reps,
                    "completedAtMillis": NSNumber(value: set.completedAtMillis)
                ]
            },
            "healthKit": workout.healthKit.rawValue
        ]
        if let value = workout.planRevision { object["planRevision"] = NSNumber(value: value) }
        if let value = workout.averageHeartRate { object["averageHeartRate"] = value }
        if let value = workout.maximumHeartRate { object["maximumHeartRate"] = value }
        if let value = workout.activeKilocalories { object["activeKilocalories"] = value }
        let data = try serialize(object)
        guard decodeWorkout(data, nowMillis: nowMillis) == .valid(workout) else {
            throw EncodeError.invalid
        }
        return data
    }

    static func encode(_ ack: WatchAckMessage) throws -> Data {
        guard WatchSync.isValidRequestID(ack.requestId),
              WatchSync.isValidHash(ack.accountBinding) else { throw EncodeError.invalid }
        return try serialize([
            "type": "ack",
            "protocolVersion": WatchSync.protocolVersion,
            "requestId": ack.requestId,
            "accountBinding": ack.accountBinding,
            "status": ack.status.rawValue
        ])
    }

    static func encode(_ nack: WatchNackMessage) throws -> Data {
        guard WatchSync.isValidRequestID(nack.requestId) else { throw EncodeError.invalid }
        return try serialize([
            "type": "nack",
            "protocolVersion": WatchSync.protocolVersion,
            "requestId": nack.requestId,
            "reason": nack.reason.rawValue
        ])
    }

    // MARK: Decode

    static func decodeContext(_ bytes: Data) -> WatchContextMessage? {
        if case .success(let value) = decodeContextResult(bytes) { return value }
        return nil
    }

    static func decodeReply(_ bytes: Data) -> WatchReply? {
        guard bytes.count <= WatchSync.maximumEnvelopeBytes,
              let object = jsonObject(bytes),
              integer(object["protocolVersion"]) == Int64(WatchSync.protocolVersion),
              let requestId = object["requestId"] as? String,
              WatchSync.isValidRequestID(requestId) else { return nil }
        switch object["type"] as? String {
        case "ack":
            guard Set(object.keys) == ["type", "protocolVersion", "requestId", "accountBinding", "status"],
                  let binding = object["accountBinding"] as? String,
                  WatchSync.isValidHash(binding),
                  let status = (object["status"] as? String).flatMap(WatchAckStatus.init(rawValue:)) else {
                return nil
            }
            return .ack(.init(requestId: requestId, accountBinding: binding, status: status))
        case "nack":
            guard Set(object.keys) == ["type", "protocolVersion", "requestId", "reason"],
                  let reason = (object["reason"] as? String).flatMap(WatchNackReason.init(rawValue:)) else {
                return nil
            }
            return .nack(.init(requestId: requestId, reason: reason))
        default:
            return nil
        }
    }

    /// Watch-only: version, state and account of a context of any protocol version. A newer
    /// phone must still be able to unbind the watch and release version holds.
    static func decodeContextHeader(_ bytes: Data) -> WatchContextHeader? {
        guard bytes.count <= WatchSync.maximumEnvelopeBytes,
              let object = jsonObject(bytes),
              object["type"] as? String == "context",
              let version = int(object["protocolVersion"], in: 1 ... 1_000_000) else { return nil }
        switch object["state"] as? String {
        case "unbound":
            return WatchContextHeader(protocolVersion: version, accountBinding: nil)
        case "bound":
            guard let binding = object["accountBinding"] as? String, WatchSync.isValidHash(binding) else { return nil }
            return WatchContextHeader(protocolVersion: version, accountBinding: binding)
        default:
            return nil
        }
    }

    /// Watch-only reply decode: strict for this protocol version; from a newer phone only
    /// the fields every version shares are read, so an ack still clears the outbox item.
    static func decodeReplyTolerant(_ bytes: Data) -> WatchReply? {
        if let strict = decodeReply(bytes) { return strict }
        guard bytes.count <= WatchSync.maximumEnvelopeBytes,
              let object = jsonObject(bytes),
              let version = integer(object["protocolVersion"]),
              version > Int64(WatchSync.protocolVersion),
              let requestId = object["requestId"] as? String,
              WatchSync.isValidRequestID(requestId) else { return nil }
        switch object["type"] as? String {
        case "ack":
            guard let binding = object["accountBinding"] as? String, WatchSync.isValidHash(binding) else { return nil }
            let status = (object["status"] as? String).flatMap(WatchAckStatus.init(rawValue:)) ?? .committed
            return .ack(.init(requestId: requestId, accountBinding: binding, status: status))
        case "nack":
            guard let reason = (object["reason"] as? String).flatMap(WatchNackReason.init(rawValue:)) else { return nil }
            return .nack(.init(requestId: requestId, reason: reason))
        default:
            return nil
        }
    }

    /// Phone-side decode following the contract's decision order:
    /// envelope bytes/JSON/requestId -> protocolVersion -> strict shape and bounds.
    static func decodeWorkout(_ bytes: Data, nowMillis: Int64) -> WatchWorkoutDecodeResult {
        guard !bytes.isEmpty,
              bytes.count <= WatchSync.maximumEnvelopeBytes,
              let object = jsonObject(bytes),
              let requestId = object["requestId"] as? String,
              WatchSync.isValidRequestID(requestId) else {
            return .drop
        }
        if let version = integer(object["protocolVersion"]), version > Int64(WatchSync.protocolVersion) {
            return .unsupportedVersion(requestId: requestId)
        }
        guard let message = strictWorkout(object, requestId: requestId, nowMillis: nowMillis) else {
            return .malformed(requestId: requestId)
        }
        return .valid(message)
    }

    // MARK: Private

    private enum ContextFailure: Error { case invalid }

    private static func decodeContextResult(_ bytes: Data) -> Result<WatchContextMessage, ContextFailure> {
        guard bytes.count <= WatchSync.maximumEnvelopeBytes,
              let object = jsonObject(bytes),
              object["type"] as? String == "context",
              integer(object["protocolVersion"]) == Int64(WatchSync.protocolVersion),
              let sentAt = integer(object["sentAtMillis"]),
              (0 ... WatchSync.maximumSafeInteger).contains(sentAt) else {
            return .failure(.invalid)
        }
        let required: Set<String> = ["type", "protocolVersion", "state", "sentAtMillis"]
        switch object["state"] as? String {
        case "unbound":
            guard Set(object.keys) == required else { return .failure(.invalid) }
            return .success(.init(sentAtMillis: sentAt, bound: nil))
        case "bound":
            guard Set(object.keys) == required.union(["accountBinding", "language", "planRevision", "plan", "exercises"]),
                  let binding = object["accountBinding"] as? String,
                  WatchSync.isValidHash(binding),
                  let language = object["language"] as? String,
                  WatchSync.languages.contains(language),
                  let revision = integer(object["planRevision"]),
                  WatchSync.planRevisionRange.contains(revision),
                  let rawPlan = object["plan"] as? [Any],
                  rawPlan.count <= WatchSync.maximumPlanExercises,
                  let rawExercises = object["exercises"] as? [Any],
                  rawExercises.count <= WatchSync.maximumCatalogNames else {
                return .failure(.invalid)
            }
            var plan: [WatchPlanExercise] = []
            var totalSets = 0
            var planBytes = 0
            for rawExercise in rawPlan {
                guard let exercise = rawExercise as? [String: Any],
                      Set(exercise.keys) == ["name", "restSeconds", "sets"],
                      let name = exercise["name"] as? String,
                      WatchSync.isValidExerciseName(name),
                      let rest = int(exercise["restSeconds"], in: WatchSync.restSecondsRange),
                      let rawSets = exercise["sets"] as? [Any],
                      (1 ... WatchSync.maximumSetsPerExercise).contains(rawSets.count) else {
                    return .failure(.invalid)
                }
                planBytes += name.utf8.count
                totalSets += rawSets.count
                guard planBytes <= WatchSync.maximumTotalExerciseBytes,
                      totalSets <= WatchSync.maximumPlanSets else { return .failure(.invalid) }
                var sets: [WatchPlanSet] = []
                for rawSet in rawSets {
                    guard let set = rawSet as? [String: Any],
                          Set(set.keys) == ["weight", "reps"],
                          let weight = number(set["weight"]),
                          WatchSync.isValidWeight(weight),
                          let reps = int(set["reps"], in: WatchSync.repsRange) else {
                        return .failure(.invalid)
                    }
                    sets.append(.init(weight: weight, reps: reps))
                }
                plan.append(.init(name: name, restSeconds: rest, sets: sets))
            }
            var names: [String] = []
            var seen = Set<String>()
            var catalogBytes = 0
            for rawName in rawExercises {
                guard let name = rawName as? String,
                      WatchSync.isValidExerciseName(name),
                      seen.insert(name).inserted else { return .failure(.invalid) }
                catalogBytes += name.utf8.count
                guard catalogBytes <= WatchSync.maximumTotalExerciseBytes else { return .failure(.invalid) }
                names.append(name)
            }
            return .success(.init(
                sentAtMillis: sentAt,
                bound: .init(
                    accountBinding: binding,
                    language: language,
                    planRevision: revision,
                    plan: plan,
                    exercises: names
                )
            ))
        default:
            return .failure(.invalid)
        }
    }

    private static func strictWorkout(
        _ object: [String: Any],
        requestId: String,
        nowMillis: Int64
    ) -> WatchWorkoutMessage? {
        let required: Set<String> = [
            "type", "protocolVersion", "requestId", "accountBinding", "mode", "startedAtMillis",
            "endedAtMillis", "durationSeconds", "sets", "healthKit"
        ]
        let optional: Set<String> = ["planRevision", "averageHeartRate", "maximumHeartRate", "activeKilocalories"]
        let keys = Set(object.keys)
        guard required.isSubset(of: keys),
              keys.isSubset(of: required.union(optional)),
              object["type"] as? String == "workout",
              integer(object["protocolVersion"]) == Int64(WatchSync.protocolVersion),
              let binding = object["accountBinding"] as? String,
              WatchSync.isValidHash(binding),
              let mode = (object["mode"] as? String).flatMap(WatchWorkoutMode.init(rawValue:)),
              let healthKit = (object["healthKit"] as? String).flatMap(WatchHealthKitStatus.init(rawValue:)),
              let startedAt = integer(object["startedAtMillis"]),
              let endedAt = integer(object["endedAtMillis"]),
              let duration = integer(object["durationSeconds"]),
              startedAt >= WatchSync.minimumStartedAtMillis,
              endedAt > startedAt,
              endedAt <= nowMillis + WatchSync.maximumFutureSkewMillis,
              WatchSync.durationSecondsRange.contains(duration),
              duration <= (endedAt - startedAt + 999) / 1_000,
              let rawSets = object["sets"] as? [Any],
              rawSets.count <= WatchSync.maximumWorkoutSets else {
            return nil
        }

        let planRevision: Int64?
        if let raw = object["planRevision"] {
            guard mode == .plan,
                  let value = integer(raw),
                  WatchSync.planRevisionRange.contains(value) else { return nil }
            planRevision = value
        } else {
            planRevision = nil
        }

        let hasAverage = object["averageHeartRate"] != nil
        let hasMaximum = object["maximumHeartRate"] != nil
        guard hasAverage == hasMaximum else { return nil }
        var averageHeartRate: Int?
        var maximumHeartRate: Int?
        if hasAverage {
            guard let average = int(object["averageHeartRate"], in: WatchSync.heartRateRange),
                  let maximum = int(object["maximumHeartRate"], in: WatchSync.heartRateRange),
                  average <= maximum else { return nil }
            averageHeartRate = average
            maximumHeartRate = maximum
        }

        var activeKilocalories: Double?
        if let raw = object["activeKilocalories"] {
            guard let value = number(raw),
                  value.isFinite,
                  WatchSync.activeKilocaloriesRange.contains(value) else { return nil }
            activeKilocalories = value
        }

        let lowerTime = startedAt - WatchSync.setTimeToleranceMillis
        let upperTime = endedAt + WatchSync.setTimeToleranceMillis
        var totalBytes = 0
        var sets: [WatchWorkoutSet] = []
        sets.reserveCapacity(rawSets.count)
        for rawSet in rawSets {
            guard let set = rawSet as? [String: Any],
                  Set(set.keys) == ["exerciseName", "weight", "reps", "completedAtMillis"],
                  let name = set["exerciseName"] as? String,
                  WatchSync.isValidExerciseName(name),
                  let weight = number(set["weight"]),
                  WatchSync.isValidWeight(weight),
                  let reps = int(set["reps"], in: WatchSync.repsRange),
                  let completedAt = integer(set["completedAtMillis"]),
                  (lowerTime ... upperTime).contains(completedAt) else {
                return nil
            }
            totalBytes += name.utf8.count
            guard totalBytes <= WatchSync.maximumTotalExerciseBytes else { return nil }
            sets.append(.init(exerciseName: name, weight: weight, reps: reps, completedAtMillis: completedAt))
        }

        return WatchWorkoutMessage(
            requestId: requestId,
            accountBinding: binding,
            mode: mode,
            planRevision: planRevision,
            startedAtMillis: startedAt,
            endedAtMillis: endedAt,
            durationSeconds: duration,
            sets: sets,
            healthKit: healthKit,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            activeKilocalories: activeKilocalories
        )
    }

    private static func serialize(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw EncodeError.invalid }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= WatchSync.maximumEnvelopeBytes else { throw EncodeError.tooLarge }
        return data
    }

    private static func jsonObject(_ bytes: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: bytes, options: [])) as? [String: Any]
    }

    /// A JSON number that is not a boolean.
    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// An exact JSON integer inside `range`. Narrowed with `Int(exactly:)` so an
    /// out-of-range value is rejected instead of trapping where `Int` is 32-bit (arm64_32 watches).
    private static func int(_ value: Any?, in range: ClosedRange<Int>) -> Int? {
        guard let raw = integer(value),
              let narrowed = Int(exactly: raw),
              range.contains(narrowed) else { return nil }
        return narrowed
    }

    /// A JSON number that is an exact integer within the safe-integer range.
    private static func integer(_ value: Any?) -> Int64? {
        guard let double = number(value),
              double == double.rounded(),
              abs(double) <= Double(WatchSync.maximumSafeInteger) else { return nil }
        return Int64(double)
    }
}
