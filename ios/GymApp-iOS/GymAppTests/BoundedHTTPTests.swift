import Foundation
import XCTest
@testable import GymApp

@MainActor
final class BoundedHTTPTests: XCTestCase {
    func testLoaderRejectsUndeclaredBodyBeyondLimitWithoutTruncating() async throws {
        let session = makeURLSession()
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
        }
        BoundedHTTPURLProtocolStub.handler = { request in
            (
                try Self.response(for: request, statusCode: 200),
                [Data(repeating: 0x61, count: 65)]
            )
        }

        do {
            _ = try await BoundedURLSessionLoader.data(
                for: URLRequest(url: try endpoint("stream-overflow")),
                using: session,
                successLimit: 64,
                errorLimit: 16
            )
            XCTFail("An undeclared oversized body must be rejected, not truncated.")
        } catch BoundedURLSessionError.responseTooLarge(statusCode: 200) {
            // Expected.
        } catch {
            XCTFail("Unexpected bounded-loader error: \(error)")
        }
    }

    func testLoaderPrechecksContentLengthAgainstStatusSpecificErrorLimit() async throws {
        let session = makeURLSession()
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
        }
        BoundedHTTPURLProtocolStub.handler = { request in
            (
                try Self.response(
                    for: request,
                    statusCode: 400,
                    headers: ["Content-Length": "17"]
                ),
                [Data("{}".utf8)]
            )
        }

        do {
            _ = try await BoundedURLSessionLoader.data(
                for: URLRequest(url: try endpoint("declared-error-overflow")),
                using: session,
                successLimit: 64,
                errorLimit: 16
            )
            XCTFail("An error body must use the smaller error-response limit.")
        } catch BoundedURLSessionError.responseTooLarge(statusCode: 400) {
            // Expected.
        } catch {
            XCTFail("Unexpected bounded-loader error: \(error)")
        }
    }

    func testLoaderPreservesLegitimateBodyAtExactLimit() async throws {
        let session = makeURLSession()
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
        }
        let expected = Data(repeating: 0x62, count: 64)
        BoundedHTTPURLProtocolStub.handler = { request in
            (
                try Self.response(
                    for: request,
                    statusCode: 200,
                    headers: ["Content-Length": "64"]
                ),
                [expected.prefix(31), expected.dropFirst(31)]
            )
        }

        let (data, response) = try await BoundedURLSessionLoader.data(
            for: URLRequest(url: try endpoint("exact-limit")),
            using: session,
            successLimit: 64,
            errorLimit: 16
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(data, expected)
    }

    func testLoaderCancellationStopsTheChildDataTask() async throws {
        let started = expectation(description: "URLProtocol request started")
        let taskCompletion = BoundedHTTPTaskCompletionRecorder()
        let session = makeURLSession()
        BoundedHTTPURLProtocolStub.stallHandler = { _ in
            started.fulfill()
            return true
        }
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
        }

        let pending = Task {
            try await BoundedURLSessionLoader.data(
                for: URLRequest(url: try endpoint("cancel")),
                using: session,
                successLimit: 64,
                errorLimit: 16,
                taskCompletionObserver: { state, wasCancelled in
                    taskCompletion.record(state: state, wasCancelled: wasCancelled)
                }
            )
        }
        await fulfillment(of: [started], timeout: 2)
        pending.cancel()

        do {
            _ = try await pending.value
            XCTFail("A cancelled caller must not receive a late response.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Cancellation must surface as CancellationError, got: \(error)")
        }
        let completion = try XCTUnwrap(taskCompletion.snapshot)
        XCTAssertEqual(completion.state, .completed)
        XCTAssertTrue(
            completion.wasCancelled,
            "The child data task must complete with NSURLErrorCancelled."
        )
    }

    func testLoaderAllowsOnlySameOriginHTTPSRedirect() async throws {
        let session = makeURLSession()
        let recorder = BoundedHTTPRequestRecorder()
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
        }
        BoundedHTTPURLProtocolStub.redirectHandler = { request in
            recorder.append(request)
            guard request.url?.path == "/same-origin-start" else { return nil }
            let destination = try XCTUnwrap(
                URL(string: "https://owrcbsrectdgaotndtxy.supabase.co/same-origin-finish")
            )
            return (
                URLRequest(url: destination),
                try Self.response(
                    for: request,
                    statusCode: 302,
                    headers: ["Location": destination.absoluteString]
                )
            )
        }
        BoundedHTTPURLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/same-origin-finish")
            return (try Self.response(for: request, statusCode: 200), [Data("ok".utf8)])
        }

        let (data, response) = try await BoundedURLSessionLoader.data(
            for: URLRequest(url: try endpoint("same-origin-start")),
            using: session,
            successLimit: 64,
            errorLimit: 16
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(data, Data("ok".utf8))
        XCTAssertEqual(recorder.requests.compactMap(\.url?.path), [
            "/same-origin-start",
            "/same-origin-finish"
        ])
    }

    func testLoaderRejectsCrossOriginAndHTTPSDowngradeRedirects() async throws {
        for (name, destination) in [
            ("cross-origin", "https://attacker.invalid/stolen"),
            ("downgrade", "http://owrcbsrectdgaotndtxy.supabase.co/stolen")
        ] {
            let session = makeURLSession()
            let recorder = BoundedHTTPRequestRecorder()
            BoundedHTTPURLProtocolStub.redirectHandler = { request in
                recorder.append(request)
                guard request.url?.path == "/\(name)-start" else { return nil }
                let destinationURL = try XCTUnwrap(URL(string: destination))
                return (
                    URLRequest(url: destinationURL),
                    try Self.response(
                        for: request,
                        statusCode: 302,
                        headers: ["Location": destination]
                    )
                )
            }
            BoundedHTTPURLProtocolStub.handler = { request in
                XCTFail("Unsafe redirect was followed to \(request.url?.absoluteString ?? "unknown").")
                return (try Self.response(for: request, statusCode: 200), [Data("unsafe".utf8)])
            }
            defer {
                BoundedHTTPURLProtocolStub.reset()
                session.invalidateAndCancel()
            }

            do {
                _ = try await BoundedURLSessionLoader.data(
                    for: URLRequest(url: try endpoint("\(name)-start")),
                    using: session,
                    successLimit: 64,
                    errorLimit: 16
                )
                XCTFail("An unsafe redirect must fail instead of becoming a final response.")
            } catch BoundedURLSessionError.invalidResponse {
                // Expected.
            } catch {
                XCTFail("Unexpected unsafe-redirect error: \(error)")
            }
            XCTAssertEqual(recorder.requests.count, 1)
        }
    }

    func testLoaderRejectsNonHTTPSInitialRequestBeforeNetwork() async throws {
        let session = makeURLSession()
        let recorder = BoundedHTTPRequestRecorder()
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
        }
        BoundedHTTPURLProtocolStub.handler = { request in
            recorder.append(request)
            return (try Self.response(for: request, statusCode: 200), [Data("unsafe".utf8)])
        }
        let insecureURL = try XCTUnwrap(
            URL(string: "http://owrcbsrectdgaotndtxy.supabase.co/insecure")
        )

        do {
            _ = try await BoundedURLSessionLoader.data(
                for: URLRequest(url: insecureURL),
                using: session,
                successLimit: 64,
                errorLimit: 16
            )
            XCTFail("An initial non-HTTPS request must be rejected.")
        } catch BoundedURLSessionError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected initial-origin error: \(error)")
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testAuthRejectsDeclaredResponseAbove64KiB() async throws {
        let session = makeURLSession()
        let keychain = BoundedHTTPKeychainStore()
        let auth = makeAuth(keychain: keychain, session: session, name: "auth-response-cap")
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
            try? auth.clearSession()
        }
        let validSession = try Self.authSessionResponse()
        BoundedHTTPURLProtocolStub.handler = { request in
            (
                try Self.response(
                    for: request,
                    statusCode: 200,
                    headers: ["Content-Length": String(64 * 1_024 + 1)]
                ),
                [validSession]
            )
        }

        await auth.signIn(email: "bounded@example.com", password: "Password1")

        XCTAssertNil(auth.session)
        XCTAssertNil(try keychain.read(account: "current-session"))
        XCTAssertEqual(auth.message, AuthServiceError.malformedResponse.errorDescription)
    }

    func testAuthRejectsReturnedTokenBeyond16KiB() async throws {
        let session = makeURLSession()
        let keychain = BoundedHTTPKeychainStore()
        let auth = makeAuth(keychain: keychain, session: session, name: "auth-token-cap")
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
            try? auth.clearSession()
        }
        let oversizedToken = String(repeating: "t", count: 16 * 1_024 + 1)
        let responseData = try Self.authSessionResponse(accessToken: oversizedToken)
        BoundedHTTPURLProtocolStub.handler = { request in
            (try Self.response(for: request, statusCode: 200), [responseData])
        }

        await auth.signIn(email: "bounded@example.com", password: "Password1")

        XCTAssertNil(auth.session)
        XCTAssertNil(try keychain.read(account: "current-session"))
        XCTAssertEqual(auth.message, AuthServiceError.malformedResponse.errorDescription)
    }

    func testAuthRejectsOversizedCallbackRequestBeforeSecondNetworkCall() async throws {
        let session = makeURLSession()
        let keychain = BoundedHTTPKeychainStore()
        let recorder = BoundedHTTPRequestRecorder()
        let auth = makeAuth(keychain: keychain, session: session, name: "auth-request-cap")
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
            try? auth.clearSession()
        }
        BoundedHTTPURLProtocolStub.handler = { request in
            recorder.append(request)
            return (try Self.response(for: request, statusCode: 200), [Data("{}".utf8)])
        }

        await auth.requestPasswordReset(email: "bounded@example.com")
        let transactionData = try XCTUnwrap(keychain.read(account: "pending-auth-transaction"))
        let transaction = try XCTUnwrap(
            JSONSerialization.jsonObject(with: transactionData) as? [String: Any]
        )
        let state = try XCTUnwrap(transaction["state"] as? String)
        let oversizedPadding = String(repeating: "a", count: 8 * 1_024 + 1)
        let callback = try XCTUnwrap(
            URL(
                string: "com.setforge.gymapp.ios://auth/callback/\(state)?code=test-auth-code&padding=\(oversizedPadding)"
            )
        )
        XCTAssertGreaterThan(callback.absoluteString.utf8.count, 8 * 1_024)

        await auth.handleOpenURL(callback)

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertNil(auth.session)
        XCTAssertEqual(auth.message, AuthServiceError.malformedResponse.errorDescription)
        XCTAssertEqual(try keychain.read(account: "pending-auth-transaction"), transactionData)
    }

    func testCloudStateAllowsSmallResponseThroughClonedSessionConfiguration() async throws {
        let session = makeURLSession()
        let auth = makeAuthenticatedAuth(session: session, name: "cloud-small-response")
        let cloud = CloudSyncService(auth: auth, urlSession: session)
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
            try? auth.clearSession()
        }
        let responseData = Data(
            #"[{"state":{"schemaVersion":2},"updated_at":"2026-07-14T12:00:00.000Z"}]"#.utf8
        )
        BoundedHTTPURLProtocolStub.handler = { request in
            (try Self.response(for: request, statusCode: 200), [responseData])
        }

        let loadedState = try await cloud.loadRemoteState(expectedUserID: "bounded-user")
        let stateData = try XCTUnwrap(loadedState)
        let state = try XCTUnwrap(
            JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        )

        XCTAssertEqual((state["schemaVersion"] as? NSNumber)?.intValue, 2)
    }

    func testCloudStateRejectsDeclaredResponseAbove10MiB() async throws {
        let session = makeURLSession()
        let auth = makeAuthenticatedAuth(session: session, name: "cloud-response-cap")
        let cloud = CloudSyncService(auth: auth, urlSession: session)
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
            try? auth.clearSession()
        }
        BoundedHTTPURLProtocolStub.handler = { request in
            (
                try Self.response(
                    for: request,
                    statusCode: 200,
                    headers: ["Content-Length": String(10 * 1_024 * 1_024 + 1)]
                ),
                [Data("[]".utf8)]
            )
        }

        do {
            _ = try await cloud.loadRemoteState(expectedUserID: "bounded-user")
            XCTFail("A cloud-state response above the route cap must be rejected.")
        } catch CloudSyncError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected cloud response-cap error: \(error)")
        }
    }

    func testCloudRejectsBackupBeyond8MiBBeforeNetworkOrParsing() async throws {
        let session = makeURLSession()
        let recorder = BoundedHTTPRequestRecorder()
        let auth = makeAuthenticatedAuth(session: session, name: "cloud-request-cap")
        let cloud = CloudSyncService(auth: auth, urlSession: session)
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
            try? auth.clearSession()
        }
        BoundedHTTPURLProtocolStub.handler = { request in
            recorder.append(request)
            return (try Self.response(for: request, statusCode: 200), [Data("[]".utf8)])
        }
        var oversizedObject = Data(#"{"padding":""#.utf8)
        oversizedObject.append(Data(repeating: 0x61, count: 8 * 1_024 * 1_024))
        oversizedObject.append(Data(#""}"#.utf8))

        do {
            try await cloud.saveRemoteState(
                backupData: oversizedObject,
                xp: 0,
                level: 1,
                workouts: 0,
                expectedUserID: "bounded-user"
            )
            XCTFail("A cloud request above the backup contract must be rejected.")
        } catch CloudSyncError.invalidPayload {
            // Expected.
        } catch {
            XCTFail("Unexpected cloud request-cap error: \(error)")
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testStoredOversizedBearerCannotReachCloudRequest() async throws {
        let session = makeURLSession()
        let recorder = BoundedHTTPRequestRecorder()
        let keychain = BoundedHTTPKeychainStore()
        let auth = makeAuth(keychain: keychain, session: session, name: "stored-token-cap")
        let cloud = CloudSyncService(auth: auth, urlSession: session)
        defer {
            BoundedHTTPURLProtocolStub.reset()
            session.invalidateAndCancel()
            try? auth.clearSession()
        }
        try auth.installSessionForTesting(
            .cloud(
                CloudAccountSession(
                    userID: "bounded-user",
                    email: "bounded@example.com",
                    displayName: "Bounded",
                    accessToken: String(repeating: "x", count: 16 * 1_024 + 1),
                    refreshToken: "refresh-token",
                    expiresAt: Date().addingTimeInterval(3_600)
                )
            )
        )
        BoundedHTTPURLProtocolStub.handler = { request in
            recorder.append(request)
            return (try Self.response(for: request, statusCode: 200), [Data("[]".utf8)])
        }

        do {
            _ = try await cloud.loadRemoteState(expectedUserID: "bounded-user")
            XCTFail("An oversized stored bearer token must not become an HTTP header.")
        } catch AuthServiceError.malformedResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected stored-token error: \(error)")
        }
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    private func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedHTTPURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeAuth(
        keychain: BoundedHTTPKeychainStore,
        session: URLSession,
        name: String
    ) -> AuthService {
        let suiteName = "GymAppTests.BoundedHTTP.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return AuthService(keychain: keychain, urlSession: session, defaults: defaults)
    }

    private func makeAuthenticatedAuth(session: URLSession, name: String) -> AuthService {
        let auth = makeAuth(
            keychain: BoundedHTTPKeychainStore(),
            session: session,
            name: name
        )
        try! auth.installSessionForTesting(
            .cloud(
                CloudAccountSession(
                    userID: "bounded-user",
                    email: "bounded@example.com",
                    displayName: "Bounded",
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date().addingTimeInterval(3_600)
                )
            )
        )
        return auth
    }

    private func endpoint(_ path: String) throws -> URL {
        try XCTUnwrap(URL(string: "https://owrcbsrectdgaotndtxy.supabase.co/\(path)"))
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int,
        headers: [String: String] = [:]
    ) throws -> HTTPURLResponse {
        var responseHeaders = headers
        responseHeaders["Content-Type"] = "application/json"
        return try XCTUnwrap(
            HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: responseHeaders
            )
        )
    }

    private static func authSessionResponse(
        accessToken: String = "access-token"
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "access_token": accessToken,
            "refresh_token": "refresh-token",
            "expires_in": 3_600,
            "user": [
                "id": "bounded-user",
                "email": "bounded@example.com",
                "user_metadata": ["display_name": "Bounded"]
            ]
        ])
    }
}

private final class BoundedHTTPURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, [Data]))?
    nonisolated(unsafe) static var redirectHandler: (
        (URLRequest) throws -> (URLRequest, HTTPURLResponse)?
    )?
    nonisolated(unsafe) static var stallHandler: ((URLRequest) -> Bool)?

    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let materializedRequest = try Self.materializedRequest(request)
            if Self.stallHandler?(materializedRequest) == true { return }
            if let (redirect, response) = try Self.redirectHandler?(materializedRequest) {
                client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
                return
            }
            guard let handler = Self.handler else {
                throw URLError(.unsupportedURL)
            }
            let (response, chunks) = try handler(materializedRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        handler = nil
        redirectHandler = nil
        stallHandler = nil
    }

    private static func materializedRequest(_ request: URLRequest) throws -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }

        var result = request
        result.httpBodyStream = nil
        result.httpBody = data
        return result
    }
}

private final class BoundedHTTPKeychainStore: KeychainStoring {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        lock.lock()
        values[account] = data
        lock.unlock()
    }

    func read(account: String) throws -> Data? {
        lock.lock()
        let value = values[account]
        lock.unlock()
        return value
    }

    func delete(account: String) throws {
        lock.lock()
        values.removeValue(forKey: account)
        lock.unlock()
    }
}

private final class BoundedHTTPRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        let value = storedRequests
        lock.unlock()
        return value
    }

    func append(_ request: URLRequest) {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
    }
}

private struct BoundedHTTPTaskCompletionSnapshot {
    let state: URLSessionTask.State
    let wasCancelled: Bool
}

private final class BoundedHTTPTaskCompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshot: BoundedHTTPTaskCompletionSnapshot?

    var snapshot: BoundedHTTPTaskCompletionSnapshot? {
        lock.lock()
        let value = storedSnapshot
        lock.unlock()
        return value
    }

    func record(state: URLSessionTask.State, wasCancelled: Bool) {
        lock.lock()
        storedSnapshot = BoundedHTTPTaskCompletionSnapshot(
            state: state,
            wasCancelled: wasCancelled
        )
        lock.unlock()
    }
}
