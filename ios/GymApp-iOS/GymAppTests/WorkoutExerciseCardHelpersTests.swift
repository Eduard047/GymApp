import Foundation
import XCTest
@testable import GymApp

final class WorkoutExerciseCardHelpersTests: XCTestCase {
    func testRemoveExerciseIsHiddenForTheOnlyExerciseOutsideEditingOrWhileUndoIsPending() {
        XCTAssertTrue(workoutDetailCanRemoveExercise(isEditing: true, exerciseCount: 2, hasPendingDeletion: false))
        XCTAssertFalse(workoutDetailCanRemoveExercise(isEditing: true, exerciseCount: 1, hasPendingDeletion: false))
        XCTAssertFalse(workoutDetailCanRemoveExercise(isEditing: false, exerciseCount: 3, hasPendingDeletion: false))
        XCTAssertFalse(workoutDetailCanRemoveExercise(isEditing: true, exerciseCount: 3, hasPendingDeletion: true))
    }

    func testSavedSetEditorRequiresFiniteNonNegativeWeightAndAtLeastOneRep() {
        XCTAssertTrue(workoutDetailCanSaveSet(weight: 0, reps: 1))
        XCTAssertTrue(workoutDetailCanSaveSet(weight: 82.5, reps: 8))
        XCTAssertFalse(workoutDetailCanSaveSet(weight: -1, reps: 8))
        XCTAssertFalse(workoutDetailCanSaveSet(weight: .nan, reps: 8))
        XCTAssertFalse(workoutDetailCanSaveSet(weight: .infinity, reps: 8))
        XCTAssertFalse(workoutDetailCanSaveSet(weight: 50, reps: 0))
    }

    func testRemoveExerciseAlertMessagePluralizesRecordedSetsPerLanguage() {
        XCTAssertEqual(
            gymRemoveExerciseAlertMessage(name: "Squat", recordedSetCount: 1, languageCode: "en"),
            "Squat\n1 recorded set will be removed."
        )
        XCTAssertEqual(
            gymRemoveExerciseAlertMessage(name: "Squat", recordedSetCount: 4, languageCode: "en"),
            "Squat\n4 recorded sets will be removed."
        )
        XCTAssertEqual(
            gymRemoveExerciseAlertMessage(name: "Присед", recordedSetCount: 3, languageCode: "uk"),
            "Присед\n3 записані підходи буде видалено."
        )
        XCTAssertEqual(
            gymRemoveExerciseAlertMessage(name: "Присед", recordedSetCount: 5, languageCode: "ru"),
            "Присед\n5 записанных подходов будут удалены."
        )
        XCTAssertEqual(
            gymRemoveExerciseAlertMessage(name: "Присед", recordedSetCount: 21, languageCode: "ru"),
            "Присед\n21 записанный подход будет удалён."
        )
    }

    func testRemoveExerciseAlertMessageWithoutRecordedSetsMentionsPlannedSets() {
        XCTAssertEqual(
            gymRemoveExerciseAlertMessage(name: "Squat", recordedSetCount: 0, languageCode: "en"),
            "Squat\nIts planned sets will be removed from this workout."
        )
    }

    func testRowActionTitlesAreLocalized() {
        XCTAssertEqual(gymDeleteSetActionTitle(languageCode: "en"), "Delete set")
        XCTAssertEqual(gymDeleteSetActionTitle(languageCode: "uk"), "Видалити підхід")
        XCTAssertEqual(gymDeleteSetActionTitle(languageCode: "ru"), "Удалить подход")
        XCTAssertEqual(gymRemoveExerciseActionTitle(languageCode: "en"), "Remove exercise")
        XCTAssertEqual(gymRemoveExerciseActionTitle(languageCode: "uk"), "Видалити вправу")
        XCTAssertEqual(gymRemoveExerciseActionTitle(languageCode: "ru"), "Удалить упражнение")
    }

    func testSavedWorkoutCardsToggleCollapseIndependently() {
        let first = UUID()
        let second = UUID()

        var collapsed: Set<UUID> = []
        collapsed = WorkoutDetailDisclosurePolicy.toggledCollapsed(collapsed, tapped: first)
        XCTAssertEqual(collapsed, [first])
        collapsed = WorkoutDetailDisclosurePolicy.toggledCollapsed(collapsed, tapped: second)
        XCTAssertEqual(collapsed, [first, second])
        collapsed = WorkoutDetailDisclosurePolicy.toggledCollapsed(collapsed, tapped: first)
        XCTAssertEqual(collapsed, [second])
    }
}
