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

    func testSharedRestLimitsMatchAndroid() throws {
        let limits = try XCTUnwrap(contract()["restLimits"] as? [String: Any])
        XCTAssertEqual(limits["minSeconds"] as? Int, RestTimerLimits.minimumSeconds)
        XCTAssertEqual(limits["maxSeconds"] as? Int, RestTimerLimits.maximumSeconds)

        let valid = try XCTUnwrap(limits["validCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(valid.count, 6)
        for item in valid {
            let id = try XCTUnwrap(item["id"] as? String)
            XCTAssertEqual(
                RestTimerLimits.isValid(try XCTUnwrap(item["seconds"] as? Int)),
                try XCTUnwrap(item["valid"] as? Bool),
                id
            )
        }

        let adjust = try XCTUnwrap(limits["adjustCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(adjust.count, 11)
        for item in adjust {
            let id = try XCTUnwrap(item["id"] as? String)
            XCTAssertEqual(
                RestTimerLimits.adjusted(
                    remainingSeconds: try XCTUnwrap(item["remainingSeconds"] as? Int),
                    deltaSeconds: try XCTUnwrap(item["deltaSeconds"] as? Int)
                ),
                try XCTUnwrap(item["expectedSeconds"] as? Int),
                id
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
