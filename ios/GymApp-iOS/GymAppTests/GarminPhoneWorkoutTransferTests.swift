import XCTest
@testable import GymApp

final class GarminPhoneWorkoutTransferTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private let binding = GarminPhoneBinding(account: String(repeating: "a", count: 64), device: "transfer-test-device", pairingGeneration: String(repeating: "b", count: 64))

    private func frame(_ offset: Int, total: Int = 60) -> [String: Any] {
        [
            "type": "workout_part", "transferVersion": 1, "attemptId": "transfer-attempt-\(offset)", "offset": offset, "totalSets": total,
            "metadata": [
                "type": "create_workout", "bindingVersion": 2, "workoutMode": "planned",
                "requestId": "workout-transfer-test-001", "accountBinding": binding.account,
                "deviceBinding": binding.device, "pairingGeneration": binding.pairingGeneration,
                "startedAtSeconds": Int64(now.timeIntervalSince1970) - 3600,
                "durationSeconds": 3600, "gymCalories": 60.0, "plannedSetCount": total,
                "plannedTargetSetCount": total, "completedPlannedSetCount": total
            ] as [String: Any],
            "set": ["exerciseName": "Bench Press", "weight": 50.0 + Double(offset), "reps": 8],
            "interval": [offset * 30, offset * 30 + 30, 1.0, NSNull(), 0, 0, 0, 0, 0, 0]
        ]
    }

    func testAttemptIdentityIsValidatedAndEchoedWithoutChangingDurableRows() throws {
        let first = try XCTUnwrap(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: frame(0), binding: binding, now: now))
        var retry = frame(0)
        retry["attemptId"] = "transfer-retry-00001"
        let replay = try XCTUnwrap(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: retry, binding: binding, now: now))
        XCTAssertEqual(replay.attemptID, "transfer-retry-00001")
        XCTAssertEqual(first.state, replay.state)
        for invalid in [NSNull(), "", "short", String(repeating: "a", count: 129), "invalid-attempt\nvalue", 17] as [Any] {
            retry["attemptId"] = invalid
            XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: retry, binding: binding, now: now))
        }
    }

    func testSixtySetsSurviveSerializedRestartAndIdenticalReplay() throws {
        var state: Data?
        for offset in 0 ..< 60 {
            let step = try XCTUnwrap(GarminPhoneWorkoutTransfer.accept(previous: state, raw: frame(offset), binding: binding, now: now))
            XCTAssertEqual(step.nextOffset, offset + 1)
            if offset < 59 { XCTAssertNil(step.completeMessage) }
            else {
                let parsed = try XCTUnwrap(GarminPhoneWorkoutParser.parse(step.completeMessage!, expectedBinding: binding, now: now))
                XCTAssertEqual(parsed.sets.count, 60)
                XCTAssertEqual(parsed.sets.last?.weight, 109)
                XCTAssertEqual(parsed.setIntervals.count, 60)
            }
            state = step.state
            XCTAssertEqual(GarminPhoneWorkoutTransfer.accept(previous: state, raw: frame(offset), binding: binding, now: now)?.state, state)
        }
    }

    func testRejectsGapsConflictsOwnershipAndChangedMetadata() throws {
        let first = try XCTUnwrap(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: frame(0), binding: binding, now: now))
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: frame(2), binding: binding, now: now))
        var conflict = frame(0)
        conflict["set"] = ["exerciseName": "Squat", "weight": 50, "reps": 8]
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: conflict, binding: binding, now: now))
        let wrong = GarminPhoneBinding(account: String(repeating: "c", count: 64), device: binding.device, pairingGeneration: binding.pairingGeneration)
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: frame(1), binding: wrong, now: now))
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: frame(1, total: 59), binding: binding, now: now))
        XCTAssertNotNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: frame(1), binding: binding, now: now))
    }

    func testRejectsCorruptStorageOverlappingIntervalsAndMissingFields() throws {
        let first = try XCTUnwrap(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: frame(0, total: 2), binding: binding, now: now))
        let corrupted = Data(String(decoding: first.state, as: UTF8.self).replacingOccurrences(of: "Bench Press", with: "").utf8)
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: corrupted, raw: frame(1, total: 2), binding: binding, now: now))
        var overlap = frame(1, total: 2)
        overlap["interval"] = [0, 30, 1.0, NSNull(), 0, 0, 0, 0, 0, 0]
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: overlap, binding: binding, now: now))
        var missing = frame(1, total: 2)
        missing.removeValue(forKey: "interval")
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: missing, binding: binding, now: now))
    }

    func testBoundsAndExpiredContinuation() throws {
        var invalid = frame(0)
        invalid["offset"] = true
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: invalid, binding: binding, now: now))
        invalid = frame(0); invalid["extra"] = "x"
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: invalid, binding: binding, now: now))
        invalid = frame(0); invalid["interval"] = [Double.nan]
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: invalid, binding: binding, now: now))
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: Data(String(repeating: "[", count: 100).utf8), raw: frame(0), binding: binding, now: now))
        let first = try XCTUnwrap(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: frame(0), binding: binding, now: now))
        let later = now.addingTimeInterval(86401)
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: frame(1), binding: binding, now: later))
        XCTAssertNotNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: frame(0), binding: binding, now: later))
    }

    func testFreeWorkoutHasOriginalMetricsWithoutInventedSets() throws {
        var free = frame(0)
        free["totalSets"] = 0
        free.removeValue(forKey: "set"); free.removeValue(forKey: "interval")
        var metadata = free["metadata"] as! [String: Any]
        metadata["workoutMode"] = "free"
        for key in ["plannedSetCount", "plannedTargetSetCount", "completedPlannedSetCount"] { metadata.removeValue(forKey: key) }
        free["metadata"] = metadata
        let step = try XCTUnwrap(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: free, binding: binding, now: now))
        let workout = try XCTUnwrap(GarminPhoneWorkoutParser.parse(step.completeMessage!, expectedBinding: binding, now: now))
        XCTAssertEqual(workout.mode, .free)
        XCTAssertTrue(workout.sets.isEmpty)
        XCTAssertEqual(workout.durationSeconds, 3600)
    }
    func testFileStoreRestartBackupExclusionAndRejectedWritePreservation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try XCTUnwrap(GarminPhoneWorkoutTransferStore(root: root).accept(account: "synthetic-account", device: binding.device, frame: frame(0, total: 2), binding: binding, now: now))
        XCTAssertNil(GarminPhoneWorkoutTransferStore(root: root).accept(account: "synthetic-account", device: binding.device, frame: frame(1, total: 3), binding: binding, now: now))
        let folder = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: file), first.state)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertNotNil(GarminPhoneWorkoutTransferStore(root: root).accept(account: "synthetic-account", device: binding.device, frame: frame(1, total: 2), binding: binding, now: now)?.completeMessage)
        XCTAssertTrue(GarminPhoneWorkoutTransferStore(root: root).clear(account: "synthetic-account"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testFreshGenerationCanRestartOnlyFromOffsetZero() throws {
        let first = try XCTUnwrap(GarminPhoneWorkoutTransfer.accept(previous: nil, raw: frame(0), binding: binding, now: now))
        let nextBinding = GarminPhoneBinding(account: binding.account, device: binding.device, pairingGeneration: String(repeating: "c", count: 64))
        func next(_ offset: Int) -> [String: Any] {
            var value = frame(offset)
            var metadata = value["metadata"] as! [String: Any]
            metadata["pairingGeneration"] = nextBinding.pairingGeneration
            value["metadata"] = metadata
            return value
        }
        XCTAssertNil(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: next(1), binding: nextBinding, now: now))
        XCTAssertEqual(GarminPhoneWorkoutTransfer.accept(previous: first.state, raw: next(0), binding: nextBinding, now: now)?.nextOffset, 1)
    }

}
