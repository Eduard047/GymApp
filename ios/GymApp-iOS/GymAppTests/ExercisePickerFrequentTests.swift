import Foundation
import XCTest
@testable import GymApp

final class ExercisePickerFrequentTests: XCTestCase {
    private func ids(_ count: Int) -> [UUID] {
        (0..<count).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0 + 1))! }
    }

    func testTakesTopTwelveByWorkoutCountDescending() {
        let all = ids(15)
        var counts: [UUID: Int] = [:]
        for (index, id) in all.enumerated() { counts[id] = index + 1 }

        let result = ExercisePickerFrequent.topIDs(sessionCounts: counts)

        XCTAssertEqual(result.count, 12)
        XCTAssertEqual(result, Array(all.reversed().prefix(12)))
    }

    func testTiesResolvedByLatestSessionDateThenStableID() {
        let all = ids(4)
        let counts = Dictionary(uniqueKeysWithValues: all.map { ($0, 3) })
        let dates: [UUID: Date] = [
            all[0]: Date(timeIntervalSince1970: 100),
            all[1]: Date(timeIntervalSince1970: 300),
            all[2]: Date(timeIntervalSince1970: 300),
            all[3]: Date(timeIntervalSince1970: 200)
        ]

        let result = ExercisePickerFrequent.topIDs(sessionCounts: counts, latestSessionDates: dates)

        XCTAssertEqual(result, [all[1], all[2], all[3], all[0]])
    }

    func testExcludesZeroCountExercisesAndHonorsLimit() {
        let all = ids(3)
        let counts = [all[0]: 0, all[1]: 2, all[2]: 1]

        XCTAssertEqual(ExercisePickerFrequent.topIDs(sessionCounts: counts), [all[1], all[2]])
        XCTAssertEqual(ExercisePickerFrequent.topIDs(sessionCounts: counts, limit: 1), [all[1]])
        XCTAssertEqual(ExercisePickerFrequent.topIDs(sessionCounts: counts, limit: 0), [])
        XCTAssertEqual(ExercisePickerFrequent.topIDs(sessionCounts: [all[0]: 0]), [])
    }

    func testLatestSessionDatesKeepsNewestPerExercise() {
        let exerciseID = ids(1)[0]
        func entry(_ seconds: TimeInterval) -> ExerciseHistoryEntry {
            ExerciseHistoryEntry(
                setID: UUID(),
                workoutID: UUID(),
                sessionDate: Date(timeIntervalSince1970: seconds),
                exerciseID: exerciseID,
                exerciseName: "Bench",
                exerciseCatalogKey: nil,
                weight: 50,
                reps: 5,
                setOrderIndex: 0
            )
        }

        let result = ExercisePickerFrequent.latestSessionDates(from: [entry(10), entry(30), entry(20)])

        XCTAssertEqual(result[exerciseID], Date(timeIntervalSince1970: 30))
    }
}
