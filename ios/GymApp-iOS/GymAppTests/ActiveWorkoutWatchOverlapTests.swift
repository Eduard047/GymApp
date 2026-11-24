import XCTest
@testable import GymApp

final class ActiveWorkoutWatchOverlapTests: XCTestCase {
    private let draftStart = Date(timeIntervalSince1970: 1_790_000_000)
    private var draftEnd: Date { draftStart.addingTimeInterval(60 * 60) }

    private func workout(
        note: String?,
        startOffset: TimeInterval,
        durationSeconds: Int?
    ) -> WorkoutSession {
        WorkoutSession(
            date: draftStart.addingTimeInterval(startOffset),
            note: note,
            durationSeconds: durationSeconds,
            exercises: []
        )
    }

    private func covering(_ workouts: [WorkoutSession], finishedAt: Date? = nil) -> WorkoutSession? {
        ActiveWorkoutWatchOverlap.coveringWorkout(
            draftStartedAt: draftStart,
            finishedAt: finishedAt ?? draftEnd,
            workouts: workouts
        )
    }

    func testAppleWatchWorkoutInsideTheDraftWindowOverlaps() {
        let watch = workout(note: "Apple Watch · Avg HR 120", startOffset: 5 * 60, durationSeconds: 50 * 60)
        XCTAssertEqual(covering([watch])?.id, watch.id)
    }

    func testWatchWorkoutLongBeforeOrAfterTheDraftDoesNotOverlap() {
        let before = workout(note: "Apple Watch", startOffset: -3 * 60 * 60, durationSeconds: 60 * 60)
        let after = workout(note: "Apple Watch", startOffset: 2 * 60 * 60, durationSeconds: 30 * 60)
        XCTAssertNil(covering([before, after]))
    }

    func testPhoneAndManualWorkoutsAreIgnoredEvenWhenTheyOverlap() {
        let manual = workout(note: nil, startOffset: 0, durationSeconds: 60 * 60)
        let noted = workout(note: "Leg day", startOffset: 10 * 60, durationSeconds: 40 * 60)
        XCTAssertNil(covering([manual, noted]))
        XCTAssertFalse(ActiveWorkoutWatchOverlap.isWatchOrImported(manual))
        XCTAssertFalse(ActiveWorkoutWatchOverlap.isWatchOrImported(noted))
    }

    func testToleranceEdgeIsOneHundredTwentySeconds() {
        // Watch workout ends exactly 120 s before the draft starts: still the same session.
        let atEdge = workout(note: "Apple Watch", startOffset: -(30 * 60 + 120), durationSeconds: 30 * 60)
        XCTAssertNotNil(covering([atEdge]))
        // One second further away: a separate session.
        let pastEdge = workout(note: "Apple Watch", startOffset: -(30 * 60 + 121), durationSeconds: 30 * 60)
        XCTAssertNil(covering([pastEdge]))
        // Watch workout starts 120 s after the draft finishes: overlaps; 121 s: does not.
        XCTAssertNotNil(covering([workout(note: "Apple Watch", startOffset: 60 * 60 + 120, durationSeconds: 600)]))
        XCTAssertNil(covering([workout(note: "Apple Watch", startOffset: 60 * 60 + 121, durationSeconds: 600)]))
    }

    func testEveryWatchAndHealthSourceCounts() {
        let notes = [
            "Garmin · 5/6 sets",
            "Garmin Fenix 8",
            "Apple Health · Strength training · 40:00",
            "Health Connect · Strength training",
            "Morning lift · Wear OS · Avg HR 110",
            "Apple Watch"
        ]
        for note in notes {
            let imported = workout(note: note, startOffset: 0, durationSeconds: 45 * 60)
            XCTAssertTrue(ActiveWorkoutWatchOverlap.isWatchOrImported(imported), note)
            XCTAssertNotNil(covering([imported]), note)
        }
    }

    func testWorkoutWithoutDurationOverlapsOnlyNearTheWindow() {
        XCTAssertNotNil(covering([workout(note: "Apple Watch", startOffset: 30 * 60, durationSeconds: nil)]))
        XCTAssertNil(covering([workout(note: "Apple Watch", startOffset: -10 * 60, durationSeconds: nil)]))
    }

    func testFinishBeforeStartIsClampedToTheStart() {
        let watch = workout(note: "Apple Watch", startOffset: 60, durationSeconds: 600)
        XCTAssertNotNil(covering([watch], finishedAt: draftStart.addingTimeInterval(-3_600)))
    }

    func testDialogCopyIsLocalized() {
        XCTAssertEqual(
            ActiveWorkoutFinishCopy.watchOverlapTitle(languageCode: "en"),
            "Another workout already covers this time"
        )
        XCTAssertEqual(
            ActiveWorkoutFinishCopy.watchOverlapMessage(languageCode: "uk"),
            "Зберегти й це тренування чи відкинути його?"
        )
        XCTAssertEqual(ActiveWorkoutFinishCopy.watchOverlapKeepBothButton(languageCode: "ru"), "Оставить обе")
        XCTAssertEqual(
            ActiveWorkoutFinishCopy.watchOverlapDiscardButton(languageCode: "ru"),
            "Удалить эту тренировку"
        )
    }
}
