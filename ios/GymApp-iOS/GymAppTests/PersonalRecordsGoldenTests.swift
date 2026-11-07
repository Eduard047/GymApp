import Foundation
import XCTest
@testable import GymApp

/// Runs shared/personal-records-v1.json, the same cases the Android suite runs.
final class PersonalRecordsGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let expected = try XCTUnwrap(item["expected"] as? [String: Any])

            // Exercise keys map to ids on first use.
            var ids: [String: UUID] = [:]
            func idOf(_ key: String) -> UUID {
                if let existing = ids[key] { return existing }
                let created = UUID()
                ids[key] = created
                return created
            }

            let historyItems = try XCTUnwrap(item["history"] as? [[String: Any]])
            var history: [ExerciseHistoryEntry] = []
            let workoutID = UUID()
            for (index, entry) in historyItems.enumerated() {
                let key = try XCTUnwrap(entry["exercise"] as? String)
                history.append(
                    ExerciseHistoryEntry(
                        setID: UUID(),
                        workoutID: workoutID,
                        sessionDate: start.addingTimeInterval(-86_400),
                        exerciseID: idOf(key),
                        exerciseName: key,
                        weight: try number(entry["weight"]),
                        reps: try XCTUnwrap(entry["reps"] as? Int),
                        setOrderIndex: index
                    )
                )
            }
            let baselines = LivePersonalRecords.baselines(history: history)

            let expectedBaselines = try XCTUnwrap(expected["baselines"] as? [String: [String: Any]])
            XCTAssertEqual(baselines.count, expectedBaselines.count, "\(id) baseline exercises")
            for (key, want) in expectedBaselines {
                let baseline = try XCTUnwrap(baselines[idOf(key)], "\(id) \(key) baseline")
                XCTAssertEqual(baseline.bestWeight, try number(want["bestWeight"]), accuracy: 1e-6, "\(id) \(key) bestWeight")
                XCTAssertEqual(
                    baseline.bestEstimatedOneRepMax,
                    try number(want["bestEstimatedOneRepMax"]),
                    accuracy: 1e-6,
                    "\(id) \(key) bestEstimatedOneRepMax"
                )
            }

            // Every set is completed one minute after the previous one, in list order.
            var minute: Double = 0
            var blocks: [ActiveWorkoutExercise] = []
            var keys: [String] = []
            for exercise in try XCTUnwrap(item["workout"] as? [[String: Any]]) {
                let key = try XCTUnwrap(exercise["exercise"] as? String)
                var sets: [ActiveWorkoutSet] = []
                for set in try XCTUnwrap(exercise["sets"] as? [[String: Any]]) {
                    minute += 1
                    sets.append(
                        ActiveWorkoutSet(
                            weight: try number(set["weight"]),
                            reps: try XCTUnwrap(set["reps"] as? Int),
                            completedAt: start.addingTimeInterval(minute * 60)
                        )
                    )
                }
                blocks.append(ActiveWorkoutExercise(exerciseID: idOf(key), sets: sets))
                keys.append(key)
            }
            let draft = ActiveWorkoutDraft(startedAt: start, workoutDate: start, exercises: blocks)
            let records = LivePersonalRecords.recordSetIDs(in: draft, baselines: baselines)

            let expectedRecords = try XCTUnwrap(expected["records"] as? [[String: Any]])
            XCTAssertEqual(expectedRecords.count, blocks.count, "\(id) exercise count")
            for (index, want) in expectedRecords.enumerated() {
                XCTAssertEqual(want["exercise"] as? String, keys[index], "\(id) exercise key")
                let flags = try XCTUnwrap(want["sets"] as? [Bool])
                let actual = blocks[index].sets.map { records.contains($0.id) }
                XCTAssertEqual(actual, flags, "\(id) \(keys[index]) records")
            }
        }
    }

    private func number(_ value: Any?) throws -> Double {
        try XCTUnwrap((value as? NSNumber)?.doubleValue, "Not a number: \(String(describing: value))")
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/personal-records-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
