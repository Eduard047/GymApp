import Foundation
import XCTest
@testable import GymApp

final class TrainingToolsTests: XCTestCase {
    func testStepWeightUsesConfiguredMachineStackAndStopsAtEdges() {
        let stack = [5.0, 7.5, 10.0]
        XCTAssertEqual(TrainingTools.stepWeight(5, direction: 1, allowed: stack), 7.5)
        XCTAssertEqual(TrainingTools.stepWeight(10, direction: -1, allowed: stack), 7.5)
        XCTAssertEqual(TrainingTools.stepWeight(10, direction: 1, allowed: stack), 10)
    }

    func testWeeklyReviewComparesOnlyTheExactSameWeight() {
        let calendar = Calendar(identifier: .iso8601)
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let exercise = UUID()
        let prior = entry(exercise, date: monday.addingTimeInterval(-2 * 86_400), weight: 50, reps: 8)
        let current = entry(exercise, date: monday.addingTimeInterval(86_400), weight: 50, reps: 10)
        let differentWeight = entry(exercise, date: monday.addingTimeInterval(2 * 86_400), weight: 55, reps: 12)

        let review = WeeklyReview.build([prior, current, differentWeight], now: now, calendar: calendar)
        XCTAssertTrue(review.partial)
        XCTAssertEqual(review.comparableCount, 1)
        XCTAssertEqual(review.insights.first?.current.reps, 10)
    }

    func testAdaptationPreservesCompletedSetsAndChangesOnlyPendingWork() {
        let exercise = UUID()
        let completed = ActiveWorkoutSet(weight: 20, reps: 8, completedAt: Date(timeIntervalSince1970: 100))
        let pending = ActiveWorkoutSet(weight: 20, reps: 8)
        let source = ActiveWorkoutDraft(
            workoutDate: Date(),
            exercises: [ActiveWorkoutExercise(exerciseID: exercise, exerciseName: "Row", sets: [completed, pending])]
        )

        let result = WorkoutAdaptation.build(source, reason: "tooHard", catalog: [])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.exercises[0].sets[0], completed)
        XCTAssertEqual(result?.exercises[0].sets[1].weight, 17.5)
        XCTAssertTrue(WorkoutAdaptation.preservesCompleted(source, result!))
    }

    @MainActor func testProgramsAreIsolatedByAccountAndRejectWrongOwnerOrOversizeData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.json")
        let secondURL = directory.appendingPathComponent("second.json")
        let first = TrainingProgramStore(owner: "first", workoutStorageURL: firstURL)
        let second = TrainingProgramStore(owner: "second", workoutStorageURL: secondURL)
        first.create(profile: TrainingProfile(workoutsPerWeek: 3))
        second.create(profile: TrainingProfile(workoutsPerWeek: 6))
        XCTAssertEqual(first.program?.slots.count, 12)
        XCTAssertEqual(second.program?.slots.count, 24)
        XCTAssertEqual(TrainingProgramStore(owner: "first", workoutStorageURL: firstURL).program, first.program)
        XCTAssertNil(TrainingProgramStore(owner: "second", workoutStorageURL: firstURL).program)
        first.status("paused")
        let paused = first.program
        first.reschedule()
        XCTAssertEqual(first.program, paused)
        first.status("active")
        first.reschedule()
        XCTAssertNotEqual(first.program?.slots, paused?.slots)
        first.status("completed")
        first.status("active")
        XCTAssertEqual(first.program?.status, "completed")
        let persisted = TrainingProgramStore.storageURL(forWorkoutStorageURL: firstURL)
        try Data(repeating: 32, count: 32769).write(to: persisted)
        XCTAssertNil(TrainingProgramStore(owner: "first", workoutStorageURL: firstURL).program)
        XCTAssertEqual(TrainingProgramStore(owner: "second", workoutStorageURL: secondURL).program, second.program)
    }

    private func entry(_ exercise: UUID, date: Date, weight: Double, reps: Int) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(setID: UUID(), workoutID: UUID(), sessionDate: date, exerciseID: exercise,
            exerciseName: "Exercise", weight: weight, reps: reps, setOrderIndex: 0)
    }
}
