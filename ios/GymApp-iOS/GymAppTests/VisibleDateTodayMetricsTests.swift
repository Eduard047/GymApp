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
        let ukrainianDate = gymFormattedDate(
            date,
            date: .long,
            time: .omitted,
            languageCode: "uk"
        ).lowercased()
        XCTAssertTrue(ukrainianDate.contains("13 серпня 2026"))
        XCTAssertFalse(ukrainianDate.contains("13 серпень"))
    }

    func testWeekRangeMatchesWebFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        }
        let now = day(2026, 10, 16)
        func range(_ a: Date, _ b: Date, _ code: String) -> String {
            gymFormattedDateRange(from: a, to: b, calendar: calendar, now: now, languageCode: code)
        }
        let sameMonth = (day(2026, 10, 12), day(2026, 10, 18))
        let crossMonth = (day(2026, 9, 28), day(2026, 10, 4))
        let otherYear = (day(2025, 9, 22), day(2025, 9, 28))
        let crossYear = (day(2025, 12, 29), day(2026, 1, 4))

        XCTAssertEqual(range(sameMonth.0, sameMonth.1, "ru"), "12 окт. \u{2013} 18 окт.")
        XCTAssertEqual(range(sameMonth.0, sameMonth.1, "uk"), "12 жовт. \u{2013} 18 жовт.")
        XCTAssertEqual(range(sameMonth.0, sameMonth.1, "en"), "Oct 12 \u{2013} Oct 18")
        XCTAssertEqual(range(crossMonth.0, crossMonth.1, "ru"), "28 сент. \u{2013} 4 окт.")
        XCTAssertEqual(range(crossMonth.0, crossMonth.1, "en"), "Sep 28 \u{2013} Oct 4")

        // The year is added to both ends when either end is outside the current year.
        XCTAssertEqual(range(otherYear.0, otherYear.1, "en"), "Sep 22, 2025 \u{2013} Sep 28, 2025")
        XCTAssertEqual(range(crossYear.0, crossYear.1, "en"), "Dec 29, 2025 \u{2013} Jan 4, 2026")
        for code in ["ru", "uk"] {
            let text = range(crossYear.0, crossYear.1, code)
            XCTAssertTrue(text.contains("2025") && text.contains("2026") && text.contains("\u{2013}"), text)
        }

        XCTAssertEqual(
            gymSpokenDateRange(from: sameMonth.0, to: sameMonth.1, calendar: calendar, now: now, languageCode: "ru"),
            "с 12 окт. по 18 окт."
        )
        XCTAssertEqual(
            gymSpokenDateRange(from: sameMonth.0, to: sameMonth.1, calendar: calendar, now: now, languageCode: "en"),
            "from Oct 12 to Oct 18"
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

    func testWeeklySummaryUsesLocalMondayDistinctDaysAndCanonicalDurations() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "uk_UA")
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 60 * 60)!
        let now = date(2026, 8, 15, hour: 18, calendar: calendar)
        let sessions = [
            summary(
                date: date(2026, 8, 10, hour: 8, calendar: calendar),
                exerciseCount: 3,
                setCount: 9,
                volume: 1_000
            ),
            summary(
                date: date(2026, 8, 15, hour: 9, calendar: calendar),
                exerciseCount: 20,
                setCount: 100,
                volume: 2_000
            ),
            summary(
                date: date(2026, 8, 15, hour: 11, calendar: calendar),
                note: "Garmin · Duration 1:00:01",
                exerciseCount: 1,
                setCount: 1,
                volume: 500
            ),
            summary(
                date: date(2026, 8, 16, hour: 12, calendar: calendar),
                exerciseCount: 20,
                setCount: 100,
                volume: 9_000
            ),
            summary(
                date: date(2026, 8, 9, hour: 12, calendar: calendar),
                exerciseCount: 20,
                setCount: 100,
                volume: 9_000
            ),
            summary(
                date: date(2026, 8, 17, hour: 12, calendar: calendar),
                exerciseCount: 20,
                setCount: 100,
                volume: 9_000
            )
        ]

        let summary = WeeklyTrainingSummary(
            sessions: sessions,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.weekStart, date(2026, 8, 10, calendar: calendar))
        XCTAssertEqual(summary.completedSessionCount, 3)
        XCTAssertEqual(summary.completedTrainingDays.count, 2)
        XCTAssertEqual(summary.totalMinutes, 27 + 90 + 61)
        XCTAssertEqual(summary.totalVolume, 3_500)
        XCTAssertTrue(summary.hasCompletedWorkoutToday(now: now, calendar: calendar))
        XCTAssertFalse(
            summary.hasWorkout(
                on: date(2026, 8, 16, calendar: calendar),
                calendar: calendar
            )
        )
    }

    func testWeeklySummaryCanAnchorHistoricalWeekWithoutIncludingCurrentOrFutureSessions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 8, 15, hour: 12, calendar: calendar)
        let sessions = [
            summary(date: date(2026, 8, 5, hour: 8, calendar: calendar), volume: 100),
            summary(date: date(2026, 8, 12, hour: 8, calendar: calendar), volume: 200),
            summary(date: date(2026, 8, 15, hour: 18, calendar: calendar), volume: 300)
        ]

        let historical = WeeklyTrainingSummary(
            sessions: sessions,
            weekContaining: date(2026, 8, 5, calendar: calendar),
            now: now,
            calendar: calendar
        )
        let current = WeeklyTrainingSummary(
            sessions: sessions,
            weekContaining: date(2026, 8, 15, calendar: calendar),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(historical.weekStart, date(2026, 8, 3, calendar: calendar))
        XCTAssertEqual(historical.completedSessionCount, 1)
        XCTAssertEqual(historical.totalVolume, 100)
        XCTAssertFalse(historical.hasCompletedWorkoutToday(now: now, calendar: calendar))
        XCTAssertEqual(current.completedSessionCount, 1)
        XCTAssertEqual(current.totalVolume, 200)
    }

    func testWeeklyDurationPrefersNativeMeasurementAndFallsBackWithoutIt() {
        XCTAssertEqual(
            WeeklyTrainingSummary.durationMinutes(
                for: summary(durationSeconds: 95, exerciseCount: 20, setCount: 100, volume: 0)
            ),
            2
        )
        XCTAssertEqual(
            WeeklyTrainingSummary.durationMinutes(
                for: summary(durationSeconds: 0, exerciseCount: 20, setCount: 100, volume: 0)
            ),
            0
        )
        XCTAssertEqual(
            WeeklyTrainingSummary.durationMinutes(
                for: summary(exerciseCount: 3, setCount: 9, volume: 0)
            ),
            27
        )
        XCTAssertEqual(
            WeeklyTrainingSummary.durationMinutes(
                for: summary(
                    note: "Garmin · Duration 0:00",
                    exerciseCount: 20,
                    setCount: 100,
                    volume: 0
                )
            ),
            90
        )
    }

    func testMonthlySummaryUsesSelectedMonthDistinctDaysAndExcludesFutureSessions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 8, 15, hour: 12, calendar: calendar)
        let sessions = [
            summary(
                date: date(2026, 7, 2, hour: 8, calendar: calendar),
                exerciseCount: 2,
                setCount: 3,
                volume: 100
            ),
            summary(
                date: date(2026, 7, 20, hour: 8, calendar: calendar),
                durationSeconds: 61,
                volume: 200
            ),
            summary(
                date: date(2026, 7, 20, hour: 10, calendar: calendar),
                volume: .nan
            ),
            summary(date: date(2026, 8, 10, hour: 8, calendar: calendar), volume: 300),
            summary(date: date(2026, 8, 15, hour: 18, calendar: calendar), volume: 500)
        ]

        let july = MonthlyTrainingSummary(
            sessions: sessions,
            monthContaining: date(2026, 7, 10, calendar: calendar),
            now: now,
            calendar: calendar
        )
        let august = MonthlyTrainingSummary(
            sessions: sessions,
            monthContaining: now,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(july.monthStart, date(2026, 7, 1, calendar: calendar))
        XCTAssertEqual(july.completedSessionCount, 3)
        XCTAssertEqual(july.completedTrainingDays.count, 2)
        XCTAssertEqual(july.totalMinutes, 24)
        XCTAssertEqual(july.totalVolume, 300)
        XCTAssertEqual(august.completedSessionCount, 1)
        XCTAssertEqual(august.totalVolume, 300)
    }

    private func summary(
        date: Date = Date(timeIntervalSince1970: 1_786_588_800),
        note: String? = nil,
        durationSeconds: Int? = nil,
        exerciseCount: Int = 1,
        setCount: Int = 1,
        volume: Double
    ) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            workoutID: UUID(),
            date: date,
            note: note,
            durationSeconds: durationSeconds,
            exerciseCount: exerciseCount,
            setCount: setCount,
            totalVolume: volume
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
