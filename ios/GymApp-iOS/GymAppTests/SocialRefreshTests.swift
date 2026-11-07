import XCTest
@testable import GymApp

@MainActor
final class SocialRefreshTests: XCTestCase {
    private struct OtherError: Error {}

    func testOfflineURLErrorsMapToConnectionCopy() {
        for code: URLError.Code in [.notConnectedToInternet, .timedOut, .networkConnectionLost,
                                    .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed] {
            XCTAssertEqual(socialErrorKind(for: URLError(code), sessionEnded: false), .connection)
        }
    }

    func testEndedSessionWinsOverConnectionError() {
        XCTAssertEqual(
            socialErrorKind(for: URLError(.notConnectedToInternet), sessionEnded: true),
            .sessionEnded
        )
    }

    func testOtherErrorsKeepScreenFallback() {
        XCTAssertEqual(socialErrorKind(for: OtherError(), sessionEnded: false), .other)
        XCTAssertEqual(socialErrorKind(for: URLError(.cancelled), sessionEnded: false), .other)
        XCTAssertEqual(socialErrorKind(for: URLError(.badServerResponse), sessionEnded: false), .other)
    }

    func testIdleBeginRunsAndSecondBeginIsDropped() {
        var c = SocialRefreshCoalescer()
        XCTAssertTrue(c.begin(force: false))
        XCTAssertFalse(c.begin(force: false))
        XCTAssertFalse(c.hasPendingForced)
        XCTAssertFalse(c.finish())
        XCTAssertFalse(c.isRunning)
    }

    func testForcedRequestDuringRefreshRunsExactlyOneMoreRefresh() {
        var c = SocialRefreshCoalescer()
        XCTAssertTrue(c.begin(force: false))
        XCTAssertFalse(c.begin(force: true))
        XCTAssertFalse(c.begin(force: true))
        XCTAssertFalse(c.begin(force: true))
        XCTAssertTrue(c.finish())
        XCTAssertTrue(c.isRunning)
        XCTAssertFalse(c.finish())
        XCTAssertFalse(c.isRunning)
        XCTAssertTrue(c.begin(force: false))
    }

    func testResetClearsPendingAndRunning() {
        var c = SocialRefreshCoalescer()
        _ = c.begin(force: false)
        _ = c.begin(force: true)
        c.reset()
        XCTAssertEqual(c, SocialRefreshCoalescer())
    }
}
