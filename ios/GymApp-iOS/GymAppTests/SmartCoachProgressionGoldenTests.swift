import Foundation
import XCTest
@testable import GymApp

final class SmartCoachProgressionGoldenTests: XCTestCase {
    func testSharedProgressionVectorsMatchIOSPerExerciseEngine() throws {
        let data = try Data(contentsOf: sharedFixtureURL())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["contractVersion"] as? Int, 1)
        let nowMillis = try XCTUnwrap((root["nowEpochMillis"] as? NSNumber)?.int64Value)
        let vectors = try XCTUnwrap(root["vectors"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(vectors.count, 8)

        for vector in vectors {
            let name = try XCTUnwrap(vector["name"] as? String)
            let expected = try XCTUnwrap(vector["expected"] as? [String: Any])
            let recommendation = try recommend(vector, nowMillis: nowMillis)

            XCTAssertEqual(recommendation.kind.rawValue, expected["kind"] as? String, name)
            let targetRIR = try XCTUnwrap(expected["targetRir"] as? [Int], name)
            XCTAssertEqual(recommendation.targetRIR.lowerBound, targetRIR[0], name)
            XCTAssertEqual(recommendation.targetRIR.upperBound, targetRIR[1], name)
            let sets = try XCTUnwrap(expected["sets"] as? [[String: Any]], name)
            XCTAssertEqual(recommendation.sets.count, sets.count, name)
            for (index, expectedSet) in zip(sets.indices, sets) where index < recommendation.sets.count {
                let actual = recommendation.sets[index]
                if let weight = expectedSet["weight"] as? NSNumber {
                    XCTAssertEqual(actual.weight ?? .nan, weight.doubleValue, accuracy: 0.0001, "\(name) set \(index) weight")
                } else {
                    XCTAssertNil(actual.weight, "\(name) set \(index) weight")
                }
                XCTAssertEqual(actual.reps, expectedSet["reps"] as? Int, "\(name) set \(index) reps")
            }
        }
    }

    private func recommend(_ vector: [String: Any], nowMillis: Int64) throws -> WorkoutRecommendation {
        let profile = try XCTUnwrap(vector["trainingProfile"] as? [String: Any])
        let exerciseName = try XCTUnwrap(vector["exerciseName"] as? String)
        let offsetDays = try XCTUnwrap(vector["nowOffsetDays"] as? Int)
        let dayMillis: Int64 = 86_400_000
        let exerciseID = UUID()
        let workoutIDs = Dictionary(
            uniqueKeysWithValues: Set(
                try XCTUnwrap(vector["history"] as? [[String: Any]]).compactMap { $0["daysAgo"] as? Int }
            ).map { ($0, UUID()) }
        )
        let history = try XCTUnwrap(vector["history"] as? [[String: Any]]).map { entry -> ExerciseHistoryEntry in
            let daysAgo = entry["daysAgo"] as! Int
            return ExerciseHistoryEntry(
                setID: UUID(),
                workoutID: workoutIDs[daysAgo]!,
                sessionDate: Date(timeIntervalSince1970: Double(nowMillis - Int64(daysAgo) * dayMillis) / 1_000),
                exerciseID: exerciseID,
                exerciseName: exerciseName,
                weight: (entry["weight"] as! NSNumber).doubleValue,
                reps: entry["reps"] as! Int,
                setOrderIndex: entry["setOrder"] as! Int
            )
        }
        var machineProfile: MachineLoadProfile?
        if let raw = vector["loadProfile"] as? [String: Any] {
            machineProfile = try MachineLoadProfile(
                direction: try XCTUnwrap(MachineLoadDirection(rawValue: raw["direction"] as! String)),
                allowedWeightsKg: (raw["allowedWeightsKg"] as! [NSNumber]).map(\.doubleValue)
            )
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        return RecommendationEngine.buildForExercise(
            exerciseID: exerciseID,
            history: history,
            exerciseName: exerciseName,
            machineLoadProfile: machineProfile,
            trainingProfile: TrainingProfile(
                split: try XCTUnwrap(TrainingSplit(rawValue: profile["split"] as! String)),
                workoutsPerWeek: profile["workoutsPerWeek"] as! Int,
                goal: try XCTUnwrap(TrainingGoal(rawValue: profile["goal"] as! String)),
                calorieMode: try XCTUnwrap(CalorieMode(rawValue: profile["calorieMode"] as! String))
            ),
            effort: try XCTUnwrap(SmartWorkoutEffort(rawValue: vector["effort"] as! String)),
            now: Date(timeIntervalSince1970: Double(nowMillis + Int64(offsetDays) * dayMillis) / 1_000),
            calendar: calendar
        )
    }

    private func sharedFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/smart-coach-progression-v1.json")
    }
}
