import Foundation
import XCTest
@testable import GymApp

final class GarminPhonePlanStoreTests: XCTestCase {
    private let binding = GarminPhoneBinding(account: String(repeating: "a", count: 64),
        device: "11111111-2222-3333-4444-555555555555", pairingGeneration: String(repeating: "b", count: 64))

    private func delivery(revision: Int64 = 1, acknowledged: Bool = false) -> GarminPhonePlanDelivery {
        GarminPhonePlanDelivery(version: 1, binding: binding, syncID: "plan-delivery-test-001", revision: revision,
            language: "ru", sets: [.init(exerciseName: "Жим штанги", weight: 52.5, reps: 9)],
            exercises: ["Жим штанги"], acknowledged: acknowledged)
    }

    func testDurablePlanPreservesExactValuesAndRejectsInvalidReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GarminPhonePlanStore(root: root)
        let original = delivery()
        try store.save(original, account: "account-a")
        XCTAssertThrowsError(try store.save(delivery(revision: 0, acknowledged: true), account: "account-a"))
        let reopened = GarminPhonePlanStore(root: root)
        XCTAssertEqual(try reopened.load(account: "account-a", binding: binding), original)
        XCTAssertNil(try reopened.load(account: "account-b", binding: binding))
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let files = enumerator.allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try Data(repeating: 32, count: 65_537).write(to: file)
        XCTAssertThrowsError(try reopened.load(account: "account-a", binding: binding))
        XCTAssertTrue(reopened.clear(account: "account-a"))
        XCTAssertNil(try reopened.load(account: "account-a", binding: binding))
    }

    func testDeviceSelectionCleanupRetainsOnlySelectedWatchInTheSameAccount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GarminPhonePlanStore(root: root)
        try store.save(delivery(), account: "account-a")
        try store.save(delivery(), account: "account-b")
        XCTAssertTrue(store.retain(account: "account-a", devices: [binding.device]))
        XCTAssertNotNil(try store.load(account: "account-a", binding: binding))
        XCTAssertTrue(store.retain(account: "account-a", devices: []))
        XCTAssertNil(try store.load(account: "account-a", binding: binding))
        XCTAssertNotNil(try store.load(account: "account-b", binding: binding))
    }

    func testPlanPayloadBoundsAndResetCannotCarryExerciseSets() throws {
        let set = NamedWorkoutSetDraft(exerciseName: "Жим штанги", weight: 52.5, reps: 9)
        XCTAssertNil(GarminPhoneSyncProtocol.syncPayload(binding: binding, syncID: "plan-delivery-test-001",
            revision: 1, language: "ru", exercises: [], resetWorkout: true, plan: [set]))
        for weight in [Double.nan, Double.infinity, -1, 1_000_001] {
            XCTAssertNil(GarminPhoneSyncProtocol.validatedPlan([.init(exerciseName: "Bench", weight: weight, reps: 8)]))
        }
        XCTAssertNil(GarminPhoneSyncProtocol.validatedPlan([.init(exerciseName: "Bench\nPress", weight: 50, reps: 8)]))
        XCTAssertNil(GarminPhoneSyncProtocol.validatedPlan([.init(exerciseName: "Bench", weight: 50, reps: 0)]))
        XCTAssertNil(GarminPhoneSyncProtocol.validatedPlan(Array(repeating: set, count: 61)))
        let longSet = NamedWorkoutSetDraft(exerciseName: String(repeating: "Ж", count: 160), weight: 50, reps: 8)
        XCTAssertNil(GarminPhoneSyncProtocol.validatedPlan(Array(repeating: longSet, count: 38)))
        let catalog = try XCTUnwrap(GarminPhoneSyncProtocol.exerciseCatalog(plan: [set],
            candidates: (0..<60).map { "Catalog \($0)" }))
        XCTAssertEqual(catalog.first, "Жим штанги")
        XCTAssertEqual(catalog.count, 60)
    }
}
