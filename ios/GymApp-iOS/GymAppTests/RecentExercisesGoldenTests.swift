import Foundation
import XCTest
@testable import GymApp

/// Runs shared/recent-exercises-v1.json, the same cases the Android suite runs.
final class RecentExercisesGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let rows = try XCTUnwrap(item["history"] as? [[String: Any]]).map { row in
                RecentExerciseRow(
                    exerciseID: row["exerciseId"] as? Int ?? -1,
                    sessionID: row["sessionId"] as? Int ?? -1,
                    date: (row["date"] as? NSNumber)?.doubleValue ?? -1,
                    blockOrderIndex: row["blockOrderIndex"] as? Int ?? -1
                )
            }
            let eligible = Set(try XCTUnwrap(item["eligibleExerciseIds"] as? [Int]))
            let expected = try XCTUnwrap(item["expected"] as? [Int])
            XCTAssertEqual(
                GymRecentExercises.ids(
                    history: rows,
                    pickerIDs: eligible,
                    query: item["query"] as? String ?? ""
                ),
                expected,
                id
            )
        }
    }

    func testStoredWorkoutsFollowTheSameRules() {
        let ids = (0..<10).map { _ in UUID() }
        let day = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func block(_ index: Int, sets: Int = 1) -> WorkoutExercise {
            WorkoutExercise(
                exerciseID: ids[index],
                sets: (0..<sets).map { _ in WorkoutSet(weight: 0, reps: 0) }
            )
        }
        let older = WorkoutSession(date: day, exercises: [block(0), block(1), block(2)])
        let newer = WorkoutSession(
            date: day.addingTimeInterval(60),
            exercises: [block(3), block(1, sets: 0), block(4), block(3)]
        )
        let all = Set(ids)
        // Newest session first in block order; the empty block of ids[1] is skipped there, so
        // ids[1] keeps its older position; ids[3] is listed once.
        XCTAssertEqual(
            GymRecentExercises.ids(workouts: [older, newer], pickerIDs: all),
            [ids[3], ids[4], ids[0], ids[1], ids[2]]
        )
        // Same date: the later-stored workout wins.
        let sameDay = WorkoutSession(date: day, exercises: [block(5)])
        XCTAssertEqual(
            GymRecentExercises.ids(workouts: [sameDay, older], pickerIDs: all),
            [ids[0], ids[1], ids[2], ids[5]]
        )
        XCTAssertEqual(GymRecentExercises.ids(workouts: [older, newer], pickerIDs: all, query: "bench"), [])
        XCTAssertEqual(GymRecentExercises.ids(workouts: [], pickerIDs: all), [])
        XCTAssertEqual(
            GymRecentExercises.ids(workouts: [older, newer], pickerIDs: [ids[2], ids[4]]),
            [ids[4], ids[2]]
        )
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/recent-exercises-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
