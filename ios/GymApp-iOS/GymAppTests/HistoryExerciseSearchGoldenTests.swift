import Foundation
import XCTest
@testable import GymApp

/// Runs shared/history-exercise-search-v1.json, the same cases the Android suite runs.
final class HistoryExerciseSearchGoldenTests: XCTestCase {
    private struct Workout {
        let id: String
        let exerciseNames: [String]
    }

    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        if let limit = root["displayLimit"] as? Int {
            XCTAssertEqual(limit, HistoryExerciseSearch.displayLimit)
        }
        let workouts = try XCTUnwrap(root["workouts"] as? [[String: Any]]).map { item in
            Workout(
                id: item["id"] as? String ?? "",
                exerciseNames: item["exerciseNames"] as? [String] ?? []
            )
        }
        XCTAssertEqual(workouts.count, 10)
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 16)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let query = try XCTUnwrap(item["query"] as? String, id)
            let expected = try XCTUnwrap(item["expectedWorkoutIds"] as? [String], id)
            let actual = HistoryExerciseSearch.filter(workouts, query: query) { $0.exerciseNames }
                .map(\.id)
            XCTAssertEqual(actual, expected, "\(id) (query: \"\(query)\")")
        }
    }

    func testFilterIsUncappedAndKeepsInputOrder() {
        let workouts = (0..<50).map { Workout(id: "w\($0)", exerciseNames: ["Bench Press"]) }
        let result = HistoryExerciseSearch.filter(workouts, query: "bench") { $0.exerciseNames }
        XCTAssertEqual(result.map(\.id), workouts.map(\.id))
        XCTAssertEqual(HistoryExerciseSearch.displayLimit, 30)
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/history-exercise-search-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
