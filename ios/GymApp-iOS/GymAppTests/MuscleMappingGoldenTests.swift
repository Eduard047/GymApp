import Foundation
import XCTest
@testable import GymApp

/// Runs shared/muscle-contributions-v1.json, the same cases the Android suite runs.
final class MuscleMappingGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 100)

        for item in cases {
            let name = try XCTUnwrap(item["name"] as? String)
            let expectedJSON = try XCTUnwrap(item["contributions"] as? [String: Any])
            let expected = try expectedJSON.mapValues { value -> Double in
                try XCTUnwrap((value as? NSNumber)?.doubleValue, "Not a number for \(name)")
            }
            let list = MuscleMappingEngine.defaultContributions(for: name)
            let actual = Dictionary(list.map { ($0.muscleID, $0.weight) }, uniquingKeysWith: { first, _ in first })
            XCTAssertEqual(Set(actual.keys), Set(expected.keys), "\(name) muscle ids")
            XCTAssertEqual(list.count, actual.count, "\(name) has duplicate muscle ids")
            for (muscle, weight) in expected {
                XCTAssertEqual(actual[muscle] ?? -1, weight, accuracy: 1e-9, "\(name) \(muscle)")
            }
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/muscle-contributions-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
