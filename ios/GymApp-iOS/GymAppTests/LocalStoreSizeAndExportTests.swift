import Foundation
import XCTest
@testable import GymApp

/// Local account file cap (32 MiB, separate from the 8 MiB import cap), compact manual
/// backup export, and the one-pass latest-session lookup used by Add Workout presets.
@MainActor
final class LocalStoreSizeAndExportTests: XCTestCase {
    func testLocalStoreLargerThanImportCapPersistsAndReopens() throws {
        let directory = try temporaryDirectory(named: "local-store-cap")
        let owner = BackupOwner(accountID: "local_big", remote: false)
        let store = try WorkoutStore(accountStorageKey: "local_big", directoryURL: directory)
        let bench = try store.addExercise(name: "Bench Press")
        _ = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_600_000_000),
            exercises: [WorkoutExerciseDraft(exerciseID: bench.id, sets: [WorkoutSetDraft(weight: 80, reps: 8)])]
        )
        let template = try jsonObject(store.exportBackupData(owner: owner, prettyPrinted: false))
        // 3,900 three-byte characters: ~11.4 KiB per session in the local file.
        let note = String(repeating: "\u{6F22}", count: 3_900)
        let perBatch = 400
        for batch in 0 ..< 2 {
            let data = try syntheticBackup(
                template: template,
                sessionCount: perBatch,
                firstDateMillis: 1_650_000_000_000 + Int64(batch * perBatch) * 86_400_000,
                note: note
            )
            XCTAssertLessThanOrEqual(data.count, BackupImportLimits.standard.maximumFileBytes)
            let result = try store.importBackup(data: data, activeOwner: owner)
            XCTAssertEqual(result.importedSessions, perBatch)
        }

        let fileSize = try XCTUnwrap(
            store.storageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        XCTAssertGreaterThan(fileSize, 8 * 1_024 * 1_024)
        XCTAssertLessThan(fileSize, 32 * 1_024 * 1_024)
        XCTAssertEqual(WorkoutStore.maximumLocalStoreFileBytes, 32 * 1_024 * 1_024)
        XCTAssertEqual(BackupImportLimits.standard.maximumFileBytes, 8 * 1_024 * 1_024)

        let reopened = try WorkoutStore(accountStorageKey: "local_big", directoryURL: directory)
        XCTAssertEqual(reopened.workouts.count, 1 + 2 * perBatch)
        XCTAssertEqual(reopened.snapshot, store.snapshot)
        XCTAssertEqual(reopened.workouts.filter { $0.note == note }.count, 2 * perBatch)

        // A further save on the reopened large store still persists.
        _ = try reopened.createWorkout(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            exercises: [WorkoutExerciseDraft(exerciseID: bench.id, sets: [WorkoutSetDraft(weight: 85, reps: 5)])]
        )
        let again = try WorkoutStore(accountStorageKey: "local_big", directoryURL: directory)
        XCTAssertEqual(again.workouts.count, 2 + 2 * perBatch)
    }

    func testManualBackupExportIsCompactAndImportsBackEqual() async throws {
        let directory = try temporaryDirectory(named: "compact-export")
        let defaults = temporaryDefaults(named: "compact-export")
        let session = AppAccountSession.local(
            id: "11111111-2222-4333-8444-666666666666",
            displayName: "Owner"
        )
        let auth = AuthService(keychain: LocalStoreTestKeychain(), defaults: defaults)
        try auth.installSessionForTesting(session)
        let appState = try AppState(auth: auth, defaults: defaults, workoutDirectoryURL: directory)
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)

        let source = appState.workoutStore
        let bench = try source.addExercise(name: "Compact Export Lift A")
        let row = try source.addExercise(name: "Compact Export Lift B")
        XCTAssertTrue(try source.toggleExerciseFavorite(id: row.id))
        _ = try source.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            note: "Push day",
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: bench.id,
                    sets: [WorkoutSetDraft(weight: 80, reps: 8), WorkoutSetDraft(weight: 82.5, reps: 6)]
                ),
                WorkoutExerciseDraft(exerciseID: row.id, sets: [WorkoutSetDraft(weight: 50, reps: 12)])
            ]
        )

        let exported = try appState.exportBackup()
        XCTAssertFalse(exported.contains(UInt8(ascii: "\n")))
        let text = try XCTUnwrap(String(data: exported, encoding: .utf8))
        XCTAssertFalse(text.contains("  "))
        XCTAssertFalse(text.contains("\": "))

        let owner = appState.backupOwner
        let target = try WorkoutStore(
            accountStorageKey: source.accountStorageKey,
            directoryURL: try temporaryDirectory(named: "compact-export-target")
        )
        let result = try target.importBackup(data: exported, activeOwner: owner)
        XCTAssertEqual(result.importedSessions, 1)

        var original = try jsonObject(exported)
        var roundTrip = try jsonObject(target.exportManualBackupData(owner: owner, prettyPrinted: false))
        original.removeValue(forKey: "exportedAt")
        roundTrip.removeValue(forKey: "exportedAt")
        XCTAssertEqual(original as NSDictionary, roundTrip as NSDictionary)
    }

    func testLatestSessionDateByExerciseMatchesPerExerciseHistory() throws {
        let store = try WorkoutStore(
            accountStorageKey: "preset-order",
            directoryURL: try temporaryDirectory(named: "preset-order")
        )
        let names = ["Bench Press", "Incline Press", "Overhead Press", "Dips", "Push Up", "Fly"]
        let exercises = try names.map { try store.addExercise(name: $0) }
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func day(_ offset: Int) -> Date { base.addingTimeInterval(Double(offset) * 86_400) }
        let plan: [(Int, [Int])] = [
            (0, [0, 1]),
            (3, [2]),
            (3, [0, 3]),      // same date as another workout
            (-5, [4]),        // older than the rest, inserted later
            (7, [1, 1]),      // the same exercise twice in one workout
            (1, [3])
        ]
        for (offset, indices) in plan {
            _ = try store.createWorkout(
                date: day(offset),
                exercises: indices.map {
                    WorkoutExerciseDraft(
                        exerciseID: exercises[$0].id,
                        sets: [WorkoutSetDraft(weight: 40, reps: 10)]
                    )
                }
            )
        }

        let latest = store.latestSessionDateByExercise()
        for exercise in store.exercises {
            XCTAssertEqual(
                latest[exercise.id],
                store.exerciseHistory(exerciseID: exercise.id).first?.sessionDate,
                exercise.name
            )
        }
        XCTAssertNil(latest[exercises[5].id])

        // Same comparator as AddWorkoutView's preset, fed by the old and new date sources.
        func ordered(_ date: (Exercise) -> Date) -> [UUID] {
            store.exercises
                .map { ($0, 1, date($0)) }
                .sorted {
                    if $0.1 != $1.1 { return $0.1 > $1.1 }
                    if $0.2 != $1.2 { return $0.2 < $1.2 }
                    return gymExerciseName($0.0)
                        .localizedCaseInsensitiveCompare(gymExerciseName($1.0)) == .orderedAscending
                }
                .map(\.0.id)
        }
        let old = ordered {
            store.exerciseHistory(exerciseID: $0.id).first?.sessionDate ?? .distantPast
        }
        let new = ordered { latest[$0.id] ?? .distantPast }
        XCTAssertEqual(old, new)
    }

    // MARK: Helpers

    private func syntheticBackup(
        template: [String: Any],
        sessionCount: Int,
        firstDateMillis: Int64,
        note: String
    ) throws -> Data {
        var root = template
        let sessions = try XCTUnwrap(template["sessions"] as? [[String: Any]])
        let first = try XCTUnwrap(sessions.first)
        let sets = try XCTUnwrap(
            ((first["exercises"] as? [[String: Any]])?.first?["sets"] as? [[String: Any]])
        )
        var generated: [[String: Any]] = []
        var volume = 0.0
        for index in 0 ..< sessionCount {
            var session = first
            session["date"] = firstDateMillis + Int64(index) * 86_400_000
            session.removeValue(forKey: "startedAt")
            session["note"] = note
            generated.append(session)
            for set in sets {
                volume += (set["weight"] as? Double ?? 0) * Double(set["reps"] as? Int ?? 0)
            }
        }
        root["sessions"] = generated
        var summary = try XCTUnwrap(template["summary"] as? [String: Any])
        summary["sessionCount"] = sessionCount
        summary["setCount"] = sessionCount * sets.count
        summary["totalVolume"] = volume
        root["summary"] = summary
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func temporaryDefaults(named name: String) -> UserDefaults {
        let suiteName = "GymAppTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private final class LocalStoreTestKeychain: KeychainStoring {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        lock.withLock { values[account] = data }
    }

    func read(account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func delete(account: String) throws {
        lock.withLock { _ = values.removeValue(forKey: account) }
    }
}
