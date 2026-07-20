import Foundation

struct LeaderboardEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let userID: String
    let displayName: String
    let xp: Int
    let level: Int
    let workouts: Int
    let isCurrentUser: Bool

    init(
        id: String? = nil,
        userID: String,
        displayName: String,
        xp: Int,
        level: Int,
        workouts: Int,
        isCurrentUser: Bool
    ) {
        self.id = id ?? Self.localOpaqueIdentifier(for: userID)
        self.userID = userID
        self.displayName = displayName
        self.xp = xp
        self.level = level
        self.workouts = workouts
        self.isCurrentUser = isCurrentUser
    }

    private static func localOpaqueIdentifier(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "leaderboard-local-\(String(hash, radix: 16))"
    }
}

enum CloudSyncError: LocalizedError {
    case invalidPayload
    case invalidLeaderboardProfile
    case invalidResponse
    case staleRemoteState
    case reportAlreadySubmitted
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "The local backup is not valid JSON."
        case .invalidLeaderboardProfile: return "This leaderboard profile is no longer available."
        case .invalidResponse: return "The cloud returned an invalid response."
        case .staleRemoteState:
            return "Cloud data changed on another device. Reload it before syncing again."
        case .reportAlreadySubmitted:
            return "You already reported this display name."
        case .requestFailed(let message): return message
        }
    }
}

@MainActor
final class CloudSyncService: ObservableObject {
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
            token: session.accessToken,
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
                token: session.accessToken,
                prefer: "return=representation",
                body: ["state": state, "updated_at": timestamp]
            )
        } else {
            revisionData = try await request(
                path: "/rest/v1/user_states?select=updated_at",
                method: "POST",
                token: session.accessToken,
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
            token: session.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal",
            body: profileBody
        )
        guard operationRevision == expectedOperation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        lastSyncedAt = Date()
        lastError = nil
    }

    func leaderboard(
        limit: Int = 50,
        expectedUserID: String? = nil
    ) async throws -> [LeaderboardEntry] {
        let session = try await auth.validCloudSession(expectedUserID: expectedUserID)
        let userID = expectedUserID ?? session.userID
        guard session.userID == userID else { throw AuthServiceError.sessionChanged }
        let safeLimit = min(max(limit, 1), 100)
        let data = try await request(
            path: "/rest/v1/leaderboard_public?select=profile_id,display_name,xp,level,workouts,is_current_user&order=xp.desc,workouts.desc,display_name.asc&limit=\(safeLimit)",
            method: "GET",
            token: session.accessToken
        )
        guard auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CloudSyncError.invalidResponse
        }
        return rows.compactMap { row in
            guard let profileID = row["profile_id"] as? String,
                  Self.isValidPublicProfileID(profileID) else { return nil }
            let isCurrentUser = row["is_current_user"] as? Bool ?? false
            return LeaderboardEntry(
                id: profileID,
                // Kept for existing in-process UI correlation only; no other user's
                // Supabase UUID is requested or received from the public view.
                userID: isCurrentUser ? session.userID : profileID,
                displayName: (row["display_name"] as? String)?.nonEmpty ?? "GymApp user",
                xp: (row["xp"] as? NSNumber)?.intValue ?? 0,
                level: max(1, (row["level"] as? NSNumber)?.intValue ?? 1),
                workouts: max(0, (row["workouts"] as? NSNumber)?.intValue ?? 0),
                isCurrentUser: isCurrentUser
            )
        }
    }

    /// Reports the only public user-generated field in GymApp: a leaderboard display name.
    /// The server derives and validates the reporter from the bearer token; no free-form
    /// report text is accepted or uploaded.
    func reportLeaderboardDisplayName(profileID: String) async throws {
        guard Self.isValidPublicProfileID(profileID) else { throw CloudSyncError.invalidLeaderboardProfile }
        let session = try await auth.validCloudSession()
        do {
            _ = try await request(
                path: "/rest/v1/leaderboard_reports",
                method: "POST",
                token: session.accessToken,
                prefer: "return=minimal",
                body: [[
                    "reported_profile_id": profileID,
                    "reason": "inappropriate_name"
                ]]
            )
        } catch CloudSyncError.requestFailed(let message)
                    where message.localizedCaseInsensitiveContains("duplicate") {
            throw CloudSyncError.reportAlreadySubmitted
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

    private func request(
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
        } catch is BoundedURLSessionError {
            throw CloudSyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if conflictMeansStaleState && http.statusCode == 409 {
                throw CloudSyncError.staleRemoteState
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = object?["message"] as? String
                ?? object?["error"] as? String
                ?? "Cloud sync failed (HTTP \(http.statusCode))."
            throw CloudSyncError.requestFailed(message)
        }
        return data
    }

    private static func queryValue(_ value: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func isValidPublicProfileID(_ value: String) -> Bool {
        value.range(of: #"^p_[0-9a-f]{32}$"#, options: .regularExpression) != nil
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
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
