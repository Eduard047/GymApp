import Foundation
import XCTest
@testable import GymApp

@MainActor
final class CloudBackwardCompatibilityTests: XCTestCase {
    func testCloudWriterKeepsLegacyEightKeyRootWhileLocalBackupKeepsSeedMarker() throws {
        let directory = try temporaryDirectory(named: "legacy-cloud-root")
        let accountID = "cloud_123e4567-e89b-12d3-a456-426614174000"
        let userID = "123e4567-e89b-12d3-a456-426614174000"
        let owner = BackupOwner(
            accountID: accountID,
            userID: userID,
            remote: true
        )
        let store = try WorkoutStore(accountStorageKey: accountID, directoryURL: directory)
        XCTAssertEqual(try store.seedBuiltInExercises(), BuiltInExerciseCatalog.definitions.count)
        let machine = try store.addExercise(
            name: "Compatibility Machine",
            machineLoadProfile: try MachineLoadProfile(
                direction: .higherIsHarder,
                allowedWeightsKg: [10, 20, 30]
            )
        )
        _ = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: machine.id,
                    sets: [WorkoutSetDraft(weight: 20, reps: 8)]
                )
            ]
        )

        let localRoot = try jsonObject(store.exportBackupData(owner: owner))
        XCTAssertEqual(localRoot["catalogSeedVersion"] as? Int, BuiltInExerciseCatalog.seedVersion)

        let cloudData = try store.exportCloudBackupData(
            owner: owner,
            extensionsData: Data(#"{"pwa":{"language":"uk"}}"#.utf8)
        )
        let cloudRoot = try jsonObject(cloudData)
        XCTAssertEqual(
            Set(cloudRoot.keys),
            Set([
                "schemaVersion",
                "exportedAt",
                "app",
                "diagnostics",
                "owner",
                "exercises",
                "sessions",
                "summary"
            ])
        )
        XCTAssertNil(cloudRoot["catalogSeedVersion"])
        XCTAssertNil(cloudRoot["extensions"])

        let cloudExercises = try XCTUnwrap(cloudRoot["exercises"] as? [[String: Any]])
        XCTAssertTrue(cloudExercises.allSatisfy {
            Set($0.keys).isSubset(of: ["name", "catalogKey"]) && $0["loadProfile"] == nil
        })
        let cloudSessions = try XCTUnwrap(cloudRoot["sessions"] as? [[String: Any]])
        let cloudBlocks = try XCTUnwrap(cloudSessions.first?["exercises"] as? [[String: Any]])
        XCTAssertTrue(cloudBlocks.allSatisfy {
            Set($0.keys).isSubset(of: ["name", "catalogKey", "sets"]) &&
                $0["loadProfile"] == nil
        })
        let cloudSets = try XCTUnwrap(cloudBlocks.first?["sets"] as? [[String: Any]])
        XCTAssertTrue(cloudSets.allSatisfy {
            Set($0.keys) == Set(["weight", "reps"])
        })

        _ = try store.restoreBackup(data: cloudData, activeOwner: owner)
        XCTAssertEqual(
            store.exercise(named: "Compatibility Machine")?.machineLoadProfile,
            machine.machineLoadProfile
        )

        // A new reader still accepts the optional marker emitted by an earlier development
        // build, while its next cloud write returns to the legacy public shape.
        var optionalMarkerRoot = cloudRoot
        optionalMarkerRoot["catalogSeedVersion"] = BuiltInExerciseCatalog.seedVersion
        let optionalMarkerData = try JSONSerialization.data(
            withJSONObject: optionalMarkerRoot,
            options: [.sortedKeys]
        )
        let prepared = try WorkoutStore.prepareCloudBackup(
            optionalMarkerData,
            activeOwner: owner
        )
        let decoded = try JSONDecoder().decode(GymBackup.self, from: prepared.data)
        XCTAssertEqual(decoded.catalogSeedVersion, BuiltInExerciseCatalog.seedVersion)
        XCTAssertTrue(prepared.roundTripSafe)
    }

    func testFullLegacyCatalogDoesNotBlockOpeningAndLeavesMigrationRetryable() throws {
        let directory = try temporaryDirectory(named: "catalog-capacity")
        let accountID = "catalog-capacity"
        let owner = BackupOwner(accountID: accountID)
        let store = try WorkoutStore(accountStorageKey: accountID, directoryURL: directory)
        let maximumExercises = BackupImportLimits.standard.maximumExercises
        let backup = GymBackup(
            exportedAt: 1_750_000_000_000,
            diagnostics: false,
            owner: owner,
            catalogSeedVersion: 0,
            exercises: (0 ..< maximumExercises).map { index in
                BackupExercise(name: "Capacity exercise \(index)")
            },
            sessions: [],
            summary: BackupSummary(
                exerciseCount: maximumExercises,
                sessionCount: 0,
                setCount: 0,
                totalVolume: 0
            )
        )
        let data = try JSONEncoder().encode(backup)
        _ = try store.restoreBackup(data: data, activeOwner: owner)

        XCTAssertEqual(try store.seedBuiltInExercises(), 0)
        XCTAssertEqual(store.exercises.count, maximumExercises)
        XCTAssertEqual(store.catalogSeedVersion, 0)

        let reopened = try WorkoutStore(accountStorageKey: accountID, directoryURL: directory)
        XCTAssertEqual(reopened.exercises.count, maximumExercises)
        XCTAssertEqual(reopened.catalogSeedVersion, 0)
    }

    func testCatalogUpgradeAddsOnlyVersionedExercisesToExistingAccounts() throws {
        let directory = try temporaryDirectory(named: "catalog-seed-upgrade")
        let accountID = "catalog-seed-upgrade"
        let owner = BackupOwner(accountID: accountID)
        let store = try WorkoutStore(accountStorageKey: accountID, directoryURL: directory)
        XCTAssertEqual(try store.seedBuiltInExercises(), BuiltInExerciseCatalog.definitions.count)

        var versionOneBackup = try store.makeBackup(owner: owner)
        versionOneBackup.catalogSeedVersion = 1
        versionOneBackup.exercises.removeAll {
            $0.catalogKey == "bench_press" ||
                $0.catalogKey == "hip_abduction" ||
                $0.catalogKey == "assisted_dip"
        }
        versionOneBackup.summary?.exerciseCount = versionOneBackup.exercises.count
        _ = try store.restoreBackup(
            data: JSONEncoder().encode(versionOneBackup),
            activeOwner: owner
        )

        XCTAssertEqual(try store.seedBuiltInExercises(), 2)
        XCTAssertTrue(store.exercises.contains { $0.catalogKey == "hip_abduction" })
        XCTAssertTrue(store.exercises.contains { $0.catalogKey == "assisted_dip" })
        XCTAssertFalse(store.exercises.contains { $0.catalogKey == "bench_press" })
        XCTAssertEqual(store.catalogSeedVersion, BuiltInExerciseCatalog.seedVersion)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
