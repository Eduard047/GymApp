import CoreFoundation
import Foundation

enum LiveWorkoutContractError: Error, Equatable, Sendable {
    case invalidResponse
}

enum LiveWorkoutRoomStatus: String, Hashable, Sendable {
    case waiting
    case ready
    case active
    case completed
    case cancelled
    case expired
}

enum LiveWorkoutRole: String, Codable, Hashable, Sendable {
    case owner
    case participant
}

enum LiveWorkoutMemberState: String, Hashable, Sendable {
    case invited
    case joined
    case finished
    case left
    case revoked
}

struct LiveWorkoutProfile: Equatable, Sendable {
    let profileID: String
    let displayName: String
}

struct LiveWorkoutSummary: Equatable, Sendable {
    let exerciseCount: Int
    let setCount: Int
    let exerciseNames: [String]
}

struct LiveWorkoutPlanSet: Equatable, Sendable {
    let setID: String
    let weight: Double
    let reps: Int
}

struct LiveWorkoutPlanExercise: Equatable, Sendable {
    let exerciseID: String
    let catalogKey: String?
    let name: String
    let sets: [LiveWorkoutPlanSet]
}

struct LiveWorkoutPlan: Equatable, Sendable {
    let exercises: [LiveWorkoutPlanExercise]

    var sharedPlan: SharedWorkoutPlan {
        SharedWorkoutPlan(exercises: exercises.map { exercise in
            SharedWorkoutPlanExercise(
                catalogKey: exercise.catalogKey,
                name: exercise.name,
                sets: exercise.sets.map {
                    SharedWorkoutPlanSet(weight: $0.weight, repetitions: $0.reps)
                }
            )
        })
    }
}

struct LiveWorkoutCompletedSet: Equatable, Sendable {
    let setID: String
    let weight: Double
    let reps: Int
    let completedAt: String
}

struct LiveWorkoutProgress: Equatable, Sendable {
    let revision: Int
    let completedSets: [LiveWorkoutCompletedSet]
    let undoableSetID: String?
    let finishedAt: String?
}

struct LiveWorkoutParticipant: Equatable, Sendable {
    let isSelf: Bool
    let profile: LiveWorkoutProfile
    let role: LiveWorkoutRole
    let state: LiveWorkoutMemberState
    let membershipRevision: Int
    let joinedAt: String?
    let finishedAt: String?
    let departedAt: String?
    let progress: LiveWorkoutProgress?
}

struct LiveWorkoutRoom: Equatable, Sendable {
    let roomID: String
    let status: LiveWorkoutRoomStatus
    let roomRevision: Int
    let closeReason: String?
    let createdAt: String
    let inviteExpiresAt: String
    let startedAt: String?
    let activeExpiresAt: String?
    let endedAt: String?
    let summary: LiveWorkoutSummary
}

struct LiveWorkoutSnapshot: Equatable, Sendable {
    var allowsFinishedViewing: Bool {
        (room.status == .active || room.status == .completed)
            && currentParticipant?.state == .finished
            && currentParticipant?.progress?.finishedAt != nil
    }
    let room: LiveWorkoutRoom
    let plan: LiveWorkoutPlan
    let participants: [LiveWorkoutParticipant]

    var currentParticipant: LiveWorkoutParticipant? {
        participants.first(where: \.isSelf)
    }

    var peerParticipant: LiveWorkoutParticipant? {
        participants.first(where: { !$0.isSelf })
    }

    var exerciseLaneSummaries: [LiveWorkoutExerciseLaneSummary] {
        let selfCompleted = Set(
            currentParticipant?.progress?.completedSets.map(\.setID) ?? []
        )
        let peerCompleted = Set(
            peerParticipant?.progress?.completedSets.map(\.setID) ?? []
        )
        return plan.exercises.map { exercise in
            LiveWorkoutExerciseLaneSummary(
                exerciseID: exercise.exerciseID,
                catalogKey: exercise.catalogKey,
                name: exercise.name,
                selfCompleted: exercise.sets.map { selfCompleted.contains($0.setID) },
                peerCompleted: exercise.sets.map { peerCompleted.contains($0.setID) }
            )
        }
    }
}

struct LiveWorkoutExerciseLaneSummary: Identifiable, Equatable, Sendable {
    var id: String { exerciseID }
    let exerciseID: String
    let catalogKey: String?
    let name: String
    let selfCompleted: [Bool]
    let peerCompleted: [Bool]
}

struct LiveWorkoutInvitation: Identifiable, Equatable, Sendable {
    var id: String { roomID }
    let roomID: String
    let roomRevision: Int
    let createdAt: String
    let inviteExpiresAt: String
    let summary: LiveWorkoutSummary
    let owner: LiveWorkoutProfile
}

struct LiveWorkoutOpenRoom: Identifiable, Equatable, Sendable {
    var id: String { roomID }
    let roomID: String
    let status: LiveWorkoutRoomStatus
    let roomRevision: Int
    let role: LiveWorkoutRole
    let memberState: LiveWorkoutMemberState
    let membershipRevision: Int
    let createdAt: String
    let startedAt: String?
    let activeExpiresAt: String?
    let summary: LiveWorkoutSummary
    let peer: LiveWorkoutProfile
}

struct LiveWorkoutInbox: Equatable, Sendable {
    let invitations: [LiveWorkoutInvitation]
    let rooms: [LiveWorkoutOpenRoom]
}

struct LiveWorkoutSendResult: Equatable, Sendable {
    let submitted: Bool
    let roomID: String?
    let roomRevision: Int?
}

struct LiveWorkoutRespondResult: Equatable, Sendable {
    let result: String
    let roomID: String
    let status: LiveWorkoutRoomStatus
    let roomRevision: Int
    let membershipRevision: Int?
    let endedAt: String?
}

struct LiveWorkoutStartResult: Equatable, Sendable {
    let roomID: String
    let roomRevision: Int
    let startedAt: String
    let activeExpiresAt: String
    let progressRevision: Int
}

struct LiveWorkoutApplyResult: Equatable, Sendable {
    let roomID: String
    let roomRevision: Int
    let progressRevision: Int
    let kind: String
    let setID: String
    let completedAt: String?
}

struct LiveWorkoutFinishResult: Equatable, Sendable {
    let roomID: String
    let status: LiveWorkoutRoomStatus
    let roomRevision: Int
    let progressRevision: Int
    let membershipRevision: Int
    let finishedAt: String
}

struct LiveWorkoutTerminalResult: Equatable, Sendable {
    let result: String
    let roomID: String
    let status: LiveWorkoutRoomStatus
    let roomRevision: Int
    let membershipRevision: Int?
    let endedAt: String
}

struct LiveWorkoutRealtimeHint: Equatable, Sendable {
    let kind: String
    let roomID: String
    let roomRevision: Int
}

enum LiveWorkoutPayloadParser {
    static let maximumResponseBytes = 256 * 1_024
    static let maximumMutationResponseBytes = 32 * 1_024
    static let maximumRequestBytes = 48 * 1_024
    static let maximumOperations = 256

    /// Converts a timestamp that has already crossed the strict live-workout wire
    /// boundary into the local date representation used by the active-workout sidecars.
    /// Keep this parser shared so recovery never falls back to locale-dependent dates.
    static func validatedDate(from timestamp: String) throws -> Date {
        try date(try self.timestamp(timestamp))
    }

    static func gatewayResultData(from data: Data) throws -> Data {
        let root = try object(try json(data), keys: ["version", "result"])
        try version(root["version"])
        guard let result = root["result"], JSONSerialization.isValidJSONObject(result) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        guard !encoded.isEmpty, encoded.count <= maximumResponseBytes else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return encoded
    }

    private static let maximumRooms = 25
    private static let maximumExercises = 20
    private static let maximumSetsPerExercise = 12
    private static let maximumTotalSets = 120
    private static let maximumRevision = 2_147_483_647
    private static let maximumWeight = 1_000_000.0
    private static let maximumReps = 10_000
    private static let roomPattern = try! NSRegularExpression(pattern: #"^lr_[0-9a-f]{32}$"#)
    private static let profilePattern = try! NSRegularExpression(pattern: #"^p_[0-9a-f]{32}$"#)
    private static let exercisePattern = try! NSRegularExpression(pattern: #"^e_[0-9]{2}$"#)
    private static let setPattern = try! NSRegularExpression(pattern: #"^s_[0-9]{2}_[0-9]{2}$"#)
    private static let catalogPattern = try! NSRegularExpression(pattern: #"^[a-z0-9_]{1,64}$"#)
    private static let timestampPattern = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$"#
    )

    static func inbox(from data: Data) throws -> LiveWorkoutInbox {
        let root = try object(try json(data), keys: ["version", "invitations", "rooms"])
        try version(root["version"])
        let invitations = try array(root["invitations"], maximumCount: maximumRooms).map { value in
            let row = try object(
                value,
                keys: [
                    "roomId", "status", "roomRevision", "createdAt", "inviteExpiresAt",
                    "summary", "owner"
                ]
            )
            guard try string(row["status"], maximumCharacters: 16, maximumBytes: 16) == "waiting" else {
                throw LiveWorkoutContractError.invalidResponse
            }
            let createdAt = try timestamp(row["createdAt"])
            let inviteExpiresAt = try timestamp(row["inviteExpiresAt"])
            guard try date(inviteExpiresAt) > date(createdAt) else {
                throw LiveWorkoutContractError.invalidResponse
            }
            return LiveWorkoutInvitation(
                roomID: try identifier(row["roomId"], pattern: roomPattern),
                roomRevision: try revision(row["roomRevision"]),
                createdAt: createdAt,
                inviteExpiresAt: inviteExpiresAt,
                summary: try summary(row["summary"]),
                owner: try profile(row["owner"])
            )
        }
        let rooms = try array(root["rooms"], maximumCount: maximumRooms).map { value in
            let row = try object(
                value,
                keys: [
                    "roomId", "status", "roomRevision", "role", "memberState",
                    "membershipRevision", "createdAt", "startedAt", "activeExpiresAt",
                    "summary", "peer"
                ]
            )
            let status = try roomStatus(row["status"], allowed: [.waiting, .ready, .active])
            let role = try role(row["role"])
            let memberState = try memberState(row["memberState"])
            guard memberState == .joined || memberState == .finished else {
                throw LiveWorkoutContractError.invalidResponse
            }
            let startedAt = try optionalTimestamp(row["startedAt"])
            let activeExpiresAt = try optionalTimestamp(row["activeExpiresAt"])
            guard (status == .active) == (startedAt != nil && activeExpiresAt != nil) else {
                throw LiveWorkoutContractError.invalidResponse
            }
            if let startedAt, let activeExpiresAt, try date(activeExpiresAt) <= date(startedAt) {
                throw LiveWorkoutContractError.invalidResponse
            }
            return LiveWorkoutOpenRoom(
                roomID: try identifier(row["roomId"], pattern: roomPattern),
                status: status,
                roomRevision: try revision(row["roomRevision"]),
                role: role,
                memberState: memberState,
                membershipRevision: try revision(row["membershipRevision"]),
                createdAt: try timestamp(row["createdAt"]),
                startedAt: startedAt,
                activeExpiresAt: activeExpiresAt,
                summary: try summary(row["summary"]),
                peer: try profile(row["peer"])
            )
        }
        let identifiers = invitations.map(\.roomID) + rooms.map(\.roomID)
        guard Set(identifiers).count == identifiers.count else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutInbox(invitations: invitations, rooms: rooms)
    }

    static func snapshot(from data: Data) throws -> LiveWorkoutSnapshot {
        let root = try object(try json(data), keys: ["version", "room", "plan", "participants"])
        try version(root["version"])
        let parsedPlan = try plan(root["plan"])
        let parsedRoom = try room(root["room"])
        guard parsedRoom.summary.exerciseCount == parsedPlan.exercises.count,
              parsedRoom.summary.setCount == parsedPlan.exercises.reduce(0, { $0 + $1.sets.count }),
              parsedRoom.summary.exerciseNames == parsedPlan.exercises.map(\.name) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        let participants = try array(root["participants"], exactCount: 2).map {
            try participant($0, plan: parsedPlan, roomStatus: parsedRoom.status)
        }
        guard participants.filter(\.isSelf).count == 1,
              Set(participants.map(\.role)).count == 2,
              Set(participants.map { $0.profile.profileID }).count == 2 else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutSnapshot(room: parsedRoom, plan: parsedPlan, participants: participants)
    }

    static func sendResult(from data: Data) throws -> LiveWorkoutSendResult {
        let row = try object(
            try json(data),
            keys: ["version", "result", "roomId", "status", "roomRevision"]
        )
        try version(row["version"])
        let result = try string(row["result"], maximumCharacters: 32, maximumBytes: 32)
        guard result == "submitted" || result == "submitted_or_unavailable" else {
            throw LiveWorkoutContractError.invalidResponse
        }
        if result == "submitted_or_unavailable" {
            guard row["roomId"] is NSNull, row["status"] is NSNull, row["roomRevision"] is NSNull else {
                throw LiveWorkoutContractError.invalidResponse
            }
            return LiveWorkoutSendResult(submitted: false, roomID: nil, roomRevision: nil)
        }
        guard try string(row["status"], maximumCharacters: 16, maximumBytes: 16) == "waiting" else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutSendResult(
            submitted: true,
            roomID: try identifier(row["roomId"], pattern: roomPattern),
            roomRevision: try revision(row["roomRevision"])
        )
    }

    static func respondResult(from data: Data) throws -> LiveWorkoutRespondResult {
        let raw = try json(data)
        let probe = try objectWithAllowedKeys(
            raw,
            required: ["version", "result", "roomId", "status", "roomRevision"],
            optional: ["membershipRevision", "endedAt"]
        )
        try version(probe["version"])
        let result = try string(probe["result"], maximumCharacters: 16, maximumBytes: 16)
        if result == "closed" {
            guard Set(probe.keys) == Set(["version", "result", "roomId", "status", "roomRevision", "endedAt"]),
                  try roomStatus(probe["status"], allowed: [.expired]) == .expired else {
                throw LiveWorkoutContractError.invalidResponse
            }
            _ = try identifier(probe["roomId"], pattern: roomPattern)
            _ = try revision(probe["roomRevision"])
            _ = try timestamp(probe["endedAt"])
            throw LiveWorkoutGatewayError.resourceUnavailable
        }
        let joined = result == "joined"
        let expected = joined
            ? ["version", "result", "roomId", "status", "roomRevision", "membershipRevision"]
            : ["version", "result", "roomId", "status", "roomRevision", "membershipRevision", "endedAt"]
        let row = try object(raw, keys: expected)
        guard result == "joined" || result == "declined" else {
            throw LiveWorkoutContractError.invalidResponse
        }
        // The atomic-accept contract activates the room immediately. Keep `.ready`
        // decode compatibility for responses delivered by the previous server version.
        let status = try roomStatus(
            row["status"],
            allowed: joined ? [.ready, .active] : [.cancelled]
        )
        return LiveWorkoutRespondResult(
            result: result,
            roomID: try identifier(row["roomId"], pattern: roomPattern),
            status: status,
            roomRevision: try revision(row["roomRevision"]),
            membershipRevision: try revision(row["membershipRevision"]),
            endedAt: joined ? nil : try timestamp(row["endedAt"])
        )
    }

    static func startResult(from data: Data) throws -> LiveWorkoutStartResult {
        let raw = try json(data)
        if let row = raw as? [String: Any], row["result"] as? String == "closed" {
            _ = try terminalResult(fromObject: raw, expectedResult: "closed")
            throw LiveWorkoutGatewayError.resourceUnavailable
        }
        let row = try object(
            raw,
            keys: [
                "version", "result", "roomId", "status", "roomRevision", "startedAt",
                "activeExpiresAt", "myProgressRevision"
            ]
        )
        try version(row["version"])
        guard try string(row["result"], maximumCharacters: 16, maximumBytes: 16) == "started",
              try roomStatus(row["status"], allowed: [.active]) == .active else {
            throw LiveWorkoutContractError.invalidResponse
        }
        let startedAt = try timestamp(row["startedAt"])
        let expiresAt = try timestamp(row["activeExpiresAt"])
        guard try date(expiresAt) > date(startedAt) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutStartResult(
            roomID: try identifier(row["roomId"], pattern: roomPattern),
            roomRevision: try revision(row["roomRevision"]),
            startedAt: startedAt,
            activeExpiresAt: expiresAt,
            progressRevision: try revision(row["myProgressRevision"])
        )
    }

    static func applyResult(from data: Data) throws -> LiveWorkoutApplyResult {
        let raw = try json(data)
        if let row = raw as? [String: Any], row["result"] as? String == "closed" {
            _ = try terminalResult(fromObject: raw, expectedResult: "closed")
            throw LiveWorkoutGatewayError.resourceUnavailable
        }
        let row = try object(
            raw,
            keys: [
                "version", "result", "roomId", "roomRevision", "progressRevision", "kind",
                "setId", "completedAt"
            ]
        )
        try version(row["version"])
        let kind = try string(row["kind"], maximumCharacters: 24, maximumBytes: 24)
        guard try string(row["result"], maximumCharacters: 16, maximumBytes: 16) == "applied",
              kind == "complete_set" || kind == "undo_set" else {
            throw LiveWorkoutContractError.invalidResponse
        }
        let completedAt = try optionalTimestamp(row["completedAt"])
        guard (kind == "complete_set") == (completedAt != nil) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutApplyResult(
            roomID: try identifier(row["roomId"], pattern: roomPattern),
            roomRevision: try revision(row["roomRevision"]),
            progressRevision: try revision(row["progressRevision"]),
            kind: kind,
            setID: try identifier(row["setId"], pattern: setPattern),
            completedAt: completedAt
        )
    }

    static func finishResult(from data: Data) throws -> LiveWorkoutFinishResult {
        let raw = try json(data)
        if let row = raw as? [String: Any], row["result"] as? String == "closed" {
            _ = try terminalResult(fromObject: raw, expectedResult: "closed")
            throw LiveWorkoutGatewayError.resourceUnavailable
        }
        let row = try object(
            raw,
            keys: [
                "version", "result", "roomId", "status", "roomRevision", "progressRevision",
                "membershipRevision", "finishedAt"
            ]
        )
        try version(row["version"])
        guard try string(row["result"], maximumCharacters: 16, maximumBytes: 16) == "finished" else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutFinishResult(
            roomID: try identifier(row["roomId"], pattern: roomPattern),
            status: try roomStatus(row["status"], allowed: [.active, .completed]),
            roomRevision: try revision(row["roomRevision"]),
            progressRevision: try revision(row["progressRevision"]),
            membershipRevision: try revision(row["membershipRevision"]),
            finishedAt: try timestamp(row["finishedAt"])
        )
    }

    static func terminalResult(from data: Data, expectedResult: String) throws -> LiveWorkoutTerminalResult {
        try terminalResult(fromObject: json(data), expectedResult: expectedResult)
    }

    static func realtimeHint(from value: Any) throws -> LiveWorkoutRealtimeHint {
        let row = try object(value, keys: ["version", "kind", "roomId", "roomRevision"])
        try version(row["version"])
        let kind = try string(row["kind"], maximumCharacters: 24, maximumBytes: 24)
        guard [
            "invite", "joined", "started", "progress", "participant_finished", "room_closed"
        ].contains(kind) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutRealtimeHint(
            kind: kind,
            roomID: try identifier(row["roomId"], pattern: roomPattern),
            roomRevision: try revision(row["roomRevision"])
        )
    }

    static func workoutObject(for plan: SharedWorkoutPlan) throws -> [String: Any] {
        let validated = try SharedWorkoutLinkValidator.validate(plan)
        let value: [String: Any] = [
            "version": 1,
            "exercises": validated.exercises.map { exercise in
                var row: [String: Any] = [
                    "name": exercise.name,
                    "sets": exercise.sets.map {
                        ["weight": $0.weight == 0 ? 0.0 : $0.weight, "reps": $0.repetitions]
                    }
                ]
                if let catalogKey = exercise.catalogKey { row["catalogKey"] = catalogKey }
                return row
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= 40 * 1_024 else { throw LiveWorkoutContractError.invalidResponse }
        return value
    }

    private static func terminalResult(fromObject raw: Any, expectedResult: String) throws -> LiveWorkoutTerminalResult {
        let closed = expectedResult == "closed"
        let expected = closed
            ? ["version", "result", "roomId", "status", "roomRevision", "endedAt"]
            : ["version", "result", "roomId", "status", "roomRevision", "membershipRevision", "endedAt"]
        let row = try object(raw, keys: expected)
        try version(row["version"])
        let result = try string(row["result"], maximumCharacters: 16, maximumBytes: 16)
        guard result == expectedResult else { throw LiveWorkoutContractError.invalidResponse }
        let status = try roomStatus(row["status"], allowed: closed ? [.expired] : [.cancelled])
        return LiveWorkoutTerminalResult(
            result: result,
            roomID: try identifier(row["roomId"], pattern: roomPattern),
            status: status,
            roomRevision: try revision(row["roomRevision"]),
            membershipRevision: closed ? nil : try revision(row["membershipRevision"]),
            endedAt: try timestamp(row["endedAt"])
        )
    }

    private static func room(_ value: Any?) throws -> LiveWorkoutRoom {
        let row = try object(
            value,
            keys: [
                "roomId", "status", "roomRevision", "closeReason", "createdAt",
                "inviteExpiresAt", "startedAt", "activeExpiresAt", "endedAt", "summary"
            ]
        )
        let status = try roomStatus(
            row["status"],
            allowed: [.waiting, .ready, .active, .completed, .cancelled, .expired]
        )
        let createdAt = try timestamp(row["createdAt"])
        let inviteExpiresAt = try timestamp(row["inviteExpiresAt"])
        let startedAt = try optionalTimestamp(row["startedAt"])
        let activeExpiresAt = try optionalTimestamp(row["activeExpiresAt"])
        let endedAt = try optionalTimestamp(row["endedAt"])
        let closeReason = try optionalString(row["closeReason"], maximumCharacters: 32, maximumBytes: 32)
        let terminal = status == .completed || status == .cancelled || status == .expired
        let open = status == .waiting || status == .ready || status == .active
        let validCloseReasons = [
            "completed", "declined", "cancelled", "left", "friend_removed", "blocked",
            "account_deleted", "expired"
        ]
        guard try date(inviteExpiresAt) > date(createdAt),
              (startedAt == nil) == (activeExpiresAt == nil),
              !([.waiting, .ready].contains(status) && startedAt != nil),
              !([.active, .completed].contains(status) && startedAt == nil),
              terminal == (endedAt != nil),
              open == (closeReason == nil),
              closeReason.map({ validCloseReasons.contains($0) }) ?? true,
              (status != .completed || closeReason == "completed"),
              (status != .expired || closeReason == "expired") else {
            throw LiveWorkoutContractError.invalidResponse
        }
        if let startedAt, let activeExpiresAt, try date(activeExpiresAt) <= date(startedAt) {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutRoom(
            roomID: try identifier(row["roomId"], pattern: roomPattern),
            status: status,
            roomRevision: try revision(row["roomRevision"]),
            closeReason: closeReason,
            createdAt: createdAt,
            inviteExpiresAt: inviteExpiresAt,
            startedAt: startedAt,
            activeExpiresAt: activeExpiresAt,
            endedAt: endedAt,
            summary: try summary(row["summary"])
        )
    }

    private static func plan(_ value: Any?) throws -> LiveWorkoutPlan {
        let root = try object(value, keys: ["version", "exercises"])
        try version(root["version"])
        let values = try array(root["exercises"], minimumCount: 1, maximumCount: maximumExercises)
        var totalSets = 0
        var nameKeys = Set<String>()
        var catalogKeys = Set<String>()
        var setIDs = Set<String>()
        var exercises: [LiveWorkoutPlanExercise] = []
        for (exerciseIndex, value) in values.enumerated() {
            let row = try objectWithAllowedKeys(
                value,
                required: ["exerciseId", "name", "sets"],
                optional: ["catalogKey"]
            )
            let exerciseID = try identifier(row["exerciseId"], pattern: exercisePattern)
            guard exerciseID == String(format: "e_%02d", exerciseIndex + 1) else {
                throw LiveWorkoutContractError.invalidResponse
            }
            let name = try safeText(row["name"], maximumCharacters: 120, maximumBytes: 480)
            guard nameKeys.insert(normalizeExerciseIdentityName(name)).inserted else {
                throw LiveWorkoutContractError.invalidResponse
            }
            let catalogKey: String?
            if row.keys.contains("catalogKey") {
                catalogKey = try identifier(row["catalogKey"], pattern: catalogPattern)
                guard catalogKeys.insert(catalogKey!).inserted else {
                    throw LiveWorkoutContractError.invalidResponse
                }
            } else {
                catalogKey = nil
            }
            let setValues = try array(
                row["sets"],
                minimumCount: 1,
                maximumCount: maximumSetsPerExercise
            )
            totalSets += setValues.count
            guard totalSets <= maximumTotalSets else {
                throw LiveWorkoutContractError.invalidResponse
            }
            var sets: [LiveWorkoutPlanSet] = []
            for (setIndex, value) in setValues.enumerated() {
                let set = try object(value, keys: ["setId", "weight", "reps"])
                let setID = try identifier(set["setId"], pattern: setPattern)
                guard setID == String(format: "s_%02d_%02d", exerciseIndex + 1, setIndex + 1),
                      setIDs.insert(setID).inserted else {
                    throw LiveWorkoutContractError.invalidResponse
                }
                sets.append(LiveWorkoutPlanSet(
                    setID: setID,
                    weight: try number(set["weight"], range: 0 ... maximumWeight),
                    reps: try integer(set["reps"], range: 1 ... maximumReps)
                ))
            }
            exercises.append(LiveWorkoutPlanExercise(
                exerciseID: exerciseID,
                catalogKey: catalogKey,
                name: name,
                sets: sets
            ))
        }
        return LiveWorkoutPlan(exercises: exercises)
    }

    private static func participant(
        _ value: Any,
        plan: LiveWorkoutPlan,
        roomStatus: LiveWorkoutRoomStatus
    ) throws -> LiveWorkoutParticipant {
        let row = try object(
            value,
            keys: [
                "isSelf", "profile", "role", "state", "membershipRevision", "joinedAt",
                "finishedAt", "departedAt", "progress"
            ]
        )
        guard let isSelf = row["isSelf"] as? Bool else {
            throw LiveWorkoutContractError.invalidResponse
        }
        let state = try memberState(row["state"])
        let joinedAt = try optionalTimestamp(row["joinedAt"])
        let finishedAt = try optionalTimestamp(row["finishedAt"])
        let departedAt = try optionalTimestamp(row["departedAt"])
        let validLifecycle: Bool
        switch state {
        case .invited:
            validLifecycle = joinedAt == nil && finishedAt == nil && departedAt == nil
        case .joined:
            validLifecycle = joinedAt != nil && finishedAt == nil && departedAt == nil
        case .finished:
            validLifecycle = joinedAt != nil && finishedAt != nil && departedAt == nil
        case .left, .revoked:
            validLifecycle = departedAt != nil
        }
        guard validLifecycle else { throw LiveWorkoutContractError.invalidResponse }
        let parsedProgress = row["progress"] is NSNull ? nil : try progress(row["progress"], plan: plan)
        guard !([.waiting, .ready].contains(roomStatus) && parsedProgress != nil),
              !([.active, .completed].contains(roomStatus) &&
                [.joined, .finished].contains(state) && parsedProgress == nil),
              !(state == .finished && parsedProgress?.finishedAt == nil) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutParticipant(
            isSelf: isSelf,
            profile: try profile(row["profile"]),
            role: try role(row["role"]),
            state: state,
            membershipRevision: try revision(row["membershipRevision"]),
            joinedAt: joinedAt,
            finishedAt: finishedAt,
            departedAt: departedAt,
            progress: parsedProgress
        )
    }

    private static func progress(_ value: Any?, plan: LiveWorkoutPlan) throws -> LiveWorkoutProgress {
        let row = try object(
            value,
            keys: ["version", "revision", "completedSets", "undoableSetId", "finishedAt"]
        )
        try version(row["version"])
        let validSetIDs = Set(plan.exercises.flatMap { $0.sets.map(\.setID) })
        var completedIDs = Set<String>()
        let completed = try array(row["completedSets"], maximumCount: maximumTotalSets).map { value in
            let set = try object(value, keys: ["setId", "weight", "reps", "completedAt"])
            let setID = try identifier(set["setId"], pattern: setPattern)
            guard validSetIDs.contains(setID), completedIDs.insert(setID).inserted else {
                throw LiveWorkoutContractError.invalidResponse
            }
            return LiveWorkoutCompletedSet(
                setID: setID,
                weight: try number(set["weight"], range: 0 ... maximumWeight),
                reps: try integer(set["reps"], range: 1 ... maximumReps),
                completedAt: try timestamp(set["completedAt"])
            )
        }
        let undoableSetID: String?
        if row["undoableSetId"] is NSNull {
            undoableSetID = nil
        } else {
            undoableSetID = try identifier(row["undoableSetId"], pattern: setPattern)
            guard completedIDs.contains(undoableSetID!), completed.last?.setID == undoableSetID else {
                throw LiveWorkoutContractError.invalidResponse
            }
        }
        let finishedAt = try optionalTimestamp(row["finishedAt"])
        guard !(finishedAt != nil && undoableSetID != nil) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutProgress(
            revision: try revision(row["revision"]),
            completedSets: completed,
            undoableSetID: undoableSetID,
            finishedAt: finishedAt
        )
    }

    private static func summary(_ value: Any?) throws -> LiveWorkoutSummary {
        let row = try object(value, keys: ["exerciseCount", "setCount", "exerciseNames"])
        let exerciseCount = try integer(row["exerciseCount"], range: 1 ... maximumExercises)
        let names = try array(row["exerciseNames"], exactCount: exerciseCount).map {
            try safeText($0, maximumCharacters: 120, maximumBytes: 480)
        }
        guard Set(names.map(normalizeExerciseIdentityName)).count == names.count else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return LiveWorkoutSummary(
            exerciseCount: exerciseCount,
            setCount: try integer(row["setCount"], range: 1 ... maximumTotalSets),
            exerciseNames: names
        )
    }

    private static func profile(_ value: Any?) throws -> LiveWorkoutProfile {
        let row = try object(value, keys: ["profileId", "displayName"])
        return LiveWorkoutProfile(
            profileID: try identifier(row["profileId"], pattern: profilePattern),
            displayName: try safeText(row["displayName"], maximumCharacters: 40, maximumBytes: 160)
        )
    }

    private static func role(_ value: Any?) throws -> LiveWorkoutRole {
        guard let role = LiveWorkoutRole(
            rawValue: try string(value, maximumCharacters: 16, maximumBytes: 16)
        ) else { throw LiveWorkoutContractError.invalidResponse }
        return role
    }

    private static func memberState(_ value: Any?) throws -> LiveWorkoutMemberState {
        guard let state = LiveWorkoutMemberState(
            rawValue: try string(value, maximumCharacters: 16, maximumBytes: 16)
        ) else { throw LiveWorkoutContractError.invalidResponse }
        return state
    }

    private static func roomStatus(
        _ value: Any?,
        allowed: Set<LiveWorkoutRoomStatus>
    ) throws -> LiveWorkoutRoomStatus {
        guard let status = LiveWorkoutRoomStatus(
            rawValue: try string(value, maximumCharacters: 16, maximumBytes: 16)
        ), allowed.contains(status) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return status
    }

    private static func json(_ data: Data) throws -> Any {
        guard !data.isEmpty, data.count <= maximumResponseBytes else {
            throw LiveWorkoutContractError.invalidResponse
        }
        try StrictLiveWorkoutJSONScanner.validate(data)
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LiveWorkoutContractError.invalidResponse
        }
    }

    private static func object(_ value: Any?, keys: [String]) throws -> [String: Any] {
        guard let value = value as? [String: Any], Set(value.keys) == Set(keys) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return value
    }

    private static func objectWithAllowedKeys(
        _ value: Any?,
        required: [String],
        optional: [String]
    ) throws -> [String: Any] {
        guard let value = value as? [String: Any],
              Set(required).isSubset(of: value.keys),
              Set(value.keys).isSubset(of: Set(required + optional)) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return value
    }

    private static func array(
        _ value: Any?,
        minimumCount: Int = 0,
        maximumCount: Int
    ) throws -> [Any] {
        guard let value = value as? [Any],
              value.count >= minimumCount,
              value.count <= maximumCount else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return value
    }

    private static func array(_ value: Any?, exactCount: Int) throws -> [Any] {
        guard let value = value as? [Any], value.count == exactCount else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return value
    }

    private static func version(_ value: Any?) throws {
        guard try integer(value, range: 1 ... 1) == 1 else {
            throw LiveWorkoutContractError.invalidResponse
        }
    }

    private static func revision(_ value: Any?) throws -> Int {
        try integer(value, range: 1 ... maximumRevision)
    }

    private static func integer(_ value: Any?, range: ClosedRange<Int>) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= Double(Int.min),
              number.doubleValue <= Double(Int.max),
              range.contains(number.intValue) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return number.intValue
    }

    private static func number(_ value: Any?, range: ClosedRange<Double>) throws -> Double {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              range.contains(number.doubleValue) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return number.doubleValue == 0 ? 0.0 : number.doubleValue
    }

    private static func identifier(_ value: Any?, pattern: NSRegularExpression) throws -> String {
        let string = try string(value, maximumCharacters: 80, maximumBytes: 80)
        let range = NSRange(string.startIndex..., in: string)
        guard pattern.firstMatch(in: string, range: range)?.range == range else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return string
    }

    private static func safeText(
        _ value: Any?,
        maximumCharacters: Int,
        maximumBytes: Int
    ) throws -> String {
        let value = try string(
            value,
            maximumCharacters: maximumCharacters,
            maximumBytes: maximumBytes
        )
        guard !value.isEmpty,
              value.first != " ",
              value.last != " ",
              !value.unicodeScalars.contains(where: { scalar in
                  CharacterSet.controlCharacters.contains(scalar) ||
                      scalar.properties.generalCategory == .format ||
                      scalar.value == 0x2028 || scalar.value == 0x2029
              }) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return value
    }

    private static func string(
        _ value: Any?,
        maximumCharacters: Int,
        maximumBytes: Int
    ) throws -> String {
        guard let value = value as? String,
              value.count <= maximumCharacters,
              value.utf8.count <= maximumBytes else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return value
    }

    private static func optionalString(
        _ value: Any?,
        maximumCharacters: Int,
        maximumBytes: Int
    ) throws -> String? {
        if value is NSNull { return nil }
        return try string(value, maximumCharacters: maximumCharacters, maximumBytes: maximumBytes)
    }

    private static func timestamp(_ value: Any?) throws -> String {
        let value = try string(value, maximumCharacters: 40, maximumBytes: 40)
        let range = NSRange(value.startIndex..., in: value)
        guard timestampPattern.firstMatch(in: value, range: range)?.range == range,
              let parsed = parseTimestamp(value) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        let components = value.prefix(19).split(whereSeparator: { $0 == "-" || $0 == "T" || $0 == ":" })
        guard components.count == 6,
              let rawYear = Int(components[0]),
              let rawMonth = Int(components[1]),
              let rawDay = Int(components[2]),
              let rawHour = Int(components[3]),
              let rawMinute = Int(components[4]),
              let rawSecond = Int(components[5]),
              (2020 ... 2200).contains(rawYear),
              (1 ... 12).contains(rawMonth),
              (0 ... 23).contains(rawHour),
              (0 ... 59).contains(rawMinute),
              (0 ... 59).contains(rawSecond),
              Calendar(identifier: .gregorian).date(
                from: DateComponents(year: rawYear, month: rawMonth, day: rawDay)
              ).map({ date in
                  let check = Calendar(identifier: .gregorian).dateComponents(
                    [.year, .month, .day],
                    from: date
                  )
                  return check.year == rawYear && check.month == rawMonth && check.day == rawDay
              }) == true else {
            throw LiveWorkoutContractError.invalidResponse
        }
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: parsed)
        guard (2019 ... 2201).contains(year) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return value
    }

    private static func optionalTimestamp(_ value: Any?) throws -> String? {
        if value is NSNull { return nil }
        return try timestamp(value)
    }

    private static func date(_ value: String) throws -> Date {
        guard let parsed = parseTimestamp(value) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return parsed
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        ISO8601DateFormatter.gymLiveWorkoutFractional.date(from: value) ??
            ISO8601DateFormatter.gymLiveWorkoutWholeSeconds.date(from: value)
    }
}

private extension ISO8601DateFormatter {
    static let gymLiveWorkoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let gymLiveWorkoutWholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

struct StrictLiveWorkoutJSONScanner {
    private let bytes: [UInt8]
    private var index = 0
    private var containers = 0

    static func validate(_ data: Data) throws {
        var scanner = Self(bytes: Array(data))
        try scanner.parseValue(depth: 0)
        scanner.skipWhitespace()
        guard scanner.index == scanner.bytes.count else {
            throw LiveWorkoutContractError.invalidResponse
        }
    }

    private mutating func parseValue(depth: Int) throws {
        guard depth <= 16 else { throw LiveWorkoutContractError.invalidResponse }
        skipWhitespace()
        guard let byte = current else { throw LiveWorkoutContractError.invalidResponse }
        switch byte {
        case 0x7B: try parseObject(depth: depth + 1)
        case 0x5B: try parseArray(depth: depth + 1)
        case 0x22: _ = try parseString()
        case 0x74: try consumeLiteral("true")
        case 0x66: try consumeLiteral("false")
        case 0x6E: try consumeLiteral("null")
        case 0x2D, 0x30 ... 0x39: try parseNumber()
        default: throw LiveWorkoutContractError.invalidResponse
        }
    }

    private mutating func parseObject(depth: Int) throws {
        containers += 1
        guard containers <= 1_024 else { throw LiveWorkoutContractError.invalidResponse }
        try consume(0x7B)
        skipWhitespace()
        if current == 0x7D { index += 1; return }
        var keys = Set<String>()
        while true {
            skipWhitespace()
            let key = try parseString()
            guard key.utf8.count <= 80, keys.insert(key).inserted else {
                throw LiveWorkoutContractError.invalidResponse
            }
            skipWhitespace()
            try consume(0x3A)
            try parseValue(depth: depth)
            skipWhitespace()
            if current == 0x7D { index += 1; return }
            try consume(0x2C)
        }
    }

    private mutating func parseArray(depth: Int) throws {
        containers += 1
        guard containers <= 1_024 else { throw LiveWorkoutContractError.invalidResponse }
        try consume(0x5B)
        skipWhitespace()
        if current == 0x5D { index += 1; return }
        var count = 0
        while true {
            count += 1
            guard count <= 256 else { throw LiveWorkoutContractError.invalidResponse }
            try parseValue(depth: depth)
            skipWhitespace()
            if current == 0x5D { index += 1; return }
            try consume(0x2C)
        }
    }

    private mutating func parseString() throws -> String {
        try consume(0x22)
        var raw: [UInt8] = []
        while let byte = current {
            index += 1
            if byte == 0x22 {
                guard let value = String(bytes: raw, encoding: .utf8), value.utf8.count <= 4_000 else {
                    throw LiveWorkoutContractError.invalidResponse
                }
                return value
            }
            if byte == 0x5C {
                guard let escaped = current else { throw LiveWorkoutContractError.invalidResponse }
                index += 1
                switch escaped {
                case 0x22: raw.append(0x22)
                case 0x5C: raw.append(0x5C)
                case 0x2F: raw.append(0x2F)
                case 0x62: raw.append(0x08)
                case 0x66: raw.append(0x0C)
                case 0x6E: raw.append(0x0A)
                case 0x72: raw.append(0x0D)
                case 0x74: raw.append(0x09)
                case 0x75:
                    let scalar = try parseUnicodeEscape()
                    raw.append(contentsOf: String(scalar).utf8)
                default: throw LiveWorkoutContractError.invalidResponse
                }
            } else {
                guard byte >= 0x20 else { throw LiveWorkoutContractError.invalidResponse }
                raw.append(byte)
            }
        }
        throw LiveWorkoutContractError.invalidResponse
    }

    private mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
        let first = try parseHexQuad()
        if (0xD800 ... 0xDBFF).contains(first) {
            try consume(0x5C)
            try consume(0x75)
            let second = try parseHexQuad()
            guard (0xDC00 ... 0xDFFF).contains(second),
                  let scalar = Unicode.Scalar(
                    0x10000 + ((UInt32(first) - 0xD800) << 10) + (UInt32(second) - 0xDC00)
                  ) else { throw LiveWorkoutContractError.invalidResponse }
            return scalar
        }
        guard !(0xDC00 ... 0xDFFF).contains(first), let scalar = Unicode.Scalar(first) else {
            throw LiveWorkoutContractError.invalidResponse
        }
        return scalar
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = current else { throw LiveWorkoutContractError.invalidResponse }
            index += 1
            let value: UInt32
            switch byte {
            case 0x30 ... 0x39: value = UInt32(byte - 0x30)
            case 0x41 ... 0x46: value = UInt32(byte - 0x41 + 10)
            case 0x61 ... 0x66: value = UInt32(byte - 0x61 + 10)
            default: throw LiveWorkoutContractError.invalidResponse
            }
            result = result * 16 + value
        }
        return result
    }

    private mutating func parseNumber() throws {
        let start = index
        if current == 0x2D { index += 1 }
        if current == 0x30 {
            index += 1
            if let current, (0x30 ... 0x39).contains(current) {
                throw LiveWorkoutContractError.invalidResponse
            }
        } else {
            try consumeDigits(minimum: 1)
        }
        if current == 0x2E {
            index += 1
            try consumeDigits(minimum: 1)
        }
        if current == 0x65 || current == 0x45 {
            index += 1
            if current == 0x2B || current == 0x2D { index += 1 }
            try consumeDigits(minimum: 1)
        }
        guard index - start <= 64 else { throw LiveWorkoutContractError.invalidResponse }
    }

    private mutating func consumeDigits(minimum: Int) throws {
        let start = index
        while let byte = current, (0x30 ... 0x39).contains(byte) { index += 1 }
        guard index - start >= minimum else { throw LiveWorkoutContractError.invalidResponse }
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        for byte in literal.utf8 { try consume(byte) }
    }

    private mutating func consume(_ expected: UInt8) throws {
        guard current == expected else { throw LiveWorkoutContractError.invalidResponse }
        index += 1
    }

    private mutating func skipWhitespace() {
        while let byte = current, [0x20, 0x09, 0x0A, 0x0D].contains(byte) { index += 1 }
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }
}
