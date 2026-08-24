import Foundation
import XCTest
@testable import GymApp

final class SmartCoachV2GoldenTests: XCTestCase {
    func testSharedGoldenVectorsExecuteIOSPolicyEngine() throws {
        let data = try Data(contentsOf: sharedFixtureURL())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["contractVersion"] as? Int, smartCoachV2ContractVersion)
        let vectors = try XCTUnwrap(root["vectors"] as? [[String: Any]])

        for vector in vectors {
            let name = try XCTUnwrap(vector["name"] as? String)
            let input = try XCTUnwrap(vector["input"] as? [String: Any])
            let expected = try XCTUnwrap(vector["expected"] as? [String: Any])
            let adaptation = try resolve(input)

            XCTAssertEqual(adaptation.eligible, expected["eligible"] as? Bool, name)
            XCTAssertEqual(adaptation.appliedEffort.rawValue, expected["appliedEffort"] as? String, name)
            XCTAssertEqual(adaptation.setBudget, expected["setBudget"] as? Int, name)
            let targetRIR = try XCTUnwrap(expected["targetRir"] as? [Int])
            XCTAssertEqual(adaptation.targetRIR.lowerBound, targetRIR[0], name)
            XCTAssertEqual(adaptation.targetRIR.upperBound, targetRIR[1], name)
            XCTAssertEqual(adaptation.restSeconds, expected["restSeconds"] as? Int, name)
            XCTAssertEqual(adaptation.loadAdjustmentSteps, expected["loadAdjustmentSteps"] as? Int, name)
            XCTAssertEqual(Int(adaptation.confidenceDelta * 1_000), expected["confidenceDeltaMilli"] as? Int, name)
            XCTAssertEqual(adaptation.freshForSeconds, expected["freshForSeconds"] as? Int, name)
            XCTAssertEqual(adaptation.reasons.map(\.rawValue), expected["reasons"] as? [String], name)
        }
    }

    func testIOSPlanEngineAppliesV2ContextFeedbackAndCoreRest() {
        let exercises = BuiltInExerciseCatalog.definitions.map {
            Exercise(name: $0.englishName, catalogKey: $0.key)
        }
        let plan = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: [],
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 2,
                goal: .muscleGain,
                calorieMode: .surplus
            ),
            context: SmartCoachContextV2(readiness: .low, availableMinutes: 45)
        )

        XCTAssertEqual(plan.contractVersion, smartCoachV2ContractVersion)
        XCTAssertEqual(plan.freshForSeconds, smartCoachV2FreshForSeconds)
        XCTAssertEqual(plan.appliedEffort, .recovery)
        XCTAssertEqual(plan.setBudget, 15)
        XCTAssertLessThanOrEqual(plan.exercises.reduce(0) { $0 + $1.recommendation.sets.count }, 15)
        XCTAssertTrue(plan.adaptationReasons.contains(.readinessRecovery))
        XCTAssertTrue(plan.adaptationReasons.contains(.timeCapped))
        XCTAssertNotNil(plan.estimatedMinutes)

        let exerciseID = UUID()
        let baseline = RecommendationEngine.buildForExercise(
            exerciseID: exerciseID,
            history: [],
            exerciseCatalogKey: "bench_press",
            exerciseName: "Bench Press"
        )
        let protected = RecommendationEngine.buildForExercise(
            exerciseID: exerciseID,
            history: [],
            exerciseCatalogKey: "bench_press",
            exerciseName: "Bench Press",
            exerciseFeedback: [SmartCoachExerciseFeedbackSignalV2(
                actualRIR: 1,
                outcome: .tooHard,
                ageDays: 1
            )]
        )
        XCTAssertEqual(protected.sets.map(\.reps), baseline.sets.map { max(1, $0.reps - 1) })
        XCTAssertEqual(protected.targetRIR, 3 ... 4)
        XCTAssertTrue(protected.reasons.contains(.exerciseFeedbackTooHard))

        let coreExercise = Exercise(name: "Weighted Crunch", catalogKey: "weighted_crunch")
        let core = SmartWorkoutExercise(
            exercise: coreExercise,
            recommendation: RecommendationEngine.buildForExercise(
                exerciseID: coreExercise.id,
                history: [],
                exerciseCatalogKey: coreExercise.catalogKey,
                exerciseName: coreExercise.name
            )
        )
        XCTAssertEqual(core.recommendedRestSeconds, 60)
    }

    private func resolve(_ input: [String: Any]) throws -> SmartCoachV2Adaptation {
        let effort = try XCTUnwrap(SmartWorkoutEffort(rawValue: try string("requestedEffort", in: input)))
        let role = try XCTUnwrap(SmartCoachExerciseRoleV2(rawValue: try string("role", in: input)))
        let equipment = try XCTUnwrap(SmartCoachEquipmentV2(rawValue: try string("equipment", in: input)))
        let readiness = try optionalString("readiness", in: input).map {
            try XCTUnwrap(SmartCoachReadinessV2(rawValue: $0))
        }
        let availableEquipment = try optionalStrings("availableEquipment", in: input).map { values in
            try Set(values.map { try XCTUnwrap(SmartCoachEquipmentV2(rawValue: $0)) })
        }
        let feedback = try (input["feedback"] as? [[String: Any]] ?? []).map { value in
            SmartCoachExerciseFeedbackSignalV2(
                actualRIR: value["actualRir"] as? Int,
                outcome: try XCTUnwrap(
                    SmartCoachExerciseFeedbackOutcomeV2(rawValue: try string("outcome", in: value))
                ),
                ageDays: try XCTUnwrap(value["ageDays"] as? Int)
            )
        }
        return resolveSmartCoachV2(SmartCoachV2Scenario(
            requestedEffort: effort,
            baseSetBudget: try XCTUnwrap(input["baseSetBudget"] as? Int),
            role: role,
            equipment: equipment,
            primaryMuscles: Set(input["primaryMuscles"] as? [String] ?? []),
            context: SmartCoachContextV2(
                readiness: readiness,
                availableMinutes: input["availableMinutes"] as? Int,
                availableEquipment: availableEquipment,
                musclesToAvoid: Set(input["musclesToAvoid"] as? [String] ?? [])
            ),
            feedback: feedback
        ))
    }

    private func string(_ key: String, in value: [String: Any]) throws -> String {
        try XCTUnwrap(value[key] as? String)
    }

    private func optionalString(_ key: String, in value: [String: Any]) throws -> String? {
        guard value[key] != nil else { return nil }
        return try string(key, in: value)
    }

    private func optionalStrings(_ key: String, in value: [String: Any]) throws -> [String]? {
        guard value[key] != nil else { return nil }
        return try XCTUnwrap(value[key] as? [String])
    }

    private func sharedFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/smart-coach-v2-golden.json")
    }
}
