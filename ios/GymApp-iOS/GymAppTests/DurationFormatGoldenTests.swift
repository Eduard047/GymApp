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
