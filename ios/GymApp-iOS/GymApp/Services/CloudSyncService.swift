import Foundation
import OSLog

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

enum CloudSyncOperation: String, CaseIterable, Sendable {
    case workoutStateRead = "workout_state_read"
    case workoutStateWrite = "workout_state_write"
    case workoutProfileWrite = "workout_profile_write"
    case workoutDurationWrite = "workout_duration_write"
    case activityOnlyRead = "activity_only_read"
    case activityOnlyWrite = "activity_only_write"
    case friendDashboard = "friend_dashboard"
    case friendCode = "friend_code"
    case friendDetails = "friend_details"
    case friendWorkoutPage = "friend_workout_page"
    case friendWorkoutDetailCapability = "friend_workout_detail_capability"
    case friendPrivacyRead = "friend_privacy_read"
    case friendPrivacyWrite = "friend_privacy_write"
    case friendRelationshipWrite = "friend_relationship_write"
    case friendInboxPage = "friend_inbox_page"
    case friendInboxLegacy = "friend_inbox_legacy"
    case friendInvitePlan = "friend_invite_plan"
    case friendInviteWrite = "friend_invite_write"
    case unknown = "unknown"

    static func resolve(path: String, method: String) -> Self {
        if path.hasPrefix("/rest/v1/user_states") {
            return method == "GET" ? .workoutStateRead : .workoutStateWrite
        }
        if path.hasPrefix("/rest/v1/profiles") {
            return .workoutProfileWrite
        }
        switch path {
        case "/rest/v1/rpc/social_sync_workout_durations":
            return .workoutDurationWrite
        case "/rest/v1/rpc/garmin_read_activity_only_workouts":
            return .activityOnlyRead
        case "/rest/v1/rpc/garmin_sync_activity_only_workouts":
            return .activityOnlyWrite
        case "/rest/v1/rpc/social_dashboard":
            return .friendDashboard
        case "/rest/v1/rpc/social_my_friend_code":
            return .friendCode
        case "/rest/v1/rpc/social_friend_details":
            return .friendDetails
        case "/rest/v1/rpc/social_friend_workout_page":
            return .friendWorkoutPage
        case "/rest/v1/rpc/social_friend_workout_detail_capability":
            return .friendWorkoutDetailCapability
        case "/rest/v1/rpc/social_workout_detail_privacy":
            return .friendPrivacyRead
        case "/rest/v1/rpc/social_update_workout_detail_privacy",
             "/rest/v1/rpc/social_update_privacy":
            return .friendPrivacyWrite
        case "/rest/v1/rpc/social_send_friend_request",
             "/rest/v1/rpc/social_respond_friend_request",
             "/rest/v1/rpc/social_cancel_friend_request",
             "/rest/v1/rpc/social_remove_friend",
             "/rest/v1/rpc/social_block_profile",
             "/rest/v1/rpc/social_unblock_profile":
            return .friendRelationshipWrite
        case "/rest/v1/rpc/social_workout_inbox_page":
            return .friendInboxPage
        case "/rest/v1/rpc/social_workout_inbox":
            return .friendInboxLegacy
        case "/rest/v1/rpc/social_workout_invite_plan":
            return .friendInvitePlan
        case "/rest/v1/rpc/social_send_workout_invite",
             "/rest/v1/rpc/social_respond_workout_invite",
             "/rest/v1/rpc/social_cancel_workout_invite":
            return .friendInviteWrite
        default:
            return .unknown
        }
    }
}

enum CloudSyncDiagnosticPhase: String, Sendable {
    case request
    case response
    case decode
    case cas
    case commit
    case gate
    case reconciliation
}

enum CloudSyncDiagnosticOutcome: String, Sendable {
    case success
    case failure
    case retry
    case queued
    case skipped
    case paused
}

enum CloudSyncDiagnosticTransport: String, Sendable {
    case http
    case network
    case responseLimit = "response_limit"
    case decode
    case validation
    case authentication
    case cancellation
    case unknown
    case none
}

enum CloudSyncDiagnosticCodeReason: String, Sendable {
    case none
    case missingCode = "missing_code"
    case unrecognizedCode = "unrecognized_code"
    case allowlistedCode = "allowlisted_code"
}

struct CloudSyncDiagnosticGate: Equatable, Sendable {
    let accountReady: Bool
    let signingOut: Bool
    let storeMatches: Bool
    let cloudSessionMatches: Bool
    let writesAllowed: Bool
}

struct CloudSyncDiagnosticEvent: Equatable, Sendable {
    let operation: CloudSyncOperation
    let phase: CloudSyncDiagnosticPhase
    let outcome: CloudSyncDiagnosticOutcome
    let statusCode: Int?
    let postgRESTCode: String?
    let postgRESTCodeReason: CloudSyncDiagnosticCodeReason
    let transport: CloudSyncDiagnosticTransport
    let gate: CloudSyncDiagnosticGate?
}

enum CloudSyncDiagnostics {
    private static let logger = Logger(
        subsystem: "com.setforge.gymapp.ios",
        category: "cloud-sync"
    )

    // Keep this list deliberately small. Status remains useful when a structured
    // server code is unknown, while only stable, reviewed codes are emitted.
    static let allowedPostgRESTCodes: Set<String> = [
        "PGRST100", "PGRST102", "PGRST106",
        "PGRST202", "PGRST204", "PGRST301", "PGRST302", "PGRST303",
        "42883", "42501", "42702", "22P02", "P0001", "P0002", "22023",
        "42P01", "42703", "23505"
    ]

#if DEBUG
    nonisolated(unsafe) static var testObserver: ((CloudSyncDiagnosticEvent) -> Void)?
#endif

    static func sanitizedPostgRESTCode(_ code: String?) -> String? {
        guard let code, allowedPostgRESTCodes.contains(code) else { return nil }
        return code
    }

    static func makeEvent(
        operation: CloudSyncOperation,
        phase: CloudSyncDiagnosticPhase,
        outcome: CloudSyncDiagnosticOutcome,
        statusCode: Int? = nil,
        postgRESTCode: String? = nil,
        postgRESTCodePresent: Bool? = nil,
        transportClass: CloudSyncDiagnosticTransport? = nil,
        error: Error? = nil,
        gate: CloudSyncDiagnosticGate? = nil
    ) -> CloudSyncDiagnosticEvent {
        let safeStatus = statusCode.flatMap { (100 ... 599).contains($0) ? $0 : nil }
        let codeReason = Self.codeReason(
            statusCode: safeStatus,
            postgRESTCode: postgRESTCode,
            postgRESTCodePresent: postgRESTCodePresent ?? (postgRESTCode != nil)
        )
        return CloudSyncDiagnosticEvent(
            operation: operation,
            phase: phase,
            outcome: outcome,
            statusCode: safeStatus,
            postgRESTCode: sanitizedPostgRESTCode(postgRESTCode),
            postgRESTCodeReason: codeReason,
            transport: transportClass ?? Self.transport(for: error),
            gate: gate
        )
    }

    @discardableResult
    static func record(
        operation: CloudSyncOperation,
        phase: CloudSyncDiagnosticPhase,
        outcome: CloudSyncDiagnosticOutcome,
        statusCode: Int? = nil,
        postgRESTCode: String? = nil,
        postgRESTCodePresent: Bool? = nil,
        transportClass: CloudSyncDiagnosticTransport? = nil,
        error: Error? = nil,
        gate: CloudSyncDiagnosticGate? = nil
    ) -> CloudSyncDiagnosticEvent {
        let event = makeEvent(
            operation: operation,
            phase: phase,
            outcome: outcome,
            statusCode: statusCode,
            postgRESTCode: postgRESTCode,
            postgRESTCodePresent: postgRESTCodePresent,
            transportClass: transportClass,
            error: error,
            gate: gate
        )
#if DEBUG
        testObserver?(event)
#endif
        let status = event.statusCode.map(String.init) ?? "none"
        let code = event.postgRESTCode ?? "none"
        let codeReason = event.postgRESTCodeReason.rawValue
        let gateDescription = event.gate.map {
            "ready=\($0.accountReady),signing_out=\($0.signingOut),store=\($0.storeMatches),session=\($0.cloudSessionMatches),writes=\($0.writesAllowed)"
        } ?? "none"
        logger.notice(
            "cloud_sync op=\(event.operation.rawValue, privacy: .public) phase=\(event.phase.rawValue, privacy: .public) outcome=\(event.outcome.rawValue, privacy: .public) status=\(status, privacy: .public) code=\(code, privacy: .public) code_reason=\(codeReason, privacy: .public) transport=\(event.transport.rawValue, privacy: .public) gate=\(gateDescription, privacy: .public)"
        )
        return event
    }

    private static func codeReason(
        statusCode: Int?,
        postgRESTCode: String?,
        postgRESTCodePresent: Bool
    ) -> CloudSyncDiagnosticCodeReason {
        if let postgRESTCode {
            return allowedPostgRESTCodes.contains(postgRESTCode)
                ? .allowlistedCode
                : .unrecognizedCode
        }
        guard postgRESTCodePresent else {
            guard let statusCode, (400 ... 599).contains(statusCode) else { return .none }
            return .missingCode
        }
        return .unrecognizedCode
    }

    static func transport(for error: Error?) -> CloudSyncDiagnosticTransport {
        guard let error else { return .none }
        if error is CancellationError { return .cancellation }
        if error is URLError { return .network }
        if error is BoundedURLSessionError { return .responseLimit }
        if error is AuthServiceError { return .authentication }
        if error is DecodingError { return .decode }
        if let cloudError = error as? CloudSyncError {
            switch cloudError {
            case .invalidPayload, .invalidSocialProfile, .invalidFriendship,
                 .invalidWorkoutInvite:
                return .validation
            case .invalidResponse:
                return .decode
            case .staleRemoteState:
                return .validation
            case .postgRESTFailure:
                return .http
            case .requestFailed:
                return .unknown
            }
        }
        return .unknown
    }
}

private struct CloudSyncResponse: Sendable {
    let data: Data
    let statusCode: Int
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
        let session = try await validCloudSession(
            expectedUserID: expectedUserID,
            operation: .workoutStateRead
        )
        let userID = expectedUserID ?? session.userID
        guard session.userID == userID else { throw AuthServiceError.sessionChanged }
        stateRevision = .unknown
        let path = "/rest/v1/user_states?select=state,updated_at&user_id=eq.\(Self.queryValue(userID))&limit=1"
        let response = try await request(
            path: path,
            method: "GET",
            expectedUserID: userID,
            maximumResponseBytes: Self.maximumCloudStateResponseBytes
        )
        let data = response.data
        guard operationRevision == expectedOperation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        let rows: [[String: Any]]
        do {
            guard let decodedRows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw CloudSyncError.invalidResponse
            }
            rows = decodedRows
        } catch {
            CloudSyncDiagnostics.record(
                operation: .workoutStateRead,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode,
                error: error
            )
            throw error
        }
        guard let row = rows.first else {
            stateRevision = .missing(userID: userID)
            return nil
        }
        guard let state = row["state"],
              let updatedAt = (row["updated_at"] as? String)?.nonEmpty else {
            CloudSyncDiagnostics.record(
                operation: .workoutStateRead,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode
            )
            throw CloudSyncError.invalidResponse
        }
        stateRevision = .loaded(userID: userID, updatedAt: updatedAt)
        return try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    }

    func loadActivityOnlyWorkouts(
        expectedUserID: String? = nil
    ) async throws -> ActivityOnlyWorkoutCloudReadResult {
        do {
            let (response, _) = try await socialRequestWithResponse(
                path: "/rest/v1/rpc/garmin_read_activity_only_workouts",
                expectedUserID: expectedUserID,
                body: [:],
                maximumResponseBytes: ActivityOnlyWorkoutCloudCodec.maximumResponseBytes
            )
            do {
                return .snapshot(try ActivityOnlyWorkoutCloudCodec.parseReadResponse(response.data))
            } catch {
                CloudSyncDiagnostics.record(
                    operation: .activityOnlyRead,
                    phase: .decode,
                    outcome: .failure,
                    statusCode: response.statusCode,
                    transportClass: .decode,
                    error: error
                )
                throw error
            }
        } catch let error where Self.isMissingActivityOnlyRPC(error) {
            // Mixed-version deployments must keep the local owner-private activity instead
            // of falling back to schema-v2 or the public workout-duration sidecar.
            return .unavailable
        }
    }

    func syncActivityOnlyWorkouts(
        expectedRevision: Int64,
        requestID: UUID,
        items: [ActivityOnlyWorkoutCloudItem],
        exactRequestBody: Data? = nil,
        expectedUserID: String? = nil
    ) async throws -> ActivityOnlyWorkoutCloudSyncResult {
        let canonicalRequestBody = try ActivityOnlyWorkoutCloudCodec.syncRequestData(
            expectedRevision: expectedRevision,
            requestID: requestID,
            items: items
        )
        guard exactRequestBody.map({ $0 == canonicalRequestBody }) ?? true else {
            throw CloudSyncError.invalidPayload
        }
        do {
            let (response, _) = try await socialRequestWithResponse(
                path: "/rest/v1/rpc/garmin_sync_activity_only_workouts",
                expectedUserID: expectedUserID,
                encodedBody: exactRequestBody ?? canonicalRequestBody,
                maximumResponseBytes: ActivityOnlyWorkoutCloudCodec.maximumResponseBytes
            )
            let result: ActivityOnlyWorkoutCloudSyncResult
            do {
                result = try ActivityOnlyWorkoutCloudCodec.parseSyncResponse(response.data)
            } catch {
                CloudSyncDiagnostics.record(
                    operation: .activityOnlyWrite,
                    phase: .decode,
                    outcome: .failure,
                    statusCode: response.statusCode,
                    transportClass: .decode,
                    error: error
                )
                throw error
            }
            if case .synced(_, let syncedCount, _, _) = result,
               syncedCount != items.count {
                CloudSyncDiagnostics.record(
                    operation: .activityOnlyWrite,
                    phase: .commit,
                    outcome: .failure,
                    statusCode: response.statusCode,
                    transportClass: .validation
                )
                throw CloudSyncError.invalidResponse
            }
            if case .synced = result {
                CloudSyncDiagnostics.record(
                    operation: .activityOnlyWrite,
                    phase: .commit,
                    outcome: .success,
                    statusCode: response.statusCode,
                    transportClass: .http
                )
            }
            return result
        } catch let error where Self.isMissingActivityOnlyRPC(error) {
            return .unavailable
        }
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
        let session = try await validCloudSession(
            expectedUserID: expectedUserID,
            operation: .workoutStateWrite
        )
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

        let revisionResponse: CloudSyncResponse
        if let priorRevision {
            revisionResponse = try await request(
                path: "/rest/v1/user_states?user_id=eq.\(Self.queryValue(userID))&updated_at=eq.\(Self.queryValue(priorRevision))&select=updated_at",
                method: "PATCH",
                expectedUserID: userID,
                prefer: "return=representation",
                body: ["state": state, "updated_at": timestamp]
            )
        } else {
            revisionResponse = try await request(
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

        guard let storedRevision = Self.singleUpdatedAt(in: revisionResponse.data) else {
            CloudSyncDiagnostics.record(
                operation: .workoutStateWrite,
                phase: .cas,
                outcome: .failure,
                statusCode: revisionResponse.statusCode,
                transportClass: .decode
            )
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
            let durationResponse = try await request(
                path: "/rest/v1/rpc/social_sync_workout_durations",
                method: "POST",
                expectedUserID: userID,
                body: ["p_items": workoutDurations]
            )
            let durationData = durationResponse.data
            guard let result = try JSONSerialization.jsonObject(with: durationData) as? [String: Any],
                  let version = ActivityOnlyWorkoutCloudCodec.exactInteger(
                    result["version"], range: 1 ... 2
                  ) else {
                throw CloudSyncError.invalidResponse
            }
            if version == 1 {
                guard Set(result.keys) == ["version", "syncedCount"],
                      ActivityOnlyWorkoutCloudCodec.exactInteger(
                        result["syncedCount"], range: 0 ... 5_000
                      ) == Int64(workoutDurations.count) else {
                    throw CloudSyncError.invalidResponse
                }
            } else if let error = result["error"] as? String {
                guard Set(result.keys) == ["version", "error", "retryAfter"],
                      ["rate_limited", "invalid_payload"].contains(error),
                      let retryAfter = ActivityOnlyWorkoutCloudCodec.exactInteger(
                        result["retryAfter"], range: 0 ... 600
                      ),
                      (error == "rate_limited" && (1 ... 600).contains(retryAfter)) ||
                        (error == "invalid_payload" && retryAfter == 0) else {
                    throw CloudSyncError.invalidResponse
                }
                throw CloudSyncError.requestFailed(
                    "Workout duration synchronization was rejected: \(error)."
                )
            } else {
                guard Set(result.keys) == [
                    "version", "syncedCount", "changedCount"
                ],
                ActivityOnlyWorkoutCloudCodec.exactInteger(
                    result["syncedCount"], range: 0 ... 5_000
                ) == Int64(workoutDurations.count),
                ActivityOnlyWorkoutCloudCodec.exactInteger(
                    result["changedCount"], range: 0 ... 10_000
                ) != nil else {
                    throw CloudSyncError.invalidResponse
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            CloudSyncDiagnostics.record(
                operation: .workoutDurationWrite,
                phase: .commit,
                outcome: .failure,
                error: error
            )
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
        CloudSyncDiagnostics.record(
            operation: .workoutStateWrite,
            phase: .commit,
            outcome: .success,
            transportClass: CloudSyncDiagnosticTransport.none
        )
    }

    func socialDashboard(expectedUserID: String? = nil) async throws -> SocialDashboard {
        let (response, _) = try await socialRequestWithResponse(
            path: "/rest/v1/rpc/social_dashboard",
            expectedUserID: expectedUserID,
            body: [:],
            maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
        )
        do {
            return try SocialPayloadParser.dashboard(from: response.data)
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendDashboard,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode
            )
            throw CloudSyncError.invalidResponse
        }
    }

    func socialMyFriendCode(expectedUserID: String? = nil) async throws -> String {
        let (response, _) = try await socialRequestWithResponse(
            path: "/rest/v1/rpc/social_my_friend_code",
            expectedUserID: expectedUserID,
            body: [:],
            maximumResponseBytes: SocialPayloadParser.maximumFriendCodeResponseBytes
        )
        do {
            return try SocialPayloadParser.friendCode(from: response.data)
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendCode,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode
            )
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
        let (response, _) = try await socialRequestWithResponse(
            path: "/rest/v1/rpc/social_friend_details",
            expectedUserID: expectedUserID,
            body: ["p_profile_id": profileID],
            maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
        )
        do {
            let details = try SocialPayloadParser.friendDetails(from: response.data)
            guard details.friend.profileID == profileID else {
                throw SocialPayloadError.invalidResponse
            }
            return details
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendDetails,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode
            )
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
        let response: CloudSyncResponse
        do {
            (response, _) = try await socialRequestWithResponse(
                path: "/rest/v1/rpc/social_friend_workout_page",
                expectedUserID: expectedUserID,
                body: body,
                maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
            )
        } catch CloudSyncError.postgRESTFailure(_, let code, _)
                    where ["P0002", "PGRST202", "42883"].contains(code) {
            return nil
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendWorkoutPage,
                phase: .request,
                outcome: .failure,
                transportClass: CloudSyncDiagnostics.transport(for: error),
                error: error
            )
            throw CloudSyncError.invalidResponse
        }
        do {
            let page = try SocialPayloadParser.friendWorkoutPage(from: response.data)
            guard page.profileID == profileID,
                  expectedActivityRevision == nil ||
                    page.activityRevision == expectedActivityRevision else {
                throw SocialPayloadError.invalidResponse
            }
            return page
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendWorkoutPage,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode,
                error: error
            )
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
        let response: CloudSyncResponse
        do {
            (response, _) = try await socialRequestWithResponse(
                path: "/rest/v1/rpc/social_friend_workout_detail_capability",
                expectedUserID: expectedUserID,
                body: ["p_profile_id": profileID],
                maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
            )
        } catch CloudSyncError.postgRESTFailure(let status, let code, _)
                    where status == 404 && ["PGRST202", "42883"].contains(code) {
            return SocialFriendWorkoutDetailCapability(available: false)
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendWorkoutDetailCapability,
                phase: .request,
                outcome: .failure,
                transportClass: CloudSyncDiagnostics.transport(for: error),
                error: error
            )
            throw error
        }
        do {
            return try SocialPayloadParser.friendWorkoutDetailCapability(from: response.data)
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendWorkoutDetailCapability,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode,
                error: error
            )
            throw error
        }
    }

    func socialWorkoutDetailPrivacy(
        expectedUserID: String? = nil
    ) async throws -> SocialWorkoutDetailPrivacy {
        let (response, _) = try await socialRequestWithResponse(
            path: "/rest/v1/rpc/social_workout_detail_privacy",
            expectedUserID: expectedUserID,
            body: [:],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        do {
            return try SocialPayloadParser.workoutDetailPrivacy(from: response.data)
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendPrivacyRead,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode,
                error: error
            )
            throw error
        }
    }

    func socialUpdateWorkoutDetailPrivacy(
        _ enabled: Bool,
        expectedRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> SocialWorkoutDetailPrivacy {
        guard (1 ... 2_147_483_647).contains(expectedRevision) else {
            throw CloudSyncError.invalidResponse
        }
        let (response, _) = try await socialRequestWithResponse(
            path: "/rest/v1/rpc/social_update_workout_detail_privacy",
            expectedUserID: expectedUserID,
            body: [
                "p_share_workout_details": enabled,
                "p_expected_revision": expectedRevision
            ],
            maximumResponseBytes: SocialPayloadParser.maximumMutationResponseBytes
        )
        let result: SocialWorkoutDetailPrivacy
        do {
            result = try SocialPayloadParser.workoutDetailPrivacy(from: response.data)
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendPrivacyWrite,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode,
                error: error
            )
            throw error
        }
        guard result.shareWorkoutDetails == enabled else {
            CloudSyncDiagnostics.record(
                operation: .friendPrivacyWrite,
                phase: .commit,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .validation
            )
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
        let (response, _) = try await socialRequestWithResponse(
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
            return try SocialPayloadParser.privacyMutation(from: response.data)
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendPrivacyWrite,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode
            )
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
        let response: CloudSyncResponse
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
            (response, _) = try await socialRequestWithResponse(
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
            let (legacyResponse, _) = try await socialRequestWithResponse(
                path: "/rest/v1/rpc/social_workout_inbox",
                expectedUserID: expectedUserID,
                body: [:],
                maximumResponseBytes: SocialPayloadParser.maximumResponseBytes
            )
            do {
                return try SocialPayloadParser.workoutInbox(from: legacyResponse.data)
            } catch {
                CloudSyncDiagnostics.record(
                    operation: .friendInboxLegacy,
                    phase: .decode,
                    outcome: .failure,
                    statusCode: legacyResponse.statusCode,
                    transportClass: .decode
                )
                throw CloudSyncError.invalidResponse
            }
        }
        do {
            return try SocialPayloadParser.workoutInboxPage(
                from: response.data,
                expectedLimit: limit
            )
        } catch {
            CloudSyncDiagnostics.record(
                operation: .friendInboxPage,
                phase: .decode,
                outcome: .failure,
                statusCode: response.statusCode,
                transportClass: .decode
            )
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
        body: Any? = nil,
        encodedBody: Data? = nil,
        maximumResponseBytes: Int
    ) async throws -> (Data, String) {
        let (response, userID) = try await socialRequestWithResponse(
            path: path,
            expectedUserID: expectedUserID,
            body: body,
            encodedBody: encodedBody,
            maximumResponseBytes: maximumResponseBytes
        )
        return (response.data, userID)
    }

    private func socialRequestWithResponse(
        path: String,
        expectedUserID: String?,
        body: Any? = nil,
        encodedBody: Data? = nil,
        maximumResponseBytes: Int
    ) async throws -> (CloudSyncResponse, String) {
        let expectedOperation = operationRevision
        let operation = CloudSyncOperation.resolve(path: path, method: "POST")
        let session = try await validCloudSession(
            expectedUserID: expectedUserID,
            operation: operation
        )
        let userID = expectedUserID ?? session.userID
        guard session.userID == userID else { throw AuthServiceError.sessionChanged }
        let response = try await request(
            path: path,
            method: "POST",
            expectedUserID: userID,
            maximumResponseBytes: maximumResponseBytes,
            body: body,
            encodedBody: encodedBody
        )
        guard operationRevision == expectedOperation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        return (response, userID)
    }

    private func validCloudSession(
        expectedUserID: String?,
        operation: CloudSyncOperation
    ) async throws -> CloudAccountSession {
        do {
            return try await auth.validCloudSession(expectedUserID: expectedUserID)
        } catch {
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .request,
                outcome: .failure,
                transportClass: CloudSyncDiagnostics.transport(for: error),
                error: error
            )
            throw error
        }
    }

    private func request(
        path: String,
        method: String,
        expectedUserID: String,
        prefer: String? = nil,
        conflictMeansStaleState: Bool = false,
        maximumResponseBytes: Int? = nil,
        body: Any? = nil,
        encodedBody: Data? = nil
    ) async throws -> CloudSyncResponse {
        let operation = CloudSyncOperation.resolve(path: path, method: method)
        guard body == nil || encodedBody == nil else {
            let error = CloudSyncError.invalidPayload
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .request,
                outcome: .failure,
                transportClass: .validation,
                error: error
            )
            throw error
        }
        let requestBody: Data?
        if let encodedBody {
            requestBody = encodedBody
        } else if let body {
            requestBody = try JSONSerialization.data(
                withJSONObject: body,
                options: [.sortedKeys]
            )
        } else {
            requestBody = nil
        }
        if let requestBody,
           requestBody.count > Self.maximumCloudRequestBytes {
            let error = CloudSyncError.invalidPayload
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .request,
                outcome: .failure,
                transportClass: .validation,
                error: error
            )
            throw error
        }
        guard let initialSession = auth.session?.cloud,
              initialSession.userID == expectedUserID else {
            let error = AuthServiceError.sessionChanged
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .request,
                outcome: .failure,
                transportClass: .authentication,
                error: error
            )
            throw error
        }
        do {
            return try await requestOnce(
                path: path,
                method: method,
                token: initialSession.accessToken,
                prefer: prefer,
                conflictMeansStaleState: conflictMeansStaleState,
                maximumResponseBytes: maximumResponseBytes,
                body: requestBody
            )
        } catch RequestFailure.http(let statusCode, _, _)
                    where statusCode == 401 || statusCode == 403 {
            guard auth.session?.cloud == initialSession else {
                let error = AuthServiceError.sessionChanged
                CloudSyncDiagnostics.record(
                    operation: operation,
                    phase: .request,
                    outcome: .failure,
                    statusCode: statusCode,
                    transportClass: .authentication,
                    error: error
                )
                throw error
            }
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .request,
                outcome: .retry,
                statusCode: statusCode,
                transportClass: .http
            )
            let refreshed: CloudAccountSession
            do {
                refreshed = try await auth.validCloudSession(
                    expectedUserID: expectedUserID,
                    forceRefresh: true
                )
            } catch {
                CloudSyncDiagnostics.record(
                    operation: operation,
                    phase: .request,
                    outcome: .failure,
                    statusCode: statusCode,
                    transportClass: .authentication,
                    error: error
                )
                throw error
            }
            do {
                return try await requestOnce(
                    path: path,
                    method: method,
                    token: refreshed.accessToken,
                    prefer: prefer,
                    conflictMeansStaleState: conflictMeansStaleState,
                    maximumResponseBytes: maximumResponseBytes,
                    body: requestBody
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
        } catch {
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .request,
                outcome: .failure,
                error: error
            )
            throw error
        }
    }

    private func requestOnce(
        path: String,
        method: String,
        token: String,
        prefer: String? = nil,
        conflictMeansStaleState: Bool = false,
        maximumResponseBytes: Int? = nil,
        body: Data? = nil
    ) async throws -> CloudSyncResponse {
        let operation = CloudSyncOperation.resolve(path: path, method: method)
        guard let url = URL(string: path, relativeTo: GymAppConfiguration.supabaseURL) else {
            let error = CloudSyncError.invalidResponse
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .request,
                outcome: .failure,
                transportClass: .validation,
                error: error
            )
            throw error
        }
        let responseLimit = maximumResponseBytes ?? Self.maximumCloudResponseBytes
        guard !token.isEmpty,
              token.utf8.prefix(Self.maximumTokenBytes + 1).count <= Self.maximumTokenBytes,
              token.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }),
              (1...Self.maximumCloudStateResponseBytes).contains(responseLimit) else {
            let error = CloudSyncError.invalidResponse
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .request,
                outcome: .failure,
                transportClass: .validation,
                error: error
            )
            throw error
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
            request.httpBody = body
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
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .response,
                outcome: .failure,
                statusCode: statusCode,
                transportClass: .responseLimit
            )
            throw RequestFailure.http(
                statusCode: statusCode,
                code: nil,
                message: "Cloud sync failed (HTTP \(statusCode))."
            )
        } catch BoundedURLSessionError.responseTooLarge(let statusCode) {
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .response,
                outcome: .failure,
                statusCode: statusCode,
                transportClass: .responseLimit
            )
            throw CloudSyncError.invalidResponse
        } catch is BoundedURLSessionError {
            let error = CloudSyncError.invalidResponse
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .response,
                outcome: .failure,
                transportClass: .responseLimit,
                error: error
            )
            throw error
        } catch {
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .response,
                outcome: .failure,
                error: error
            )
            throw error
        }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = Self.postgRESTErrorCode(object?["code"])
            let codePresent = object?["code"] != nil
            if conflictMeansStaleState && http.statusCode == 409 {
                CloudSyncDiagnostics.record(
                    operation: operation,
                    phase: .cas,
                    outcome: .failure,
                    statusCode: http.statusCode,
                    postgRESTCode: code,
                    postgRESTCodePresent: codePresent,
                    transportClass: .http
                )
                throw CloudSyncError.staleRemoteState
            }
            let message = object?["message"] as? String
                ?? object?["error"] as? String
                ?? "Cloud sync failed (HTTP \(http.statusCode))."
            CloudSyncDiagnostics.record(
                operation: operation,
                phase: .response,
                outcome: .failure,
                statusCode: http.statusCode,
                postgRESTCode: code,
                postgRESTCodePresent: codePresent,
                transportClass: .http
            )
            throw RequestFailure.http(
                statusCode: http.statusCode,
                code: code,
                message: message
            )
        }
        CloudSyncDiagnostics.record(
            operation: operation,
            phase: .response,
            outcome: .success,
            statusCode: http.statusCode,
            transportClass: .http
        )
        return CloudSyncResponse(data: data, statusCode: http.statusCode)
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

    private static func isMissingActivityOnlyRPC(_ error: Error) -> Bool {
        switch error {
        case CloudSyncError.postgRESTFailure(let statusCode, let code, _):
            return statusCode == 404 && (code == "PGRST202" || code == "42883")
        case CloudSyncError.requestFailed(let message):
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
