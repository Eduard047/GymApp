import XCTest
@testable import GymApp

final class PostWorkoutPersonalRecordsTests: XCTestCase {
    private let benchID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    private let rowID = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!

    private func history(_ exerciseID: UUID, weight: Double, reps: Int = 8) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            setID: UUID(),
            workoutID: UUID(),
            sessionDate: Date(timeIntervalSince1970: 1_000),
            exerciseID: exerciseID,
            exerciseName: "X",
            exerciseCatalogKey: nil,
            weight: weight,
            reps: reps,
            setOrderIndex: 0
        )
    }

    private func build(_ blocks: [WorkoutExercise]) -> [PostWorkoutPersonalRecord] {
        postWorkoutPersonalRecords(
            blocks: blocks,
            previousHistory: { [benchID, rowID] id in
                id == benchID ? [self.history(benchID, weight: 80)] : id == rowID ? [] : []
            },
            title: { $0 == self.benchID ? "Bench" : "Row" }
        )
    }

    func testRepeatedBlocksOfOneExerciseMergeIntoOneRowWithBestSets() {
        let blocks = [
            WorkoutExercise(exerciseID: benchID, sets: [WorkoutSet(weight: 82.5, reps: 5)]),
            WorkoutExercise(exerciseID: rowID, sets: [WorkoutSet(weight: 60, reps: 8)]),
            WorkoutExercise(exerciseID: benchID, sets: [WorkoutSet(weight: 90, reps: 3)])
        ]
        let records = build(blocks)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.exerciseID, benchID)
        XCTAssertEqual(records.first?.weight, 90)
        // 90 x 3 does not beat the previous 80 x 8 estimate, so only the weight is a record.
        XCTAssertNil(records.first?.estimatedOneRepMax)
    }

    func testRecordIdsAreStableAcrossEvaluations() {
        let blocks = [
            WorkoutExercise(exerciseID: benchID, sets: [WorkoutSet(weight: 85, reps: 5)]),
            WorkoutExercise(exerciseID: benchID, sets: [WorkoutSet(weight: 90, reps: 3)])
        ]
        let first = build(blocks)
        let second = build(blocks)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), [benchID])
    }

    func testNoPreviousHistoryOrNoImprovementGivesNoRow() {
        let blocks = [
            WorkoutExercise(exerciseID: rowID, sets: [WorkoutSet(weight: 60, reps: 8)]),
            WorkoutExercise(exerciseID: benchID, sets: [WorkoutSet(weight: 70, reps: 5)])
        ]
        XCTAssertTrue(build(blocks).isEmpty)
    }
}
