import Foundation
import XCTest
@testable import GymApp

final class VisibleDateTodayMetricsTests: XCTestCase {
    func testVisibleCalendarDateIncludesLocalizedWeekday() {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13))!

        XCTAssertEqual(
            gymFormattedDate(date, date: .long, time: .omitted, languageCode: "en"),
            "Thursday, August 13, 2026"
        )
        XCTAssertTrue(
            gymFormattedDate(date, date: .long, time: .omitted, languageCode: "ru")
                .lowercased()
                .contains("четверг")
        )
        XCTAssertTrue(
            gymFormattedDate(date, date: .long, time: .omitted, languageCode: "uk")
                .lowercased()
                .contains("четвер")
        )
    }

    func testStatusTimestampDoesNotGainWeekday() {
        let date = Date(timeIntervalSince1970: 1_786_588_800)
        let timestamp = gymFormattedTimestamp(
            date,
            date: .abbreviated,
            time: .shortened,
            languageCode: "en"
        )
        XCTAssertFalse(timestamp.contains("Thu"))
        XCTAssertFalse(timestamp.contains("Thursday"))
    }

    func testTodayMetricsUseCompletedSummariesAndBoundInvalidVolume() {
        let sessions = [
            summary(volume: 1_250.5),
            summary(volume: .nan),
            summary(volume: -50),
            summary(volume: 2_000_000_000_000_000)
        ]

        let metrics = TodayHeroMetrics(sessions: sessions, weeklyStreakWeeks: -3)
        XCTAssertEqual(metrics.totalWorkouts, 4)
        XCTAssertEqual(metrics.weeklyStreakWeeks, 0)
        XCTAssertEqual(metrics.totalVolume, 1_000_000_000_000_000)
    }

    private func summary(volume: Double) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            workoutID: UUID(),
            date: Date(timeIntervalSince1970: 1_786_588_800),
            note: nil,
            exerciseCount: 1,
            setCount: 1,
            totalVolume: volume
        )
    }
}
