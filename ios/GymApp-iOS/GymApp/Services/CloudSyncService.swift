import Foundation

enum CloudSyncError: LocalizedError {
    case invalidPayload
    case invalidSocialProfile
    case invalidFriendship
    case invalidWorkoutInvite
    case invalidResponse
    case staleRemoteState
    case postgRESTFailure(statusCode: Int, code: String, message: String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "The local backup is not valid JSON."
        case .invalidSocialProfile: return "This social profile is no longer available."
        case .invalidFriendship: return "This friend request is no longer available."
        case .invalidWorkoutInvite: return "This workout invitation is no longer available."
        case .invalidResponse: return "The cloud returned an invalid response."
        case .staleRemoteState:
            return "Cloud data changed on another device. Reload it before syncing again."
        case .postgRESTFailure(_, _, let message): return message
        case .requestFailed(let message): return message
        }
    }
}

@MainActor
final class CloudSyncService: ObservableObject {
    private enum RequestFailure: Error {
        case http(statusCode: Int, code: String?, message: String)
    }

    private enum StateRevision {
        case unknown
        case missing(userID: String)
        case loaded(userID: String, updatedAt: String)
    }

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    private let auth: AuthService
    private let urlSession: URLSession
    private var stateRevision: StateRevision = .unknown
    private var operationRevision: UInt64 = 0

    private static let maximumCloudStateBytes = BackupImportLimits.standard.maximumFileBytes
    private static let maximumCloudStateResponseBytes = 10 * 1_024 * 1_024
    private static let maximumCloudResponseBytes = 256 * 1_024
    private static let maximumCloudErrorResponseBytes = 8 * 1_024
    private static let maximumCloudRequestBytes = 10 * 1_024 * 1_024
    private static let maximumTokenBytes = 16 * 1_024

    init(auth: AuthService, urlSession: URLSession = .shared) {
        self.auth = auth
        self.urlSession = urlSession
    }

    func resetForAccountTransition() {
        operationRevision &+= 1
        stateRevision = .unknown
        lastSyncedAt = nil
        lastError = nil
    }

    func loadRemoteState(expectedUserID: String? = nil) async throws -> Data? {
        operationRevision &+= 1
        let expectedOperation = operationRevision
        let session = try await auth.validCloudSession(expectedUserID: expectedUserID)
        let userID = expectedUserID ?? session.userID
        guard session.userID == userID else { throw AuthServiceError.sessionChanged }
        stateRevision = .unknown
        let path = "/rest/v1/user_states?select=state,updated_at&user_id=eq.\(Self.queryValue(userID))&limit=1"
        let data = try await request(
            path: path,
            method: "GET",
            expectedUserID: userID,
            maximumResponseBytes: Self.maximumCloudStateResponseBytes
        )
        guard operationRevision == expectedOperation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CloudSyncError.invalidResponse
        }
        guard let row = rows.first else {
            stateRevision = .missing(userID: userID)
            return nil
        }
        guard let state = row["state"],
              let updatedAt = (row["updated_at"] as? String)?.nonEmpty else {
            throw CloudSyncError.invalidResponse
        }
        stateRevision = .loaded(userID: userID, updatedAt: updatedAt)
        return try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    }

    func saveRemoteState(
        backupData: Data,
        xp: Int,
        level: Int,
        workouts: Int,
        workoutDurations: [[String: Any]] = [],
        expectedUserID: String? = nil
    ) async throws {
        guard backupData.count <= Self.maximumCloudStateBytes else {
            throw CloudSyncError.invalidPayload
        }
        guard let state = try JSONSerialization.jsonObject(with: backupData) as? [String: Any] else {
            throw CloudSyncError.invalidPayload
        }
        let expectedOperation = operationRevision
        let session = try await auth.validCloudSession(expectedUserID: expectedUserID)
        let userID = expectedUserID ?? session.userID
        guard session.userID == userID,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        let priorRevision: String?
        switch stateRevision {
        case .loaded(let revisionUserID, let updatedAt) where revisionUserID == userID:
            priorRevision = updatedAt
        case .missing(let revisionUserID) where revisionUserID == userID:
            priorRevision = nil
        default:
            throw CloudSyncError.staleRemoteState
        }
        let timestamp = Self.nextRevisionTimestamp(after: priorRevision)

        let revisionData: Data
        if let priorRevision {
            revisionData = try await request(
                path: "/rest/v1/user_states?user_id=eq.\(Self.queryValue(userID))&updated_at=eq.\(Self.queryValue(priorRevision))&select=updated_at",
                method: "PATCH",
                expectedUserID: userID,
                prefer: "return=representation",
                body: ["state": state, "updated_at": timestamp]
            )
        } else {
            revisionData = try await request(
                path: "/rest/v1/user_states?select=updated_at",
                method: "POST",
                expectedUserID: userID,
                prefer: "return=representation",
                conflictMeansStaleState: true,
                body: [[
                    "user_id": userID,
                    "state": state,
                    "updated_at": timestamp
                ]]
            )
        }

        guard let storedRevision = Self.singleUpdatedAt(in: revisionData) else {
            throw CloudSyncError.staleRemoteState
        }
        guard operationRevision == expectedOperation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        stateRevision = .loaded(userID: userID, updatedAt: storedRevision)

        let profileBody: [[String: Any]] = [[
            "user_id": userID,
            "display_name": session.displayName,
            "xp": max(0, xp),
            "level": max(1, level),
            "workouts": max(0, workouts),
            "updated_at": timestamp
        ]]
        _ = try await request(
            path: "/rest/v1/profiles?on_conflict=user_id",
            method: "POST",
            expectedUserID: userID,
            prefer: "resolution=merge-duplicates,return=minimal",
            body: profileBody
        )
        guard operationRevision == expectedOperation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }

        do {
            let durationData = try await request(
                path: "/rest/v1/rpc/social_sync_workout_durations",
                method: "POST",
                expectedUserID: userID,
                body: ["p_items": workoutDurations]
            )
            guard let result = try JSONSerialization.jsonObject(with: durationData) as? [String: Any],
                  Set(result.keys) == ["version", "syncedCount"],
                  (result["version"] as? NSNumber)?.intValue == 1,
                  (result["syncedCount"] as? NSNumber)?.intValue == workoutDurations.count else {
                throw CloudSyncError.invalidResponse
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The core row and public profile are already committed. Duration is an
            // optional forward-compatible sidecar, so a transient RPC failure must not
            // turn that successful write into a stale-revision retry loop.
        }
        guard operationRevision == expectedOperation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        lastSyncedAt = Date()
        lastError = nil
    }

    func socialDashboard(expectedUserID: String? = nil) async throws -> SocialDashboard {
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_dashboard",
            expectedUserID: expectedUserID,
            body: [:],
            maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
        )
        do {
            return try SocialPayloadParser.dashboard(from: data)
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialMyFriendCode(expectedUserID: String? = nil) async throws -> String {
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_my_friend_code",
            expectedUserID: expectedUserID,
            body: [:],
            maximumResponseBytes: SocialPayloadParser.maximumFriendCodeResponseBytes
        )
        do {
            return try SocialPayloadParser.friendCode(from: data)
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialFriendDetails(
        profileID: String,
        expectedUserID: String? = nil
    ) async throws -> SocialFriendDetails {
        guard SocialPayloadParser.isValidProfileID(profileID) else {
            throw CloudSyncError.invalidSocialProfile
        }
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_friend_details",
            expectedUserID: expectedUserID,
            body: ["p_profile_id": profileID],
            maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
        )
        do {
            let details = try SocialPayloadParser.friendDetails(from: data)
            guard details.friend.profileID == profileID else {
                throw SocialPayloadError.invalidResponse
            }
            return details
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialFriendWorkoutPage(
        profileID: String,
        expectedActivityRevision: String? = nil,
        expectedUserID: String? = nil
    ) async throws -> SocialFriendWorkoutPage? {
        guard SocialPayloadParser.isValidProfileID(profileID),
              expectedActivityRevision == nil || Self.isValidSocialTimestamp(expectedActivityRevision)
        else {
            throw CloudSyncError.invalidSocialProfile
        }
        var body: [String: Any] = [
            "p_profile_id": profileID,
            "p_cursor": NSNull(),
            "p_limit": 5
        ]
        if let expectedActivityRevision {
            body["p_expected_activity_revision"] = expectedActivityRevision
        }
        do {
            let (data, _) = try await socialRequest(
                path: "/rest/v1/rpc/social_friend_workout_page",
                expectedUserID: expectedUserID,
                body: body,
                maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
            )
            let page = try SocialPayloadParser.friendWorkoutPage(from: data)
            guard page.profileID == profileID,
                  expectedActivityRevision == nil ||
                    page.activityRevision == expectedActivityRevision else {
                throw SocialPayloadError.invalidResponse
            }
            return page
        } catch CloudSyncError.postgRESTFailure(_, let code, _)
                    where ["P0002", "PGRST202", "42883"].contains(code) {
            return nil
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialFriendWorkoutDetailCapability(
        profileID: String,
        expectedUserID: String? = nil
    ) async throws -> SocialFriendWorkoutDetailCapability {
        guard SocialPayloadParser.isValidProfileID(profileID) else {
            throw CloudSyncError.invalidSocialProfile
        }
        do {
            let (data, _) = try await socialRequest(
                path: "/rest/v1/rpc/social_friend_workout_detail_capability",
                expectedUserID: expectedUserID,
                body: ["p_profile_id": profileID],
                maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
            )
            return try SocialPayloadParser.friendWorkoutDetailCapability(from: data)
        } catch CloudSyncError.postgRESTFailure(let status, let code, _)
                    where status == 404 && ["PGRST202", "42883"].contains(code) {
            return SocialFriendWorkoutDetailCapability(available: false)
        }
    }

    func socialWorkoutDetailPrivacy(
        expectedUserID: String? = nil
    ) async throws -> SocialWorkoutDetailPrivacy {
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_workout_detail_privacy",
            expectedUserID: expectedUserID,
            body: [:],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        return try SocialPayloadParser.workoutDetailPrivacy(from: data)
    }

    func socialUpdateWorkoutDetailPrivacy(
        _ enabled: Bool,
        expectedRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> SocialWorkoutDetailPrivacy {
        guard (1 ... 2_147_483_647).contains(expectedRevision) else {
            throw CloudSyncError.invalidResponse
        }
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_update_workout_detail_privacy",
            expectedUserID: expectedUserID,
            body: [
                "p_share_workout_details": enabled,
                "p_expected_revision": expectedRevision
            ],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        let result = try SocialPayloadParser.workoutDetailPrivacy(from: data)
        guard result.shareWorkoutDetails == enabled else {
            throw CloudSyncError.invalidResponse
        }
        return result
    }

    func socialSendFriendRequest(
        friendCode: String,
        expectedUserID: String? = nil
    ) async throws {
        guard SocialFriendCode.isValidCanonical(friendCode) else {
            throw CloudSyncError.invalidSocialProfile
        }
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_send_friend_request",
            expectedUserID: expectedUserID,
            body: ["p_friend_code": friendCode],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            try SocialPayloadParser.submittedFriendRequest(from: data)
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialRespondFriendRequest(
        friendshipID: String,
        decision: String,
        expectedRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> SocialFriendshipMutation {
        guard SocialPayloadParser.isValidFriendshipID(friendshipID),
              ["accept", "decline"].contains(decision),
              (1 ... 2_147_483_647).contains(expectedRevision) else {
            throw CloudSyncError.invalidFriendship
        }
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_respond_friend_request",
            expectedUserID: expectedUserID,
            body: [
                "p_friendship_id": friendshipID,
                "p_decision": decision,
                "p_expected_revision": expectedRevision
            ],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            let result = try SocialPayloadParser.friendshipMutation(from: data)
            let expectedStatus: SocialFriendshipMutation.Status =
                decision == "accept" ? .accepted : .declined
            guard result.friendshipID == friendshipID,
                  result.status == expectedStatus else {
                throw SocialPayloadError.invalidResponse
            }
            return result
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialCancelFriendRequest(
        friendshipID: String,
        expectedRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> SocialFriendshipMutation {
        try await socialFriendshipRemovalRPC(
            path: "/rest/v1/rpc/social_cancel_friend_request",
            friendshipID: friendshipID,
            expectedRevision: expectedRevision,
            expectedUserID: expectedUserID
        )
    }

    func socialRemoveFriend(
        friendshipID: String,
        expectedRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> SocialFriendshipMutation {
        try await socialFriendshipRemovalRPC(
            path: "/rest/v1/rpc/social_remove_friend",
            friendshipID: friendshipID,
            expectedRevision: expectedRevision,
            expectedUserID: expectedUserID
        )
    }

    func socialBlockProfile(
        profileID: String,
        expectedUserID: String? = nil
    ) async throws -> SocialBlockMutation {
        try await socialBlockRPC(
            path: "/rest/v1/rpc/social_block_profile",
            profileID: profileID,
            expectedUserID: expectedUserID
        )
    }

    func socialUnblockProfile(
        profileID: String,
        expectedUserID: String? = nil
    ) async throws -> SocialBlockMutation {
        try await socialBlockRPC(
            path: "/rest/v1/rpc/social_unblock_profile",
            profileID: profileID,
            expectedUserID: expectedUserID
        )
    }

    func socialUpdatePrivacy(
        _ privacy: SocialPrivacy,
        expectedRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> (SocialPrivacy, Int) {
        guard (1 ... 2_147_483_647).contains(expectedRevision) else {
            throw CloudSyncError.invalidResponse
        }
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_update_privacy",
            expectedUserID: expectedUserID,
            body: [
                "p_allow_requests": privacy.allowRequests,
                "p_share_progress": privacy.shareProgress,
                "p_share_recent_workouts": privacy.shareRecentWorkouts,
                "p_share_records": privacy.shareRecords,
                "p_expected_revision": expectedRevision
            ],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            return try SocialPayloadParser.privacyMutation(from: data)
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialWorkoutInbox(expectedUserID: String? = nil) async throws -> SocialWorkoutInbox {
        try await socialWorkoutInboxPage(
            after: nil,
            limit: SocialPayloadParser.workoutInboxPageLimit,
            permitsLegacyFallback: true,
            expectedUserID: expectedUserID
        )
    }

    func socialWorkoutInboxPage(
        after cursor: SocialWorkoutInboxCursor,
        limit: Int = SocialPayloadParser.workoutInboxPageLimit,
        expectedUserID: String? = nil
    ) async throws -> SocialWorkoutInbox {
        guard SocialPayloadParser.isValidWorkoutInboxCursor(cursor),
              (1 ... SocialPayloadParser.workoutInboxPageLimit).contains(limit) else {
            throw CloudSyncError.invalidResponse
        }
        return try await socialWorkoutInboxPage(
            after: cursor,
            limit: limit,
            permitsLegacyFallback: false,
            expectedUserID: expectedUserID
        )
    }

    private func socialWorkoutInboxPage(
        after cursor: SocialWorkoutInboxCursor?,
        limit: Int,
        permitsLegacyFallback: Bool,
        expectedUserID: String?
    ) async throws -> SocialWorkoutInbox {
        guard (1 ... SocialPayloadParser.workoutInboxPageLimit).contains(limit) else {
            throw CloudSyncError.invalidResponse
        }
        let data: Data
        do {
            var body: [String: Any] = [
                "p_cursor_created_at": NSNull(),
                "p_cursor_invite_id": NSNull(),
                "p_cursor_pending": NSNull(),
                "p_limit": limit
            ]
            if let cursor {
                body["p_cursor_created_at"] = cursor.createdAt
                body["p_cursor_invite_id"] = cursor.inviteID
                body["p_cursor_pending"] = cursor.pending
            }
            (data, _) = try await socialRequest(
                path: "/rest/v1/rpc/social_workout_inbox_page",
                expectedUserID: expectedUserID,
                body: body,
                maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
            )
        } catch let error where Self.isMissingSocialRPC(error) {
            // Compatibility for installations that have not received the bounded
            // metadata/detail RPC pair yet. Only a confirmed missing-function result
            // may fall back; authorization, validation, and transient failures remain
            // observable instead of silently changing the trust boundary.
            guard permitsLegacyFallback, cursor == nil else {
                throw CloudSyncError.invalidResponse
            }
            let (data, _) = try await socialRequest(
                path: "/rest/v1/rpc/social_workout_inbox",
                expectedUserID: expectedUserID,
                body: [:],
                maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
            )
            do {
                return try SocialPayloadParser.workoutInbox(from: data)
            } catch {
                throw CloudSyncError.invalidResponse
            }
        }
        do {
            return try SocialPayloadParser.workoutInboxPage(
                from: data,
                expectedLimit: limit
            )
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialWorkoutInvitePlan(
        inviteID: String,
        expectedRevision: Int,
        legacyWorkout: SharedWorkoutPlan?,
        expectedUserID: String? = nil
    ) async throws -> SharedWorkoutPlan {
        guard SocialPayloadParser.isValidInviteID(inviteID),
              (1 ... 2_147_483_647).contains(expectedRevision) else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        do {
            let (data, _) = try await socialRequest(
                path: "/rest/v1/rpc/social_workout_invite_plan",
                expectedUserID: expectedUserID,
                body: [
                    "p_invite_id": inviteID,
                    "p_expected_revision": expectedRevision
                ],
                maximumResponseBytes: SocialPayloadParser.maximumWorkoutPlanResponseBytes
            )
            let result = try SocialPayloadParser.workoutInvitePlan(from: data)
            guard result.inviteID == inviteID,
                  result.inviteRevision == expectedRevision else {
                throw SocialPayloadError.invalidResponse
            }
            return result.workout
        } catch let error where Self.isMissingSocialRPC(error) {
            // An embedded workout can only originate from the strictly parsed legacy
            // inbox. A metadata-only v2 invite has no fallback and fails generically.
            guard let legacyWorkout else { throw CloudSyncError.invalidWorkoutInvite }
            do {
                return try SharedWorkoutLinkValidator.validate(legacyWorkout)
            } catch {
                throw CloudSyncError.invalidWorkoutInvite
            }
        } catch CloudSyncError.postgRESTFailure(_, let code, _)
                    where code == "P0001" || code == "P0002" || code == "22023" {
            throw CloudSyncError.invalidWorkoutInvite
        } catch is SocialPayloadError {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialSendWorkoutInvite(
        profileID: String,
        clientRequestID: UUID,
        workout: SharedWorkoutPlan,
        expectedUserID: String? = nil
    ) async throws {
        guard SocialPayloadParser.isValidProfileID(profileID) else {
            throw CloudSyncError.invalidSocialProfile
        }
        let workoutObject: [String: Any]
        do {
            workoutObject = try SocialPayloadParser.workoutObject(for: workout)
        } catch {
            throw CloudSyncError.invalidPayload
        }
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_send_workout_invite",
            expectedUserID: expectedUserID,
            body: [
                "p_profile_id": profileID,
                "p_client_request_id": clientRequestID.uuidString.lowercased(),
                "p_workout": workoutObject
            ],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            try SocialPayloadParser.submittedWorkoutInvite(from: data)
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialRespondWorkoutInvite(
        inviteID: String,
        decision: String,
        expectedRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> SocialWorkoutInviteMutation {
        guard SocialPayloadParser.isValidInviteID(inviteID),
              ["accept", "decline"].contains(decision),
              (1 ... 2_147_483_647).contains(expectedRevision) else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_respond_workout_invite",
            expectedUserID: expectedUserID,
            body: [
                "p_invite_id": inviteID,
                "p_decision": decision,
                "p_expected_revision": expectedRevision
            ],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            let result = try SocialPayloadParser.workoutInviteMutation(
                from: data,
                permitsWorkout: true
            )
            let expectedStatus: SocialWorkoutInviteStatus =
                decision == "accept" ? .accepted : .declined
            guard result.inviteID == inviteID,
                  result.status == expectedStatus,
                  expectedRevision < 2_147_483_647,
                  result.inviteRevision == expectedRevision + 1 else {
                throw SocialPayloadError.invalidResponse
            }
            return result
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func socialCancelWorkoutInvite(
        inviteID: String,
        expectedRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> SocialWorkoutInviteMutation {
        guard SocialPayloadParser.isValidInviteID(inviteID),
              (1 ... 2_147_483_647).contains(expectedRevision) else {
            throw CloudSyncError.invalidWorkoutInvite
        }
        let (data, _) = try await socialRequest(
            path: "/rest/v1/rpc/social_cancel_workout_invite",
            expectedUserID: expectedUserID,
            body: [
                "p_invite_id": inviteID,
                "p_expected_revision": expectedRevision
            ],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            let result = try SocialPayloadParser.workoutInviteMutation(
                from: data,
                permitsWorkout: false
            )
            guard result.inviteID == inviteID else {
                throw SocialPayloadError.invalidResponse
            }
            return result
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    func withSyncIndicator<T>(_ action: () async throws -> T) async rethrows -> T {
        isSyncing = true
        defer { isSyncing = false }
        do {
            return try await action()
        } catch {
            lastError = gymSafeEnglishErrorMessage(error)
            throw error
        }
    }

    private func socialFriendshipRemovalRPC(
        path: String,
        friendshipID: String,
        expectedRevision: Int,
        expectedUserID: String?
    ) async throws -> SocialFriendshipMutation {
        guard SocialPayloadParser.isValidFriendshipID(friendshipID),
              (1 ... 2_147_483_647).contains(expectedRevision) else {
            throw CloudSyncError.invalidFriendship
        }
        let (data, _) = try await socialRequest(
            path: path,
            expectedUserID: expectedUserID,
            body: [
                "p_friendship_id": friendshipID,
                "p_expected_revision": expectedRevision
            ],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            let result = try SocialPayloadParser.friendshipMutation(from: data)
            guard result.friendshipID == friendshipID,
                  result.status == .removed else {
                throw SocialPayloadError.invalidResponse
            }
            return result
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    private func socialBlockRPC(
        path: String,
        profileID: String,
        expectedUserID: String?
    ) async throws -> SocialBlockMutation {
        guard SocialPayloadParser.isValidProfileID(profileID) else {
            throw CloudSyncError.invalidSocialProfile
        }
        let (data, _) = try await socialRequest(
            path: path,
            expectedUserID: expectedUserID,
            body: ["p_profile_id": profileID],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            return try SocialPayloadParser.blockMutation(from: data)
        } catch {
            throw CloudSyncError.invalidResponse
        }
    }

    private func socialRequest(
        path: String,
        expectedUserID: String?,
        body: Any,
        maximumResponseBytes: Int
    ) async throws -> (Data, String) {
        let expectedOperation = operationRevision
        let session = try await auth.validCloudSession(expectedUserID: expectedUserID)
        let userID = expectedUserID ?? session.userID
        guard session.userID == userID else { throw AuthServiceError.sessionChanged }
        let data = try await request(
            path: path,
            method: "POST",
            expectedUserID: userID,
            maximumResponseBytes: maximumResponseBytes,
            body: body
        )
        guard operationRevision == expectedOperation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        return (data, userID)
    }

    private func request(
        path: String,
        method: String,
        expectedUserID: String,
        prefer: String? = nil,
        conflictMeansStaleState: Bool = false,
        maximumResponseBytes: Int? = nil,
        body: Any? = nil
    ) async throws -> Data {
        guard let initialSession = auth.session?.cloud,
              initialSession.userID == expectedUserID else {
            throw AuthServiceError.sessionChanged
        }
        do {
            return try await requestOnce(
                path: path,
                method: method,
                token: initialSession.accessToken,
                prefer: prefer,
                conflictMeansStaleState: conflictMeansStaleState,
                maximumResponseBytes: maximumResponseBytes,
                body: body
            )
        } catch RequestFailure.http(let statusCode, _, _)
                    where statusCode == 401 || statusCode == 403 {
            guard auth.session?.cloud == initialSession else {
                throw AuthServiceError.sessionChanged
            }
            let refreshed = try await auth.validCloudSession(
                expectedUserID: expectedUserID,
                forceRefresh: true
            )
            do {
                return try await requestOnce(
                    path: path,
                    method: method,
                    token: refreshed.accessToken,
                    prefer: prefer,
                    conflictMeansStaleState: conflictMeansStaleState,
                    maximumResponseBytes: maximumResponseBytes,
                    body: body
                )
            } catch RequestFailure.http(let statusCode, let code, let message) {
                throw Self.cloudError(
                    statusCode: statusCode,
                    code: code,
                    message: message
                )
            }
        } catch RequestFailure.http(let statusCode, let code, let message) {
            throw Self.cloudError(
                statusCode: statusCode,
                code: code,
                message: message
            )
        }
    }

    private func requestOnce(
        path: String,
        method: String,
        token: String,
        prefer: String? = nil,
        conflictMeansStaleState: Bool = false,
        maximumResponseBytes: Int? = nil,
        body: Any? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: GymAppConfiguration.supabaseURL) else {
            throw CloudSyncError.invalidResponse
        }
        let responseLimit = maximumResponseBytes ?? Self.maximumCloudResponseBytes
        guard !token.isEmpty,
              token.utf8.prefix(Self.maximumTokenBytes + 1).count <= Self.maximumTokenBytes,
              token.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }),
              (1...Self.maximumCloudStateResponseBytes).contains(responseLimit) else {
            throw CloudSyncError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue(GymAppConfiguration.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoded = try JSONSerialization.data(withJSONObject: body)
            guard encoded.count <= Self.maximumCloudRequestBytes else {
                throw CloudSyncError.invalidPayload
            }
            request.httpBody = encoded
        }
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await BoundedURLSessionLoader.data(
                for: request,
                using: urlSession,
                successLimit: responseLimit,
                errorLimit: Self.maximumCloudErrorResponseBytes
            )
        } catch BoundedURLSessionError.responseTooLarge(let statusCode?)
                    where statusCode == 401 || statusCode == 403 {
            throw RequestFailure.http(
                statusCode: statusCode,
                code: nil,
                message: "Cloud sync failed (HTTP \(statusCode))."
            )
        } catch is BoundedURLSessionError {
            throw CloudSyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if conflictMeansStaleState && http.statusCode == 409 {
                throw CloudSyncError.staleRemoteState
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = Self.postgRESTErrorCode(object?["code"])
            let message = object?["message"] as? String
                ?? object?["error"] as? String
                ?? "Cloud sync failed (HTTP \(http.statusCode))."
            throw RequestFailure.http(
                statusCode: http.statusCode,
                code: code,
                message: message
            )
        }
        return data
    }

    private static func cloudError(
        statusCode: Int,
        code: String?,
        message: String
    ) -> CloudSyncError {
        guard let code else { return .requestFailed(message) }
        return .postgRESTFailure(statusCode: statusCode, code: code, message: message)
    }

    private static func isMissingSocialRPC(_ error: Error) -> Bool {
        switch error {
        case CloudSyncError.postgRESTFailure(let statusCode, let code, _):
            return statusCode == 404 && (code == "PGRST202" || code == "42883")
        case CloudSyncError.requestFailed(let message):
            // Some older test/proxy layers omit PostgREST's structured error body.
            // Keep this exact generic 404 compatible without treating arbitrary
            // request failures as evidence that the RPC is absent.
            return message == "Cloud sync failed (HTTP 404)."
        default:
            return false
        }
    }

    private static func postgRESTErrorCode(_ value: Any?) -> String? {
        guard let value = value as? String,
              value.utf8.prefix(33).count <= 32,
              value.range(
                  of: #"^(?:PGRST[0-9]{3}|[0-9A-Z]{5})$"#,
                  options: .regularExpression
              ) != nil else {
            return nil
        }
        return value
    }

    private static func queryValue(_ value: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func singleUpdatedAt(in data: Data) -> String? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.count == 1 else { return nil }
        return (rows[0]["updated_at"] as? String)?.nonEmpty
    }

    private static func nextRevisionTimestamp(after previous: String?) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var next = Date()
        if let previous,
           let previousDate = formatter.date(from: previous),
           next <= previousDate {
            next = previousDate.addingTimeInterval(0.001)
        }
        return formatter.string(from: next)
    }

    private static func isValidSocialTimestamp(_ value: String?) -> Bool {
        guard let value, value.utf8.count <= 40 else { return false }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if fractional.date(from: value) != nil { return true }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value) != nil
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
