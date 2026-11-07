import XCTest
@testable import GymApp

/// Runs shared/exercise-search-v1.json, the same cases the Android suite runs.
final class ExerciseSearchGoldenTests: XCTestCase {
    func testSharedTransliterationMatchesAndroid() throws {
        let cases = try XCTUnwrap(contract()["transliteration"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let input = try XCTUnwrap(item["input"] as? String)
            let expected = try XCTUnwrap(item["expected"] as? String)
            XCTAssertEqual(ExerciseFilterEngine.transliterated(input), expected, id)
        }
    }

    func testSharedTokenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["tokenCases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let query = try XCTUnwrap(item["query"] as? String)
            let expected = try XCTUnwrap(item["tokens"] as? [String])
            let actual = ExerciseFilterEngine.boundedSearchTokens(
                query,
                maximumCharacters: 256,
                fallbackToRawTokensWhenEmpty: true
            )
            XCTAssertEqual(actual, expected, id)
        }
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/exercise-search-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
