import XCTest
@testable import GymApp

final class LivePersonalRecordsTests: XCTestCase {
    private let benchID = UUID()
    private let squatID = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private struct PlannedSet {
        let weight: Double
        let reps: Int
        let completed: Bool
    }

    private struct PlannedExercise {
        let id: UUID
        let sets: [PlannedSet]
    }

    private func done(_ weight: Double, _ reps: Int) -> PlannedSet {
        PlannedSet(weight: weight, reps: reps, completed: true)
    }

    private func pending(_ weight: Double, _ reps: Int) -> PlannedSet {
        PlannedSet(weight: weight, reps: reps, completed: false)
    }

    private func history(
        exerciseID: UUID,
        weights: [Double],
        reps: [Int],
        daysAgo: Double = 3
    ) -> [ExerciseHistoryEntry] {
        let workoutID = UUID()
        let sessionDate: Date = start.addingTimeInterval(-daysAgo * 86_400)
        var entries: [ExerciseHistoryEntry] = []
        for index in weights.indices {
            entries.append(
                ExerciseHistoryEntry(
                    setID: UUID(),
                    workoutID: workoutID,
                    sessionDate: sessionDate,
                    exerciseID: exerciseID,
                    exerciseName: "Custom lift",
                    weight: weights[index],
                    reps: reps[index],
                    setOrderIndex: index
                )
            )
        }
        return entries
    }

    /// Each set is completed one minute after the previous one, across exercises
    /// in list order, unless it is pending.
    private func draft(_ exercises: [PlannedExercise]) -> ActiveWorkoutDraft {
        var minute: Double = 0
        var blocks: [ActiveWorkoutExercise] = []
        for exercise in exercises {
            var sets: [ActiveWorkoutSet] = []
            for planned in exercise.sets {
                minute += 1
                let completedAt: Date? = planned.completed ? start.addingTimeInterval(minute * 60) : nil
                sets.append(ActiveWorkoutSet(weight: planned.weight, reps: planned.reps, completedAt: completedAt))
            }
            blocks.append(ActiveWorkoutExercise(exerciseID: exercise.id, sets: sets))
        }
        return ActiveWorkoutDraft(startedAt: start, workoutDate: start, exercises: blocks)
    }

    private func records(_ draft: ActiveWorkoutDraft, history: [ExerciseHistoryEntry]) -> [Bool] {
        let ids = LivePersonalRecords.recordSetIDs(
            in: draft,
            baselines: LivePersonalRecords.baselines(history: history)
        )
        var flags: [Bool] = []
        for exercise in draft.exercises {
            for set in exercise.sets {
                flags.append(ids.contains(set.id))
            }
        }
        return flags
    }

    func testHeavierWeightOrBetterEstimateIsARecord() {
        let past = history(exerciseID: benchID, weights: [80, 80], reps: [8, 8])
        let workout = draft([PlannedExercise(id: benchID, sets: [done(85, 3), done(80, 10), done(80, 8)])])

        // 85 kg beats the weight best; 80×10 beats the 80×8 estimate; 80×8 equals it.
        XCTAssertEqual(records(workout, history: past), [true, true, false])
    }

    func testEqualToTheBestIsNotARecord() {
        let past = history(exerciseID: benchID, weights: [100], reps: [5])
        let workout = draft([PlannedExercise(id: benchID, sets: [done(100, 5)])])

        XCTAssertEqual(records(workout, history: past), [false])
    }

    func testFirstSessionOfAnExerciseNeverSetsARecord() {
        let workout = draft([PlannedExercise(id: benchID, sets: [done(60, 8), done(70, 8)])])

        XCTAssertEqual(records(workout, history: []), [false, false])
    }

    func testZeroKilogramSetIsNeverARecord() {
        let past = history(exerciseID: benchID, weights: [0], reps: [8])
        let workout = draft([PlannedExercise(id: benchID, sets: [done(0, 20), done(5, 8)])])

        XCTAssertEqual(records(workout, history: past), [false, true])
    }

    func testLaterSetsCompareAgainstTheBestSoFarInThisWorkout() {
        let past = history(exerciseID: benchID, weights: [80], reps: [5])
        let workout = draft([
            PlannedExercise(id: benchID, sets: [done(90, 5), done(85, 5), done(95, 5), done(95, 5)])
        ])

        XCTAssertEqual(records(workout, history: past), [true, false, true, false])
    }

    func testIncompleteSetsAndOtherExercisesDoNotInterfere() {
        let benchHistory = history(exerciseID: benchID, weights: [80], reps: [5])
        let squatHistory = history(exerciseID: squatID, weights: [140], reps: [5])
        let past: [ExerciseHistoryEntry] = benchHistory + squatHistory
        let workout = draft([
            PlannedExercise(id: benchID, sets: [pending(120, 5), done(82.5, 5)]),
            PlannedExercise(id: squatID, sets: [done(100, 5)])
        ])

        XCTAssertEqual(records(workout, history: past), [false, true, false])
    }

    func testCompletionOrderDecidesWhichSetHoldsTheRecord() {
        let past = history(exerciseID: benchID, weights: [80], reps: [5])
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
        let past = history(exerciseID: benchID, weights: [100, 80], reps: [1, 10])
        let baseline = LivePersonalRecords.baselines(history: past)[benchID]

        XCTAssertEqual(baseline?.bestWeight, 100)
        let expectedEstimate: Double = 80.0 * (1.0 + 10.0 / 30.0)
        let actualEstimate: Double = baseline?.bestEstimatedOneRepMax ?? 0
        XCTAssertEqual(actualEstimate, expectedEstimate, accuracy: 1e-9)
        XCTAssertEqual(past[1].estimatedOneRepMax, GymOneRepMax.estimate(weight: 80, reps: 10))
    }
}
