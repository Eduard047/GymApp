import Foundation
import XCTest
@testable import GymApp

/// Runs shared/untrained-muscles-v1.json, the same cases the Android suite runs.
final class UntrainedMusclesGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let contract = try contract()
        XCTAssertEqual(contract["majorMuscles"] as? [String], GymUntrainedMuscles.majorMuscleIDs)
        let cases = try XCTUnwrap(contract["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 19)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let zone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(item["timeZone"] as? String)), id)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let workouts = try XCTUnwrap(item["workouts"] as? [NSNumber]).map { date($0) }
            let sets = try XCTUnwrap(item["sets"] as? [[String: Any]]).map { row in
                UntrainedMuscleSet(
                    date: date(row["date"]),
                    reps: (row["reps"] as? NSNumber)?.intValue ?? 0,
                    muscles: (row["muscles"] as? [String: NSNumber])?.mapValues(\.doubleValue) ?? [:]
                )
            }
            let actual = GymUntrainedMuscles.untrainedMuscleIDs(
                workoutDates: workouts,
                sets: sets,
                now: date(item["now"]),
                calendar: calendar
            )
            XCTAssertEqual(actual, item["expected"] as? [String], id)
        }
    }

    private func date(_ value: Any?) -> Date {
        Date(timeIntervalSince1970: ((value as? NSNumber)?.doubleValue ?? 0) / 1000)
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/untrained-muscles-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
