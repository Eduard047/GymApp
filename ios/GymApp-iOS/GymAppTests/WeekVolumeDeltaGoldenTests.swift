import Foundation
import XCTest
@testable import GymApp

/// Runs shared/week-volume-delta-v1.json, the same cases the Android suite runs.
final class WeekVolumeDeltaGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let zoneID = try XCTUnwrap(item["zone"] as? String)
            let zone = try XCTUnwrap(TimeZone(identifier: zoneID), id)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone

            let rows = try XCTUnwrap(item["sessions"] as? [[String: Any]])
            let sessions = try rows.map { row in
                WorkoutSessionSummary(
                    workoutID: UUID(),
                    date: try date(try XCTUnwrap(row["at"] as? String), calendar: calendar),
                    note: nil,
                    exerciseCount: 1,
                    setCount: 1,
                    totalVolume: try XCTUnwrap(row["volume"] as? Double)
                )
            }
            let now = try date(try XCTUnwrap(item["now"] as? String), calendar: calendar)
            let offset = try XCTUnwrap(item["weekOffset"] as? Int)
            let reference = try XCTUnwrap(calendar.date(byAdding: .day, value: offset * 7, to: now))

            let actual = weekVolumeDeltaPercent(
                sessions: sessions,
                weekContaining: reference,
                now: now,
                calendar: calendar
            )
            let expected = item["expectedPercent"] as? Int
            XCTAssertEqual(actual, expected, id)

            let summary = WeeklyTrainingSummary(
                sessions: sessions,
                weekContaining: reference,
                now: now,
                calendar: calendar
            )
            XCTAssertEqual(summary.volumeDeltaPercent, expected, "\(id) summary")
        }
    }

    func testDisplayUsesTrueMinusSignAndNoSignForZero() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(weekVolumeDeltaText(12, locale: locale), "+12%")
        XCTAssertEqual(weekVolumeDeltaText(-8, locale: locale), "\u{2212}8%")
        XCTAssertEqual(weekVolumeDeltaText(0, locale: locale), "0%")
        XCTAssertEqual(weekVolumeDeltaText(999, locale: locale), "+999%")
    }

    private func date(_ local: String, calendar: Calendar) throws -> Date {
        let parts = local.split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        XCTAssertEqual(parts.count, 6, local)
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = parts[3]
        components.minute = parts[4]
        components.second = parts[5]
        return try XCTUnwrap(calendar.date(from: components), local)
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/week-volume-delta-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
