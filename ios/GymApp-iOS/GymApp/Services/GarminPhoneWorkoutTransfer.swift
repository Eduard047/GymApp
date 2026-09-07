import Foundation
import CoreFoundation

/// The caller stores `state` durably before sending a partial acknowledgement.
struct GarminPhoneTransferStep {
    let state: Data
    let nextOffset: Int
    let attemptID: String
    let completeMessage: [AnyHashable: Any]?
}

enum GarminPhoneWorkoutTransfer {
    private static let maximumFrameBytes = 4096
    private static let maximumStateBytes = 65536
    private static let maximumAge: TimeInterval = 86400
    private static let frameKeys: Set<String> = [
        "type", "transferVersion", "offset", "totalSets", "attemptId", "metadata", "set", "interval", "metrics"
    ]
    private static let metadataKeys: Set<String> = [
        "type", "bindingVersion", "workoutMode", "requestId", "accountBinding", "deviceBinding",
        "pairingGeneration", "startedAtSeconds", "durationSeconds", "gymCalories", "garminCalories",
        "avgHeartRate", "maxHeartRate", "lastHeartRate", "heartRateZone", "plannedSetCount",
        "plannedTargetSetCount", "completedPlannedSetCount"
    ]
    private static let stateKeys: Set<String> = [
        "version", "createdAt", "totalSets", "metadata", "sets", "intervals", "metrics"
    ]
    private enum Invalid: Error { case state }
    private static func check(_ value: Bool) throws { if !value { throw Invalid.state } }

    static func accept(
        previous: Data?, raw: Any, binding: GarminPhoneBinding, now: Date = Date()
    ) -> GarminPhoneTransferStep? {
        try? acceptValidated(previous: previous, raw: raw, binding: binding, now: now)
    }

    private static func acceptValidated(
        previous: Data?, raw: Any, binding: GarminPhoneBinding, now: Date
    ) throws -> GarminPhoneTransferStep {
        guard let frame = raw as? [String: Any], bounded(frame, depth: 0),
              Set(frame.keys).isSubset(of: frameKeys),
              let metadata = frame["metadata"] as? [String: Any],
              Set(metadata.keys).isSubset(of: metadataKeys),
              frame["type"] as? String == "workout_part",
              integer(frame["transferVersion"], 1, 1) == 1,
              let attemptID = frame["attemptId"] as? String,
              GarminPhoneSyncProtocol.isValidMessageID(attemptID),
              let total = integer(frame["totalSets"], 0, 60),
              let offset = integer(frame["offset"], 0, total == 0 ? 0 : total - 1) else {
            throw Invalid.state
        }
        try check(encode(frame).count <= maximumFrameBytes)
        let free = metadata["workoutMode"] as? String == "free"
        try check((total == 0) == free)
        if free {
            try check(frame["set"] == nil && frame["interval"] == nil && frame["metrics"] == nil)
        } else {
            guard let row = frame["set"] as? [String: Any],
                  Set(row.keys) == ["exerciseName", "weight", "reps"] else { throw Invalid.state }
        }
        // Check all metadata with the released parser and the declared set count.
        // Real rows and cumulative interval consistency are validated separately.
        var scalarCheck = metadata
        scalarCheck["sets"] = (0 ..< total).map { _ in ["exerciseName": "X", "weight": 0, "reps": 1] as [String: Any] }
        try check(GarminPhoneWorkoutParser.parse(scalarCheck, expectedBinding: binding, now: now) != nil)
        var rowCheck = withoutPlanProgress(metadata)
        rowCheck["sets"] = free ? [] : [frame["set"]!]
        if let interval = frame["interval"] { rowCheck["setIntervals"] = [interval] }
        if let metrics = frame["metrics"] { rowCheck["setMetrics"] = [metrics] }
        try check(GarminPhoneWorkoutParser.parse(rowCheck, expectedBinding: binding, now: now) != nil)

        var retained: [String: Any]?
        if let previous {
            let old = try decode(previous)
            try check(Set(old.keys).isSubset(of: stateKeys))
            guard let milliseconds = integer64(old["createdAt"]), milliseconds >= 0 else { throw Invalid.state }
            let created = TimeInterval(milliseconds) / 1000
            try check(created <= now.timeIntervalSince1970)
            guard let oldMetadata = old["metadata"] as? [String: Any] else { throw Invalid.state }
            if now.timeIntervalSince1970 - created <= maximumAge &&
                oldMetadata["accountBinding"] as? String == binding.account &&
                oldMetadata["deviceBinding"] as? String == binding.device &&
                oldMetadata["pairingGeneration"] as? String == binding.pairingGeneration { retained = old }
        }
        var sets: [Any] = []
        var intervals: [Any]? = frame["interval"] != nil ? [] : nil
        var metrics: [Any]? = frame["metrics"] != nil ? [] : nil
        var created = Int64(now.timeIntervalSince1970 * 1000)
        if let retained {
            try check(integer(retained["version"], 1, 1) == 1 && integer(retained["totalSets"], 0, 60) == total)
            guard let oldMetadata = retained["metadata"] as? [String: Any],
                  let oldSets = retained["sets"] as? [Any] else { throw Invalid.state }
            try check(encode(oldMetadata) == encode(metadata))
            sets = oldSets
            intervals = retained["intervals"] as? [Any]
            metrics = retained["metrics"] as? [Any]
            try check(sets.count <= total && (intervals == nil || intervals!.count == sets.count) &&
                (metrics == nil || metrics!.count == sets.count))
            try check((intervals != nil) == (frame["interval"] != nil) &&
                (metrics != nil) == (frame["metrics"] != nil))
            created = integer64(retained["createdAt"])!
        } else { try check(offset == 0) }
        try check(offset <= sets.count)
        if !free {
            if offset == sets.count {
                sets.append(frame["set"]!)
                intervals?.append(frame["interval"]!)
                metrics?.append(frame["metrics"]!)
            } else {
                try check(encode(sets[offset]) == encode(frame["set"]!))
                if let intervals { try check(encode(intervals[offset]) == encode(frame["interval"]!)) }
                if let metrics { try check(encode(metrics[offset]) == encode(frame["metrics"]!)) }
            }
        }
        // Disk state is untrusted. Check the complete retained prefix after a
        // restart as well as each new row before it can be acknowledged.
        if !sets.isEmpty {
            var prefix = withoutPlanProgress(metadata)
            prefix["sets"] = sets
            if let intervals { prefix["setIntervals"] = intervals }
            if let metrics { prefix["setMetrics"] = metrics }
            try check(GarminPhoneWorkoutParser.parse(prefix, expectedBinding: binding, now: now) != nil)
        }
        var state: [String: Any] = [
            "version": 1, "createdAt": created, "totalSets": total, "metadata": metadata, "sets": sets
        ]
        if let intervals { state["intervals"] = intervals }
        if let metrics { state["metrics"] = metrics }
        let encoded = try encode(state)
        try check(encoded.count <= maximumStateBytes)
        var complete: [AnyHashable: Any]?
        if sets.count == total {
            var message = metadata
            message["sets"] = sets
            if let intervals { message["setIntervals"] = intervals }
            if let metrics { message["setMetrics"] = metrics }
            try check(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding, now: now) != nil)
            complete = message
        }
        return GarminPhoneTransferStep(state: encoded, nextOffset: sets.count, attemptID: attemptID, completeMessage: complete)
    }

    private static func withoutPlanProgress(_ metadata: [String: Any]) -> [String: Any] {
        var result = metadata
        result.removeValue(forKey: "plannedSetCount")
        result.removeValue(forKey: "plannedTargetSetCount")
        result.removeValue(forKey: "completedPlannedSetCount")
        return result
    }

    private static func integer64(_ value: Any?) -> Int64? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        guard d.isFinite, d.rounded(.towardZero) == d, abs(d) <= 9_007_199_254_740_991 else { return nil }
        return Int64(d)
    }

    private static func integer(_ value: Any?, _ minimum: Int, _ maximum: Int) -> Int? {
        guard let n = integer64(value), n >= minimum, n <= maximum else { return nil }
        return Int(n)
    }

    private static func bounded(_ value: Any, depth: Int) -> Bool {
        if depth > 4 { return false }
        if value is NSNull { return true }
        if let s = value as? String { return s.utf8.prefix(641).count <= 640 }
        if let n = value as? NSNumber { return n.doubleValue.isFinite }
        if let a = value as? [Any] { return a.count <= 60 && a.allSatisfy { bounded($0, depth: depth + 1) } }
        if let d = value as? [String: Any] {
            return d.count <= 20 && d.allSatisfy { $0.key.utf8.count <= 32 && bounded($0.value, depth: depth + 1) }
        }
        return false
    }

    private static func encode(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        try check(data.count <= maximumStateBytes)
        var depth = 0
        var quoted = false
        var escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else {
                if byte == 34 { quoted = true }
                else if byte == 91 || byte == 123 { depth += 1; try check(depth <= 5) }
                else if byte == 93 || byte == 125 { depth -= 1; try check(depth >= 0) }
            }
        }
        try check(depth == 0 && !quoted)
        guard let state = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Invalid.state }
        return state
    }
}
