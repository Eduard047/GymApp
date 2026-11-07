import Foundation
import XCTest
@testable import GymApp

/// Runs shared/live-social-names-v1.json through the live and social name validators, like the Android suite.
final class LiveSocialNamesGoldenTests: XCTestCase {
    private struct Vector {
        let id: String
        let kinds: Set<String>
        let valid: Bool
        let text: String
    }

    func testSharedVectorsGiveTheSameVerdictInLiveAndSocial() throws {
        let vectors = try loadVectors()
        XCTAssertGreaterThanOrEqual(vectors.count, 40)
        var exerciseChecked = 0
        var displayChecked = 0
        for vector in vectors {
            if vector.kinds.contains("exerciseName") {
                exerciseChecked += 1
                assertVerdict("live exercise name \(vector.id)", vector.valid) {
                    _ = try LiveWorkoutPayloadParser.inbox(from: self.data(self.liveInbox(exerciseName: vector.text)))
                }
                assertVerdict("social exercise name \(vector.id)", vector.valid) {
                    _ = try SocialPayloadParser.workoutInvitePlan(from: self.data(self.socialInvitePlan(vector.text)))
                }
            }
            if vector.kinds.contains("displayName") {
                displayChecked += 1
                assertVerdict("live display name \(vector.id)", vector.valid) {
                    _ = try LiveWorkoutPayloadParser.inbox(from: self.data(self.liveInbox(displayName: vector.text)))
                }
                assertVerdict("social display name \(vector.id)", vector.valid) {
                    _ = try SocialPayloadParser.dashboard(from: self.data(self.socialDashboard(vector.text)))
                }
            }
        }
        XCTAssertGreaterThanOrEqual(exerciseChecked, 30)
        XCTAssertGreaterThanOrEqual(displayChecked, 25)
    }

    private func assertVerdict(
        _ label: String,
        _ valid: Bool,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ parse: () throws -> Void
    ) {
        let accepted = (try? parse()) != nil
        XCTAssertEqual(accepted, valid, label, file: file, line: line)
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func liveInbox(exerciseName: String = "Bench press", displayName: String = "Owner") -> [String: Any] {
        [
            "version": 1,
            "invitations": [[
                "roomId": "lr_0123456789abcdef0123456789abcdef",
                "status": "waiting",
                "roomRevision": 1,
                "createdAt": "2026-08-10T09:00:00Z",
                "inviteExpiresAt": "2026-08-10T11:00:00Z",
                "summary": [
                    "exerciseCount": 1,
                    "setCount": 1,
                    "exerciseNames": [exerciseName]
                ],
                "owner": [
                    "profileId": "p_" + String(repeating: "1", count: 32),
                    "displayName": displayName
                ]
            ]],
            "rooms": []
        ]
    }

    private func socialInvitePlan(_ exerciseName: String) -> [String: Any] {
        [
            "version": 1,
            "inviteId": "wi_" + String(repeating: "1", count: 32),
            "inviteRevision": 1,
            "workout": [
                "version": 1,
                "exercises": [[
                    "name": exerciseName,
                    "sets": [["weight": 60.0, "reps": 5]]
                ]]
            ]
        ]
    }

    private func socialDashboard(_ displayName: String) -> [String: Any] {
        let profileID = "p_" + String(repeating: "0", count: 32)
        return [
            "version": 1,
            "self": [
                "profileId": profileID,
                "friendCode": profileID,
                "displayName": displayName,
                "xp": 800,
                "level": 4,
                "workouts": 12,
                "statsAvailable": true,
                "progressUpdatedAt": "2026-08-09T10:00:00Z",
                "privacy": [
                    "allowRequests": true,
                    "shareProgress": true,
                    "shareRecentWorkouts": true,
                    "shareRecords": true
                ],
                "settingsRevision": 3
            ],
            "friends": [],
            "incoming": [],
            "outgoing": [],
            "blocked": [],
            "pendingWorkoutInviteCount": 0
        ]
    }

    private func loadVectors() throws -> [Vector] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/live-social-names-v1.json")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        let items = try XCTUnwrap(root["vectors"] as? [[String: Any]])
        return try items.map { item in
            let text: String
            if let repeatSpec = item["repeat"] as? [String: Any] {
                let unit = try XCTUnwrap(repeatSpec["unit"] as? String)
                let count = try XCTUnwrap(repeatSpec["count"] as? Int)
                text = (repeatSpec["prefix"] as? String ?? "")
                    + String(repeating: unit, count: count)
                    + (repeatSpec["suffix"] as? String ?? "")
            } else {
                text = try XCTUnwrap(item["text"] as? String)
            }
            return Vector(
                id: try XCTUnwrap(item["id"] as? String),
                kinds: Set(try XCTUnwrap(item["kinds"] as? [String])),
                valid: try XCTUnwrap(item["valid"] as? Bool),
                text: text
            )
        }
    }
}
