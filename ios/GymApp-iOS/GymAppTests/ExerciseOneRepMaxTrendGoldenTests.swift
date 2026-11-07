import Foundation
import XCTest
@testable import GymApp

/// Runs shared/e1rm-trend-v1.json, the same cases the Android suite runs.
final class ExerciseOneRepMaxTrendGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let cases = try XCTUnwrap(contract()["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 6)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let sessions = try XCTUnwrap(item["sessions"] as? [[String: Any]])
            let expected = try XCTUnwrap(item["expected"] as? [String: Any])

            let points = ExerciseProgressPoint.make(from: try history(sessions))
            let expectedPoints = try XCTUnwrap(expected["points"] as? [[String: Any]])
            XCTAssertEqual(points.count, expectedPoints.count, "\(id) point count")
            for (point, expectedPoint) in zip(points, expectedPoints) {
                let session = try XCTUnwrap(expectedPoint["session"] as? Int)
                XCTAssertEqual(point.workoutID, uuid(session), "\(id) session order")
                if let expectedValue = expectedPoint["e1rm"] as? Double {
                    let actual = try XCTUnwrap(point.estimatedOneRepMax, "\(id) session \(session)")
                    XCTAssertEqual((actual * 10).rounded() / 10, expectedValue, accuracy: 0, "\(id) session \(session)")
                } else {
                    XCTAssertNil(point.estimatedOneRepMax, "\(id) session \(session)")
                }
            }

            let chartVisible = try XCTUnwrap(expected["chartVisible"] as? Bool)
            let series = ExerciseProgressPoint.oneRepMaxSeries(in: points)
            XCTAssertEqual(!series.isEmpty, chartVisible, "\(id) chart visible")
            if chartVisible {
                XCTAssertGreaterThanOrEqual(series.count, 2, "\(id) charted sessions")
            }

            let best = ExerciseProgressPoint.bestOneRepMax(in: points)
            if let expectedBest = expected["bestE1rm"] as? Double {
                XCTAssertEqual(
                    (try XCTUnwrap(best, "\(id) best") * 10).rounded() / 10,
                    expectedBest,
                    accuracy: 0,
                    "\(id) best"
                )
            } else {
                XCTAssertNil(best, "\(id) best")
            }
        }
    }

    private func uuid(_ session: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", session))!
    }

    private func history(_ sessions: [[String: Any]]) throws -> [ExerciseHistoryEntry] {
        var entries: [ExerciseHistoryEntry] = []
        let exerciseID = UUID()
        for session in sessions {
            let sessionID = try XCTUnwrap(session["id"] as? Int)
            let day = try XCTUnwrap(session["date"] as? Int)
            let sets = try XCTUnwrap(session["sets"] as? [[String: Any]])
            for (index, set) in sets.enumerated() {
                entries.append(
                    ExerciseHistoryEntry(
                        setID: UUID(),
                        workoutID: uuid(sessionID),
                        sessionDate: Date(timeIntervalSince1970: Double(day) * 86_400),
                        exerciseID: exerciseID,
                        exerciseName: "Bench Press",
                        weight: try XCTUnwrap((set["weight"] as? NSNumber)?.doubleValue),
                        reps: try XCTUnwrap(set["reps"] as? Int),
                        setOrderIndex: index
                    )
                )
            }
        }
        return entries
    }

    private func contract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/e1rm-trend-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
