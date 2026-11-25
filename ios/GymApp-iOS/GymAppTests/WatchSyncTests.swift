import CryptoKit
import XCTest
@testable import GymApp

/// Runs every case of shared/watch-sync-v1.json through the shared codec and, for
/// watch-to-phone cases, through WatchConnectivityService with a fake WCSession.
@MainActor
final class WatchSyncGoldenTests: XCTestCase {
    func testEveryGoldenCase() throws {
        let contract = try WatchSyncTestSupport.loadContract()
        let cases = try XCTUnwrap(contract["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 24)
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0["id"] as! String, $0) })
        for item in cases {
            let id = item["id"] as! String
            let expect = try XCTUnwrap(item["expect"] as? [String: Any], id)
            if item["direction"] as? String == "phoneToWatch" {
                let message = try WatchSyncTestSupport.message(for: item, byID: byID)
                let bytes = try WatchSyncTestSupport.bytes(message)
                if message["type"] as? String == "account-deleted" {
                    let deleted = WatchSyncCodec.decodeAccountDeleted(bytes)
                    XCTAssertEqual(deleted != nil, expect["valid"] as? Bool, id)
                    XCTAssertNil(WatchSyncCodec.decodeContext(bytes), id)
                    XCTAssertNil(WatchSyncCodec.decodeReplyTolerant(bytes), id)
                    if let deleted {
                        XCTAssertEqual(WatchSyncCodec.decodeAccountDeleted(try WatchSyncCodec.encode(deleted)), deleted, id)
                    }
                    continue
                }
                let decoded = WatchSyncCodec.decodeContext(bytes)
                XCTAssertEqual(decoded != nil, expect["valid"] as? Bool, id)
                if let decoded {
                    // Round trip: encode -> decode gives the same message.
                    let reencoded = try WatchSyncCodec.encode(decoded)
                    XCTAssertEqual(WatchSyncCodec.decodeContext(reencoded), decoded, id)
                    XCTAssertEqual(decoded.bound == nil, expect["watchDropsPlan"] as? Bool ?? false, id)
                    if let restEndAlert = expect["restEndAlert"] as? Bool {
                        XCTAssertEqual(decoded.bound?.restEndAlert, restEndAlert, id)
                    }
                }
                continue
            }
            try runPhoneCase(item, byID: byID, expect: expect)
        }
    }

    func testPlanContextKeepsCyrillicNamesVerbatim() throws {
        let contract = try WatchSyncTestSupport.loadContract()
        let cases = try XCTUnwrap(contract["cases"] as? [[String: Any]])
        let item = try XCTUnwrap(cases.first { $0["id"] as? String == "context-bound-with-cyrillic-plan" })
        let bytes = try WatchSyncTestSupport.bytes(item["message"] as! [String: Any])
        let context = try XCTUnwrap(WatchSyncCodec.decodeContext(bytes))
        XCTAssertEqual(context.bound?.plan.map(\.name), ["Жим лёжа", "Присед"])
        XCTAssertEqual(context.bound?.plan.first?.sets.last, WatchPlanSet(weight: 62.5, reps: 6))
    }

    func testRestEndAlertDecodesTrueFalseAndAbsentAndIsSentOnlyWhenOff() throws {
        func bound(_ restEndAlert: Bool) -> WatchContextMessage {
            WatchContextMessage(sentAtMillis: 1_795_000_000_000, bound: WatchBoundContext(
                accountBinding: WatchSyncTestSupport.activeAccount,
                language: "en",
                planRevision: 2,
                plan: [],
                exercises: ["Bench press"],
                restEndAlert: restEndAlert
            ))
        }
        // On (default): the key is not sent, so the context keeps its old exact key set.
        let onBytes = try WatchSyncCodec.encode(bound(true))
        let onObject = try XCTUnwrap(JSONSerialization.jsonObject(with: onBytes) as? [String: Any])
        XCTAssertNil(onObject["restEndAlert"])
        XCTAssertEqual(WatchSyncCodec.decodeContext(onBytes)?.bound?.restEndAlert, true)
        // Off: sent as JSON false and decoded as false.
        let offBytes = try WatchSyncCodec.encode(bound(false))
        XCTAssertTrue(String(decoding: offBytes, as: UTF8.self).contains(#""restEndAlert":false"#))
        XCTAssertEqual(WatchSyncCodec.decodeContext(offBytes)?.bound?.restEndAlert, false)
        // Explicit true is accepted; a number or string is not a boolean.
        var object = onObject
        object["restEndAlert"] = true
        XCTAssertEqual(WatchSyncCodec.decodeContext(try JSONSerialization.data(withJSONObject: object))?.bound?.restEndAlert, true)
        object["restEndAlert"] = 1
        XCTAssertNil(WatchSyncCodec.decodeContext(try JSONSerialization.data(withJSONObject: object)))
        object["restEndAlert"] = "false"
        XCTAssertNil(WatchSyncCodec.decodeContext(try JSONSerialization.data(withJSONObject: object)))
        // Never on the unbound context.
        var unbound = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try WatchSyncCodec.encode(WatchContextMessage(sentAtMillis: 1, bound: nil))
        ) as? [String: Any])
        unbound["restEndAlert"] = false
        XCTAssertNil(WatchSyncCodec.decodeContext(try JSONSerialization.data(withJSONObject: unbound)))
    }

    func testCachedContextWithoutRestEndAlertReadsAsOn() throws {
        let legacy = Data(#"{"accountBinding":"\#(WatchSyncTestSupport.activeAccount)","language":"en","planRevision":3,"plan":[],"exercises":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(WatchBoundContext.self, from: legacy)
        XCTAssertTrue(decoded.restEndAlert)
        let off = WatchBoundContext(
            accountBinding: WatchSyncTestSupport.activeAccount, language: "en", planRevision: 3,
            plan: [], exercises: [], restEndAlert: false
        )
        XCTAssertEqual(try JSONDecoder().decode(WatchBoundContext.self, from: JSONEncoder().encode(off)), off)
    }

    func testOlderRevisionKeepsTheCachedPlanButTakesTheRestEndAlertSwitch() {
        let cached = WatchContextMessage(sentAtMillis: 10, bound: WatchBoundContext(
            accountBinding: WatchSyncTestSupport.activeAccount, language: "en", planRevision: 5,
            plan: [WatchPlanExercise(name: "Squat", restSeconds: 90, sets: [WatchPlanSet(weight: 100, reps: 5)])],
            exercises: ["Squat"]
        ))
        let incoming = WatchContextMessage(sentAtMillis: 20, bound: WatchBoundContext(
            accountBinding: WatchSyncTestSupport.activeAccount, language: "en", planRevision: 4,
            plan: [], exercises: ["Squat"], restEndAlert: false
        ))
        let merged = WatchContextMerge.merge(cached: cached, incoming: incoming)
        XCTAssertEqual(merged.bound?.plan, cached.bound?.plan)
        XCTAssertEqual(merged.bound?.restEndAlert, false)
    }

    func testPhoneContextCarriesTheRestEndAlertSwitchAndResendsOnChange() throws {
        let fixture = try WatchSyncFixture(name: "rest-alert")
        fixture.service.publishContext()
        XCTAssertEqual(fixture.transport.lastContext?.bound?.restEndAlert, true)
        let sent = fixture.transport.contexts.count
        fixture.defaults.set(false, forKey: GymRestEndAlert.preferenceKey)
        fixture.service.publishContext()
        XCTAssertEqual(fixture.transport.contexts.count, sent + 1, "a changed switch is re-sent")
        XCTAssertEqual(fixture.transport.lastContext?.bound?.restEndAlert, false)
    }

    func testRequestIDAndHashFormats() {
        for _ in 0 ..< 20 { XCTAssertTrue(WatchSync.isValidRequestID(WatchSync.makeRequestID())) }
        XCTAssertFalse(WatchSync.isValidRequestID("aw-0F8FAD5B-D9CB-469F-A165-70867728950E"))
        XCTAssertFalse(WatchSync.isValidRequestID("aw-0f8fad5b-d9cb-169f-a165-70867728950e"))
        XCTAssertFalse(WatchSync.isValidRequestID("garmin-123"))
        XCTAssertTrue(WatchSync.isValidHash(String(repeating: "a", count: 64)))
        XCTAssertFalse(WatchSync.isValidHash(String(repeating: "A", count: 64)))
        XCTAssertEqual(WatchNackReason.notReady.group, .transient)
        XCTAssertEqual(WatchNackReason.storage.group, .transient)
        XCTAssertEqual(WatchNackReason.rateLimited.group, .transient)
        XCTAssertEqual(WatchNackReason.foreignAccount.group, .hold)
        XCTAssertEqual(WatchNackReason.unsupportedVersion.group, .hold)
        XCTAssertEqual(WatchNackReason.malformed.group, .deterministic)
        XCTAssertEqual(WatchNackReason.conflict.group, .deterministic)
        XCTAssertEqual(WatchNackReason.invalid.group, .deterministic)
    }

    func testEnvelopeIsSingleKeyAndBounded() {
        let bytes = Data("{}".utf8)
        XCTAssertEqual(WatchSyncCodec.envelopeBytes(from: WatchSyncCodec.envelope(bytes)), bytes)
        XCTAssertNil(WatchSyncCodec.envelopeBytes(from: [WatchSync.envelopeKey: bytes, "x": 1]))
        XCTAssertNil(WatchSyncCodec.envelopeBytes(from: [WatchSync.envelopeKey: "text"]))
        XCTAssertNil(WatchSyncCodec.envelopeBytes(from: [WatchSync.envelopeKey: Data(count: 65_537)]))
    }

    func testAckAndNackRoundTrip() throws {
        let ack = WatchAckMessage(
            requestId: "aw-0f8fad5b-d9cb-469f-a165-70867728950e",
            accountBinding: WatchSyncTestSupport.activeAccount,
            status: .committed
        )
        XCTAssertEqual(WatchSyncCodec.decodeReply(try WatchSyncCodec.encode(ack)), .ack(ack))
        for reason in WatchNackReason.allCases {
            let nack = WatchNackMessage(requestId: ack.requestId, reason: reason)
            XCTAssertEqual(WatchSyncCodec.decodeReply(try WatchSyncCodec.encode(nack)), .nack(nack))
        }
    }

    func testAccountDeletedRoundTripAndOldWatchTolerance() throws {
        let deleted = WatchAccountDeletedMessage(accountBinding: WatchSyncTestSupport.activeAccount, sentAtMillis: 1_795_000_000_000)
        let bytes = try WatchSyncCodec.encode(deleted)
        XCTAssertEqual(WatchSyncCodec.messageType(of: bytes), "account-deleted")
        XCTAssertEqual(WatchSyncCodec.decodeAccountDeleted(bytes), deleted)
        // Watches without the message route userInfo to the reply decoder: it must be ignored.
        XCTAssertNil(WatchSyncCodec.decodeReply(bytes))
        XCTAssertNil(WatchSyncCodec.decodeReplyTolerant(bytes))
        XCTAssertNil(WatchSyncCodec.decodeContext(bytes))
        // An unknown userInfo type is ignored by this watch as well.
        XCTAssertNil(WatchSyncCodec.decodeAccountDeleted(Data(#"{"type":"future-thing","protocolVersion":1}"#.utf8)))
        XCTAssertNil(WatchSyncCodec.decodeReplyTolerant(Data(#"{"type":"future-thing","protocolVersion":2,"requestId":"aw-0f8fad5b-d9cb-469f-a165-70867728950e"}"#.utf8)))
        // Invalid binding or version 0: rejected; newer phone with extra keys: binding still read.
        XCTAssertThrowsError(try WatchSyncCodec.encode(WatchAccountDeletedMessage(accountBinding: "ABC", sentAtMillis: 1)))
        let bad = #"{"type":"account-deleted","protocolVersion":1,"accountBinding":"XYZ","sentAtMillis":1}"#
        XCTAssertNil(WatchSyncCodec.decodeAccountDeleted(Data(bad.utf8)))
        let old = #"{"type":"account-deleted","protocolVersion":0,"accountBinding":"\#(WatchSyncTestSupport.activeAccount)","sentAtMillis":1}"#
        XCTAssertNil(WatchSyncCodec.decodeAccountDeleted(Data(old.utf8)))
        let newer = #"{"type":"account-deleted","protocolVersion":2,"accountBinding":"\#(WatchSyncTestSupport.activeAccount)","extra":true}"#
        XCTAssertEqual(WatchSyncCodec.decodeAccountDeleted(Data(newer.utf8))?.accountBinding, WatchSyncTestSupport.activeAccount)
    }

    private func runPhoneCase(_ item: [String: Any], byID: [String: [String: Any]], expect: [String: Any]) throws {
        let id = item["id"] as! String
        let fixture = try WatchSyncFixture(name: id, bindStore: item["phoneState"] as? String != "signedOut")
        let bytes: Data
        if let size = item["envelopeBytes"] as? Int {
            bytes = Data(repeating: 0x20, count: size)
        } else {
            bytes = try WatchSyncTestSupport.bytes(try WatchSyncTestSupport.message(for: item, byID: byID))
        }
        let replay = expect["status"] as? String == "duplicate" || expect["reason"] as? String == "conflict"
        if replay, let baseID = item["replayOf"] as? String {
            let base = try WatchSyncTestSupport.bytes(try XCTUnwrap(byID[baseID]?["message"] as? [String: Any]))
            XCTAssertEqual(fixture.service.receiveWorkout(base), .ack(.committed), id)
        }
        let workoutsBefore = fixture.store.workouts.count
        fixture.transport.userInfos.removeAll()
        let outcome = fixture.service.receiveWorkout(bytes)
        let writes = fixture.store.workouts.count - workoutsBefore

        switch expect["result"] as? String {
        case "drop":
            XCTAssertEqual(outcome, .dropped, id)
            XCTAssertTrue(fixture.transport.userInfos.isEmpty, id)
        case "ack":
            let status = try XCTUnwrap(WatchAckStatus(rawValue: expect["status"] as! String), id)
            XCTAssertEqual(outcome, .ack(status), id)
            guard case .ack(let ack)? = fixture.transport.lastReply else { return XCTFail(id) }
            XCTAssertEqual(ack.status, status, id)
            XCTAssertEqual(ack.accountBinding, WatchSyncTestSupport.activeAccount, id)
            if let call = expect["storeCall"] as? String {
                let workout = try XCTUnwrap(fixture.store.workouts.last, id)
                XCTAssertEqual(workout.exercises.isEmpty, call == "createActivityWorkout", id)
            }
        case "nack":
            let reason = try XCTUnwrap(WatchNackReason(rawValue: expect["reason"] as! String), id)
            XCTAssertEqual(outcome, .nack(reason), id)
            XCTAssertEqual(fixture.transport.lastReply, .nack(.init(
                requestId: try XCTUnwrap(WatchSyncTestSupport.requestID(bytes)), reason: reason
            )), id)
        default:
            XCTFail("unknown result in \(id)")
        }
        if let expected = expect["workoutWrites"] as? Int {
            XCTAssertEqual(writes, expected, id)
        }
        if expect["ledgerWrites"] as? Int == 0 {
            XCTAssertFalse(fixture.ledgerExists, id)
        }
    }
}

@MainActor
final class WatchConnectivityServiceTests: XCTestCase {
    func testImportStoresSetsHeartRateAndCaloriesInTheNote() throws {
        let fixture = try WatchSyncFixture(name: "happy")
        let bytes = try WatchSyncTestSupport.caseBytes("workout-plan-imported")
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        let workout = try XCTUnwrap(fixture.store.workouts.last)
        XCTAssertEqual(workout.date.timeIntervalSince1970, 1_794_996_000)
        XCTAssertEqual(workout.durationSeconds, 3_000)
        XCTAssertEqual(workout.exercises.first?.sets.count, 2)
        let note = try XCTUnwrap(workout.note)
        XCTAssertTrue(note.hasPrefix("Apple Watch"), note)
        XCTAssertTrue(note.contains("118") && note.contains("161") && note.contains("312"), note)
        XCTAssertEqual(try fixture.files.loadLedger(storageKey: fixture.storageKey).records.map(\.state), [.committed])
    }

    func testTimeOnlyWorkoutStoresHeartRateAndCaloriesAsSidecarMetrics() throws {
        let fixture = try WatchSyncFixture(name: "time-only-metrics")
        let cases = try XCTUnwrap(WatchSyncTestSupport.loadContract()["cases"] as? [[String: Any]])
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0["id"] as! String, $0) })
        var message = try WatchSyncTestSupport.message(
            for: try XCTUnwrap(byID["workout-free-time-only"]), byID: byID
        )
        let measured = try WatchSyncTestSupport.message(
            for: try XCTUnwrap(byID["workout-plan-imported"]), byID: byID
        )
        for key in ["healthKit", "averageHeartRate", "maximumHeartRate", "activeKilocalories"] {
            message[key] = try XCTUnwrap(measured[key], key)
        }
        XCTAssertEqual(
            fixture.service.receiveWorkout(try WatchSyncTestSupport.bytes(message)),
            .ack(.committed)
        )
        let workout = try XCTUnwrap(fixture.store.workouts.last)
        XCTAssertTrue(workout.exercises.isEmpty)
        XCTAssertTrue(workout.note?.hasPrefix("Apple Watch") == true)
        XCTAssertTrue(fixture.store.hasRecordedActivityMetrics(workout))
        XCTAssertEqual(fixture.store.activityOnlyCloudItems.count, 1)
        let item = try XCTUnwrap(fixture.store.activityOnlyCloudItems.first)
        XCTAssertEqual(item.workoutStartedAt, 1_794_990_000_000)
        XCTAssertEqual(item.durationSeconds, 2_400)
        XCTAssertEqual(item.gymCalories, 312)
        XCTAssertEqual(item.averageHeartRate, 118)
        XCTAssertEqual(item.maximumHeartRate, 161)
        XCTAssertNil(item.garminCalories)
        XCTAssertNil(item.endingHeartRateZone)
        XCTAssertEqual(try fixture.store.activityOnlyCloudSnapshotItems(), [item], "what cloud sync uploads")
        // The same bytes again: still one workout and one item.
        XCTAssertEqual(
            fixture.service.receiveWorkout(try WatchSyncTestSupport.bytes(message)),
            .ack(.duplicate)
        )
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertEqual(fixture.store.activityOnlyCloudItems.count, 1)
    }

    func testActivityMetricsComeFromTheMessageFields() throws {
        let bytes = try WatchSyncTestSupport.caseBytes("workout-plan-imported")
        guard case let .valid(message) = WatchSyncCodec.decodeWorkout(
            bytes, nowMillis: 1_795_000_000_000
        ) else {
            return XCTFail("the contract case must decode")
        }
        let metrics = WatchConnectivityService.activityMetrics(message)
        XCTAssertEqual(metrics.gymCalories, 312)
        XCTAssertEqual(metrics.averageHeartRate, 118)
        XCTAssertEqual(metrics.maximumHeartRate, 161)
    }

    func testWatchWorkoutWithSetsReplacesTheHealthImportOfTheSameSession() async throws {
        let fixture = try WatchSyncFixture(name: "after-health-import")
        // Garmin Connect / another app wrote the same session to Apple Health a little later.
        let health = try await fixture.importedHealthSession(
            recordId: "WATCH-DUP-1", startMillis: 1_794_996_020_000, endMillis: 1_794_999_010_000
        )
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertTrue(try XCTUnwrap(fixture.store.workouts.first).exercises.isEmpty)
        XCTAssertEqual(fixture.store.activityOnlyCloudItems.count, 1)

        let bytes = try WatchSyncTestSupport.caseBytes("workout-plan-imported")
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        XCTAssertEqual(fixture.store.workouts.count, 1, "the imported copy is replaced, not doubled")
        XCTAssertFalse(try XCTUnwrap(fixture.store.workouts.first).exercises.isEmpty)
        XCTAssertTrue(fixture.store.activityOnlyCloudItems.isEmpty)

        _ = await health.service.importNow()
        XCTAssertEqual(fixture.store.workouts.count, 1, "the receipt keeps the session out")
        XCTAssertEqual(health.service.lastSummary?.imported, 0)
        XCTAssertEqual(health.states.load(account: fixture.storageKey).receipts, ["apple_health:WATCH-DUP-1"])
    }

    func testTimeOnlyWatchWorkoutReplacesTheHealthImportAtTheSameStart() async throws {
        let fixture = try WatchSyncFixture(name: "time-only-after-health-import")
        let health = try await fixture.importedHealthSession(
            recordId: "WATCH-DUP-2", startMillis: 1_794_990_000_000, endMillis: 1_794_992_400_000
        )
        XCTAssertEqual(fixture.store.workouts.count, 1)

        let bytes = try WatchSyncTestSupport.caseBytes("workout-free-time-only")
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertTrue(try XCTUnwrap(fixture.store.workouts.first).note?.hasPrefix("Apple Watch") == true)
        XCTAssertEqual(fixture.store.activityOnlyCloudItems.map(\.workoutStartedAt), [1_794_990_000_000])

        _ = await health.service.importNow()
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertEqual(health.service.lastSummary?.imported, 0)
    }

    func testWatchWorkoutLeavesANonOverlappingHealthImportAlone() async throws {
        let fixture = try WatchSyncFixture(name: "separate-health-import")
        // Ends more than the overlap tolerance before the watch workout starts.
        _ = try await fixture.importedHealthSession(
            recordId: "WATCH-SEP-1", startMillis: 1_794_980_000_000, endMillis: 1_794_983_000_000
        )
        let bytes = try WatchSyncTestSupport.caseBytes("workout-plan-imported")
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        XCTAssertEqual(fixture.store.workouts.count, 2)
        XCTAssertEqual(fixture.store.activityOnlyCloudItems.count, 1)
    }

    func testDuplicateGivesTheSameAckWithoutASecondWorkout() throws {
        let fixture = try WatchSyncFixture(name: "duplicate")
        let bytes = try WatchSyncTestSupport.caseBytes("workout-free-time-only")
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.duplicate))
        XCTAssertEqual(fixture.store.workouts.count, 1)
    }

    func testLedgerStorageFailureIsTransientAndWritesNothing() throws {
        let fixture = try WatchSyncFixture(name: "storage")
        // A file where the account directory should be makes every ledger write fail.
        let directory = fixture.files.directory(storageKey: fixture.storageKey)
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: directory)
        let outcome = fixture.service.receiveWorkout(try WatchSyncTestSupport.caseBytes("workout-free-time-only"))
        XCTAssertEqual(outcome, .nack(.storage))
        XCTAssertEqual(WatchNackReason.storage.group, .transient)
        XCTAssertTrue(fixture.store.workouts.isEmpty)
    }

    func testCorruptLedgerFailsClosed() throws {
        let fixture = try WatchSyncFixture(name: "corrupt")
        let directory = fixture.files.directory(storageKey: fixture.storageKey)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("receipts.json"))
        let outcome = fixture.service.receiveWorkout(try WatchSyncTestSupport.caseBytes("workout-free-time-only"))
        XCTAssertEqual(outcome, .nack(.storage))
        XCTAssertTrue(fixture.store.workouts.isEmpty)
    }

    func testAccountSwitchMidImportWritesNothingAndRollsBackThePendingReceipt() throws {
        let fixture = try WatchSyncFixture(name: "switch")
        fixture.service.beforeStoreWriteForTesting = {
            try? fixture.auth.installSessionForTesting(
                .local(id: "00000000-0000-4000-8000-000000000902", displayName: "Other")
            )
        }
        let outcome = fixture.service.receiveWorkout(try WatchSyncTestSupport.caseBytes("workout-plan-imported"))
        XCTAssertEqual(outcome, .nack(.notReady))
        XCTAssertTrue(fixture.store.workouts.isEmpty)
        XCTAssertTrue(try fixture.files.loadLedger(storageKey: fixture.storageKey).records.isEmpty)
    }

    func testPendingReceiptWithStoredWorkoutCommitsWithoutDuplicate() throws {
        let fixture = try WatchSyncFixture(name: "pending")
        let bytes = try WatchSyncTestSupport.caseBytes("workout-plan-imported")
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        var ledger = try fixture.files.loadLedger(storageKey: fixture.storageKey)
        ledger.records[0].state = .pending
        try fixture.files.saveLedger(ledger, storageKey: fixture.storageKey)
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertEqual(try fixture.files.loadLedger(storageKey: fixture.storageKey).records.map(\.state), [.committed])
    }

    // MARK: Late arrival over an already saved phone workout

    func testLateTimeOnlyWorkoutCoveredByAPhoneWorkoutIsAckedWithoutBeingStored() throws {
        let fixture = try WatchSyncFixture(name: "late-time-only-covered")
        // Phone workout with sets 1 minute into the watch's 40-minute window.
        let phone = try XCTUnwrap(fixture.store.createWorkout(
            date: Date(timeIntervalSince1970: 1_794_990_060),
            namedSets: [NamedWorkoutSetDraft(exerciseName: "Bench Press", weight: 80, reps: 8)],
            durationSeconds: 2_000
        ))
        let bytes = try WatchSyncTestSupport.caseBytes("workout-free-time-only")

        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        guard case .ack(let ack)? = fixture.transport.lastReply else { return XCTFail("no ack sent") }
        XCTAssertEqual(ack.status, .committed)
        XCTAssertEqual(fixture.store.workouts.map(\.id), [phone.id])
        XCTAssertTrue(fixture.store.activityOnlyCloudItems.isEmpty, "no sidecar that cloud sync could resurrect")
        XCTAssertEqual(try fixture.files.loadLedger(storageKey: fixture.storageKey).records.map(\.state), [.committed])

        // Replay of a committed receipt: duplicate ack, still nothing stored.
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.duplicate))
        XCTAssertEqual(fixture.store.workouts.map(\.id), [phone.id])

        // A receipt left pending (crash between decide and commit) decides the same way again.
        var ledger = try fixture.files.loadLedger(storageKey: fixture.storageKey)
        ledger.records[0].state = .pending
        try fixture.files.saveLedger(ledger, storageKey: fixture.storageKey)
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        XCTAssertEqual(fixture.store.workouts.map(\.id), [phone.id])
        XCTAssertEqual(try fixture.files.loadLedger(storageKey: fixture.storageKey).records.map(\.state), [.committed])
    }

    func testLateWorkoutWithTheSameSetsAsAPhoneWorkoutIsAckedWithoutBeingStored() throws {
        let fixture = try WatchSyncFixture(name: "late-same-sets")
        let phone = try XCTUnwrap(fixture.store.createWorkout(
            date: Date(timeIntervalSince1970: 1_794_996_030),
            namedSets: [
                NamedWorkoutSetDraft(exerciseName: "Жим лёжа", weight: 60, reps: 8),
                NamedWorkoutSetDraft(exerciseName: "Жим лёжа", weight: 62.5, reps: 6)
            ],
            durationSeconds: 2_900
        ))
        XCTAssertEqual(
            fixture.service.receiveWorkout(try WatchSyncTestSupport.caseBytes("workout-plan-imported")),
            .ack(.committed)
        )
        XCTAssertEqual(fixture.store.workouts.map(\.id), [phone.id])
        XCTAssertEqual(try fixture.files.loadLedger(storageKey: fixture.storageKey).records.map(\.state), [.committed])
    }

    func testLateWorkoutWithDifferentSetsKeepsBothWorkouts() throws {
        let fixture = try WatchSyncFixture(name: "late-different-sets")
        _ = try XCTUnwrap(fixture.store.createWorkout(
            date: Date(timeIntervalSince1970: 1_794_996_030),
            namedSets: [
                NamedWorkoutSetDraft(exerciseName: "Жим лёжа", weight: 60, reps: 8),
                NamedWorkoutSetDraft(exerciseName: "Жим лёжа", weight: 62.5, reps: 7)
            ],
            durationSeconds: 2_900
        ))
        XCTAssertEqual(
            fixture.service.receiveWorkout(try WatchSyncTestSupport.caseBytes("workout-plan-imported")),
            .ack(.committed)
        )
        XCTAssertEqual(fixture.store.workouts.count, 2, "a workout that differs is never dropped")
    }

    func testRateLimit() throws {
        let fixture = try WatchSyncFixture(name: "rate")
        let records = (0 ..< WatchSync.maximumReceiptsPerHour).map { _ in
            WatchReceiptRecord(
                requestID: WatchSync.makeRequestID(),
                digest: String(repeating: "c", count: 64),
                createdAt: fixture.now.timeIntervalSince1970 - 10,
                state: .committed
            )
        }
        try fixture.files.saveLedger(.init(records: records), storageKey: fixture.storageKey)
        let outcome = fixture.service.receiveWorkout(try WatchSyncTestSupport.caseBytes("workout-free-time-only"))
        XCTAssertEqual(outcome, .nack(.rateLimited))
        XCTAssertTrue(fixture.store.workouts.isEmpty)
    }

    func testPlanPublishRefreshesContextAndSkipsUnchangedBytes() throws {
        let fixture = try WatchSyncFixture(name: "plan")
        fixture.transport.contexts.removeAll()
        let plan = GarminWorkoutPlan(
            source: "test", version: 1, title: "", createdAt: "", startedAt: "", note: "",
            exercises: [GarminPlanExercise(name: "Жим лёжа", sets: [
                GarminPlanSet(weight: 60, reps: 8, orderIndex: 0),
                GarminPlanSet(weight: 62.5, reps: 6, orderIndex: 1)
            ])]
        )
        try fixture.service.publishPlan(plan)
        let first = try XCTUnwrap(fixture.transport.lastContext?.bound)
        XCTAssertEqual(first.accountBinding, WatchSyncTestSupport.activeAccount)
        XCTAssertEqual(first.plan.map(\.name), ["Жим лёжа"])
        XCTAssertEqual(first.plan.first?.restSeconds, 90)
        XCTAssertTrue(first.exercises.contains("Жим лёжа"))
        let sent = fixture.transport.contexts.count
        fixture.service.publishContext()
        XCTAssertEqual(fixture.transport.contexts.count, sent, "unchanged context is not re-sent")

        try fixture.service.publishPlan(plan)
        XCTAssertEqual(fixture.transport.lastContext?.bound?.planRevision, first.planRevision + 1)

        try fixture.service.clearPlan()
        XCTAssertEqual(fixture.transport.lastContext?.bound?.plan, [])
    }

    func testAccountSwitchPublishesTheNewAccountWithoutTheOldPlan() async throws {
        let fixture = try WatchSyncFixture(name: "rebind")
        try fixture.service.publishPlan(GarminWorkoutPlan(
            source: "test", version: 1, title: "", createdAt: "", startedAt: "", note: "",
            exercises: [GarminPlanExercise(name: "Присед", sets: [GarminPlanSet(weight: 100, reps: 5, orderIndex: 0)])]
        ))
        let other = AppAccountSession.local(id: "00000000-0000-4000-8000-000000000903", displayName: "Other")
        try fixture.auth.installSessionForTesting(other)
        for _ in 0 ..< 20 { await Task.yield() }
        // The old store is still bound: the new account is not ready, so the watch gets `unbound`.
        XCTAssertNotNil(fixture.transport.lastContext)
        XCTAssertNil(fixture.transport.lastContext?.bound)

        let otherStore = try WorkoutStore(
            accountStorageKey: other.storageKey,
            directoryURL: fixture.root.appendingPathComponent("other", isDirectory: true)
        )
        fixture.service.bind(workoutStore: otherStore)
        let bound = try XCTUnwrap(fixture.transport.lastContext?.bound)
        XCTAssertNotEqual(bound.accountBinding, WatchSyncTestSupport.activeAccount)
        XCTAssertEqual(bound.plan, [])

        // A late workout for the old account is held, not written.
        let outcome = fixture.service.receiveWorkout(try WatchSyncTestSupport.caseBytes("workout-free-time-only"))
        XCTAssertEqual(outcome, .nack(.foreignAccount))
        XCTAssertTrue(otherStore.workouts.isEmpty)
        XCTAssertTrue(fixture.store.workouts.isEmpty)
    }

    func testAccountChangeAfterTheStoreWriteNeverAcksAndNeverReachesTheOtherAccount() async throws {
        let fixture = try WatchSyncFixture(name: "late-switch")
        let other = AppAccountSession.local(id: "00000000-0000-4000-8000-000000000904", displayName: "Other")
        let auth = fixture.auth
        fixture.service.afterStoreWriteForTesting = { try? auth.installSessionForTesting(other) }
        let bytes = try WatchSyncTestSupport.caseBytes("workout-plan-imported")
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .nack(.notReady))
        fixture.service.afterStoreWriteForTesting = nil

        // No ack left the phone. The workout is in the account it was recorded for, receipt pending.
        XCTAssertFalse(fixture.transport.userInfos.contains { info in
            if case .ack? = WatchSyncCodec.envelopeBytes(from: info).flatMap(WatchSyncCodec.decodeReply) { return true }
            return false
        })
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertEqual(try fixture.files.loadLedger(storageKey: fixture.storageKey).records.map(\.state), [.pending])

        // While the other account is active the retry is held: nothing is written or acknowledged for it.
        for _ in 0 ..< 20 { await Task.yield() }
        let otherStore = try WorkoutStore(
            accountStorageKey: other.storageKey,
            directoryURL: fixture.root.appendingPathComponent("other", isDirectory: true)
        )
        fixture.service.bind(workoutStore: otherStore)
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .nack(.foreignAccount))
        XCTAssertTrue(otherStore.workouts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.files.directory(storageKey: other.storageKey).appendingPathComponent("receipts.json").path
        ))
        XCTAssertEqual(fixture.store.workouts.count, 1)

        // Back on the original account the pending receipt commits without a second workout.
        try fixture.auth.installSessionForTesting(
            .local(id: "00000000-0000-4000-8000-000000000901", displayName: "Watch")
        )
        for _ in 0 ..< 20 { await Task.yield() }
        fixture.service.bind(workoutStore: fixture.store)
        XCTAssertEqual(fixture.service.receiveWorkout(bytes), .ack(.committed))
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertEqual(try fixture.files.loadLedger(storageKey: fixture.storageKey).records.map(\.state), [.committed])
    }

    func testPlanCarriesTheExercisesOwnRestAndDefaultsTo90() throws {
        let fixture = try WatchSyncFixture(name: "rest")
        let saved = ExerciseRestTimeStore(defaults: fixture.defaults).setRestSeconds(
            150,
            accountStorageKey: fixture.storageKey,
            identityKey: FriendGhosts.exerciseKey(catalogKey: nil, name: "Моя тяга")
        )
        XCTAssertEqual(saved, .stored(150))
        try fixture.service.publishPlan(GarminWorkoutPlan(
            source: "test", version: 1, title: "", createdAt: "", startedAt: "", note: "",
            exercises: [
                GarminPlanExercise(name: "Моя тяга", sets: [GarminPlanSet(weight: 40, reps: 10, orderIndex: 0)]),
                GarminPlanExercise(name: "Мой подъём", sets: [GarminPlanSet(weight: 20, reps: 12, orderIndex: 0)])
            ]
        ))
        XCTAssertEqual(fixture.transport.lastContext?.bound?.plan.map(\.restSeconds), [150, 90])
    }

    func testNothingIsSentWithoutAPairedWatchThatHasTheApp() throws {
        let fixture = try WatchSyncFixture(name: "unpaired")
        fixture.transport.contexts.removeAll()
        fixture.transport.isWatchAppInstalled = false
        fixture.service.watchTransportStateDidChange()
        try fixture.service.clearPlan()
        XCTAssertTrue(fixture.transport.contexts.isEmpty)
        XCTAssertFalse(fixture.service.isWatchAppInstalled)

        fixture.transport.isWatchAppInstalled = true
        fixture.service.watchTransportStateDidChange()
        XCTAssertEqual(fixture.transport.contexts.count, 1)
        XCTAssertEqual(fixture.transport.lastContext?.bound?.plan, [])
        XCTAssertTrue(fixture.service.isWatchAppInstalled)
    }

    func testFirstSavedPlanOutranksTheEmptyContextAndACorruptPlanFileIsIgnored() throws {
        let fixture = try WatchSyncFixture(name: "revision")
        let empty = try XCTUnwrap(fixture.transport.lastContext?.bound)
        XCTAssertEqual(empty.plan, [])
        let plan = GarminWorkoutPlan(
            source: "test", version: 1, title: "", createdAt: "", startedAt: "", note: "",
            exercises: [GarminPlanExercise(name: "Присед", sets: [GarminPlanSet(weight: 100, reps: 5, orderIndex: 0)])]
        )
        try fixture.service.publishPlan(plan)
        let first = try XCTUnwrap(fixture.transport.lastContext?.bound)
        XCTAssertGreaterThan(first.planRevision, empty.planRevision)

        // A stored plan outside the contract bounds is treated as unreadable, not published.
        let tooManySets = (0 ..< 21).map { _ in WatchPlanSet(weight: 1, reps: 1) }
        try fixture.files.savePlan(
            .init(planRevision: 9, plan: [.init(name: "X", restSeconds: 90, sets: tooManySets)], updatedAt: 0),
            storageKey: fixture.storageKey
        )
        XCTAssertThrowsError(try fixture.files.loadPlan(storageKey: fixture.storageKey))
        XCTAssertEqual(fixture.service.currentContext().bound?.plan, [])
        try fixture.service.publishPlan(plan)
        XCTAssertGreaterThan(try XCTUnwrap(fixture.transport.lastContext?.bound?.planRevision), 9)
    }

    func testOutOfRangeIntegersAreRejectedNotTrapped() throws {
        let base = try WatchSyncTestSupport.caseBytes("workout-plan-imported")
        var message = try XCTUnwrap(JSONSerialization.jsonObject(with: base) as? [String: Any])
        var sets = try XCTUnwrap(message["sets"] as? [[String: Any]])
        sets[0]["reps"] = 9_007_199_254_740_991
        message["sets"] = sets
        message["averageHeartRate"] = 4_294_967_296
        let bytes = try WatchSyncTestSupport.bytes(message)
        guard case .malformed = WatchSyncCodec.decodeWorkout(bytes, nowMillis: 1_795_000_000_000) else {
            return XCTFail("expected malformed")
        }
    }

    func testClearLocalDataRemovesFilesAndPublishesUnbound() throws {
        let fixture = try WatchSyncFixture(name: "clear")
        XCTAssertEqual(
            fixture.service.receiveWorkout(try WatchSyncTestSupport.caseBytes("workout-free-time-only")),
            .ack(.committed)
        )
        fixture.service.clearLocalData(storageKey: fixture.storageKey)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.files.directory(storageKey: fixture.storageKey).path))
        XCTAssertNil(fixture.defaults.string(forKey: WatchAccountBinding.localKey(storageKey: fixture.storageKey)))
        XCTAssertNil(fixture.transport.lastContext?.bound)
    }

    func testDeletionSendsAccountDeletedNoticeWithTheDeletedBindingAndAPlainUnboundContext() throws {
        let fixture = try WatchSyncFixture(name: "delete-notice")
        let binding = try XCTUnwrap(fixture.defaults.string(forKey: WatchAccountBinding.localKey(storageKey: fixture.storageKey)))
        fixture.transport.userInfos.removeAll()
        fixture.service.clearLocalData(storageKey: fixture.storageKey)
        let notices = fixture.transport.userInfos.compactMap { WatchSyncCodec.envelopeBytes(from: $0) }
            .compactMap(WatchSyncCodec.decodeAccountDeleted)
        XCTAssertEqual(notices.map(\.accountBinding), [binding])
        // The context stays the exact v1 unbound shape old watches decode.
        let context = try XCTUnwrap(fixture.transport.contexts.last.flatMap(WatchSyncCodec.envelopeBytes(from:)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: context) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["type", "protocolVersion", "state", "sentAtMillis"])
        XCTAssertTrue(WatchDeletedAccountNotices.pending(defaults: fixture.defaults).isEmpty)
    }

    func testDeletionNoticeWaitsForAWatchAndSurvivesRecovery() throws {
        let fixture = try WatchSyncFixture(name: "delete-recovery")
        let binding = try XCTUnwrap(fixture.defaults.string(forKey: WatchAccountBinding.localKey(storageKey: fixture.storageKey)))
        // Startup recovery runs before the service exists: the binding is recorded before its key is removed.
        WatchConnectivityService.clearStoredData(defaults: fixture.defaults, storageKey: fixture.storageKey, fileRoot: fixture.root.appendingPathComponent("WatchSync", isDirectory: true))
        XCTAssertNil(fixture.defaults.string(forKey: WatchAccountBinding.localKey(storageKey: fixture.storageKey)))
        XCTAssertEqual(WatchDeletedAccountNotices.pending(defaults: fixture.defaults), [binding])
        fixture.transport.userInfos.removeAll()
        fixture.transport.isPaired = false
        fixture.service.watchTransportStateDidChange()
        XCTAssertTrue(fixture.transport.userInfos.isEmpty)
        XCTAssertEqual(WatchDeletedAccountNotices.pending(defaults: fixture.defaults), [binding])
        fixture.transport.isPaired = true
        fixture.service.watchTransportStateDidChange()
        let notices = fixture.transport.userInfos.compactMap { WatchSyncCodec.envelopeBytes(from: $0) }
            .compactMap(WatchSyncCodec.decodeAccountDeleted)
        XCTAssertEqual(notices.map(\.accountBinding), [binding])
        XCTAssertTrue(WatchDeletedAccountNotices.pending(defaults: fixture.defaults).isEmpty)
    }

    func testCloudDeletionBindingIsDerivedFromTheStorageKey() {
        let defaults = UserDefaults(suiteName: "watch-delete-cloud")!
        defer { defaults.removePersistentDomain(forName: "watch-delete-cloud") }
        let userID = "0f8fad5b-d9cb-469f-a165-70867728950e"
        let expected = SHA256.hash(data: Data("gymapp-watch-account/v1\u{0}\(userID)".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(WatchDeletedAccountNotices.binding(storageKey: "cloud_\(userID)", defaults: defaults), expected)
        XCTAssertNil(WatchDeletedAccountNotices.binding(storageKey: "cloud_not-a-uuid", defaults: defaults))
        XCTAssertNil(WatchDeletedAccountNotices.binding(storageKey: "local_never-bound", defaults: defaults))
    }
}

// MARK: - Support

@MainActor
final class FakeWatchTransport: WatchSessionTransport {
    var isPaired = true
    var isWatchAppInstalled = true
    var isActivated = true
    var contexts: [[String: Any]] = []
    var userInfos: [[String: Any]] = []

    func activate(handler: WatchSessionTransportHandler) {}

    func updateApplicationContext(_ context: [String: Any]) throws {
        contexts.append(context)
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        userInfos.append(userInfo)
    }

    var lastContext: WatchContextMessage? {
        contexts.last.flatMap(WatchSyncCodec.envelopeBytes(from:)).flatMap(WatchSyncCodec.decodeContext)
    }

    var lastReply: WatchReply? {
        userInfos.last.flatMap(WatchSyncCodec.envelopeBytes(from:)).flatMap(WatchSyncCodec.decodeReply)
    }
}

@MainActor
final class WatchSyncFixture {
    let auth: AuthService
    let defaults: UserDefaults
    let store: WorkoutStore
    let transport = FakeWatchTransport()
    let files: WatchSyncFileStore
    let service: WatchConnectivityService
    let storageKey: String
    let root: URL
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let suite: String

    init(name: String, bindStore: Bool = true) throws {
        suite = "WatchSyncTests-\(name)-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        auth = AuthService(keychain: WatchSyncTestKeychain(), defaults: defaults)
        let account = AppAccountSession.local(id: "00000000-0000-4000-8000-000000000901", displayName: "Watch")
        try auth.installSessionForTesting(account)
        storageKey = account.storageKey
        // The fixture account hash from the contract is this account's local binding.
        defaults.set(WatchSyncTestSupport.activeAccount, forKey: WatchAccountBinding.localKey(storageKey: storageKey))
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try WorkoutStore(
            accountStorageKey: account.storageKey,
            directoryURL: root.appendingPathComponent("workouts", isDirectory: true)
        )
        let fileRoot = root.appendingPathComponent("WatchSync", isDirectory: true)
        files = WatchSyncFileStore(root: fileRoot)
        let fixedNow = now
        service = WatchConnectivityService(
            auth: auth,
            defaults: defaults,
            transport: transport,
            useLiveTransport: false,
            fileRoot: fileRoot,
            now: { fixedNow }
        )
        if bindStore { service.bind(workoutStore: store) }
    }

    /// Connects an Apple Health import to this fixture's account and store and imports one
    /// gym session with the given interval.
    func importedHealthSession(
        recordId: String,
        startMillis: Int64,
        endMillis: Int64
    ) async throws -> (service: HealthKitImportService, states: HealthImportStateStore) {
        let states = HealthImportStateStore(root: root.appendingPathComponent("HealthImport", isDirectory: true))
        let fixedNow = now
        let health = HealthKitImportService(
            auth: auth,
            defaults: defaults,
            client: WatchSyncHealthClient(session: HealthImportSession(
                recordId: recordId,
                startMillis: startMillis,
                endMillis: endMillis,
                exerciseType: "traditionalStrengthTraining",
                sourceId: "com.example.health-writer",
                kilocalories: 300,
                heartRateSamples: []
            )),
            stateStore: states,
            now: { fixedNow }
        )
        health.bind(workoutStore: store)
        await health.connect()
        XCTAssertTrue(health.isConnected)
        XCTAssertEqual(health.lastSummary?.imported, 1)
        return (health, states)
    }

    var ledgerExists: Bool {
        FileManager.default.fileExists(
            atPath: files.directory(storageKey: storageKey).appendingPathComponent("receipts.json").path
        )
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private struct WatchSyncHealthClient: HealthKitImportClient {
    let session: HealthImportSession

    var isAvailable: Bool { true }

    func requestAuthorization() async throws {}

    func fetchWorkouts(since: Date, limit: Int) async throws -> [HealthImportSession] { [session] }

    func heartRateSamples(
        startMillis: Int64,
        endMillis: Int64,
        sourceId: String
    ) async throws -> [HealthImportHeartRateSample] { [] }
}

private final class WatchSyncTestKeychain: KeychainStoring {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws { lock.withLock { values[account] = data } }
    func read(account: String) throws -> Data? { lock.withLock { values[account] } }
    func delete(account: String) throws { lock.withLock { _ = values.removeValue(forKey: account) } }
}

enum WatchSyncTestSupport {
    static let activeAccount = String(repeating: "1", count: 64)

    static func loadContract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/watch-sync-v1.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func caseBytes(_ id: String) throws -> Data {
        let cases = try XCTUnwrap(loadContract()["cases"] as? [[String: Any]])
        let byID = Dictionary(uniqueKeysWithValues: cases.map { ($0["id"] as! String, $0) })
        return try bytes(message(for: try XCTUnwrap(byID[id]), byID: byID))
    }

    /// Expands `replayOf` and `mutate` (dotted path, `null` removes, `REPEAT(x,n)`).
    static func message(for item: [String: Any], byID: [String: [String: Any]]) throws -> [String: Any] {
        var message: [String: Any]
        if let own = item["message"] as? [String: Any] {
            message = own
        } else {
            let base = try XCTUnwrap(byID[try XCTUnwrap(item["replayOf"] as? String)])
            message = try XCTUnwrap(base["message"] as? [String: Any])
        }
        for (path, rawValue) in (item["mutate"] as? [String: Any] ?? [:]) {
            let value = try expand(rawValue, in: message)
            message = set(path: Array(path.split(separator: ".").map(String.init)), value: value, in: message)
        }
        return message
    }

    static func bytes(_ message: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
    }

    static func requestID(_ bytes: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any])?["requestId"] as? String
    }

    private static func expand(_ value: Any, in message: [String: Any]) throws -> Any? {
        if value is NSNull { return nil }
        guard let text = value as? String, text.hasPrefix("REPEAT("), text.hasSuffix(")") else { return value }
        let inner = text.dropFirst("REPEAT(".count).dropLast()
        let parts = inner.split(separator: ",", maxSplits: 1).map(String.init)
        let count = try XCTUnwrap(Int(parts[1]))
        if parts[0] == "sets[0]" {
            let first = try XCTUnwrap((message["sets"] as? [Any])?.first)
            return Array(repeating: first, count: count)
        }
        return String(repeating: parts[0], count: count)
    }

    private static func set(path: [String], value: Any?, in object: [String: Any]) -> [String: Any] {
        var object = object
        guard let head = path.first else { return object }
        if let bracket = head.firstIndex(of: "[") {
            let key = String(head[..<bracket])
            let index = Int(head[head.index(after: bracket) ..< head.index(before: head.endIndex)])!
            var array = object[key] as! [Any]
            var element = array[index] as! [String: Any]
            element = set(path: Array(path.dropFirst()), value: value, in: element)
            array[index] = element
            object[key] = array
            return object
        }
        if path.count == 1 {
            object[head] = value
        } else {
            object[head] = set(path: Array(path.dropFirst()), value: value, in: object[head] as? [String: Any] ?? [:])
        }
        return object
    }
}
