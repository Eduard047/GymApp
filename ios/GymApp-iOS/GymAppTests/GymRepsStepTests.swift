import XCTest
@testable import GymApp

final class GymRepsStepTests: XCTestCase {
    func testRepsStepStaysWithinOneAndStoreMaximum() {
        XCTAssertEqual(GymRepsStep.maximum, 10_000)
        XCTAssertEqual(GymRepsStep.maximum, ActiveWorkoutStore.maximumReps)

        XCTAssertFalse(GymRepsStep.canStepDown(1))
        XCTAssertTrue(GymRepsStep.canStepDown(2))
        XCTAssertEqual(GymRepsStep.steppedDown(1), 1)
        XCTAssertEqual(GymRepsStep.steppedDown(0), 1)
        XCTAssertEqual(GymRepsStep.steppedDown(2), 1)

        XCTAssertTrue(GymRepsStep.canStepUp(9_999))
        XCTAssertFalse(GymRepsStep.canStepUp(10_000))
        XCTAssertFalse(GymRepsStep.canStepUp(20_000))
        XCTAssertEqual(GymRepsStep.steppedUp(9_999), 10_000)
        XCTAssertEqual(GymRepsStep.steppedUp(10_000), 10_000)
        XCTAssertEqual(GymRepsStep.steppedUp(1), 2)
    }

    func testNominalWeightStepDefaultsAndUsesSmallestMachineGap() {
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: []), 2.5)
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: [20]), 2.5)
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: [10, 15, 17.5, 30]), 2.5)
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: [5, 10, 20]), 5)
    }

    func testNominalWeightStepIgnoresNonFiniteAndNonPositiveGaps() {
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: [10, 10, 15]), 5)
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: [20, 10, 15]), 5)
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: [10, .infinity, 15]), 2.5)
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: [10, .nan, 20]), 2.5)
        XCTAssertEqual(gymNominalWeightStep(allowedWeights: [10, 10]), 2.5)
    }

    func testWeightStepTargetsUseNominalStepForBlockedDirection() {
        let targets = gymWeightStepTargets(weight: 0, allowedWeights: [])
        XCTAssertEqual(targets.minusDelta, 2.5)
        XCTAssertEqual(targets.plusDelta, 2.5)
    }
}
