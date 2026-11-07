import Foundation
import XCTest
@testable import GymApp

/// Runs shared/pr-history-v1.json, the same cases the Android suite runs.
final class PersonalRecordHistoryGoldenTests: XCTestCase {
    func testSharedGoldenCasesMatchAndroid() throws {
        let root = try contract()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 10)
        let limit = try XCTUnwrap(root["limit"] as? Int)
        XCTAssertEqual(limit, PersonalRecordHistory.maximumCount)

        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String)
            let sessions = try XCTUnwrap(item["sessions"] as? [[String: Any]])
            let expected = try XCTUnwrap(item["expected"] as? [[String: Any]])

            let actual = PersonalRecordHistory.replay(try history(sessions), limit: limit).map { event in
                "\(sessionNumber(event.workoutID))/\(event.setOrderIndex)/\(event.weight)/\(event.reps)/\(kindName(event.kind))"
            }
            let wanted = try expected.map { row -> String in
                let session = try XCTUnwrap(row["session"] as? Int)
                let set = try XCTUnwrap(row["set"] as? Int)
                let weight = try XCTUnwrap((row["weight"] as? NSNumber)?.doubleValue)
                let reps = try XCTUnwrap(row["reps"] as? Int)
                let kind = try XCTUnwrap(row["kind"] as? String)
                return "\(session)/\(set)/\(weight)/\(reps)/\(kind)"
            }
            XCTAssertEqual(actual, wanted, id)
        }
    }

    func testEventsCarryTheSessionDate() throws {
        let sessions: [[String: Any]] = [
            ["id": 1, "date": 1000, "sets": [["weight": 100, "reps": 5]]],
            ["id": 2, "date": 5000, "sets": [["weight": 105, "reps": 5]]]
        ]
        let events = PersonalRecordHistory.replay(try history(sessions))
        XCTAssertEqual(events.map(\.date), [Date(timeIntervalSince1970: 5)])
    }

    func testListIsCappedAtTheLimitKeepingTheNewest() {
        // 60 sessions, each heavier than the last: 59 records.
        let entries = (1 ... 60).map { session in
            ExerciseHistoryEntry(
                setID: sessionUUID(session * 10),
                workoutID: sessionUUID(session),
                sessionDate: Date(timeIntervalSince1970: Double(session)),
                exerciseID: sessionUUID(999),
                exerciseName: "Bench",
                weight: 50 + Double(session),
                reps: 5,
                setOrderIndex: 0
            )
        }
        let events = PersonalRecordHistory.replay(entries)
        XCTAssertEqual(events.count, PersonalRecordHistory.maximumCount)
        XCTAssertEqual(events.first.map { sessionNumber($0.workoutID) }, 60)
        XCTAssertEqual(events.last.map { sessionNumber($0.workoutID) }, 11)
        XCTAssertTrue(PersonalRecordHistory.replay([]).isEmpty)
    }

    private func kindName(_ kind: PersonalRecordHistoryKind) -> String {
        switch kind {
        case .weight: return "weight"
        case .estimatedOneRepMax: return "e1rm"
        }
    }

    private func sessionUUID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", number))!
    }

    private func sessionNumber(_ id: UUID) -> Int {
        Int(id.uuidString.suffix(12)) ?? -1
    }

    private func history(_ sessions: [[String: Any]]) throws -> [ExerciseHistoryEntry] {
        var entries: [ExerciseHistoryEntry] = []
        for session in sessions {
            let sessionID = try XCTUnwrap(session["id"] as? Int)
            let date = try XCTUnwrap((session["date"] as? NSNumber)?.doubleValue)
            let sets = try XCTUnwrap(session["sets"] as? [[String: Any]])
            for (index, set) in sets.enumerated() {
                entries.append(
                    ExerciseHistoryEntry(
                        setID: sessionUUID(sessionID * 1_000 + index),
                        workoutID: sessionUUID(sessionID),
                        sessionDate: Date(timeIntervalSince1970: date / 1000),
                        exerciseID: sessionUUID(999_999),
                        exerciseName: "Exercise",
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
            .appendingPathComponent("shared/pr-history-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }
}
