import Foundation
import XCTest
@testable import GymApp

/// Runs shared/plan-seed-last-session-v1.json, the same cases the Android suite runs.
final class PlanSeedLastSessionGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 12)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let exerciseID = try XCTUnwrap(item["exerciseId"] as? Int)
            let rows = try XCTUnwrap(item["history"] as? [[String: Any]]).map { row in
                PlanSeedHistoryRow(
                    exerciseID: row["exerciseId"] as? Int ?? -1,
                    sessionID: row["sessionId"] as? Int ?? -1,
                    date: (row["date"] as? NSNumber)?.doubleValue ?? -1,
                    blockOrderIndex: row["blockOrderIndex"] as? Int ?? -1,
                    setOrderIndex: row["setOrderIndex"] as? Int ?? -1,
                    weight: (row["weight"] as? NSNumber)?.doubleValue ?? -1,
                    reps: row["reps"] as? Int ?? -1
                )
            }
            let expected: [PlanSeedSet]? = (item["expected"] as? [[String: Any]]).map { sets in
                sets.map {
                    PlanSeedSet(
                        weight: ($0["weight"] as? NSNumber)?.doubleValue ?? -1,
                        reps: $0["reps"] as? Int ?? -1
                    )
                }
            }
            XCTAssertEqual(
                GymPlanSeed.lastSessionSetSeed(exerciseID: exerciseID, history: rows),
                expected,
                id
            )
        }
    }

    func testStoredWorkoutsFollowTheSameRules() {
        let bench = UUID()
        let other = UUID()
        let day = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func workout(_ date: Date, _ blocks: [WorkoutExercise]) -> WorkoutSession {
            WorkoutSession(date: date, exercises: blocks)
        }
        let older = workout(day, [WorkoutExercise(exerciseID: bench, sets: [WorkoutSet(weight: 40, reps: 12)])])
        let newerFirst = workout(day.addingTimeInterval(60), [
            WorkoutExercise(exerciseID: other, sets: [WorkoutSet(weight: 99, reps: 1)]),
            WorkoutExercise(exerciseID: bench, sets: [
                WorkoutSet(weight: 0, reps: 15), WorkoutSet(weight: 50, reps: 0), WorkoutSet(weight: 55.5, reps: 6)
            ]),
            WorkoutExercise(exerciseID: bench, sets: [WorkoutSet(weight: 30, reps: 20)])
        ])
        XCTAssertEqual(
            GymPlanSeed.lastSessionSetSeed(exerciseID: bench, workouts: [newerFirst, older]),
            [PlanSeedSet(weight: 0, reps: 15), PlanSeedSet(weight: 55.5, reps: 6)]
        )
        XCTAssertNil(GymPlanSeed.lastSessionSetSeed(exerciseID: UUID(), workouts: [older, newerFirst]))

        // Same date: the later-stored workout wins.
        let sameDay = workout(day, [WorkoutExercise(exerciseID: bench, sets: [WorkoutSet(weight: 70, reps: 5)])])
        XCTAssertEqual(
            GymPlanSeed.lastSessionSetSeed(exerciseID: bench, workouts: [older, sameDay]),
            [PlanSeedSet(weight: 70, reps: 5)]
        )
    }

    func testPickerDraftFallsBackToDefaultCard() {
        let id = UUID()
        let none = GymPlanSeed.pickerDraft(exerciseID: id, workouts: [], lastWeight: 42.5)
        XCTAssertEqual(none.sets.map(\.weight), [42.5])
        XCTAssertEqual(none.sets.map(\.reps), [10])
        let blank = GymPlanSeed.pickerDraft(exerciseID: id, workouts: [], lastWeight: nil)
        XCTAssertEqual(blank.sets.map(\.weight), [0])

        let seeded = GymPlanSeed.pickerDraft(
            exerciseID: id,
            workouts: [WorkoutSession(date: Date(), exercises: [
                WorkoutExercise(exerciseID: id, sets: [WorkoutSet(weight: 60, reps: 8), WorkoutSet(weight: 60, reps: 6)])
            ])],
            lastWeight: 60
        )
        XCTAssertEqual(seeded.sets.map(\.reps), [8, 6])
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/plan-seed-last-session-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
