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

    func testOpenIsRequestedOnlyWithADraftOrAPreparingAccount() {
        typealias D = ActiveWorkoutDeepLink
        XCTAssertTrue(D.shouldRequestOpen(hasDraft: true, isPreparingAccount: false))
        XCTAssertTrue(D.shouldRequestOpen(hasDraft: false, isPreparingAccount: true))
        XCTAssertFalse(D.shouldRequestOpen(hasDraft: false, isPreparingAccount: false))
    }

    func testOnlyRestNotificationIdentifiersAreActiveWorkoutNotifications() {
        typealias D = ActiveWorkoutDeepLink
        XCTAssertTrue(D.isRestNotification(identifier: "gymapp.rest.abc.1f"))
        XCTAssertTrue(D.isRestNotification(identifier: "gymapp.rest.legacy"))
        XCTAssertFalse(D.isRestNotification(identifier: "gymapp.push.abc"))
        XCTAssertFalse(D.isRestNotification(identifier: "gymapp.rest"))
        XCTAssertFalse(D.isRestNotification(identifier: ""))
    }

    @MainActor
    func testNotificationTapIsConsumedOnceAndExpires() {
        typealias D = ActiveWorkoutDeepLink
        // A stash of its own, and no notification is posted: the tests run inside the real
        // app, whose live listener takes every tap from the shared stash.
        let stash = D.NotificationTapStash()
        let t0 = Date()
        XCTAssertFalse(stash.take(now: t0))
        stash.note(now: t0)
        XCTAssertTrue(stash.take(now: t0.addingTimeInterval(1)))
        XCTAssertFalse(stash.take(now: t0.addingTimeInterval(1)))
        stash.note(now: t0)
        XCTAssertFalse(stash.take(now: t0.addingTimeInterval(D.notificationTapTimeout + 1)))
        stash.note(now: t0)
        XCTAssertFalse(stash.take(now: t0.addingTimeInterval(-1)), "a tap dated after `now` is dropped")
        XCTAssertFalse(stash.take(now: t0), "a dropped tap is cleared too")
    }
}
