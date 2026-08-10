import Foundation
import XCTest
@testable import GymApp

@MainActor
final class NativePushTests: XCTestCase {
    private let userA = "10000000-0000-4000-8000-000000000001"
    private let userB = "20000000-0000-4000-8000-000000000002"
    private let userC = "60000000-0000-4000-8000-000000000006"
    private let sessionA = "30000000-0000-4000-8000-000000000003"
    private let sessionB = "40000000-0000-4000-8000-000000000004"
    private let sessionC = "70000000-0000-4000-8000-000000000007"
    private let bindingA = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let bindingB = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let bindingC = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
    private let installationID = UUID(uuidString: "12345678-1234-4abc-8def-1234567890ab")!

    func testParserAcceptsOnlyExactDataOnlySocialAndLivePayloads() throws {
        let social = socialPayload(bindingID: bindingA)
        let parsedSocial = try XCTUnwrap(NativePushPayloadParser.remoteEvent(from: social))
        XCTAssertEqual(parsedSocial.bindingID, bindingA)
        XCTAssertEqual(parsedSocial.eventType, .friendRequestReceived)
        XCTAssertEqual(parsedSocial.objectID, "f_0123456789abcdef0123456789abcdef")
        XCTAssertEqual(parsedSocial.objectRevision, 7)

        let live: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "gymapp": [
                "version": 1,
                "bindingId": bindingA.uuidString.lowercased(),
                "kind": "started",
                "roomId": "lr_0123456789abcdef0123456789abcdef",
                "roomRevision": 9
            ]
        ]
        let parsedLive = try XCTUnwrap(NativePushPayloadParser.remoteEvent(from: live))
        XCTAssertEqual(parsedLive.eventType, .liveRoomStarted)
        XCTAssertEqual(parsedLive.eventType.destination, .live)

        var alert = social
        alert["aps"] = ["content-available": 1, "alert": ["title": "unsafe"]]
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: alert))

        var sound = social
        sound["aps"] = ["content-available": 1, "sound": "default"]
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: sound))

        var booleanVersion = social
        var booleanObject = try XCTUnwrap(booleanVersion["gymapp"] as? [String: Any])
        booleanObject["version"] = true
        booleanVersion["gymapp"] = booleanObject
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: booleanVersion))

        var unknown = social
        var unknownObject = try XCTUnwrap(unknown["gymapp"] as? [String: Any])
        unknownObject["profileName"] = "private"
        unknown["gymapp"] = unknownObject
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: unknown))

        var mismatchedObject = social
        var mismatchObject = try XCTUnwrap(mismatchedObject["gymapp"] as? [String: Any])
        mismatchObject["objectId"] = "wi_0123456789abcdef0123456789abcdef"
        mismatchedObject["gymapp"] = mismatchObject
        XCTAssertNil(NativePushPayloadParser.remoteEvent(from: mismatchedObject))
    }

    func testBindingStoreKeepsStableInstallationIDAndRejectsMalformedBinding() throws {
        let keychain = PushTestKeychain()
        let first = NativePushBindingStore(keychain: keychain)
        let installation = try first.installationID()
        XCTAssertEqual(try NativePushBindingStore(keychain: keychain).installationID(), installation)

        let binding = NativePushBinding(
            version: NativePushBinding.currentVersion,
            installationID: installation,
            userID: userA,
            authSessionID: sessionA,
            bindingID: bindingA,
            environment: .sandbox,
            tokenDigest: String(repeating: "a", count: 64),
            registrationRevision: 2,
            supersededRevocationBindingID: nil
        )
        try first.saveBinding(binding)
        XCTAssertEqual(try first.loadBinding(), binding)

        let event = try XCTUnwrap(NativePushPayloadParser.remoteEvent(
            from: socialPayload(bindingID: bindingA, revision: 7)
        ))
        XCTAssertTrue(try first.canDisplay(event, binding: binding))
        XCTAssertTrue(try first.commitDisplayed(event, binding: binding))
        XCTAssertFalse(try NativePushBindingStore(keychain: keychain).canDisplay(
            event,
            binding: binding
        ))
        XCTAssertNotNil(try keychain.read(account: "native-push-delivery-state-v1"))

        let pending = NativePushPendingRevocation(
            version: NativePushPendingRevocation.currentVersion,
            installationID: installation,
            userID: userA,
            authSessionID: sessionA,
            bindingID: bindingA,
            registrationRevision: 2
        )
        try first.savePendingRevocation(pending)
        XCTAssertEqual(
            try NativePushBindingStore(keychain: keychain).loadPendingRevocation(),
            pending
        )

        try keychain.save(Data(#"{"version":999}"#.utf8), account: "native-push-binding-v1")
        XCTAssertNil(try first.loadBinding())
        XCTAssertNil(try keychain.read(account: "native-push-binding-v1"))
        XCTAssertNil(try keychain.read(account: "native-push-delivery-state-v1"))
        XCTAssertEqual(try first.loadPendingRevocation(), pending)
    }

    func testRegistrationBindsPayloadBeforeLocalDisplayAndTapRouting() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }

        await harness.manager.activateIfNeeded()
        XCTAssertEqual(harness.system.registerCallCount, 1)
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x41, count: 32))
        let becameActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(becameActive)
        XCTAssertEqual(harness.backend.operations, ["register:\(userA)"])
        XCTAssertEqual(harness.store.binding?.bindingID, bindingA)

        let wrongBindingOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: UUID())
        )
        XCTAssertEqual(wrongBindingOutcome, .noData)
        XCTAssertTrue(harness.system.scheduled.isEmpty)

        let acceptedOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(acceptedOutcome, .newData)
        let scheduled = try XCTUnwrap(harness.system.scheduled.last)
        XCTAssertEqual(scheduled.destination, .social)
        XCTAssertFalse(scheduled.title.contains(userA))
        XCTAssertFalse(scheduled.body.contains("f_"))

        harness.manager.handleLocalNotificationTap(
            identifier: scheduled.identifier,
            userInfo: localTapPayload(bindingID: bindingA, destination: .social)
        )
        XCTAssertEqual(harness.manager.consumePendingRoute()?.destination, .social)

        harness.manager.handleLocalNotificationTap(
            identifier: scheduled.identifier,
            userInfo: localTapPayload(bindingID: bindingB, destination: .live)
        )
        XCTAssertNil(harness.manager.consumePendingRoute())
    }

    func testDeliveryHighWaterRejectsDuplicateAndStaleRevisionsAndReplacesNewer() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x47, count: 32))
        let active = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(active)

        let firstOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA, revision: 7)
        )
        XCTAssertEqual(firstOutcome, .newData)
        let first = try XCTUnwrap(harness.system.scheduled.last)
        XCTAssertEqual(harness.system.scheduleCallCount, 1)

        let duplicateOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA, revision: 7)
        )
        XCTAssertEqual(duplicateOutcome, .noData)
        XCTAssertEqual(harness.system.scheduleCallCount, 1)

        let newerOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(
                bindingID: bindingA,
                type: "friend_request_accepted",
                revision: 8
            )
        )
        XCTAssertEqual(newerOutcome, .newData)
        XCTAssertEqual(harness.system.scheduleCallCount, 2)
        XCTAssertEqual(harness.system.scheduled.count, 1)
        XCTAssertEqual(harness.system.scheduled.last?.identifier, first.identifier)

        let staleCrossTypeOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA, revision: 6)
        )
        let equalCrossTypeOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA, revision: 8)
        )
        XCTAssertEqual(staleCrossTypeOutcome, .noData)
        XCTAssertEqual(equalCrossTypeOutcome, .noData)
        XCTAssertEqual(harness.system.scheduleCallCount, 2)
        XCTAssertEqual(harness.system.scheduled.count, 1)
    }

    func testLiveDeliveryHighWaterRejectsStaleStartedAfterNewerRoomClosed() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x49, count: 32))
        let active = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(active)

        let roomClosedPayload = livePayload(
            bindingID: bindingA,
            kind: "room_closed",
            revision: 10
        )
        let staleStartedPayload = livePayload(
            bindingID: bindingA,
            kind: "started",
            revision: 9
        )
        let roomClosed = try XCTUnwrap(
            NativePushPayloadParser.remoteEvent(from: roomClosedPayload)
        )
        let staleStarted = try XCTUnwrap(
            NativePushPayloadParser.remoteEvent(from: staleStartedPayload)
        )
        XCTAssertEqual(roomClosed.deliveryKey, "live:lr_0123456789abcdef0123456789abcdef")
        XCTAssertEqual(staleStarted.deliveryKey, roomClosed.deliveryKey)

        let closedOutcome = await harness.manager.handleRemoteNotification(roomClosedPayload)
        XCTAssertEqual(closedOutcome, .newData)
        let scheduled = try XCTUnwrap(harness.system.scheduled.last)

        let staleStartedOutcome = await harness.manager.handleRemoteNotification(
            staleStartedPayload
        )
        XCTAssertEqual(staleStartedOutcome, .noData)
        XCTAssertEqual(harness.system.scheduleCallCount, 1)
        XCTAssertEqual(harness.system.scheduled.map(\.identifier), [scheduled.identifier])
    }

    func testAccountSwitchImmediatelyFencesOldBindingAndSerializesNewOwner() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x42, count: 32))
        let firstRegistrationFinished = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(firstRegistrationFinished)

        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        let oldOwnerOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(oldOwnerOutcome, .noData)
        let secondRegistrationFinished = await waitUntil {
            harness.store.binding?.userID == self.userB
                && harness.manager.status == .active
        }
        XCTAssertTrue(secondRegistrationFinished)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "register:\(userB)"
        ])
        XCTAssertGreaterThanOrEqual(harness.system.removeAllCallCount, 1)

        let newOwnerOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingB)
        )
        XCTAssertEqual(newOwnerOutcome, .newData)
    }

    func testSessionEndClearsLocalBindingAndRevokesAfterRegistration() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x43, count: 32))
        let becameActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(becameActive)

        await harness.manager.prepareForSessionEnd(expectedUserID: userA)
        XCTAssertNil(harness.store.binding)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)"
        ])
        XCTAssertNil(harness.store.pendingRevocation)
        let postRevokeOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(postRevokeOutcome, .noData)
        XCTAssertGreaterThanOrEqual(harness.system.unregisterCallCount, 1)
    }

    func testFailedRevocationStaysDurableAndRetriesWithoutReenablingDelivery() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x48, count: 32))
        let active = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(active)
        harness.backend.failNextRevoke()

        await harness.manager.disable()
        XCTAssertFalse(harness.manager.isEnabled)
        XCTAssertNotNil(harness.store.binding)
        XCTAssertNotNil(harness.store.pendingRevocation)
        XCTAssertEqual(harness.manager.status, .revocationPending)
        let fencedOutcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(fencedOutcome, .noData)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)"
        ])

        await harness.manager.activateIfNeeded()
        XCTAssertNil(harness.store.pendingRevocation)
        XCTAssertNil(harness.store.binding)
        XCTAssertFalse(harness.manager.isEnabled)
        XCTAssertEqual(harness.manager.status, .disabled)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)",
            "revoke:\(userA)"
        ])
    }

    func testPendingSaveFailureKeepsRevocationSourceAcrossRestartAndRetries() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x4c, count: 32))
        let becameActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(becameActive)
        harness.store.failNextPendingRevocationSave()
        harness.backend.failNextRevoke()

        await harness.manager.disable()
        XCTAssertNotNil(harness.store.binding)
        XCTAssertNil(harness.store.pendingRevocation)
        XCTAssertEqual(
            harness.defaults.string(
                forKey: "gymapp.native-push.revocation-fence-binding.v1"
            ),
            bindingA.uuidString.lowercased()
        )

        let restarted = NativePushManager(
            auth: harness.auth,
            defaults: harness.defaults,
            store: harness.store,
            backend: harness.backend,
            system: harness.system,
            environment: .sandbox
        )
        XCTAssertNotNil(harness.store.pendingRevocation)
        XCTAssertNotEqual(restarted.status, .active)
        await restarted.activateIfNeeded()

        XCTAssertNil(harness.store.binding)
        XCTAssertNil(harness.store.pendingRevocation)
        XCTAssertNil(harness.defaults.object(
            forKey: "gymapp.native-push.revocation-fence-binding.v1"
        ))
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)",
            "revoke:\(userA)"
        ])
    }

    func testAccountSwitchWaitsForDurablePriorOwnerMarkerBeforeRegistering() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x54, count: 32))
        let firstBecameActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(firstBecameActive)
        harness.store.failNextPendingRevocationSaves(count: 2)

        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(harness.backend.operations, ["register:\(userA)"])
        XCTAssertEqual(harness.store.binding?.userID, userA)
        XCTAssertNil(harness.store.pendingRevocation)
        XCTAssertEqual(harness.manager.status, .unavailable)

        await harness.manager.activateIfNeeded()
        let replacementBecameActive = await waitUntil {
            harness.store.binding?.userID == self.userB
                && harness.manager.status == .active
        }
        XCTAssertTrue(replacementBecameActive)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "register:\(userB)"
        ])
        XCTAssertNil(harness.store.pendingRevocation)
    }

    func testReplacementSaveAndRevokeFailuresKeepNewOwnerCleanupDurable() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x55, count: 32))
        let firstBecameActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(firstBecameActive)
        harness.store.failNextBindingSave()
        harness.backend.failNextRevoke()
        harness.backend.failNextRevoke()

        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        let replacementCleanupPersisted = await waitUntil {
            harness.store.pendingRevocation?.userID == self.userB
        }
        XCTAssertTrue(replacementCleanupPersisted)
        XCTAssertEqual(harness.store.pendingRevocation?.bindingID, bindingB)
        XCTAssertEqual(harness.store.binding?.userID, userA)
        XCTAssertEqual(harness.manager.status, .unavailable)

        await harness.manager.disable()
        XCTAssertFalse(harness.manager.isEnabled)
        XCTAssertEqual(harness.store.pendingRevocation?.userID, userB)

        let restarted = NativePushManager(
            auth: harness.auth,
            defaults: harness.defaults,
            store: harness.store,
            backend: harness.backend,
            system: harness.system,
            environment: .sandbox
        )
        XCTAssertEqual(restarted.status, .revocationPending)
        await restarted.activateIfNeeded()

        XCTAssertNil(harness.store.pendingRevocation)
        XCTAssertNil(harness.store.binding)
        XCTAssertFalse(restarted.isEnabled)
        XCTAssertEqual(restarted.status, .disabled)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "register:\(userB)",
            "revoke:\(userB)",
            "revoke:\(userB)",
            "revoke:\(userB)"
        ])
    }

    func testTransientBindingSaveFailureCanRetrySameTokenInSameProcess() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        let token = Data(repeating: 0x56, count: 32)
        harness.store.failNextBindingSave()
        await harness.manager.activateIfNeeded()

        harness.manager.didReceiveDeviceToken(token)
        let firstCleanupFinished = await waitUntil {
            harness.manager.status == .unavailable
                && harness.backend.operations == [
                    "register:\(self.userA)",
                    "revoke:\(self.userA)"
                ]
        }
        XCTAssertTrue(firstCleanupFinished)
        XCTAssertNil(harness.store.binding)
        XCTAssertNil(harness.store.pendingRevocation)

        await harness.manager.activateIfNeeded()
        let retryBecameActive = await waitUntil {
            harness.manager.status == .active
                && harness.store.binding?.userID == self.userA
        }

        XCTAssertTrue(retryBecameActive)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)",
            "register:\(userA)"
        ])
        XCTAssertEqual(harness.store.binding?.bindingID, bindingA)
    }

    func testRestoredOrphanFenceDoesNotPermanentlyBlockFreshRegistration() async throws {
        let suiteName = "NativePushOrphanFenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "gymapp.native-push.enabled.v1")
        defaults.set(
            bindingA.uuidString.lowercased(),
            forKey: "gymapp.native-push.revocation-fence-binding.v1"
        )
        let auth = AuthService(keychain: PushTestKeychain(), defaults: defaults)
        try auth.installSessionForTesting(cloudSession(userID: userA))
        let store = PushBindingMemoryStore(installationID: installationID)
        let backend = PushBackendFake(bindings: [userA: bindingA])
        let system = PushSystemFake(permission: .authorized)
        let manager = NativePushManager(
            auth: auth,
            defaults: defaults,
            store: store,
            backend: backend,
            system: system,
            environment: .sandbox
        )

        XCTAssertNotEqual(manager.status, .unavailable)
        XCTAssertNil(defaults.object(
            forKey: "gymapp.native-push.revocation-fence-binding.v1"
        ))
        let orphanDelivery = await manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(orphanDelivery, .noData)

        await manager.activateIfNeeded()
        manager.didReceiveDeviceToken(Data(repeating: 0x4f, count: 32))
        let active = await waitUntil { manager.status == .active }
        XCTAssertTrue(active)
        XCTAssertEqual(store.binding?.authSessionID, sessionA)
        XCTAssertEqual(backend.operations, ["register:\(userA)"])
    }

    func testUnprovenMixedBindingAndPendingStateStaysFencedUntilReplacementIsDurable() async throws {
        let suiteName = "NativePushMixedStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "gymapp.native-push.enabled.v1")
        let auth = AuthService(keychain: PushTestKeychain(), defaults: defaults)
        try auth.installSessionForTesting(cloudSession(userID: userA))
        let oldBinding = nativeBinding(
            userID: userA,
            authSessionID: sessionA,
            bindingID: bindingA,
            revision: 4
        )
        let unresolved = NativePushPendingRevocation(
            version: NativePushPendingRevocation.currentVersion,
            installationID: installationID,
            userID: userB,
            authSessionID: sessionB,
            bindingID: bindingB,
            registrationRevision: 3
        )
        let store = PushBindingMemoryStore(
            installationID: installationID,
            binding: oldBinding,
            pendingRevocation: unresolved
        )
        let backend = PushBackendFake(bindings: [
            userA: bindingA,
            userB: bindingB,
            userC: bindingC
        ])
        let system = PushSystemFake(permission: .authorized)
        let manager = NativePushManager(
            auth: auth,
            defaults: defaults,
            store: store,
            backend: backend,
            system: system,
            environment: .sandbox
        )

        XCTAssertEqual(store.pendingRevocation, unresolved)
        XCTAssertNotEqual(manager.status, .active)
        let fencedOutcome = await manager.handleRemoteNotification(
            socialPayload(bindingID: bindingA)
        )
        XCTAssertEqual(fencedOutcome, .noData)

        await manager.activateIfNeeded()
        manager.didReceiveDeviceToken(Data(repeating: 0x4d, count: 32))
        let replacementBecameActive = await waitUntil { manager.status == .active }
        XCTAssertTrue(replacementBecameActive)
        XCTAssertNil(store.pendingRevocation)
        XCTAssertEqual(store.binding?.supersededRevocationBindingID, bindingB)
        XCTAssertNil(defaults.object(
            forKey: "gymapp.native-push.revocation-fence-binding.v1"
        ))
        XCTAssertEqual(backend.operations, ["register:\(userA)"])
    }

    func testLegacyV1BindingIsNeverReactivatedAndIsReplacedBySessionBoundV2() async throws {
        let suiteName = "NativePushLegacyBindingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "gymapp.native-push.enabled.v1")
        let keychain = PushTestKeychain()
        try saveLegacyBinding(to: keychain)
        let auth = AuthService(keychain: PushTestKeychain(), defaults: defaults)
        try auth.installSessionForTesting(cloudSession(userID: userA))
        let store = NativePushBindingStore(keychain: keychain)
        let backend = PushBackendFake(bindings: [userA: bindingA])
        let system = PushSystemFake(permission: .authorized)
        let manager = NativePushManager(
            auth: auth,
            defaults: defaults,
            store: store,
            backend: backend,
            system: system,
            environment: .sandbox
        )

        XCTAssertNotEqual(manager.status, .active)
        XCTAssertNil(try store.loadBinding())
        XCTAssertNotNil(try store.loadLegacyBinding())
        await manager.activateIfNeeded()
        XCTAssertNil(try store.loadLegacyBinding())
        manager.didReceiveDeviceToken(Data(repeating: 0x4e, count: 32))
        let replacementBecameActive = await waitUntil { manager.status == .active }
        XCTAssertTrue(replacementBecameActive)
        let upgraded = try XCTUnwrap(store.loadBinding())
        XCTAssertEqual(upgraded.version, NativePushBinding.currentVersion)
        XCTAssertEqual(upgraded.authSessionID, sessionA)
        XCTAssertNil(upgraded.supersededRevocationBindingID)
        XCTAssertEqual(backend.operations, ["revoke:\(userA)", "register:\(userA)"])
    }

    func testDisabledLegacyV1UpgradeRevokesWithoutReactivation() async throws {
        let suiteName = "NativePushDisabledLegacyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "gymapp.native-push.enabled.v1")
        let keychain = PushTestKeychain()
        try saveLegacyBinding(to: keychain)
        let auth = AuthService(keychain: PushTestKeychain(), defaults: defaults)
        try auth.installSessionForTesting(cloudSession(userID: userA))
        let store = NativePushBindingStore(keychain: keychain)
        let backend = PushBackendFake(bindings: [userA: bindingA])
        let system = PushSystemFake(permission: .authorized)
        let manager = NativePushManager(
            auth: auth,
            defaults: defaults,
            store: store,
            backend: backend,
            system: system,
            environment: .sandbox
        )

        XCTAssertEqual(manager.status, .revocationPending)
        XCTAssertNotNil(try store.loadLegacyBinding())
        await manager.activateIfNeeded()

        XCTAssertEqual(manager.status, .disabled)
        XCTAssertNil(try store.loadLegacyBinding())
        XCTAssertNil(defaults.object(
            forKey: "gymapp.native-push.revocation-fence-binding.v1"
        ))
        XCTAssertEqual(backend.operations, ["revoke:\(userA)"])
        XCTAssertEqual(system.registerCallCount, 0)
    }

    func testRestartTreatsDurableReplacementMarkerAsAuthoritativeOverStaleLegacySource() async throws {
        let suiteName = "NativePushLegacyReplacementRestartTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "gymapp.native-push.enabled.v1")
        defaults.set(
            bindingA.uuidString.lowercased(),
            forKey: "gymapp.native-push.revocation-fence-binding.v1"
        )
        let keychain = PushTestKeychain()
        try saveLegacyBinding(to: keychain)
        let store = NativePushBindingStore(keychain: keychain)
        let replacement = NativePushPendingRevocation(
            version: NativePushPendingRevocation.currentVersion,
            installationID: installationID,
            userID: userB,
            authSessionID: sessionB,
            bindingID: bindingB,
            registrationRevision: 1
        )
        try store.savePendingRevocation(replacement)
        let auth = AuthService(keychain: PushTestKeychain(), defaults: defaults)
        try auth.installSessionForTesting(cloudSession(userID: userB))
        let backend = PushBackendFake(bindings: [userB: bindingB])
        let system = PushSystemFake(permission: .authorized)

        let restarted = NativePushManager(
            auth: auth,
            defaults: defaults,
            store: store,
            backend: backend,
            system: system,
            environment: .sandbox
        )

        XCTAssertEqual(restarted.status, .revocationPending)
        XCTAssertEqual(try store.loadPendingRevocation(), replacement)
        XCTAssertNotNil(try store.loadLegacyBinding())
        XCTAssertEqual(
            defaults.string(forKey: "gymapp.native-push.revocation-fence-binding.v1"),
            bindingB.uuidString.lowercased()
        )
        let fencedOutcome = await restarted.handleRemoteNotification(
            socialPayload(bindingID: bindingB)
        )
        XCTAssertEqual(fencedOutcome, .noData)

        await restarted.activateIfNeeded()

        XCTAssertEqual(restarted.status, .disabled)
        XCTAssertNil(try store.loadPendingRevocation())
        XCTAssertNil(try store.loadLegacyBinding())
        XCTAssertNil(defaults.object(
            forKey: "gymapp.native-push.revocation-fence-binding.v1"
        ))
        XCTAssertEqual(backend.operations, ["revoke:\(userB)"])
        XCTAssertEqual(system.registerCallCount, 0)
    }

    func testSameUserNewAuthSessionRevokesOldBindingBeforeReregistering() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x49, count: 32))
        let firstActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(firstActive)
        let replacementSession = "50000000-0000-4000-8000-000000000005"

        try harness.auth.installSessionForTesting(
            cloudSession(userID: userA, authSessionID: replacementSession)
        )
        let secondActive = await waitUntil {
            harness.store.binding?.authSessionID == replacementSession
                && harness.manager.status == .active
        }
        XCTAssertTrue(secondActive)
        XCTAssertNil(harness.store.pendingRevocation)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)",
            "register:\(userA)"
        ])
    }

    func testAccountSwitchDuringRevokeCannotApplyOldCompletionToNewOwner() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x4a, count: 32))
        let firstActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(firstActive)
        harness.backend.suspendNextRevoke()

        let ending = Task { @MainActor in
            await harness.manager.prepareForSessionEnd(expectedUserID: self.userA)
        }
        let revokeStarted = await waitUntil {
            harness.backend.operations.last == "revoke:\(self.userA)"
        }
        XCTAssertTrue(revokeStarted)
        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        harness.backend.resumeSuspendedRevoke()
        await ending.value

        let newOwnerRequestedToken = await waitUntil {
            harness.system.registerCallCount >= 2
        }
        XCTAssertTrue(newOwnerRequestedToken)
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x4b, count: 32))
        let secondActive = await waitUntil {
            harness.store.binding?.userID == self.userB
                && harness.manager.status == .active
        }
        XCTAssertTrue(secondActive)
        XCTAssertNil(harness.store.pendingRevocation)
        XCTAssertEqual(harness.store.binding?.authSessionID, sessionB)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)",
            "register:\(userB)"
        ])
    }

    func testSessionEndGlobalCleanupFinishesBeforeReplacementOwnerActivates() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x51, count: 32))
        let firstActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(firstActive)
        harness.system.suspendNextRemoveAll()

        let ending = Task { @MainActor in
            await harness.manager.prepareForSessionEnd(expectedUserID: self.userA)
        }
        let cleanupStarted = await waitUntil { harness.system.removeAllIsSuspended }
        XCTAssertTrue(cleanupStarted)
        try harness.auth.installSessionForTesting(cloudSession(userID: userB))

        let activatedBeforeCleanup = await waitUntil(timeout: .milliseconds(100)) {
            harness.store.binding?.userID == self.userB
        }
        XCTAssertFalse(activatedBeforeCleanup)
        harness.system.resumeSuspendedRemoveAll()
        await ending.value

        let replacementRequestedToken = await waitUntil {
            harness.system.registerCallCount >= 2
        }
        XCTAssertTrue(replacementRequestedToken)
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x52, count: 32))

        let replacementActive = await waitUntil {
            harness.store.binding?.userID == self.userB
                && harness.manager.status == .active
        }
        XCTAssertTrue(replacementActive)
        let outcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingB)
        )
        XCTAssertEqual(outcome, .newData)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(harness.system.scheduled.count, 1)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "register:\(userB)"
        ])
    }

    func testAccountSwitchDuringInFlightRegisterCannotLeaveOldOwnerLast() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        harness.backend.suspendRegistration(for: userA)
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x44, count: 32))
        let firstStarted = await waitUntil {
            harness.backend.operations == ["register:\(self.userA)"]
        }
        XCTAssertTrue(firstStarted)

        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        XCTAssertEqual(harness.backend.operations, ["register:\(userA)"])
        harness.backend.resumeSuspendedRegistration()

        let switched = await waitUntil {
            harness.store.binding?.userID == self.userB
                && harness.manager.status == .active
        }
        XCTAssertTrue(switched)
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "register:\(userB)"
        ])
        XCTAssertEqual(harness.store.binding?.bindingID, bindingB)
    }

    func testAccountSwitchDuringLocalSchedulingRemovesLateNotification() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x45, count: 32))
        let active = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(active)
        harness.system.suspendNextSchedule()

        let delivery = Task { @MainActor in
            await harness.manager.handleRemoteNotification(
                self.socialPayload(bindingID: self.bindingA)
            )
        }
        let schedulingStarted = await waitUntil { harness.system.scheduleIsSuspended }
        XCTAssertTrue(schedulingStarted)
        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        harness.system.resumeSuspendedSchedule()

        let outcome = await delivery.value
        XCTAssertEqual(outcome, .noData)
        XCTAssertTrue(harness.system.scheduled.isEmpty)
    }

    func testRapidAccountSwitchSerializesGlobalCleanupBeforeNewestOwnerActivates() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x50, count: 32))
        let firstActive = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(firstActive)
        harness.system.suspendNextRemoveAll()

        try harness.auth.installSessionForTesting(cloudSession(userID: userB))
        let oldCleanupStarted = await waitUntil { harness.system.removeAllIsSuspended }
        XCTAssertTrue(oldCleanupStarted)
        try harness.auth.installSessionForTesting(cloudSession(userID: userC))

        let activatedBeforeOldCleanup = await waitUntil(timeout: .milliseconds(100)) {
            harness.store.binding?.userID == self.userC
        }
        XCTAssertFalse(activatedBeforeOldCleanup)
        XCTAssertEqual(harness.backend.operations, ["register:\(userA)"])

        harness.system.resumeSuspendedRemoveAll()
        let newestOwnerActive = await waitUntil {
            harness.store.binding?.userID == self.userC
                && harness.manager.status == .active
        }
        XCTAssertTrue(
            newestOwnerActive,
            "status=\(harness.manager.status) operations=\(harness.backend.operations) "
                + "binding=\(String(describing: harness.store.binding)) "
                + "pending=\(String(describing: harness.store.pendingRevocation))"
        )
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "register:\(userC)"
        ])

        let outcome = await harness.manager.handleRemoteNotification(
            socialPayload(bindingID: bindingC)
        )
        XCTAssertEqual(outcome, .newData)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(harness.system.scheduled.count, 1)
    }

    func testSessionEndLatchPreventsForegroundReactivationBeforeLogout() async throws {
        let harness = try makeHarness(userID: userA)
        defer { harness.cleanup() }
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x46, count: 32))
        let active = await waitUntil { harness.manager.status == .active }
        XCTAssertTrue(active)
        harness.backend.suspendNextRevoke()

        let ending = Task { @MainActor in
            await harness.manager.prepareForSessionEnd(expectedUserID: self.userA)
        }
        let revokeStarted = await waitUntil {
            harness.backend.operations.last == "revoke:\(self.userA)"
        }
        XCTAssertTrue(revokeStarted)
        await harness.manager.activateIfNeeded()
        harness.manager.didReceiveDeviceToken(Data(repeating: 0x46, count: 32))
        harness.backend.resumeSuspendedRevoke()
        await ending.value

        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(harness.backend.operations, [
            "register:\(userA)",
            "revoke:\(userA)"
        ])
        XCTAssertNil(harness.store.binding)
    }

    func testSupabaseBackendUsesExactBoundedRegisterAndRevokeContracts() async throws {
        let suiteName = "NativePushBackendTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativePushURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer {
            NativePushURLProtocolStub.handler = nil
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let auth = AuthService(
            keychain: PushTestKeychain(),
            urlSession: session,
            defaults: defaults
        )
        try auth.installSessionForTesting(cloudSession(userID: userA))
        let requests = PushRequestRecorder()
        NativePushURLProtocolStub.handler = { request in
            requests.append(request)
            let body: String
            switch request.url?.path {
            case "/rest/v1/rpc/notification_register_installation":
                body = """
                {"version":1,"installationId":"\(self.installationID.uuidString.lowercased())","provider":"apns","environment":"sandbox","bindingId":"\(self.bindingA.uuidString.lowercased())","registrationRevision":3,"registeredAt":"2026-08-10T08:00:00Z"}
                """
            case "/rest/v1/rpc/notification_revoke_installation":
                body = """
                {"version":1,"installationId":"\(self.installationID.uuidString.lowercased())","revoked":true}
                """
            default:
                body = #"{"message":"not found"}"#
            }
            let status = request.url?.path.hasPrefix("/rest/v1/rpc/notification_") == true
                ? 200
                : 404
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            return (response, Data(body.utf8))
        }

        let client = SupabaseNativePushBackendClient(auth: auth, urlSession: session)
        let registered = try await client.register(
            installationID: installationID,
            environment: .sandbox,
            token: String(repeating: "ab", count: 32),
            locale: "en-US",
            appVersion: "3.0.4",
            expectedUserID: userA
        )
        XCTAssertEqual(registered.bindingID, bindingA)
        try await client.revoke(installationID: installationID, expectedUserID: userA)

        XCTAssertEqual(requests.requests.map { $0.url?.path }, [
            "/rest/v1/rpc/notification_register_installation",
            "/rest/v1/rpc/notification_revoke_installation"
        ])
        XCTAssertTrue(requests.requests.allSatisfy { request in
            request.httpMethod == "POST"
                && request.value(forHTTPHeaderField: "apikey") ==
                    GymAppConfiguration.supabasePublishableKey
                && request.value(forHTTPHeaderField: "Authorization") ==
                    "Bearer \(self.accessToken(sessionID: self.sessionA))"
        })
        let registerBody = try requestObject(requests.requests[0])
        XCTAssertEqual(Set(registerBody.keys), [
            "p_installation_id", "p_platform", "p_provider", "p_environment",
            "p_provider_token", "p_web_push_p256dh", "p_web_push_auth", "p_locale",
            "p_app_version"
        ])
        XCTAssertEqual(registerBody["p_platform"] as? String, "ios")
        XCTAssertEqual(registerBody["p_provider"] as? String, "apns")
        XCTAssertEqual(registerBody["p_environment"] as? String, "sandbox")
        XCTAssertTrue(registerBody["p_web_push_p256dh"] is NSNull)
        XCTAssertTrue(registerBody["p_web_push_auth"] is NSNull)
        XCTAssertEqual(
            Set(try requestObject(requests.requests[1]).keys),
            ["p_installation_id"]
        )
    }

    func testDeniedPermissionNeverRegistersOrStoresBinding() async throws {
        let harness = try makeHarness(userID: userA, enabled: false, permission: .denied)
        defer { harness.cleanup() }

        await harness.manager.enable()
        XCTAssertEqual(harness.manager.status, .denied)
        XCTAssertFalse(harness.manager.isEnabled)
        XCTAssertEqual(harness.system.registerCallCount, 0)
        XCTAssertNil(harness.store.binding)
        XCTAssertTrue(harness.backend.operations.isEmpty)
    }

    private func makeHarness(
        userID: String,
        enabled: Bool = true,
        permission: NativePushPermissionState = .authorized
    ) throws -> PushHarness {
        let suiteName = "NativePushTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(enabled, forKey: "gymapp.native-push.enabled.v1")
        let auth = AuthService(keychain: PushTestKeychain(), defaults: defaults)
        try auth.installSessionForTesting(cloudSession(userID: userID))
        let store = PushBindingMemoryStore(installationID: installationID)
        let backend = PushBackendFake(bindings: [
            userA: bindingA,
            userB: bindingB,
            userC: bindingC
        ])
        let system = PushSystemFake(permission: permission)
        let manager = NativePushManager(
            auth: auth,
            defaults: defaults,
            store: store,
            backend: backend,
            system: system,
            environment: .sandbox
        )
        return PushHarness(
            suiteName: suiteName,
            defaults: defaults,
            auth: auth,
            store: store,
            backend: backend,
            system: system,
            manager: manager
        )
    }

    private func saveLegacyBinding(to keychain: PushTestKeychain) throws {
        try keychain.save(
            Data(installationID.uuidString.lowercased().utf8),
            account: "native-push-installation-v1"
        )
        let legacy: [String: Any] = [
            "version": NativePushLegacyBinding.currentVersion,
            "installationID": installationID.uuidString.lowercased(),
            "userID": userA,
            "bindingID": bindingA.uuidString.lowercased(),
            "environment": "sandbox",
            "tokenDigest": String(repeating: "a", count: 64),
            "registrationRevision": 2
        ]
        try keychain.save(
            JSONSerialization.data(withJSONObject: legacy),
            account: "native-push-binding-v1"
        )
    }

    private func cloudSession(
        userID: String,
        authSessionID: String? = nil
    ) -> AppAccountSession {
        let resolvedSessionID = authSessionID ?? {
            switch userID {
            case userA: sessionA
            case userB: sessionB
            default: sessionC
            }
        }()
        return .cloud(CloudAccountSession(
            userID: userID,
            email: "push@example.invalid",
            displayName: "Push Tester",
            accessToken: accessToken(sessionID: resolvedSessionID),
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        ))
    }

    private func nativeBinding(
        userID: String,
        authSessionID: String,
        bindingID: UUID,
        revision: Int,
        supersededRevocationBindingID: UUID? = nil
    ) -> NativePushBinding {
        NativePushBinding(
            version: NativePushBinding.currentVersion,
            installationID: installationID,
            userID: userID,
            authSessionID: authSessionID,
            bindingID: bindingID,
            environment: .sandbox,
            tokenDigest: String(repeating: "a", count: 64),
            registrationRevision: revision,
            supersededRevocationBindingID: supersededRevocationBindingID
        )
    }

    private func accessToken(sessionID: String) -> String {
        let payload = Data("{\"session_id\":\"\(sessionID)\"}".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(payload).test-signature"
    }

    private func socialPayload(
        bindingID: UUID,
        type: String = "friend_request_received",
        revision: Int = 7
    ) -> [AnyHashable: Any] {
        [
            "aps": ["content-available": 1],
            "gymapp": [
                "version": 1,
                "bindingId": bindingID.uuidString.lowercased(),
                "type": type,
                "objectId": "f_0123456789abcdef0123456789abcdef",
                "objectRevision": revision
            ]
        ]
    }

    private func livePayload(
        bindingID: UUID,
        kind: String,
        revision: Int
    ) -> [AnyHashable: Any] {
        [
            "aps": ["content-available": 1],
            "gymapp": [
                "version": 1,
                "bindingId": bindingID.uuidString.lowercased(),
                "kind": kind,
                "roomId": "lr_0123456789abcdef0123456789abcdef",
                "roomRevision": revision
            ]
        ]
    }

    private func localTapPayload(
        bindingID: UUID,
        destination: NativePushDestination
    ) -> [AnyHashable: Any] {
        [
            "gymappLocal": [
                "version": 1,
                "bindingId": bindingID.uuidString.lowercased(),
                "destination": destination.rawValue
            ]
        ]
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func requestObject(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var result = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 1_024)
                if count < 0 { throw NativePushError.invalidResponse }
                if count == 0 { break }
                result.append(buffer, count: count)
            }
            data = result
        } else {
            throw NativePushError.invalidResponse
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
private struct PushHarness {
    let suiteName: String
    let defaults: UserDefaults
    let auth: AuthService
    let store: PushBindingMemoryStore
    let backend: PushBackendFake
    let system: PushSystemFake
    let manager: NativePushManager

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private final class PushTestKeychain: KeychainStoring {
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

private final class PushBindingMemoryStore: NativePushBindingStoring {
    let fixedInstallationID: UUID
    private(set) var binding: NativePushBinding?
    private(set) var pendingRevocation: NativePushPendingRevocation?
    private var deliveryScope: NativePushBinding?
    private var deliveryRecords: [(key: String, revision: Int)] = []
    private var pendingSaveFailuresRemaining = 0
    private var bindingSaveFailuresRemaining = 0

    init(
        installationID: UUID,
        binding: NativePushBinding? = nil,
        pendingRevocation: NativePushPendingRevocation? = nil
    ) {
        fixedInstallationID = installationID
        self.binding = binding
        self.pendingRevocation = pendingRevocation
    }

    func installationID() throws -> UUID { fixedInstallationID }
    func loadBinding() throws -> NativePushBinding? { binding }
    func loadLegacyBinding() throws -> NativePushLegacyBinding? { nil }
    func saveBinding(_ binding: NativePushBinding) throws {
        if bindingSaveFailuresRemaining > 0 {
            bindingSaveFailuresRemaining -= 1
            throw NativePushError.invalidState
        }
        if deliveryScope != binding {
            deliveryScope = nil
            deliveryRecords.removeAll()
        }
        self.binding = binding
    }
    func clearBinding() throws {
        binding = nil
        try clearDeliveryState()
    }
    func clearLegacyBinding(_ expected: NativePushLegacyBinding) throws -> Bool {
        true
    }
    func clearDeliveryState() throws {
        deliveryScope = nil
        deliveryRecords.removeAll()
    }
    func loadPendingRevocation() throws -> NativePushPendingRevocation? { pendingRevocation }
    func savePendingRevocation(_ pending: NativePushPendingRevocation) throws {
        if pendingSaveFailuresRemaining > 0 {
            pendingSaveFailuresRemaining -= 1
            throw NativePushError.invalidState
        }
        pendingRevocation = pending
    }
    func clearPendingRevocation(_ expected: NativePushPendingRevocation) throws -> Bool {
        guard let current = pendingRevocation else { return true }
        guard current == expected else { return false }
        pendingRevocation = nil
        return true
    }
    func failNextPendingRevocationSave() {
        failNextPendingRevocationSaves(count: 1)
    }
    func failNextPendingRevocationSaves(count: Int) {
        pendingSaveFailuresRemaining += count
    }
    func failNextBindingSave() {
        bindingSaveFailuresRemaining += 1
    }
    func canDisplay(
        _ event: NativePushRemoteEvent,
        binding: NativePushBinding
    ) throws -> Bool {
        bindDeliveryScope(binding)
        guard let current = deliveryRecords.first(where: {
            $0.key == event.deliveryKey
        })?.revision else {
            return true
        }
        return event.objectRevision > current
    }
    func commitDisplayed(
        _ event: NativePushRemoteEvent,
        binding: NativePushBinding
    ) throws -> Bool {
        bindDeliveryScope(binding)
        if let current = deliveryRecords.first(where: { $0.key == event.deliveryKey }),
           event.objectRevision <= current.revision {
            return false
        }
        deliveryRecords.removeAll { $0.key == event.deliveryKey }
        deliveryRecords.append((event.deliveryKey, event.objectRevision))
        if deliveryRecords.count > 128 {
            deliveryRecords.removeFirst(deliveryRecords.count - 128)
        }
        return true
    }

    private func bindDeliveryScope(_ binding: NativePushBinding) {
        guard deliveryScope != binding else { return }
        deliveryScope = binding
        deliveryRecords.removeAll()
    }
}

@MainActor
private final class PushBackendFake: NativePushBackendServing {
    private let bindings: [String: UUID]
    private(set) var operations: [String] = []
    private var suspendedUserID: String?
    private var suspendedContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendRevoke = false
    private var revokeContinuation: CheckedContinuation<Void, Never>?
    private var revokeFailuresRemaining = 0

    init(bindings: [String: UUID]) {
        self.bindings = bindings
    }

    func register(
        installationID: UUID,
        environment: NativePushEnvironment,
        token: String,
        locale: String?,
        appVersion: String?,
        expectedUserID: String
    ) async throws -> NativePushRegistrationResponse {
        operations.append("register:\(expectedUserID)")
        if suspendedUserID == expectedUserID {
            await withCheckedContinuation { continuation in
                suspendedContinuation = continuation
            }
            suspendedUserID = nil
        }
        guard let binding = bindings[expectedUserID], token.utf8.count == 64 else {
            throw NativePushError.invalidState
        }
        return NativePushRegistrationResponse(
            installationID: installationID,
            bindingID: binding,
            environment: environment,
            registrationRevision: operations.count
        )
    }

    func revoke(installationID: UUID, expectedUserID: String) async throws {
        operations.append("revoke:\(expectedUserID)")
        if shouldSuspendRevoke {
            shouldSuspendRevoke = false
            await withCheckedContinuation { continuation in
                revokeContinuation = continuation
            }
        }
        if revokeFailuresRemaining > 0 {
            revokeFailuresRemaining -= 1
            throw NativePushError.requestFailed
        }
    }

    func suspendRegistration(for userID: String) {
        suspendedUserID = userID
    }

    func resumeSuspendedRegistration() {
        suspendedContinuation?.resume()
        suspendedContinuation = nil
    }

    func suspendNextRevoke() {
        shouldSuspendRevoke = true
    }

    func failNextRevoke() {
        revokeFailuresRemaining += 1
    }

    func resumeSuspendedRevoke() {
        revokeContinuation?.resume()
        revokeContinuation = nil
    }
}

@MainActor
private final class PushSystemFake: NativePushSystemControlling {
    var permission: NativePushPermissionState
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var removeAllCallCount = 0
    private(set) var scheduleCallCount = 0
    private(set) var scheduled: [NativePushLocalNotification] = []
    private var scheduleContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendSchedule = false
    private var removeAllContinuation: CheckedContinuation<Void, Never>?
    private var shouldSuspendRemoveAll = false

    var scheduleIsSuspended: Bool { scheduleContinuation != nil }
    var removeAllIsSuspended: Bool { removeAllContinuation != nil }

    init(permission: NativePushPermissionState) {
        self.permission = permission
    }

    func configure() {}
    func permissionState() async -> NativePushPermissionState { permission }
    func requestPermission() async throws -> NativePushPermissionState { permission }
    func registerForRemoteNotifications() { registerCallCount += 1 }
    func unregisterForRemoteNotifications() { unregisterCallCount += 1 }
    func schedule(_ notification: NativePushLocalNotification) async throws {
        scheduleCallCount += 1
        if shouldSuspendSchedule {
            shouldSuspendSchedule = false
            await withCheckedContinuation { continuation in
                scheduleContinuation = continuation
            }
        }
        scheduled.removeAll { $0.identifier == notification.identifier }
        scheduled.append(notification)
    }
    func removeNotification(identifier: String) async {
        scheduled.removeAll { $0.identifier == identifier }
    }
    func removeAllAccountBoundNotifications() async {
        removeAllCallCount += 1
        if shouldSuspendRemoveAll {
            shouldSuspendRemoveAll = false
            await withCheckedContinuation { continuation in
                removeAllContinuation = continuation
            }
        }
        scheduled.removeAll()
    }


    func suspendNextSchedule() {
        shouldSuspendSchedule = true
    }

    func resumeSuspendedSchedule() {
        scheduleContinuation?.resume()
        scheduleContinuation = nil
    }

    func suspendNextRemoveAll() {
        shouldSuspendRemoveAll = true
    }

    func resumeSuspendedRemoveAll() {
        removeAllContinuation?.resume()
        removeAllContinuation = nil
    }
}

private final class PushRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { stored } }

    func append(_ request: URLRequest) {
        lock.withLock { stored.append(request) }
    }
}

private final class NativePushURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handler }
        do {
            guard let handler else { throw NativePushError.requestFailed }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
