import XCTest
@testable import GymApp

final class GymStepRepeatScheduleTests: XCTestCase {
    func testFirstRepeatComesAfterInitialDelay() {
        XCTAssertEqual(GymStepRepeatSchedule.nextStepTime(after: nil), 0.35, accuracy: 0.000_001)
        XCTAssertEqual(GymStepRepeatSchedule.repeatStepCount(heldFor: 0.34), 0)
        XCTAssertEqual(GymStepRepeatSchedule.repeatStepCount(heldFor: 0.35), 1)
    }

    func testRepeatsRunAtEightPerSecondThenSixteenAfterOneAndAHalfSeconds() {
        // 0.35, 0.475, 0.6, ... one step every 125 ms.
        XCTAssertEqual(GymStepRepeatSchedule.nextStepTime(after: 0.35), 0.475, accuracy: 0.000_001)
        XCTAssertEqual(GymStepRepeatSchedule.nextStepTime(after: 1.1), 1.225, accuracy: 0.000_001)
        // Once the press has been held 1.5 s, one step every 62.5 ms.
        XCTAssertEqual(GymStepRepeatSchedule.nextStepTime(after: 1.5), 1.5625, accuracy: 0.000_001)
        XCTAssertEqual(GymStepRepeatSchedule.nextStepTime(after: 2.0), 2.0625, accuracy: 0.000_001)

        var time = GymStepRepeatSchedule.nextStepTime(after: nil)
        var times = [time]
        while times.count < 40 {
            time = GymStepRepeatSchedule.nextStepTime(after: time)
            times.append(time)
        }
        let gaps = zip(times, times.dropFirst()).map { ($0, $1 - $0) }
        for (start, gap) in gaps {
            XCTAssertEqual(gap, start >= 1.5 ? 0.0625 : 0.125, accuracy: 0.000_001, "gap after \(start)")
        }
        // Steps held for 3 s: 10 slow steps up to 1.475 plus 1.5/16-spaced ones after.
        XCTAssertEqual(GymStepRepeatSchedule.repeatStepCount(heldFor: 3.0), 33)
    }

    func testHapticsAreCappedAtTenPerSecond() {
        var last: TimeInterval?
        var played: [TimeInterval] = []
        var time = GymStepRepeatSchedule.nextStepTime(after: nil)
        while time <= 4.0 {
            if GymStepRepeatSchedule.shouldEmitHaptic(lastEmittedAt: last, at: time) {
                played.append(time)
                last = time
            }
            time = GymStepRepeatSchedule.nextStepTime(after: time)
        }
        for second in 0 ..< 4 {
            let inWindow = played.filter { $0 >= Double(second) && $0 < Double(second + 1) }
            XCTAssertLessThanOrEqual(inWindow.count, 10, "second \(second)")
        }
        XCTAssertTrue(GymStepRepeatSchedule.shouldEmitHaptic(lastEmittedAt: nil, at: 0))
        XCTAssertFalse(GymStepRepeatSchedule.shouldEmitHaptic(lastEmittedAt: 1.0, at: 1.0625))
        XCTAssertTrue(GymStepRepeatSchedule.shouldEmitHaptic(lastEmittedAt: 1.0, at: 1.1))
    }

    func testRepeatedWeightStepsStopAtTheAllowedWeightsAndNeverPassZero() {
        let steps = GymStepRepeatSchedule.repeatStepCount(heldFor: 5)
        XCTAssertGreaterThan(steps, 20)

        var weight = 20.0
        for _ in 0 ..< steps { weight = gymWeightStepTargets(weight: weight, allowedWeights: [20, 30, 40]).plus }
        XCTAssertEqual(weight, 40)
        for _ in 0 ..< steps { weight = gymWeightStepTargets(weight: weight, allowedWeights: [20, 30, 40]).minus }
        XCTAssertEqual(weight, 20)

        weight = 7.5
        for _ in 0 ..< steps { weight = gymWeightStepTargets(weight: weight, allowedWeights: []).minus }
        XCTAssertEqual(weight, 0)
        weight = 10
        weight = gymWeightStepTargets(weight: weight, allowedWeights: []).plus
        XCTAssertEqual(weight, 12.5)
    }

    func testRepeatedRepsStepsStayAtOrAboveOne() {
        var reps = 3
        for _ in 0 ..< GymStepRepeatSchedule.repeatStepCount(heldFor: 5) { reps = max(1, reps - 1) }
        XCTAssertEqual(reps, 1)
    }
}
