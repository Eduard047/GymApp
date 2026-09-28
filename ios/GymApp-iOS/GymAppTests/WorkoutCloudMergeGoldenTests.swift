import XCTest
@testable import GymApp

/// Runs the shared per-workout merge scenarios from
/// `shared/workout-sync-merge-v1.json` against the iOS merge engine.
final class WorkoutCloudMergeGoldenTests: XCTestCase {
    private struct Contract: Decodable {
        struct Side: Decodable {
            let sessions: [String]?
            let exercises: [String]?
        }

        struct Scenario: Decodable {
            let name: String
            let base: Side
            let local: Side
            let remote: Side
            let localChangedAt: [String: String]?
            let result: Side?
        }

        let sessions: [String: BackupSession]
        let exercises: [String: BackupExercise]
        let times: [String: Int64]
        let mergeScenarios: [Scenario]
        let failClosedScenarios: [Scenario]
    }

    private func loadContract() throws -> Contract {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/workout-sync-merge-v1.json")
        return try JSONDecoder().decode(Contract.self, from: Data(contentsOf: url))
    }

    private func core(_ side: Contract.Side, in contract: Contract) throws -> WorkoutCloudMerge.Core {
        var sessions: [BackupSession] = []
        for name in side.sessions ?? [] {
            sessions.append(try XCTUnwrap(contract.sessions[name], name))
        }
        var exercises: [BackupExercise] = []
        for name in side.exercises ?? [] {
            exercises.append(try XCTUnwrap(contract.exercises[name], name))
        }
        return WorkoutCloudMerge.Core(configuredExercises: exercises, sessions: sessions)
    }

    private func startTime(_ session: BackupSession) -> Int64 {
        WorkoutCloudMerge.sessionIdentity(session) ?? 0
    }

    private func merge(_ scenario: Contract.Scenario, in contract: Contract) throws -> WorkoutCloudMerge.Result {
        var localChangedAt: [Int64: Int64] = [:]
        for (fixture, timeName) in scenario.localChangedAt ?? [:] {
            let session = try XCTUnwrap(contract.sessions[fixture], fixture)
            let identity = try XCTUnwrap(WorkoutCloudMerge.sessionIdentity(session), fixture)
            localChangedAt[identity] = try XCTUnwrap(contract.times[timeName], timeName)
        }
        let remoteRowUpdatedAt: Int64 = try XCTUnwrap(contract.times["remoteRowUpdatedAt"])
        return try WorkoutCloudMerge.merge(
            base: try core(scenario.base, in: contract),
            local: try core(scenario.local, in: contract),
            remote: try core(scenario.remote, in: contract),
            localChangedAt: localChangedAt,
            remoteRowUpdatedAt: remoteRowUpdatedAt
        )
    }

    func testEverySharedMergeScenario() throws {
        let contract = try loadContract()
        XCTAssertGreaterThanOrEqual(contract.mergeScenarios.count, 20)
        for scenario in contract.mergeScenarios {
            let result = try merge(scenario, in: contract)
            let expected = try core(try XCTUnwrap(scenario.result, scenario.name), in: contract)
            let expectedSessions: [BackupSession] = expected.sessions.sorted { (left: BackupSession, right: BackupSession) -> Bool in
                startTime(left) < startTime(right)
            }
            let expectedExercises: [BackupExercise] = expected.configuredExercises
                .sorted(by: BackupExercisePortableWireOrder.precedes)
            XCTAssertEqual(result.merged.sessions, expectedSessions, scenario.name)
            XCTAssertEqual(result.merged.configuredExercises, expectedExercises, scenario.name)
        }
    }

    func testDuplicateStartTimesFailClosed() throws {
        let contract = try loadContract()
        for scenario in contract.failClosedScenarios {
            XCTAssertThrowsError(try merge(scenario, in: contract), scenario.name) { error in
                guard case WorkoutCloudMerge.MergeError.duplicateStartTime = error else {
                    return XCTFail("Unexpected error \(error) in \(scenario.name)")
                }
            }
        }
    }

    func testDivergentWinnersAreReported() throws {
        let contract = try loadContract()
        let localNewer = try XCTUnwrap(contract.mergeScenarios.first { $0.name == "divergent edits: newer local edit wins" })
        let remoteNewer = try XCTUnwrap(contract.mergeScenarios.first { $0.name == "divergent edits: newer remote row wins" })
        let workoutStart: Int64 = try XCTUnwrap(contract.sessions["a"]?.date)

        let localResult = try merge(localNewer, in: contract)
        XCTAssertEqual(localResult.localWins, [workoutStart])
        XCTAssertEqual(localResult.remoteWins, [])

        let remoteResult = try merge(remoteNewer, in: contract)
        XCTAssertEqual(remoteResult.localWins, [])
        XCTAssertEqual(remoteResult.remoteWins, [workoutStart])
    }
}
