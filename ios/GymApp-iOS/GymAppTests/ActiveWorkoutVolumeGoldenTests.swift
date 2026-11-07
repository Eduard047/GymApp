import Foundation
import XCTest
@testable import GymApp

/// Runs shared/active-volume-v1.json, the same cases the Android suite runs.
final class ActiveWorkoutVolumeGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        let languages = try XCTUnwrap(root["languages"] as? [String])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        XCTAssertEqual(languages.count, 3)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let sets = try XCTUnwrap(item["sets"] as? [[String: Any]]).map { set -> ActiveWorkoutSet in
                let weight = (set["weight"] as? NSNumber)?.doubleValue ?? .nan
                let reps = (set["reps"] as? NSNumber)?.intValue ?? 0
                let completed = (set["completed"] as? Bool) ?? false
                return ActiveWorkoutSet(weight: weight, reps: reps, completedAt: completed ? Date(timeIntervalSince1970: 1) : nil)
            }
            let expectedVolume = try XCTUnwrap((item["volume"] as? NSNumber)?.doubleValue)
            let visible = try XCTUnwrap(item["visible"] as? Bool)
            let text = try XCTUnwrap(item["text"] as? [String: String])

            let draft = ActiveWorkoutDraft(
                workoutDate: Date(timeIntervalSince1970: 0),
                exercises: [ActiveWorkoutExercise(exerciseID: UUID(), sets: sets)]
            )
            XCTAssertEqual(draft.completedVolume, expectedVolume, accuracy: 1e-9, "\(id) volume")
            XCTAssertEqual(draft.completedVolume >= 0.5, visible, "\(id) visible")
            for language in languages {
                let expectedText = try XCTUnwrap(text[language])
                let unit = gymLocalized("kg", languageCode: language)
                XCTAssertEqual(
                    gymHeroVolumeText(draft.completedVolume, languageCode: language),
                    "\(expectedText)\u{00A0}\(unit)",
                    "\(id) text \(language)"
                )
            }
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/active-volume-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
