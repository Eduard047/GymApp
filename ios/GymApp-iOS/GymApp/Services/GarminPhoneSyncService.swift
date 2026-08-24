import Combine
import ConnectIQ
import CoreFoundation
import CryptoKit
import Foundation

struct GarminPhoneDeviceSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let model: String
    let connected: Bool
}

struct GarminPhoneBinding: Codable, Equatable {
    let account: String
    let device: String
    let pairingGeneration: String
}

enum GarminPhoneBindingHandshake: String, Codable, Equatable {
    case proof
    case repair
    case reset
}

struct GarminPhonePendingAuthTransition: Codable, Equatable {
    let binding: GarminPhoneBinding
    let syncID: String
    let revision: Int64
    let language: String
    let exercises: [String]
    let handshake: GarminPhoneBindingHandshake
}

struct GarminPhoneSyncRequestClaim: Equatable {
    let account: String
    let device: String
    let pairingGeneration: String?
}

private struct GarminPhoneDeviceHandshakeMarker: Codable, Equatable {
    let bindingScope: String
    let syncID: String
    let revision: Int64
}

private struct GarminPhoneResetAuthorization: Codable, Equatable {
    let deviceBinding: String
    let targetBindingScope: String
    let proofSyncID: String
    let proofRevision: Int64
    let previousBindingScope: String
    let previousSyncID: String
    let previousRevision: Int64
}

enum GarminPhoneSyncProtocol {
    static let maximumSyncRevision: Int64 = 9_007_199_254_740_991
    static let maximumMessageEntries = 16

    static func nextRevision(lastRevision: Int64?, nowMilliseconds: Int64) -> Int64? {
        guard nowMilliseconds > 0,
              nowMilliseconds <= maximumSyncRevision,
              lastRevision.map({ (0 ... maximumSyncRevision).contains($0) }) ?? true else {
            return nil
        }
        guard let lastRevision else { return nowMilliseconds }
        guard lastRevision < maximumSyncRevision else { return nil }
        return max(nowMilliseconds, lastRevision + 1)
    }

    static func boundedExerciseCatalog(_ candidates: [String]) -> [String] {
        var totalBytes = 0
        var values: [String] = []
        values.reserveCapacity(min(candidates.count, GarminPhoneWorkoutParser.maximumSets))
        for candidate in candidates {
            guard values.count < GarminPhoneWorkoutParser.maximumSets else { break }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let bytes = trimmed.utf8.count
            guard !trimmed.isEmpty,
                  trimmed.utf16.count <= GarminPhoneWorkoutParser.maximumExerciseCharacters,
                  bytes <= GarminPhoneWorkoutParser.maximumExerciseBytes,
                  !trimmed.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }) else {
                continue
            }
            guard totalBytes <= GarminPhoneWorkoutParser.maximumTotalExerciseBytes - bytes else {
                break
            }
            totalBytes += bytes
            values.append(trimmed)
        }
        return values
    }

    static func syncPayload(
        binding: GarminPhoneBinding,
        syncID: String,
        revision: Int64,
        language: String,
        exercises: [String],
        resetWorkout: Bool,
        repairPairing: Bool = false
    ) -> [String: Any]? {
        guard binding.account.isGarminBinding,
              binding.device.utf8.count <= 128,
              !binding.device.isEmpty,
              binding.pairingGeneration.isGarminBinding,
              isValidMessageID(syncID),
              (1 ... maximumSyncRevision).contains(revision),
              ["en", "uk", "ru"].contains(language),
              !(resetWorkout && repairPairing),
              exercises.count <= GarminPhoneWorkoutParser.maximumSets else {
            return nil
        }

        let boundedExercises: [String]
        if resetWorkout {
            boundedExercises = []
        } else {
            var totalBytes = 0
            var values: [String] = []
            values.reserveCapacity(exercises.count)
            for exercise in exercises {
                let trimmed = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
                let bytes = trimmed.utf8.count
                guard !trimmed.isEmpty,
                      trimmed.utf16.count <= GarminPhoneWorkoutParser.maximumExerciseCharacters,
                      bytes <= GarminPhoneWorkoutParser.maximumExerciseBytes,
                      totalBytes <= GarminPhoneWorkoutParser.maximumTotalExerciseBytes - bytes,
                      !trimmed.unicodeScalars.contains(where: {
                          CharacterSet.controlCharacters.contains($0)
                      }) else {
                    return nil
                }
                totalBytes += bytes
                values.append(trimmed)
            }
            boundedExercises = values
        }

        var payload: [String: Any] = [
            "type": "sync",
            "bindingVersion": GarminPhoneWorkoutParser.bindingVersion,
            "syncId": syncID,
            "requestId": syncID,
            "bindingSource": "phone",
            "accountBinding": binding.account,
            "deviceBinding": binding.device,
            "pairingGeneration": binding.pairingGeneration,
            "syncRevision": revision,
            "language": language,
            "planNames": [],
            "planWeights": [],
            "planReps": [],
            "exercises": boundedExercises
        ]
        if repairPairing {
            payload["repairPairing"] = true
        } else {
            payload["resetWorkout"] = resetWorkout
        }
        return payload
    }

    static func syncRequestClaim(
        _ rawMessage: Any,
        sourceDeviceBinding: String
    ) -> GarminPhoneSyncRequestClaim? {
        let allowedKeys = Set([
            "type", "bindingVersion", "requestId", "accountBinding", "deviceBinding",
            "pairingGeneration", "pairingGenerationSupported", "watchVersion", "status"
        ])
        guard sourceDeviceBinding.utf8.count <= 128,
              !sourceDeviceBinding.isEmpty,
              let message = dictionary(rawMessage),
              message.count <= allowedKeys.count,
              message.keys.allSatisfy({ key in
                  guard let key = key as? String else { return false }
                  return allowedKeys.contains(key)
              }),
              message["type"] as? String == "request_sync",
              integer(message["bindingVersion"]) ==
                Int64(GarminPhoneWorkoutParser.bindingVersion),
              let requestID = message["requestId"] as? String,
              isValidMessageID(requestID),
              let account = message["accountBinding"] as? String,
              account.isGarminBinding,
              let device = message["deviceBinding"] as? String,
              device == sourceDeviceBinding else {
            return nil
        }
        let generation: String?
        if let rawGeneration = message["pairingGeneration"] {
            guard let rawGeneration = rawGeneration as? String,
                  rawGeneration.isGarminBinding else {
                return nil
            }
            generation = rawGeneration
        } else {
            generation = nil
        }
        if let supported = message["pairingGenerationSupported"],
           boolean(supported) == nil {
            return nil
        }
        if let rawVersion = message["watchVersion"] {
            guard let version = rawVersion as? String,
                  version.utf8.count <= 64 else {
                return nil
            }
        }
        if let rawStatus = message["status"] {
            guard let status = rawStatus as? String,
                  status.utf8.count <= 64 else {
                return nil
            }
        }
        return GarminPhoneSyncRequestClaim(
            account: account,
            device: device,
            pairingGeneration: generation
        )
    }

    static func acknowledgementMatches(
        _ rawMessage: Any,
        expected: GarminPhonePendingAuthTransition,
        sourceDeviceBinding: String
    ) -> Bool {
        guard sourceDeviceBinding == expected.binding.device,
              expected.binding.account.isGarminBinding,
              expected.binding.pairingGeneration.isGarminBinding,
              isValidMessageID(expected.syncID),
              (1 ... maximumSyncRevision).contains(expected.revision),
              let message = dictionary(rawMessage),
              message.count <= maximumMessageEntries,
              message["type"] as? String == "sync_ack",
              integer(message["bindingVersion"]) == Int64(GarminPhoneWorkoutParser.bindingVersion),
              message["syncId"] as? String == expected.syncID,
              message["requestId"] as? String == expected.syncID,
              integer(message["syncRevision"]) == expected.revision,
              message["accountBinding"] as? String == expected.binding.account,
              message["deviceBinding"] as? String == expected.binding.device,
              message["pairingGeneration"] as? String == expected.binding.pairingGeneration,
              boolean(message["applied"]) == true else {
            return false
        }
        return true
    }

    private static func dictionary(_ value: Any) -> [AnyHashable: Any]? {
        if let value = value as? [AnyHashable: Any] { return value }
        guard let value = value as? NSDictionary,
              value.count <= maximumMessageEntries else {
            return nil
        }
        var result: [AnyHashable: Any] = [:]
        for (key, item) in value {
            guard let key = key as? AnyHashable else { return nil }
            result[key] = item
        }
        return result
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let raw = number.doubleValue
        guard raw.isFinite,
              raw.rounded(.towardZero) == raw,
              raw >= 0,
              raw <= Double(maximumSyncRevision) else {
            return nil
        }
        return Int64(raw)
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    static func isValidMessageID(_ value: String) -> Bool {
        value.utf8.count >= 16 && value.utf8.count <= 128 &&
            value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0)
            }
    }
}

protocol GarminPhoneConnectIQTransport: AnyObject {
    func initialize(urlScheme: String, restorationIdentifier: String)
    func showDeviceSelection()
    func parseDeviceSelectionResponse(from url: URL) -> [IQDevice]?
    func registerDeviceEvents(_ device: IQDevice, delegate: IQDeviceEventDelegate)
    func unregisterAllDeviceEvents(delegate: IQDeviceEventDelegate)
    func deviceStatus(_ device: IQDevice) -> IQDeviceStatus
    func registerAppMessages(_ app: IQApp, delegate: IQAppMessageDelegate)
    func unregisterAllAppMessages(delegate: IQAppMessageDelegate)
    func send(
        _ message: [String: Any],
        to app: IQApp,
        completion: @escaping (Bool) -> Void
    )
}

private final class LiveGarminPhoneConnectIQTransport: GarminPhoneConnectIQTransport {
    private let connectIQ: ConnectIQ

    init(connectIQ: ConnectIQ = ConnectIQ.sharedInstance()) {
        self.connectIQ = connectIQ
    }

    func initialize(urlScheme: String, restorationIdentifier: String) {
        self.connectIQ.initialize(
            withUrlScheme: urlScheme,
            uiOverrideDelegate: nil,
            stateRestorationIdentifier: restorationIdentifier
        )
    }

    func showDeviceSelection() {
        connectIQ.showDeviceSelection()
    }

    func parseDeviceSelectionResponse(from url: URL) -> [IQDevice]? {
        connectIQ.parseDeviceSelectionResponse(from: url) as? [IQDevice]
    }

    func registerDeviceEvents(_ device: IQDevice, delegate: IQDeviceEventDelegate) {
        connectIQ.register(forDeviceEvents: device, delegate: delegate)
    }

    func unregisterAllDeviceEvents(delegate: IQDeviceEventDelegate) {
        connectIQ.unregister(forAllDeviceEvents: delegate)
    }

    func deviceStatus(_ device: IQDevice) -> IQDeviceStatus {
        connectIQ.getDeviceStatus(device)
    }

    func registerAppMessages(_ app: IQApp, delegate: IQAppMessageDelegate) {
        connectIQ.register(forAppMessages: app, delegate: delegate)
    }

    func unregisterAllAppMessages(delegate: IQAppMessageDelegate) {
        connectIQ.unregister(forAllAppMessages: delegate)
    }

    func send(
        _ message: [String: Any],
        to app: IQApp,
        completion: @escaping (Bool) -> Void
    ) {
        connectIQ.sendMessage(
            message,
            to: app,
            progress: { _, _ in },
            completion: { completion($0 == .success) },
            isTransient: false
        )
    }
}

struct GarminPhoneSetStatistics: Codable, Equatable {
    let activeSeconds: Int64?
    let restBeforeSeconds: Int64?
    let startHeartRate: Int?
    let peakHeartRate: Int?
    let endHeartRate: Int?
    let recoveryHeartRateDrop: Int?
    let detectionConfidence: Int?
}

struct GarminPhoneSetInterval: Codable, Equatable {
    let startSeconds: Int64
    let endSeconds: Int64
    let gymCalories: Double
    let garminCalories: Int?
    let heartRateZoneSeconds: [Int64]
}

enum GarminPhoneWorkoutMode: String, Codable, Equatable {
    case planned
    case free
}

struct GarminPhoneWorkoutCommand: Codable, Equatable {
    let requestID: String
    let startedAtSeconds: Int64
    let mode: GarminPhoneWorkoutMode
    let sets: [NamedWorkoutSetDraft]
    let plannedSetCount: Int?
    let plannedTargetSetCount: Int?
    let completedPlannedSetCount: Int?
    let durationSeconds: Int64?
    let gymCalories: Double?
    let garminCalories: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let endingHeartRateZone: Int?
    let setStatistics: [GarminPhoneSetStatistics?]
    let setIntervals: [GarminPhoneSetInterval?]

    var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if mode == .free {
            let identity = GarminPhoneFreeWorkoutReceiptIdentity(
                version: 1,
                mode: mode,
                requestID: requestID,
                startedAtSeconds: startedAtSeconds,
                durationSeconds: durationSeconds,
                gymCalories: gymCalories,
                garminCalories: garminCalories,
                averageHeartRate: averageHeartRate,
                maximumHeartRate: maximumHeartRate,
                endingHeartRateZone: endingHeartRateZone
            )
            let data = (try? encoder.encode(identity)) ?? Data()
            return data.garminSHA256Hex
        }
        // Keep the released receipt identity stable. Exact planned/completed progress
        // and `setIntervals` are diagnostic enrichments; older clients ignored them
        // before persisting the same core workout and may replay after an ack loss.
        let legacyIdentity = GarminPhoneWorkoutReceiptIdentity(
            requestID: requestID,
            startedAtSeconds: startedAtSeconds,
            sets: sets,
            durationSeconds: durationSeconds,
            gymCalories: gymCalories,
            garminCalories: garminCalories,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            endingHeartRateZone: endingHeartRateZone,
            setStatistics: setStatistics
        )
        let data = (try? encoder.encode(legacyIdentity)) ?? Data()
        return data.garminSHA256Hex
    }
}

private struct GarminPhoneFreeWorkoutReceiptIdentity: Codable {
    let version: Int
    let mode: GarminPhoneWorkoutMode
    let requestID: String
    let startedAtSeconds: Int64
    let durationSeconds: Int64?
    let gymCalories: Double?
    let garminCalories: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let endingHeartRateZone: Int?
}

private struct GarminPhoneWorkoutReceiptIdentity: Codable {
    let requestID: String
    let startedAtSeconds: Int64
    let sets: [NamedWorkoutSetDraft]
    let durationSeconds: Int64?
    let gymCalories: Double?
    let garminCalories: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let endingHeartRateZone: Int?
    let setStatistics: [GarminPhoneSetStatistics?]
}

enum GarminPhoneWorkoutParser {
    static let bindingVersion = 2
    static let maximumMessageEntries = 32
    static let maximumSets = 60
    static let maximumSetEntries = 8
    static let maximumExerciseCharacters = 160
    static let maximumExerciseBytes = 640
    static let maximumTotalExerciseBytes = 12_000
    static let maximumRequestIDBytes = 128
    static let maximumDurationSeconds: Int64 = 7 * 24 * 60 * 60
    static let minimumStartedAtSeconds: Int64 = 946_684_800
    static let maximumFutureSkewSeconds: Int64 = 24 * 60 * 60
    static let setIntervalCalorieRoundingTolerance = 0.1

    static func parse(
        _ rawMessage: Any,
        expectedBinding: GarminPhoneBinding,
        now: Date = Date()
    ) -> GarminPhoneWorkoutCommand? {
        guard let message = dictionary(rawMessage),
              message.count <= maximumMessageEntries,
              string(message["type"], maximumBytes: 20) == "create_workout",
              integer(message["bindingVersion"], minimum: 2, maximum: 2) == bindingVersion,
              string(message["accountBinding"], maximumBytes: 64) == expectedBinding.account,
              string(message["deviceBinding"], maximumBytes: 128) == expectedBinding.device,
              string(message["pairingGeneration"], maximumBytes: 64) ==
                expectedBinding.pairingGeneration,
              let requestID = string(
                message["requestId"],
                maximumBytes: maximumRequestIDBytes
              ),
              requestID.utf8.count >= 16,
              requestID.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0)
              }),
              let rawSets = array(message["sets"]) else {
            return nil
        }

        let mode: GarminPhoneWorkoutMode
        if message["workoutMode"] == nil {
            mode = .planned
        } else if let rawMode = string(message["workoutMode"], maximumBytes: 16),
                  let parsedMode = GarminPhoneWorkoutMode(rawValue: rawMode) {
            mode = parsedMode
        } else {
            return nil
        }
        guard mode == .free ? rawSets.isEmpty : (1 ... maximumSets).contains(rawSets.count) else {
            return nil
        }
        if mode == .free,
           (
               message["plannedSetCount"] != nil ||
                message["plannedTargetSetCount"] != nil ||
                message["completedPlannedSetCount"] != nil ||
                message["setMetrics"] != nil ||
                message["setIntervals"] != nil
           ) {
            return nil
        }

        var totalExerciseBytes = 0
        var sets: [NamedWorkoutSetDraft] = []
        sets.reserveCapacity(rawSets.count)
        for rawSet in rawSets {
            guard let set = dictionary(rawSet),
                  set.count <= maximumSetEntries,
                  let rawName = string(
                    set["exerciseName"],
                    maximumBytes: maximumExerciseBytes
                  ),
                  rawName.utf16.count <= maximumExerciseCharacters else {
                return nil
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  !name.unicodeScalars.contains(where: {
                      CharacterSet.controlCharacters.contains($0)
                  }),
                  let weight = finiteDouble(set["weight"], minimum: 0, maximum: 1_000_000),
                  let reps = integer(set["reps"], minimum: 1, maximum: 10_000) else {
                return nil
            }
            totalExerciseBytes += name.utf8.count
            guard totalExerciseBytes <= maximumTotalExerciseBytes else { return nil }
            sets.append(
                NamedWorkoutSetDraft(
                    exerciseName: name,
                    weight: weight,
                    reps: reps
                )
            )
        }

        let plannedSetCount: Int? = optionalInteger(
            message["plannedSetCount"],
            minimum: sets.count,
            maximum: maximumSets
        )
        guard optionalNumberWasValid(
            message["plannedSetCount"],
            parsed: plannedSetCount
        ) else {
            return nil
        }

        let plannedTargetSetCount: Int? = optionalInteger(
            message["plannedTargetSetCount"],
            minimum: 1,
            maximum: maximumSets
        )
        guard optionalNumberWasValid(
            message["plannedTargetSetCount"],
            parsed: plannedTargetSetCount
        ) else {
            return nil
        }

        let completedPlannedSetCount: Int?
        if let rawCompletedCount = message["completedPlannedSetCount"] {
            guard !(rawCompletedCount is NSNull),
                  let completedCount = integer(
                      rawCompletedCount,
                      minimum: 0,
                      maximum: maximumSets
                  ),
                  let plannedSetCount,
                  let plannedTargetSetCount,
                  plannedSetCount >= plannedTargetSetCount,
                  completedCount <= min(plannedTargetSetCount, sets.count) else {
                return nil
            }
            completedPlannedSetCount = completedCount
        } else {
            completedPlannedSetCount = nil
        }
        let hasPlannedTargetSetCount = message["plannedTargetSetCount"] != nil
        let hasCompletedPlannedSetCount = message["completedPlannedSetCount"] != nil
        guard hasPlannedTargetSetCount == hasCompletedPlannedSetCount else { return nil }

        let setStatistics: [GarminPhoneSetStatistics?]
        if message["setMetrics"] == nil || message["setMetrics"] is NSNull {
            setStatistics = Array(repeating: nil, count: sets.count)
        } else {
            guard let metrics = array(message["setMetrics"]),
                  metrics.count == sets.count else {
                return nil
            }
            var parsed: [GarminPhoneSetStatistics?] = []
            parsed.reserveCapacity(metrics.count)
            for value in metrics {
                guard let items = array(value), items.count == 7 else { return nil }
                let statistics = GarminPhoneSetStatistics(
                    activeSeconds: optionalInteger(items[0], minimum: 0, maximum: 7_200),
                    restBeforeSeconds: optionalInteger(items[1], minimum: 0, maximum: 86_400),
                    startHeartRate: optionalInteger(items[2], minimum: 0, maximum: 240),
                    peakHeartRate: optionalInteger(items[3], minimum: 0, maximum: 240),
                    endHeartRate: optionalInteger(items[4], minimum: 0, maximum: 240),
                    recoveryHeartRateDrop: optionalInteger(items[5], minimum: 0, maximum: 240),
                    detectionConfidence: optionalInteger(items[6], minimum: 0, maximum: 100)
                )
                guard optionalNumberWasValid(items[0], parsed: statistics.activeSeconds),
                      optionalNumberWasValid(items[1], parsed: statistics.restBeforeSeconds),
                      optionalNumberWasValid(items[2], parsed: statistics.startHeartRate),
                      optionalNumberWasValid(items[3], parsed: statistics.peakHeartRate),
                      optionalNumberWasValid(items[4], parsed: statistics.endHeartRate),
                      optionalNumberWasValid(items[5], parsed: statistics.recoveryHeartRateDrop),
                      optionalNumberWasValid(items[6], parsed: statistics.detectionConfidence),
                      statistics.startHeartRate == nil ||
                        statistics.peakHeartRate == nil ||
                        statistics.startHeartRate! <= statistics.peakHeartRate!,
                      statistics.endHeartRate == nil ||
                        statistics.peakHeartRate == nil ||
                        statistics.endHeartRate! <= statistics.peakHeartRate! else {
                    return nil
                }
                parsed.append(statistics == GarminPhoneSetStatistics(
                    activeSeconds: nil,
                    restBeforeSeconds: nil,
                    startHeartRate: nil,
                    peakHeartRate: nil,
                    endHeartRate: nil,
                    recoveryHeartRateDrop: nil,
                    detectionConfidence: nil
                ) ? nil : statistics)
            }
            setStatistics = parsed
        }

        let setIntervals: [GarminPhoneSetInterval?]
        if message["setIntervals"] == nil || message["setIntervals"] is NSNull {
            setIntervals = Array(repeating: nil, count: sets.count)
        } else {
            guard let intervals = array(message["setIntervals"]),
                  intervals.count == sets.count else {
                return nil
            }
            var parsed: [GarminPhoneSetInterval?] = []
            parsed.reserveCapacity(intervals.count)
            for value in intervals {
                guard let items = array(value), items.count == 10,
                      let startSeconds: Int64 = integer(
                          items[0],
                          minimum: 0,
                          maximum: maximumDurationSeconds
                      ),
                      let endSeconds: Int64 = integer(
                          items[1],
                          minimum: startSeconds,
                          maximum: maximumDurationSeconds
                      ),
                      let gymCalories = finiteDouble(
                          items[2],
                          minimum: 0,
                          maximum: 100_000
                      ) else {
                    return nil
                }
                let garminCalories: Int? = optionalInteger(
                    items[3],
                    minimum: 0,
                    maximum: 100_000
                )
                guard optionalNumberWasValid(items[3], parsed: garminCalories) else {
                    return nil
                }
                var zones: [Int64] = []
                zones.reserveCapacity(6)
                for zoneValue in items[4 ... 9] {
                    guard let seconds: Int64 = integer(
                        zoneValue,
                        minimum: 0,
                        maximum: 7_200
                    ) else {
                        return nil
                    }
                    zones.append(seconds)
                }
                guard endSeconds - startSeconds <= 7_200,
                      zones.reduce(0, +) <= endSeconds - startSeconds else {
                    return nil
                }
                parsed.append(
                    GarminPhoneSetInterval(
                        startSeconds: startSeconds,
                        endSeconds: endSeconds,
                        gymCalories: gymCalories,
                        garminCalories: garminCalories,
                        heartRateZoneSeconds: zones
                    )
                )
            }
            setIntervals = parsed
        }

        let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
        let startedAtSeconds = optionalInteger(
            message["startedAtSeconds"],
            minimum: minimumStartedAtSeconds,
            maximum: nowSeconds + maximumFutureSkewSeconds
        ) ?? nowSeconds
        guard optionalNumberWasValid(
            message["startedAtSeconds"],
            parsed: optionalInteger(
                message["startedAtSeconds"],
                minimum: minimumStartedAtSeconds,
                maximum: nowSeconds + maximumFutureSkewSeconds
            )
        ) else {
            return nil
        }
        if mode == .free,
           (message["startedAtSeconds"] == nil || message["startedAtSeconds"] is NSNull) {
            return nil
        }
        let averageHeartRate = optionalInteger(
            message["avgHeartRate"],
            minimum: 0,
            maximum: 300
        )
        let maximumHeartRate = optionalInteger(
            message["maxHeartRate"],
            minimum: 0,
            maximum: 300
        )
        let lastHeartRate = optionalInteger(
            message["lastHeartRate"],
            minimum: 0,
            maximum: 300
        )
        guard optionalNumberWasValid(message["avgHeartRate"], parsed: averageHeartRate),
              optionalNumberWasValid(message["maxHeartRate"], parsed: maximumHeartRate),
              optionalNumberWasValid(message["lastHeartRate"], parsed: lastHeartRate),
              averageHeartRate == nil ||
                maximumHeartRate == nil ||
                averageHeartRate! <= maximumHeartRate! else {
            return nil
        }

        let duration = optionalInteger(
            message["durationSeconds"],
            minimum: 0,
            maximum: maximumDurationSeconds
        )
        let gymCalories = optionalFiniteDouble(
            message["gymCalories"],
            minimum: 0,
            maximum: 100_000
        )
        let garminCalories = optionalInteger(
            message["garminCalories"],
            minimum: 0,
            maximum: 100_000
        )
        let heartRateZone = optionalInteger(
            message["heartRateZone"],
            minimum: 0,
            maximum: 5
        )
        guard optionalNumberWasValid(message["durationSeconds"], parsed: duration),
              optionalNumberWasValid(message["gymCalories"], parsed: gymCalories),
              optionalNumberWasValid(message["garminCalories"], parsed: garminCalories),
              optionalNumberWasValid(message["heartRateZone"], parsed: heartRateZone) else {
            return nil
        }
        if mode == .free {
            guard let duration, duration >= 1, gymCalories != nil else { return nil }
        }

        if message["setIntervals"] != nil, !(message["setIntervals"] is NSNull) {
            let structuredIntervals = setIntervals.compactMap { $0 }
            guard structuredIntervals.count == sets.count else { return nil }

            for index in structuredIntervals.indices.dropFirst() {
                guard structuredIntervals[index].startSeconds >=
                    structuredIntervals[structuredIntervals.index(before: index)].endSeconds else {
                    return nil
                }
            }
            guard let duration,
                  structuredIntervals.allSatisfy({ $0.endSeconds <= duration }) else {
                return nil
            }
            guard let gymCalories else { return nil }
            let intervalGymCalories = structuredIntervals.reduce(0.0) { $0 + $1.gymCalories }
            guard intervalGymCalories <= gymCalories + setIntervalCalorieRoundingTolerance else {
                return nil
            }
            let intervalGarminCalories = structuredIntervals.compactMap(\.garminCalories)
            if !intervalGarminCalories.isEmpty {
                guard let garminCalories,
                      intervalGarminCalories.reduce(0, +) <= garminCalories else {
                    return nil
                }
            }
        }

        return GarminPhoneWorkoutCommand(
            requestID: requestID,
            startedAtSeconds: startedAtSeconds,
            mode: mode,
            sets: sets,
            plannedSetCount: plannedSetCount,
            plannedTargetSetCount: plannedTargetSetCount,
            completedPlannedSetCount: completedPlannedSetCount,
            durationSeconds: duration,
            gymCalories: gymCalories,
            garminCalories: garminCalories,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            endingHeartRateZone: heartRateZone,
            setStatistics: setStatistics,
            setIntervals: setIntervals
        )
    }

    static func messageType(_ rawMessage: Any) -> String? {
        guard let message = dictionary(rawMessage) else { return nil }
        return string(message["type"], maximumBytes: 20)
    }

    private static func dictionary(_ value: Any) -> [AnyHashable: Any]? {
        if let value = value as? [AnyHashable: Any] { return value }
        guard let value = value as? NSDictionary else { return nil }
        var result: [AnyHashable: Any] = [:]
        guard value.count <= maximumMessageEntries else { return nil }
        for (key, item) in value {
            guard let key = key as? AnyHashable else { return nil }
            result[key] = item
        }
        return result
    }

    private static func array(_ value: Any?) -> [Any]? {
        if let value = value as? [Any] { return value }
        return (value as? NSArray)?.map { $0 }
    }

    private static func string(_ value: Any?, maximumBytes: Int) -> String? {
        guard let value = value as? String,
              !value.isEmpty,
              value.utf8.prefix(maximumBytes + 1).count <= maximumBytes else {
            return nil
        }
        return value
    }

    private static func finiteDouble(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let result = number.doubleValue
        guard result.isFinite, (minimum ... maximum).contains(result) else { return nil }
        return result
    }

    private static func optionalFiniteDouble(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard value != nil, !(value is NSNull) else { return nil }
        return finiteDouble(value, minimum: minimum, maximum: maximum)
    }

    private static func integer<T: FixedWidthInteger>(
        _ value: Any?,
        minimum: T,
        maximum: T
    ) -> T? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let raw = number.doubleValue
        guard raw.isFinite,
              raw.rounded(.towardZero) == raw,
              raw >= Double(minimum),
              raw <= Double(maximum) else {
            return nil
        }
        return T(raw)
    }

    private static func optionalInteger<T: FixedWidthInteger>(
        _ value: Any?,
        minimum: T,
        maximum: T
    ) -> T? {
        guard value != nil, !(value is NSNull) else { return nil }
        return integer(value, minimum: minimum, maximum: maximum)
    }

    private static func optionalNumberWasValid<T>(_ raw: Any?, parsed: T?) -> Bool {
        raw == nil || raw is NSNull || parsed != nil
    }
}

struct GarminWorkoutNoteInterval: Equatable, Identifiable {
    let setIndex: Int
    let startSeconds: Int64
    let endSeconds: Int64
    let gymCalories: Double
    let garminCalories: Int?
    let heartRateZoneSeconds: [Int64]

    var id: Int { setIndex }
}

struct GarminWorkoutNoteSetMetrics: Equatable, Identifiable {
    let setIndex: Int
    let activeSeconds: Int64?
    let restBeforeSeconds: Int64?
    let startHeartRate: Int?
    let peakHeartRate: Int?
    let endHeartRate: Int?
    let recoveryHeartRateDrop: Int?
    let detectionConfidence: Int?

    var id: Int { setIndex }

    var hasHeartRate: Bool {
        startHeartRate != nil || peakHeartRate != nil || endHeartRate != nil
    }
}

struct GarminWorkoutNoteSummary: Equatable {
    let durationSeconds: Int64?
    let gymCalories: Int?
    let garminCalories: Int?
    let averageHeartRate: Int?
    let maximumHeartRate: Int?
    let endingHeartRateZone: Int?
    let completedSetCount: Int?
    let plannedSetCount: Int?
    let setMetrics: [GarminWorkoutNoteSetMetrics]
    let intervals: [GarminWorkoutNoteInterval]
    let omittedMetricRows: Int?

    var hasWorkoutMetrics: Bool {
        durationSeconds != nil || gymCalories != nil || garminCalories != nil ||
            averageHeartRate != nil || maximumHeartRate != nil || endingHeartRateZone != nil
    }

    func metrics(for setIndex: Int) -> GarminWorkoutNoteSetMetrics? {
        setMetrics.first { $0.setIndex == setIndex }
    }

    func interval(for setIndex: Int) -> GarminWorkoutNoteInterval? {
        intervals.first { $0.setIndex == setIndex }
    }

    var visualSetIndexes: [Int] {
        Array(Set(setMetrics.map(\.setIndex) + intervals.map(\.setIndex))).sorted()
    }
}

struct GarminWorkoutTimelineSlice: Equatable, Identifiable {
    let setIndex: Int
    let startSeconds: Int64
    let endSeconds: Int64
    let detectionConfidence: Int?

    var id: Int { setIndex }
}

/// A bounded, display-only interpretation of the metrics already persisted in a
/// Garmin workout note. It deliberately avoids inferring physiology: every value
/// is either an aggregate of recorded set rows or absent.
struct GarminWorkoutSessionInsights: Equatable {
    static let maximumSets = 60
    static let maximumSessionSeconds: Int64 = 7 * 24 * 60 * 60
    static let maximumSetSeconds: Int64 = 7_200
    static let maximumCalories = 100_000.0

    let timelineDurationSeconds: Int64?
    let timelineSlices: [GarminWorkoutTimelineSlice]
    let recordedActiveSeconds: Int64?
    let recordedRestSeconds: Int64?
    let workDensityPercent: Int?
    let averageDetectionConfidence: Int?
    let averageRecoveryHeartRateDrop: Int?
    let aggregateHeartRateZoneSeconds: [Int64]?
    let dominantHeartRateZone: Int?
    let peakHeartRate: Int?
    let peakHeartRateSetIndex: Int?
    let longestRestSeconds: Int64?
    let longestRestSetIndex: Int?
    let lowConfidenceSetIndexes: [Int]
    let isPartial: Bool

    var hasContent: Bool {
        !timelineSlices.isEmpty || recordedActiveSeconds != nil ||
            recordedRestSeconds != nil || averageDetectionConfidence != nil ||
            averageRecoveryHeartRateDrop != nil || aggregateHeartRateZoneSeconds != nil ||
            peakHeartRate != nil || longestRestSeconds != nil
    }

    static func make(from summary: GarminWorkoutNoteSummary) -> Self? {
        guard summary.setMetrics.count <= maximumSets,
              summary.intervals.count <= maximumSets,
              validOptional(summary.durationSeconds, range: 0 ... maximumSessionSeconds),
              validSetIndexes(summary.setMetrics.map(\.setIndex)),
              validSetIndexes(summary.intervals.map(\.setIndex)) else {
            return nil
        }

        let metricsByIndex = Dictionary(
            uniqueKeysWithValues: summary.setMetrics.map { ($0.setIndex, $0) }
        )
        guard metricsByIndex.count == summary.setMetrics.count else { return nil }

        for metric in summary.setMetrics {
            guard validOptional(metric.activeSeconds, range: 0 ... maximumSetSeconds),
                  validOptional(metric.restBeforeSeconds, range: 0 ... 86_400),
                  validOptional(metric.startHeartRate, range: 0 ... 240),
                  validOptional(metric.peakHeartRate, range: 0 ... 240),
                  validOptional(metric.endHeartRate, range: 0 ... 240),
                  validOptional(metric.recoveryHeartRateDrop, range: 0 ... 240),
                  validOptional(metric.detectionConfidence, range: 0 ... 100),
                  metric.startHeartRate == nil || metric.peakHeartRate == nil ||
                    metric.startHeartRate! <= metric.peakHeartRate!,
                  metric.endHeartRate == nil || metric.peakHeartRate == nil ||
                    metric.endHeartRate! <= metric.peakHeartRate! else {
                return nil
            }
        }

        var previousEnd: Int64 = 0
        var intervalIndexes = Set<Int>()
        var aggregateZones = Array(repeating: Int64(0), count: 6)
        var hasTimedZone = false
        var slices: [GarminWorkoutTimelineSlice] = []
        slices.reserveCapacity(summary.intervals.count)
        for interval in summary.intervals {
            let duration = interval.endSeconds - interval.startSeconds
            guard intervalIndexes.insert(interval.setIndex).inserted,
                  interval.startSeconds >= 0,
                  interval.startSeconds >= previousEnd,
                  interval.endSeconds >= interval.startSeconds,
                  interval.endSeconds <= maximumSessionSeconds,
                  duration <= maximumSetSeconds,
                  interval.gymCalories.isFinite,
                  (0 ... maximumCalories).contains(interval.gymCalories),
                  interval.garminCalories.map({ (0 ... Int(maximumCalories)).contains($0) }) ?? true,
                  interval.heartRateZoneSeconds.count == 6,
                  interval.heartRateZoneSeconds.allSatisfy({ (0 ... maximumSetSeconds).contains($0) }),
                  safeSum(interval.heartRateZoneSeconds).map({ $0 <= duration }) == true else {
                return nil
            }
            previousEnd = interval.endSeconds
            for zoneIndex in aggregateZones.indices {
                guard aggregateZones[zoneIndex] <= Int64.max - interval.heartRateZoneSeconds[zoneIndex] else {
                    return nil
                }
                aggregateZones[zoneIndex] += interval.heartRateZoneSeconds[zoneIndex]
                hasTimedZone = hasTimedZone || interval.heartRateZoneSeconds[zoneIndex] > 0
            }
            if duration > 0 {
                slices.append(
                    GarminWorkoutTimelineSlice(
                        setIndex: interval.setIndex,
                        startSeconds: interval.startSeconds,
                        endSeconds: interval.endSeconds,
                        detectionConfidence: metricsByIndex[interval.setIndex]?.detectionConfidence
                    )
                )
            }
        }
        if let sessionDuration = summary.durationSeconds,
           summary.intervals.contains(where: { $0.endSeconds > sessionDuration }) {
            return nil
        }

        let visualIndexes = summary.visualSetIndexes
        let activeValues = visualIndexes.compactMap { setIndex -> Int64? in
            metricsByIndex[setIndex]?.activeSeconds ??
                summary.intervals.first(where: { $0.setIndex == setIndex }).map {
                    $0.endSeconds - $0.startSeconds
                }
        }
        let restValues = summary.setMetrics.compactMap(\.restBeforeSeconds)
        guard let activeTotal = safeSum(activeValues),
              let restTotal = safeSum(restValues) else {
            return nil
        }
        let recordedActive = activeValues.isEmpty ? nil : activeTotal
        let recordedRest = restValues.isEmpty ? nil : restTotal
        let density: Int?
        let hasContiguousSetIndexes = !visualIndexes.isEmpty &&
            visualIndexes == Array(1 ... visualIndexes.count)
        let hasEveryActiveDuration = activeValues.count == visualIndexes.count
        let hasEveryBetweenSetRest = visualIndexes.dropFirst().allSatisfy { setIndex in
            metricsByIndex[setIndex]?.restBeforeSeconds != nil
        }
        let canCalculateCompleteDensity = summary.omittedMetricRows == nil &&
            hasContiguousSetIndexes && hasEveryActiveDuration && hasEveryBetweenSetRest
        if canCalculateCompleteDensity, let recordedActive,
           recordedActive <= Int64.max - restTotal,
           recordedActive + restTotal > 0 {
            density = Int(
                (Double(recordedActive) / Double(recordedActive + restTotal) * 100).rounded()
            )
        } else {
            density = nil
        }

        let confidenceValues = summary.setMetrics.compactMap(\.detectionConfidence)
        let recoveryValues = summary.setMetrics.compactMap(\.recoveryHeartRateDrop)
        let averageConfidence = roundedAverage(confidenceValues)
        let averageRecovery = roundedAverage(recoveryValues)
        let lowConfidenceSets = summary.setMetrics.compactMap { metric in
            metric.detectionConfidence.map { $0 < 40 ? metric.setIndex : nil } ?? nil
        }

        let peak = summary.setMetrics.compactMap { metric -> (Int, Int)? in
            guard let value = metric.peakHeartRate, value > 0 else { return nil }
            return (metric.setIndex, value)
        }.max { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 > rhs.0 : lhs.1 < rhs.1
        }
        let longestRest = summary.setMetrics.compactMap { metric -> (Int, Int64)? in
            guard let value = metric.restBeforeSeconds, value > 0 else { return nil }
            return (metric.setIndex, value)
        }.max { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0 > rhs.0 : lhs.1 < rhs.1
        }

        let dominantZone: Int?
        if hasTimedZone {
            dominantZone = aggregateZones.indices.max { lhs, rhs in
                aggregateZones[lhs] == aggregateZones[rhs]
                    ? lhs > rhs
                    : aggregateZones[lhs] < aggregateZones[rhs]
            }
        } else {
            dominantZone = nil
        }
        let lastIntervalEnd = summary.intervals.last?.endSeconds ?? 0
        let timelineDuration = max(summary.durationSeconds ?? 0, lastIntervalEnd)

        let result = Self(
            timelineDurationSeconds: timelineDuration > 0 ? timelineDuration : nil,
            timelineSlices: slices,
            recordedActiveSeconds: recordedActive,
            recordedRestSeconds: recordedRest,
            workDensityPercent: density,
            averageDetectionConfidence: averageConfidence,
            averageRecoveryHeartRateDrop: averageRecovery,
            aggregateHeartRateZoneSeconds: hasTimedZone ? aggregateZones : nil,
            dominantHeartRateZone: dominantZone,
            peakHeartRate: peak?.1,
            peakHeartRateSetIndex: peak?.0,
            longestRestSeconds: longestRest?.1,
            longestRestSetIndex: longestRest?.0,
            lowConfidenceSetIndexes: lowConfidenceSets,
            isPartial: summary.omittedMetricRows != nil
        )
        return result.hasContent ? result : nil
    }

    private static func validSetIndexes(_ values: [Int]) -> Bool {
        values.allSatisfy { (1 ... maximumSets).contains($0) } && Set(values).count == values.count
    }

    private static func validOptional<T: Comparable>(
        _ value: T?,
        range: ClosedRange<T>
    ) -> Bool {
        value.map(range.contains) ?? true
    }

    private static func safeSum(_ values: [Int64]) -> Int64? {
        var total: Int64 = 0
        for value in values {
            guard value >= 0, total <= Int64.max - value else { return nil }
            total += value
        }
        return total
    }

    private static func roundedAverage(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}

enum GarminWorkoutNoteParser {
    private static let maximumCharacters = 4_000
    private static let maximumBytes = 16_000
    private static let maximumSets = 60
    private static let maximumSessionSeconds: Int64 = 7 * 24 * 60 * 60
    private static let maximumSetSeconds: Int64 = 7_200
    private static let maximumCalories = 100_000.0

    static func parse(_ note: String?) -> GarminWorkoutNoteSummary? {
        guard let note,
              note.count <= maximumCharacters,
              note.utf8.count <= maximumBytes else {
            return nil
        }
        let segments = note.components(separatedBy: " · ")
        guard let prefix = segments.first,
              prefix == "Garmin" || prefix == "Garmin Fenix 8" else {
            return nil
        }

        var completedSetCount: Int?
        var plannedSetCount: Int?
        var omittedMetricRows: Int?
        var gymCalories: Int?
        var garminCalories: Int?
        var averageHeartRate: Int?
        var maximumHeartRate: Int?
        var endingHeartRateZone: Int?
        var setMetrics: [GarminWorkoutNoteSetMetrics] = []
        var intervals: [GarminWorkoutNoteInterval] = []
        var seenSetIndexes = Set<Int>()
        var durationSeconds: Int64?

        for segment in segments.dropFirst() {
            let tokens = segment.split(separator: " ").map(String.init)
            guard let first = tokens.first else { continue }
            if ["Duration", "Тривалість", "Длительность"].contains(first) {
                guard durationSeconds == nil,
                      tokens.count == 2,
                      let parsedDuration = parseDuration(tokens[1]) else {
                    return nil
                }
                durationSeconds = parsedDuration
                continue
            }
            if first == "Gym", tokens.count == 3,
               ["kcal", "ккал"].contains(tokens[1]) {
                guard gymCalories == nil,
                      let value = boundedInteger(
                        tokens[2], minimum: 1, maximum: Int(maximumCalories)
                      ) else {
                    return nil
                }
                gymCalories = value
                continue
            }
            if first == "Garmin", tokens.count == 3,
               ["kcal", "ккал"].contains(tokens[1]) {
                guard garminCalories == nil,
                      let value = boundedInteger(
                        tokens[2], minimum: 1, maximum: Int(maximumCalories)
                      ) else {
                    return nil
                }
                garminCalories = value
                continue
            }
            if ["Avg", "Сер", "Средний"].contains(first), tokens.count == 3,
               ["HR", "пульс"].contains(tokens[1]) {
                guard averageHeartRate == nil,
                      let value = boundedInteger(tokens[2], minimum: 1, maximum: 240) else {
                    return nil
                }
                averageHeartRate = value
                continue
            }
            if ["Max", "Макс", "Макс."].contains(first), tokens.count == 3,
               ["HR", "пульс"].contains(tokens[1]) {
                guard maximumHeartRate == nil,
                      let value = boundedInteger(tokens[2], minimum: 1, maximum: 240) else {
                    return nil
                }
                maximumHeartRate = value
                continue
            }
            if ["Ending", "Кінцева", "Конечная"].contains(first),
               let zoneToken = tokens.last,
               zoneToken.first == "Z" {
                guard endingHeartRateZone == nil,
                      let value = boundedInteger(
                        String(zoneToken.dropFirst()), minimum: 1, maximum: 5
                      ) else {
                    return nil
                }
                endingHeartRateZone = value
                continue
            }
            if ["Completed", "Partial", "Виконано", "Частково", "Выполнено", "Частично"]
                .contains(first), tokens.count >= 2 {
                let counts = tokens[1].split(separator: "/", omittingEmptySubsequences: false)
                guard completedSetCount == nil,
                      plannedSetCount == nil,
                      counts.count == 2,
                      let completed = boundedInteger(String(counts[0]), minimum: 0, maximum: maximumSets),
                      let planned = boundedInteger(String(counts[1]), minimum: 1, maximum: maximumSets),
                      planned > completed else {
                    return nil
                }
                completedSetCount = completed
                plannedSetCount = planned
                continue
            }
            if first.hasPrefix("S+"), tokens.count == 1 {
                guard omittedMetricRows == nil,
                      let value = boundedInteger(
                    String(first.dropFirst(2)),
                    minimum: 1,
                    maximum: maximumSets
                ) else {
                    return nil
                }
                omittedMetricRows = value
                continue
            }
            guard first.first == "S",
                  let setIndex = boundedInteger(
                      String(first.dropFirst()),
                      minimum: 1,
                      maximum: maximumSets
                  ) else {
                continue
            }
            let intervalToken = tokens.first(where: { $0.first == "I" })
            let calorieToken = tokens.first(where: { $0.first == "K" })
            let zoneToken = tokens.first(where: { $0.first == "Z" })
            let metricResult = parseSetMetrics(setIndex: setIndex, tokens: tokens)
            let hasIntervalData = intervalToken != nil || calorieToken != nil || zoneToken != nil
            let hasMetricData: Bool
            switch metricResult {
            case .none:
                hasMetricData = false
            case let .valid(metrics):
                hasMetricData = true
                setMetrics.append(metrics)
            case .invalid:
                return nil
            }
            guard hasIntervalData || hasMetricData else { continue }
            guard seenSetIndexes.insert(setIndex).inserted else { return nil }
            if hasIntervalData {
                guard let intervalToken, let calorieToken, let zoneToken,
                      let interval = parseInterval(
                        setIndex: setIndex,
                        intervalToken: intervalToken,
                        calorieToken: calorieToken,
                        zoneToken: zoneToken
                      ) else {
                    return nil
                }
                intervals.append(interval)
            }
        }
        let parsedSetIndexes = Set(intervals.map(\.setIndex) + setMetrics.map(\.setIndex))
        guard parsedSetIndexes.count + (omittedMetricRows ?? 0) <= maximumSets else {
            return nil
        }
        for index in intervals.indices.dropFirst() {
            let previous = intervals[intervals.index(before: index)]
            let current = intervals[index]
            guard current.setIndex > previous.setIndex,
                  current.startSeconds >= previous.endSeconds else {
                return nil
            }
        }
        for index in setMetrics.indices.dropFirst() {
            let previous = setMetrics[setMetrics.index(before: index)]
            let current = setMetrics[index]
            guard current.setIndex > previous.setIndex else { return nil }
        }
        if let durationSeconds,
           intervals.contains(where: { $0.endSeconds > durationSeconds }) {
            return nil
        }
        if let averageHeartRate, let maximumHeartRate,
           averageHeartRate > maximumHeartRate {
            return nil
        }
        return GarminWorkoutNoteSummary(
            durationSeconds: durationSeconds,
            gymCalories: gymCalories,
            garminCalories: garminCalories,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            endingHeartRateZone: endingHeartRateZone,
            completedSetCount: completedSetCount,
            plannedSetCount: plannedSetCount,
            setMetrics: setMetrics.sorted { $0.setIndex < $1.setIndex },
            intervals: intervals.sorted { $0.setIndex < $1.setIndex },
            omittedMetricRows: omittedMetricRows
        )
    }

    private enum SetMetricsParseResult {
        case none
        case valid(GarminWorkoutNoteSetMetrics)
        case invalid
    }

    private static func parseSetMetrics(
        setIndex: Int,
        tokens: [String]
    ) -> SetMetricsParseResult {
        var activeSeconds: Int64?
        var restBeforeSeconds: Int64?
        var startHeartRate: Int?
        var peakHeartRate: Int?
        var endHeartRate: Int?
        var recoveryHeartRateDrop: Int?
        var detectionConfidence: Int?
        var recognized = false

        for token in tokens.dropFirst() {
            if token.first == "I" || token.first == "K" || token.first == "Z" {
                continue
            }
            if token.hasPrefix("R") {
                recognized = true
                guard restBeforeSeconds == nil,
                      token.hasSuffix("s"),
                      let value = boundedInteger(
                        String(token.dropFirst().dropLast()),
                        minimum: Int64(0),
                        maximum: Int64(86_400)
                      ) else {
                    return .invalid
                }
                restBeforeSeconds = value
                continue
            }
            if token.hasPrefix("HR") {
                recognized = true
                guard startHeartRate == nil, peakHeartRate == nil, endHeartRate == nil else {
                    return .invalid
                }
                let values = token.dropFirst(2)
                    .split(separator: "/", omittingEmptySubsequences: false)
                guard values.count == 3 else { return .invalid }
                func heartRate(_ value: Substring) -> Int? {
                    value == "-" ? nil : boundedInteger(
                        String(value), minimum: 0, maximum: 240
                    )
                }
                let start = heartRate(values[0])
                let peak = heartRate(values[1])
                let end = heartRate(values[2])
                guard values[0] == "-" || start != nil,
                      values[1] == "-" || peak != nil,
                      values[2] == "-" || end != nil,
                      start != nil || peak != nil || end != nil,
                      peak == nil || start == nil || start! <= peak!,
                      peak == nil || end == nil || end! <= peak! else {
                    return .invalid
                }
                startHeartRate = start
                peakHeartRate = peak
                endHeartRate = end
                continue
            }
            if token.hasPrefix("↓") {
                recognized = true
                guard recoveryHeartRateDrop == nil,
                      let value = boundedInteger(
                        String(token.dropFirst()), minimum: 0, maximum: 240
                      ) else {
                    return .invalid
                }
                recoveryHeartRateDrop = value
                continue
            }
            if token.hasPrefix("C") {
                recognized = true
                guard detectionConfidence == nil,
                      token.hasSuffix("%"),
                      let value = boundedInteger(
                        String(token.dropFirst().dropLast()), minimum: 0, maximum: 100
                      ) else {
                    return .invalid
                }
                detectionConfidence = value
                continue
            }
            if token.hasSuffix("s") {
                recognized = true
                guard activeSeconds == nil,
                      let value = boundedInteger(
                        String(token.dropLast()),
                        minimum: Int64(0),
                        maximum: maximumSetSeconds
                      ) else {
                    return .invalid
                }
                activeSeconds = value
            }
        }
        guard recognized else { return .none }
        return .valid(
            GarminWorkoutNoteSetMetrics(
                setIndex: setIndex,
                activeSeconds: activeSeconds,
                restBeforeSeconds: restBeforeSeconds,
                startHeartRate: startHeartRate,
                peakHeartRate: peakHeartRate,
                endHeartRate: endHeartRate,
                recoveryHeartRateDrop: recoveryHeartRateDrop,
                detectionConfidence: detectionConfidence
            )
        )
    }

    private static func parseInterval(
        setIndex: Int,
        intervalToken: String,
        calorieToken: String,
        zoneToken: String
    ) -> GarminWorkoutNoteInterval? {
        guard intervalToken.hasPrefix("I"), intervalToken.hasSuffix("s"),
              calorieToken.hasPrefix("K"),
              zoneToken.hasPrefix("Z"), zoneToken.hasSuffix("s") else {
            return nil
        }
        let range = intervalToken.dropFirst().dropLast()
            .split(separator: "-", omittingEmptySubsequences: false)
        let calories = calorieToken.dropFirst()
            .split(separator: "/", omittingEmptySubsequences: false)
        let zones = zoneToken.dropFirst().dropLast()
            .split(separator: "/", omittingEmptySubsequences: false)
        guard range.count == 2,
              calories.count == 2,
              zones.count == 6,
              let startSeconds = boundedInteger(
                  String(range[0]),
                  minimum: Int64(0),
                  maximum: maximumSessionSeconds
              ),
              let endSeconds = boundedInteger(
                  String(range[1]),
                  minimum: startSeconds,
                  maximum: maximumSessionSeconds
              ),
              endSeconds - startSeconds <= maximumSetSeconds,
              decimalStringIsBounded(String(calories[0])),
              let gymCalories = Double(String(calories[0])),
              gymCalories.isFinite,
              (0 ... maximumCalories).contains(gymCalories) else {
            return nil
        }
        let garminCalories: Int?
        if calories[1] == "-" {
            garminCalories = nil
        } else {
            guard let value = boundedInteger(
                String(calories[1]),
                minimum: 0,
                maximum: Int(maximumCalories)
            ) else {
                return nil
            }
            garminCalories = value
        }
        var zoneSeconds: [Int64] = []
        zoneSeconds.reserveCapacity(6)
        for value in zones {
            guard let seconds = boundedInteger(
                String(value),
                minimum: Int64(0),
                maximum: maximumSetSeconds
            ) else {
                return nil
            }
            zoneSeconds.append(seconds)
        }
        guard zoneSeconds.reduce(0, +) <= endSeconds - startSeconds else { return nil }
        return GarminWorkoutNoteInterval(
            setIndex: setIndex,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            gymCalories: gymCalories,
            garminCalories: garminCalories,
            heartRateZoneSeconds: zoneSeconds
        )
    }

    private static func decimalStringIsBounded(_ value: String) -> Bool {
        value.range(
            of: "^[0-9]+(?:\\.[0-9]{1,2})?$",
            options: .regularExpression
        ) != nil
    }

    private static func parseDuration(_ value: String) -> Int64? {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3,
              components.allSatisfy({ component in
                  !component.isEmpty && component.allSatisfy({ character in
                      character.isNumber
                  })
              }) else {
            return nil
        }
        if components.count == 2 {
            guard let minutes = Int64(components[0]),
                  let seconds = Int64(components[1]),
                  minutes <= maximumSessionSeconds / 60,
                  seconds < 60 else {
                return nil
            }
            return minutes * 60 + seconds
        }
        guard let hours = Int64(components[0]),
              let minutes = Int64(components[1]),
              let seconds = Int64(components[2]),
              hours <= maximumSessionSeconds / 3_600,
              minutes < 60,
              seconds < 60 else {
            return nil
        }
        let duration = hours * 3_600 + minutes * 60 + seconds
        return duration <= maximumSessionSeconds ? duration : nil
    }

    private static func boundedInteger<T: FixedWidthInteger>(
        _ value: String,
        minimum: T,
        maximum: T
    ) -> T? {
        guard !value.isEmpty,
              value.allSatisfy(\.isNumber),
              let parsed = T(value),
              (minimum ... maximum).contains(parsed) else {
            return nil
        }
        return parsed
    }
}

private struct GarminPhoneReceiptLedger: Codable {
    static let currentVersion = 1
    static let maximumRecords = 256

    struct Record: Codable {
        enum State: String, Codable {
            case pending
            case committed
        }

        let requestID: String
        let digest: String
        let createdAt: TimeInterval
        var state: State
    }

    let version: Int
    var records: [Record]
}

private struct GarminDeviceSelectionTransaction: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let storageKeyHash: String
    let nonce: UUID
    let createdAt: TimeInterval
}

@MainActor
final class GarminPhoneSyncService: NSObject, ObservableObject {
    private static let returnURLScheme = "com.setforge.gymapp.ios"
    private static let restorationIdentifier = "com.setforge.gymapp.ios.connectiq"
    private static let appUUID = UUID(uuidString: "A72A5B9F-4E3D-4E5A-8B72-C1D9F6123E40")!
    private static let storeUUID = UUID(uuidString: "fe82a300-4d9f-4588-8b10-365d75280b8f")!
    private static let maximumArchivedDevicesBytes = 128 * 1_024
    private static let maximumDevices = 8
    private static let maximumInboundBatch = 8
    private static let maximumReceiptsPerHour = 60
    private static let deviceSelectionMaximumAge: TimeInterval = 5 * 60
    private static let deviceSelectionFutureSkew: TimeInterval = 60

    @Published private(set) var devices: [GarminPhoneDeviceSummary] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsError = false

    private let auth: AuthService
    private let defaults: UserDefaults
    private let connectIQ: GarminPhoneConnectIQTransport
    private let syncDeliveryTimeout: Duration
    private weak var workoutStore: WorkoutStore?
    private var sessionSubscription: AnyCancellable?
    private var activeStorageKey: String?
    private var rawDevices: [UUID: IQDevice] = [:]
    private var apps: [UUID: IQApp] = [:]
    private var syncInFlight: [UUID: UUID] = [:]
    private var syncDeliveryTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingDeviceSelection: GarminDeviceSelectionTransaction?

    init(
        auth: AuthService,
        defaults: UserDefaults = .standard,
        connectIQ: GarminPhoneConnectIQTransport? = nil,
        syncDeliveryTimeout: Duration = .seconds(15)
    ) {
        self.auth = auth
        self.defaults = defaults
        self.connectIQ = connectIQ ?? LiveGarminPhoneConnectIQTransport()
        self.syncDeliveryTimeout = syncDeliveryTimeout
        super.init()
        self.connectIQ.initialize(
            urlScheme: Self.returnURLScheme,
            restorationIdentifier: Self.restorationIdentifier
        )
        sessionSubscription = auth.$session
            .removeDuplicates(by: { $0?.storageKey == $1?.storageKey })
            .sink { [weak self] session in
                Task { @MainActor in self?.activate(session) }
            }
        activate(auth.session)
    }

    deinit {
        connectIQ.unregisterAllDeviceEvents(delegate: self)
        connectIQ.unregisterAllAppMessages(delegate: self)
    }

    func bind(workoutStore: WorkoutStore) {
        self.workoutStore = workoutStore
        synchronizeConnectedDevices()
    }

    func selectDevices() {
        guard auth.session != nil, let storageKey = activeStorageKey else {
            publishStatus("Sign in before connecting a Garmin watch.", isError: true)
            return
        }
        let transaction = GarminDeviceSelectionTransaction(
            version: GarminDeviceSelectionTransaction.currentVersion,
            storageKeyHash: Data(storageKey.utf8).garminSHA256Hex,
            nonce: UUID(),
            createdAt: Date().timeIntervalSince1970
        )
        guard persistDeviceSelection(transaction, storageKey: storageKey) else {
            publishStatus("Garmin device selection could not be prepared safely.", isError: true)
            return
        }
        pendingDeviceSelection = transaction
        connectIQ.showDeviceSelection()
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == Self.returnURLScheme else { return false }
        guard let selected = connectIQ.parseDeviceSelectionResponse(from: url)
        else {
            return false
        }
        guard selected.count <= Self.maximumDevices else {
            publishStatus("Garmin returned too many watches. Select at most eight.", isError: true)
            return true
        }
        guard consumePendingDeviceSelection() else {
            publishStatus("This Garmin device selection is no longer valid. Start it again in GymApp.", isError: true)
            return true
        }
        rawDevices = Dictionary(
            uniqueKeysWithValues: selected.map { ($0.uuid as UUID, $0) }
        )
        guard persistDevices() else {
            rawDevices.removeAll()
            registerDevices()
            publishStatus("The selected Garmin watches could not be stored safely.", isError: true)
            return true
        }
        registerDevices()
        synchronizeConnectedDevices()
        publishStatus(
            selected.isEmpty
                ? "No Garmin watches are connected to this iPhone."
                : "Garmin watches connected. Open GymApp on the watch to synchronize.",
            isError: false
        )
        return true
    }

    private func activate(_ session: AppAccountSession?) {
        if let previousStorageKey = activeStorageKey {
            clearPendingDeviceSelection(storageKey: previousStorageKey)
        }
        pendingDeviceSelection = nil
        connectIQ.unregisterAllDeviceEvents(delegate: self)
        connectIQ.unregisterAllAppMessages(delegate: self)
        apps.removeAll()
        rawDevices.removeAll()
        devices.removeAll()
        syncDeliveryTimeoutTasks.values.forEach { $0.cancel() }
        syncDeliveryTimeoutTasks.removeAll()
        syncInFlight.removeAll()
        activeStorageKey = session?.storageKey
        guard session != nil else { return }
        restoreDevices()
        registerDevices()
    }

    private func persistDeviceSelection(
        _ transaction: GarminDeviceSelectionTransaction,
        storageKey: String
    ) -> Bool {
        guard transaction.version == GarminDeviceSelectionTransaction.currentVersion,
              transaction.storageKeyHash == Data(storageKey.utf8).garminSHA256Hex,
              let data = try? JSONEncoder().encode(transaction),
              data.count <= 1024 else {
            return false
        }
        let key = deviceSelectionTransactionKey(storageKey: storageKey)
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else { return false }
        rememberStateKey(key, storageKey: storageKey)
        return true
    }

    private func consumePendingDeviceSelection(now: Date = Date()) -> Bool {
        guard let storageKey = activeStorageKey,
              let inMemory = pendingDeviceSelection else {
            return false
        }
        let key = deviceSelectionTransactionKey(storageKey: storageKey)
        guard let data = defaults.data(forKey: key), data.count <= 1024,
              let durable = try? JSONDecoder().decode(
                GarminDeviceSelectionTransaction.self,
                from: data
              ) else {
            clearPendingDeviceSelection(storageKey: storageKey)
            return false
        }
        defaults.removeObject(forKey: key)
        pendingDeviceSelection = nil
        let nowSeconds = now.timeIntervalSince1970
        return durable == inMemory
            && durable.version == GarminDeviceSelectionTransaction.currentVersion
            && durable.storageKeyHash == Data(storageKey.utf8).garminSHA256Hex
            && durable.createdAt <= nowSeconds + Self.deviceSelectionFutureSkew
            && nowSeconds - durable.createdAt <= Self.deviceSelectionMaximumAge
    }

    private func clearPendingDeviceSelection(storageKey: String) {
        defaults.removeObject(forKey: deviceSelectionTransactionKey(storageKey: storageKey))
    }

    private func deviceSelectionTransactionKey(storageKey: String) -> String {
        "garmin-phone-device-selection.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
    }

    private func registerDevices() {
        connectIQ.unregisterAllDeviceEvents(delegate: self)
        connectIQ.unregisterAllAppMessages(delegate: self)
        apps.removeAll()
        for device in rawDevices.values {
            connectIQ.registerDeviceEvents(device, delegate: self)
            guard let app = IQApp(
                uuid: Self.appUUID,
                store: Self.storeUUID,
                device: device
            ) else {
                continue
            }
            apps[device.uuid as UUID] = app
            connectIQ.registerAppMessages(app, delegate: self)
        }
        refreshDeviceSummaries()
    }

    private func refreshDeviceSummaries() {
        devices = rawDevices.values
            .map { device in
                let connected = connectIQ.deviceStatus(device) == .connected
                return GarminPhoneDeviceSummary(
                    id: (device.uuid as UUID).uuidString.lowercased(),
                    name: device.friendlyName,
                    model: device.modelName,
                    connected: connected
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func synchronizeConnectedDevices() {
        guard readyWorkoutStore() != nil else { return }
        for (deviceID, app) in apps {
            guard let device = rawDevices[deviceID],
                  connectIQ.deviceStatus(device) == .connected else {
                continue
            }
            sendSync(to: app)
        }
    }

    private func persistDevices() -> Bool {
        guard let storageKey = activeStorageKey,
              rawDevices.count <= Self.maximumDevices else {
            return false
        }
        do {
            let archive = try NSKeyedArchiver.archivedData(
                withRootObject: rawDevices,
                requiringSecureCoding: true
            )
            guard archive.count <= Self.maximumArchivedDevicesBytes else { return false }
            let key = deviceArchiveKey(storageKey: storageKey)
            defaults.set(archive, forKey: key)
            guard defaults.data(forKey: key) == archive else { return false }
            rememberStateKey(key, storageKey: storageKey)
            return true
        } catch {
            return false
        }
    }

    private func restoreDevices() {
        guard let storageKey = activeStorageKey,
              let archive = defaults.data(forKey: deviceArchiveKey(storageKey: storageKey)),
              archive.count <= Self.maximumArchivedDevicesBytes else {
            return
        }
        do {
            let classes: [AnyClass] = [
                NSDictionary.self,
                NSMutableDictionary.self,
                IQDevice.self,
                NSUUID.self,
                NSString.self
            ]
            guard let restored = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: classes,
                from: archive
            ) as? [UUID: IQDevice],
            restored.count <= Self.maximumDevices else {
                defaults.removeObject(forKey: deviceArchiveKey(storageKey: storageKey))
                return
            }
            rawDevices = restored
        } catch {
            defaults.removeObject(forKey: deviceArchiveKey(storageKey: storageKey))
        }
    }

    private func process(_ rawMessage: Any, app: IQApp) {
        let sourceDeviceID = app.device.uuid as UUID
        guard let registeredApp = apps[sourceDeviceID],
              rawDevices[sourceDeviceID] != nil,
              registeredApp.device.uuid as UUID == sourceDeviceID,
              registeredApp.uuid as UUID == Self.appUUID,
              app.uuid as UUID == Self.appUUID,
              registeredApp.storeUuid as UUID == Self.storeUUID,
              app.storeUuid as UUID == Self.storeUUID else {
            return
        }
        let messages: [Any]
        if let batch = rawMessage as? [Any],
           batch.count <= Self.maximumInboundBatch,
           batch.allSatisfy({ $0 is NSDictionary || $0 is [AnyHashable: Any] }) {
            messages = batch
        } else {
            messages = [rawMessage]
        }
        for message in messages {
            switch GarminPhoneWorkoutParser.messageType(message) {
            case "request_sync":
                receiveSyncRequest(message, from: app)
            case "sync_ack":
                receiveSyncAcknowledgement(message, from: app)
            case "create_workout":
                receiveWorkout(message, from: app)
            default:
                continue
            }
        }
    }

    private func sendSync(to app: IQApp) {
        guard let binding = binding(for: app.device),
              let store = readyWorkoutStore() else {
            return
        }
        let deviceID = app.device.uuid as UUID
        guard syncInFlight[deviceID] == nil else { return }
        let attemptID = UUID()
        syncInFlight[deviceID] = attemptID
        let currentLanguage = normalizedLanguage(gymCurrentLanguageCode(defaults: defaults))
        let currentExercises = GarminPhoneSyncProtocol.boundedExerciseCatalog(
            store.exercises.map(\.name)
        )

        let transition: GarminPhonePendingAuthTransition?
        if isBindingConfirmed(binding) {
            removePendingAuthTransitionFile(binding)
            transition = nil
        } else if let existing = pendingAuthTransition(binding),
                  existing.binding == binding {
            transition = existing
        } else {
            guard let revision = nextSyncRevision(binding: binding) else {
                syncInFlight.removeValue(forKey: deviceID)
                publishStatus("The Garmin sync revision could not be stored safely.", isError: true)
                return
            }
            let previousMarker = deviceHandshakeMarker(binding)
            let handshake: GarminPhoneBindingHandshake =
                shouldStartWithPreservingProof(
                    binding,
                    deviceMarker: previousMarker
                ) ? .proof : .reset
            let pending = GarminPhonePendingAuthTransition(
                binding: binding,
                syncID: UUID().uuidString.lowercased(),
                revision: revision,
                language: currentLanguage,
                exercises: handshake == .reset ? [] : currentExercises,
                handshake: handshake
            )
            guard savePendingAuthTransition(
                pending,
                resetAuthorizationFrom: handshake == .proof ? previousMarker : nil
            ) else {
                syncInFlight.removeValue(forKey: deviceID)
                publishStatus("The Garmin account transition could not be stored safely.", isError: true)
                return
            }
            transition = pending
        }

        let syncID = transition?.syncID ?? UUID().uuidString.lowercased()
        let revision: Int64
        if let transition {
            revision = transition.revision
        } else {
            guard let next = nextSyncRevision(binding: binding) else {
                syncInFlight.removeValue(forKey: deviceID)
                publishStatus("The Garmin sync revision could not be stored safely.", isError: true)
                return
            }
            revision = next
        }
        let language = transition?.language ?? currentLanguage
        guard let payload = GarminPhoneSyncProtocol.syncPayload(
            binding: binding,
            syncID: syncID,
            revision: revision,
            language: language,
            exercises: transition?.exercises ?? currentExercises,
            resetWorkout: transition?.handshake == .reset,
            repairPairing: transition?.handshake == .repair
        ) else {
            syncInFlight.removeValue(forKey: deviceID)
            publishStatus("The Garmin sync payload is outside the supported limits.", isError: true)
            return
        }
        let deliveryTimeout = syncDeliveryTimeout
        syncDeliveryTimeoutTasks[deviceID]?.cancel()
        syncDeliveryTimeoutTasks[deviceID] = Task { [weak self] in
            do {
                try await Task.sleep(for: deliveryTimeout)
            } catch {
                return
            }
            guard let self else { return }
            self.finishSyncAttempt(
                deviceID: deviceID,
                attemptID: attemptID,
                app: app,
                binding: binding,
                transition: transition,
                delivered: false,
                timedOut: true
            )
        }
        send(payload, to: app) { [weak self] delivered in
            self?.finishSyncAttempt(
                deviceID: deviceID,
                attemptID: attemptID,
                app: app,
                binding: binding,
                transition: transition,
                delivered: delivered,
                timedOut: false
            )
        }
    }

    private func finishSyncAttempt(
        deviceID: UUID,
        attemptID: UUID,
        app: IQApp,
        binding: GarminPhoneBinding,
        transition: GarminPhonePendingAuthTransition?,
        delivered: Bool,
        timedOut: Bool
    ) {
        guard syncInFlight[deviceID] == attemptID else { return }
        syncInFlight.removeValue(forKey: deviceID)
        if timedOut {
            syncDeliveryTimeoutTasks.removeValue(forKey: deviceID)
        } else {
            syncDeliveryTimeoutTasks.removeValue(forKey: deviceID)?.cancel()
        }
        guard self.binding(for: app.device) == binding else { return }
        let transitionConfirmed = transition != nil && isBindingConfirmed(binding)
        if !delivered && !transitionConfirmed {
            publishStatus(
                timedOut
                    ? "Garmin message delivery timed out. Reconnect the watch to retry."
                    : "Garmin message delivery failed. Keep both apps open and retry.",
                isError: true
            )
        }
        if transitionConfirmed {
            sendSync(to: app)
        }
    }

    private func receiveSyncAcknowledgement(_ rawMessage: Any, from app: IQApp) {
        guard let binding = binding(for: app.device),
              let pending = pendingAuthTransition(binding),
              pending.binding == binding,
              GarminPhoneSyncProtocol.acknowledgementMatches(
                  rawMessage,
                  expected: pending,
                  sourceDeviceBinding: (app.device.uuid as UUID).uuidString.lowercased()
              ) else {
            return
        }
        guard confirmBinding(binding) else {
            publishStatus("The Garmin account binding could not be stored safely.", isError: true)
            return
        }
        removePendingAuthTransition(pending)
        publishStatus("Garmin watch synchronized securely.", isError: false)
        sendSync(to: app)
    }

    private func receiveSyncRequest(_ rawMessage: Any, from app: IQApp) {
        guard let binding = binding(for: app.device),
              let claim = GarminPhoneSyncProtocol.syncRequestClaim(
                  rawMessage,
                  sourceDeviceBinding: (app.device.uuid as UUID).uuidString.lowercased()
              ) else {
            return
        }

        if claim.account != binding.account {
            guard let claimedGeneration = claim.pairingGeneration,
                  resetAuthorization(
                      for: binding,
                      claimedPreviousBinding: GarminPhoneBinding(
                          account: claim.account,
                          device: claim.device,
                          pairingGeneration: claimedGeneration
                      )
                  ) != nil else {
                // A watch claim is untrusted. It can only select the destructive
                // path when it exactly proves the previous side of a transition
                // that the phone already staged and durably correlated.
                return
            }
            stageHandshake(.reset, binding: binding, to: app)
            return
        }
        guard claim.device == binding.device else { return }
        if claim.pairingGeneration == binding.pairingGeneration {
            if pendingAuthTransition(binding)?.handshake == .reset {
                // A target-shaped request_sync is not the acknowledgement for a
                // destructive reset. Preserve and resend the exact transaction;
                // only its fully correlated sync_ack may confirm the binding.
                cancelSyncAttempt(deviceID: app.device.uuid as UUID)
                sendSync(to: app)
                return
            }
            // A matching request is sufficient for proof (non-destructive) and
            // repair (the watch already presents the repaired generation).
            guard confirmBinding(binding) else {
                publishStatus("The Garmin account binding could not be stored safely.", isError: true)
                return
            }
            if let pending = pendingAuthTransition(binding) {
                removePendingAuthTransition(pending)
            }
            cancelSyncAttempt(deviceID: app.device.uuid as UUID)
            sendSync(to: app)
        } else if claim.pairingGeneration == nil {
            // Older same-owner watches can adopt the generation without clearing
            // an active workout. The exact applied acknowledgement confirms it.
            stageHandshake(.proof, binding: binding, to: app)
        } else {
            // The watch proves the same account/device but an older generation.
            // Its repairPairing path rotates pending workout ownership in place.
            stageHandshake(.repair, binding: binding, to: app)
        }
    }

    private func stageHandshake(
        _ handshake: GarminPhoneBindingHandshake,
        binding: GarminPhoneBinding,
        to app: IQApp
    ) {
        if let existing = pendingAuthTransition(binding),
           existing.handshake == handshake {
            sendSync(to: app)
            return
        }
        guard let store = readyWorkoutStore(),
              let revision = nextSyncRevision(binding: binding) else {
            publishStatus("The Garmin sync revision could not be stored safely.", isError: true)
            return
        }
        let exercises = handshake == .reset
            ? []
            : GarminPhoneSyncProtocol.boundedExerciseCatalog(
                store.exercises.map(\.name)
            )
        let pending = GarminPhonePendingAuthTransition(
            binding: binding,
            syncID: UUID().uuidString.lowercased(),
            revision: revision,
            language: normalizedLanguage(gymCurrentLanguageCode(defaults: defaults)),
            exercises: exercises,
            handshake: handshake
        )
        guard savePendingAuthTransition(pending) else {
            publishStatus("The Garmin account transition could not be stored safely.", isError: true)
            return
        }
        cancelSyncAttempt(deviceID: app.device.uuid as UUID)
        sendSync(to: app)
    }

    private func cancelSyncAttempt(deviceID: UUID) {
        syncDeliveryTimeoutTasks.removeValue(forKey: deviceID)?.cancel()
        syncInFlight.removeValue(forKey: deviceID)
    }

    private func receiveWorkout(_ rawMessage: Any, from app: IQApp) {
        guard let binding = binding(for: app.device),
              let store = readyWorkoutStore(),
              let command = GarminPhoneWorkoutParser.parse(
                  rawMessage,
                  expectedBinding: binding
              ) else {
            publishStatus("A malformed or unbound Garmin workout was rejected.", isError: true)
            return
        }
        let receiptKey = receiptLedgerKey(binding: binding)
        if let activeStorageKey {
            rememberStateKey(receiptKey, storageKey: activeStorageKey)
        }
        var ledger = loadReceiptLedger(key: receiptKey)
        if let existing = ledger.records.first(where: { $0.requestID == command.requestID }) {
            guard existing.digest == command.digest else {
                publishStatus("A conflicting Garmin workout replay was rejected.", isError: true)
                return
            }
            if existing.state == .pending {
                guard matchingWorkout(command, in: store) else {
                    ledger.records.removeAll { $0.requestID == command.requestID }
                    guard saveReceiptLedger(ledger, key: receiptKey) else { return }
                    receiveWorkout(rawMessage, from: app)
                    return
                }
                updateReceipt(
                    requestID: command.requestID,
                    state: .committed,
                    ledger: &ledger
                )
                guard saveReceiptLedger(ledger, key: receiptKey) else { return }
            }
            sendAcknowledgement(for: command.requestID, binding: binding, to: app)
            return
        }

        let oneHourAgo = Date().timeIntervalSince1970 - 3_600
        guard ledger.records.lazy.filter({ $0.createdAt >= oneHourAgo }).count <
                Self.maximumReceiptsPerHour else {
            publishStatus("Garmin workout import is temporarily rate limited.", isError: true)
            return
        }
        ledger.records.append(
            .init(
                requestID: command.requestID,
                digest: command.digest,
                createdAt: Date().timeIntervalSince1970,
                state: .pending
            )
        )
        trimLedger(&ledger)
        guard saveReceiptLedger(ledger, key: receiptKey) else {
            publishStatus("The Garmin import receipt could not be stored.", isError: true)
            return
        }

        do {
            let workoutDate = Date(timeIntervalSince1970: TimeInterval(command.startedAtSeconds))
            let note = workoutNote(command)
            let created: WorkoutSession?
            if command.mode == .free {
                created = try store.createActivityWorkout(
                    date: workoutDate,
                    note: note,
                    durationSeconds: Int(command.durationSeconds ?? 0)
                )
            } else {
                created = try store.createWorkout(
                    date: workoutDate,
                    note: note,
                    namedSets: command.sets,
                    durationSeconds: command.durationSeconds.map(Int.init)
                )
            }
            guard created != nil,
                  readyWorkoutStore() === store else {
                throw GarminPhoneSyncError.accountChanged
            }
            updateReceipt(
                requestID: command.requestID,
                state: .committed,
                ledger: &ledger
            )
            guard saveReceiptLedger(ledger, key: receiptKey) else {
                publishStatus(
                    "The workout was saved, but Garmin acknowledgement is waiting for receipt recovery.",
                    isError: true
                )
                return
            }
            sendAcknowledgement(for: command.requestID, binding: binding, to: app)
            publishStatus("Workout received from Garmin.", isError: false)
        } catch {
            ledger.records.removeAll { $0.requestID == command.requestID }
            _ = saveReceiptLedger(ledger, key: receiptKey)
            publishStatus("The Garmin workout could not be saved.", isError: true)
        }
    }

    private func sendAcknowledgement(
        for requestID: String,
        binding: GarminPhoneBinding,
        to app: IQApp
    ) {
        send(
            [
                "type": "ack",
                "requestId": requestID,
                "bindingVersion": GarminPhoneWorkoutParser.bindingVersion,
                "accountBinding": binding.account,
                "deviceBinding": binding.device,
                "pairingGeneration": binding.pairingGeneration
            ],
            to: app
        )
    }

    private func send(
        _ message: [String: Any],
        to app: IQApp,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        connectIQ.send(message, to: app) { [weak self] delivered in
            Task { @MainActor in
                guard let self else { return }
                if let completion {
                    completion(delivered)
                } else if !delivered {
                    self.publishStatus(
                        "Garmin message delivery failed. Keep both apps open and retry.",
                        isError: true
                    )
                }
            }
        }
    }

    private func readyWorkoutStore() -> WorkoutStore? {
        guard let session = auth.session,
              let activeStorageKey,
              activeStorageKey == session.storageKey,
              let workoutStore,
              workoutStore.accountStorageKey == session.storageKey else {
            return nil
        }
        return workoutStore
    }

    private func binding(for device: IQDevice) -> GarminPhoneBinding? {
        guard let session = auth.session,
              activeStorageKey == session.storageKey else {
            return nil
        }
        let deviceBinding = (device.uuid as UUID).uuidString.lowercased()
        guard rawDevices[device.uuid as UUID] != nil else { return nil }
        let accountBinding: String
        if let cloud = session.cloud {
            guard UUID(uuidString: cloud.userID)?.uuidString.lowercased() ==
                    cloud.userID.lowercased() else {
                return nil
            }
            accountBinding = Data(cloud.userID.lowercased().utf8).garminSHA256Hex
        } else {
            let key = localAccountBindingKey(storageKey: session.storageKey)
            if let existing = defaults.string(forKey: key),
               existing.isGarminBinding {
                accountBinding = existing
            } else {
                let generated = Data(
                    "gymapp-local-account-binding/v1\u{0}\(UUID().uuidString.lowercased())".utf8
                ).garminSHA256Hex
            defaults.set(generated, forKey: key)
            guard defaults.string(forKey: key) == generated else { return nil }
            rememberStateKey(key, storageKey: session.storageKey)
                accountBinding = generated
            }
            rememberStateKey(key, storageKey: session.storageKey)
        }
        let generationKey = pairingGenerationKey(
            accountBinding: accountBinding,
            deviceBinding: deviceBinding
        )
        let generation: String
        if let existing = defaults.string(forKey: generationKey),
           existing.isGarminBinding {
            generation = existing
        } else {
            let generated = Data(
                "gymapp-garmin-pairing-generation/v1\u{0}\(UUID().uuidString.lowercased())".utf8
            ).garminSHA256Hex
            defaults.set(generated, forKey: generationKey)
            guard defaults.string(forKey: generationKey) == generated else { return nil }
            rememberStateKey(generationKey, storageKey: session.storageKey)
            generation = generated
        }
        rememberStateKey(generationKey, storageKey: session.storageKey)
        return GarminPhoneBinding(
            account: accountBinding,
            device: deviceBinding,
            pairingGeneration: generation
        )
    }

    private func nextSyncRevision(binding: GarminPhoneBinding) -> Int64? {
        let key = deviceSyncRevisionKey(deviceBinding: binding.device)
        let current = (defaults.object(forKey: key) as? NSNumber)?.int64Value
        let nowMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        guard let next = GarminPhoneSyncProtocol.nextRevision(
            lastRevision: current,
            nowMilliseconds: nowMilliseconds
        ) else {
            return nil
        }
        defaults.set(next, forKey: key)
        guard (defaults.object(forKey: key) as? NSNumber)?.int64Value == next else {
            return nil
        }
        return next
    }

    static func formattedWorkoutNote(
        _ command: GarminPhoneWorkoutCommand,
        language rawLanguage: String
    ) -> String {
        let language = ["uk", "ru"].contains(rawLanguage) ? rawLanguage : "en"
        var details = ["Garmin"]
        if command.mode == .free {
            details.append(
                language == "uk" ? "Вільне тренування" :
                    language == "ru" ? "Свободная тренировка" :
                    "Free workout"
            )
        }
        let progress: (completed: Int, planned: Int)?
        if let plannedTargetSetCount = command.plannedTargetSetCount,
           let completedPlannedSetCount = command.completedPlannedSetCount {
            progress = (completedPlannedSetCount, plannedTargetSetCount)
        } else if let plannedSetCount = command.plannedSetCount {
            progress = (command.sets.count, plannedSetCount)
        } else {
            progress = nil
        }
        if let progress, progress.planned > progress.completed {
            details.append(
                language == "uk" ? "Виконано \(progress.completed)/\(progress.planned) підходів" :
                    language == "ru" ? "Выполнено \(progress.completed)/\(progress.planned) подходов" :
                    "Completed \(progress.completed)/\(progress.planned) sets"
            )
        }
        if let seconds = command.durationSeconds, seconds > 0 {
            let duration = String(format: "%lld:%02lld", seconds / 60, seconds % 60)
            details.append(
                language == "uk" ? "Тривалість \(duration)" :
                    language == "ru" ? "Длительность \(duration)" :
                    "Duration \(duration)"
            )
        }
        if let value = command.gymCalories, value > 0 {
            details.append(language == "uk" ? "Gym ккал \(Int(value))" : "Gym kcal \(Int(value))")
        }
        if let value = command.garminCalories, value > 0 {
            details.append(language == "uk" ? "Garmin ккал \(value)" : "Garmin kcal \(value)")
        }
        if let value = command.averageHeartRate, value > 0 {
            details.append(
                language == "uk" ? "Сер пульс \(value)" :
                    language == "ru" ? "Средний пульс \(value)" :
                    "Avg HR \(value)"
            )
        }
        if let value = command.maximumHeartRate, value > 0 {
            details.append(
                language == "uk" ? "Макс пульс \(value)" :
                    language == "ru" ? "Макс. пульс \(value)" :
                    "Max HR \(value)"
            )
        }
        if let value = command.endingHeartRateZone, value > 0 {
            details.append(
                language == "uk" ? "Кінцева зона пульсу Z\(value)" :
                    language == "ru" ? "Конечная зона пульса Z\(value)" :
                    "Ending HR zone Z\(value)"
            )
        }
        for index in command.sets.indices {
            var values: [String] = []
            if let statistics = command.setStatistics[index] {
                if let value = statistics.activeSeconds { values.append("\(value)s") }
                if let value = statistics.restBeforeSeconds, value > 0 {
                    values.append("R\(value)s")
                }
                let heartRates = [
                    statistics.startHeartRate,
                    statistics.peakHeartRate,
                    statistics.endHeartRate
                ]
                if heartRates.contains(where: { $0 != nil }) {
                    values.append(
                        "HR" + heartRates.map { $0.map(String.init) ?? "-" }
                            .joined(separator: "/")
                    )
                }
                if let value = statistics.recoveryHeartRateDrop { values.append("↓\(value)") }
                if let value = statistics.detectionConfidence { values.append("C\(value)%") }
            }
            if let interval = command.setIntervals[index] {
                values.append("I\(interval.startSeconds)-\(interval.endSeconds)s")
                let gymCalories = String(
                    format: "%.2f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    interval.gymCalories
                )
                    .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
                values.append("K\(gymCalories)/\(interval.garminCalories.map(String.init) ?? "-")")
                values.append(
                    "Z" + interval.heartRateZoneSeconds.map(String.init).joined(separator: "/") + "s"
                )
            }
            if !values.isEmpty {
                let detail = "S\(index + 1) \(values.joined(separator: " "))"
                let remainingAfterCurrent = command.sets.count - index - 1
                let reservedMarker = remainingAfterCurrent > 0
                    ? "S+\(remainingAfterCurrent)"
                    : nil
                let candidateDetails = details + [detail] + (reservedMarker.map { [$0] } ?? [])
                let candidate = candidateDetails.joined(separator: " · ")
                guard candidate.count <= 4_000, candidate.utf8.count <= 16_000 else {
                    let marker = "S+\(command.sets.count - index)"
                    let marked = (details + [marker]).joined(separator: " · ")
                    if marked.count <= 4_000, marked.utf8.count <= 16_000 {
                        details.append(marker)
                    }
                    break
                }
                details.append(detail)
            }
        }
        return details.joined(separator: " · ")
    }

    private func workoutNote(_ command: GarminPhoneWorkoutCommand) -> String {
        Self.formattedWorkoutNote(
            command,
            language: normalizedLanguage(gymCurrentLanguageCode(defaults: defaults))
        )
    }

    private func matchingWorkout(
        _ command: GarminPhoneWorkoutCommand,
        in store: WorkoutStore
    ) -> Bool {
        Self.matchesPersistedWorkout(command, in: store)
    }

    static func matchesPersistedWorkout(
        _ command: GarminPhoneWorkoutCommand,
        in store: WorkoutStore
    ) -> Bool {
        let expectedDate = TimeInterval(command.startedAtSeconds)
        let names = Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0.name) })
        let expectedSets = canonicalGroupedSets(command.sets)
        return store.workouts.contains { workout in
            guard abs(workout.date.timeIntervalSince1970 - expectedDate) < 1 else {
                return false
            }
            if command.mode == .free {
                return workout.exercises.isEmpty &&
                    workout.durationSeconds == command.durationSeconds.map(Int.init)
            }
            let flattened = workout.exercises.flatMap { block in
                block.sets.map {
                    NamedWorkoutSetDraft(
                        exerciseName: names[block.exerciseID] ?? "",
                        weight: $0.weight,
                        reps: $0.reps
                    )
                }
            }
            return canonicalGroupedSets(flattened) == expectedSets
        }
    }

    private struct CanonicalWorkoutSet: Equatable {
        let exerciseKey: String
        let weight: Double
        let reps: Int
    }

    private static func canonicalGroupedSets(
        _ sets: [NamedWorkoutSetDraft]
    ) -> [CanonicalWorkoutSet] {
        var orderedExerciseKeys: [String] = []
        var grouped: [String: [CanonicalWorkoutSet]] = [:]
        for set in sets {
            let exerciseKey = set.exerciseName.gymTrimmed.lowercased()
            if grouped[exerciseKey] == nil {
                orderedExerciseKeys.append(exerciseKey)
            }
            grouped[exerciseKey, default: []].append(
                CanonicalWorkoutSet(
                    exerciseKey: exerciseKey,
                    weight: set.weight,
                    reps: set.reps
                )
            )
        }
        return orderedExerciseKeys.flatMap { grouped[$0, default: []] }
    }

    private func loadReceiptLedger(key: String) -> GarminPhoneReceiptLedger {
        guard let data = defaults.data(forKey: key),
              data.count <= 256 * 1_024,
              let value = try? JSONDecoder().decode(GarminPhoneReceiptLedger.self, from: data),
              value.version == GarminPhoneReceiptLedger.currentVersion,
              value.records.count <= GarminPhoneReceiptLedger.maximumRecords,
              Set(value.records.map(\.requestID)).count == value.records.count else {
            return GarminPhoneReceiptLedger(
                version: GarminPhoneReceiptLedger.currentVersion,
                records: []
            )
        }
        return value
    }

    private func saveReceiptLedger(
        _ ledger: GarminPhoneReceiptLedger,
        key: String
    ) -> Bool {
        guard ledger.records.count <= GarminPhoneReceiptLedger.maximumRecords,
              let data = try? JSONEncoder().encode(ledger),
              data.count <= 256 * 1_024 else {
            return false
        }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    private func updateReceipt(
        requestID: String,
        state: GarminPhoneReceiptLedger.Record.State,
        ledger: inout GarminPhoneReceiptLedger
    ) {
        guard let index = ledger.records.firstIndex(where: { $0.requestID == requestID }) else {
            return
        }
        ledger.records[index].state = state
    }

    private func trimLedger(_ ledger: inout GarminPhoneReceiptLedger) {
        if ledger.records.count > GarminPhoneReceiptLedger.maximumRecords {
            ledger.records.sort { $0.createdAt < $1.createdAt }
            ledger.records.removeFirst(
                ledger.records.count - GarminPhoneReceiptLedger.maximumRecords
            )
        }
    }

    private func deviceArchiveKey(storageKey: String) -> String {
        "garmin-phone-devices.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
    }

    private static func stateIndexKey(storageKey: String) -> String {
        "garmin-phone-state-index.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
    }

    private func rememberStateKey(_ key: String, storageKey: String) {
        let indexKey = Self.stateIndexKey(storageKey: storageKey)
        var keys = Set(defaults.stringArray(forKey: indexKey) ?? [])
        guard keys.count <= 1_024 else { return }
        keys.insert(key)
        defaults.set(keys.sorted(), forKey: indexKey)
    }

    func clearLocalData(storageKey: String) {
        Self.clearStoredData(defaults: defaults, storageKey: storageKey)
        if activeStorageKey == storageKey {
            activate(nil)
        }
    }

    static func clearStoredData(defaults: UserDefaults, storageKey: String) {
        let indexKey = stateIndexKey(storageKey: storageKey)
        let indexedKeys = defaults.stringArray(forKey: indexKey) ?? []
        for key in indexedKeys.prefix(1_024) {
            guard key.hasPrefix("garmin-phone-") else { continue }
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(
            forKey: "garmin-phone-devices.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
        )
        defaults.removeObject(forKey: indexKey)
    }

    private func localAccountBindingKey(storageKey: String) -> String {
        "garmin-phone-local-account.v1.\(Data(storageKey.utf8).garminSHA256Hex)"
    }

    private func bindingStateScope(_ binding: GarminPhoneBinding) -> String {
        Data(
            "\(binding.account)\u{0}\(binding.device)\u{0}\(binding.pairingGeneration)".utf8
        ).garminSHA256Hex
    }

    private func confirmedBindingKey(_ binding: GarminPhoneBinding) -> String {
        "garmin-phone-confirmed-binding.v1.\(bindingStateScope(binding))"
    }

    private func currentDeviceBindingKey(_ binding: GarminPhoneBinding) -> String {
        "garmin-phone-current-binding.v1.\(Data(binding.device.utf8).garminSHA256Hex)"
    }

    private func deviceHandshakeMarkerKey(_ binding: GarminPhoneBinding) -> String {
        "garmin-phone-device-handshake.v1.\(Data(binding.device.utf8).garminSHA256Hex)"
    }

    private func pendingAuthTransitionKey(_ binding: GarminPhoneBinding) -> String {
        "garmin-phone-pending-transition.v1.\(bindingStateScope(binding))"
    }

    private func resetAuthorizationKey(_ binding: GarminPhoneBinding) -> String {
        "garmin-phone-reset-authorization.v1.\(bindingStateScope(binding))"
    }

    private func legacySyncRevisionKey(_ binding: GarminPhoneBinding) -> String {
        "garmin-phone-sync-revision.v1.\(bindingStateScope(binding))"
    }

    private func deviceSyncRevisionKey(deviceBinding: String) -> String {
        "garmin-phone-device-revision.v2.\(Data(deviceBinding.utf8).garminSHA256Hex)"
    }

    private func isBindingConfirmed(_ binding: GarminPhoneBinding) -> Bool {
        let key = confirmedBindingKey(binding)
        let currentKey = currentDeviceBindingKey(binding)
        let expectedScope = bindingStateScope(binding)
        return deviceHandshakeMarker(binding) == nil &&
            defaults.string(forKey: currentKey) == expectedScope &&
            defaults.bool(forKey: key)
    }

    private func shouldStartWithPreservingProof(
        _ binding: GarminPhoneBinding,
        deviceMarker: GarminPhoneDeviceHandshakeMarker?
    ) -> Bool {
        if deviceMarker != nil {
            // An unacknowledged transition may or may not have reached the watch.
            // Probe non-destructively; a bound watch request can then prove whether
            // an explicit reset or pairing repair is actually required.
            return true
        }
        guard defaults.string(forKey: currentDeviceBindingKey(binding)) == nil,
              let legacy = defaults.object(
                  forKey: legacySyncRevisionKey(binding)
              ) as? NSNumber,
              CFGetTypeID(legacy) != CFBooleanGetTypeID() else {
            return false
        }
        // Released iOS persisted this counter before transport completion, so it
        // is evidence of an attempted sync only. A reset=false proof preserves a
        // same-owner active workout and never silently treats the attempt as ACKed.
        return (1 ... GarminPhoneSyncProtocol.maximumSyncRevision)
            .contains(legacy.int64Value)
    }

    private func confirmBinding(_ binding: GarminPhoneBinding) -> Bool {
        guard let activeStorageKey else { return false }
        let currentKey = currentDeviceBindingKey(binding)
        let expectedScope = bindingStateScope(binding)
        defaults.set(expectedScope, forKey: currentKey)
        guard defaults.string(forKey: currentKey) == expectedScope else { return false }
        let key = confirmedBindingKey(binding)
        defaults.set(true, forKey: key)
        guard defaults.bool(forKey: key) else { return false }
        rememberStateKey(key, storageKey: activeStorageKey)
        return true
    }

    private func pendingAuthTransition(
        _ binding: GarminPhoneBinding
    ) -> GarminPhonePendingAuthTransition? {
        let key = pendingAuthTransitionKey(binding)
        guard let data = defaults.data(forKey: key) else { return nil }
        guard data.count <= 32 * 1_024,
              let pending = try? JSONDecoder().decode(
                  GarminPhonePendingAuthTransition.self,
                  from: data
              ),
              pending.binding == binding,
              GarminPhoneSyncProtocol.syncPayload(
                  binding: pending.binding,
                  syncID: pending.syncID,
                  revision: pending.revision,
                  language: pending.language,
                  exercises: pending.exercises,
                  resetWorkout: pending.handshake == .reset,
                  repairPairing: pending.handshake == .repair
              ) != nil,
              deviceHandshakeMarker(binding) == handshakeMarker(for: pending) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return pending
    }

    private func savePendingAuthTransition(
        _ pending: GarminPhonePendingAuthTransition,
        resetAuthorizationFrom previousMarker: GarminPhoneDeviceHandshakeMarker? = nil
    ) -> Bool {
        let targetScope = bindingStateScope(pending.binding)
        let resetAuthorization: GarminPhoneResetAuthorization?
        if let previousMarker,
           pending.handshake == .proof,
           previousMarker.bindingScope != targetScope {
            guard previousMarker.bindingScope.isGarminBinding,
                  GarminPhoneSyncProtocol.isValidMessageID(previousMarker.syncID),
                  (1 ... GarminPhoneSyncProtocol.maximumSyncRevision)
                    .contains(previousMarker.revision),
                  pending.revision > previousMarker.revision else {
                return false
            }
            resetAuthorization = GarminPhoneResetAuthorization(
                deviceBinding: pending.binding.device,
                targetBindingScope: targetScope,
                proofSyncID: pending.syncID,
                proofRevision: pending.revision,
                previousBindingScope: previousMarker.bindingScope,
                previousSyncID: previousMarker.syncID,
                previousRevision: previousMarker.revision
            )
        } else {
            resetAuthorization = nil
        }
        let authorizationData: Data?
        if let resetAuthorization {
            guard let encoded = try? JSONEncoder().encode(resetAuthorization),
                  encoded.count <= 2 * 1_024 else {
                return false
            }
            authorizationData = encoded
        } else {
            authorizationData = nil
        }
        guard let activeStorageKey,
              GarminPhoneSyncProtocol.syncPayload(
                  binding: pending.binding,
                  syncID: pending.syncID,
                  revision: pending.revision,
                  language: pending.language,
                  exercises: pending.exercises,
                  resetWorkout: pending.handshake == .reset,
                  repairPairing: pending.handshake == .repair
              ) != nil,
              let data = try? JSONEncoder().encode(pending),
              data.count <= 32 * 1_024,
              let markerData = try? JSONEncoder().encode(handshakeMarker(for: pending)),
              markerData.count <= 1_024 else {
            return false
        }
        let key = pendingAuthTransitionKey(pending.binding)
        let markerKey = deviceHandshakeMarkerKey(pending.binding)
        let authorizationKey = resetAuthorizationKey(pending.binding)
        let previousPendingData = defaults.data(forKey: key)
        let previousMarkerData = defaults.data(forKey: markerKey)
        let previousAuthorizationData = defaults.data(forKey: authorizationKey)
        let rollback = {
            self.restoreData(previousPendingData, forKey: key)
            self.restoreData(previousMarkerData, forKey: markerKey)
            self.restoreData(previousAuthorizationData, forKey: authorizationKey)
        }
        defaults.set(data, forKey: key)
        guard defaults.data(forKey: key) == data else {
            rollback()
            return false
        }
        defaults.set(markerData, forKey: markerKey)
        guard defaults.data(forKey: markerKey) == markerData else {
            rollback()
            return false
        }
        if resetAuthorization != nil {
            guard let authorizationData else {
                rollback()
                return false
            }
            defaults.set(authorizationData, forKey: authorizationKey)
            guard defaults.data(forKey: authorizationKey) == authorizationData else {
                rollback()
                return false
            }
        } else {
            defaults.removeObject(forKey: authorizationKey)
            guard defaults.data(forKey: authorizationKey) == nil else {
                rollback()
                return false
            }
        }
        rememberStateKey(key, storageKey: activeStorageKey)
        rememberStateKey(authorizationKey, storageKey: activeStorageKey)
        return true
    }

    private func removePendingAuthTransitionFile(_ binding: GarminPhoneBinding) {
        defaults.removeObject(forKey: pendingAuthTransitionKey(binding))
        defaults.removeObject(forKey: resetAuthorizationKey(binding))
    }

    private func restoreData(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func removePendingAuthTransition(_ pending: GarminPhonePendingAuthTransition) {
        removePendingAuthTransitionFile(pending.binding)
        guard deviceHandshakeMarker(pending.binding) == handshakeMarker(for: pending) else {
            return
        }
        defaults.removeObject(forKey: deviceHandshakeMarkerKey(pending.binding))
    }

    private func handshakeMarker(
        for pending: GarminPhonePendingAuthTransition
    ) -> GarminPhoneDeviceHandshakeMarker {
        GarminPhoneDeviceHandshakeMarker(
            bindingScope: bindingStateScope(pending.binding),
            syncID: pending.syncID,
            revision: pending.revision
        )
    }

    private func deviceHandshakeMarker(
        _ binding: GarminPhoneBinding
    ) -> GarminPhoneDeviceHandshakeMarker? {
        let key = deviceHandshakeMarkerKey(binding)
        guard let data = defaults.data(forKey: key) else { return nil }
        guard data.count <= 1_024,
              let marker = try? JSONDecoder().decode(
                  GarminPhoneDeviceHandshakeMarker.self,
                  from: data
              ),
              marker.bindingScope.isGarminBinding,
              marker.syncID.utf8.count >= 16,
              marker.syncID.utf8.count <= 128,
              marker.syncID.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) ||
                    "-_.:".unicodeScalars.contains($0)
              }),
              (1 ... GarminPhoneSyncProtocol.maximumSyncRevision)
                .contains(marker.revision) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return marker
    }

    private func resetAuthorization(
        for binding: GarminPhoneBinding,
        claimedPreviousBinding: GarminPhoneBinding
    ) -> GarminPhoneResetAuthorization? {
        let key = resetAuthorizationKey(binding)
        guard let data = defaults.data(forKey: key) else { return nil }
        let targetScope = bindingStateScope(binding)
        let previousScope = bindingStateScope(claimedPreviousBinding)
        guard data.count <= 2 * 1_024,
              let authorization = try? JSONDecoder().decode(
                  GarminPhoneResetAuthorization.self,
                  from: data
              ),
              authorization.deviceBinding == binding.device,
              authorization.targetBindingScope == targetScope,
              authorization.previousBindingScope != targetScope,
              authorization.targetBindingScope.isGarminBinding,
              authorization.previousBindingScope.isGarminBinding,
              GarminPhoneSyncProtocol.isValidMessageID(authorization.proofSyncID),
              GarminPhoneSyncProtocol.isValidMessageID(authorization.previousSyncID),
              (1 ... GarminPhoneSyncProtocol.maximumSyncRevision)
                .contains(authorization.proofRevision),
              (1 ... GarminPhoneSyncProtocol.maximumSyncRevision)
                .contains(authorization.previousRevision),
              authorization.proofRevision > authorization.previousRevision,
              let proof = pendingAuthTransition(binding),
              proof.handshake == .proof,
              proof.syncID == authorization.proofSyncID,
              proof.revision == authorization.proofRevision,
              deviceHandshakeMarker(binding) == handshakeMarker(for: proof) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        guard claimedPreviousBinding.device == binding.device,
              authorization.previousBindingScope == previousScope else {
            // A rejected watch claim must not consume a legitimate phone-side
            // transition authorization; the exact expected watch may retry.
            return nil
        }
        return authorization
    }

    private func pairingGenerationKey(
        accountBinding: String,
        deviceBinding: String
    ) -> String {
        "garmin-phone-generation.v1.\(Data("\(accountBinding)\u{0}\(deviceBinding)".utf8).garminSHA256Hex)"
    }

    private func receiptLedgerKey(binding: GarminPhoneBinding) -> String {
        "garmin-phone-receipts.v1.\(Data("\(binding.account)\u{0}\(binding.device)\u{0}\(binding.pairingGeneration)".utf8).garminSHA256Hex)"
    }

    private func normalizedLanguage(_ rawValue: String?) -> String {
        switch rawValue {
        case AppLanguage.ukrainian.rawValue: return "uk"
        case AppLanguage.russian.rawValue: return "ru"
        default: return "en"
        }
    }

    private func publishStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

extension GarminPhoneSyncService: IQDeviceEventDelegate {
    nonisolated func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshDeviceSummaries()
            guard status == .connected,
                  let device,
                  let app = self.apps[device.uuid as UUID] else {
                return
            }
            self.sendSync(to: app)
        }
    }

    nonisolated func deviceCharacteristicsDiscovered(_ device: IQDevice!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshDeviceSummaries()
            guard let device,
                  let app = self.apps[device.uuid as UUID] else {
                return
            }
            self.sendSync(to: app)
        }
    }
}

extension GarminPhoneSyncService: IQAppMessageDelegate {
    nonisolated func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let message, let app else { return }
        Task { @MainActor [weak self] in
            self?.process(message, app: app)
        }
    }
}

private enum GarminPhoneSyncError: Error {
    case accountChanged
}

private extension Data {
    var garminSHA256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var isGarminBinding: Bool {
        count == 64 && unicodeScalars.allSatisfy {
            ("0" ... "9").contains(Character($0)) ||
                ("a" ... "f").contains(Character($0))
        }
    }
}
