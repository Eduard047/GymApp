import Foundation
import XCTest
@testable import GymApp

@MainActor
final class LiveWorkoutContractTests: XCTestCase {
    func testCanonicalActiveSnapshotAndGatewayEnvelopeAreAccepted() throws {
        let rawSnapshot = liveSnapshotObject()
        let snapshot = try LiveWorkoutPayloadParser.snapshot(from: liveJSONData(rawSnapshot))

        XCTAssertEqual(snapshot.room.roomID, liveRoomID)
        XCTAssertEqual(snapshot.room.status, .active)
        XCTAssertEqual(snapshot.plan.exercises.map(\.exerciseID), ["e_01"])
        XCTAssertEqual(snapshot.plan.exercises[0].sets.map(\.setID), ["s_01_01", "s_01_02"])
        XCTAssertEqual(snapshot.currentParticipant?.role, .owner)
        XCTAssertEqual(snapshot.peerParticipant?.progress?.completedSets.map(\.setID), ["s_01_01"])

        let wrapped: [String: Any] = ["version": 1, "result": rawSnapshot]
        let resultData = try LiveWorkoutPayloadParser.gatewayResultData(from: liveJSONData(wrapped))
        XCTAssertEqual(try LiveWorkoutPayloadParser.snapshot(from: resultData), snapshot)
    }

    func testSnapshotRejectsUnknownDuplicateAndNoncanonicalInput() throws {
        var unknown = liveSnapshotObject()
        var room = try XCTUnwrap(unknown["room"] as? [String: Any])
        room["privateUserId"] = liveUserID
        unknown["room"] = room
        XCTAssertThrowsError(try LiveWorkoutPayloadParser.snapshot(from: liveJSONData(unknown))) {
            XCTAssertEqual($0 as? LiveWorkoutContractError, .invalidResponse)
        }

        let duplicate = Data("""
        {"version":1,"version":1,"invitations":[],"rooms":[]}
        """.utf8)
        XCTAssertThrowsError(try LiveWorkoutPayloadParser.inbox(from: duplicate)) {
            XCTAssertEqual($0 as? LiveWorkoutContractError, .invalidResponse)
        }

        var noncanonical = liveSnapshotObject()
        var plan = try XCTUnwrap(noncanonical["plan"] as? [String: Any])
        var exercises = try XCTUnwrap(plan["exercises"] as? [[String: Any]])
        var firstExercise = try XCTUnwrap(exercises.first)
        var sets = try XCTUnwrap(firstExercise["sets"] as? [[String: Any]])
        sets[0]["setId"] = "s_01_02"
        sets[1]["setId"] = "s_01_01"
        firstExercise["sets"] = sets
        exercises[0] = firstExercise
        plan["exercises"] = exercises
        noncanonical["plan"] = plan
        XCTAssertThrowsError(try LiveWorkoutPayloadParser.snapshot(from: liveJSONData(noncanonical)))

        var invalidLifecycle = liveSnapshotObject()
        var participants = try XCTUnwrap(invalidLifecycle["participants"] as? [[String: Any]])
        participants[0]["state"] = "finished"
        participants[0]["finishedAt"] = NSNull()
        invalidLifecycle["participants"] = participants
        XCTAssertThrowsError(try LiveWorkoutPayloadParser.snapshot(from: liveJSONData(invalidLifecycle)))
    }

    func testMutationContractsAndClosedResultsFailClosed() throws {
        let joined = try LiveWorkoutPayloadParser.respondResult(from: liveJSONData([
            "version": 1,
            "result": "joined",
            "roomId": liveRoomID,
            "status": "ready",
            "roomRevision": 2,
            "membershipRevision": 2
        ]))
        XCTAssertEqual(joined.status, .ready)

        let joinedActive = try LiveWorkoutPayloadParser.respondResult(from: liveJSONData([
            "version": 1,
            "result": "joined",
            "roomId": liveRoomID,
            "status": "active",
            "roomRevision": 3,
            "membershipRevision": 2
        ]))
        XCTAssertEqual(joinedActive.status, .active)

        let started = try LiveWorkoutPayloadParser.startResult(from: liveJSONData([
            "version": 1,
            "result": "started",
            "roomId": liveRoomID,
            "status": "active",
            "roomRevision": 3,
            "startedAt": liveStartedAt,
            "activeExpiresAt": liveActiveExpiresAt,
            "myProgressRevision": 1
        ]))
        XCTAssertEqual(started.progressRevision, 1)

        let applied = try LiveWorkoutPayloadParser.applyResult(from: liveJSONData([
            "version": 1,
            "result": "applied",
            "roomId": liveRoomID,
            "roomRevision": 4,
            "progressRevision": 2,
            "kind": "complete_set",
            "setId": "s_01_01",
            "completedAt": liveCompletedAt
        ]))
        XCTAssertEqual(applied.kind, "complete_set")

        let finished = try LiveWorkoutPayloadParser.finishResult(from: liveJSONData([
            "version": 1,
            "result": "finished",
            "roomId": liveRoomID,
            "status": "active",
            "roomRevision": 5,
            "progressRevision": 3,
            "membershipRevision": 3,
            "finishedAt": liveFinishedAt
        ]))
        XCTAssertEqual(finished.status, .active)

        let left = try LiveWorkoutPayloadParser.terminalResult(from: liveJSONData([
            "version": 1,
            "result": "left",
            "roomId": liveRoomID,
            "status": "cancelled",
            "roomRevision": 6,
            "membershipRevision": 4,
            "endedAt": liveFinishedAt
        ]), expectedResult: "left")
        XCTAssertEqual(left.result, "left")

        let closed: [String: Any] = [
            "version": 1,
            "result": "closed",
            "roomId": liveRoomID,
            "status": "expired",
            "roomRevision": 7,
            "endedAt": liveFinishedAt
        ]
        for parser in [
            LiveWorkoutPayloadParser.respondResult,
            LiveWorkoutPayloadParser.startResult,
            LiveWorkoutPayloadParser.applyResult,
            LiveWorkoutPayloadParser.finishResult
        ] as [(Data) throws -> Any] {
            XCTAssertThrowsError(try parser(liveJSONData(closed))) {
                XCTAssertEqual($0 as? LiveWorkoutGatewayError, .resourceUnavailable)
            }
        }

        var malformedClosed = closed
        malformedClosed["endedAt"] = NSNull()
        XCTAssertThrowsError(try LiveWorkoutPayloadParser.applyResult(from: liveJSONData(malformedClosed))) {
            XCTAssertEqual($0 as? LiveWorkoutContractError, .invalidResponse)
        }
    }

    func testRealtimeHintsAreBoundedExactInvalidationsOnly() throws {
        let participantFinished = try LiveWorkoutPayloadParser.realtimeHint(from: [
            "version": 1,
            "kind": "participant_finished",
            "roomId": liveRoomID,
            "roomRevision": 8
        ])
        XCTAssertEqual(participantFinished.kind, "participant_finished")

        let roomClosed = try LiveWorkoutPayloadParser.realtimeHint(from: [
            "version": 1,
            "kind": "room_closed",
            "roomId": liveRoomID,
            "roomRevision": 9
        ])
        XCTAssertEqual(roomClosed.kind, "room_closed")

        for staleAlias in ["finished", "closed"] {
            XCTAssertThrowsError(try LiveWorkoutPayloadParser.realtimeHint(from: [
                "version": 1,
                "kind": staleAlias,
                "roomId": liveRoomID,
                "roomRevision": 9
            ]))
        }

        XCTAssertThrowsError(try LiveWorkoutPayloadParser.realtimeHint(from: [
            "version": 1,
            "kind": "progress",
            "roomId": liveRoomID,
            "roomRevision": 9,
            "completedSets": []
        ]))
    }

    func testWorkoutObjectPreservesStaticPlanCompatibilityAndBounds() throws {
        let plan = SharedWorkoutPlan(exercises: [
            SharedWorkoutPlanExercise(
                catalogKey: "bench_press",
                name: "Bench Press",
                sets: [SharedWorkoutPlanSet(weight: 80, repetitions: 8)]
            )
        ])
        let value = try LiveWorkoutPayloadParser.workoutObject(for: plan)
        XCTAssertEqual(Set(value.keys), Set(["version", "exercises"]))

        let exercises = try XCTUnwrap(value["exercises"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(exercises.first).keys), Set(["catalogKey", "name", "sets"]))

        let oversized = Data(repeating: UInt8(ascii: " "), count: LiveWorkoutPayloadParser.maximumResponseBytes + 1)
        XCTAssertThrowsError(try LiveWorkoutPayloadParser.snapshot(from: oversized))
    }

    func testDirectEditorInviteConsumesOnlyAfterDurableRoomConfirmationWithoutAwaitingInbox() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-LiveDraftConsumptionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "LiveWorkoutDraftConsumptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let recorder = LiveGatewayActionRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveGatewayURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        defer {
            LiveGatewayURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let auth = AuthService(
            keychain: LiveWorkoutTestKeychain(),
            urlSession: urlSession,
            defaults: defaults
        )
        try auth.installSessionForTesting(.cloud(CloudAccountSession(
            userID: liveUserID,
            email: "draft-consumption@example.invalid",
            displayName: "Draft Consumption Tester",
            accessToken: try liveSyntheticJWT(sessionID: liveSessionID),
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        let storageKey = try XCTUnwrap(auth.session?.storageKey)
        let workoutStore = try WorkoutStore(accountStorageKey: storageKey, directoryURL: root)
        let activeWorkoutStore = ActiveWorkoutStore(
            accountStorageKey: storageKey,
            workoutStorageURL: workoutStore.storageURL
        )
        let coordinator = LiveWorkoutCoordinator(
            auth: auth,
            workoutStore: workoutStore,
            activeWorkoutStore: activeWorkoutStore,
            urlSession: urlSession
        )
        let recipientProfileID = "p_22222222222222222222222222222222"
        let request = LiveWorkoutDraftSendRequest(
            recipientProfileID: recipientProfileID,
            friendshipID: "f_33333333333333333333333333333333",
            friendshipRevision: 7,
            draftFingerprint: String(repeating: "a", count: 64)
        )
        let plan = SharedWorkoutPlan(exercises: [
            SharedWorkoutPlanExercise(
                catalogKey: "bench_press",
                name: "Bench Press",
                sets: [SharedWorkoutPlanSet(weight: 80, repetitions: 8)]
            )
        ])
        let sendCount = LiveGatewayCounter()
        LiveGatewayURLProtocolStub.handler = { request in
            let requestObject = try LiveGatewayURLProtocolStub.requestObject(request)
            let action = try XCTUnwrap(requestObject["action"] as? String)
            recorder.append(action)
            switch action {
            case "live_send_invite":
                let count = sendCount.increment()
                let result: [String: Any] = count == 1
                    ? [
                        "version": 1,
                        "result": "submitted_or_unavailable",
                        "roomId": NSNull(),
                        "status": NSNull(),
                        "roomRevision": NSNull()
                    ]
                    : [
                        "version": 1,
                        "result": "submitted",
                        "roomId": liveRoomID,
                        "status": "waiting",
                        "roomRevision": 1
                    ]
                return try LiveGatewayURLProtocolStub.response(
                    for: request,
                    jsonData: liveJSONData(["version": 1, "result": result])
                )
            case "live_inbox":
                // A confirmed send must return and publish its durable marker even when
                // the opportunistic post-confirmation refresh is cancelled or unavailable.
                throw URLError(.notConnectedToInternet)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        let unavailable = try await coordinator.sendInvite(
            to: recipientProfileID,
            plan: plan,
            draftRequest: request
        )
        XCTAssertFalse(unavailable)
        XCTAssertNil(coordinator.confirmedDraftConsumption)
        XCTAssertNil(coordinator.draftConsumptionStore.consumption)
        XCTAssertNil(activeWorkoutStore.liveSlotReservationStore.reservation)

        let confirmedRoom = try await coordinator.sendInvite(
            to: recipientProfileID,
            plan: plan,
            draftRequest: request
        )
        XCTAssertTrue(confirmedRoom)
        let confirmed = try XCTUnwrap(coordinator.confirmedDraftConsumption)
        XCTAssertEqual(confirmed.phase, .confirmed)
        XCTAssertEqual(confirmed.roomID, liveRoomID)
        XCTAssertEqual(confirmed.recipientProfileID, recipientProfileID)
        XCTAssertEqual(confirmed.friendshipID, request.friendshipID)
        XCTAssertEqual(confirmed.friendshipRevision, request.friendshipRevision)
        XCTAssertEqual(confirmed.draftFingerprint, request.draftFingerprint)
        XCTAssertEqual(
            activeWorkoutStore.liveSlotReservationStore.reservation?.operationID,
            confirmed.operationID
        )
        let reopened = LiveWorkoutDraftConsumptionStore(
            accountStorageKey: storageKey,
            workoutStorageURL: workoutStore.storageURL
        )
        XCTAssertEqual(reopened.consumption, confirmed)
        XCTAssertEqual(recorder.actions.filter { $0 == "live_send_invite" }.count, 2)

        coordinator.stopMonitoring()
        let restartedCoordinator = LiveWorkoutCoordinator(
            auth: auth,
            workoutStore: workoutStore,
            activeWorkoutStore: activeWorkoutStore,
            urlSession: urlSession
        )
        await restartedCoordinator.refreshAll(showErrors: false)
        XCTAssertEqual(restartedCoordinator.confirmedDraftConsumption, confirmed)

        try restartedCoordinator.acknowledgeConfirmedDraftConsumption(confirmed)
        XCTAssertNil(restartedCoordinator.confirmedDraftConsumption)
        XCTAssertNil(restartedCoordinator.draftConsumptionStore.consumption)
    }

    func testAcceptPreflightsFrozenAliasPairBeforeRespondMutation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-LiveAcceptPreflightTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "LiveWorkoutContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let recorder = LiveGatewayActionRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveGatewayURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        defer {
            LiveGatewayURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let auth = AuthService(
            keychain: LiveWorkoutTestKeychain(),
            urlSession: urlSession,
            defaults: defaults
        )
        try auth.installSessionForTesting(.cloud(CloudAccountSession(
            userID: liveUserID,
            email: "live@example.invalid",
            displayName: "Live Tester",
            accessToken: try liveSyntheticJWT(sessionID: liveSessionID),
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        let storageKey = try XCTUnwrap(auth.session?.storageKey)
        let workoutStore = try WorkoutStore(accountStorageKey: storageKey, directoryURL: root)
        let activeWorkoutStore = ActiveWorkoutStore(
            accountStorageKey: storageKey,
            workoutStorageURL: workoutStore.storageURL
        )
        let frozenObject = liveWaitingAliasSnapshotObject()
        LiveGatewayURLProtocolStub.handler = { request in
            let requestObject = try LiveGatewayURLProtocolStub.requestObject(request)
            let action = try XCTUnwrap(requestObject["action"] as? String)
            recorder.append(action)
            let result: [String: Any]
            switch action {
            case "live_snapshot":
                result = frozenObject
            case "live_respond_invite":
                result = [
                    "version": 1,
                    "result": "joined",
                    "roomId": liveRoomID,
                    "status": "ready",
                    "roomRevision": 2,
                    "membershipRevision": 2
                ]
            default:
                throw URLError(.unsupportedURL)
            }
            return try LiveGatewayURLProtocolStub.response(
                for: request,
                jsonData: liveJSONData(["version": 1, "result": result])
            )
        }
        let coordinator = LiveWorkoutCoordinator(
            auth: auth,
            workoutStore: workoutStore,
            activeWorkoutStore: activeWorkoutStore,
            urlSession: urlSession
        )
        let invitation = LiveWorkoutInvitation(
            roomID: liveRoomID,
            roomRevision: 1,
            createdAt: "2026-08-10T09:55:00Z",
            inviteExpiresAt: "2026-08-10T10:10:00Z",
            summary: LiveWorkoutSummary(
                exerciseCount: 2,
                setCount: 2,
                exerciseNames: ["Bench Press", "Жим штанги лежачи"]
            ),
            owner: LiveWorkoutProfile(
                profileID: "p_11111111111111111111111111111111",
                displayName: "Owner"
            )
        )

        do {
            _ = try await coordinator.respond(to: invitation, accept: true)
            XCTFail("A locally ambiguous frozen plan must remain waiting")
        } catch LiveWorkoutGatewayError.invalidRequest {
            // The local import boundary rejects the alias pair before membership changes.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(recorder.actions, ["live_snapshot"])
        XCTAssertFalse(recorder.actions.contains("live_respond_invite"))
        XCTAssertNil(activeWorkoutStore.draft)
        XCTAssertNil(coordinator.sidecar.attachment)
    }

    func testAcceptDryRunsCurrentCatalogBeforeRespondMutation() async throws {
        struct LegacyEnvelope: Encodable {
            let schemaVersion: Int
            let accountStorageKey: String
            let savedAt: Date
            let snapshot: WorkoutDataSnapshot
            let favoriteExerciseIDs: [UUID]
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-LiveCatalogPreflightTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "LiveWorkoutCatalogPreflightTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let recorder = LiveGatewayActionRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveGatewayURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        defer {
            LiveGatewayURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let auth = AuthService(
            keychain: LiveWorkoutTestKeychain(),
            urlSession: urlSession,
            defaults: defaults
        )
        try auth.installSessionForTesting(.cloud(CloudAccountSession(
            userID: liveUserID,
            email: "catalog@example.invalid",
            displayName: "Catalog Tester",
            accessToken: try liveSyntheticJWT(sessionID: liveSessionID),
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        let storageKey = try XCTUnwrap(auth.session?.storageKey)
        let placeholder = try WorkoutStore(accountStorageKey: storageKey, directoryURL: root)
        let first = Exercise(name: "Legacy  Custom")
        let second = Exercise(name: "Legacy Custom")
        let frozenName = "Legacy\u{2007}Custom"
        let envelope = LegacyEnvelope(
            schemaVersion: 2,
            accountStorageKey: storageKey,
            savedAt: Date(),
            snapshot: WorkoutDataSnapshot(exercises: [first, second]),
            favoriteExerciseIDs: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(envelope).write(to: placeholder.storageURL, options: .atomic)
        let workoutStore = try WorkoutStore(accountStorageKey: storageKey, directoryURL: root)
        let before = workoutStore.snapshot
        let activeWorkoutStore = ActiveWorkoutStore(
            accountStorageKey: storageKey,
            workoutStorageURL: workoutStore.storageURL
        )

        var frozenObject = liveWaitingAliasSnapshotObject()
        var room = try XCTUnwrap(frozenObject["room"] as? [String: Any])
        room["summary"] = [
            "exerciseCount": 1,
            "setCount": 1,
            "exerciseNames": [frozenName]
        ]
        frozenObject["room"] = room
        frozenObject["plan"] = [
            "version": 1,
            "exercises": [[
                "exerciseId": "e_01",
                "name": frozenName,
                "sets": [["setId": "s_01_01", "weight": 50, "reps": 8]]
            ]]
        ]
        LiveGatewayURLProtocolStub.handler = { request in
            let requestObject = try LiveGatewayURLProtocolStub.requestObject(request)
            let action = try XCTUnwrap(requestObject["action"] as? String)
            recorder.append(action)
            let result: [String: Any]
            if action == "live_snapshot" {
                result = frozenObject
            } else if action == "live_respond_invite" {
                result = [
                    "version": 1,
                    "result": "joined",
                    "roomId": liveRoomID,
                    "status": "ready",
                    "roomRevision": 2,
                    "membershipRevision": 2
                ]
            } else {
                throw URLError(.unsupportedURL)
            }
            return try LiveGatewayURLProtocolStub.response(
                for: request,
                jsonData: liveJSONData(["version": 1, "result": result])
            )
        }
        let coordinator = LiveWorkoutCoordinator(
            auth: auth,
            workoutStore: workoutStore,
            activeWorkoutStore: activeWorkoutStore,
            urlSession: urlSession
        )
        let invitation = LiveWorkoutInvitation(
            roomID: liveRoomID,
            roomRevision: 1,
            createdAt: "2026-08-10T09:55:00Z",
            inviteExpiresAt: "2026-08-10T10:10:00Z",
            summary: LiveWorkoutSummary(
                exerciseCount: 1,
                setCount: 1,
                exerciseNames: [frozenName]
            ),
            owner: LiveWorkoutProfile(
                profileID: "p_11111111111111111111111111111111",
                displayName: "Owner"
            )
        )

        do {
            _ = try await coordinator.respond(to: invitation, accept: true)
            XCTFail("Ambiguous local catalog must block membership mutation")
        } catch WorkoutStoreError.duplicateExerciseName {
            // The exact dry-run resolver found two current local matches.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(recorder.actions, ["live_snapshot"])
        XCTAssertFalse(recorder.actions.contains("live_respond_invite"))
        XCTAssertEqual(workoutStore.snapshot, before)
        XCTAssertNil(activeWorkoutStore.draft)
        XCTAssertNil(coordinator.sidecar.attachment)
    }

    func testConfirmedAcceptRefreshFailureRestoresWithoutReplayingMutation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-LiveConfirmedRestoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "LiveWorkoutConfirmedRestoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let recorder = LiveGatewayActionRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveGatewayURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        defer {
            LiveGatewayURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let auth = AuthService(
            keychain: LiveWorkoutTestKeychain(),
            urlSession: urlSession,
            defaults: defaults
        )
        try auth.installSessionForTesting(.cloud(CloudAccountSession(
            userID: liveUserID,
            email: "restore-after-accept@example.invalid",
            displayName: "Restore Tester",
            accessToken: try liveSyntheticJWT(sessionID: liveSessionID),
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        let storageKey = try XCTUnwrap(auth.session?.storageKey)
        let workoutStore = try WorkoutStore(accountStorageKey: storageKey, directoryURL: root)
        let activeWorkoutStore = ActiveWorkoutStore(
            accountStorageKey: storageKey,
            workoutStorageURL: workoutStore.storageURL
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let createdAt = formatter.string(from: Date().addingTimeInterval(-60))
        let expiresAt = formatter.string(from: Date().addingTimeInterval(15 * 60))
        var waiting = liveWaitingAliasSnapshotObject()
        var room = try XCTUnwrap(waiting["room"] as? [String: Any])
        room["createdAt"] = createdAt
        room["inviteExpiresAt"] = expiresAt
        room["summary"] = [
            "exerciseCount": 1,
            "setCount": 1,
            "exerciseNames": ["Bench Press"]
        ]
        waiting["room"] = room
        waiting["plan"] = [
            "version": 1,
            "exercises": [[
                "exerciseId": "e_01",
                "catalogKey": "bench_press",
                "name": "Bench Press",
                "sets": [["setId": "s_01_01", "weight": 80, "reps": 8]]
            ]]
        ]
        var participants = try XCTUnwrap(waiting["participants"] as? [[String: Any]])
        participants[0]["joinedAt"] = createdAt
        waiting["participants"] = participants

        LiveGatewayURLProtocolStub.handler = { request in
            let requestObject = try LiveGatewayURLProtocolStub.requestObject(request)
            let action = try XCTUnwrap(requestObject["action"] as? String)
            recorder.append(action)
            switch action {
            case "live_snapshot" where recorder.actions.filter({ $0 == action }).count == 1:
                return try LiveGatewayURLProtocolStub.response(
                    for: request,
                    jsonData: liveJSONData(["version": 1, "result": waiting])
                )
            case "live_respond_invite":
                return try LiveGatewayURLProtocolStub.response(
                    for: request,
                    jsonData: liveJSONData(["version": 1, "result": [
                        "version": 1,
                        "result": "joined",
                        "roomId": liveRoomID,
                        "status": "active",
                        "roomRevision": 2,
                        "membershipRevision": 2
                    ]])
                )
            default:
                return try LiveGatewayURLProtocolStub.response(
                    for: request,
                    statusCode: 503,
                    jsonData: liveJSONData(["error": "synthetic_refresh_failure"])
                )
            }
        }
        let coordinator = LiveWorkoutCoordinator(
            auth: auth,
            workoutStore: workoutStore,
            activeWorkoutStore: activeWorkoutStore,
            urlSession: urlSession
        )
        let invitation = LiveWorkoutInvitation(
            roomID: liveRoomID,
            roomRevision: 1,
            createdAt: createdAt,
            inviteExpiresAt: expiresAt,
            summary: LiveWorkoutSummary(
                exerciseCount: 1,
                setCount: 1,
                exerciseNames: ["Bench Press"]
            ),
            owner: LiveWorkoutProfile(
                profileID: "p_11111111111111111111111111111111",
                displayName: "Owner"
            )
        )

        let outcome = try await coordinator.respond(to: invitation, accept: true)

        XCTAssertEqual(outcome, .confirmedRestoring)
        XCTAssertTrue(coordinator.isRestoring(roomID: liveRoomID))
        XCTAssertNil(coordinator.lastError)
        XCTAssertNil(activeWorkoutStore.draft)
        XCTAssertNotNil(activeWorkoutStore.liveSlotReservationStore.reservation)
        XCTAssertEqual(recorder.actions.filter { $0 == "live_respond_invite" }.count, 1)

        do {
            _ = try await coordinator.respond(to: invitation, accept: true)
            XCTFail("A confirmed mutation must not be replayed with a new operation ID")
        } catch LiveWorkoutGatewayError.invalidRequest {
            // The restoring state owns the slot until authoritative reconciliation.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(recorder.actions.filter { $0 == "live_respond_invite" }.count, 1)
    }

    func testActiveSnapshotMaterializesAuthoritativeProgressAndServerStart() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-LiveProgressRestoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "LiveWorkoutProgressRestoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveGatewayURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        defer {
            LiveGatewayURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let auth = AuthService(
            keychain: LiveWorkoutTestKeychain(),
            urlSession: urlSession,
            defaults: defaults
        )
        try auth.installSessionForTesting(.cloud(CloudAccountSession(
            userID: liveUserID,
            email: "restore@example.invalid",
            displayName: "Restore Tester",
            accessToken: try liveSyntheticJWT(sessionID: liveSessionID),
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        let storageKey = try XCTUnwrap(auth.session?.storageKey)
        let workoutStore = try WorkoutStore(accountStorageKey: storageKey, directoryURL: root)
        let reservationURL = LiveWorkoutSlotReservationStore.storageURL(
            forWorkoutStorageURL: workoutStore.storageURL
        )
        XCTAssertEqual(
            reservationURL.deletingLastPathComponent().standardizedFileURL,
            root.standardizedFileURL
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: reservationURL.path))
        let activeWorkoutStore = ActiveWorkoutStore(
            accountStorageKey: storageKey,
            workoutStorageURL: workoutStore.storageURL
        )
        XCTAssertNil(activeWorkoutStore.liveSlotReservationStore.reservation)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let referenceNow = Date()
        let createdAt = dateFormatter.string(from: referenceNow.addingTimeInterval(-15 * 60))
        let startedAt = dateFormatter.string(from: referenceNow.addingTimeInterval(-10 * 60))
        let completedAt = dateFormatter.string(from: referenceNow.addingTimeInterval(-5 * 60))
        let activeExpiresAt = dateFormatter.string(from: referenceNow.addingTimeInterval(6 * 60 * 60))
        var object = liveSnapshotObject()
        var room = try XCTUnwrap(object["room"] as? [String: Any])
        room["createdAt"] = createdAt
        room["inviteExpiresAt"] = startedAt
        room["startedAt"] = startedAt
        room["activeExpiresAt"] = activeExpiresAt
        object["room"] = room
        var participants = try XCTUnwrap(object["participants"] as? [[String: Any]])
        participants[0]["joinedAt"] = createdAt
        participants[0]["progress"] = [
            "version": 1,
            "revision": 2,
            "completedSets": [[
                "setId": "s_01_01",
                "weight": 82.5,
                "reps": 7,
                "completedAt": completedAt
            ]],
            "undoableSetId": "s_01_01",
            "finishedAt": NSNull()
        ]
        object["participants"] = participants
        LiveGatewayURLProtocolStub.handler = { request in
            let requestObject = try LiveGatewayURLProtocolStub.requestObject(request)
            XCTAssertEqual(requestObject["action"] as? String, "live_snapshot")
            return try LiveGatewayURLProtocolStub.response(
                for: request,
                jsonData: liveJSONData(["version": 1, "result": object])
            )
        }
        let coordinator = LiveWorkoutCoordinator(
            auth: auth,
            workoutStore: workoutStore,
            activeWorkoutStore: activeWorkoutStore,
            urlSession: urlSession
        )

        try await coordinator.openRoom(liveRoomID)

        let draft = try XCTUnwrap(activeWorkoutStore.draft)
        XCTAssertEqual(
            draft.startedAt,
            try LiveWorkoutPayloadParser.validatedDate(from: startedAt)
        )
        XCTAssertEqual(draft.workoutDate, draft.startedAt)
        let sets = try XCTUnwrap(draft.exercises.first?.sets)
        XCTAssertEqual(sets[0].weight, 82.5)
        XCTAssertEqual(sets[0].reps, 7)
        XCTAssertEqual(
            sets[0].completedAt,
            try LiveWorkoutPayloadParser.validatedDate(from: completedAt)
        )
        XCTAssertEqual(draft.undoableSetID, sets[0].id)
        XCTAssertNil(sets[1].completedAt)
        XCTAssertEqual(sets[1].weight, 80)
        XCTAssertEqual(sets[1].reps, 8)
        XCTAssertEqual(coordinator.sidecar.attachment?.progressRevision, 2)
        XCTAssertEqual(
            coordinator.sidecar.attachment?.serverToLocalSetIDs["s_01_01"],
            sets[0].id
        )

        let completedWorkout = try activeWorkoutStore.finish(
            draftID: draft.id,
            expectedRevision: draft.revision,
            into: workoutStore
        )
        try await coordinator.openRoom(liveRoomID)
        XCTAssertEqual(
            coordinator.sidecar.attachment?.pendingOperations.map(\.kind),
            [.finish]
        )

        coordinator.stopMonitoring()
        let replacementSessionID = "33333333-3333-4333-8333-333333333333"
        try auth.installSessionForTesting(.cloud(CloudAccountSession(
            userID: liveUserID,
            email: "restore@example.invalid",
            displayName: "Restore Tester",
            accessToken: try liveSyntheticJWT(sessionID: replacementSessionID),
            refreshToken: "replacement-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        let inboxObject: [String: Any] = [
            "version": 1,
            "invitations": [],
            "rooms": [[
                "roomId": liveRoomID,
                "status": "active",
                "roomRevision": 3,
                "role": "owner",
                "memberState": "joined",
                "membershipRevision": 1,
                "createdAt": createdAt,
                "startedAt": startedAt,
                "activeExpiresAt": activeExpiresAt,
                "summary": [
                    "exerciseCount": 1,
                    "setCount": 2,
                    "exerciseNames": ["Bench Press"]
                ],
                "peer": [
                    "profileId": "p_22222222222222222222222222222222",
                    "displayName": "Friend"
                ]
            ]]
        ]
        LiveGatewayURLProtocolStub.handler = { request in
            let requestObject = try LiveGatewayURLProtocolStub.requestObject(request)
            switch requestObject["action"] as? String {
            case "live_inbox":
                return try LiveGatewayURLProtocolStub.response(
                    for: request,
                    jsonData: liveJSONData(["version": 1, "result": inboxObject])
                )
            case "live_snapshot":
                return try LiveGatewayURLProtocolStub.response(
                    for: request,
                    jsonData: liveJSONData(["version": 1, "result": object])
                )
            case "live_finish":
                throw URLError(.notConnectedToInternet)
            default:
                throw URLError(.unsupportedURL)
            }
        }

        await coordinator.refreshAll()

        XCTAssertEqual(coordinator.sidecar.attachment?.sessionID, replacementSessionID)
        XCTAssertEqual(coordinator.sidecar.attachment?.pendingOperations.map(\.kind), [.finish])
        XCTAssertNil(activeWorkoutStore.draft)
        XCTAssertEqual(workoutStore.workout(id: draft.id), completedWorkout)
        coordinator.stopMonitoring()

        LiveGatewayURLProtocolStub.handler = { request in
            try LiveGatewayURLProtocolStub.response(
                for: request,
                statusCode: 404,
                jsonData: liveJSONData(["error": "not_found"])
            )
        }
        do {
            try await coordinator.openRoom(liveRoomID)
            XCTFail("An inaccessible attached room must fail closed")
        } catch LiveWorkoutGatewayError.resourceUnavailable {
            // The local draft stays standalone while the stale binding is removed.
        }
        XCTAssertNil(coordinator.sidecar.attachment)
        XCTAssertNil(activeWorkoutStore.draft)
        XCTAssertEqual(workoutStore.workout(id: draft.id), completedWorkout)

        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reservationURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}

@MainActor
final class LiveWorkoutSidecarStoreTests: XCTestCase {
    func testAttachmentMapsCanonicalSetsAndDurablyReplaysQueueWithoutToken() throws {
        let fixture = try makeFixture()
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL
        )

        let attachment = try store.attach(
            snapshot: fixture.snapshot,
            draft: fixture.draft,
            context: liveContext
        )
        XCTAssertEqual(attachment.serverToLocalSetIDs["s_01_01"], fixture.firstSetID)
        XCTAssertEqual(attachment.serverToLocalSetIDs["s_01_02"], fixture.secondSetID)

        try store.enqueueCompletedSet(localSetID: fixture.firstSetID, weight: 82.5, reps: 7)
        try store.enqueueUndo(localSetID: fixture.firstSetID)
        XCTAssertEqual(store.attachment?.pendingOperations.map(\.expectedProgressRevision), [1, 2])
        XCTAssertEqual(store.attachment?.pendingOperations.map(\.kind), [.completeSet, .undoSet])

        let persisted = try Data(contentsOf: store.storageURL)
        let persistedText = try XCTUnwrap(String(data: persisted, encoding: .utf8))
        XCTAssertFalse(persistedText.contains(liveContext.accessToken))

        let reopened = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL
        )
        XCTAssertEqual(reopened.attachment, store.attachment)

        let firstOperationID = try XCTUnwrap(reopened.attachment?.pendingOperations.first?.clientOperationID)
        try reopened.acknowledge(operationID: firstOperationID, progressRevision: 2, roomRevision: 4)
        XCTAssertEqual(reopened.attachment?.progressRevision, 2)
        XCTAssertEqual(reopened.attachment?.pendingOperations.map(\.expectedProgressRevision), [2])
    }

    func testSameUserSessionChangePreservesThenAuthoritativelyRebindsQueue() throws {
        let fixture = try makeFixture()
        let storageKey = "cloud-\(liveUserID)"
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: storageKey,
            workoutStorageURL: fixture.workoutStorageURL
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        try store.enqueueCompletedSet(localSetID: fixture.firstSetID, weight: 80, reps: 8)

        let differentSession = LiveWorkoutSessionContext(
            userID: liveUserID,
            sessionID: "33333333-3333-4333-8333-333333333333",
            accessToken: "replacement-token"
        )
        XCTAssertThrowsError(try store.bind(to: differentSession)) {
            XCTAssertEqual($0 as? LiveWorkoutSidecarError, .sessionMismatch)
        }
        let preserved = try XCTUnwrap(store.attachment)
        XCTAssertEqual(preserved.sessionID, liveSessionID)
        XCTAssertEqual(preserved.pendingOperations.count, 1)

        let afterSessionChange = LiveWorkoutSidecarStore(
            accountStorageKey: storageKey,
            workoutStorageURL: fixture.workoutStorageURL
        )
        XCTAssertEqual(afterSessionChange.attachment, preserved)

        let authoritative = try liveSnapshotWithSelfProgress(
            revision: 2,
            completed: [[
                "setId": "s_01_01", "weight": 80, "reps": 8,
                "completedAt": liveCompletedAt
            ]],
            undoable: "s_01_01"
        )
        try afterSessionChange.reconcileAfterSessionChange(
            snapshot: authoritative,
            draft: fixture.draft,
            context: differentSession
        )
        XCTAssertEqual(afterSessionChange.attachment?.sessionID, differentSession.sessionID)
        XCTAssertEqual(afterSessionChange.attachment?.progressRevision, 2)
        XCTAssertEqual(afterSessionChange.attachment?.pendingOperations, [])
        XCTAssertNoThrow(try afterSessionChange.bind(to: differentSession))
    }

    func testSameUserSessionChangeRebindsExactCommittedHistoryWithPendingFinish() throws {
        let fixture = try makeFixture()
        let storageKey = "cloud-\(liveUserID)"
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: storageKey,
            workoutStorageURL: fixture.workoutStorageURL
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        try store.enqueueCompletedSet(
            localSetID: fixture.firstSetID,
            weight: 80,
            reps: 8
        )
        try store.enqueueFinish()
        let before = try XCTUnwrap(store.attachment)
        XCTAssertEqual(before.pendingOperations.map(\.kind), [.completeSet, .finish])

        let committed = WorkoutSession(
            id: fixture.draft.id,
            date: fixture.draft.workoutDate,
            exercises: [
                WorkoutExercise(
                    id: fixture.draft.exercises[0].id,
                    exerciseID: fixture.draft.exercises[0].exerciseID,
                    sets: [WorkoutSet(id: fixture.firstSetID, weight: 80, reps: 8)]
                )
            ]
        )
        let replacement = LiveWorkoutSessionContext(
            userID: liveUserID,
            sessionID: "33333333-3333-4333-8333-333333333333",
            accessToken: "replacement-token"
        )

        try store.reconcileAfterSessionChange(
            snapshot: fixture.snapshot,
            committedWorkout: committed,
            context: replacement
        )

        XCTAssertEqual(store.attachment?.sessionID, replacement.sessionID)
        XCTAssertEqual(store.attachment?.pendingOperations.map(\.kind), [.completeSet, .finish])
        XCTAssertNoThrow(try store.bind(to: replacement))

        let mismatchedStore = LiveWorkoutSidecarStore(
            accountStorageKey: storageKey,
            workoutStorageURL: fixture.workoutStorageURL
        )
        let wrongHistory = WorkoutSession(
            id: committed.id,
            date: committed.date,
            exercises: [
                WorkoutExercise(
                    id: committed.exercises[0].id,
                    exerciseID: committed.exercises[0].exerciseID,
                    sets: [WorkoutSet(id: fixture.firstSetID, weight: 81, reps: 8)]
                )
            ]
        )
        let anotherSession = LiveWorkoutSessionContext(
            userID: liveUserID,
            sessionID: "44444444-4444-4444-8444-444444444444",
            accessToken: "another-token"
        )
        XCTAssertThrowsError(try mismatchedStore.reconcileAfterSessionChange(
            snapshot: fixture.snapshot,
            committedWorkout: wrongHistory,
            context: anotherSession
        ))
        XCTAssertEqual(mismatchedStore.attachment?.sessionID, replacement.sessionID)
    }

    func testWrongAccountBindDoesNotDeleteAnotherOwnersLiveQueue() throws {
        let fixture = try makeFixture()
        let storageKey = "cloud-\(liveUserID)"
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: storageKey,
            workoutStorageURL: fixture.workoutStorageURL
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        try store.enqueueCompletedSet(localSetID: fixture.firstSetID, weight: 80, reps: 8)
        let preserved = try XCTUnwrap(store.attachment)

        let differentAccount = LiveWorkoutSessionContext(
            userID: "44444444-4444-4444-8444-444444444444",
            sessionID: liveSessionID,
            accessToken: "replacement-token"
        )
        XCTAssertThrowsError(try store.bind(to: differentAccount)) {
            XCTAssertEqual($0 as? LiveWorkoutSidecarError, .accountMismatch)
        }
        XCTAssertEqual(store.attachment, preserved)

        let reopened = LiveWorkoutSidecarStore(
            accountStorageKey: storageKey,
            workoutStorageURL: fixture.workoutStorageURL
        )
        XCTAssertEqual(reopened.attachment, preserved)
    }

    func testFailedPersistenceDoesNotPublishAttachmentOrQueuedMutation() throws {
        let fixture = try makeFixture()
        var failWrites = false
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL,
            envelopeWriter: { data, url in
                if failWrites { throw SyntheticLiveSidecarWriteError() }
                try data.write(to: url, options: .atomic)
            }
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)

        failWrites = true
        XCTAssertThrowsError(
            try store.enqueueCompletedSet(localSetID: fixture.firstSetID, weight: 80, reps: 8)
        ) {
            XCTAssertEqual($0 as? LiveWorkoutSidecarError, .storageUnavailable)
        }
        XCTAssertEqual(store.attachment?.pendingOperations, [])
    }

    func testAttachmentRejectsChangedFrozenPlanWithoutPartialState() throws {
        let fixture = try makeFixture(firstWeight: 81)
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL
        )

        XCTAssertThrowsError(
            try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        ) {
            XCTAssertEqual($0 as? LiveWorkoutSidecarError, .invalidState)
        }
        XCTAssertNil(store.attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.storageURL.path))
    }

    func testDuplicateKeySidecarIsNeverReplayed() throws {
        let fixture = try makeFixture()
        let storageKey = "cloud-\(liveUserID)"
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: storageKey,
            workoutStorageURL: fixture.workoutStorageURL
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        let original = try Data(contentsOf: store.storageURL)
        var text = try XCTUnwrap(String(data: original, encoding: .utf8))
        text = text.replacingOccurrences(
            of: "\"schemaVersion\":1",
            with: "\"schemaVersion\":1,\"schemaVersion\":1"
        )
        XCTAssertNotEqual(Data(text.utf8), original)
        try Data(text.utf8).write(to: store.storageURL, options: .atomic)

        let reopened = LiveWorkoutSidecarStore(
            accountStorageKey: storageKey,
            workoutStorageURL: fixture.workoutStorageURL
        )
        XCTAssertNil(reopened.attachment)
        XCTAssertNotNil(reopened.recoveryMessage)
        XCTAssertThrowsError(try reopened.bind(to: liveContext)) {
            XCTAssertEqual($0 as? LiveWorkoutSidecarError, .storageUnavailable)
        }
    }

    func testAttachmentNeverTrustsUnknownWireCatalogKeyForLocalIdentity() throws {
        let fixture = try makeFixture()
        var object = liveSnapshotObject()
        var plan = try XCTUnwrap(object["plan"] as? [String: Any])
        var exercises = try XCTUnwrap(plan["exercises"] as? [[String: Any]])
        exercises[0]["catalogKey"] = "future_machine_v2"
        exercises[0]["name"] = "Custom Future Machine"
        plan["exercises"] = exercises
        object["plan"] = plan
        var room = try XCTUnwrap(object["room"] as? [String: Any])
        var summary = try XCTUnwrap(room["summary"] as? [String: Any])
        summary["exerciseNames"] = ["Custom Future Machine"]
        room["summary"] = summary
        object["room"] = room
        let snapshot = try LiveWorkoutPayloadParser.snapshot(from: liveJSONData(object))
        let draft = ActiveWorkoutDraft(
            id: fixture.draft.id,
            startedAt: fixture.draft.startedAt,
            workoutDate: fixture.draft.workoutDate,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: fixture.draft.exercises[0].exerciseID,
                    exerciseName: "Custom Future Machine",
                    exerciseCatalogKey: nil,
                    sets: fixture.draft.exercises[0].sets
                )
            ]
        )
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL
        )

        XCTAssertNoThrow(try store.attach(snapshot: snapshot, draft: draft, context: liveContext))
        XCTAssertEqual(store.attachment?.serverToLocalSetIDs.count, 2)
    }

    func testSaveAllQueuePublishesWholeBatchOrNothing() throws {
        let fixture = try makeFixture()
        var failWrites = false
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL,
            envelopeWriter: { data, url in
                if failWrites { throw SyntheticLiveSidecarWriteError() }
                try data.write(to: url, options: .atomic)
            }
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        let batch = [
            (id: fixture.firstSetID, weight: 80.0, reps: 8),
            (id: fixture.secondSetID, weight: 82.5, reps: 7)
        ]
        XCTAssertNoThrow(try store.preflightCompletedSets(batch))

        failWrites = true
        XCTAssertThrowsError(try store.enqueueCompletedSets(batch)) {
            XCTAssertEqual($0 as? LiveWorkoutSidecarError, .storageUnavailable)
        }
        XCTAssertEqual(store.attachment?.pendingOperations, [])
    }

    func testConflictReconcileDropsOnlyProvenAppliedPrefix() throws {
        let fixture = try makeFixture()
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        try store.enqueueCompletedSets([
            (id: fixture.firstSetID, weight: 80, reps: 8),
            (id: fixture.secondSetID, weight: 82.5, reps: 7)
        ])
        let originalSecond = try XCTUnwrap(store.attachment?.pendingOperations.last)
        let snapshot = try liveSnapshotWithSelfProgress(
            revision: 2,
            completed: [[
                "setId": "s_01_01", "weight": 80, "reps": 8,
                "completedAt": liveCompletedAt
            ]],
            undoable: "s_01_01"
        )

        let result = try LiveWorkoutSidecarStore.reconcile(
            attachment: try XCTUnwrap(store.attachment),
            snapshot: snapshot
        )
        guard case .reconciled(let reconciled) = result else {
            return XCTFail("Expected a safely reconciled queue")
        }
        XCTAssertEqual(reconciled.progressRevision, 2)
        XCTAssertEqual(reconciled.pendingOperations.count, 1)
        XCTAssertEqual(reconciled.pendingOperations[0].serverSetID, "s_01_02")
        XCTAssertEqual(reconciled.pendingOperations[0].expectedProgressRevision, 2)
        XCTAssertEqual(reconciled.pendingOperations[0].clientOperationID, originalSecond.clientOperationID)
    }

    func testConflictReconcileRejectsDifferentRemoteValuesAndImpossibleUndo() throws {
        let fixture = try makeFixture()
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        try store.enqueueCompletedSet(localSetID: fixture.firstSetID, weight: 80, reps: 8)
        let wrongValue = try liveSnapshotWithSelfProgress(
            revision: 2,
            completed: [[
                "setId": "s_01_01", "weight": 120, "reps": 8,
                "completedAt": liveCompletedAt
            ]],
            undoable: "s_01_01"
        )
        XCTAssertEqual(
            try LiveWorkoutSidecarStore.reconcile(
                attachment: try XCTUnwrap(store.attachment),
                snapshot: wrongValue
            ),
            .unsafe
        )

        let undoStore = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL
                .deletingLastPathComponent()
                .appendingPathComponent("undo-workout.json")
        )
        try undoStore.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        try undoStore.enqueueUndo(localSetID: fixture.firstSetID)
        XCTAssertEqual(
            try LiveWorkoutSidecarStore.reconcile(
                attachment: try XCTUnwrap(undoStore.attachment),
                snapshot: fixture.snapshot
            ),
            .unsafe
        )
    }

    func testLocalBatchRecoveryQueuesPlanOrderedSuffixAtomically() throws {
        let fixture = try makeFixture()
        let store = LiveWorkoutSidecarStore(
            accountStorageKey: "cloud-\(liveUserID)",
            workoutStorageURL: fixture.workoutStorageURL
        )
        try store.attach(snapshot: fixture.snapshot, draft: fixture.draft, context: liveContext)
        let completedAt = try LiveWorkoutPayloadParser.validatedDate(from: liveCompletedAt)
        var recovered = fixture.draft
        recovered.exercises[0].sets[0].completedAt = completedAt
        recovered.exercises[0].sets[1].weight = 82.5
        recovered.exercises[0].sets[1].reps = 7
        recovered.exercises[0].sets[1].completedAt = completedAt
        recovered.lastModifiedAt = completedAt

        XCTAssertTrue(try store.recoverLocalDraft(from: fixture.snapshot, draft: recovered))
        XCTAssertEqual(
            store.attachment?.pendingOperations.map(\.serverSetID),
            ["s_01_01", "s_01_02"]
        )
        XCTAssertEqual(store.attachment?.pendingOperations.map(\.expectedProgressRevision), [1, 2])
    }

    private func makeFixture(firstWeight: Double = 80) throws -> LiveSidecarFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-LiveSidecarTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let snapshot = try LiveWorkoutPayloadParser.snapshot(from: liveJSONData(liveSnapshotObject()))
        let firstSetID = UUID()
        let secondSetID = UUID()
        let startedAt = try LiveWorkoutPayloadParser.validatedDate(from: liveStartedAt)
        let draft = ActiveWorkoutDraft(
            id: UUID(),
            startedAt: startedAt,
            workoutDate: startedAt,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: UUID(),
                    exerciseName: "Bench Press",
                    exerciseCatalogKey: "bench_press",
                    sets: [
                        ActiveWorkoutSet(id: firstSetID, weight: firstWeight, reps: 8),
                        ActiveWorkoutSet(id: secondSetID, weight: 80, reps: 8)
                    ]
                )
            ]
        )
        return LiveSidecarFixture(
            workoutStorageURL: root.appendingPathComponent("workout.json"),
            snapshot: snapshot,
            draft: draft,
            firstSetID: firstSetID,
            secondSetID: secondSetID
        )
    }
}

private struct LiveSidecarFixture {
    let workoutStorageURL: URL
    let snapshot: LiveWorkoutSnapshot
    let draft: ActiveWorkoutDraft
    let firstSetID: UUID
    let secondSetID: UUID
}

private struct SyntheticLiveSidecarWriteError: Error {}

private let liveRoomID = "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
private let liveUserID = "11111111-1111-4111-8111-111111111111"
private let liveSessionID = "22222222-2222-4222-8222-222222222222"
private let liveStartedAt = "2026-08-10T10:00:00Z"
private let liveActiveExpiresAt = "2026-08-11T10:00:00Z"
private let liveCompletedAt = "2026-08-10T10:05:00Z"
private let liveFinishedAt = "2026-08-10T11:00:00Z"

private let liveContext = LiveWorkoutSessionContext(
    userID: liveUserID,
    sessionID: liveSessionID,
    accessToken: "synthetic-live-secret-token"
)

private func liveSnapshotObject() -> [String: Any] {
    [
        "version": 1,
        "room": [
            "roomId": liveRoomID,
            "status": "active",
            "roomRevision": 3,
            "closeReason": NSNull(),
            "createdAt": "2026-08-10T09:55:00Z",
            "inviteExpiresAt": "2026-08-10T10:10:00Z",
            "startedAt": liveStartedAt,
            "activeExpiresAt": liveActiveExpiresAt,
            "endedAt": NSNull(),
            "summary": [
                "exerciseCount": 1,
                "setCount": 2,
                "exerciseNames": ["Bench Press"]
            ]
        ],
        "plan": [
            "version": 1,
            "exercises": [[
                "exerciseId": "e_01",
                "catalogKey": "bench_press",
                "name": "Bench Press",
                "sets": [
                    ["setId": "s_01_01", "weight": 80, "reps": 8],
                    ["setId": "s_01_02", "weight": 80, "reps": 8]
                ]
            ]]
        ],
        "participants": [
            [
                "isSelf": true,
                "profile": [
                    "profileId": "p_11111111111111111111111111111111",
                    "displayName": "Owner"
                ],
                "role": "owner",
                "state": "joined",
                "membershipRevision": 1,
                "joinedAt": "2026-08-10T09:55:00Z",
                "finishedAt": NSNull(),
                "departedAt": NSNull(),
                "progress": [
                    "version": 1,
                    "revision": 1,
                    "completedSets": [],
                    "undoableSetId": NSNull(),
                    "finishedAt": NSNull()
                ]
            ],
            [
                "isSelf": false,
                "profile": [
                    "profileId": "p_22222222222222222222222222222222",
                    "displayName": "Friend"
                ],
                "role": "participant",
                "state": "joined",
                "membershipRevision": 2,
                "joinedAt": "2026-08-10T09:59:00Z",
                "finishedAt": NSNull(),
                "departedAt": NSNull(),
                "progress": [
                    "version": 1,
                    "revision": 2,
                    "completedSets": [[
                        "setId": "s_01_01",
                        "weight": 82.5,
                        "reps": 7,
                        "completedAt": liveCompletedAt
                    ]],
                    "undoableSetId": "s_01_01",
                    "finishedAt": NSNull()
                ]
            ]
        ]
    ]
}

private func liveSnapshotWithSelfProgress(
    revision: Int,
    completed: [[String: Any]],
    undoable: String?,
    finishedAt: String? = nil
) throws -> LiveWorkoutSnapshot {
    var object = liveSnapshotObject()
    var participants = try XCTUnwrap(object["participants"] as? [[String: Any]])
    participants[0]["state"] = finishedAt == nil ? "joined" : "finished"
    participants[0]["finishedAt"] = finishedAt.map { $0 as Any } ?? NSNull()
    participants[0]["progress"] = [
        "version": 1,
        "revision": revision,
        "completedSets": completed,
        "undoableSetId": undoable.map { $0 as Any } ?? NSNull(),
        "finishedAt": finishedAt.map { $0 as Any } ?? NSNull()
    ]
    object["participants"] = participants
    return try LiveWorkoutPayloadParser.snapshot(from: liveJSONData(object))
}

private func liveWaitingAliasSnapshotObject() -> [String: Any] {
    [
        "version": 1,
        "room": [
            "roomId": liveRoomID,
            "status": "waiting",
            "roomRevision": 1,
            "closeReason": NSNull(),
            "createdAt": "2026-08-10T09:55:00Z",
            "inviteExpiresAt": "2026-08-10T10:10:00Z",
            "startedAt": NSNull(),
            "activeExpiresAt": NSNull(),
            "endedAt": NSNull(),
            "summary": [
                "exerciseCount": 2,
                "setCount": 2,
                "exerciseNames": ["Bench Press", "Жим штанги лежачи"]
            ]
        ],
        "plan": [
            "version": 1,
            "exercises": [
                [
                    "exerciseId": "e_01",
                    "catalogKey": "bench_press",
                    "name": "Bench Press",
                    "sets": [["setId": "s_01_01", "weight": 80, "reps": 8]]
                ],
                [
                    "exerciseId": "e_02",
                    "name": "Жим штанги лежачи",
                    "sets": [["setId": "s_02_01", "weight": 70, "reps": 10]]
                ]
            ]
        ],
        "participants": [
            [
                "isSelf": false,
                "profile": [
                    "profileId": "p_11111111111111111111111111111111",
                    "displayName": "Owner"
                ],
                "role": "owner",
                "state": "joined",
                "membershipRevision": 1,
                "joinedAt": "2026-08-10T09:55:00Z",
                "finishedAt": NSNull(),
                "departedAt": NSNull(),
                "progress": NSNull()
            ],
            [
                "isSelf": true,
                "profile": [
                    "profileId": "p_22222222222222222222222222222222",
                    "displayName": "Friend"
                ],
                "role": "participant",
                "state": "invited",
                "membershipRevision": 1,
                "joinedAt": NSNull(),
                "finishedAt": NSNull(),
                "departedAt": NSNull(),
                "progress": NSNull()
            ]
        ]
    ]
}

private func liveSyntheticJWT(sessionID: String) throws -> String {
    let payload = try liveJSONData(["session_id": sessionID])
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "e30.\(encoded).x"
}

private func liveJSONData(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

private final class LiveWorkoutTestKeychain: KeychainStoring {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        lock.withLock { values[account] = data }
    }

    func read(account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func delete(account: String) throws {
        lock.withLock { _ = values.removeValue(forKey: account) }
    }
}

private final class LiveGatewayActionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var actions: [String] { lock.withLock { stored } }

    func append(_ action: String) {
        lock.withLock { stored.append(action) }
    }
}

private final class LiveGatewayCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private final class LiveGatewayURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "owrcbsrectdgaotndtxy.supabase.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func requestObject(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
                if count == 0 { break }
                collected.append(buffer, count: count)
            }
            data = collected
        } else {
            throw URLError(.cannotDecodeContentData)
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        jsonData: Data
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        return (response, jsonData)
    }
}
