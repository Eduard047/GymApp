import Foundation
import XCTest
@testable import GymApp

final class WorkoutComparisonTests: XCTestCase {
    private let squat = Exercise(name: "Squat")
    private let bench = Exercise(name: "Bench Press")
    private let curl = Exercise(name: "My Custom Curl")

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
    }

    private func workout(
        _ offset: Int,
        id: UUID = UUID(),
        _ blocks: [(Exercise, [(Double, Int)])]
    ) -> WorkoutSession {
        WorkoutSession(
            id: id,
            date: day(offset),
            exercises: blocks.map { exercise, sets in
                WorkoutExercise(
                    exerciseID: exercise.id,
                    sets: sets.map { WorkoutSet(weight: $0.0, reps: $0.1) }
                )
            }
        )
    }

    private func compare(_ current: WorkoutSession, in workouts: [WorkoutSession]) -> WorkoutComparison? {
        WorkoutComparisonEngine.comparison(
            for: current.id,
            workouts: workouts,
            exercises: [squat, bench, curl]
        )
    }

    func testComparesSetsRepsAndVolumeWithThePreviousWorkoutOfTheSameExercises() throws {
        let older = workout(-14, [(squat, [(100, 5), (100, 5)]), (bench, [(60, 10)])])
        let previous = workout(-7, [(squat, [(100, 5), (100, 5)]), (bench, [(60, 10)])])
        let current = workout(0, [(bench, [(65, 10), (65, 10)]), (squat, [(100, 5)])])

        let result = try XCTUnwrap(compare(current, in: [older, previous, current]))

        XCTAssertEqual(result.previousWorkoutID, previous.id)
        XCTAssertEqual(result.previousDate, previous.date)
        XCTAssertEqual(result.matchedExerciseCount, 2)
        XCTAssertEqual(result.sets.current, 3)
        XCTAssertEqual(result.sets.previous, 3)
        XCTAssertTrue(result.sets.isUnchanged)
        XCTAssertEqual(result.reps.current, 25)
        XCTAssertEqual(result.reps.previous, 20)
        XCTAssertEqual(result.reps.delta, 5)
        XCTAssertEqual(result.volume.current, 1_800)
        XCTAssertEqual(result.volume.previous, 1_600)
        XCTAssertEqual(result.volume.delta, 200)
        XCTAssertFalse(result.volume.isUnchanged)
    }

    func testNegativeDeltaAndFractionalVolumeNoiseIsUnchanged() throws {
        let previous = workout(-3, [(squat, [(100, 5)])])
        let lower = workout(0, [(squat, [(90, 5)])])
        let lowerResult = try XCTUnwrap(compare(lower, in: [previous, lower]))
        XCTAssertEqual(lowerResult.volume.delta, -50)

        let same = workout(1, [(squat, [(100.005, 5)])])
        let sameResult = try XCTUnwrap(compare(same, in: [previous, same]))
        XCTAssertTrue(sameResult.volume.isUnchanged)
    }

    func testDifferentExerciseSetsNeverMatch() {
        let previous = workout(-7, [(squat, [(100, 5)]), (bench, [(60, 10)])])
        let subset = workout(0, [(squat, [(100, 5)])])
        let superset = workout(1, [(squat, [(100, 5)]), (bench, [(60, 10)]), (curl, [(20, 10)])])
        XCTAssertNil(compare(subset, in: [previous, subset, superset]))
        XCTAssertNil(compare(superset, in: [previous, subset, superset]))
    }

    func testIgnoresLaterWorkoutsAndHidesWhenNothingEarlierMatches() {
        let current = workout(-7, [(squat, [(100, 5)])])
        let later = workout(0, [(squat, [(100, 5)])])
        XCTAssertNil(compare(current, in: [current, later]))
        XCTAssertNil(compare(current, in: [current]))
    }

    func testPicksTheLatestEarlierMatchRegardlessOfStorageOrder() throws {
        let older = workout(-20, [(squat, [(100, 5)])])
        let newest = workout(-2, [(squat, [(110, 5)])])
        let other = workout(-1, [(bench, [(60, 10)])])
        let current = workout(0, [(squat, [(120, 5)])])
        let result = try XCTUnwrap(compare(current, in: [newest, other, current, older]))
        XCTAssertEqual(result.previousWorkoutID, newest.id)
    }

    func testSameDayWorkoutsOrderByIdentifierDeterministically() throws {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = workout(0, id: low, [(squat, [(100, 5)])])
        let second = workout(0, id: high, [(squat, [(105, 5)])])
        XCTAssertEqual(try XCTUnwrap(compare(second, in: [first, second])).previousWorkoutID, low)
        XCTAssertNil(compare(first, in: [first, second]))
    }

    func testWorkoutsWithoutSetsOrWithUnreadableValuesAreSkipped() throws {
        let valid = workout(-9, [(squat, [(100, 5)])])
        let empty = workout(-5, [(squat, [])])
        let broken = workout(-3, [(squat, [(.nan, 5)])])
        let current = workout(0, [(squat, [(100, 6)])])
        XCTAssertEqual(try XCTUnwrap(compare(current, in: [valid, empty, broken, current])).previousWorkoutID, valid.id)
        XCTAssertNil(compare(empty, in: [valid, empty]))
        XCTAssertNil(compare(broken, in: [valid, broken]))
    }

    func testRepeatedExerciseBlocksCountOnceInTheSignature() throws {
        let previous = workout(-4, [(squat, [(100, 5)])])
        let current = workout(0, [(squat, [(100, 5)]), (squat, [(100, 5)])])
        let result = try XCTUnwrap(compare(current, in: [previous, current]))
        XCTAssertEqual(result.matchedExerciseCount, 1)
        XCTAssertEqual(result.sets.current, 2)
    }
}
