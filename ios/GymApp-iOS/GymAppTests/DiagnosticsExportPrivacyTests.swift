import Foundation
import XCTest
@testable import GymApp

@MainActor
final class DiagnosticsExportPrivacyTests: XCTestCase {
    func testDiagnosticsJSONIsMinimizedWhileBackupKeepsPrivateData() throws {
        let store = try WorkoutStore(
            accountStorageKey: "diagnostics-account-canary",
            directoryURL: try temporaryDirectory(named: "diagnostics-json")
        )
        let exercise = try store.addExercise(name: "PRIVATE EXERCISE CANARY")
        _ = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            note: "PRIVATE NOTE CANARY",
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [.init(weight: 123.45, reps: 7)]
                )
            ]
        )
        let owner = BackupOwner(
            accountID: "diagnostics-account-canary",
            userID: "diagnostics-user-canary",
            email: "diagnostics-email-canary@example.com",
            remote: true
        )

        let diagnosticsData = try ExportService.diagnosticsJSON(
            snapshot: store.diagnosticsSnapshot(),
            context: ExportService.DiagnosticsContext(
                version: "1.2.3",
                build: "456",
                operatingSystemVersion: "iOS test",
                localeIdentifier: "en_US",
                cloudSyncEnabled: true,
                hasSuccessfulSync: true,
                hasError: false
            )
        )
        let diagnostics = try XCTUnwrap(
            JSONSerialization.jsonObject(with: diagnosticsData) as? [String: Any]
        )

        XCTAssertEqual(
            Set(diagnostics.keys),
            ["schemaVersion", "reportType", "application", "workoutData", "cloudSync"]
        )
        XCTAssertEqual(diagnostics["schemaVersion"] as? Int, 1)
        XCTAssertEqual(diagnostics["reportType"] as? String, "diagnostics")
        let application = try XCTUnwrap(diagnostics["application"] as? [String: Any])
        XCTAssertEqual(
            Set(application.keys),
            ["version", "build", "operatingSystemVersion", "localeIdentifier"]
        )
        XCTAssertEqual(application["version"] as? String, "1.2.3")
        XCTAssertEqual(application["build"] as? String, "456")
        let workoutData = try XCTUnwrap(diagnostics["workoutData"] as? [String: Any])
        XCTAssertEqual(
            Set(workoutData.keys),
            ["exerciseCount", "workoutCount", "setCount", "manualMuscleMappingCount"]
        )
        XCTAssertEqual(workoutData["exerciseCount"] as? Int, 1)
        XCTAssertEqual(workoutData["workoutCount"] as? Int, 1)
        XCTAssertEqual(workoutData["setCount"] as? Int, 1)
        XCTAssertEqual(workoutData["manualMuscleMappingCount"] as? Int, 0)
        let cloudSync = try XCTUnwrap(diagnostics["cloudSync"] as? [String: Any])
        XCTAssertEqual(Set(cloudSync.keys), ["enabled", "hasSuccessfulSync", "hasError"])
        XCTAssertEqual(cloudSync["enabled"] as? Bool, true)
        XCTAssertEqual(cloudSync["hasSuccessfulSync"] as? Bool, true)
        XCTAssertEqual(cloudSync["hasError"] as? Bool, false)

        let diagnosticsText = try XCTUnwrap(String(data: diagnosticsData, encoding: .utf8))
        for forbiddenValue in [
            "PRIVATE EXERCISE CANARY",
            "PRIVATE NOTE CANARY",
            "diagnostics-account-canary",
            "diagnostics-user-canary",
            "diagnostics-email-canary@example.com",
            "123.45",
            "1750000000000",
            "access-token-canary",
            "refresh-token-canary"
        ] {
            XCTAssertFalse(diagnosticsText.contains(forbiddenValue), "Diagnostics leaked \(forbiddenValue)")
        }

        let backupData = try store.exportBackupData(owner: owner)
        let backup = try XCTUnwrap(JSONSerialization.jsonObject(with: backupData) as? [String: Any])
        XCTAssertEqual(backup["diagnostics"] as? Bool, false)
        XCTAssertEqual((backup["owner"] as? [String: Any])?["email"] as? String, owner.email)
        XCTAssertEqual((backup["exercises"] as? [[String: Any]])?.first?["name"] as? String, exercise.name)
        let session = try XCTUnwrap((backup["sessions"] as? [[String: Any]])?.first)
        XCTAssertEqual(session["note"] as? String, "PRIVATE NOTE CANARY")
        let workoutExercise = try XCTUnwrap((session["exercises"] as? [[String: Any]])?.first)
        let set = try XCTUnwrap((workoutExercise["sets"] as? [[String: Any]])?.first)
        XCTAssertEqual(set["weight"] as? Double, 123.45)
        XCTAssertEqual(set["reps"] as? Int, 7)
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gymapp-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
