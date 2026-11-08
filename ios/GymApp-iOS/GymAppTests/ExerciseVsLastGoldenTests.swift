import Foundation
import XCTest
@testable import GymApp

/// Runs shared/exercise-vs-last-v1.json, the same cases the Android suite runs.
final class ExerciseVsLastGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 18)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let current = try XCTUnwrap(item["currentSession"] as? [String: Any])
            let currentID = try XCTUnwrap(current["id"] as? Int)
            let currentDate = try XCTUnwrap((current["date"] as? NSNumber)?.doubleValue)
            let history = try XCTUnwrap(item["history"] as? [[String: Any]]).map { row in
                VsLastHistoryRow(
                    exerciseID: row["exerciseId"] as? Int ?? -1,
                    sessionID: row["sessionId"] as? Int ?? -1,
                    date: (row["date"] as? NSNumber)?.doubleValue ?? -1,
                    blockOrderIndex: row["blockOrderIndex"] as? Int ?? -1,
                    weight: (row["weight"] as? NSNumber)?.doubleValue ?? -1,
                    reps: row["reps"] as? Int ?? -1
                )
            }
            let expected = try XCTUnwrap(item["expected"] as? [[String: Any]])
            let actual = GymExerciseVsLast.rows(history: history, currentSessionID: currentID, currentDate: currentDate)

            XCTAssertEqual(actual.map(\.exerciseID), expected.map { $0["exerciseId"] as? Int ?? -1 }, id)
            for (row, want) in zip(actual, expected) {
                XCTAssertEqual(row.status.rawValue, want["status"] as? String, id)
                XCTAssertEqual(row.basis?.rawValue, want["basis"] as? String, id)
                let wantDelta = (want["delta"] as? NSNumber)?.doubleValue
                XCTAssertEqual(row.delta == nil, wantDelta == nil, id)
                if let delta = row.delta, let wantDelta {
                    XCTAssertEqual(delta, wantDelta, accuracy: 1e-9, id)
                }
                XCTAssertEqual(row.best, set(want["best"]), id)
                XCTAssertEqual(row.previousBest, set(want["previousBest"]), id)
            }
        }
    }

    func testStoredHistoryUsesWorkoutPositionAsSessionID() {
        let bench = UUID()
        let squat = UUID()
        let day = Date(timeIntervalSinceReferenceDate: 2_000_000)
        func entry(_ workout: UUID, _ order: Int, _ date: Date, _ exercise: UUID, _ block: Int, _ weight: Double, _ reps: Int) -> ExerciseHistoryEntry {
            ExerciseHistoryEntry(
                setID: UUID(), workoutID: workout, sessionDate: date, exerciseID: exercise,
                exerciseName: "x", exerciseCatalogKey: nil, weight: weight, reps: reps,
                setOrderIndex: 0, blockOrderIndex: block, workoutOrderIndex: order
            )
        }
        let older = UUID()
        let sameDayEarlier = UUID()
        let finished = UUID()
        let history = [
            entry(older, 0, day.addingTimeInterval(-100), bench, 0, 50, 10),
            entry(sameDayEarlier, 1, day, bench, 1, 60, 8),
            entry(sameDayEarlier, 1, day, bench, 0, 60, 5),
            entry(finished, 2, day, squat, 0, 100, 5),
            entry(finished, 2, day, bench, 1, 60, 10)
        ]
        let rows = GymExerciseVsLast.rows(history: history, workoutID: finished, currentDate: day)
        // Same date: the earlier-stored workout counts as previous; its first block (60 x 5 = 300) is used.
        XCTAssertEqual(rows.map(\.exerciseID), [squat.uuidString, bench.uuidString])
        XCTAssertEqual(rows.map(\.status), [.new, .up])
        XCTAssertEqual(rows[1].delta, 300)
        XCTAssertEqual(rows[1].previousBest, VsLastSet(weight: 60, reps: 5))
        XCTAssertTrue(GymExerciseVsLast.rows(history: history, workoutID: UUID(), currentDate: day).isEmpty)
    }

    private func set(_ value: Any?) -> VsLastSet? {
        guard let dict = value as? [String: Any] else { return nil }
        return VsLastSet(
            weight: (dict["weight"] as? NSNumber)?.doubleValue ?? -1,
            reps: dict["reps"] as? Int ?? -1
        )
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/exercise-vs-last-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
