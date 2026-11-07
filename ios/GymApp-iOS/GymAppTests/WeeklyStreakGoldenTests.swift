import Foundation
import XCTest
@testable import GymApp

/// Runs shared/weekly-streak-v1.json, the same cases the Android suite runs.
final class WeeklyStreakGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let zoneID = try XCTUnwrap(root["timezone"] as? String)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zoneID))
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let target = try XCTUnwrap(item["targetPerWeek"] as? Int)
            let now = try date(item["now"])
            let sessions = try XCTUnwrap(item["sessions"] as? [String]).map { iso -> WorkoutSessionSummary in
                WorkoutSessionSummary(
                    workoutID: UUID(),
                    date: (try? date(iso)) ?? .distantPast,
                    note: nil,
                    exerciseCount: 1,
                    setCount: 3,
                    totalVolume: 1_000
                )
            }
            XCTAssertFalse(sessions.contains { $0.date == .distantPast }, "\(id) has an unparsable session")
            let period = try XCTUnwrap(item["period"] as? [String: Any])
            let expected = try XCTUnwrap(item["expected"] as? [String: Int])

            XCTAssertEqual(
                WeeklyStreakCalculator.current(
                    sessions: sessions,
                    targetTrainingDays: target,
                    now: now,
                    calendar: calendar
                ),
                expected["current"],
                "\(id) current"
            )
            XCTAssertEqual(
                WeeklyStreakCalculator.bestDuringPeriod(
                    sessions: sessions,
                    from: try date(period["start"]),
                    through: try date(period["end"]),
                    targetTrainingDays: target,
                    calendar: calendar
                ),
                expected["bestDuringPeriod"],
                "\(id) bestDuringPeriod"
            )
            XCTAssertEqual(
                WeeklyStreakCalculator.longest(
                    sessions: sessions.filter { $0.date <= now },
                    targetTrainingDays: target,
                    calendar: calendar
                ),
                expected["longest"],
                "\(id) longest"
            )
        }
    }

    private func date(_ value: Any?) throws -> Date {
        let text = try XCTUnwrap(value as? String)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: text), "Unparsable date \(text)")
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/weekly-streak-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
