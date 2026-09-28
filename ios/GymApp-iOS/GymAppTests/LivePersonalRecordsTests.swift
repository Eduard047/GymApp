import XCTest
@testable import GymApp

final class LivePersonalRecordsTests: XCTestCase {
    private let benchID = UUID()
    private let squatID = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func history(
        exerciseID: UUID,
        _ sets: [(weight: Double, reps: Int)],
        daysAgo: Double = 3
    ) -> [ExerciseHistoryEntry] {
        let workoutID = UUID()
        return sets.enumerated().map { index, set in
            ExerciseHistoryEntry(
                setID: UUID(),
                workoutID: workoutID,
                sessionDate: start.addingTimeInterval(-daysAgo * 86_400),
                exerciseID: exerciseID,
                exerciseName: "Custom lift",
                weight: set.weight,
                reps: set.reps,
                setOrderIndex: index
            )
        }
    }

    /// Each set is completed one minute after the previous one, across exercises
    /// in list order, unless `completed` is false.
    private func draft(_ exercises: [(id: UUID, sets: [(weight: Double, reps: Int, completed: Bool)])]) -> ActiveWorkoutDraft {
        var minute = 0.0
        let blocks = exercises.map { exercise in
            ActiveWorkoutExercise(
                exerciseID: exercise.id,
                sets: exercise.sets.map { set in
                    minute += 1
                    return ActiveWorkoutSet(
                        weight: set.weight,
                        reps: set.reps,
                        completedAt: set.completed ? start.addingTimeInterval(minute * 60) : nil
                    )
                }
            )
        }
        return ActiveWorkoutDraft(startedAt: start, workoutDate: start, exercises: blocks)
    }

    private func records(_ draft: ActiveWorkoutDraft, history: [ExerciseHistoryEntry]) -> [Bool] {
        let ids = LivePersonalRecords.recordSetIDs(
            in: draft,
            baselines: LivePersonalRecords.baselines(history: history)
        )
        return draft.exercises.flatMap(\.sets).map { ids.contains($0.id) }
    }

    func testHeavierWeightOrBetterEstimateIsARecord() {
        let past = history(exerciseID: benchID, [(80, 8), (80, 8)])
        let workout = draft([(benchID, [(85, 3, true), (80, 10, true), (80, 8, true)])])

        // 85 kg beats the weight best; 80×10 beats the 80×8 estimate; 80×8 equals it.
        XCTAssertEqual(records(workout, history: past), [true, true, false])
    }

    func testEqualToTheBestIsNotARecord() {
        let past = history(exerciseID: benchID, [(100, 5)])
        let workout = draft([(benchID, [(100, 5, true)])])

        XCTAssertEqual(records(workout, history: past), [false])
    }

    func testFirstSessionOfAnExerciseNeverSetsARecord() {
        let workout = draft([(benchID, [(60, 8, true), (70, 8, true)])])

        XCTAssertEqual(records(workout, history: []), [false, false])
    }

    func testZeroKilogramSetIsNeverARecord() {
        let past = history(exerciseID: benchID, [(0, 8)])
        let workout = draft([(benchID, [(0, 20, true), (5, 8, true)])])

        XCTAssertEqual(records(workout, history: past), [false, true])
    }

    func testLaterSetsCompareAgainstTheBestSoFarInThisWorkout() {
        let past = history(exerciseID: benchID, [(80, 5)])
        let workout = draft([(benchID, [(90, 5, true), (85, 5, true), (95, 5, true), (95, 5, true)])])

        XCTAssertEqual(records(workout, history: past), [true, false, true, false])
    }

    func testIncompleteSetsAndOtherExercisesDoNotInterfere() {
        let past = history(exerciseID: benchID, [(80, 5)]) + history(exerciseID: squatID, [(140, 5)])
        let workout = draft([
            (benchID, [(120, 5, false), (82.5, 5, true)]),
            (squatID, [(100, 5, true)])
        ])

        XCTAssertEqual(records(workout, history: past), [false, true, false])
    }

    func testCompletionOrderDecidesWhichSetHoldsTheRecord() {
        let past = history(exerciseID: benchID, [(80, 5)])
        let first = ActiveWorkoutSet(weight: 90, reps: 5, completedAt: start.addingTimeInterval(120))
        let second = ActiveWorkoutSet(weight: 90, reps: 5, completedAt: start.addingTimeInterval(60))
        let workout = ActiveWorkoutDraft(
            startedAt: start,
            workoutDate: start,
            exercises: [ActiveWorkoutExercise(exerciseID: benchID, sets: [first, second])]
        )

        let ids = LivePersonalRecords.recordSetIDs(
            in: workout,
            baselines: LivePersonalRecords.baselines(history: past)
        )

        XCTAssertEqual(ids, [second.id])
    }

    func testBaselinesUseHistoryBestsAndTheSharedEstimate() {
        let past = history(exerciseID: benchID, [(100, 1), (80, 10)])
        let baseline = LivePersonalRecords.baselines(history: past)[benchID]

        XCTAssertEqual(baseline?.bestWeight, 100)
        XCTAssertEqual(baseline?.bestEstimatedOneRepMax ?? 0, 80 * (1 + 10.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(past[1].estimatedOneRepMax, GymOneRepMax.estimate(weight: 80, reps: 10))
    }
}
