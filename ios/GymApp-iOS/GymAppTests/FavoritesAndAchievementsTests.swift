import Foundation
import XCTest
@testable import GymApp

@MainActor
final class FavoritesAndAchievementsTests: XCTestCase {
    func testLeaderboardSafetyPreferencesUseAccountScopedKeys() {
        XCTAssertNotEqual(
            leaderboardHiddenProfilesDefaultsKey(for: "account-a"),
            leaderboardHiddenProfilesDefaultsKey(for: "account-b")
        )
    }

    func testExerciseFavoriteDecodingIsBackwardCompatibleAndSharedEncodingStaysNarrow() throws {
        let id = UUID()
        let legacy = Data(#"{"id":"\#(id.uuidString)","name":"Bench Press","catalogKey":"bench_press"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(Exercise.self, from: legacy)
        XCTAssertFalse(decodedLegacy.isFavorite)

        let newer = Data(#"{"id":"\#(id.uuidString)","name":"Bench Press","catalogKey":"bench_press","isFavorite":true}"#.utf8)
        let decodedNewer = try JSONDecoder().decode(Exercise.self, from: newer)
        XCTAssertTrue(decodedNewer.isFavorite)

        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(decodedNewer)
        ) as? [String: Any]
        XCTAssertNil(encoded?["isFavorite"])

        let malformed = Data(#"{"id":"\#(id.uuidString)","name":"Bench Press","isFavorite":"yes"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Exercise.self, from: malformed))
    }

    func testFavoriteTogglePersistsPerAccountAndMigratesSchemaOne() throws {
        let directory = try temporaryDirectory(named: "favorite-account-scope")
        let accountA = try WorkoutStore(accountStorageKey: "favorite-a", directoryURL: directory)
        let bench = try accountA.addExercise(name: "Bench Press")
        XCTAssertTrue(try accountA.toggleExerciseFavorite(id: bench.id))
        XCTAssertTrue(accountA.exercise(id: bench.id)?.isFavorite == true)

        let reopenedA = try WorkoutStore(accountStorageKey: "favorite-a", directoryURL: directory)
        XCTAssertTrue(reopenedA.exercise(id: bench.id)?.isFavorite == true)

        let accountB = try WorkoutStore(accountStorageKey: "favorite-b", directoryURL: directory)
        let otherBench = try accountB.addExercise(name: "Bench Press")
        XCTAssertFalse(accountB.exercise(id: otherBench.id)?.isFavorite == true)

        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: reopenedA.storageURL)) as? [String: Any]
        )
        XCTAssertEqual(root["schemaVersion"] as? Int, 2)
        XCTAssertEqual((root["favoriteExerciseIDs"] as? [String])?.count, 1)

        var snapshot = try XCTUnwrap(root["snapshot"] as? [String: Any])
        let encodedExercises = try XCTUnwrap(snapshot["exercises"] as? [[String: Any]])
        XCTAssertTrue(encodedExercises.allSatisfy { $0["isFavorite"] == nil })

        root["schemaVersion"] = 1
        root.removeValue(forKey: "favoriteExerciseIDs")
        snapshot["exercises"] = encodedExercises
        root["snapshot"] = snapshot
        let schemaOne = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try schemaOne.write(to: reopenedA.storageURL, options: .atomic)

        let migrated = try WorkoutStore(accountStorageKey: "favorite-a", directoryURL: directory)
        XCTAssertFalse(migrated.exercise(id: bench.id)?.isFavorite == true)
        try migrated.saveNow()
        let migratedRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: migrated.storageURL)) as? [String: Any]
        )
        XCTAssertEqual(migratedRoot["schemaVersion"] as? Int, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: migrated.storageURL.path))
    }

    func testCloudRoundTripCannotEraseMatchingLocalFavoriteOrPublishIt() throws {
        let targetDirectory = try temporaryDirectory(named: "favorite-cloud-target")
        let sourceDirectory = try temporaryDirectory(named: "favorite-cloud-source")
        let accountID = "cloud_favorite-test"
        let owner = BackupOwner(
            accountID: accountID,
            userID: "favorite-test",
            remote: true
        )

        let target = try WorkoutStore(accountStorageKey: accountID, directoryURL: targetDirectory)
        let targetBench = try target.addExercise(name: "Bench Press")
        _ = try target.toggleExerciseFavorite(id: targetBench.id)

        let source = try WorkoutStore(accountStorageKey: accountID, directoryURL: sourceDirectory)
        _ = try source.addExercise(name: "Bench Press")
        let remoteData = try source.exportBackupData(owner: owner)
        _ = try target.restoreBackup(data: remoteData, activeOwner: owner)

        XCTAssertTrue(target.exercise(named: "Bench Press")?.isFavorite == true)

        let cloudRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: target.exportCloudBackupData(owner: owner)) as? [String: Any]
        )
        let cloudExercises = try XCTUnwrap(cloudRoot["exercises"] as? [[String: Any]])
        XCTAssertTrue(cloudExercises.allSatisfy { $0["isFavorite"] == nil })
    }

    func testAchievementIconCatalogCoversCanonicalAchievements() {
        let snapshot = GamificationEngine.buildSnapshot(
            sessions: [],
            now: Date(timeIntervalSince1970: 1_750_000_000),
            calendar: Calendar(identifier: .gregorian)
        )
        XCTAssertEqual(snapshot.achievements.count, 12)
        XCTAssertEqual(
            Set(AchievementIconCatalog.iconsByID.keys),
            Set(snapshot.achievements.map(\.id))
        )
        XCTAssertTrue(AchievementIconCatalog.iconsByID.values.allSatisfy { !$0.isEmpty })
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
