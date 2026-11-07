import Foundation
import XCTest
@testable import GymApp

/// Runs shared/warmup-ramp-v1.json, the same cases the Android suite runs.
final class WarmupRampGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        XCTAssertEqual(root["minimumAboveBarKg"] as? Double, PlateCalculator.warmupMinimumAboveBar)
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let actual = PlateCalculator.warmup(
                workingWeight: try XCTUnwrap(item["workingWeight"] as? Double),
                bar: try XCTUnwrap(item["bar"] as? Double),
                plates: try XCTUnwrap(item["plates"] as? [Double])
            )
            let expected = try XCTUnwrap(item["steps"] as? [[String: Any]])
            XCTAssertEqual(actual.count, expected.count, "\(id) step count")
            for (step, expectedStep) in zip(actual, expected) {
                XCTAssertEqual(step.weight, expectedStep["weight"] as? Double, "\(id) weight")
                XCTAssertEqual(step.reps, expectedStep["reps"] as? Int, "\(id) reps")
                XCTAssertEqual(step.load.platesPerSide, expectedStep["platesPerSide"] as? [Double], "\(id) plates")
            }
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/warmup-ramp-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
