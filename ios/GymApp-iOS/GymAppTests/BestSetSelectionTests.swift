import Foundation
import XCTest
@testable import GymApp

/// Runs shared/best-set-v1.json, the same cases the Android suite runs.
final class BestSetSelectionTests: XCTestCase {
    func testSharedCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let sets = try XCTUnwrap(item["sets"] as? [[String: Any]])
            let candidates = try sets.map { set in
                BestSetCandidate(
                    weight: try XCTUnwrap((set["weight"] as? NSNumber)?.doubleValue),
                    reps: try XCTUnwrap(set["reps"] as? Int),
                    isPersonalRecord: try XCTUnwrap(set["isPR"] as? Bool)
                )
            }
            let expected = item["expectedBestIndex"] as? Int
            XCTAssertEqual(BestSetSelection.bestIndex(of: candidates), expected, id)
        }
    }

    private func contract() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("shared/best-set-v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
