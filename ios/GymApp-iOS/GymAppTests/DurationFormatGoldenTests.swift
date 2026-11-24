import Foundation
import XCTest
@testable import GymApp

/// Runs shared/duration-format-v1.json, the same cases the Android suite runs.
@MainActor
final class DurationFormatGoldenTests: XCTestCase {
    func testCompactDurationMatchesSharedCases() throws {
        try checkLocalized("compactDuration") { seconds, language in
            gymCompactDuration(seconds, languageCode: language)
        }
    }

    func testWorkoutDurationMatchesSharedCases() throws {
        try checkLocalized("workoutDuration") { seconds, language in
            gymWorkoutDuration(seconds, languageCode: language)
        }
    }

    func testSpokenImportedMetricsUseFullWordsAndPlurals() {
        XCTAssertEqual(gymSpokenWorkoutDuration(3_900, languageCode: "en"), "1 hour 5 minutes")
        XCTAssertEqual(gymSpokenWorkoutDuration(3_900, languageCode: "ru"), "1 час 5 минут")
        XCTAssertEqual(gymSpokenWorkoutDuration(7_380, languageCode: "uk"), "2 години 3 хвилини")
        XCTAssertEqual(gymSpokenWorkoutDuration(0, languageCode: "en"), "1 minute")
        XCTAssertEqual(gymSpokenWorkoutDuration(7_200, languageCode: "ru"), "2 часа")
        XCTAssertEqual(gymSpokenBeatsPerMinute(72, languageCode: "ru"), "72 удара в минуту")
        XCTAssertEqual(gymSpokenBeatsPerMinute(115, languageCode: "uk"), "115 ударів на хвилину")
        XCTAssertEqual(gymSpokenBeatsPerMinute(1, languageCode: "en"), "1 beat per minute")
        XCTAssertEqual(gymSpokenKilocalories(421, languageCode: "ru"), "421 килокалория")
        XCTAssertEqual(gymSpokenKilocalories(350, languageCode: "en"), "350 kilocalories")
    }

    func testElapsedTimerMatchesSharedCases() throws {
        try checkPlain("elapsedTimer") { seconds in
            ActiveWorkoutView.clock(TimeInterval(seconds))
        }
    }

    func testRestCountdownMatchesSharedCases() throws {
        try checkPlain("restCountdown") { seconds in
            WorkoutRestTimerControls.clock(seconds)
        }
    }

    func testGarminDurationMatchesSharedCases() throws {
        try checkPlain("garminDuration") { seconds in
            garminDuration(Int64(seconds))
        }
    }

    private func cases(_ name: String) throws -> [[String: Any]] {
        let formatters = try XCTUnwrap(contract()["formatters"] as? [String: Any])
        let formatter = try XCTUnwrap(formatters[name] as? [String: Any])
        let cases = try XCTUnwrap(formatter["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 11, "\(name) needs the full second set")
        return cases
    }

    private func checkLocalized(_ name: String, format: (Int, String) -> String) throws {
        let languages = try XCTUnwrap(contract()["languages"] as? [String])
        XCTAssertEqual(languages.count, 3)
        for item in try cases(name) {
            let seconds = try XCTUnwrap(item["seconds"] as? Int)
            let expected = try XCTUnwrap(item["expected"] as? [String: String])
            for language in languages {
                XCTAssertEqual(
                    format(seconds, language), try XCTUnwrap(expected[language]),
                    "\(name) \(seconds) \(language)"
                )
            }
        }
    }

    private func checkPlain(_ name: String, format: (Int) -> String) throws {
        for item in try cases(name) {
            let seconds = try XCTUnwrap(item["seconds"] as? Int)
            let expected = try XCTUnwrap(item["expected"] as? String)
            XCTAssertEqual(format(seconds), expected, "\(name) \(seconds)")
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/duration-format-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
