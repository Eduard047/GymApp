import Foundation
import XCTest
@testable import GymApp

final class PlanEditorSnapshotTests: XCTestCase {
    func testSnapshotIgnoresEphemeralDraftAndSetIdentifiers() {
        let exerciseID = UUID()
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let firstDraft = WorkoutEditorExerciseDraft(
            id: UUID(),
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(id: UUID(), weight: 42.5, reps: 8)]
        )
        let recreatedDraft = WorkoutEditorExerciseDraft(
            id: UUID(),
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(id: UUID(), weight: 42.5, reps: 8)]
        )

        XCTAssertEqual(
            PlanEditorSnapshot(date: date, note: "", effort: .auto, drafts: [firstDraft]),
            PlanEditorSnapshot(date: date, note: "", effort: .auto, drafts: [recreatedDraft])
        )
    }

    func testSnapshotStillDetectsMeaningfulPlanChanges() {
        let exerciseID = UUID()
        let date = Date(timeIntervalSince1970: 1_787_000_000)
        let baseline = WorkoutEditorExerciseDraft(
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(weight: 0, reps: 10)]
        )
        let edited = WorkoutEditorExerciseDraft(
            exerciseID: exerciseID,
            sets: [WorkoutEditorSetDraft(weight: 0, reps: 12)]
        )

        XCTAssertNotEqual(
            PlanEditorSnapshot(date: date, note: "", effort: .auto, drafts: [baseline]),
            PlanEditorSnapshot(date: date, note: "", effort: .auto, drafts: [edited])
        )
    }
}
