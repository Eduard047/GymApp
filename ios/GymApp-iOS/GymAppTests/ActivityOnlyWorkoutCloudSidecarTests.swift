import Foundation
import XCTest
@testable import GymApp

@MainActor
final class ActivityOnlyWorkoutCloudSidecarTests: XCTestCase {
    func testBoundedNoteCountsUnicodeScalarsInsteadOfGraphemeClusters() {
        let combiningPair = "e\u{0301}"
        let exactly512Scalars = String(repeating: combiningPair, count: 256)
        let scalars513 = exactly512Scalars + "\u{0301}"

        XCTAssertEqual(exactly512Scalars.unicodeScalars.count, 512)
        XCTAssertEqual(scalars513.unicodeScalars.count, 513)
        XCTAssertEqual(exactly512Scalars.count, 256)
        XCTAssertEqual(scalars513.count, 256)
        XCTAssertLessThanOrEqual(exactly512Scalars.utf8.count, 2_048)
        XCTAssertLessThanOrEqual(scalars513.utf8.count, 2_048)
        XCTAssertEqual(
            ActivityOnlyWorkoutCloudCodec.boundedNote(exactly512Scalars),
            exactly512Scalars
        )
        XCTAssertNil(ActivityOnlyWorkoutCloudCodec.boundedNote(scalars513))
    }

    func testSharedGoldenThreeWayMergeScenariosAndExactOptionalWireValues() throws {
        let data = try Data(contentsOf: sharedActivityOnlyFixtureURL())
        let fixture = try JSONDecoder().decode(
            ActivityOnlySyncGoldenFixture.self,
            from: data
        )
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.identityField, "workoutStartedAt")
        XCTAssertEqual(fixture.maximumItems, ActivityOnlyWorkoutCloudCodec.maximumItemCount)
        XCTAssertTrue(fixture.wireContract.absentOptionalFieldsAreDistinctFromZero)
        XCTAssertEqual(
            fixture.wireContract.noteMaximumUnicodeCodePoints,
            ActivityOnlyWorkoutCloudCodec.maximumNoteCharacters
        )
        XCTAssertEqual(
            fixture.wireContract.noteMaximumUtf8Bytes,
            ActivityOnlyWorkoutCloudCodec.maximumNoteBytes
        )

        for scenario in fixture.mergeScenarios {
            let base = try scenario.base.map { try XCTUnwrap(fixture.items[$0]) }
            let local = try scenario.local.map { try XCTUnwrap(fixture.items[$0]) }
            let remote = try scenario.remote.map { try XCTUnwrap(fixture.items[$0]) }
            if scenario.conflict == true {
                XCTAssertThrowsError(
                    try ActivityOnlyWorkoutCloudCodec.reconciledItems(
                        base: base,
                        remote: remote,
                        local: local,
                        coreWorkoutTimestamps: []
                    ),
                    scenario.name
                )
            } else {
                let expected = try XCTUnwrap(scenario.result).map {
                    try XCTUnwrap(fixture.items[$0])
                }
                let merged = try ActivityOnlyWorkoutCloudCodec.reconciledItems(
                    base: base,
                    remote: remote,
                    local: local,
                    coreWorkoutTimestamps: []
                )
                XCTAssertEqual(merged.outbound, expected, scenario.name)
            }
        }

        let absent = try XCTUnwrap(fixture.items["cExact"])
        let explicitZero = try XCTUnwrap(fixture.items["cZero"])
        XCTAssertNil(absent.garminCalories)
        XCTAssertEqual(explicitZero.garminCalories, 0)
        XCTAssertNotEqual(absent, explicitZero)
    }

    func testExactOwnerBoundBaselineUsesProtectedAccountEnvelopeAndIsBackwardCompatible() throws {
        let directory = try temporaryDirectory(named: "baseline-store")
        let storageKey = "cloud-baseline-owner"
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let otherOwnerID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let store = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        XCTAssertNil(store.loadActivityOnlyCloudBaseline(ownerUserID: ownerID))

        let exact = try item(
            timestamp: 1_750_000_000_000,
            duration: 1_234,
            gymCalories: 87.125,
            garminCalories: nil,
            averageHeartRate: 0,
            maximumHeartRate: 0,
            endingHeartRateZone: 0,
            note: "Exact baseline"
        )
        let baseline = try ActivityOnlyWorkoutCloudBaseline(
            ownerUserID: ownerID,
            items: [exact]
        )
        try store.saveActivityOnlyCloudBaseline(baseline)
        XCTAssertEqual(
            store.loadActivityOnlyCloudBaseline(ownerUserID: ownerID),
            baseline
        )
        XCTAssertNil(store.loadActivityOnlyCloudBaseline(ownerUserID: otherOwnerID))
        XCTAssertEqual(
            try store.storageURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup,
            true
        )

        let reopened = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        XCTAssertEqual(
            reopened.loadActivityOnlyCloudBaseline(ownerUserID: ownerID),
            baseline
        )
        try reopened.clearActivityOnlyCloudSyncArtifacts()
        XCTAssertNil(reopened.loadActivityOnlyCloudBaseline(ownerUserID: ownerID))
    }

    func testProtectedEnvelopeAcceptsMissingLegacyFieldsAndRejectsMalformedPrivateSyncState() throws {
        let directory = try temporaryDirectory(named: "baseline-envelope-compatibility")
        let storageKey = "cloud-envelope-compatibility"
        let store = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        _ = try store.createActivityWorkout(
            date: Date(gymEpochMilliseconds: 1_750_000_000_000),
            note: "legacy envelope",
            durationSeconds: 600
        )

        let legacyData = try Data(contentsOf: store.storageURL)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: legacyData) as? [String: Any]
        )
        XCTAssertNil(legacyObject["pendingActivityOnlyCloudSync"])
        XCTAssertNil(legacyObject["activityOnlyCloudBaseline"])
        let reopenedLegacy = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        XCTAssertFalse(reopenedLegacy.hasActivityOnlyCloudSyncArtifacts)

        legacyObject["activityOnlyCloudBaseline"] = [
            "version": 1,
            "ownerUserID": "not-a-uuid",
            "items": []
        ]
        try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
            .write(to: store.storageURL, options: .atomic)
        XCTAssertThrowsError(try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )) { error in
            guard case WorkoutStoreError.corruptStore = error else {
                return XCTFail("Expected corruptStore, got \(error)")
            }
        }
    }

    func testExactBaselineRejectsOverBoundWireWithoutReplacingProtectedState() throws {
        let directory = try temporaryDirectory(named: "baseline-envelope-bound")
        let storageKey = "cloud-envelope-bound"
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let store = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        let sentinel = try ActivityOnlyWorkoutCloudBaseline(
            ownerUserID: ownerID,
            items: [try item(
                timestamp: 1_750_000_000_000,
                duration: 600,
                gymCalories: 30,
                note: "sentinel"
            )]
        )
        try store.saveActivityOnlyCloudBaseline(sentinel)

        let maximumByteNote = String(repeating: "😀", count: 512)
        XCTAssertEqual(maximumByteNote.unicodeScalars.count, 512)
        XCTAssertEqual(maximumByteNote.utf8.count, 2_048)
        let overBoundItems = try (0 ..< 600).map { offset in
            try item(
                timestamp: 1_760_000_000_000 + Int64(offset),
                duration: 600,
                gymCalories: 30,
                note: maximumByteNote
            )
        }
        XCTAssertThrowsError(try ActivityOnlyWorkoutCloudBaseline(
            ownerUserID: ownerID,
            items: overBoundItems
        ))

        XCTAssertEqual(store.loadActivityOnlyCloudBaseline(ownerUserID: ownerID), sentinel)
        let reopened = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        XCTAssertEqual(reopened.loadActivityOnlyCloudBaseline(ownerUserID: ownerID), sentinel)
    }

    func testCodecAcceptsNormativeSnapshotAndRejectsOutOfContractValues() throws {
        let valid: [String: Any] = [
            "version": 1,
            "revision": 9,
            "items": [[
                "workoutStartedAt": 1_750_000_000_123 as Int64,
                "durationSeconds": 1_234,
                "gymCalories": 87.125,
                "garminCalories": 95,
                "averageHeartRate": 120,
                "maximumHeartRate": 150,
                "endingHeartRateZone": 3,
                "note": "Free workout"
            ]]
        ]
        let snapshot = try ActivityOnlyWorkoutCloudCodec.parseReadResponse(
            try JSONSerialization.data(withJSONObject: valid, options: [.sortedKeys])
        )
        XCTAssertEqual(snapshot.revision, 9)
        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items[0].gymCalories, 87.125)
        XCTAssertEqual(snapshot.items[0].maximumHeartRate, 150)

        var unknownItem = try XCTUnwrap(valid["items"] as? [[String: Any]])[0]
        unknownItem["unexpected"] = true
        XCTAssertThrowsError(try parseRead(items: [unknownItem]))

        var fractionalInteger = unknownItem
        fractionalInteger.removeValue(forKey: "unexpected")
        fractionalInteger["durationSeconds"] = 1.5
        XCTAssertThrowsError(try parseRead(items: [fractionalInteger]))

        var excessivePrecision = fractionalInteger
        excessivePrecision["durationSeconds"] = 1_234
        excessivePrecision["gymCalories"] = 87.0001
        XCTAssertThrowsError(try parseRead(items: [excessivePrecision]))

        var invertedHeartRate = excessivePrecision
        invertedHeartRate["gymCalories"] = 87.125
        invertedHeartRate["averageHeartRate"] = 151
        XCTAssertThrowsError(try parseRead(items: [invertedHeartRate]))

        let rateLimit601 = Data(
            #"{"version":1,"status":"rate_limited","retryAfter":601}"#.utf8
        )
        XCTAssertThrowsError(
            try ActivityOnlyWorkoutCloudCodec.parseSyncResponse(rateLimit601)
        )
        let rateLimit600 = Data(
            #"{"version":1,"status":"rate_limited","retryAfter":600}"#.utf8
        )
        XCTAssertEqual(
            try ActivityOnlyWorkoutCloudCodec.parseSyncResponse(rateLimit600),
            .rateLimited(retryAfter: 600)
        )
    }

    func testReconciliationPreservesCoreCollisionAndExactMetricsAcrossReopen() throws {
        let directory = try temporaryDirectory(named: "merge")
        let storageKey = "activity-sidecar-owner"
        let store = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        let coreDate = Date(gymEpochMilliseconds: 1_750_000_000_000)
        _ = try store.createWorkout(
            date: coreDate,
            namedSets: [
                NamedWorkoutSetDraft(
                    exerciseName: "Core Exercise",
                    weight: 80,
                    reps: 8
                )
            ],
            durationSeconds: 900
        )
        let shadowedByCore = try item(
            timestamp: coreDate.gymEpochMilliseconds,
            duration: 600,
            gymCalories: 45.25,
            note: "Remote activity at core timestamp"
        )
        let remoteOnly = try item(
            timestamp: 1_750_000_100_000,
            duration: 1_234,
            gymCalories: 87.125,
            garminCalories: 95,
            averageHeartRate: 120,
            maximumHeartRate: 150,
            endingHeartRateZone: 3,
            note: "Remote free workout"
        )
        let remote = [shadowedByCore, remoteOnly]
        let reconciled = try ActivityOnlyWorkoutCloudCodec.reconciledItems(
            base: [],
            remote: remote,
            local: [],
            coreWorkoutTimestamps: [coreDate.gymEpochMilliseconds]
        )

        XCTAssertEqual(reconciled.outbound, remote)
        XCTAssertEqual(reconciled.materialize, [remoteOnly])
        XCTAssertEqual(
            try store.applyActivityOnlyCloudItems(
                reconciled.outbound,
                expectedLocalItems: []
            ),
            1
        )
        XCTAssertEqual(store.workouts.filter { !$0.exercises.isEmpty }.count, 1)
        XCTAssertEqual(store.workouts.filter(\.exercises.isEmpty).count, 1)
        XCTAssertEqual(try store.activityOnlyCloudSnapshotItems(), remote)

        let reopened = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        XCTAssertEqual(try reopened.activityOnlyCloudSnapshotItems(), remote)
        XCTAssertEqual(reopened.workouts.filter { !$0.exercises.isEmpty }.count, 1)
        XCTAssertEqual(reopened.workouts.filter(\.exercises.isEmpty).count, 1)

        let ownerID = "11111111-2222-4333-8444-555555555555"
        let cloudData = try reopened.exportCloudBackupData(
            owner: BackupOwner(
                accountID: ownerID,
                userID: ownerID,
                email: "owner@example.com",
                remote: true
            )
        )
        let cloudBackup = try JSONDecoder().decode(GymBackup.self, from: cloudData)
        XCTAssertEqual(cloudBackup.sessions.count, 1)
        XCTAssertFalse((cloudBackup.sessions[0].exercises ?? []).isEmpty)

        let durationItems = try AppState.workoutDurationSyncItems(reopened.workouts)
        XCTAssertEqual(durationItems.count, 1)
        XCTAssertEqual(
            durationItems[0]["workoutStartedAt"] as? Int64,
            coreDate.gymEpochMilliseconds
        )
    }

    func testSameTimestampDifferentWireMetricFailsClosed() throws {
        let local = try item(
            timestamp: 1_750_000_000_000,
            duration: 600,
            gymCalories: 45.25,
            maximumHeartRate: 150,
            note: "Same visible workout"
        )
        let remote = try item(
            timestamp: local.workoutStartedAt,
            duration: local.durationSeconds,
            gymCalories: local.gymCalories,
            maximumHeartRate: 151,
            note: local.note
        )
        XCTAssertThrowsError(
            try ActivityOnlyWorkoutCloudCodec.reconciledItems(
                base: [],
                remote: [remote],
                local: [local],
                coreWorkoutTimestamps: []
            )
        )
    }

    func testThreeWayApplyPropagatesRemoteEditAndDeletionAtomicallyAcrossReopen() throws {
        let directory = try temporaryDirectory(named: "three-way-apply")
        let storageKey = "activity-three-way-owner"
        let timestamp: Int64 = 1_750_000_000_000
        let base = try item(
            timestamp: timestamp,
            duration: 600,
            gymCalories: 45.125,
            note: "base"
        )
        let remoteEdit = try item(
            timestamp: timestamp,
            duration: 720,
            gymCalories: 47.375,
            garminCalories: nil,
            averageHeartRate: 0,
            maximumHeartRate: 0,
            endingHeartRateZone: 0,
            note: "remote edit"
        )
        let store = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        _ = try store.createActivityWorkout(
            date: Date(gymEpochMilliseconds: timestamp),
            note: base.note,
            durationSeconds: base.durationSeconds
        )
        try store.setActivityOnlyCloudItems([base])
        let local = try store.activityOnlyCloudSnapshotItems()
        let edited = try ActivityOnlyWorkoutCloudCodec.reconciledItems(
            base: [base],
            remote: [remoteEdit],
            local: local,
            coreWorkoutTimestamps: []
        )
        XCTAssertEqual(
            try store.applyActivityOnlyCloudItems(
                edited.outbound,
                expectedLocalItems: local
            ),
            1
        )
        XCTAssertEqual(try store.activityOnlyCloudSnapshotItems(), [remoteEdit])
        XCTAssertEqual(store.workouts.count, 1)
        XCTAssertEqual(store.workouts.first?.durationSeconds, remoteEdit.durationSeconds)
        XCTAssertEqual(store.workouts.first?.note, remoteEdit.note)

        let reopened = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        XCTAssertEqual(try reopened.activityOnlyCloudSnapshotItems(), [remoteEdit])
        let beforeDeletion = try reopened.activityOnlyCloudSnapshotItems()
        let deleted = try ActivityOnlyWorkoutCloudCodec.reconciledItems(
            base: [remoteEdit],
            remote: [],
            local: beforeDeletion,
            coreWorkoutTimestamps: []
        )
        XCTAssertEqual(
            try reopened.applyActivityOnlyCloudItems(
                deleted.outbound,
                expectedLocalItems: beforeDeletion
            ),
            1
        )
        XCTAssertTrue(reopened.workouts.isEmpty)
        XCTAssertEqual(try reopened.activityOnlyCloudSnapshotItems(), [])
    }

    func testNoteOnlyEditPreservesExactCachedMetricsAndNilVersusZeroAcrossReopen() throws {
        let directory = try temporaryDirectory(named: "note-edit-exact-wire")
        let storageKey = "activity-note-edit-owner"
        let timestamp: Int64 = 1_750_000_000_000
        let exact = try item(
            timestamp: timestamp,
            duration: 900,
            gymCalories: 45.125,
            garminCalories: nil,
            averageHeartRate: 0,
            maximumHeartRate: 0,
            endingHeartRateZone: 0,
            note: "original note"
        )
        let store = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        let workout = try store.createActivityWorkout(
            date: Date(gymEpochMilliseconds: timestamp),
            note: exact.note,
            durationSeconds: exact.durationSeconds
        )
        try store.setActivityOnlyCloudItems([exact])
        try store.updateWorkout(
            id: workout.id,
            date: workout.date,
            note: "locally edited note"
        )

        let edited = try XCTUnwrap(store.activityOnlyCloudSnapshotItems().first)
        XCTAssertEqual(edited.note, "locally edited note")
        XCTAssertEqual(edited.durationSeconds, exact.durationSeconds)
        XCTAssertEqual(edited.gymCalories, 45.125)
        XCTAssertNil(edited.garminCalories)
        XCTAssertEqual(edited.averageHeartRate, 0)
        XCTAssertEqual(edited.maximumHeartRate, 0)
        XCTAssertEqual(edited.endingHeartRateZone, 0)

        let reopened = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        XCTAssertEqual(try reopened.activityOnlyCloudSnapshotItems(), [edited])
    }

    func testPendingTupleIsOwnerBoundAndExactTransientReplayUsesSameBody() async throws {
        let directory = try temporaryDirectory(named: "exact-replay")
        let storageKey = "cloud-activity-owner"
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let otherOwnerID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let requestID = UUID(uuidString: "01234567-89ab-4cde-8fab-0123456789ab")!
        let items = [try item(
            timestamp: 1_750_000_000_000,
            duration: 1_234,
            gymCalories: 87.125,
            garminCalories: 95,
            averageHeartRate: 120,
            maximumHeartRate: 150,
            endingHeartRateZone: 3,
            note: "Exact replay"
        )]
        let pending = try PendingActivityOnlyWorkoutCloudSync(
            ownerUserID: ownerID,
            requestID: requestID,
            expectedRevision: 7,
            items: items
        )
        XCTAssertTrue(AppState.activityOnlyOutcomeRequiresExactReplay(
            CloudSyncError.postgRESTFailure(
                statusCode: 503,
                code: "55P03",
                message: "lock timeout"
            )
        ))
        XCTAssertTrue(AppState.activityOnlyOutcomeRequiresExactReplay(
            CloudSyncError.postgRESTFailure(
                statusCode: 503,
                code: "57014",
                message: "statement timeout"
            )
        ))
        XCTAssertTrue(AppState.activityOnlyOutcomeRequiresExactReplay(
            URLError(.networkConnectionLost)
        ))
        XCTAssertFalse(AppState.activityOnlyOutcomeRequiresExactReplay(
            CloudSyncError.postgRESTFailure(
                statusCode: 409,
                code: "23505",
                message: "known failure"
            )
        ))
        let store = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        try store.savePendingActivityOnlyCloudSync(pending)
        XCTAssertEqual(
            store.loadPendingActivityOnlyCloudSync(ownerUserID: ownerID),
            pending
        )
        XCTAssertNil(store.loadPendingActivityOnlyCloudSync(ownerUserID: otherOwnerID))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivitySidecarURLProtocol.self]
        let auth = AuthService(
            keychain: ActivitySidecarKeychainStore(),
            urlSession: URLSession(configuration: configuration),
            defaults: temporaryDefaults(named: "exact-replay-auth")
        )
        let cloud = CloudAccountSession(
            userID: ownerID,
            email: "owner@example.com",
            displayName: "Owner",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        try auth.installSessionForTesting(AppAccountSession.cloud(cloud))
        let service = CloudSyncService(
            auth: auth,
            urlSession: URLSession(configuration: configuration)
        )
        var requestBodies: [Data] = []
        var attempts = 0
        ActivitySidecarURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.path,
                "/rest/v1/rpc/garmin_sync_activity_only_workouts"
            )
            requestBodies.append(try XCTUnwrap(request.httpBody))
            attempts += 1
            if attempts == 1 {
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    statusCode: 503,
                    json: #"{"code":"55P03","message":"lock timeout"}"#
                )
            }
            return try ActivitySidecarURLProtocol.response(
                for: request,
                json: #"{"version":1,"status":"synced","revision":8,"syncedCount":1,"changedCount":1,"replayed":true}"#
            )
        }
        defer { ActivitySidecarURLProtocol.handler = nil }

        do {
            _ = try await service.syncActivityOnlyWorkouts(
                expectedRevision: pending.expectedRevision,
                requestID: try XCTUnwrap(pending.requestUUID),
                items: pending.items,
                exactRequestBody: pending.requestBody,
                expectedUserID: ownerID
            )
            XCTFail("The transient SQLSTATE must remain outcome-unknown")
        } catch CloudSyncError.postgRESTFailure(_, let code, _) {
            XCTAssertEqual(code, "55P03")
        }
        let exactReplay = try XCTUnwrap(
            store.loadPendingActivityOnlyCloudSync(ownerUserID: ownerID)
        )
        let result = try await service.syncActivityOnlyWorkouts(
            expectedRevision: exactReplay.expectedRevision,
            requestID: try XCTUnwrap(exactReplay.requestUUID),
            items: exactReplay.items,
            exactRequestBody: exactReplay.requestBody,
            expectedUserID: ownerID
        )

        XCTAssertEqual(
            result,
            ActivityOnlyWorkoutCloudSyncResult.synced(
                revision: 8,
                syncedCount: 1,
                changedCount: 1,
                replayed: true
            )
        )
        XCTAssertEqual(requestBodies.count, 2)
        XCTAssertEqual(exactReplay.requestBody, pending.requestBody)
        XCTAssertEqual(requestBodies[0], requestBodies[1])
        XCTAssertEqual(requestBodies[0], pending.requestBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: requestBodies[0]) as? [String: Any]
        )
        XCTAssertEqual(body["p_expected_revision"] as? Int64, 7)
        XCTAssertEqual(body["p_request_id"] as? String, requestID.uuidString.lowercased())
        XCTAssertEqual((body["p_items"] as? [[String: Any]])?.count, 1)
    }

    func testAppStateReplaysExactPendingBodyAndKeepsActivityOutOfCoreAndSocial() async throws {
        let directory = try temporaryDirectory(named: "app-state-replay")
        let defaults = temporaryDefaults(named: "app-state-replay")
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let cloud = CloudAccountSession(
            userID: ownerID,
            email: "owner@example.com",
            displayName: "Owner",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let accountSession = AppAccountSession.cloud(cloud)
        let localStore = try WorkoutStore(
            accountStorageKey: accountSession.storageKey,
            directoryURL: directory
        )
        _ = try localStore.seedBuiltInExercises()
        _ = try localStore.seedDefaultMuscleMappings()
        _ = try localStore.createActivityWorkout(
            date: Date(gymEpochMilliseconds: 1_750_000_000_000),
            note: "AppState exact replay activity",
            durationSeconds: 1_234
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivitySidecarURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: ActivitySidecarKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        var activitySyncBodies: [Data] = []
        var coreStateBodies: [Data] = []
        var durationBodies: [Data] = []
        var activityRevision: Int64 = 0
        var remoteItems: [[String: Any]] = []
        ActivitySidecarURLProtocol.handler = { request in
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                return try ActivitySidecarURLProtocol.response(for: request, json: "[]")
            case ("/rest/v1/rpc/garmin_read_activity_only_workouts", "POST"):
                let data = try JSONSerialization.data(withJSONObject: [
                    "version": 1,
                    "revision": activityRevision,
                    "items": remoteItems
                ], options: [.sortedKeys])
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    json: try XCTUnwrap(String(data: data, encoding: .utf8))
                )
            case ("/rest/v1/rpc/garmin_sync_activity_only_workouts", "POST"):
                let bodyData = try XCTUnwrap(request.httpBody)
                activitySyncBodies.append(bodyData)
                if activitySyncBodies.count == 1 {
                    return try ActivitySidecarURLProtocol.response(
                        for: request,
                        statusCode: 503,
                        json: #"{"code":"55P03","message":"lock timeout"}"#
                    )
                }
                let body = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                )
                remoteItems = try XCTUnwrap(body["p_items"] as? [[String: Any]])
                activityRevision = 1
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    json: #"{"version":1,"status":"synced","revision":1,"syncedCount":1,"changedCount":1,"replayed":true}"#
                )
            case ("/rest/v1/user_states", "POST"), ("/rest/v1/user_states", "PATCH"):
                coreStateBodies.append(try XCTUnwrap(request.httpBody))
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    json: #"[{"updated_at":"2026-08-24T12:00:00.000000Z"}]"#
                )
            case ("/rest/v1/profiles", "POST"):
                return try ActivitySidecarURLProtocol.response(for: request, json: "{}")
            case ("/rest/v1/rpc/social_sync_workout_durations", "POST"):
                durationBodies.append(try XCTUnwrap(request.httpBody))
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    json: #"{"version":2,"syncedCount":0,"changedCount":0}"#
                )
            default:
                XCTFail(
                    "Unexpected AppState activity request: \(request.httpMethod ?? "nil") " +
                        "\(request.url?.absoluteString ?? "nil")"
                )
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        defer {
            ActivitySidecarURLProtocol.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(
                keychain: ActivitySidecarKeychainStore()
            )
        )
        try auth.installSessionForTesting(accountSession)
        let ready = await waitUntil { appState.isAccountReady }

        XCTAssertTrue(ready)
        XCTAssertEqual(activitySyncBodies.count, 2)
        XCTAssertEqual(activitySyncBodies[0], activitySyncBodies[1])
        XCTAssertEqual(remoteItems.count, 1)
        XCTAssertEqual(coreStateBodies.count, 1)
        XCTAssertEqual(durationBodies.count, 1)
        XCTAssertNil(appState.workoutStore.loadPendingActivityOnlyCloudSync(
            ownerUserID: ownerID
        ))
        XCTAssertNil(defaults.object(
            forKey: LegacyPendingActivityOnlyWorkoutCloudSyncPreferences.keyPrefix +
                accountSession.storageKey
        ))

        let coreRequest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(coreStateBodies.first))
                as? [[String: Any]]
        )
        let coreState = try XCTUnwrap(coreRequest.first?["state"] as? [String: Any])
        XCTAssertTrue((coreState["sessions"] as? [[String: Any]])?.isEmpty == true)
        let durationRequest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(durationBodies.first))
                as? [String: Any]
        )
        XCTAssertTrue((durationRequest["p_items"] as? [[String: Any]])?.isEmpty == true)
    }

    func testStaleManualSyncReplaysPendingBeforeCoreLoadAndFinishesSidecarInOnePress() async throws {
        let directory = try temporaryDirectory(named: "manual-stale-order")
        let defaults = temporaryDefaults(named: "manual-stale-order")
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let cloud = CloudAccountSession(
            userID: ownerID,
            email: "owner@example.com",
            displayName: "Owner",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: ownerID,
            userID: ownerID,
            email: cloud.email,
            remote: true
        )
        let localStore = try WorkoutStore(
            accountStorageKey: accountSession.storageKey,
            directoryURL: directory
        )
        let timestamp: Int64 = 1_750_000_000_000
        _ = try localStore.createActivityWorkout(
            date: Date(gymEpochMilliseconds: timestamp),
            note: "manual stale activity",
            durationSeconds: 1_234
        )
        let localItems = try localStore.activityOnlyCloudSnapshotItems()
        let pending = try PendingActivityOnlyWorkoutCloudSync(
            ownerUserID: ownerID,
            requestID: UUID(uuidString: "01234567-89ab-4cde-8fab-0123456789ab")!,
            expectedRevision: 0,
            items: localItems
        )
        try localStore.savePendingActivityOnlyCloudSync(pending)
        let remoteCore = try localStore.exportCloudBackupData(owner: owner)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivitySidecarURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: ActivitySidecarKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        try auth.installSessionForTesting(accountSession)
        var events: [String] = []
        var coreLoads = 0
        var remoteItems: [[String: Any]] = []
        ActivitySidecarURLProtocol.handler = { request in
            switch request.url?.path {
            case "/rest/v1/rpc/garmin_sync_activity_only_workouts":
                events.append("sidecar-sync")
                let body = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody))
                        as? [String: Any]
                )
                remoteItems = try XCTUnwrap(body["p_items"] as? [[String: Any]])
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    json: #"{"version":1,"status":"synced","revision":1,"syncedCount":1,"changedCount":1,"replayed":true}"#
                )
            case "/rest/v1/rpc/garmin_read_activity_only_workouts":
                events.append("sidecar-read")
                let data = try JSONSerialization.data(withJSONObject: [
                    "version": 1,
                    "revision": 1,
                    "items": remoteItems
                ], options: [.sortedKeys])
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    json: try XCTUnwrap(String(data: data, encoding: .utf8))
                )
            default:
                XCTFail("Unexpected stale manual sync request: \(request.url?.path ?? "nil")")
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        defer {
            ActivitySidecarURLProtocol.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, ownerID)
                coreLoads += 1
                events.append("core-load-\(coreLoads)")
                if coreLoads == 1 { throw URLError(.notConnectedToInternet) }
                return remoteCore
            },
            garminBindingStore: GarminDeviceBindingStore(
                keychain: ActivitySidecarKeychainStore()
            )
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        events.removeAll()

        await appState.forceCloudSync()

        XCTAssertEqual(events, ["sidecar-sync", "core-load-2", "sidecar-read"])
        XCTAssertEqual(remoteItems.count, 1)
        XCTAssertEqual(appState.workoutStore.workouts.filter(\.exercises.isEmpty).count, 1)
        XCTAssertNil(appState.workoutStore.loadPendingActivityOnlyCloudSync(
            ownerUserID: ownerID
        ))
        XCTAssertEqual(
            appState.workoutStore.loadActivityOnlyCloudBaseline(
                ownerUserID: ownerID
            )?.items,
            localItems
        )
    }

    func testMissingRPCIsSafeUnavailableWithoutFallback() async throws {
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivitySidecarURLProtocol.self]
        let auth = AuthService(
            keychain: ActivitySidecarKeychainStore(),
            urlSession: URLSession(configuration: configuration),
            defaults: temporaryDefaults(named: "missing-rpc-auth")
        )
        try auth.installSessionForTesting(AppAccountSession.cloud(CloudAccountSession(
            userID: ownerID,
            email: "owner@example.com",
            displayName: "Owner",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        let service = CloudSyncService(
            auth: auth,
            urlSession: URLSession(configuration: configuration)
        )
        ActivitySidecarURLProtocol.handler = { request in
            try ActivitySidecarURLProtocol.response(
                for: request,
                statusCode: 404,
                json: #"{"code":"PGRST202","message":"function not found"}"#
            )
        }
        defer { ActivitySidecarURLProtocol.handler = nil }

        let result = try await service.loadActivityOnlyWorkouts(expectedUserID: ownerID)
        XCTAssertEqual(result, ActivityOnlyWorkoutCloudReadResult.unavailable)
    }

    func testAppStateMissingRPCKeepsLocalActivityPendingWithoutFallback() async throws {
        let directory = try temporaryDirectory(named: "app-state-missing-rpc")
        let defaults = temporaryDefaults(named: "app-state-missing-rpc")
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let cloud = CloudAccountSession(
            userID: ownerID,
            email: "owner@example.com",
            displayName: "Owner",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let accountSession = AppAccountSession.cloud(cloud)
        let localStore = try WorkoutStore(
            accountStorageKey: accountSession.storageKey,
            directoryURL: directory
        )
        _ = try localStore.seedBuiltInExercises()
        _ = try localStore.seedDefaultMuscleMappings()
        _ = try localStore.createActivityWorkout(
            date: Date(gymEpochMilliseconds: 1_750_000_000_000),
            note: "Local activity while RPC is unavailable",
            durationSeconds: 1_234
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivitySidecarURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: ActivitySidecarKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        var coreStateBody: Data?
        var durationBody: Data?
        ActivitySidecarURLProtocol.handler = { request in
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                return try ActivitySidecarURLProtocol.response(for: request, json: "[]")
            case ("/rest/v1/rpc/garmin_read_activity_only_workouts", "POST"):
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    statusCode: 404,
                    json: #"{"code":"PGRST202","message":"function unavailable"}"#
                )
            case ("/rest/v1/rpc/garmin_sync_activity_only_workouts", "POST"):
                XCTFail("A missing READ RPC must not fall through to the SYNC RPC.")
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    statusCode: 404,
                    json: #"{"code":"PGRST202","message":"function unavailable"}"#
                )
            case ("/rest/v1/user_states", "POST"):
                coreStateBody = try XCTUnwrap(request.httpBody)
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    json: #"[{"updated_at":"2026-08-24T12:00:00.000000Z"}]"#
                )
            case ("/rest/v1/profiles", "POST"):
                return try ActivitySidecarURLProtocol.response(for: request, json: "{}")
            case ("/rest/v1/rpc/social_sync_workout_durations", "POST"):
                durationBody = try XCTUnwrap(request.httpBody)
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    json: #"{"version":2,"syncedCount":0,"changedCount":0}"#
                )
            default:
                XCTFail(
                    "Unexpected missing-RPC request: \(request.httpMethod ?? "nil") " +
                        "\(request.url?.absoluteString ?? "nil")"
                )
                return try ActivitySidecarURLProtocol.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        defer {
            ActivitySidecarURLProtocol.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(
                keychain: ActivitySidecarKeychainStore()
            )
        )
        try auth.installSessionForTesting(accountSession)
        let ready = await waitUntil { appState.isAccountReady }

        XCTAssertTrue(ready)
        XCTAssertEqual(appState.workoutStore.workouts.filter(\.exercises.isEmpty).count, 1)
        XCTAssertEqual(appState.cloudSyncStatus, .pending)
        let coreRequest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(coreStateBody))
                as? [[String: Any]]
        )
        let coreState = try XCTUnwrap(coreRequest.first?["state"] as? [String: Any])
        XCTAssertTrue((coreState["sessions"] as? [[String: Any]])?.isEmpty == true)
        let durationRequest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(durationBody))
                as? [String: Any]
        )
        XCTAssertTrue((durationRequest["p_items"] as? [[String: Any]])?.isEmpty == true)
    }

    func testStartupDeletionRemovesProtectedAndLegacyActivitySyncArtifactsBeforeMarker() throws {
        let directory = try temporaryDirectory(named: "startup-delete-artifacts")
        let defaults = temporaryDefaults(named: "startup-delete-artifacts")
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let storageKey = "cloud_\(ownerID)"
        let store = try WorkoutStore(
            accountStorageKey: storageKey,
            directoryURL: directory
        )
        let exact = try item(
            timestamp: 1_750_000_000_000,
            duration: 600,
            gymCalories: 30,
            note: "private startup payload"
        )
        let pending = try PendingActivityOnlyWorkoutCloudSync(
            ownerUserID: ownerID,
            expectedRevision: 0,
            items: [exact]
        )
        let baseline = try ActivityOnlyWorkoutCloudBaseline(
            ownerUserID: ownerID,
            items: [exact]
        )
        try store.savePendingActivityOnlyCloudSync(pending)
        try store.saveActivityOnlyCloudBaseline(baseline)
        defaults.set(
            try JSONEncoder().encode(pending),
            forKey: LegacyPendingActivityOnlyWorkoutCloudSyncPreferences.keyPrefix + storageKey
        )
        defaults.set(
            try JSONEncoder().encode(baseline),
            forKey: LegacyActivityOnlyWorkoutCloudBaselinePreferences.keyPrefix + storageKey
        )
        defaults.set(
            Data("checkpoint".utf8),
            forKey: "gymapp.cloud-sync-checkpoint.v1.\(storageKey)"
        )
        defaults.set(storageKey, forKey: "gymapp.pending-account-deletion-storage-key")

        let auth = AuthService(
            keychain: ActivitySidecarKeychainStore(),
            defaults: defaults
        )
        _ = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            garminBindingStore: GarminDeviceBindingStore(
                keychain: ActivitySidecarKeychainStore()
            )
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.storageURL.path))
        XCTAssertNil(defaults.object(
            forKey: LegacyPendingActivityOnlyWorkoutCloudSyncPreferences.keyPrefix + storageKey
        ))
        XCTAssertNil(defaults.object(
            forKey: LegacyActivityOnlyWorkoutCloudBaselinePreferences.keyPrefix + storageKey
        ))
        XCTAssertNil(defaults.object(
            forKey: "gymapp.cloud-sync-checkpoint.v1.\(storageKey)"
        ))
        XCTAssertNil(defaults.object(forKey: "gymapp.pending-account-deletion-storage-key"))
    }

    func testImmediateDeletionReadBackClearsProtectedActivitySyncArtifactsBeforeMarker() async throws {
        let directory = try temporaryDirectory(named: "immediate-delete-artifacts")
        let defaults = temporaryDefaults(named: "immediate-delete-artifacts")
        let ownerID = "11111111-2222-4333-8444-555555555555"
        let session = AppAccountSession.local(id: ownerID, displayName: "Owner")
        let auth = AuthService(
            keychain: ActivitySidecarKeychainStore(),
            defaults: defaults
        )
        try auth.installSessionForTesting(session)
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            garminBindingStore: GarminDeviceBindingStore(
                keychain: ActivitySidecarKeychainStore()
            )
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let storageKey = session.storageKey
        let targetURL = appState.workoutStore.storageURL
        let exact = try item(
            timestamp: 1_750_000_000_000,
            duration: 600,
            gymCalories: 30,
            note: "private immediate payload"
        )
        let pending = try PendingActivityOnlyWorkoutCloudSync(
            ownerUserID: ownerID,
            expectedRevision: 0,
            items: [exact]
        )
        let baseline = try ActivityOnlyWorkoutCloudBaseline(
            ownerUserID: ownerID,
            items: [exact]
        )
        try appState.workoutStore.savePendingActivityOnlyCloudSync(pending)
        try appState.workoutStore.saveActivityOnlyCloudBaseline(baseline)
        defaults.set(
            try JSONEncoder().encode(pending),
            forKey: LegacyPendingActivityOnlyWorkoutCloudSyncPreferences.keyPrefix + storageKey
        )
        defaults.set(
            try JSONEncoder().encode(baseline),
            forKey: LegacyActivityOnlyWorkoutCloudBaselinePreferences.keyPrefix + storageKey
        )
        defaults.set(
            Data("checkpoint".utf8),
            forKey: "gymapp.cloud-sync-checkpoint.v1.\(storageKey)"
        )

        try await appState.deleteCurrentAccountAndData(
            expectedStorageKey: storageKey,
            expectedCloudUserID: nil
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: targetURL.path))
        XCTAssertNil(defaults.object(
            forKey: LegacyPendingActivityOnlyWorkoutCloudSyncPreferences.keyPrefix + storageKey
        ))
        XCTAssertNil(defaults.object(
            forKey: LegacyActivityOnlyWorkoutCloudBaselinePreferences.keyPrefix + storageKey
        ))
        XCTAssertNil(defaults.object(
            forKey: "gymapp.cloud-sync-checkpoint.v1.\(storageKey)"
        ))
        XCTAssertNil(defaults.object(forKey: "gymapp.pending-account-deletion-storage-key"))
        XCTAssertNil(auth.session)
    }

    private func parseRead(items: [[String: Any]]) throws -> ActivityOnlyWorkoutCloudSnapshot {
        let object: [String: Any] = ["version": 1, "revision": 1, "items": items]
        return try ActivityOnlyWorkoutCloudCodec.parseReadResponse(
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func sharedActivityOnlyFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/activity-only-sync-v1.json")
    }

    private func item(
        timestamp: Int64,
        duration: Int,
        gymCalories: Double,
        garminCalories: Int? = nil,
        averageHeartRate: Int? = nil,
        maximumHeartRate: Int? = nil,
        endingHeartRateZone: Int? = nil,
        note: String? = nil
    ) throws -> ActivityOnlyWorkoutCloudItem {
        try ActivityOnlyWorkoutCloudItem(
            workoutStartedAt: timestamp,
            durationSeconds: duration,
            gymCalories: gymCalories,
            garminCalories: garminCalories,
            averageHeartRate: averageHeartRate,
            maximumHeartRate: maximumHeartRate,
            endingHeartRateZone: endingHeartRateZone,
            note: note
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GymAppActivitySidecarTests-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func temporaryDefaults(named name: String) -> UserDefaults {
        let suite = "GymAppActivitySidecarTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private struct ActivityOnlySyncGoldenFixture: Decodable {
    struct WireContract: Decodable {
        let absentOptionalFieldsAreDistinctFromZero: Bool
        let noteMaximumUnicodeCodePoints: Int
        let noteMaximumUtf8Bytes: Int
    }

    struct MergeScenario: Decodable {
        let name: String
        let base: [String]
        let local: [String]
        let remote: [String]
        let result: [String]?
        let conflict: Bool?
    }

    let schemaVersion: Int
    let identityField: String
    let maximumItems: Int
    let wireContract: WireContract
    let items: [String: ActivityOnlyWorkoutCloudItem]
    let mergeScenarios: [MergeScenario]
}

private final class ActivitySidecarKeychainStore: KeychainStoring {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        lock.lock()
        values[account] = data
        lock.unlock()
    }

    func read(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func delete(account: String) throws {
        lock.lock()
        values.removeValue(forKey: account)
        lock.unlock()
    }
}

private final class ActivitySidecarURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "owrcbsrectdgaotndtxy.supabase.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let request = try Self.materializedRequest(request)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        json: String
    ) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(request.url),
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        return (response, Data(json.utf8))
    }

    private static func materializedRequest(_ request: URLRequest) throws -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else {
            return request
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        var copy = request
        copy.httpBodyStream = nil
        copy.httpBody = data
        return copy
    }
}
