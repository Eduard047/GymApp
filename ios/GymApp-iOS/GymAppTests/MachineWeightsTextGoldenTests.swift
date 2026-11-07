import Foundation
import XCTest
@testable import GymApp

/// Runs shared/machine-weights-v1.json, the same cases the Android suite runs.
final class MachineWeightsTextGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 40)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let expected: [Double]? = (item["invalid"] as? Bool) == true
                ? nil
                : try XCTUnwrap(item["weights"] as? [NSNumber]).map(\.doubleValue)
            XCTAssertEqual(MachineWeightsText.parse(input), expected, id)
        }
    }

    func testEditorTextRoundTripsThroughTheParserInEveryLanguage() {
        let weights = [0, 0.25, 2.5, 12.5, 100, 1_000_000, 0.1 + 0.2]
        for language in ["en", "uk", "ru"] {
            let text = weights
                .map { gymMachineWeightEditText($0, languageCode: language) }
                .joined(separator: "\n")
            XCTAssertEqual(
                MachineWeightsText.parse(text),
                [0, 0.25, 0.3, 2.5, 12.5, 100, 1_000_000],
                language
            )
        }
        XCTAssertEqual(gymMachineWeightEditText(12.5, languageCode: "ru"), "12,5")
    }

    func testPresetWeightsNeverTrapOnDegenerateInput() {
        XCTAssertEqual(MachineWeightsText.presetWeights(step: 2.5, maximum: 10), [2.5, 5, 7.5, 10])
        XCTAssertEqual(MachineWeightsText.presetWeights(step: 5, maximum: 300).count, 60)
        XCTAssertEqual(MachineWeightsText.presetWeights(step: 1, maximum: 1_000).count, 128)
        XCTAssertEqual(MachineWeightsText.presetWeights(step: 0, maximum: 100), [])
        XCTAssertEqual(MachineWeightsText.presetWeights(step: -5, maximum: 100), [])
        XCTAssertEqual(MachineWeightsText.presetWeights(step: .nan, maximum: 100), [])
        XCTAssertEqual(MachineWeightsText.presetWeights(step: 5, maximum: .infinity), [])
        XCTAssertEqual(MachineWeightsText.presetWeights(step: 5, maximum: 4), [])
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/machine-weights-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
