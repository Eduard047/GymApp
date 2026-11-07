import Foundation
import XCTest
@testable import GymApp

/// Runs shared/exercise-identity-v1.json, the same cases the Android suite runs.
final class ExerciseIdentityGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 20)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let normalized = try XCTUnwrap(item["normalized"] as? String)
            let expectedKey = item["catalogKey"] as? String

            XCTAssertEqual(normalizeExerciseIdentityName(input), normalized, "\(id) normalized")
            XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: input), expectedKey, "\(id) canonicalKey")
            if !normalized.isEmpty {
                // The raw name is authoritative; untrusted catalogKey metadata never overrides it.
                XCTAssertEqual(
                    BuiltInExerciseCatalog.resolvedKey(catalogKey: "bench_press", name: input),
                    expectedKey,
                    "\(id) resolvedKey"
                )
                XCTAssertEqual(
                    BuiltInExerciseCatalog.resolvedKey(catalogKey: nil, name: input),
                    expectedKey,
                    "\(id) resolvedKey no metadata"
                )
            }
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/exercise-identity-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
