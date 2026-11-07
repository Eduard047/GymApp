import XCTest
@testable import GymApp

final class ProgressMemoTests: XCTestCase {
    private func entry(_ date: Date, weight: Double = 50, reps: Int = 5, exercise: UUID = UUID()) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            setID: UUID(),
            workoutID: UUID(),
            sessionDate: date,
            exerciseID: exercise,
            exerciseName: "Squat",
            exerciseCatalogKey: nil,
            weight: weight,
            reps: reps,
            setOrderIndex: 0
        )
    }

    private func generatedHistory(now: Date, calendar: Calendar) -> [ExerciseHistoryEntry] {
        var generator = SystemRandomNumberGenerator()
        let exercises = (0 ..< 5).map { _ in UUID() }
        var rows: [ExerciseHistoryEntry] = []
        for _ in 0 ..< 600 {
            let hours = Int.random(in: -24 * 30 ... 24 * 120, using: &generator)
            let date = calendar.date(byAdding: .hour, value: -hours, to: now)!
            rows.append(entry(
                date,
                weight: Double(Int.random(in: 0 ... 4, using: &generator)) * 20,
                reps: Int.random(in: 1 ... 12, using: &generator),
                exercise: exercises.randomElement()!
            ))
        }
        // Duplicate timestamps, exactly like several sets of one workout.
        rows += rows.prefix(50).map { entry($0.sessionDate, weight: $0.weight, reps: $0.reps + 1, exercise: $0.exerciseID) }
        return rows.sorted { $0.sessionDate > $1.sessionDate }
    }

    func testWindowEqualsFullFilterIncludingBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var history = generatedHistory(now: now, calendar: calendar)
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let start = calendar.date(byAdding: .day, value: -7, to: monday)!
        let until = calendar.date(byAdding: .day, value: 7, to: start)!
        let before = calendar.date(byAdding: .day, value: -7, to: start)!
        for boundary in [before, start, until, now, before.addingTimeInterval(-0.001), before.addingTimeInterval(0.001),
                         until.addingTimeInterval(-0.001), until.addingTimeInterval(0.001), now.addingTimeInterval(0.001)] {
            history.append(entry(boundary))
        }
        history.sort { $0.sessionDate > $1.sessionDate }

        for (from, through, upper) in [
            (before, now, until), (before, until, until), (start, now, until), (before, now, start),
            (before, before, until), (now, now, now), (until, before, start)
        ] {
            let expected = history.filter { $0.sessionDate >= from && $0.sessionDate <= through && $0.sessionDate < upper }
            let sliced = WeeklyReview.window(history, from: from, through: through, before: upper)
            XCTAssertEqual(Array(sliced).map(\.setID), expected.map(\.setID))
        }
        XCTAssertTrue(WeeklyReview.window([], from: before, through: now, before: until).isEmpty)
    }

    func testBuildWithSortedHintMatchesFullScanForEveryOffset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let history = generatedHistory(now: now, calendar: calendar)
        for offset in [0, -1, -2, -5, -17, -520] {
            let full = WeeklyReview.build(history, offset: offset, now: now, calendar: calendar)
            let fast = WeeklyReview.build(history, offset: offset, now: now, calendar: calendar, historySortedNewestFirst: true)
            XCTAssertEqual(fast.start, full.start)
            XCTAssertEqual(fast.end, full.end)
            XCTAssertEqual(fast.partial, full.partial)
            XCTAssertEqual(fast.trainingDays, full.trainingDays)
            XCTAssertEqual(fast.comparableCount, full.comparableCount)
            XCTAssertEqual(fast.sessions.map(\.setID), full.sessions.map(\.setID))
            XCTAssertEqual(fast.insights.map(\.current.setID), full.insights.map(\.current.setID))
            XCTAssertEqual(fast.insights.map(\.previous.setID), full.insights.map(\.previous.setID))
        }
    }

    func testMemoReusesValueForSameKeyAndRecomputesOnKeyChange() {
        let memo = ProgressMemo<Int, String>()
        var computes = 0
        func get(_ key: Int) -> String {
            memo.value(for: key) { computes += 1; return "v\(key)-\(computes)" }
        }
        XCTAssertEqual(get(1), "v1-1")
        XCTAssertEqual(get(1), "v1-1")
        XCTAssertEqual(computes, 1)
        XCTAssertEqual(get(2), "v2-2")
        XCTAssertEqual(get(2), "v2-2")
        XCTAssertEqual(computes, 2)
        XCTAssertEqual(get(1), "v1-3")
        memo.invalidate()
        XCTAssertEqual(get(1), "v1-4")
    }

    func testOverviewKeyChangesWithEveryInput() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let base = ProgressOverviewKey(
            revision: 3, accountStorageKey: "a", referenceDate: date,
            calendar: calendar, languageCode: "en", workoutsPerWeek: 3
        )
        XCTAssertEqual(base, base)
        XCTAssertNotEqual(base, ProgressOverviewKey(revision: 4, accountStorageKey: "a", referenceDate: date, calendar: calendar, languageCode: "en", workoutsPerWeek: 3))
        XCTAssertNotEqual(base, ProgressOverviewKey(revision: 3, accountStorageKey: "b", referenceDate: date, calendar: calendar, languageCode: "en", workoutsPerWeek: 3))
        XCTAssertNotEqual(base, ProgressOverviewKey(revision: 3, accountStorageKey: "a", referenceDate: date.addingTimeInterval(1), calendar: calendar, languageCode: "en", workoutsPerWeek: 3))
        XCTAssertNotEqual(base, ProgressOverviewKey(revision: 3, accountStorageKey: "a", referenceDate: date, calendar: calendar, languageCode: "uk", workoutsPerWeek: 3))
        XCTAssertNotEqual(base, ProgressOverviewKey(revision: 3, accountStorageKey: "a", referenceDate: date, calendar: calendar, languageCode: "en", workoutsPerWeek: 4))
        XCTAssertNotEqual(ProgressMonthKey(base: base, monthOffset: 0), ProgressMonthKey(base: base, monthOffset: -1))
        XCTAssertNotEqual(
            ProgressMuscleKey(base: base, period: .week, selectedMuscleID: nil),
            ProgressMuscleKey(base: base, period: .week, selectedMuscleID: "chest")
        )
        XCTAssertNotEqual(
            WeeklyReviewMemoKey(revision: 1, accountStorageKey: "a", offset: 0, day: date),
            WeeklyReviewMemoKey(revision: 1, accountStorageKey: "a", offset: -1, day: date)
        )
    }
}
