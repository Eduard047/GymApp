import Foundation
import XCTest
@testable import GymApp

@MainActor
final class RepeatLastWorkoutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStores(account: String) throws -> (WorkoutStore, ActiveWorkoutStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-repeat-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkoutStore(accountStorageKey: account, directoryURL: directory)
        let active = ActiveWorkoutStore(
            accountStorageKey: store.accountStorageKey,
            workoutStorageURL: store.storageURL
        )
        return (store, active)
    }

    private func flatten(_ drafts: [WorkoutEditorExerciseDraft]) -> [[Double]] {
        drafts.map { $0.sets.flatMap { [$0.weight, Double($0.reps)] } }
    }

    func testSeedKeepsStoredOrderAndSetValuesAndGivesEmptyExerciseOneBlankSet() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let workout = WorkoutSession(
            date: now,
            exercises: [
                WorkoutExercise(exerciseID: second, sets: [
                    WorkoutSet(weight: 62.5, reps: 8),
                    WorkoutSet(weight: 60, reps: 10)
                ]),
                WorkoutExercise(exerciseID: first, sets: []),
                WorkoutExercise(exerciseID: third, sets: [WorkoutSet(weight: 0, reps: 12)])
            ]
        )

        let seed = RepeatLastWorkout.editorDrafts(from: workout)

        XCTAssertEqual(seed.map(\.exerciseID), [second, first, third])
        XCTAssertEqual(flatten(seed), [[62.5, 8, 60, 10], [0, 10], [0, 12]])
    }

    func testDirectStartBuildsTheSameSeedAsTheEditorAndCarriesTheNote() throws {
        let (store, active) = try makeStores(account: "repeat-last-direct")
        let bench = try store.addExercise(name: "Repeat Bench \(UUID().uuidString)")
        let row = try store.addExercise(name: "Repeat Row \(UUID().uuidString)")
        _ = try store.createWorkout(
            date: now.addingTimeInterval(-7 * 86_400),
            note: "Older",
            exercises: [WorkoutExerciseDraft(exerciseID: row.id, sets: [WorkoutSetDraft(weight: 30, reps: 5)])]
        )
        _ = try store.createWorkout(
            date: now.addingTimeInterval(-86_400),
            note: "Heavy day",
            exercises: [
                WorkoutExerciseDraft(exerciseID: bench.id, sets: [
                    WorkoutSetDraft(weight: 82.5, reps: 5),
                    WorkoutSetDraft(weight: 80, reps: 6)
                ]),
                WorkoutExerciseDraft(exerciseID: row.id, sets: [WorkoutSetDraft(weight: 55, reps: 10)])
            ]
        )
        let editorSeed = RepeatLastWorkout.editorDrafts(from: try XCTUnwrap(store.latestWorkoutTemplate))

        guard case .started(let draft) = RepeatLastWorkout.start(
            workoutStore: store,
            activeWorkoutStore: active,
            now: now
        ) else {
            return XCTFail("A stored workout with sets must start directly.")
        }

        XCTAssertEqual(draft.exercises.map(\.exerciseID), editorSeed.map(\.exerciseID))
        XCTAssertEqual(
            draft.exercises.map { $0.sets.flatMap { [$0.weight, Double($0.reps)] } },
            flatten(editorSeed)
        )
        XCTAssertEqual(draft.note, "Heavy day")
        XCTAssertEqual(draft.workoutDate, now)
        XCTAssertEqual(active.draft?.id, draft.id)
        XCTAssertEqual(store.workouts.count, 2, "Direct start must not write completed history.")
        XCTAssertNil(workoutEditorValidationMessage(
            drafts: editorSeed,
            date: now,
            now: now,
            exerciseExists: { store.exercise(id: $0) != nil }
        ))
    }

    func testEmptyHistoryHidesTheActionAndDoesNotStart() throws {
        let (store, active) = try makeStores(account: "repeat-last-empty")

        XCTAssertNil(store.latestWorkoutTemplate)
        XCTAssertFalse(RepeatLastWorkout.shouldShowAction(
            hasRepeatableWorkout: store.workoutSummaries.contains { $0.setCount > 0 },
            hasActiveWorkout: false,
            hasRetainedWorkoutDraft: false
        ))
        guard case .unavailable = RepeatLastWorkout.start(
            workoutStore: store,
            activeWorkoutStore: active,
            now: now
        ) else {
            return XCTFail("Nothing to repeat must be unavailable.")
        }
        XCTAssertNil(active.draft)
    }

    func testActiveWorkoutOrKeptDraftHidesTheActionAndActiveWorkoutBlocksStart() throws {
        let (store, active) = try makeStores(account: "repeat-last-active")
        let exercise = try store.addExercise(name: "Repeat Squat \(UUID().uuidString)")
        _ = try store.createWorkout(
            date: now.addingTimeInterval(-86_400),
            exercises: [WorkoutExerciseDraft(exerciseID: exercise.id, sets: [WorkoutSetDraft(weight: 100, reps: 5)])]
        )
        let repeatable = store.workoutSummaries.contains { $0.setCount > 0 }
        XCTAssertTrue(repeatable)
        XCTAssertTrue(RepeatLastWorkout.shouldShowAction(
            hasRepeatableWorkout: repeatable, hasActiveWorkout: false, hasRetainedWorkoutDraft: false
        ))
        XCTAssertFalse(RepeatLastWorkout.shouldShowAction(
            hasRepeatableWorkout: repeatable, hasActiveWorkout: true, hasRetainedWorkoutDraft: false
        ))
        XCTAssertFalse(RepeatLastWorkout.shouldShowAction(
            hasRepeatableWorkout: repeatable, hasActiveWorkout: false, hasRetainedWorkoutDraft: true
        ))

        guard case .started(let first) = RepeatLastWorkout.start(
            workoutStore: store, activeWorkoutStore: active, now: now
        ) else { return XCTFail("The first tap must start.") }
        guard case .alreadyActive = RepeatLastWorkout.start(
            workoutStore: store, activeWorkoutStore: active, now: now
        ) else { return XCTFail("A second tap must open the existing workout.") }
        XCTAssertEqual(active.draft?.id, first.id)
    }

    func testValidationRejectsWhatTheEditorStartRejects() {
        let exerciseID = UUID()
        func message(_ drafts: [WorkoutEditorExerciseDraft], known: Bool = true) -> String? {
            workoutEditorValidationMessage(drafts: drafts, date: now, now: now, exerciseExists: { _ in known })
        }
        XCTAssertNotNil(message([]))
        XCTAssertNotNil(message([WorkoutEditorExerciseDraft(exerciseID: exerciseID)], known: false))
        XCTAssertNotNil(message([WorkoutEditorExerciseDraft(
            exerciseID: exerciseID, sets: [WorkoutEditorSetDraft(weight: 2_000_000, reps: 5)]
        )]))
        XCTAssertNotNil(message([WorkoutEditorExerciseDraft(
            exerciseID: exerciseID, sets: [WorkoutEditorSetDraft(weight: 50, reps: 0)]
        )]))
        XCTAssertNil(message([WorkoutEditorExerciseDraft(
            exerciseID: exerciseID, sets: [WorkoutEditorSetDraft(weight: 50, reps: 5)]
        )]))
    }
}
