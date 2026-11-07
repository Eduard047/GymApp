import XCTest
@testable import GymApp

final class ActiveWorkoutDeepLinkTests: XCTestCase {
    func testLiveActivityWidgetURLIsRecognized() throws {
        for raw in [
            "com.setforge.gymapp.ios://active-workout",
            "com.setforge.gymapp.ios://active-workout/",
            "COM.SETFORGE.GYMAPP.IOS://Active-Workout"
        ] {
            let url = try XCTUnwrap(URL(string: raw), raw)
            XCTAssertTrue(ActiveWorkoutDeepLink.isActiveWorkoutURL(url), raw)
        }
    }

    func testOtherURLsAreNotTreatedAsActiveWorkout() throws {
        for raw in [
            "com.setforge.gymapp.ios://auth-callback",
            "com.setforge.gymapp.ios://active-workout/extra",
            "com.setforge.gymapp.ios://active-workout?x=1",
            "com.setforge.gymapp.ios://active-workout#frag",
            "com.setforge.gymapp.ios://user@active-workout",
            "com.setforge.gymapp.ios://active-workout:80",
            "https://active-workout",
            "other.scheme://active-workout",
            "com.setforge.gymapp.ios:active-workout"
        ] {
            let url = try XCTUnwrap(URL(string: raw), raw)
            XCTAssertFalse(ActiveWorkoutDeepLink.isActiveWorkoutURL(url), raw)
        }
    }

    func testWidgetURLMatchesTheHandler() {
        XCTAssertEqual(
            "\(ActiveWorkoutDeepLink.scheme)://\(ActiveWorkoutDeepLink.host)",
            "com.setforge.gymapp.ios://active-workout"
        )
    }

    func testPendingOpenRequestWaitsForDraftThenOpensOrDrops() {
        typealias D = ActiveWorkoutDeepLink
        XCTAssertEqual(D.pendingOpenAction(requestPending: false, hasDraft: true, timedOut: false), .none)
        XCTAssertEqual(D.pendingOpenAction(requestPending: true, hasDraft: false, timedOut: false), .wait)
        XCTAssertEqual(D.pendingOpenAction(requestPending: true, hasDraft: true, timedOut: false), .open)
        XCTAssertEqual(D.pendingOpenAction(requestPending: true, hasDraft: true, timedOut: true), .open)
        XCTAssertEqual(D.pendingOpenAction(requestPending: true, hasDraft: false, timedOut: true), .drop)
        XCTAssertEqual(D.pendingOpenTimeout, 4)
    }
}
