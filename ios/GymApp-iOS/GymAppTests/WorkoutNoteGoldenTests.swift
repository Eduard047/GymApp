import Foundation
import XCTest
@testable import GymApp

/// Runs shared/workout-note-v1.json, the same cases the Android suite runs.
final class WorkoutNoteGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        XCTAssertEqual(root["maxCodePoints"] as? Int, WorkoutNoteRules.maxCodePoints)
        XCTAssertEqual(root["maxUtf8Bytes"] as? Int, WorkoutNoteRules.maxUTF8Bytes)
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)

        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let input = try text(XCTUnwrap(item["input"]), name)
            let valid = try XCTUnwrap(item["valid"] as? Bool, name)
            if valid {
                var expected: String?
                if let stored = item["stored"], !(stored is NSNull) {
                    expected = try text(stored, name)
                }
                let actual = try WorkoutNoteRules.normalized(input)
                XCTAssertEqual(actual, expected, name)
            } else {
                XCTAssertThrowsError(try WorkoutNoteRules.normalized(input), name)
            }
        }
    }

    func testNilInputStoresNothing() throws {
        XCTAssertNil(try WorkoutNoteRules.normalized(nil))
    }

    func testLimitedCutsByCodePointsNotGraphemes() {
        let long = String(repeating: "e\u{0301}", count: 2_001)
        let cut = WorkoutNoteRules.limited(long)
        XCTAssertEqual(cut.unicodeScalars.count, WorkoutNoteRules.maxCodePoints)
        XCTAssertTrue(WorkoutNoteRules.isValid(cut))
        XCTAssertFalse(WorkoutNoteRules.isValid(long))
    }

    func testCanEditNoteOnlyOnOwnTabWhenNotFinishingAndNotFrozen() {
        XCTAssertTrue(activeWorkoutCanEditNote(hasCommitIntent: false, isLivePlanFrozen: false, isOwnTab: true))
        XCTAssertFalse(activeWorkoutCanEditNote(hasCommitIntent: true, isLivePlanFrozen: false, isOwnTab: true))
        XCTAssertFalse(activeWorkoutCanEditNote(hasCommitIntent: false, isLivePlanFrozen: true, isOwnTab: true))
        XCTAssertFalse(activeWorkoutCanEditNote(hasCommitIntent: false, isLivePlanFrozen: false, isOwnTab: false))
    }

    private func text(_ value: Any, _ name: String) throws -> String {
        if let string = value as? String { return string }
        let spec = try XCTUnwrap(value as? [String: Any], name)
        let unit = try XCTUnwrap(spec["repeat"] as? String, name)
        let count = try XCTUnwrap(spec["count"] as? Int, name)
        return String(repeating: unit, count: count)
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/workout-note-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
