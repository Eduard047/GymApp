import Foundation
import XCTest
@testable import GymApp

@MainActor
final class AppleAdsAttributionTests: XCTestCase {
    private let token = "TESTTOKENabc123+/=SYNTHETIC"
    private let userA = "11111111-1111-4111-8111-111111111111"
    private let userB = "22222222-2222-4222-8222-222222222222"

    private static let attributedBody = Data("""
    {"attribution":true,"orgId":40669820,"campaignId":542370539,"adGroupId":542317095,\
    "keywordId":87675432,"adId":542317136,"conversionType":"Download","claimType":"Click",\
    "countryOrRegion":"US","supplyPlacement":"APPSTORE_SEARCH_RESULTS",\
    "clickDate":"2026-11-16T09:00Z"}
    """.utf8)

    // MARK: Resolution

    func testResolvesAttributedInstallAndErasesTokenFromState() async throws {
        let harness = Harness(self)
        harness.stub.enqueue(.response(200, Self.attributedBody))

        await harness.service.resolveIfNeeded()

        let state = try XCTUnwrap(harness.storage.state)
        XCTAssertEqual(state.status, .resolved)
        XCTAssertNil(state.pendingToken)
        XCTAssertNil(state.tokenObtainedAt)
        XCTAssertEqual(
            state.attribution,
            try XCTUnwrap(decode("""
            {"attribution":true,"campaignId":542370539,"adGroupId":542317095,"keywordId":87675432,
            "adId":542317136,"conversionType":"Download","claimType":"Click","countryOrRegion":"US",
            "supplyPlacement":"APPSTORE_SEARCH_RESULTS"}
            """))
        )
        let request = try XCTUnwrap(harness.stub.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api-adservices.apple.com/api/v1/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/plain")
        XCTAssertEqual(request.bodyString, token)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(harness.tokenCalls.count, 1)
    }

    func testSearchMatchWithoutKeywordKeepsKeywordNil() async throws {
        let harness = Harness(self)
        harness.stub.enqueue(.response(200, Data("""
        {"attribution":true,"campaignId":1,"adGroupId":2,"conversionType":"Redownload","claimType":"Impression"}
        """.utf8)))

        await harness.service.resolveIfNeeded()

        let attribution = try XCTUnwrap(harness.storage.state?.attribution)
        XCTAssertEqual(attribution.campaignID, 1)
        XCTAssertNil(attribution.keywordID)
        XCTAssertNil(attribution.adID)
        XCTAssertEqual(attribution.conversionType, "Redownload")
        XCTAssertTrue(attribution.isValid)
    }

    func testOrganicResultIsKeptAsFalseAttribution() async throws {
        let harness = Harness(self)
        harness.stub.enqueue(.response(200, Data(#"{"attribution":false}"#.utf8)))

        await harness.service.resolveIfNeeded()

        XCTAssertEqual(harness.storage.state?.status, .resolved)
        XCTAssertEqual(harness.storage.state?.attribution, .organic)
    }

    func testUnknownDescriptiveValuesAreDroppedInsteadOfBlockingUpload() async throws {
        let harness = Harness(self)
        harness.stub.enqueue(.response(200, Data("""
        {"attribution":true,"campaignId":5,"adGroupId":6,"conversionType":"FutureKind",\
        "claimType":"Hover","countryOrRegion":"usa","supplyPlacement":"APPSTORE_NEW_TAB"}
        """.utf8)))

        await harness.service.resolveIfNeeded()

        let attribution = try XCTUnwrap(harness.storage.state?.attribution)
        XCTAssertNil(attribution.conversionType)
        XCTAssertNil(attribution.claimType)
        XCTAssertNil(attribution.countryOrRegion)
        XCTAssertNil(attribution.supplyPlacement)
        XCTAssertTrue(attribution.isValid)
    }

    func testMalformedAndOversizedResponsesAreRejectedAndTokenIsKept() async throws {
        let bodies: [Data] = [
            Data("{}".utf8),
            Data("not json".utf8),
            Data(#"{"attribution":"yes"}"#.utf8),
            Data(#"{"attribution":true}"#.utf8),
            Data(#"{"attribution":true,"campaignId":-4,"adGroupId":2}"#.utf8),
            Data(#"{"attribution":true,"campaignId":1.5,"adGroupId":2}"#.utf8),
            Data(#"{"attribution":true,"campaignId":"x","adGroupId":2}"#.utf8),
            Data(#"{"attribution":false,"padding":"\#(String(repeating: "a", count: 5_000))"}"#.utf8)
        ]
        for body in bodies {
            let harness = Harness(self)
            harness.stub.enqueue(.response(200, body))

            await harness.service.refresh()

            XCTAssertEqual(harness.storage.state?.status, .pendingResolution, String(decoding: body.prefix(60), as: UTF8.self))
            XCTAssertEqual(harness.storage.state?.pendingToken, token)
            XCTAssertTrue(harness.uploads.isEmpty)
        }
    }

    func testNotReadyRetriesThreeTimesFiveSecondsApartThenKeepsToken() async throws {
        let harness = Harness(self)
        for _ in 0..<4 { harness.stub.enqueue(.response(404, Data())) }

        await harness.service.resolveIfNeeded()

        XCTAssertEqual(harness.stub.requests.count, 4)
        XCTAssertEqual(harness.sleeper.durations, [.seconds(5), .seconds(5), .seconds(5)])
        XCTAssertEqual(harness.storage.state?.status, .pendingResolution)
        XCTAssertEqual(harness.storage.state?.pendingToken, token)
    }

    func testNotReadyThenSuccessResolvesWithinRetryBudget() async throws {
        let harness = Harness(self)
        harness.stub.enqueue(.response(404, Data()))
        harness.stub.enqueue(.response(404, Data()))
        harness.stub.enqueue(.response(200, Data(#"{"attribution":false}"#.utf8)))

        await harness.service.resolveIfNeeded()

        XCTAssertEqual(harness.stub.requests.count, 3)
        XCTAssertEqual(harness.sleeper.durations.count, 2)
        XCTAssertEqual(harness.storage.state?.status, .resolved)
    }

    func testBadTokenResponseDropsTheTokenAndNeverRetries() async throws {
        let harness = Harness(self)
        harness.stub.enqueue(.response(400, Data(#"{"error":"bad"}"#.utf8)))

        await harness.service.resolveIfNeeded()
        await harness.service.resolveIfNeeded()

        XCTAssertEqual(harness.storage.state?.status, .unavailable)
        XCTAssertNil(harness.storage.state?.pendingToken)
        XCTAssertEqual(harness.stub.requests.count, 1)
        XCTAssertTrue(harness.sleeper.durations.isEmpty)
    }

    func testServerErrorAndOfflinePersistTokenAndResumeOnNextLaunch() async throws {
        for failure in [StubReply.response(500, Data()), .failure(URLError(.notConnectedToInternet))] {
            let harness = Harness(self)
            harness.stub.enqueue(failure)

            await harness.service.resolveIfNeeded()

            XCTAssertEqual(harness.storage.state?.status, .pendingResolution)
            XCTAssertEqual(harness.storage.state?.pendingToken, token)
            XCTAssertTrue(harness.sleeper.durations.isEmpty)

            // Next launch/foreground: a fresh service over the same persisted state.
            harness.stub.enqueue(.response(200, Data(#"{"attribution":false}"#.utf8)))
            let relaunched = harness.makeService()
            await relaunched.refresh()

            XCTAssertEqual(harness.storage.state?.status, .resolved)
            XCTAssertNil(harness.storage.state?.pendingToken)
            XCTAssertEqual(harness.tokenCalls.count, 1, "the token must not be re-requested")
        }
    }

    func testPendingTokenOlderThan24HoursIsDiscardedWithoutNetwork() async throws {
        let harness = Harness(self)
        let seen = harness.clock.now.addingTimeInterval(-26 * 3_600)
        harness.storage.state = AppleAdsInstallState(
            installSeenAt: seen,
            status: .pendingResolution,
            pendingToken: token,
            tokenObtainedAt: harness.clock.now.addingTimeInterval(-24 * 3_600 - 1),
            attribution: nil
        )

        await harness.service.refresh()

        XCTAssertTrue(harness.stub.requests.isEmpty)
        XCTAssertEqual(harness.storage.state?.status, .unavailable)
        XCTAssertNil(harness.storage.state?.pendingToken)
        XCTAssertTrue(harness.uploads.isEmpty)
    }

    func testPendingTokenStillValidAt24HoursIsStillTried() async throws {
        let harness = Harness(self)
        harness.storage.state = AppleAdsInstallState(
            installSeenAt: harness.clock.now.addingTimeInterval(-24 * 3_600),
            status: .pendingResolution,
            pendingToken: token,
            tokenObtainedAt: harness.clock.now.addingTimeInterval(-24 * 3_600 + 60),
            attribution: nil
        )
        harness.stub.enqueue(.response(200, Data(#"{"attribution":false}"#.utf8)))

        await harness.service.resolveIfNeeded()

        XCTAssertEqual(harness.storage.state?.status, .resolved)
    }

    func testTokenWindowDoesNotExtendWhenTheClockMovesBack() async throws {
        let harness = Harness(self)
        harness.storage.state = AppleAdsInstallState(
            installSeenAt: harness.clock.now,
            status: .pendingResolution,
            pendingToken: token,
            tokenObtainedAt: harness.clock.now.addingTimeInterval(10 * 24 * 3_600),
            attribution: nil
        )
        harness.stub.enqueue(.response(500, Data()))

        await harness.service.resolveIfNeeded()

        let obtained = try XCTUnwrap(harness.storage.state?.tokenObtainedAt)
        XCTAssertLessThanOrEqual(obtained, harness.clock.now)
    }

    func testTokenUnavailableMarksInstallAndIsNeverRetried() async throws {
        let harness = Harness(self, tokenResult: .failure(URLError(.unknown)))

        await harness.service.refresh()
        await harness.makeService().refresh()

        XCTAssertEqual(harness.storage.state?.status, .unavailable)
        XCTAssertEqual(harness.tokenCalls.count, 1)
        XCTAssertTrue(harness.stub.requests.isEmpty)
        XCTAssertTrue(harness.uploads.isEmpty)
    }

    func testTokenIsRequestedOncePerInstall() async throws {
        let harness = Harness(self)
        harness.stub.enqueue(.response(200, Data(#"{"attribution":false}"#.utf8)))

        await harness.service.refresh()
        await harness.makeService().refresh()
        await harness.makeService().refresh()

        XCTAssertEqual(harness.tokenCalls.count, 1)
        XCTAssertEqual(harness.stub.requests.count, 1)
    }

    func testCorruptStateIsReplacedWithoutRequestingATokenAgain() async throws {
        let harness = Harness(self)
        harness.storage.loadError = AppleAdsAttributionStoreError.corrupt

        await harness.service.refresh()

        XCTAssertEqual(harness.storage.state?.status, .unavailable)
        XCTAssertTrue(harness.tokenCalls.isEmpty)
        XCTAssertTrue(harness.stub.requests.isEmpty)
    }

    // MARK: Upload

    func testUploadsExactlyOncePerInstallEvenWhenServerSaysAlreadyRecorded() async throws {
        for serverAnswer in [true, false] {
            let harness = Harness(self)
            harness.user.id = userA
            harness.uploadAnswer = serverAnswer
            harness.stub.enqueue(.response(200, Self.attributedBody))

            await harness.service.refresh()
            await harness.service.uploadIfReady()
            await harness.makeService().refresh()

            XCTAssertEqual(harness.uploads.count, 1)
            XCTAssertEqual(harness.uploads.first?.userID, userA)
            XCTAssertEqual(harness.uploads.first?.record.attribution.campaignID, 542370539)
            XCTAssertEqual(harness.storage.state?.status, .uploaded)
            XCTAssertNil(harness.storage.state?.attribution)
        }
    }

    func testOrganicResultIsUploadedAsFalseAttributionWithInstallTime() async throws {
        let harness = Harness(self)
        harness.user.id = userA
        harness.stub.enqueue(.response(200, Data(#"{"attribution":false}"#.utf8)))

        await harness.service.refresh()

        let record = try XCTUnwrap(harness.uploads.first?.record)
        XCTAssertEqual(record.attribution, .organic)
        XCTAssertEqual(record.installSeenAt, harness.clock.now)
    }

    func testNothingIsUploadedForLocalOnlyProfilesAndSignInUploadsLater() async throws {
        let harness = Harness(self)
        harness.user.id = nil
        harness.stub.enqueue(.response(200, Self.attributedBody))

        await harness.service.refresh()
        await harness.service.uploadIfReady()

        XCTAssertTrue(harness.uploads.isEmpty)
        XCTAssertEqual(harness.storage.state?.status, .resolved)

        harness.user.id = userA
        await harness.service.uploadIfReady()

        XCTAssertEqual(harness.uploads.map(\.userID), [userA])
        XCTAssertEqual(harness.storage.state?.status, .uploaded)
    }

    func testResolutionFinishingAfterSignInUploadsWithoutAnotherTrigger() async throws {
        let harness = Harness(self)
        harness.user.id = userA
        harness.stub.enqueue(.response(404, Data()))
        harness.stub.enqueue(.response(200, Self.attributedBody))

        await harness.service.refresh()

        XCTAssertEqual(harness.uploads.map(\.userID), [userA])
    }

    func testOnlyTheFirstCloudAccountUploads() async throws {
        let harness = Harness(self)
        harness.user.id = userA
        harness.stub.enqueue(.response(200, Self.attributedBody))
        await harness.service.refresh()

        harness.user.id = userB
        await harness.service.uploadIfReady()
        await harness.makeService().refresh()

        XCTAssertEqual(harness.uploads.map(\.userID), [userA])
    }

    func testAccountSwitchMidUploadNeverWritesForTheWrongAccount() async throws {
        let harness = Harness(self)
        harness.user.id = userA
        harness.stub.enqueue(.response(200, Data(#"{"attribution":false}"#.utf8)))
        harness.holdFirstUpload = true
        let resolution = Task { await harness.service.refresh() }
        await harness.waitUntilUploadIsSuspended()

        // The user switches accounts while A's request is in flight; the bound
        // uploader refuses to continue, and B's trigger is coalesced.
        harness.user.id = userB
        await harness.service.uploadIfReady()
        XCTAssertEqual(harness.uploads.map(\.userID), [userA], "no write may start for B while A's call is open")
        harness.resumeHeldUpload(throwing: AuthServiceError.sessionChanged)
        await resolution.value

        // A's call never confirmed, so nothing is marked done; B then uploads once.
        XCTAssertEqual(harness.uploads.map(\.userID), [userA, userB])
        XCTAssertEqual(harness.storage.state?.status, .uploaded)
        XCTAssertEqual(harness.confirmedUserIDs, [userB])
    }

    func testSessionChangedWithoutRetriggerKeepsResultPending() async throws {
        let harness = Harness(self)
        harness.user.id = userA
        harness.stub.enqueue(.response(200, Data(#"{"attribution":false}"#.utf8)))
        harness.uploadError = AuthServiceError.sessionChanged

        await harness.service.refresh()

        XCTAssertEqual(harness.uploads.map(\.userID), [userA])
        XCTAssertEqual(harness.storage.state?.status, .resolved)
        XCTAssertNotNil(harness.storage.state?.attribution)
    }

    func testTransientUploadFailureKeepsResultAndRetriesOnNextTrigger() async throws {
        let harness = Harness(self)
        harness.user.id = userA
        harness.stub.enqueue(.response(200, Self.attributedBody))
        harness.uploadError = URLError(.notConnectedToInternet)
        await harness.service.refresh()
        XCTAssertEqual(harness.storage.state?.status, .resolved)

        harness.uploadError = nil
        await harness.service.refresh()

        XCTAssertEqual(harness.uploads.count, 2)
        XCTAssertEqual(harness.storage.state?.status, .uploaded)
    }

    func testServerRejectionStopsRetryingAndDropsThePayload() async throws {
        let harness = Harness(self)
        harness.user.id = userA
        harness.stub.enqueue(.response(200, Self.attributedBody))
        harness.uploadError = AppleAdsAttributionUploadError.rejected

        await harness.service.refresh()
        await harness.service.refresh()

        XCTAssertEqual(harness.uploads.count, 1)
        XCTAssertEqual(harness.storage.state?.status, .unavailable)
        XCTAssertNil(harness.storage.state?.attribution)
    }

    // MARK: Persistence

    func testTokenIsOnDiskOnlyWhilePendingAndFileIsExcludedFromBackup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppleAdsAttributionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = FileAppleAdsAttributionStore(fileURL: file)
        let harness = Harness(self, storage: store)
        harness.stub.enqueue(.response(500, Data()))

        await harness.service.resolveIfNeeded()

        let pendingBytes = try Data(contentsOf: file)
        XCTAssertNotNil(String(data: pendingBytes, encoding: .utf8)?.range(of: token))
        let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)

        harness.stub.enqueue(.response(200, Self.attributedBody))
        await harness.service.resolveIfNeeded()

        let resolvedText = try String(contentsOf: file, encoding: .utf8)
        XCTAssertNil(resolvedText.range(of: token))
        XCTAssertFalse(resolvedText.contains("pendingToken\":\""))
        XCTAssertEqual(try store.load()?.status, .resolved)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testFileStoreRejectsInconsistentOrOversizedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppleAdsAttributionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        let store = FileAppleAdsAttributionStore(fileURL: file)
        XCTAssertNil(try store.load())

        try Data("{\"version\":1}".utf8).write(to: file)
        XCTAssertThrowsError(try store.load())

        try Data(repeating: 0x20, count: FileAppleAdsAttributionStore.maximumFileBytes + 1).write(to: file)
        XCTAssertThrowsError(try store.load())

        // A resolved state that still carries a token is inconsistent and rejected.
        let bad = AppleAdsInstallState(
            installSeenAt: Date(),
            status: .resolved,
            pendingToken: token,
            tokenObtainedAt: Date(),
            attribution: .organic
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(bad).write(to: file)
        XCTAssertThrowsError(try store.load())
    }

    // MARK: RPC adapter

    func testRecordAdAttributionRPCUsesAuthenticatedRestPatternAndExactParameters() async throws {
        let stub = AppleAdsURLStub()
        let session = stub.makeSession()
        let cloud = makeCloud(userID: userA, session: session)
        defer { session.invalidateAndCancel() }
        let installSeen = Date(timeIntervalSince1970: 1_790_000_000)
        let record = AppleAdsAttributionRecord(
            attribution: try XCTUnwrap(decode(#"{"attribution":true,"campaignId":9,"adGroupId":8,"keywordId":7,"conversionType":"Download","countryOrRegion":"UA"}"#)),
            installSeenAt: installSeen
        )
        stub.enqueue(.response(200, Data("true".utf8)))
        stub.enqueue(.response(200, Data("false".utf8)))

        let first = try await cloud.recordAdAttribution(record, expectedUserID: userA)
        let second = try await cloud.recordAdAttribution(record, expectedUserID: userA)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/rest/v1/rpc/record_ad_attribution")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "apikey"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(request.bodyData)) as? [String: Any]
        )
        XCTAssertEqual(
            Set(body.keys),
            [
                "p_attributed", "p_campaign_id", "p_ad_group_id", "p_keyword_id", "p_ad_id",
                "p_conversion_type", "p_claim_type", "p_country_or_region",
                "p_supply_placement", "p_install_seen_at"
            ]
        )
        XCTAssertEqual(body["p_attributed"] as? Bool, true)
        XCTAssertEqual(body["p_campaign_id"] as? Int, 9)
        XCTAssertEqual(body["p_keyword_id"] as? Int, 7)
        XCTAssertTrue(body["p_ad_id"] is NSNull)
        XCTAssertTrue(body["p_claim_type"] is NSNull)
        XCTAssertEqual(body["p_country_or_region"] as? String, "UA")
        XCTAssertEqual(body["p_install_seen_at"] as? String, "2026-09-21T14:13:20Z")
    }

    func testRecordAdAttributionRefusesAnotherAccountBeforeAnyRequest() async throws {
        let stub = AppleAdsURLStub()
        let session = stub.makeSession()
        let cloud = makeCloud(userID: userA, session: session)
        defer { session.invalidateAndCancel() }
        stub.enqueue(.response(200, Data("true".utf8)))
        let record = AppleAdsAttributionRecord(attribution: .organic, installSeenAt: Date())

        do {
            _ = try await cloud.recordAdAttribution(record, expectedUserID: userB)
            XCTFail("An upload bound to another account must not be sent.")
        } catch AuthServiceError.sessionChanged {
            // Expected.
        }
        XCTAssertTrue(stub.requests.isEmpty)
    }

    func testRecordAdAttributionClassifiesServerRefusalsAndTransientFailures() async throws {
        let stub = AppleAdsURLStub()
        let session = stub.makeSession()
        let cloud = makeCloud(userID: userA, session: session)
        defer { session.invalidateAndCancel() }
        let record = AppleAdsAttributionRecord(attribution: .organic, installSeenAt: Date())

        stub.enqueue(.response(400, Data(#"{"code":"23514","message":"check"}"#.utf8)))
        do {
            _ = try await cloud.recordAdAttribution(record, expectedUserID: userA)
            XCTFail("Expected a deterministic rejection.")
        } catch AppleAdsAttributionUploadError.rejected {
            // Expected.
        }

        for (status, body) in [
            (404, #"{"code":"PGRST202","message":"missing"}"#),
            (500, #"{"code":"XX000","message":"boom"}"#)
        ] {
            stub.enqueue(.response(status, Data(body.utf8)))
            do {
                _ = try await cloud.recordAdAttribution(record, expectedUserID: userA)
                XCTFail("Expected a failure for HTTP \(status).")
            } catch AppleAdsAttributionUploadError.rejected {
                XCTFail("HTTP \(status) is transient and must not drop the attribution.")
            } catch {
                // Expected: transient.
            }
        }

        stub.enqueue(.response(200, Data(#"{"unexpected":1}"#.utf8)))
        do {
            _ = try await cloud.recordAdAttribution(record, expectedUserID: userA)
            XCTFail("A non-boolean body is invalid.")
        } catch CloudSyncError.invalidResponse {
            // Expected.
        }
    }

    // MARK: Helpers

    private func decode(_ json: String) -> AppleAdsAttribution? {
        struct Wire: Decodable {
            let attribution: Bool
            let campaignId: Int64?
            let adGroupId: Int64?
            let keywordId: Int64?
            let adId: Int64?
            let conversionType: String?
            let claimType: String?
            let countryOrRegion: String?
            let supplyPlacement: String?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else { return nil }
        return AppleAdsAttribution(
            attributed: wire.attribution,
            campaignID: wire.campaignId,
            adGroupID: wire.adGroupId,
            keywordID: wire.keywordId,
            adID: wire.adId,
            conversionType: wire.conversionType,
            claimType: wire.claimType,
            countryOrRegion: wire.countryOrRegion,
            supplyPlacement: wire.supplyPlacement
        )
    }

    private func makeCloud(userID: String, session: URLSession) -> CloudSyncService {
        let suiteName = "GymAppTests.AppleAds.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let auth = AuthService(
            keychain: AppleAdsKeychainStore(),
            urlSession: session,
            defaults: defaults
        )
        try! auth.installSessionForTesting(
            .cloud(
                CloudAccountSession(
                    userID: userID,
                    email: "ads@example.com",
                    displayName: "Ads",
                    accessToken: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date().addingTimeInterval(3_600)
                )
            )
        )
        addTeardownBlock { try? auth.clearSession() }
        return CloudSyncService(auth: auth, urlSession: session)
    }
}

// MARK: - Harness

@MainActor
private final class UserBox {
    var id: String?
}

private final class AdsClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration] = []

    var durations: [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func sleep(_ duration: Duration) async throws {
        record(duration)
    }

    private func record(_ duration: Duration) {
        lock.lock()
        recorded.append(duration)
        lock.unlock()
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    var isEmpty: Bool { count == 0 }

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private final class MemoryAppleAdsStore: AppleAdsAttributionStoring {
    var state: AppleAdsInstallState?
    var loadError: Error?

    func load() throws -> AppleAdsInstallState? {
        if let loadError { throw loadError }
        return state
    }

    func save(_ state: AppleAdsInstallState) throws {
        precondition(state.isConsistent, "The service must only persist consistent states.")
        loadError = nil
        self.state = state
    }
}

@MainActor
private final class Harness {
    struct Upload {
        let record: AppleAdsAttributionRecord
        let userID: String
    }

    let stub = AppleAdsURLStub()
    let storage: MemoryAppleAdsStore
    private let backing: any AppleAdsAttributionStoring
    let clock = AdsClock(Date(timeIntervalSince1970: 1_790_000_000))
    let sleeper = SleepRecorder()
    let tokenCalls = CallCounter()
    let user = UserBox()
    private(set) var uploads: [Upload] = []
    private(set) var confirmedUserIDs: [String] = []
    var uploadAnswer = true
    var uploadError: Error?
    var holdFirstUpload = false
    private var heldContinuation: CheckedContinuation<Void, Error>?
    private var heldUploadUsed = false
    private let tokenResult: Result<String, Error>
    private let session: URLSession
    lazy var service: AppleAdsAttributionService = makeService()

    init(
        _ owner: XCTestCase,
        tokenResult: Result<String, Error> = .success("TESTTOKENabc123+/=SYNTHETIC"),
        storage: (any AppleAdsAttributionStoring)? = nil
    ) {
        let memory = MemoryAppleAdsStore()
        self.storage = memory
        self.backing = storage ?? memory
        self.tokenResult = tokenResult
        self.session = stub.makeSession()
        let session = self.session
        owner.addTeardownBlock { session.invalidateAndCancel() }
    }

    func makeService() -> AppleAdsAttributionService {
        let tokenCalls = self.tokenCalls
        let result = tokenResult
        let clock = self.clock
        let sleeper = self.sleeper
        return AppleAdsAttributionService(
            storage: backing,
            tokenProvider: {
                tokenCalls.increment()
                return try result.get()
            },
            urlSession: session,
            now: { clock.now },
            sleep: { try await sleeper.sleep($0) },
            currentCloudUserID: { [user] in user.id },
            upload: { [unowned self] record, userID in
                try await self.performUpload(record, userID: userID)
            }
        )
    }

    private func performUpload(_ record: AppleAdsAttributionRecord, userID: String) async throws -> Bool {
        uploads.append(Upload(record: record, userID: userID))
        if holdFirstUpload, !heldUploadUsed {
            heldUploadUsed = true
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                heldContinuation = continuation
            }
        }
        if let uploadError { throw uploadError }
        confirmedUserIDs.append(userID)
        return uploadAnswer
    }

    func waitUntilUploadIsSuspended() async {
        for _ in 0..<1_000 where heldContinuation == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func resumeHeldUpload(throwing error: Error) {
        heldContinuation?.resume(throwing: error)
        heldContinuation = nil
    }
}

// MARK: - URL stub

private enum StubReply {
    case response(Int, Data)
    case failure(Error)
}

private final class AppleAdsURLStub: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [StubReply] = []
    private var recorded: [URLRequest] = []
    let id = UUID().uuidString

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func enqueue(_ reply: StubReply) {
        lock.lock()
        replies.append(reply)
        lock.unlock()
        AppleAdsURLProtocol.register(self)
    }

    func makeSession() -> URLSession {
        AppleAdsURLProtocol.register(self)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppleAdsURLProtocol.self]
        configuration.httpAdditionalHeaders = [AppleAdsURLProtocol.stubHeader: id]
        return URLSession(configuration: configuration)
    }

    fileprivate func next(for request: URLRequest) -> StubReply {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        return replies.isEmpty ? .failure(URLError(.unsupportedURL)) : replies.removeFirst()
    }
}

private final class AppleAdsURLProtocol: URLProtocol, @unchecked Sendable {
    static let stubHeader = "X-Apple-Ads-Test-Stub"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: AppleAdsURLStub] = [:]

    static func register(_ stub: AppleAdsURLStub) {
        lock.lock()
        stubs[stub.id] = stub
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.stubHeader) ?? ""
        Self.lock.lock()
        let stub = Self.stubs[id]
        Self.lock.unlock()
        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        var materialized = request
        let body = request.bodyData
        materialized.httpBodyStream = nil
        materialized.httpBody = body
        switch stub.next(for: materialized) {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .response(let status, let data):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    var bodyString: String? {
        bodyData.flatMap { String(data: $0, encoding: .utf8) }
    }
}

private final class AppleAdsKeychainStore: KeychainStoring {
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
