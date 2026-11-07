import Foundation
import XCTest
@testable import GymApp

/// Runs shared/rest-duration-v1.json, the same cases the Android suite runs.
final class RestDurationGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let name = try XCTUnwrap(item["name"] as? String)
            let expected = try XCTUnwrap(item["restSeconds"] as? Int)
            let catalogKey = item["catalogKey"] as? String

            XCTAssertEqual(
                RecommendationEngine.restDurationSeconds(exerciseCatalogKey: nil, exerciseName: name),
                expected,
                "\(id) name only"
            )
            XCTAssertEqual(
                RecommendationEngine.restDurationSeconds(exerciseCatalogKey: catalogKey, exerciseName: name),
                expected,
                "\(id) name and catalogKey"
            )
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/rest-duration-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
