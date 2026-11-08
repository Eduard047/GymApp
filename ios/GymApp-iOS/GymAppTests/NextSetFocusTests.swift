import XCTest
@testable import GymApp

/// Runs shared/next-set-focus-v1.json, the same cases the Android suite runs.
final class NextSetFocusTests: XCTestCase {
    func testSharedGoldenCases() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let rawSets = try XCTUnwrap(item["sets"] as? [[Any]])
            let sets = try rawSets.map { triple -> NextSetFocus.SetState in
                NextSetFocus.SetState(
                    exerciseIndex: try XCTUnwrap(triple[0] as? Int),
                    setIndex: try XCTUnwrap(triple[1] as? Int),
                    completed: try XCTUnwrap(triple[2] as? Bool)
                )
            }
            let rawRecorded = try XCTUnwrap(item["recorded"] as? [Int])
            let recorded = NextSetFocus.SetPosition(exerciseIndex: rawRecorded[0], setIndex: rawRecorded[1])
            var expected: NextSetFocus.SetPosition?
            if let rawNext = item["next"] as? [Int] {
                expected = NextSetFocus.SetPosition(exerciseIndex: rawNext[0], setIndex: rawNext[1])
            }
            XCTAssertEqual(NextSetFocus.next(in: sets, after: recorded), expected, id)
        }
    }

    func testRecordedSetIsNeverItsOwnTargetEvenWhenMarkedPending() {
        let sets = [NextSetFocus.SetState(exerciseIndex: 0, setIndex: 0, completed: false)]
        XCTAssertNil(NextSetFocus.next(in: sets, after: .init(exerciseIndex: 0, setIndex: 0)))
    }

    private func contract() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("shared/next-set-focus-v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
