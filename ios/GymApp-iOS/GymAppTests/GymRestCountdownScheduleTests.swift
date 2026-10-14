import XCTest
@testable import GymApp

final class GymRestCountdownScheduleTests: XCTestCase {
    private let deadline = Date(timeIntervalSinceReferenceDate: 1_000)

    private func assertOffsets(
        _ actual: [TimeInterval],
        _ expected: [TimeInterval],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, "\(actual)", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: 0.000_001, file: file, line: line)
        }
    }

    func testTicksLandOnTheDeadlinesSecondBoundariesThenEndTheHighlight() {
        let start = deadline.addingTimeInterval(-3.3)
        let dates = GymRestCountdownSchedule.entryDates(deadline: deadline, from: start)
        let offsets = dates.map { $0.timeIntervalSince(deadline) }
        assertOffsets(offsets, [-3.3, -3, -2, -1, 0, 0.6])
    }

    func testStartOnABoundaryDoesNotRepeatIt() {
        let start = deadline.addingTimeInterval(-2)
        let offsets = GymRestCountdownSchedule.entryDates(deadline: deadline, from: start)
            .map { $0.timeIntervalSince(deadline) }
        assertOffsets(offsets, [-2, -1, 0, 0.6])
    }

    func testAfterTheHighlightThereIsNothingToWaitFor() {
        let start = deadline.addingTimeInterval(5)
        XCTAssertEqual(GymRestCountdownSchedule.entryDates(deadline: deadline, from: start), [start])
        let during = deadline.addingTimeInterval(0.2)
        let offsets = GymRestCountdownSchedule.entryDates(deadline: deadline, from: during)
            .map { $0.timeIntervalSince(deadline) }
        assertOffsets(offsets, [0.2, 0.6])
    }

    func testRemainingSecondsRoundUpAndStopAtZero() {
        XCTAssertEqual(GymRestCountdownSchedule.remainingSeconds(deadline: deadline, at: deadline.addingTimeInterval(-2.4)), 3)
        XCTAssertEqual(GymRestCountdownSchedule.remainingSeconds(deadline: deadline, at: deadline.addingTimeInterval(-1)), 1)
        XCTAssertEqual(GymRestCountdownSchedule.remainingSeconds(deadline: deadline, at: deadline), 0)
        XCTAssertEqual(GymRestCountdownSchedule.remainingSeconds(deadline: deadline, at: deadline.addingTimeInterval(9)), 0)
    }

    func testEndHighlightCoversTheFirstSixTenthsAfterTheDeadline() {
        XCTAssertFalse(GymRestCountdownSchedule.isEndHighlighted(deadline: deadline, at: deadline.addingTimeInterval(-0.1)))
        XCTAssertTrue(GymRestCountdownSchedule.isEndHighlighted(deadline: deadline, at: deadline))
        XCTAssertTrue(GymRestCountdownSchedule.isEndHighlighted(deadline: deadline, at: deadline.addingTimeInterval(0.59)))
        XCTAssertFalse(GymRestCountdownSchedule.isEndHighlighted(deadline: deadline, at: deadline.addingTimeInterval(0.6)))
    }
}
