import Foundation
import XCTest
@testable import GymApp

@MainActor
final class CloudSyncDiagnosticsTests: XCTestCase {
    func testDiagnosticsDropUnknownCodeQueryAndRawErrorText() {
        let marker = "https://private.example/rest?user_id=synthetic-user&access_token=synthetic-token"
        let event = CloudSyncDiagnostics.makeEvent(
            operation: CloudSyncOperation.resolve(
                path: "/rest/v1/user_states?user_id=eq.synthetic-user&select=state",
                method: "GET"
            ),
            phase: .response,
            outcome: .failure,
            statusCode: 503,
            postgRESTCode: "unknown-code?query=\(marker)",
            error: CloudSyncError.requestFailed("raw server message: \(marker)")
        )

        XCTAssertEqual(event.operation, .workoutStateRead)
        XCTAssertEqual(event.statusCode, 503)
        XCTAssertNil(event.postgRESTCode)
        XCTAssertEqual(event.transport, .unknown)
        let rendered = String(describing: event)
        XCTAssertFalse(rendered.contains("unknown-code"))
        XCTAssertFalse(rendered.contains("synthetic-user"))
        XCTAssertFalse(rendered.contains("synthetic-token"))
        XCTAssertFalse(rendered.contains("raw server message"))
        XCTAssertFalse(rendered.contains("private.example"))
    }

    func testDiagnosticsKeepOnlyReviewedServerCodesAndBoundStatus() {
        let event = CloudSyncDiagnostics.makeEvent(
            operation: .friendDashboard,
            phase: .response,
            outcome: .failure,
            statusCode: 403,
            postgRESTCode: "42501",
            transportClass: .http
        )
        XCTAssertEqual(event.postgRESTCode, "42501")
        XCTAssertEqual(event.statusCode, 403)
        XCTAssertEqual(event.transport, .http)

        let invalidStatus = CloudSyncDiagnostics.makeEvent(
            operation: .friendDashboard,
            phase: .response,
            outcome: .failure,
            statusCode: 700,
            postgRESTCode: "P9999",
            transportClass: .http
        )
        XCTAssertNil(invalidStatus.statusCode)
        XCTAssertNil(invalidStatus.postgRESTCode)
    }

    func testPausedWriteGateRetainsOnlyBooleanState() {
        let gate = CloudSyncDiagnosticGate(
            accountReady: true,
            signingOut: false,
            storeMatches: false,
            cloudSessionMatches: true,
            writesAllowed: false
        )
        let event = CloudSyncDiagnostics.makeEvent(
            operation: .workoutStateWrite,
            phase: .gate,
            outcome: .paused,
            gate: gate
        )

        XCTAssertEqual(event.gate, gate)
        XCTAssertEqual(event.transport, .none)
        XCTAssertEqual(event.outcome, .paused)
    }

    func testHTTP200MalformedRemoteStateIsClassifiedAsDecode() async throws {
        let marker = "malformed-http-200"
        let (auth, urlSession, defaults, suiteName) = try makeCloudAuth(
            userID: "diagnostic-read-user",
            statusCode: 200,
            body: "{\"state\":\(marker)"
        )
        let cloud = CloudSyncService(auth: auth, urlSession: urlSession)
        let events = CloudSyncDiagnosticsEventCollector()
        CloudSyncDiagnostics.testObserver = { events.append($0) }
        defer {
            CloudSyncDiagnostics.testObserver = nil
            CloudSyncDiagnosticsURLProtocol.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }

        do {
            _ = try await cloud.loadRemoteState(expectedUserID: "diagnostic-read-user")
            XCTFail("Malformed HTTP 200 data must fail decoding.")
        } catch {
            let decodeEvent = try XCTUnwrap(
                events.snapshot().first {
                    $0.operation == .workoutStateRead && $0.phase == .decode
                }
            )
            XCTAssertEqual(decodeEvent.statusCode, 200)
            XCTAssertEqual(decodeEvent.transport, .decode)
            XCTAssertFalse(String(describing: events.snapshot()).contains(marker))
        }
    }

    func testHTTPFailureWithoutCodeKeepsStatusAndDropsRawMessage() async throws {
        let marker = "raw-http-message?user_id=diagnostic-user&token=diagnostic-token"
        let (auth, urlSession, defaults, suiteName) = try makeCloudAuth(
            userID: "diagnostic-failure-user",
            statusCode: 503,
            body: "{\"message\":\"\(marker)\"}"
        )
        let cloud = CloudSyncService(auth: auth, urlSession: urlSession)
        let events = CloudSyncDiagnosticsEventCollector()
        CloudSyncDiagnostics.testObserver = { events.append($0) }
        defer {
            CloudSyncDiagnostics.testObserver = nil
            CloudSyncDiagnosticsURLProtocol.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }

        do {
            _ = try await cloud.loadRemoteState(expectedUserID: "diagnostic-failure-user")
            XCTFail("HTTP 503 must fail the cloud read.")
        } catch CloudSyncError.requestFailed(let message) {
            XCTAssertEqual(message, marker)
            let responseEvent = try XCTUnwrap(
                events.snapshot().first {
                    $0.operation == .workoutStateRead && $0.phase == .response
                        && $0.outcome == .failure
                }
            )
            XCTAssertEqual(responseEvent.statusCode, 503)
            XCTAssertNil(responseEvent.postgRESTCode)
            XCTAssertEqual(responseEvent.transport, .http)
            XCTAssertFalse(String(describing: events.snapshot()).contains(marker))
        }
    }

    private func makeCloudAuth(
        userID: String,
        statusCode: Int,
        body: String
    ) throws -> (AuthService, URLSession, UserDefaults, String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudSyncDiagnosticsURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let suiteName = "CloudSyncDiagnosticsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let auth = AuthService(
            keychain: CloudSyncDiagnosticsKeychain(),
            urlSession: urlSession,
            defaults: defaults
        )
        try auth.installSessionForTesting(
            .cloud(
                CloudAccountSession(
                    userID: userID,
                    email: "\(userID)@example.test",
                    displayName: "Synthetic",
                    accessToken: "synthetic-access-token",
                    refreshToken: "synthetic-refresh-token",
                    expiresAt: Date().addingTimeInterval(3_600)
                )
            )
        )
        CloudSyncDiagnosticsURLProtocol.handler = { request in
            try CloudSyncDiagnosticsURLProtocol.response(
                for: request,
                statusCode: statusCode,
                body: body
            )
        }
        return (auth, urlSession, defaults, suiteName)
    }
}

private final class CloudSyncDiagnosticsEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CloudSyncDiagnosticEvent] = []

    func append(_ event: CloudSyncDiagnosticEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [CloudSyncDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private final class CloudSyncDiagnosticsKeychain: KeychainStoring {
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        values[account] = data
    }

    func read(account: String) throws -> Data? {
        values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }
}

private final class CloudSyncDiagnosticsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == GymAppConfiguration.supabaseURL.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func response(
        for request: URLRequest,
        statusCode: Int,
        body: String
    ) throws -> (HTTPURLResponse, Data) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            throw URLError(.badURL)
        }
        return (response, Data(body.utf8))
    }
}
