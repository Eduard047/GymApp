import Foundation
import XCTest
@testable import GymApp

@MainActor
final class PastWorkoutSetDefaultsTests: XCTestCase {
    func testNoHistoryDefaultsToZero() {
        XCTAssertEqual(PastWorkoutSetDefaults.weight(template: nil, history: nil), 0)
    }

    func testHistoryWeightIsUsedWhenThereIsNoTemplateSet() {
        XCTAssertEqual(PastWorkoutSetDefaults.weight(template: nil, history: 62.5), 62.5)
    }

    func testNonEmptyBlockCopiesTheLastSetEvenWithHistory() {
        XCTAssertEqual(PastWorkoutSetDefaults.weight(template: 40, history: 62.5), 40)
        XCTAssertEqual(PastWorkoutSetDefaults.weight(template: 0, history: 62.5), 0)
    }

    func testStoreHistoryLookupUsesTheLatestEarlierWorkoutOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppPastWorkoutDefaults", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkoutStore(accountStorageKey: "past-workout-defaults", directoryURL: directory)
        let exercise = try store.addExercise(name: "Past Defaults Press")
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNil(store.lastWeight(exerciseID: exercise.id, before: base))
        XCTAssertEqual(
            PastWorkoutSetDefaults.weight(
                template: nil,
                history: store.lastWeight(exerciseID: exercise.id, before: base)
            ),
            0
        )

        for (offset, weight) in [(0.0, 50.0), (1.0, 55.0), (3.0, 70.0)] {
            _ = try store.createWorkout(
                date: base.addingTimeInterval(offset * day),
                exercises: [WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [WorkoutSetDraft(weight: weight, reps: 5)]
                )]
            )
        }
        let past = base.addingTimeInterval(2 * day)
        XCTAssertEqual(store.lastWeight(exerciseID: exercise.id, before: past), 55)
        XCTAssertEqual(
            PastWorkoutSetDefaults.weight(
                template: nil,
                history: store.lastWeight(exerciseID: exercise.id, before: past)
            ),
            55
        )
    }
}
