import Foundation
import XCTest
@testable import GymApp

/// Runs shared/today-presentation-v1.json, the same cases the Android suite runs.
final class TodayPresentationGoldenTests: XCTestCase {
    func testWeekdayLabelsMatchContract() throws {
        let weekdays = try XCTUnwrap(contract()["weekdays"] as? [String: [String]])
        for language in ["ru", "uk", "en"] {
            let expected = try XCTUnwrap(weekdays[language], language)
            XCTAssertEqual(TodayPresentation.weekdayLabels(languageCode: language), expected, language)
            for (index, label) in expected.enumerated() {
                XCTAssertEqual(
                    TodayPresentation.weekdayLabel(mondayIndex: index, languageCode: language),
                    label
                )
            }
        }
    }

    func testWeekComparisonVisibilityMatchesContract() throws {
        let cases = try XCTUnwrap(contract()["weekComparison"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            XCTAssertEqual(
                TodayPresentation.showsWeekComparison(
                    currentWorkouts: try XCTUnwrap(item["currentWorkouts"] as? Int),
                    comparisonWorkouts: try XCTUnwrap(item["comparisonWorkouts"] as? Int)
                ),
                try XCTUnwrap(item["visible"] as? Bool),
                id
            )
        }
    }

    func testStatLabelsAgreeWithCountsInEveryLanguage() throws {
        let labels = try XCTUnwrap(contract()["statLabels"] as? [String: [[String: Any]]])
        let nouns: [(String, TodayPresentation.StatNoun)] = [("workouts", .workout), ("minutes", .minute)]
        for (key, noun) in nouns {
            for item in try XCTUnwrap(labels[key], key) {
                let count = try XCTUnwrap(item["count"] as? Int)
                for language in ["ru", "uk", "en"] {
                    XCTAssertEqual(
                        TodayPresentation.statLabel(noun, count: count, languageCode: language),
                        try XCTUnwrap(item[language] as? String),
                        "\(key) \(count) \(language)"
                    )
                }
            }
        }
    }

    func testSummaryHidesComparisonUnlessBothWeeksHaveWorkouts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func day(_ d: Int, _ month: Int = 11) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: month, day: d, hour: 9
            )))
        }
        func session(_ date: Date, volume: Double) -> WorkoutSessionSummary {
            WorkoutSessionSummary(
                workoutID: UUID(), date: date, note: nil,
                exerciseCount: 1, setCount: 1, totalVolume: volume
            )
        }
        let now = try day(4)
        // Wed 4 Nov; comparison window is Mon 26 Oct..Wed 28 Oct.
        let thisWeek = session(try day(2), volume: 500)
        let lastWeek = session(try day(26, 10), volume: 1000)

        func summary(_ sessions: [WorkoutSessionSummary]) -> WeeklyTrainingSummary {
            WeeklyTrainingSummary(sessions: sessions, now: now, calendar: calendar)
        }
        XCTAssertTrue(summary([thisWeek, lastWeek]).showsVolumeComparison)
        XCTAssertEqual(summary([thisWeek, lastWeek]).volumeDeltaPercent, -50)
        XCTAssertFalse(summary([lastWeek]).showsVolumeComparison, "empty current week")
        XCTAssertFalse(summary([thisWeek]).showsVolumeComparison, "empty comparison week")
        XCTAssertFalse(summary([]).showsVolumeComparison)
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/today-presentation-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
