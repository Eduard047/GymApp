import Foundation
import XCTest
@testable import GymApp

/// Runs shared/remaining-workout-estimate-v1.json, the same cases the Android suite runs.
final class RemainingWorkoutEstimateGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        XCTAssertEqual(root["minutesPerExercise"] as? Int, RemainingWorkoutEstimate.minutesPerExercise)
        XCTAssertEqual(root["minutesPerSet"] as? Int, RemainingWorkoutEstimate.minutesPerSet)
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let exercises = try XCTUnwrap(item["exercises"] as? [[String: Any]])
            let remaining = try exercises.map { try XCTUnwrap($0["remainingSets"] as? Int, id) }
            let actual = RemainingWorkoutEstimate.estimate(remainingSetsPerExercise: remaining)

            if let expected = item["expected"] as? [String: Any] {
                XCTAssertEqual(actual?.setsLeft, expected["setsLeft"] as? Int, id)
                XCTAssertEqual(actual?.minutes, expected["minutes"] as? Int, id)
            } else {
                XCTAssertNil(actual, id)
            }
        }
    }

    func testDraftCountsOnlyUnrecordedSets() {
        let done = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = ActiveWorkoutDraft(
            workoutDate: done,
            exercises: [
                ActiveWorkoutExercise(exerciseID: UUID(), sets: [
                    ActiveWorkoutSet(weight: 50, reps: 5, completedAt: done),
                    ActiveWorkoutSet(weight: 50, reps: 5)
                ]),
                ActiveWorkoutExercise(exerciseID: UUID(), sets: [
                    ActiveWorkoutSet(weight: 20, reps: 8, completedAt: done)
                ])
            ]
        )
        XCTAssertEqual(
            RemainingWorkoutEstimate.estimate(draft: draft),
            RemainingWorkoutEstimate.Result(setsLeft: 1, minutes: 5)
        )
    }

    func testTextUsesCorrectPluralForms() {
        func text(_ sets: Int, _ code: String) -> String {
            RemainingWorkoutEstimate.text(.init(setsLeft: sets, minutes: 12), languageCode: code)
        }
        let nb = "\u{00A0}"
        XCTAssertEqual(text(1, "en"), "1\(nb)set left · ~12\(nb)min")
        XCTAssertEqual(text(5, "en"), "5\(nb)sets left · ~12\(nb)min")
        XCTAssertEqual(text(1, "uk"), "Залишився 1\(nb)підхід · ~12\(nb)хв")
        XCTAssertEqual(text(3, "uk"), "Залишилось 3\(nb)підходи · ~12\(nb)хв")
        XCTAssertEqual(text(11, "uk"), "Залишилось 11\(nb)підходів · ~12\(nb)хв")
        XCTAssertEqual(text(1, "ru"), "Остался 1\(nb)подход · ~12\(nb)мин")
        XCTAssertEqual(text(22, "ru"), "Осталось 22\(nb)подхода · ~12\(nb)мин")
        XCTAssertEqual(text(5, "ru"), "Осталось 5\(nb)подходов · ~12\(nb)мин")
    }

    func testAccessibilityTextReadsNaturally() {
        let one = RemainingWorkoutEstimate.Result(setsLeft: 1, minutes: 1)
        let many = RemainingWorkoutEstimate.Result(setsLeft: 4, minutes: 22)
        XCTAssertTrue(RemainingWorkoutEstimate.accessibilityText(one, languageCode: "en").hasSuffix("about 1 minute"))
        XCTAssertTrue(RemainingWorkoutEstimate.accessibilityText(many, languageCode: "en").hasSuffix("about 22 minutes"))
        XCTAssertTrue(RemainingWorkoutEstimate.accessibilityText(many, languageCode: "uk").hasSuffix("приблизно 22 хвилини"))
        XCTAssertTrue(RemainingWorkoutEstimate.accessibilityText(many, languageCode: "ru").hasSuffix("примерно 22 минуты"))
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/remaining-workout-estimate-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
