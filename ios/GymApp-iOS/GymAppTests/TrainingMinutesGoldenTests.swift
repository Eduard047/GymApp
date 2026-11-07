import Foundation
import XCTest
@testable import GymApp

/// Runs shared/training-minutes-v1.json, the same cases the Android suite runs.
final class TrainingMinutesGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 20)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let session = WorkoutSessionSummary(
                workoutID: UUID(),
                date: Date(timeIntervalSince1970: 1_700_000_000),
                note: item["note"] as? String,
                durationSeconds: item["durationSeconds"] as? Int,
                exerciseCount: try XCTUnwrap(item["exerciseCount"] as? Int),
                setCount: try XCTUnwrap(item["setCount"] as? Int),
                totalVolume: 0
            )
            XCTAssertEqual(
                WeeklyTrainingSummary.durationMinutes(for: session),
                try XCTUnwrap(item["expectedMinutes"] as? Int),
                id
            )
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/training-minutes-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
