import Foundation
import XCTest
@testable import GymApp

/// Runs shared/biggest-workout-v1.json, the same cases the Android suite runs.
final class BiggestWorkoutGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 19)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let zone = try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(item["timeZone"] as? String)), id)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let earlier = try XCTUnwrap(item["earlier"] as? [[String: Any]]).map { row in
                BiggestWorkoutSession(date: date(row["date"]), volume: (row["volume"] as? NSNumber)?.doubleValue ?? -1)
            }
            let current = try XCTUnwrap(item["current"] as? [String: Any])
            let actual = GymBiggestWorkout.badge(
                earlier: earlier,
                current: BiggestWorkoutSession(
                    date: date(current["date"]),
                    volume: (current["volume"] as? NSNumber)?.doubleValue ?? -1
                ),
                calendar: calendar
            )
            XCTAssertEqual(actual?.rawValue, item["expected"] as? String, id)
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
            .appendingPathComponent("shared/biggest-workout-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
