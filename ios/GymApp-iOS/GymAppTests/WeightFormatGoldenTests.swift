import Foundation
import XCTest
@testable import GymApp

/// Runs shared/weight-format-v1.json, the same cases the Android suite runs.
final class WeightFormatGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        let languages = try XCTUnwrap(root["languages"] as? [String])
        XCTAssertGreaterThanOrEqual(cases.count, 9)
        XCTAssertEqual(languages.count, 3)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let value = try XCTUnwrap(item["value"] as? Double)
            let input = try XCTUnwrap(item["input"] as? String)
            let display = try XCTUnwrap(item["display"] as? [String: String])
            let volume = try XCTUnwrap(item["volume"] as? [String: String])

            XCTAssertEqual(gymMachineWeightEditText(value, languageCode: "en"), input, "\(id) input")
            for language in languages {
                let expectedDisplay = try XCTUnwrap(display[language])
                let expectedVolume = try XCTUnwrap(volume[language])
                let unit = gymLocalized("kg", languageCode: language)

                XCTAssertEqual(
                    gymMachineWeightEditText(value, languageCode: language), expectedDisplay,
                    "\(id) display \(language)"
                )
                XCTAssertEqual(
                    gymVolumeText(value, languageCode: language), "\(expectedVolume)\u{00A0}\(unit)",
                    "\(id) volume \(language)"
                )
                // The weight field never groups digits, so it matches the ungrouped display text
                // for every value. gymWeightText groups from 1000 on, so it only matches below that.
                XCTAssertEqual(
                    GymWeightFieldFormat(languageCode: language).format(value), expectedDisplay,
                    "\(id) field \(language)"
                )
                if value < 1000 {
                    XCTAssertEqual(
                        gymWeightText(value, languageCode: language), "\(expectedDisplay) \(unit)",
                        "\(id) weightText \(language)"
                    )
                }
            }
        }
    }

    func testWeightFieldRoundTripsLargeWeightsInEveryLanguage() {
        for language in ["en", "uk", "ru"] {
            let style = GymWeightFieldFormat(languageCode: language)
            for value in [1000.0, 1250.5, 12345.6] {
                let text = style.format(value)
                XCTAssertFalse(text.contains("\u{00A0}") || text.contains(" "), "\(language) \(value) grouped: \(text)")
                XCTAssertEqual(GymWeightFieldFormat.parse(text), value, "\(language) \(value) via \(text)")
                XCTAssertEqual(try? style.parseStrategy.parse(text), value, "\(language) \(value) strategy")
            }
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/weight-format-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
