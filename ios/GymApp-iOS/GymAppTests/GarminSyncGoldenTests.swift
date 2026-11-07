import Foundation
import XCTest
@testable import GymApp

/// Runs shared/garmin-sync-v1.json through the real iPhone builder, the same cases the Android suite runs.
final class GarminSyncGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let bindingJSON = try XCTUnwrap(root["binding"] as? [String: String])
        let binding = GarminPhoneBinding(
            account: try XCTUnwrap(bindingJSON["account"]),
            device: try XCTUnwrap(bindingJSON["device"]),
            pairingGeneration: try XCTUnwrap(bindingJSON["pairingGeneration"])
        )
        let syncID = try XCTUnwrap(root["syncId"] as? String)
        let cap = try XCTUnwrap(root["watchMaximumKeys"] as? Int)
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 5)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? [String: Any])
            let plan = try XCTUnwrap(input["plan"] as? [[String: Any]]).map { set in
                NamedWorkoutSetDraft(
                    exerciseName: set["exerciseName"] as? String ?? "",
                    weight: (set["weight"] as? NSNumber)?.doubleValue ?? -1,
                    reps: (set["reps"] as? NSNumber)?.intValue ?? 0
                )
            }
            let rawCandidates = try XCTUnwrap(input["exerciseCandidates"] as? [String])
            let bindingOnly = try XCTUnwrap(input["bindingOnly"] as? Bool)
            // Convert names to Latin first with an empty table (as the app does), then build the payload.
            let assignment = GarminLatinNames.assign(names: plan.map(\.exerciseName) + rawCandidates, existing: [])
            let watchPlan = try XCTUnwrap(GarminLatinNames.watchPlan(plan, assignment: assignment), "\(id) latin plan")
            let candidates = GarminLatinNames.watchCatalog(rawCandidates, assignment: assignment)
            // The iPhone merges the planned names with the picker catalog before building the payload.
            let catalog = bindingOnly
                ? []
                : try XCTUnwrap(
                    GarminPhoneSyncProtocol.exerciseCatalog(plan: watchPlan, candidates: candidates),
                    "\(id) catalog"
                )
            let payload = try XCTUnwrap(
                GarminPhoneSyncProtocol.syncPayload(
                    binding: binding,
                    syncID: syncID,
                    revision: try XCTUnwrap((input["syncRevision"] as? NSNumber)?.int64Value),
                    // input.language is the app UI language and is ignored: the watch always gets "en".
                    language: garminWatchLanguageTag,
                    exercises: catalog,
                    resetWorkout: try XCTUnwrap(input["resetWorkout"] as? Bool),
                    repairPairing: try XCTUnwrap(input["repairPairing"] as? Bool),
                    plan: watchPlan,
                    bindingOnly: bindingOnly
                ),
                "\(id) payload"
            )

            var expected = try XCTUnwrap(item["expected"] as? [String: Any])
            let extras = try XCTUnwrap(item["platformExtras"] as? [String: Any])
            for (key, value) in try XCTUnwrap(extras["ios"] as? [String: Any]) { expected[key] = value }
            XCTAssertEqual(
                NSDictionary(dictionary: normalized(payload)),
                NSDictionary(dictionary: normalized(expected)),
                id
            )
            XCTAssertTrue(payload["syncRevision"] is Int64, "\(id) syncRevision stays Int64")
            XCTAssertLessThanOrEqual(payload.count, cap, "\(id) fits the watch key cap")
        }
    }

    func testNonAsciiNamesAreNeverSent() throws {
        let root = try contract()
        let bindingJSON = try XCTUnwrap(root["binding"] as? [String: String])
        let binding = GarminPhoneBinding(
            account: try XCTUnwrap(bindingJSON["account"]),
            device: try XCTUnwrap(bindingJSON["device"]),
            pairingGeneration: try XCTUnwrap(bindingJSON["pairingGeneration"])
        )
        let syncID = try XCTUnwrap(root["syncId"] as? String)
        let rejectCases = try XCTUnwrap(root["rejectCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rejectCases.count, 2)
        for item in rejectCases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? [String: Any])
            let plan = try XCTUnwrap(input["plan"] as? [[String: Any]]).map { set in
                NamedWorkoutSetDraft(
                    exerciseName: set["exerciseName"] as? String ?? "",
                    weight: (set["weight"] as? NSNumber)?.doubleValue ?? -1,
                    reps: (set["reps"] as? NSNumber)?.intValue ?? 0
                )
            }
            let candidates = try XCTUnwrap(input["exerciseCandidates"] as? [String])
            // Raw names go straight to the builder: it must refuse them.
            let catalog = try XCTUnwrap(
                GarminPhoneSyncProtocol.exerciseCatalog(plan: plan, candidates: candidates), id
            )
            XCTAssertNil(
                GarminPhoneSyncProtocol.syncPayload(
                    binding: binding, syncID: syncID, revision: 1_800_000_000_123,
                    language: garminWatchLanguageTag, exercises: catalog, resetWorkout: false, plan: plan
                ),
                id
            )
        }
    }

    // Numbers compare as doubles (JSON has one number type), so 100 equals 100.0.
    private func normalized(_ dictionary: [String: Any]) -> [String: Any] {
        dictionary.mapValues { value in
            if let array = value as? [Any] {
                return array.map { element -> Any in
                    if let number = element as? NSNumber, !(element is Bool) { return number.doubleValue }
                    return element
                }
            }
            if let number = value as? NSNumber, !(value is Bool), CFGetTypeID(number) != CFBooleanGetTypeID() {
                return number.doubleValue
            }
            return value
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/garmin-sync-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
