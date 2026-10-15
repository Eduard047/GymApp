import XCTest
@testable import GymApp

final class GymToastTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testPolicyDurations() {
        XCTAssertEqual(GymToastPolicy.duration(hasAction: false, isError: false), 4)
        XCTAssertEqual(GymToastPolicy.duration(hasAction: true, isError: false), 6)
        XCTAssertEqual(GymToastPolicy.duration(hasAction: false, isError: true), 6)
        let action = GymToast.Action(title: "Undo") {}
        XCTAssertEqual(GymToast(message: "A", action: action).duration, 6)
        XCTAssertEqual(GymToast(message: "A", duration: 9).duration, 9)
    }

    func testNewToastReplacesCurrentAndNeverStacks() {
        var queue = GymToastQueue()
        let first = GymToast(message: "First")
        let second = GymToast(message: "Second")
        XCTAssertNil(queue.show(first, at: t0))
        XCTAssertEqual(queue.show(second, at: t0.addingTimeInterval(1)), first.id)
        XCTAssertEqual(queue.current?.message, "Second")
        // The countdown restarts for the replacement.
        XCTAssertEqual(queue.timeUntilExpiry(at: t0.addingTimeInterval(1)), 4)
    }

    func testExpiresAfterDuration() {
        var queue = GymToastQueue()
        queue.show(GymToast(message: "A"), at: t0)
        XCTAssertFalse(queue.expireIfDue(at: t0.addingTimeInterval(3.9)))
        XCTAssertNotNil(queue.current)
        XCTAssertTrue(queue.expireIfDue(at: t0.addingTimeInterval(4)))
        XCTAssertNil(queue.current)
    }

    func testPauseHoldsCountdownAndResumeContinuesFromRemaining() {
        var queue = GymToastQueue()
        queue.show(GymToast(message: "A"), at: t0)
        queue.setPaused(.interaction, active: true, at: t0.addingTimeInterval(3))
        XCTAssertNil(queue.timeUntilExpiry(at: t0.addingTimeInterval(3)))
        XCTAssertFalse(queue.expireIfDue(at: t0.addingTimeInterval(60)))
        queue.setPaused(.interaction, active: false, at: t0.addingTimeInterval(60))
        XCTAssertEqual(queue.timeUntilExpiry(at: t0.addingTimeInterval(60)) ?? -1, 1, accuracy: 0.001)
        XCTAssertTrue(queue.expireIfDue(at: t0.addingTimeInterval(61)))
    }

    func testEveryPauseReasonMustBeReleased() {
        var queue = GymToastQueue()
        queue.show(GymToast(message: "A"), at: t0)
        queue.setPaused(.interaction, active: true, at: t0)
        queue.setPaused(.assistiveFocus, active: true, at: t0)
        queue.setPaused(.interaction, active: false, at: t0.addingTimeInterval(1))
        XCTAssertTrue(queue.isPaused)
        XCTAssertNil(queue.timeUntilExpiry(at: t0.addingTimeInterval(2)))
        queue.setPaused(.assistiveFocus, active: false, at: t0.addingTimeInterval(2))
        XCTAssertEqual(queue.timeUntilExpiry(at: t0.addingTimeInterval(2)) ?? -1, 4, accuracy: 0.001)
    }

    func testReplacementClearsPauseAndStaleDismissIsIgnored() {
        var queue = GymToastQueue()
        let first = GymToast(message: "First")
        queue.show(first, at: t0)
        queue.setPaused(.assistiveFocus, active: true, at: t0)
        queue.show(GymToast(message: "Second"), at: t0)
        XCTAssertFalse(queue.isPaused)
        XCTAssertFalse(queue.dismiss(id: first.id))
        XCTAssertEqual(queue.current?.message, "Second")
        XCTAssertTrue(queue.dismiss())
        XCTAssertNil(queue.current)
    }

    func testTopmostPresentationHostDrawsTheToast() {
        var stack = GymToastHostStack()
        let sheet = GymToastHostID.presentation(UUID())
        let nested = GymToastHostID.presentation(UUID())
        XCTAssertNil(stack.activeHost)
        stack.register(.root)
        XCTAssertEqual(stack.activeHost, .root)
        stack.register(sheet)
        stack.register(nested)
        XCTAssertEqual(stack.activeHost, nested)
        stack.unregister(nested)
        XCTAssertEqual(stack.activeHost, sheet)
        stack.unregister(sheet)
        XCTAssertEqual(stack.activeHost, .root)
    }

    @MainActor
    func testCenterAnnouncesReplacesAndActionDismisses() {
        var announced: [String] = []
        let center = GymToastCenter(announcer: { announced.append($0) })
        center.show("One")
        center.show("Two", kind: .error)
        XCTAssertEqual(announced, ["One", "Two"])
        XCTAssertEqual(center.current?.message, "Two")

        var undone = false
        center.show("Deleted", action: .init(title: "Undo") { undone = true })
        let toast = try! XCTUnwrap(center.current)
        center.performAction(of: toast)
        XCTAssertTrue(undone)
        XCTAssertNil(center.current)

        center.show("   ")
        XCTAssertNil(center.current)
    }

    @MainActor
    func testCenterTimesOutAndPauseKeepsItVisible() async throws {
        let center = GymToastCenter(announcer: { _ in })
        center.show("Short", duration: 0.15)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertNil(center.current)

        center.show("Held", duration: 0.15)
        let id = try XCTUnwrap(center.current?.id)
        center.setPaused(.interaction, active: true, for: id)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(center.current?.message, "Held")
        center.setPaused(.interaction, active: false, for: id)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertNil(center.current)
    }

    func testSheetPresentationCarriesAToastHost() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GymApp/UI/Components/GymSheetPresentation.swift")
        let text = try String(contentsOf: root, encoding: .utf8)
        XCTAssertTrue(text.contains(".gymToastHost()"))
    }
}
