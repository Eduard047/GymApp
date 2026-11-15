import Foundation
import XCTest
@testable import GymApp

/// Runs shared/strength-trends-v1.json, the same cases the Android suite runs.
final class StrengthTrendsGoldenTests: XCTestCase {
    func testSharedCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        let calendar = Calendar(identifier: .iso8601)
        let now = Date(timeIntervalSince1970: 1_778_000_000)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            var exercises: [Int: UUID] = [:]
            func uuid(_ number: Int) -> UUID {
                if let existing = exercises[number] { return existing }
                let created = UUID()
                exercises[number] = created
                return created
            }
            let sets = try XCTUnwrap(item["sets"] as? [[String: Any]])
            let history = try sets.map { set -> ExerciseHistoryEntry in
                let exercise = try XCTUnwrap(set["exercise"] as? Int)
                let daysAgo = try XCTUnwrap((set["daysAgo"] as? NSNumber)?.doubleValue)
                return ExerciseHistoryEntry(
                    setID: UUID(),
                    workoutID: UUID(),
                    sessionDate: now.addingTimeInterval(-daysAgo * 86_400),
                    exerciseID: uuid(exercise),
                    exerciseName: "Exercise \(exercise)",
                    weight: try XCTUnwrap((set["weight"] as? NSNumber)?.doubleValue),
                    reps: try XCTUnwrap(set["reps"] as? Int),
                    setOrderIndex: 0
                )
            }
            let expected = try XCTUnwrap(item["expected"] as? [[String: Any]])
            let rows = ProgressStrengthTrend.rows(history: history, now: now, calendar: calendar)

            XCTAssertEqual(rows.count, expected.count, id)
            for (row, want) in zip(rows, expected) {
                let exercise = try XCTUnwrap(want["exercise"] as? Int)
                XCTAssertEqual(row.exerciseID, exercises[exercise], "\(id): exercise order")
                XCTAssertEqual(row.bestWeight, (want["bestWeight"] as? NSNumber)?.doubleValue, "\(id): weight")
                XCTAssertEqual(row.bestReps, want["bestReps"] as? Int, "\(id): reps")
                if let delta = (want["monthDelta"] as? NSNumber)?.doubleValue {
                    XCTAssertEqual(try XCTUnwrap(row.monthDelta, "\(id): delta"), delta, accuracy: 0.0001, id)
                } else {
                    XCTAssertNil(row.monthDelta, "\(id): delta")
                }
            }
        }
    }

    private func contract() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("shared/strength-trends-v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
