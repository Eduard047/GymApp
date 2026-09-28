import XCTest
@testable import GymApp

/// Local side of the per-workout cloud merge: the owner-bound baseline and change
/// journal, and applying a merged history to the store.
final class WorkoutCloudSyncStateTests: XCTestCase {
    private let ownerID = "00000000-0000-4000-8000-0000000001a1"
    private let otherOwnerID = "00000000-0000-4000-8000-0000000001a2"

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("workout-cloud-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func session(_ start: Int64, _ name: String, weight: Double, reps: Int) -> BackupSession {
        let block = BackupWorkoutExercise(name: name, sets: [BackupSet(weight: weight, reps: reps)])
        return BackupSession(date: start, exercises: [block])
    }

    func testSyncStateSurvivesReloadAndStaysWithItsOwner() throws {
        let directory = try makeDirectory()
        let key = "sync-state-\(UUID().uuidString)"
        let store = try WorkoutStore(accountStorageKey: key, directoryURL: directory)
        let baseline = WorkoutCloudMerge.Core(
            configuredExercises: [BackupExercise(name: "Band Fly")],
            sessions: [session(1_789_000_000_000, "Band Fly", weight: 15, reps: 12)]
        )
        let journal: [Int64: Int64] = [1_789_000_000_000: 1_790_000_000_000]
        let state = try WorkoutCloudSyncState(
            ownerUserID: ownerID.uppercased(),
            baseline: baseline,
            localChangedAt: journal
        )
        try store.saveWorkoutCloudSyncState(state)

        let reloaded = try WorkoutStore(accountStorageKey: key, directoryURL: directory)
        let loaded = try XCTUnwrap(reloaded.loadWorkoutCloudSyncState(ownerUserID: ownerID))
        XCTAssertEqual(loaded, state)
        XCTAssertEqual(loaded.ownerUserID, ownerID)
        XCTAssertEqual(loaded.baseline, baseline)
        XCTAssertEqual(loaded.localChangedAt, journal)
        XCTAssertNil(reloaded.loadWorkoutCloudSyncState(ownerUserID: otherOwnerID))

        try reloaded.saveWorkoutCloudSyncState(nil)
        XCTAssertNil(reloaded.loadWorkoutCloudSyncState(ownerUserID: ownerID))
    }

    func testSyncStateRejectsInvalidOwnersAndUnknownVersions() throws {
        XCTAssertThrowsError(try WorkoutCloudSyncState(
            ownerUserID: "not-a-user",
            baseline: nil,
            localChangedAt: [:]
        ))
        let unknownVersion = """
        {"version":2,"ownerUserID":"\(ownerID)","localChangedAt":[]}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(
            WorkoutCloudSyncState.self,
            from: Data(unknownVersion.utf8)
        ))
    }

    func testChangedSessionStartsFindsAddedRemovedAndEditedWorkouts() {
        let before = WorkoutCloudMerge.Core(
            configuredExercises: [],
            sessions: [
                session(1, "Band Fly", weight: 15, reps: 12),
                session(2, "Band Fly", weight: 15, reps: 12),
                session(3, "Band Fly", weight: 15, reps: 12)
            ]
        )
        let after = WorkoutCloudMerge.Core(
            configuredExercises: [],
            sessions: [
                session(1, "Band Fly", weight: 15, reps: 12),
                session(2, "Band Fly", weight: 17.5, reps: 12),
                session(4, "Band Fly", weight: 15, reps: 12)
            ]
        )
        let changed: Set<Int64> = WorkoutCloudMerge.changedSessionStarts(before: before, after: after)
        XCTAssertEqual(changed, [2, 3, 4])
        XCTAssertEqual(WorkoutCloudMerge.changedSessionStarts(before: before, after: before), [])
    }

    func testApplyingMergeKeepsWorkoutIdentityAndDropsUnusedRemovedExercises() throws {
        let directory = try makeDirectory()
        let store = try WorkoutStore(
            accountStorageKey: "apply-merge-\(UUID().uuidString)",
            directoryURL: directory
        )
        let landmine = try store.addExercise(name: "Landmine Press")
        let bandFly = try store.addExercise(name: "Band Fly")
        let firstStart: Int64 = 1_789_000_000_000
        let secondStart: Int64 = 1_789_100_000_000
        let newStart: Int64 = 1_789_200_000_000
        let kept = try store.createWorkout(
            date: Date(gymEpochMilliseconds: firstStart),
            exercises: [WorkoutExerciseDraft(exerciseID: landmine.id, sets: [.init(weight: 40, reps: 8)])]
        )
        _ = try store.createWorkout(
            date: Date(gymEpochMilliseconds: secondStart),
            exercises: [WorkoutExerciseDraft(exerciseID: bandFly.id, sets: [.init(weight: 15, reps: 12)])]
        )

        let local = WorkoutCloudMerge.Core(
            configuredExercises: [
                BackupExercise(name: "Band Fly"),
                BackupExercise(name: "Landmine Press")
            ],
            sessions: [
                session(firstStart, "Landmine Press", weight: 40, reps: 8),
                session(secondStart, "Band Fly", weight: 15, reps: 12)
            ]
        )
        // The other device edited the first workout, deleted the second, and added a
        // third one with an exercise this device has not seen yet.
        let merged = WorkoutCloudMerge.Core(
            configuredExercises: [
                BackupExercise(name: "Cable Kickback"),
                BackupExercise(name: "Landmine Press")
            ],
            sessions: [
                session(firstStart, "Landmine Press", weight: 42.5, reps: 8),
                session(newStart, "Cable Kickback", weight: 17.5, reps: 12)
            ]
        )

        let changed = try store.applyWorkoutCloudMerge(merged, local: local)

        XCTAssertEqual(changed, 3)
        let workouts: [WorkoutSession] = store.workouts.sorted { $0.date < $1.date }
        XCTAssertEqual(workouts.count, 2)
        XCTAssertEqual(workouts[0].id, kept.id)
        XCTAssertEqual(workouts[0].exercises.first?.sets.first?.weight, 42.5)
        XCTAssertEqual(workouts[1].date.gymEpochMilliseconds, newStart)
        let names: Set<String> = Set(store.exercises.map(\.name))
        XCTAssertTrue(names.contains("Landmine Press"))
        XCTAssertTrue(names.contains("Cable Kickback"))
        XCTAssertFalse(names.contains("Band Fly"))
    }
}
