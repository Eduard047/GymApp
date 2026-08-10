import CoreFoundation
import Foundation

enum LiveWorkoutGatewayError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case conflict
    case resourceUnavailable
    case rateLimited(retryAfter: Int)
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "This live workout request is invalid. Refresh the room before trying again."
        case .invalidResponse:
            "The live workout service returned an invalid response. Nothing local was changed."
        case .conflict:
            "Live workout progress changed on another device. GymApp will refresh it before retrying."
        case .resourceUnavailable:
            "This live workout is no longer available."
        case .rateLimited(let retryAfter):
            "Too many live workout requests. Try again in \(retryAfter) seconds."
        case .serviceUnavailable:
            "Live workouts are temporarily unavailable. Your local workout is safe."
        }
    }
}

struct LiveWorkoutSessionContext: Equatable, Sendable {
    let userID: String
    let sessionID: String
    let accessToken: String
}

@MainActor
final class LiveWorkoutGatewayService {
    private enum RequestFailure: Error {
        case http(status: Int, code: String?, retryAfter: Int?)
    }

    private let auth: AuthService
    private let urlSession: URLSession
    private var operationGeneration: UInt64 = 0

    private static let allowedActions = Set([
        "live_inbox", "live_send_invite", "live_respond_invite", "live_start",
        "live_snapshot", "live_apply", "live_finish", "live_leave", "live_cancel"
    ])
    private static let maximumTokenBytes = 16 * 1_024
    private static let maximumErrorBytes = 8 * 1_024
    private static let uuidPattern = try! NSRegularExpression(
        pattern: #"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
        options: [.caseInsensitive]
    )
    private static let roomPattern = try! NSRegularExpression(pattern: #"^lr_[0-9a-f]{32}$"#)
    private static let profilePattern = try! NSRegularExpression(pattern: #"^p_[0-9a-f]{32}$"#)
    private static let setPattern = try! NSRegularExpression(pattern: #"^s_[0-9]{2}_[0-9]{2}$"#)

    init(auth: AuthService, urlSession: URLSession = .shared) {
        self.auth = auth
        self.urlSession = urlSession
    }

    func resetForAccountTransition() {
        operationGeneration &+= 1
    }

    func currentContext(expectedUserID: String? = nil) async throws -> LiveWorkoutSessionContext {
        let cloud = try await auth.validCloudSession(expectedUserID: expectedUserID)
        guard let sessionID = Self.verifiedSessionID(in: cloud.accessToken),
              Self.matches(cloud.userID, pattern: Self.uuidPattern) else {
            throw AuthServiceError.malformedResponse
        }
        return LiveWorkoutSessionContext(
            userID: cloud.userID.lowercased(),
            sessionID: sessionID,
            accessToken: cloud.accessToken
        )
    }

    func inbox(expectedUserID: String? = nil) async throws -> LiveWorkoutInbox {
        try await perform(
            action: "live_inbox",
            payload: [:],
            expectedUserID: expectedUserID,
            maximumResponseBytes: LiveWorkoutPayloadParser.maximumResponseBytes,
            parser: LiveWorkoutPayloadParser.inbox
        )
    }

    func sendInvite(
        profileID: String,
        clientRequestID: UUID,
        plan: SharedWorkoutPlan,
        expectedUserID: String? = nil
    ) async throws -> LiveWorkoutSendResult {
        guard Self.matches(profileID, pattern: Self.profilePattern) else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        return try await perform(
            action: "live_send_invite",
            payload: [
                "profileId": profileID,
                "clientRequestId": clientRequestID.uuidString.lowercased(),
                "workout": try LiveWorkoutPayloadParser.workoutObject(for: plan)
            ],
            expectedUserID: expectedUserID,
            maximumResponseBytes: LiveWorkoutPayloadParser.maximumMutationResponseBytes,
            parser: LiveWorkoutPayloadParser.sendResult
        )
    }

    func respondInvite(
        roomID: String,
        decision: String,
        expectedRoomRevision: Int,
        clientOperationID: UUID,
        expectedUserID: String? = nil
    ) async throws -> LiveWorkoutRespondResult {
        guard Self.matches(roomID, pattern: Self.roomPattern),
              decision == "accept" || decision == "decline",
              Self.validRevision(expectedRoomRevision) else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let result = try await perform(
            action: "live_respond_invite",
            payload: [
                "roomId": roomID,
                "decision": decision,
                "expectedRoomRevision": expectedRoomRevision,
                "clientOperationId": clientOperationID.uuidString.lowercased()
            ],
            expectedUserID: expectedUserID,
            maximumResponseBytes: LiveWorkoutPayloadParser.maximumMutationResponseBytes,
            parser: LiveWorkoutPayloadParser.respondResult
        )
        guard result.roomID == roomID else { throw LiveWorkoutGatewayError.invalidResponse }
        return result
    }

    func start(
        roomID: String,
        expectedRoomRevision: Int,
        clientOperationID: UUID,
        expectedUserID: String? = nil
    ) async throws -> LiveWorkoutStartResult {
        guard Self.matches(roomID, pattern: Self.roomPattern),
              Self.validRevision(expectedRoomRevision) else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let result = try await perform(
            action: "live_start",
            payload: [
                "roomId": roomID,
                "expectedRoomRevision": expectedRoomRevision,
                "clientOperationId": clientOperationID.uuidString.lowercased()
            ],
            expectedUserID: expectedUserID,
            maximumResponseBytes: LiveWorkoutPayloadParser.maximumMutationResponseBytes,
            parser: LiveWorkoutPayloadParser.startResult
        )
        guard result.roomID == roomID else { throw LiveWorkoutGatewayError.invalidResponse }
        return result
    }

    func snapshot(
        roomID: String,
        expectedUserID: String? = nil
    ) async throws -> LiveWorkoutSnapshot {
        guard Self.matches(roomID, pattern: Self.roomPattern) else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let result = try await perform(
            action: "live_snapshot",
            payload: ["roomId": roomID],
            expectedUserID: expectedUserID,
            maximumResponseBytes: LiveWorkoutPayloadParser.maximumResponseBytes,
            parser: LiveWorkoutPayloadParser.snapshot
        )
        guard result.room.roomID == roomID else { throw LiveWorkoutGatewayError.invalidResponse }
        return result
    }

    func apply(
        roomID: String,
        clientOperationID: UUID,
        expectedProgressRevision: Int,
        kind: String,
        setID: String,
        weight: Double? = nil,
        reps: Int? = nil,
        expectedUserID: String? = nil
    ) async throws -> LiveWorkoutApplyResult {
        guard Self.matches(roomID, pattern: Self.roomPattern),
              Self.validRevision(expectedProgressRevision),
              Self.matches(setID, pattern: Self.setPattern),
              kind == "complete_set" || kind == "undo_set" else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let operation: [String: Any]
        if kind == "complete_set" {
            guard let weight, weight.isFinite, (0 ... 1_000_000).contains(weight),
                  let reps, (1 ... 10_000).contains(reps) else {
                throw LiveWorkoutGatewayError.invalidRequest
            }
            operation = ["kind": kind, "setId": setID, "weight": weight, "reps": reps]
        } else {
            guard weight == nil, reps == nil else { throw LiveWorkoutGatewayError.invalidRequest }
            operation = ["kind": kind, "setId": setID]
        }
        let result = try await perform(
            action: "live_apply",
            payload: [
                "roomId": roomID,
                "clientOperationId": clientOperationID.uuidString.lowercased(),
                "expectedProgressRevision": expectedProgressRevision,
                "operation": operation
            ],
            expectedUserID: expectedUserID,
            maximumResponseBytes: LiveWorkoutPayloadParser.maximumMutationResponseBytes,
            parser: LiveWorkoutPayloadParser.applyResult
        )
        guard result.roomID == roomID, result.kind == kind, result.setID == setID else {
            throw LiveWorkoutGatewayError.invalidResponse
        }
        return result
    }

    func finish(
        roomID: String,
        clientOperationID: UUID,
        expectedProgressRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> LiveWorkoutFinishResult {
        guard Self.matches(roomID, pattern: Self.roomPattern),
              Self.validRevision(expectedProgressRevision) else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let result = try await perform(
            action: "live_finish",
            payload: [
                "roomId": roomID,
                "clientOperationId": clientOperationID.uuidString.lowercased(),
                "expectedProgressRevision": expectedProgressRevision
            ],
            expectedUserID: expectedUserID,
            maximumResponseBytes: LiveWorkoutPayloadParser.maximumMutationResponseBytes,
            parser: LiveWorkoutPayloadParser.finishResult
        )
        guard result.roomID == roomID else { throw LiveWorkoutGatewayError.invalidResponse }
        return result
    }

    func leave(
        roomID: String,
        clientOperationID: UUID,
        expectedMembershipRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> LiveWorkoutTerminalResult {
        try await terminalAction(
            action: "live_leave",
            expectedResult: "left",
            roomID: roomID,
            clientOperationID: clientOperationID,
            revisionKey: "expectedMembershipRevision",
            revision: expectedMembershipRevision,
            expectedUserID: expectedUserID
        )
    }

    func cancel(
        roomID: String,
        clientOperationID: UUID,
        expectedRoomRevision: Int,
        expectedUserID: String? = nil
    ) async throws -> LiveWorkoutTerminalResult {
        try await terminalAction(
            action: "live_cancel",
            expectedResult: "cancelled",
            roomID: roomID,
            clientOperationID: clientOperationID,
            revisionKey: "expectedRoomRevision",
            revision: expectedRoomRevision,
            expectedUserID: expectedUserID
        )
    }

    private func terminalAction(
        action: String,
        expectedResult: String,
        roomID: String,
        clientOperationID: UUID,
        revisionKey: String,
        revision: Int,
        expectedUserID: String?
    ) async throws -> LiveWorkoutTerminalResult {
        guard Self.matches(roomID, pattern: Self.roomPattern), Self.validRevision(revision) else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let result = try await perform(
            action: action,
            payload: [
                "roomId": roomID,
                "clientOperationId": clientOperationID.uuidString.lowercased(),
                revisionKey: revision
            ],
            expectedUserID: expectedUserID,
            maximumResponseBytes: LiveWorkoutPayloadParser.maximumMutationResponseBytes,
            parser: { try LiveWorkoutPayloadParser.terminalResult(from: $0, expectedResult: expectedResult) }
        )
        guard result.roomID == roomID else { throw LiveWorkoutGatewayError.invalidResponse }
        return result
    }

    private func perform<T>(
        action: String,
        payload: [String: Any],
        expectedUserID: String?,
        maximumResponseBytes: Int,
        parser: (Data) throws -> T
    ) async throws -> T {
        guard Self.allowedActions.contains(action), JSONSerialization.isValidJSONObject(payload) else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let generation = operationGeneration
        let initial = try await auth.validCloudSession(expectedUserID: expectedUserID)
        let userID = expectedUserID ?? initial.userID
        guard initial.userID == userID else { throw AuthServiceError.sessionChanged }

        let data: Data
        do {
            data = try await requestOnce(
                action: action,
                payload: payload,
                token: initial.accessToken,
                maximumResponseBytes: maximumResponseBytes
            )
        } catch RequestFailure.http(let status, _, _) where status == 401 || status == 403 {
            guard auth.session?.cloud == initial else { throw AuthServiceError.sessionChanged }
            let refreshed = try await auth.validCloudSession(
                expectedUserID: userID,
                forceRefresh: true
            )
            do {
                data = try await requestOnce(
                    action: action,
                    payload: payload,
                    token: refreshed.accessToken,
                    maximumResponseBytes: maximumResponseBytes
                )
            } catch let failure as RequestFailure {
                throw Self.publicError(failure)
            }
        } catch let failure as RequestFailure {
            throw Self.publicError(failure)
        }
        guard operationGeneration == generation,
              auth.session?.cloud?.userID == userID else {
            throw AuthServiceError.sessionChanged
        }
        do {
            return try parser(LiveWorkoutPayloadParser.gatewayResultData(from: data))
        } catch let error as LiveWorkoutGatewayError {
            throw error
        } catch {
            throw LiveWorkoutGatewayError.invalidResponse
        }
    }

    private func requestOnce(
        action: String,
        payload: [String: Any],
        token: String,
        maximumResponseBytes: Int
    ) async throws -> Data {
        guard !token.isEmpty,
              token.utf8.prefix(Self.maximumTokenBytes + 1).count <= Self.maximumTokenBytes,
              token.unicodeScalars.allSatisfy({ (0x21 ... 0x7e).contains($0.value) }),
              let url = URL(
                string: "/functions/v1/social-live-gateway",
                relativeTo: GymAppConfiguration.supabaseURL
              ) else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        let envelope: [String: Any] = ["version": 1, "action": action, "payload": payload]
        let encoded = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        guard encoded.count <= LiveWorkoutPayloadParser.maximumRequestBytes else {
            throw LiveWorkoutGatewayError.invalidRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue(GymAppConfiguration.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = encoded

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await BoundedURLSessionLoader.data(
                for: request,
                using: urlSession,
                successLimit: maximumResponseBytes,
                errorLimit: Self.maximumErrorBytes
            )
        } catch BoundedURLSessionError.responseTooLarge(let status?) {
            throw RequestFailure.http(status: status, code: nil, retryAfter: nil)
        } catch is BoundedURLSessionError {
            throw LiveWorkoutGatewayError.serviceUnavailable
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = object?["error"] as? String
            let retryAfter = Self.boundedRetryAfter(
                object?["retryAfter"] ?? response.value(forHTTPHeaderField: "Retry-After")
            )
            throw RequestFailure.http(
                status: response.statusCode,
                code: code,
                retryAfter: retryAfter
            )
        }
        return data
    }

    private static func publicError(_ failure: RequestFailure) -> LiveWorkoutGatewayError {
        switch failure {
        case .http(let status, _, let retryAfter):
            switch status {
            case 400: return .invalidRequest
            case 404: return .resourceUnavailable
            case 409: return .conflict
            case 429: return .rateLimited(retryAfter: retryAfter ?? 60)
            default: return .serviceUnavailable
            }
        }
    }

    private static func boundedRetryAfter(_ value: Any?) -> Int? {
        let number: Int?
        if let int = value as? Int { number = int }
        else if let numberValue = value as? NSNumber,
                CFGetTypeID(numberValue) != CFBooleanGetTypeID() {
            number = numberValue.intValue
        } else if let string = value as? String { number = Int(string) }
        else { number = nil }
        guard let number, (1 ... 3_600).contains(number) else { return nil }
        return number
    }

    private static func validRevision(_ value: Int) -> Bool {
        (1 ... 2_147_483_647).contains(value)
    }

    private static func matches(_ value: String, pattern: NSRegularExpression) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return pattern.firstMatch(in: value, range: range)?.range == range
    }

    private static func verifiedSessionID(in accessToken: String) -> String? {
        guard accessToken.utf8.count <= maximumTokenBytes else { return nil }
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard base64.unicodeScalars.allSatisfy({ scalar in
            (0x41 ... 0x5A).contains(scalar.value) ||
                (0x61 ... 0x7A).contains(scalar.value) ||
                (0x30 ... 0x39).contains(scalar.value) ||
                scalar.value == 0x2B || scalar.value == 0x2F
        }) else { return nil }
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), data.count <= 8 * 1_024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["session_id"] as? String,
              matches(sessionID, pattern: uuidPattern) else {
            return nil
        }
        return sessionID.lowercased()
    }
}
