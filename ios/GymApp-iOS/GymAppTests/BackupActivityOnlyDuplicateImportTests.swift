import Foundation
import XCTest
@testable import GymApp

/// Two activity-only workouts (no sets, duration > 0) at the same start are one workout: the
/// activity-only cloud sidecar is keyed by its start. The note of a watch or Health summary is
/// localized and editable, so a merge import must not add the same summary again under another note.
@MainActor
final class BackupActivityOnlyDuplicateImportTests: XCTestCase {
    private let startMilliseconds: Int64 = 1_750_000_000_000

    func testMergeImportSkipsActivityOnlySessionAtAnExistingStartWithAnotherNote() throws {
        let store = try makeStore()
        try store.createImportedActivityWorkout(
            date: Date(gymEpochMilliseconds: startMilliseconds),
            note: "Apple Health · Core training · Duration 30:00",
            durationSeconds: 1_800,
            gymCalories: 250,
            averageHeartRate: nil,
            maximumHeartRate: nil
        )

        let result = try store.importBackup(json: backupJSON(sessions: [
            activitySession(note: "Apple Health · Тренування кору · Тривалість 30:00"),
            activitySession(note: "My edited note")
        ]))

        XCTAssertEqual(result.importedSessions, 0)
        XCTAssertEqual(result.skippedDuplicateSessions, 2)
        XCTAssertEqual(store.workouts.count, 1)
        XCTAssertEqual(store.workouts.first?.note, "Apple Health · Core training · Duration 30:00")
        // Threw CloudSyncError.invalidPayload before the fix.
        XCTAssertEqual(try store.activityOnlyCloudSnapshotItems().count, 1)
    }

    func testMergeImportSkipsActivityOnlySessionAtAnExistingStrengthStart() throws {
        let store = try makeStore()
        let squat = try store.addExercise(name: "Squat")
        _ = try store.createWorkout(
            date: Date(gymEpochMilliseconds: startMilliseconds),
            note: nil,
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: squat.id,
                    sets: [WorkoutSetDraft(weight: 100, reps: 5)]
                )
            ]
        )

        let result = try store.importBackup(json: backupJSON(sessions: [
            activitySession(note: "Watch")
        ]))

        XCTAssertEqual(result.importedSessions, 0)
        XCTAssertEqual(result.skippedDuplicateSessions, 1)
        XCTAssertEqual(store.workouts.count, 1)
    }

    func testImportKeepsOnlyTheFirstActivityOnlySessionPerStartInOneBackup() throws {
        let store = try makeStore()

        let result = try store.importBackup(json: backupJSON(sessions: [
            activitySession(note: "Apple Health · Core training · Duration 30:00"),
            activitySession(note: "Apple Health · Тренування кору · Тривалість 30:00"),
            activitySession(note: "Later start", offsetMilliseconds: 1)
        ]))

        XCTAssertEqual(result.importedSessions, 2)
        XCTAssertEqual(result.skippedDuplicateSessions, 1)
        XCTAssertEqual(
            Set(store.workouts.compactMap(\.note)),
            ["Apple Health · Core training · Duration 30:00", "Later start"]
        )
        XCTAssertEqual(try store.activityOnlyCloudSnapshotItems().count, 2)
    }

    private func activitySession(note: String, offsetMilliseconds: Int64 = 0) -> [String: Any] {
        [
            "date": startMilliseconds + offsetMilliseconds,
            "note": note,
            "durationSeconds": 1_800,
            "exercises": [Any]()
        ]
    }

    private func backupJSON(sessions: [[String: Any]]) throws -> String {
        let object: [String: Any] = [
            "schemaVersion": GymBackup.currentSchemaVersion,
            "exportedAt": startMilliseconds,
            "exercises": [Any](),
            "sessions": sessions
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func makeStore() throws -> WorkoutStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GymAppBackupActivityDuplicateTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try WorkoutStore(accountStorageKey: "local_test", directoryURL: url)
    }
}
