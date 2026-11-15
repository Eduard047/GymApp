import Foundation
import XCTest
@testable import GymApp

final class ProgressOverviewPackageETests: XCTestCase {
    private let calendar = Calendar(identifier: .iso8601)
    private let now = Date(timeIntervalSince1970: 1_778_000_000)

    private func entry(
        _ exercise: UUID,
        name: String = "Bench press",
        daysAgo: Double,
        weight: Double,
        reps: Int
    ) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            setID: UUID(),
            workoutID: UUID(),
            sessionDate: now.addingTimeInterval(-daysAgo * 86_400),
            exerciseID: exercise,
            exerciseName: name,
            weight: weight,
            reps: reps,
            setOrderIndex: 0
        )
    }

    func testStrengthTrendReportsBestSetAndMonthDelta() {
        let bench = UUID()
        let history = [
            entry(bench, daysAgo: 3, weight: 100, reps: 5),
            entry(bench, daysAgo: 10, weight: 95, reps: 8),
            entry(bench, daysAgo: 40, weight: 95, reps: 5),
            entry(bench, daysAgo: 45, weight: 90, reps: 5),
        ]
        let rows = ProgressStrengthTrend.rows(history: history, now: now, calendar: calendar)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].bestWeight, 100)
        XCTAssertEqual(rows[0].bestReps, 5)
        XCTAssertEqual(rows[0].monthDelta, 5)
    }

    func testStrengthTrendHasNoDeltaWithoutBaselineAndHidesWithoutRecentSets() {
        let squat = UUID()
        let fresh = [entry(squat, name: "Squat", daysAgo: 2, weight: 120, reps: 3)]
        let rows = ProgressStrengthTrend.rows(history: fresh, now: now, calendar: calendar)
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].monthDelta)

        let stale = [entry(squat, name: "Squat", daysAgo: 50, weight: 120, reps: 3)]
        XCTAssertTrue(ProgressStrengthTrend.rows(history: stale, now: now, calendar: calendar).isEmpty)
    }

    func testStrengthTrendRanksByRecentSetsAndLimitsRows() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var history: [ExerciseHistoryEntry] = []
        for _ in 0 ..< 4 { history.append(entry(a, name: "A", daysAgo: 1, weight: 50, reps: 5)) }
        for _ in 0 ..< 3 { history.append(entry(b, name: "B", daysAgo: 1, weight: 60, reps: 5)) }
        for _ in 0 ..< 2 { history.append(entry(c, name: "C", daysAgo: 1, weight: 70, reps: 5)) }
        history.append(entry(d, name: "D", daysAgo: 1, weight: 80, reps: 5))
        let rows = ProgressStrengthTrend.rows(history: history, now: now, calendar: calendar)
        XCTAssertEqual(rows.map(\.name), ["A", "B", "C"])
    }

    func testStrengthTrendIgnoresBodyweightAndInvalidSets() {
        let pullup = UUID()
        let history = [
            entry(pullup, name: "Pull-up", daysAgo: 1, weight: 0, reps: 10),
            entry(pullup, name: "Pull-up", daysAgo: 1, weight: .nan, reps: 10),
            entry(pullup, name: "Pull-up", daysAgo: 1, weight: 20, reps: 0),
        ]
        XCTAssertTrue(ProgressStrengthTrend.rows(history: history, now: now, calendar: calendar).isEmpty)
    }

    func testWeeklyReviewTotalsCountOnlyTheSelectedWeek() {
        let monday = {
            var iso = calendar
            iso.firstWeekday = 2
            return iso.dateInterval(of: .weekOfYear, for: now)!.start
        }()
        let exercise = UUID()
        func at(_ day: Double, _ weight: Double, _ reps: Int, workout: UUID = UUID()) -> ExerciseHistoryEntry {
            ExerciseHistoryEntry(
                setID: UUID(), workoutID: workout, sessionDate: monday.addingTimeInterval(day * 86_400),
                exerciseID: exercise, exerciseName: "Row", weight: weight, reps: reps, setOrderIndex: 0
            )
        }
        let workoutOne = UUID()
        let history = [
            at(-3, 40, 10),
            at(0.1, 50, 10, workout: workoutOne),
            at(0.1, 50, 8, workout: workoutOne),
        ]
        let review = WeeklyReview.build(history, now: monday.addingTimeInterval(2 * 86_400), calendar: calendar)
        XCTAssertEqual(review.setCount, 2)
        XCTAssertEqual(review.workoutCount, 1)
        XCTAssertEqual(review.volume, 50 * 10 + 50 * 8, accuracy: 0.001)
    }
}
