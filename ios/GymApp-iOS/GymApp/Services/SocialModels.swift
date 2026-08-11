import CoreFoundation
import Foundation

struct SocialPrivacy: Equatable, Sendable {
    var allowRequests: Bool
    var shareProgress: Bool
    var shareRecentWorkouts: Bool
    var shareRecords: Bool
}

struct SocialSelfProfile: Equatable, Sendable {
    let profileID: String
    let friendCode: String
    let displayName: String
    let xp: Int?
    let level: Int?
    let workouts: Int?
    let statsAvailable: Bool
    let progressUpdatedAt: String?
    let privacy: SocialPrivacy
    let settingsRevision: Int
}

struct SocialFriendSummary: Identifiable, Equatable, Sendable {
    var id: String { friendshipID }

    let friendshipID: String
    let profileID: String
    let displayName: String
    let xp: Int?
    let level: Int?
    let workouts: Int?
    let progressShared: Bool
    let statsAvailable: Bool
    let progressUpdatedAt: String?
    let friendshipRevision: Int
}

struct SocialFriendRequest: Identifiable, Equatable, Sendable {
    var id: String { friendshipID }

    let friendshipID: String
    let profileID: String
    let displayName: String
    let requestedAt: String
    let friendshipRevision: Int
}

struct SocialBlockedProfile: Identifiable, Equatable, Sendable {
    var id: String { profileID }

    let profileID: String
    let displayName: String
    let blockedAt: String
}

struct SocialDashboard: Equatable, Sendable {
    let currentUser: SocialSelfProfile
    let friends: [SocialFriendSummary]
    let incoming: [SocialFriendRequest]
    let outgoing: [SocialFriendRequest]
    let blocked: [SocialBlockedProfile]
    let pendingWorkoutInviteCount: Int
}

enum SocialFriendCode {
    private static let maximumInputBytes = 64

    static func normalize(_ rawValue: String) -> String? {
        guard rawValue.utf8.prefix(maximumInputBytes + 1).count <= maximumInputBytes else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalValue = value.lowercased()
        if SocialPayloadParser.isValidProfileID(canonicalValue) || isValidShortCode(canonicalValue) {
            return canonicalValue
        }

        let uppercased = value.uppercased()
        guard uppercased.range(
            of: #"^GYM-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return "g_" + uppercased.dropFirst(4).replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func display(_ canonicalValue: String) -> String {
        guard isValidShortCode(canonicalValue) else { return canonicalValue }
        let hex = canonicalValue.dropFirst(2).uppercased()
        return "GYM-\(hex.prefix(4))-\(hex.dropFirst(4).prefix(4))-\(hex.suffix(4))"
    }

    static func isValidCanonical(_ value: String) -> Bool {
        SocialPayloadParser.isValidProfileID(value) || isValidShortCode(value)
    }

    static func isValidShortCode(_ value: String) -> Bool {
        value.range(of: #"^g_[0-9a-f]{12}$"#, options: .regularExpression) != nil
    }
}

struct SocialFriendProfile: Equatable, Sendable {
    let profileID: String
    let displayName: String
    let xp: Int?
    let level: Int?
    let workouts: Int?
    let progressShared: Bool
    let statsAvailable: Bool
    let progressUpdatedAt: String?
}

struct SocialFriendSharing: Equatable, Sendable {
    let progress: Bool
    let recentWorkouts: Bool
    let records: Bool
}

struct SocialExerciseLabel: Equatable, Sendable {
    let catalogKey: String?
    let name: String
}

struct SocialRecentWorkout: Equatable, Sendable {
    let workoutDay: String
    let exerciseCount: Int
    let setCount: Int
    let exercises: [SocialExerciseLabel]
}

struct SocialExerciseRecord: Identifiable, Equatable, Sendable {
    var id: String {
        if let catalogKey { return "catalog:\(catalogKey)" }
        return "custom:\(name.precomposedStringWithCanonicalMapping.lowercased())"
    }

    let catalogKey: String?
    let name: String
    let bestWeightKg: Double
    let bestReps: Int
    let workoutCount: Int
    let lastWorkoutDay: String
}

struct SocialFriendDetails: Equatable, Sendable {
    let friend: SocialFriendProfile
    let sharing: SocialFriendSharing
    let activityUpdatedAt: String?
    let recentWorkouts: [SocialRecentWorkout]
    let exerciseRecords: [SocialExerciseRecord]
}

struct SocialFriendshipMutation: Equatable, Sendable {
    enum Status: String, Sendable {
        case accepted
        case declined
        case removed
    }

    let friendshipID: String
    let status: Status
    let friendshipRevision: Int
}

struct SocialBlockMutation: Equatable, Sendable {
    let profileID: String
    let blocked: Bool
}

enum SocialWorkoutInviteStatus: String, Equatable, Sendable {
    case pending
    case accepted
    case declined
    case cancelled
    case expired
}

struct SocialWorkoutInviteSummary: Equatable, Sendable {
    let exerciseCount: Int
    let setCount: Int
    let exerciseNames: [String]
}

struct SocialWorkoutInvite: Identifiable, Equatable, Sendable {
    var id: String { inviteID }

    let inviteID: String
    let profileID: String
    let displayName: String
    let status: SocialWorkoutInviteStatus
    let inviteRevision: Int
    let createdAt: String
    let expiresAt: String
    let respondedAt: String?
    let summary: SocialWorkoutInviteSummary
    let workout: SharedWorkoutPlan?
}

struct SocialWorkoutInbox: Equatable, Sendable {
    let pendingIncomingCount: Int
    let incoming: [SocialWorkoutInvite]
    let outgoing: [SocialWorkoutInvite]
}

struct SocialWorkoutInviteMutation: Equatable, Sendable {
    let inviteID: String
    let status: SocialWorkoutInviteStatus
    let inviteRevision: Int
    let workout: SharedWorkoutPlan?
}

enum SocialPayloadError: Error, Equatable, Sendable {
    case invalidResponse
}

enum SocialPayloadParser {
    static let maximumResponseBytes = 256 * 1_024
    static let maximumMutationResponseBytes = 32 * 1_024
    static let maximumFriendCodeResponseBytes = 1_024

    private static let maximumFriends = 200
    private static let maximumIncoming = 100
    private static let maximumOutgoing = 25
    private static let maximumBlocked = 200
    private static let maximumRecentWorkouts = 5
    private static let maximumWorkoutExerciseLabels = 20
    private static let maximumExerciseRecords = 100
    private static let maximumRevision = 2_147_483_647

    static func dashboard(from data: Data) throws -> SocialDashboard {
        let root = try object(
            try json(from: data),
            keys: [
                "version", "self", "friends", "incoming", "outgoing", "blocked",
                "pendingWorkoutInviteCount"
            ]
        )
        try version(root["version"])
        let currentUser = try selfProfile(root["self"])
        let friends = try array(root["friends"], maximumCount: maximumFriends).map(friendSummary)
        let incoming = try array(root["incoming"], maximumCount: maximumIncoming).map(friendRequest)
        let outgoing = try array(root["outgoing"], maximumCount: maximumOutgoing).map(friendRequest)
        let blocked = try array(root["blocked"], maximumCount: maximumBlocked).map(blockedProfile)

        guard unique(friends.map(\.friendshipID)),
              unique(friends.map(\.profileID)),
              unique(incoming.map(\.friendshipID)),
              unique(incoming.map(\.profileID)),
              unique(outgoing.map(\.friendshipID)),
              unique(outgoing.map(\.profileID)),
              unique(blocked.map(\.profileID)),
              Set(friends.map(\.friendshipID)).isDisjoint(with: incoming.map(\.friendshipID)),
              Set(friends.map(\.friendshipID)).isDisjoint(with: outgoing.map(\.friendshipID)),
              Set(incoming.map(\.friendshipID)).isDisjoint(with: outgoing.map(\.friendshipID)) else {
            throw SocialPayloadError.invalidResponse
        }

        let relatedProfileIDs = Set(
            friends.map(\.profileID) + incoming.map(\.profileID) + outgoing.map(\.profileID)
        )
        let friendProfileIDs = Set(friends.map(\.profileID))
        let incomingProfileIDs = Set(incoming.map(\.profileID))
        let outgoingProfileIDs = Set(outgoing.map(\.profileID))
        let blockedProfileIDs = Set(blocked.map(\.profileID))
        guard friendProfileIDs.isDisjoint(with: incomingProfileIDs),
              friendProfileIDs.isDisjoint(with: outgoingProfileIDs),
              incomingProfileIDs.isDisjoint(with: outgoingProfileIDs),
              !relatedProfileIDs.contains(currentUser.profileID),
              !blockedProfileIDs.contains(currentUser.profileID),
              relatedProfileIDs.isDisjoint(with: blocked.map(\.profileID)) else {
            throw SocialPayloadError.invalidResponse
        }
        return SocialDashboard(
            currentUser: currentUser,
            friends: friends,
            incoming: incoming,
            outgoing: outgoing,
            blocked: blocked,
            pendingWorkoutInviteCount: try integer(
                root["pendingWorkoutInviteCount"],
                range: 0 ... 25
            )
        )
    }

    static func friendCode(from data: Data) throws -> String {
        guard !data.isEmpty, data.count <= maximumFriendCodeResponseBytes else {
            throw SocialPayloadError.invalidResponse
        }
        let root = try object(
            try json(from: data),
            keys: ["version", "friendCode"]
        )
        try version(root["version"])
        let friendCode = try string(
            root["friendCode"],
            maximumCharacters: 14,
            maximumBytes: 14
        )
        guard SocialFriendCode.isValidShortCode(friendCode) else {
            throw SocialPayloadError.invalidResponse
        }
        return friendCode
    }

    static func friendDetails(from data: Data) throws -> SocialFriendDetails {
        let root = try object(
            try json(from: data),
            keys: [
                "version", "friend", "sharing", "activityUpdatedAt", "recentWorkouts",
                "exerciseRecords", "integrity"
            ]
        )
        try version(root["version"])
        guard try string(root["integrity"], maximumCharacters: 32, maximumBytes: 32) == "self_reported" else {
            throw SocialPayloadError.invalidResponse
        }
        let friend = try friendProfile(root["friend"])
        let sharing = try sharing(root["sharing"])
        let activityUpdatedAt = try optionalTimestamp(root["activityUpdatedAt"])
        let recentWorkouts = try array(
            root["recentWorkouts"],
            maximumCount: maximumRecentWorkouts
        ).map(recentWorkout)
        let exerciseRecords = try array(
            root["exerciseRecords"],
            maximumCount: maximumExerciseRecords
        ).map(exerciseRecord)

        guard friend.progressShared == sharing.progress,
              sharing.recentWorkouts || recentWorkouts.isEmpty,
              sharing.records || exerciseRecords.isEmpty,
              activityUpdatedAt != nil ||
                  (recentWorkouts.isEmpty && exerciseRecords.isEmpty),
              activityUpdatedAt == nil ||
                  sharing.recentWorkouts || sharing.records,
              unique(exerciseRecords.map(\.id)) else {
            throw SocialPayloadError.invalidResponse
        }
        return SocialFriendDetails(
            friend: friend,
            sharing: sharing,
            activityUpdatedAt: activityUpdatedAt,
            recentWorkouts: recentWorkouts,
            exerciseRecords: exerciseRecords
        )
    }

    static func submittedFriendRequest(from data: Data) throws {
        let root = try object(try json(from: data), keys: ["version", "result"])
        try version(root["version"])
        guard try string(root["result"], maximumCharacters: 64, maximumBytes: 64) ==
            "submitted_or_unavailable" else {
            throw SocialPayloadError.invalidResponse
        }
    }

    static func friendshipMutation(from data: Data) throws -> SocialFriendshipMutation {
        let root = try object(
            try json(from: data),
            keys: ["version", "friendshipId", "status", "friendshipRevision"]
        )
        try version(root["version"])
        let rawStatus = try string(root["status"], maximumCharacters: 16, maximumBytes: 16)
        guard let status = SocialFriendshipMutation.Status(rawValue: rawStatus) else {
            throw SocialPayloadError.invalidResponse
        }
        return SocialFriendshipMutation(
            friendshipID: try friendshipID(root["friendshipId"]),
            status: status,
            friendshipRevision: try revision(root["friendshipRevision"])
        )
    }

    static func blockMutation(from data: Data) throws -> SocialBlockMutation {
        let root = try object(
            try json(from: data),
            keys: ["version", "profileId", "blocked"]
        )
        try version(root["version"])
        return SocialBlockMutation(
            profileID: try profileID(root["profileId"]),
            blocked: try boolean(root["blocked"])
        )
    }

    static func privacyMutation(from data: Data) throws -> (SocialPrivacy, Int) {
        let root = try object(
            try json(from: data),
            keys: ["version", "privacy", "settingsRevision"]
        )
        try version(root["version"])
        return (try privacy(root["privacy"]), try revision(root["settingsRevision"]))
    }

    static func workoutInbox(from data: Data) throws -> SocialWorkoutInbox {
        let root = try object(
            try json(from: data),
            keys: ["version", "pendingIncomingCount", "incoming", "outgoing"]
        )
        try version(root["version"])
        let incoming = try array(root["incoming"], maximumCount: 25).map {
            try workoutInvite($0, includesWorkout: true)
        }
        let outgoing = try array(root["outgoing"], maximumCount: 25).map {
            try workoutInvite($0, includesWorkout: false)
        }
        let pendingIncomingCount = try integer(root["pendingIncomingCount"], range: 0 ... 25)
        guard pendingIncomingCount == incoming.filter({ $0.status == .pending }).count,
              unique(incoming.map(\.inviteID)),
              unique(outgoing.map(\.inviteID)),
              Set(incoming.map(\.inviteID)).isDisjoint(with: outgoing.map(\.inviteID)) else {
            throw SocialPayloadError.invalidResponse
        }
        return SocialWorkoutInbox(
            pendingIncomingCount: pendingIncomingCount,
            incoming: incoming,
            outgoing: outgoing
        )
    }

    static func submittedWorkoutInvite(from data: Data) throws {
        try submittedFriendRequest(from: data)
    }

    static func workoutInviteMutation(
        from data: Data,
        permitsWorkout: Bool
    ) throws -> SocialWorkoutInviteMutation {
        let root = try object(
            try json(from: data),
            keys: permitsWorkout
                ? ["version", "inviteId", "status", "inviteRevision", "workout"]
                : ["version", "inviteId", "status", "inviteRevision"]
        )
        try version(root["version"])
        let status = try workoutInviteStatus(root["status"])
        let workout: SharedWorkoutPlan?
        if permitsWorkout {
            if isNull(root["workout"]) {
                workout = nil
            } else {
                workout = try workoutPlan(root["workout"])
            }
            guard (status == .accepted) == (workout != nil),
                  status == .accepted || status == .declined else {
                throw SocialPayloadError.invalidResponse
            }
        } else {
            workout = nil
            guard status == .cancelled else { throw SocialPayloadError.invalidResponse }
        }
        return SocialWorkoutInviteMutation(
            inviteID: try inviteID(root["inviteId"]),
            status: status,
            inviteRevision: try revision(root["inviteRevision"]),
            workout: workout
        )
    }

    static func workoutObject(for plan: SharedWorkoutPlan) throws -> [String: Any] {
        let validated: SharedWorkoutPlan
        do {
            validated = try SharedWorkoutLinkValidator.validate(plan)
        } catch {
            throw SocialPayloadError.invalidResponse
        }
        return try workoutObject(forValidatedPlan: validated)
    }

    private static func workoutObject(
        forValidatedPlan validated: SharedWorkoutPlan
    ) throws -> [String: Any] {
        let exercises: [[String: Any]] = validated.exercises.map { exercise in
            var object: [String: Any] = [
                "name": exercise.name,
                "sets": exercise.sets.map { ["weight": $0.weight, "reps": $0.repetitions] }
            ]
            if let catalogKey = exercise.catalogKey { object["catalogKey"] = catalogKey }
            return object
        }
        let object: [String: Any] = ["version": 1, "exercises": exercises]
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              data.count <= 32 * 1_024 else {
            throw SocialPayloadError.invalidResponse
        }
        return object
    }

    static func isValidProfileID(_ value: String) -> Bool {
        value.range(of: #"^p_[0-9a-f]{32}$"#, options: .regularExpression) != nil
    }

    static func isValidFriendshipID(_ value: String) -> Bool {
        value.range(of: #"^f_[0-9a-f]{32}$"#, options: .regularExpression) != nil
    }

    static func isValidInviteID(_ value: String) -> Bool {
        value.range(of: #"^wi_[0-9a-f]{32}$"#, options: .regularExpression) != nil
    }

    private static func selfProfile(_ value: Any?) throws -> SocialSelfProfile {
        let object = try object(
            value,
            keys: [
                "profileId", "friendCode", "displayName", "xp", "level", "workouts",
                "statsAvailable", "progressUpdatedAt", "privacy", "settingsRevision"
            ]
        )
        let statsAvailable = try boolean(object["statsAvailable"])
        let values = try stats(
            xp: object["xp"],
            level: object["level"],
            workouts: object["workouts"],
            updatedAt: object["progressUpdatedAt"],
            available: statsAvailable
        )
        let parsedProfileID = try profileID(object["profileId"])
        let friendCode = try profileID(object["friendCode"])
        guard parsedProfileID == friendCode else { throw SocialPayloadError.invalidResponse }
        return SocialSelfProfile(
            profileID: parsedProfileID,
            friendCode: friendCode,
            displayName: try displayName(object["displayName"]),
            xp: values.xp,
            level: values.level,
            workouts: values.workouts,
            statsAvailable: statsAvailable,
            progressUpdatedAt: values.updatedAt,
            privacy: try privacy(object["privacy"]),
            settingsRevision: try revision(object["settingsRevision"])
        )
    }

    private static func friendSummary(_ value: Any) throws -> SocialFriendSummary {
        let object = try object(
            value,
            keys: [
                "friendshipId", "profileId", "displayName", "xp", "level", "workouts",
                "progressShared", "statsAvailable", "progressUpdatedAt",
                "friendshipRevision", "status"
            ]
        )
        guard try string(object["status"], maximumCharacters: 16, maximumBytes: 16) == "accepted" else {
            throw SocialPayloadError.invalidResponse
        }
        let progressShared = try boolean(object["progressShared"])
        let statsAvailable = try boolean(object["statsAvailable"])
        guard progressShared || !statsAvailable else { throw SocialPayloadError.invalidResponse }
        let values = try stats(
            xp: object["xp"],
            level: object["level"],
            workouts: object["workouts"],
            updatedAt: object["progressUpdatedAt"],
            available: statsAvailable
        )
        return SocialFriendSummary(
            friendshipID: try friendshipID(object["friendshipId"]),
            profileID: try profileID(object["profileId"]),
            displayName: try displayName(object["displayName"]),
            xp: values.xp,
            level: values.level,
            workouts: values.workouts,
            progressShared: progressShared,
            statsAvailable: statsAvailable,
            progressUpdatedAt: values.updatedAt,
            friendshipRevision: try revision(object["friendshipRevision"])
        )
    }

    private static func friendRequest(_ value: Any) throws -> SocialFriendRequest {
        let object = try object(
            value,
            keys: [
                "friendshipId", "profileId", "displayName", "requestedAt",
                "friendshipRevision", "status"
            ]
        )
        guard try string(object["status"], maximumCharacters: 16, maximumBytes: 16) == "pending" else {
            throw SocialPayloadError.invalidResponse
        }
        return SocialFriendRequest(
            friendshipID: try friendshipID(object["friendshipId"]),
            profileID: try profileID(object["profileId"]),
            displayName: try displayName(object["displayName"]),
            requestedAt: try timestamp(object["requestedAt"]),
            friendshipRevision: try revision(object["friendshipRevision"])
        )
    }

    private static func blockedProfile(_ value: Any) throws -> SocialBlockedProfile {
        let object = try object(
            value,
            keys: ["profileId", "displayName", "blockedAt"]
        )
        return SocialBlockedProfile(
            profileID: try profileID(object["profileId"]),
            displayName: try displayName(object["displayName"]),
            blockedAt: try timestamp(object["blockedAt"])
        )
    }

    private static func friendProfile(_ value: Any?) throws -> SocialFriendProfile {
        let object = try object(
            value,
            keys: [
                "profileId", "displayName", "xp", "level", "workouts", "progressShared",
                "statsAvailable", "progressUpdatedAt"
            ]
        )
        let progressShared = try boolean(object["progressShared"])
        let statsAvailable = try boolean(object["statsAvailable"])
        guard progressShared || !statsAvailable else { throw SocialPayloadError.invalidResponse }
        let values = try stats(
            xp: object["xp"],
            level: object["level"],
            workouts: object["workouts"],
            updatedAt: object["progressUpdatedAt"],
            available: statsAvailable
        )
        return SocialFriendProfile(
            profileID: try profileID(object["profileId"]),
            displayName: try displayName(object["displayName"]),
            xp: values.xp,
            level: values.level,
            workouts: values.workouts,
            progressShared: progressShared,
            statsAvailable: statsAvailable,
            progressUpdatedAt: values.updatedAt
        )
    }

    private static func sharing(_ value: Any?) throws -> SocialFriendSharing {
        let object = try object(value, keys: ["progress", "recentWorkouts", "records"])
        return SocialFriendSharing(
            progress: try boolean(object["progress"]),
            recentWorkouts: try boolean(object["recentWorkouts"]),
            records: try boolean(object["records"])
        )
    }

    private static func recentWorkout(_ value: Any) throws -> SocialRecentWorkout {
        let object = try object(
            value,
            keys: ["workoutDay", "exerciseCount", "setCount", "exercises"]
        )
        let exerciseCount = try integer(object["exerciseCount"], range: 1 ... 100)
        let exercises = try array(
            object["exercises"],
            maximumCount: maximumWorkoutExerciseLabels
        ).map(exerciseLabel)
        guard exercises.count == min(exerciseCount, maximumWorkoutExerciseLabels),
              unique(exercises.map(exerciseIdentity)) else {
            throw SocialPayloadError.invalidResponse
        }
        return SocialRecentWorkout(
            workoutDay: try day(object["workoutDay"]),
            exerciseCount: exerciseCount,
            setCount: try integer(object["setCount"], range: 1 ... 10_000),
            exercises: exercises
        )
    }

    private static func exerciseLabel(_ value: Any) throws -> SocialExerciseLabel {
        let object = try object(value, keys: ["catalogKey", "name"])
        return SocialExerciseLabel(
            catalogKey: try optionalCatalogKey(object["catalogKey"]),
            name: try exerciseName(object["name"])
        )
    }

    private static func exerciseRecord(_ value: Any) throws -> SocialExerciseRecord {
        let object = try object(
            value,
            keys: [
                "catalogKey", "name", "bestWeightKg", "bestReps", "workoutCount",
                "lastWorkoutDay"
            ]
        )
        return SocialExerciseRecord(
            catalogKey: try optionalCatalogKey(object["catalogKey"]),
            name: try exerciseName(object["name"]),
            bestWeightKg: try finiteNumber(object["bestWeightKg"], range: 0 ... 1_000_000),
            bestReps: try integer(object["bestReps"], range: 1 ... 10_000),
            workoutCount: try integer(object["workoutCount"], range: 1 ... 5_000),
            lastWorkoutDay: try day(object["lastWorkoutDay"])
        )
    }

    private static func workoutInvite(
        _ value: Any,
        includesWorkout: Bool
    ) throws -> SocialWorkoutInvite {
        let root = try object(
            value,
            keys: includesWorkout
                ? [
                    "inviteId", "profileId", "displayName", "status", "inviteRevision",
                    "createdAt", "expiresAt", "respondedAt", "summary", "workout"
                ]
                : [
                    "inviteId", "profileId", "displayName", "status", "inviteRevision",
                    "createdAt", "expiresAt", "respondedAt", "summary"
                ]
        )
        let createdAt = try timestamp(root["createdAt"])
        let expiresAt = try timestamp(root["expiresAt"])
        guard let createdDate = parseTimestamp(createdAt),
              let expiresDate = parseTimestamp(expiresAt),
              expiresDate > createdDate else {
            throw SocialPayloadError.invalidResponse
        }
        let summary = try workoutInviteSummary(root["summary"])
        let workout = includesWorkout ? try workoutPlan(root["workout"]) : nil
        let status = try workoutInviteStatus(root["status"])
        let respondedAt = try optionalTimestamp(root["respondedAt"])
        guard !includesWorkout || status == .pending || status == .accepted else {
            throw SocialPayloadError.invalidResponse
        }
        guard (status == .pending) == (respondedAt == nil) else {
            throw SocialPayloadError.invalidResponse
        }
        if let workout {
            guard summary.exerciseCount == workout.exercises.count,
                  summary.setCount == workout.totalSetCount,
                  summary.exerciseNames == workout.exercises.map(\.name) else {
                throw SocialPayloadError.invalidResponse
            }
        }
        return SocialWorkoutInvite(
            inviteID: try inviteID(root["inviteId"]),
            profileID: try profileID(root["profileId"]),
            displayName: try displayName(root["displayName"]),
            status: status,
            inviteRevision: try revision(root["inviteRevision"]),
            createdAt: createdAt,
            expiresAt: expiresAt,
            respondedAt: respondedAt,
            summary: summary,
            workout: workout
        )
    }

    private static func workoutInviteSummary(_ value: Any?) throws -> SocialWorkoutInviteSummary {
        let object = try object(value, keys: ["exerciseCount", "setCount", "exerciseNames"])
        let exerciseCount = try integer(object["exerciseCount"], range: 1 ... 20)
        let exerciseNames = try array(object["exerciseNames"], maximumCount: 20).map(exerciseName)
        let portableNames = exerciseNames.map(portableSocialExerciseName)
        guard exerciseNames.count == exerciseCount,
              !portableNames.contains(where: \.isEmpty),
              unique(portableNames) else {
            throw SocialPayloadError.invalidResponse
        }
        return SocialWorkoutInviteSummary(
            exerciseCount: exerciseCount,
            setCount: try integer(object["setCount"], range: exerciseCount ... 120),
            exerciseNames: exerciseNames
        )
    }

    private static func workoutPlan(_ value: Any?) throws -> SharedWorkoutPlan {
        let root = try object(value, keys: ["version", "exercises"])
        try version(root["version"])
        let rawExercises = try array(root["exercises"], maximumCount: 20)
        guard !rawExercises.isEmpty else { throw SocialPayloadError.invalidResponse }
        var totalSetCount = 0
        var portableNames = Set<String>()
        var catalogKeys = Set<String>()
        let exercises = try rawExercises.map { raw -> SharedWorkoutPlanExercise in
            let exercise = try object(
                raw,
                requiredKeys: ["name", "sets"],
                optionalKeys: ["catalogKey"]
            )
            let sets = try array(exercise["sets"], maximumCount: 12).map { rawSet in
                let set = try object(rawSet, keys: ["weight", "reps"])
                return SharedWorkoutPlanSet(
                    weight: try finiteNumber(set["weight"], range: 0 ... 1_000_000),
                    repetitions: try integer(set["reps"], range: 1 ... 10_000)
                )
            }
            guard !sets.isEmpty else { throw SocialPayloadError.invalidResponse }
            totalSetCount += sets.count
            guard totalSetCount <= 120 else { throw SocialPayloadError.invalidResponse }
            let name = try exerciseName(exercise["name"])
            let portableName = portableSocialExerciseName(name)
            guard !portableName.isEmpty,
                  portableNames.insert(portableName).inserted else {
                throw SocialPayloadError.invalidResponse
            }
            let catalogKey = try optionalCatalogKey(exercise["catalogKey"])
            if let catalogKey,
               !catalogKeys.insert(catalogKey).inserted {
                throw SocialPayloadError.invalidResponse
            }
            return SharedWorkoutPlanExercise(
                catalogKey: catalogKey,
                name: name,
                sets: sets
            )
        }
        let plan = SharedWorkoutPlan(exercises: exercises)
        do {
            // Social payloads use server-portable name and explicit-key uniqueness. Do not
            // infer local built-in aliases here: two distinct no-key names can both map to
            // one catalog exercise on this device and must remain readable in the inbox.
            // The generic shared-link validator remains the local import boundary.
            _ = try workoutObject(forValidatedPlan: plan)
            return plan
        } catch {
            throw SocialPayloadError.invalidResponse
        }
    }

    private static func stats(
        xp: Any?,
        level: Any?,
        workouts: Any?,
        updatedAt: Any?,
        available: Bool
    ) throws -> (xp: Int?, level: Int?, workouts: Int?, updatedAt: String?) {
        if !available {
            guard isNull(xp), isNull(level), isNull(workouts), isNull(updatedAt) else {
                throw SocialPayloadError.invalidResponse
            }
            return (nil, nil, nil, nil)
        }
        guard !isNull(xp), !isNull(level), !isNull(workouts), !isNull(updatedAt) else {
            throw SocialPayloadError.invalidResponse
        }
        return (
            try integer(xp, range: 0 ... maximumRevision),
            try integer(level, range: 1 ... 1_000_000),
            try integer(workouts, range: 0 ... 5_000),
            try timestamp(updatedAt)
        )
    }

    private static func privacy(_ value: Any?) throws -> SocialPrivacy {
        let object = try object(
            value,
            keys: ["allowRequests", "shareProgress", "shareRecentWorkouts", "shareRecords"]
        )
        return SocialPrivacy(
            allowRequests: try boolean(object["allowRequests"]),
            shareProgress: try boolean(object["shareProgress"]),
            shareRecentWorkouts: try boolean(object["shareRecentWorkouts"]),
            shareRecords: try boolean(object["shareRecords"])
        )
    }

    private static func json(from data: Data) throws -> Any {
        guard !data.isEmpty, data.count <= maximumResponseBytes else {
            throw SocialPayloadError.invalidResponse
        }
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw SocialPayloadError.invalidResponse
        }
    }

    private static func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any], Set(object.keys) == keys else {
            throw SocialPayloadError.invalidResponse
        }
        return object
    }

    private static func object(
        _ value: Any?,
        requiredKeys: Set<String>,
        optionalKeys: Set<String>
    ) throws -> [String: Any] {
        guard let object = value as? [String: Any],
              requiredKeys.isSubset(of: object.keys),
              Set(object.keys).isSubset(of: requiredKeys.union(optionalKeys)) else {
            throw SocialPayloadError.invalidResponse
        }
        return object
    }

    private static func array(_ value: Any?, maximumCount: Int) throws -> [Any] {
        guard let array = value as? [Any], array.count <= maximumCount else {
            throw SocialPayloadError.invalidResponse
        }
        return array
    }

    private static func version(_ value: Any?) throws {
        guard try integer(value, range: 1 ... 1) == 1 else {
            throw SocialPayloadError.invalidResponse
        }
    }

    private static func profileID(_ value: Any?) throws -> String {
        let value = try string(value, maximumCharacters: 34, maximumBytes: 34)
        guard isValidProfileID(value) else { throw SocialPayloadError.invalidResponse }
        return value
    }

    private static func friendshipID(_ value: Any?) throws -> String {
        let value = try string(value, maximumCharacters: 34, maximumBytes: 34)
        guard isValidFriendshipID(value) else { throw SocialPayloadError.invalidResponse }
        return value
    }

    private static func inviteID(_ value: Any?) throws -> String {
        let value = try string(value, maximumCharacters: 35, maximumBytes: 35)
        guard isValidInviteID(value) else { throw SocialPayloadError.invalidResponse }
        return value
    }

    private static func workoutInviteStatus(_ value: Any?) throws -> SocialWorkoutInviteStatus {
        let value = try string(value, maximumCharacters: 16, maximumBytes: 16)
        guard let status = SocialWorkoutInviteStatus(rawValue: value) else {
            throw SocialPayloadError.invalidResponse
        }
        return status
    }

    private static func displayName(_ value: Any?) throws -> String {
        try safeText(value, maximumCharacters: 40, maximumBytes: 160)
    }

    private static func exerciseName(_ value: Any?) throws -> String {
        try safeText(
            value,
            maximumCharacters: SharedWorkoutLinkEncoder.maximumExerciseNameCharacters,
            maximumBytes: SharedWorkoutLinkEncoder.maximumExerciseNameBytes
        ).precomposedStringWithCanonicalMapping
    }

    private static func optionalCatalogKey(_ value: Any?) throws -> String? {
        if isNull(value) { return nil }
        let value = try string(
            value,
            maximumCharacters: SharedWorkoutLinkEncoder.maximumCatalogKeyCharacters,
            maximumBytes: SharedWorkoutLinkEncoder.maximumCatalogKeyCharacters
        )
        guard !value.isEmpty,
              value.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil else {
            throw SocialPayloadError.invalidResponse
        }
        return value
    }

    private static func revision(_ value: Any?) throws -> Int {
        try integer(value, range: 1 ... maximumRevision)
    }

    private static func boolean(_ value: Any?) throws -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw SocialPayloadError.invalidResponse
        }
        return number.boolValue
    }

    private static func integer(_ value: Any?, range: ClosedRange<Int>) throws -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= Double(range.lowerBound),
              number.doubleValue <= Double(range.upperBound) else {
            throw SocialPayloadError.invalidResponse
        }
        return number.intValue
    }

    private static func finiteNumber(
        _ value: Any?,
        range: ClosedRange<Double>
    ) throws -> Double {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              range.contains(number.doubleValue) else {
            throw SocialPayloadError.invalidResponse
        }
        return number.doubleValue
    }

    private static func string(
        _ value: Any?,
        maximumCharacters: Int,
        maximumBytes: Int
    ) throws -> String {
        guard let value = value as? String,
              value.unicodeScalars.count <= maximumCharacters,
              value.utf8.count <= maximumBytes else {
            throw SocialPayloadError.invalidResponse
        }
        return value
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
              value.unicodeScalars.first?.value != 0x20,
              value.unicodeScalars.last?.value != 0x20,
              !value.unicodeScalars.contains(where: { scalar in
                  switch scalar.properties.generalCategory {
                  case .control, .format, .lineSeparator, .paragraphSeparator:
                      return true
                  default:
                      return false
                  }
              }) else {
            throw SocialPayloadError.invalidResponse
        }
        return value
    }

    private static func portableSocialExerciseName(_ value: String) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        var collapsed = ""
        var pendingSpace = false
        for scalar in normalized.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !collapsed.isEmpty { pendingSpace = true }
                continue
            }
            if pendingSpace {
                collapsed.append(" ")
                pendingSpace = false
            }
            collapsed.unicodeScalars.append(scalar)
        }
        return collapsed
            .lowercased()
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "ё", with: "е")
    }

    private static func timestamp(_ value: Any?) throws -> String {
        let value = try string(value, maximumCharacters: 40, maximumBytes: 40)
        guard parseTimestamp(value) != nil else { throw SocialPayloadError.invalidResponse }
        return value
    }

    private static func optionalTimestamp(_ value: Any?) throws -> String? {
        isNull(value) ? nil : try timestamp(value)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func day(_ value: Any?) throws -> String {
        let value = try string(value, maximumCharacters: 10, maximumBytes: 10)
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw SocialPayloadError.invalidResponse
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let parsed = formatter.date(from: value), formatter.string(from: parsed) == value else {
            throw SocialPayloadError.invalidResponse
        }
        return value
    }

    private static func exerciseIdentity(_ value: SocialExerciseLabel) -> String {
        if let catalogKey = value.catalogKey { return "catalog:\(catalogKey)" }
        return "custom:\(value.name.precomposedStringWithCanonicalMapping.lowercased())"
    }

    private static func unique<S: Sequence>(_ values: S) -> Bool where S.Element: Hashable {
        var seen = Set<S.Element>()
        return values.allSatisfy { seen.insert($0).inserted }
    }

    private static func isNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }
}
