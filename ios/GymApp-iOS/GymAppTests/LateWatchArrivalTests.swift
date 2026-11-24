import XCTest
@testable import GymApp

final class LateWatchArrivalTests: XCTestCase {
    // A phone workout 10:00-11:00 with two exercises.
    private let phoneStart: Int64 = 1_790_000_000_000
    private let phoneDuration = 3_600
    private var phoneEnd: Int64 { phoneStart + Int64(phoneDuration) * 1_000 }
    private let phoneSets = [
        LateWatchArrivalSet(exerciseName: "Bench Press", weight: 80, reps: 8),
        LateWatchArrivalSet(exerciseName: "Bench Press", weight: 85, reps: 6),
        LateWatchArrivalSet(exerciseName: "Squat", weight: 100, reps: 5)
    ]

    private var phoneWorkout: LateWatchArrivalStoredWorkout {
        LateWatchArrivalStoredWorkout(startMillis: phoneStart, durationSeconds: phoneDuration, sets: phoneSets)
    }

    private func decide(
        start: Int64,
        end: Int64,
        sets: [LateWatchArrivalSet] = [],
        stored: [LateWatchArrivalStoredWorkout]? = nil
    ) -> LateWatchArrivalDecision {
        LateWatchArrivalRule.decide(startMillis: start, endMillis: end, sets: sets, stored: stored ?? [phoneWorkout])
    }

    // MARK: Activity-only arrival

    func testActivityOnlyArrivalOverlappingAWorkoutWithSetsIsSkipped() {
        XCTAssertEqual(decide(start: phoneStart + 60_000, end: phoneEnd - 60_000), .skip)
    }

    func testActivityOnlyArrivalWithoutOverlapIsStored() {
        XCTAssertEqual(decide(start: phoneEnd + 3_600_000, end: phoneEnd + 7_200_000), .store)
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, stored: []), .store)
    }

    func testActivityOnlyArrivalOverlappingAnActivityOnlyWorkoutIsStored() {
        let activity = LateWatchArrivalStoredWorkout(startMillis: phoneStart, durationSeconds: phoneDuration, sets: [])
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, stored: [activity]), .store)
    }

    func testBackToBackActivityOnlyArrivalIsStored() {
        // Phone strength 10:00-11:00, watch run 11:01-11:31: a separate session, inside the tolerance.
        XCTAssertEqual(decide(start: phoneEnd + 60_000, end: phoneEnd + 1_860_000), .store)
        // Touching end to start (no gap), or ending right before the phone start: still separate.
        XCTAssertEqual(decide(start: phoneEnd, end: phoneEnd + 1_800_000), .store)
        XCTAssertEqual(decide(start: phoneStart - 1_800_000, end: phoneStart - 60_000), .store)
    }

    func testActivityOnlyArrivalCoveredByHalfIsSkipped() {
        // 30-minute arrival starting 15 minutes before the phone end: exactly 50 % covered.
        XCTAssertEqual(decide(start: phoneEnd - 900_000, end: phoneEnd + 900_000), .skip)
        // One millisecond less than half covered: stored.
        XCTAssertEqual(decide(start: phoneEnd - 899_999, end: phoneEnd + 900_001), .store)
        // Same boundary on the start side.
        XCTAssertEqual(decide(start: phoneStart - 900_000, end: phoneStart + 900_000), .skip)
        XCTAssertEqual(decide(start: phoneStart - 900_001, end: phoneStart + 899_999), .store)
    }

    func testActivityOnlyArrivalNestedInTheStoredWorkoutIsSkipped() {
        XCTAssertEqual(decide(start: phoneStart + 600_000, end: phoneStart + 1_800_000), .skip)
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd), .skip)
    }

    func testStoredWorkoutWithoutDurationNeverSkipsAnActivityOnlyArrival() {
        for duration in [nil, 0] as [Int?] {
            let noDuration = LateWatchArrivalStoredWorkout(startMillis: phoneStart, durationSeconds: duration, sets: phoneSets)
            XCTAssertEqual(decide(start: phoneStart - 600_000, end: phoneStart + 600_000, stored: [noDuration]), .store)
            XCTAssertEqual(decide(start: phoneStart, end: phoneStart, stored: [noDuration]), .store)
        }
    }

    func testEndBeforeStartIsTreatedAsAnInstant() {
        XCTAssertEqual(decide(start: phoneStart + 60_000, end: phoneStart), .skip)
    }

    // MARK: Arrival with sets

    func testIdenticalSetsAreSkippedRegardlessOfCaseSpacingAndInterleaving() {
        let arrival = [
            LateWatchArrivalSet(exerciseName: "  bench press", weight: 80, reps: 8),
            LateWatchArrivalSet(exerciseName: "SQUAT ", weight: 100, reps: 5),
            LateWatchArrivalSet(exerciseName: "Bench Press", weight: 85, reps: 6)
        ]
        XCTAssertEqual(decide(start: phoneStart + 30_000, end: phoneEnd + 30_000, sets: arrival), .skip)
    }

    func testOneDifferentRepIsStored() {
        var arrival = phoneSets
        arrival[2] = LateWatchArrivalSet(exerciseName: "Squat", weight: 100, reps: 6)
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, sets: arrival), .store)
    }

    func testDifferentWeightNameOrCountIsStored() {
        var weight = phoneSets
        weight[0] = LateWatchArrivalSet(exerciseName: "Bench Press", weight: 80.5, reps: 8)
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, sets: weight), .store)

        var name = phoneSets
        name[2] = LateWatchArrivalSet(exerciseName: "Front Squat", weight: 100, reps: 5)
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, sets: name), .store)

        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, sets: Array(phoneSets.dropLast())), .store)
        XCTAssertEqual(
            decide(start: phoneStart, end: phoneEnd, sets: phoneSets + [phoneSets[2]]),
            .store
        )
    }

    func testSetOrderWithinAnExerciseMatters() {
        let swapped = [phoneSets[1], phoneSets[0], phoneSets[2]]
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, sets: swapped), .store)
    }

    func testIdenticalSetsWithoutOverlapAreStored() {
        XCTAssertEqual(decide(start: phoneEnd + 120_001, end: phoneEnd + 3_600_000, sets: phoneSets), .store)
    }

    func testIdenticalSetsAtTheToleranceEdgeAreSkipped() {
        XCTAssertEqual(decide(start: phoneEnd + 120_000, end: phoneEnd + 3_600_000, sets: phoneSets), .skip)
    }

    func testIdenticalSetsBeforeTheStoredWorkoutKeepTheTolerance() {
        XCTAssertEqual(decide(start: phoneStart - 1_800_000, end: phoneStart - 120_000, sets: phoneSets), .skip)
        XCTAssertEqual(decide(start: phoneStart - 1_800_000, end: phoneStart - 120_001, sets: phoneSets), .store)
    }

    func testIdenticalSetsAgainstAStoredWorkoutWithoutDurationUseItsStartOnly() {
        let noDuration = LateWatchArrivalStoredWorkout(startMillis: phoneStart, durationSeconds: nil, sets: phoneSets)
        XCTAssertEqual(decide(start: phoneStart + 120_000, end: phoneStart + 600_000, sets: phoneSets, stored: [noDuration]), .skip)
        XCTAssertEqual(decide(start: phoneStart + 120_001, end: phoneStart + 600_000, sets: phoneSets, stored: [noDuration]), .store)
    }

    func testArrivalWithSetsOverlappingAnActivityOnlyWorkoutIsStored() {
        let activity = LateWatchArrivalStoredWorkout(startMillis: phoneStart, durationSeconds: phoneDuration, sets: [])
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, sets: phoneSets, stored: [activity]), .store)
    }

    func testAnyOverlappingIdenticalWorkoutSkipsEvenWhenAnotherDiffers() {
        let other = LateWatchArrivalStoredWorkout(
            startMillis: phoneStart,
            durationSeconds: phoneDuration,
            sets: [LateWatchArrivalSet(exerciseName: "Row", weight: 60, reps: 10)]
        )
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, sets: phoneSets, stored: [other, phoneWorkout]), .skip)
        XCTAssertEqual(decide(start: phoneStart, end: phoneEnd, sets: phoneSets, stored: [other]), .store)
    }

    // MARK: Store adapter

    func testStoredWorkoutsResolveExerciseNamesAndKeepBlockOrder() {
        let bench = UUID()
        let squat = UUID()
        let workout = WorkoutSession(
            date: Date(timeIntervalSince1970: TimeInterval(phoneStart / 1_000)),
            durationSeconds: phoneDuration,
            exercises: [
                WorkoutExercise(exerciseID: bench, sets: [WorkoutSet(weight: 80, reps: 8), WorkoutSet(weight: 85, reps: 6)]),
                WorkoutExercise(exerciseID: squat, sets: [WorkoutSet(weight: 100, reps: 5)])
            ]
        )
        let stored = LateWatchArrivalRule.storedWorkouts(
            [workout],
            exerciseNames: [bench: "Bench Press", squat: "Squat"]
        )
        XCTAssertEqual(stored, [phoneWorkout])
    }
}
