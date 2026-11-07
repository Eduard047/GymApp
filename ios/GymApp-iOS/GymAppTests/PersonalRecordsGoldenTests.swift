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

    /// The "storedCases" of the shared contract: the saved-workout badges, same cases as Android.
    func testStoredWorkoutGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["storedCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let currentID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        let higherID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            var ids: [String: UUID] = [:]
            func idOf(_ key: String) -> UUID {
                if let existing = ids[key] { return existing }
                let created = UUID()
                ids[key] = created
                return created
            }

            var history: [ExerciseHistoryEntry] = []
            for (index, entry) in try XCTUnwrap(item["history"] as? [[String: Any]]).enumerated() {
                let key = try XCTUnwrap(entry["exercise"] as? String)
                let whenKey = try XCTUnwrap(entry["when"] as? String)
                let workoutID: UUID
                let sessionDate: Date
                switch whenKey {
                case "earlier": (workoutID, sessionDate) = (UUID(), date.addingTimeInterval(-86_400))
                case "same-date-lower-id": (workoutID, sessionDate) = (lowerID, date)
                case "same-date-higher-id": (workoutID, sessionDate) = (higherID, date)
                case "later": (workoutID, sessionDate) = (UUID(), date.addingTimeInterval(86_400))
                case "self": (workoutID, sessionDate) = (currentID, date)
                default: return XCTFail("\(id): unknown when \(whenKey)")
                }
                history.append(
                    ExerciseHistoryEntry(
                        setID: UUID(),
                        workoutID: workoutID,
                        sessionDate: sessionDate,
                        exerciseID: idOf(key),
                        exerciseName: key,
                        weight: try number(entry["weight"]),
                        reps: try XCTUnwrap(entry["reps"] as? Int),
                        setOrderIndex: index
                    )
                )
            }

            var blocks: [WorkoutExercise] = []
            var keys: [String] = []
            for block in try XCTUnwrap(item["workout"] as? [[String: Any]]) {
                let key = try XCTUnwrap(block["exercise"] as? String)
                var sets: [WorkoutSet] = []
                for set in try XCTUnwrap(block["sets"] as? [[String: Any]]) {
                    sets.append(
                        WorkoutSet(
                            weight: try number(set["weight"]),
                            reps: try XCTUnwrap(set["reps"] as? Int)
                        )
                    )
                }
                blocks.append(WorkoutExercise(exerciseID: idOf(key), sets: sets))
                keys.append(key)
            }

            let expected = try XCTUnwrap(
                (item["expected"] as? [String: Any])?["records"] as? [[String: Any]]
            )
            XCTAssertEqual(expected.count, blocks.count, "\(id) block count")
            for (index, want) in expected.enumerated() {
                let block = blocks[index]
                let baseline = StoredWorkoutPRBaseline(
                    history: history.filter { $0.exerciseID == block.exerciseID },
                    currentWorkoutDate: date,
                    currentWorkoutID: currentID
                )
                // A repeated exercise keeps one running best across its blocks.
                let labels = baseline.labelsBySetID(
                    in: blocks.filter { $0.exerciseID == block.exerciseID }
                )
                let flags = try XCTUnwrap(want["sets"] as? [Bool])
                XCTAssertEqual(block.sets.map { labels[$0.id] != nil }, flags, "\(id) block \(index) records")
                let summary = StoredWorkoutExerciseSummary(
                    block: block,
                    personalRecordBaseline: baseline,
                    sameExerciseBlocks: blocks.filter { $0.exerciseID == block.exerciseID }
                )
                XCTAssertEqual(summary.hasPersonalRecord, flags.contains(true), "\(id) block \(index) summary")
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
