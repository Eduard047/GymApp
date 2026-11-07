import UIKit
import XCTest
@testable import GymApp

final class StartWorkoutShortcutTests: XCTestCase {
    private typealias S = StartWorkoutShortcut

    func testRoutingDecisionTable() {
        // No request pending.
        XCTAssertEqual(S.action(requestPending: false, hasAccount: true, hasDraft: true, age: 0), .none)
        // Signed out / no account: plain launch, request dropped.
        XCTAssertEqual(S.action(requestPending: true, hasAccount: false, hasDraft: false, age: 0), .drop)
        XCTAssertEqual(S.action(requestPending: true, hasAccount: false, hasDraft: true, age: 1), .drop)
        // Active draft: open it immediately.
        XCTAssertEqual(S.action(requestPending: true, hasAccount: true, hasDraft: true, age: 0), .openActiveWorkout)
        // No draft yet: settle, then open the plan editor.
        XCTAssertEqual(S.action(requestPending: true, hasAccount: true, hasDraft: false, age: 0.1), .wait)
        XCTAssertEqual(
            S.action(requestPending: true, hasAccount: true, hasDraft: false, age: S.settleDelay),
            .openWorkoutEditor
        )
        // Stale request is dropped even with an account.
        XCTAssertEqual(
            S.action(requestPending: true, hasAccount: true, hasDraft: true, age: S.pendingTimeout + 0.1),
            .drop
        )
    }

    func testOnlyTheStartWorkoutItemTypeIsRecognised() {
        XCTAssertTrue(S.isStartWorkout(UIApplicationShortcutItem(type: S.itemType, localizedTitle: "x")))
        XCTAssertFalse(S.isStartWorkout(UIApplicationShortcutItem(type: S.itemType + ".x", localizedTitle: "x")))
    }

    @MainActor
    func testHandleStashesAndConsumeClearsTheRequest() {
        S.consume()
        XCTAssertFalse(S.handle(UIApplicationShortcutItem(type: "other", localizedTitle: "x")))
        XCTAssertNil(S.pendingSince)
        XCTAssertTrue(S.handle(UIApplicationShortcutItem(type: S.itemType, localizedTitle: "x")))
        XCTAssertNotNil(S.pendingSince)
        S.consume()
        XCTAssertNil(S.pendingSince)
    }
}
