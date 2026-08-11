import Foundation
import XCTest
@testable import GymApp

@MainActor
final class SocialContractTests: XCTestCase {
    func testShortFriendCodeParserIsExactAndBounded() throws {
        let code = try SocialPayloadParser.friendCode(from: jsonData([
            "version": 1,
            "friendCode": "g_a1b2c3d4e5f6"
        ]))
        XCTAssertEqual(code, "g_a1b2c3d4e5f6")

        XCTAssertThrowsError(try SocialPayloadParser.friendCode(from: jsonData([
            "version": 1,
            "friendCode": "g_a1b2c3d4e5f6",
            "profileId": profileID(1)
        ])))
        XCTAssertThrowsError(try SocialPayloadParser.friendCode(from: jsonData([
            "version": true,
            "friendCode": "g_a1b2c3d4e5f6"
        ])))
        XCTAssertThrowsError(try SocialPayloadParser.friendCode(from: jsonData([
            "version": 1,
            "friendCode": "g_A1B2C3D4E5F6"
        ])))
        XCTAssertThrowsError(try SocialPayloadParser.friendCode(from: jsonData([
            "version": 1,
            "friendCode": profileID(1)
        ])))
        XCTAssertThrowsError(try SocialPayloadParser.friendCode(from: Data(
            repeating: UInt8(ascii: " "),
            count: SocialPayloadParser.maximumFriendCodeResponseBytes + 1
        )))
    }

    func testFriendCodeNormalizerAcceptsShortDisplayAndLegacyFormats() {
        XCTAssertEqual(
            SocialFriendCode.normalize("g_a1b2c3d4e5f6"),
            "g_a1b2c3d4e5f6"
        )
        XCTAssertEqual(
            SocialFriendCode.normalize(" G_A1B2C3D4E5F6 "),
            "g_a1b2c3d4e5f6"
        )
        XCTAssertEqual(
            SocialFriendCode.normalize("  GYM-A1B2-C3D4-E5F6\n"),
            "g_a1b2c3d4e5f6"
        )
        XCTAssertEqual(
            SocialFriendCode.normalize("gym-a1b2-c3d4-e5f6"),
            "g_a1b2c3d4e5f6"
        )
        let legacyCode = "p_abcdefabcdefabcdefabcdefabcdefab"
        XCTAssertEqual(SocialFriendCode.normalize(profileID(2)), profileID(2))
        XCTAssertEqual(SocialFriendCode.normalize(legacyCode.uppercased()), legacyCode)
        XCTAssertEqual(
            SocialFriendCode.display("g_a1b2c3d4e5f6"),
            "GYM-A1B2-C3D4-E5F6"
        )
        XCTAssertEqual(SocialFriendCode.display(profileID(2)), profileID(2))

        XCTAssertNil(SocialFriendCode.normalize("g_a1b2c3d4e5f"))
        XCTAssertNil(SocialFriendCode.normalize("GYM-A1B2-C3D4-E5FG"))
        XCTAssertNil(SocialFriendCode.normalize("GYM-A1B2-C3D4-E5F6-extra"))
        XCTAssertNil(SocialFriendCode.normalize(String(repeating: "a", count: 65)))
    }

    func testDashboardParserAcceptsV1AndRejectsUnknownPrivateAndOversizedData() throws {
        let dashboard = try SocialPayloadParser.dashboard(from: jsonData(dashboardObject()))

        XCTAssertEqual(dashboard.currentUser.friendCode, profileID(1))
        XCTAssertEqual(dashboard.friends.map(\.profileID), [profileID(2)])
        XCTAssertEqual(dashboard.incoming.map(\.profileID), [profileID(3)])
        XCTAssertEqual(dashboard.outgoing.map(\.profileID), [profileID(4)])
        XCTAssertEqual(dashboard.blocked.map(\.profileID), [profileID(5)])
        XCTAssertEqual(dashboard.pendingWorkoutInviteCount, 1)

        var unknownKey = dashboardObject()
        unknownKey["email"] = "private@example.com"
        XCTAssertThrowsError(try SocialPayloadParser.dashboard(from: jsonData(unknownKey)))

        var privateStats = dashboardObject()
        var currentUser = try XCTUnwrap(privateStats["self"] as? [String: Any])
        currentUser["statsAvailable"] = false
        currentUser["xp"] = 1
        currentUser["level"] = NSNull()
        currentUser["workouts"] = NSNull()
        currentUser["progressUpdatedAt"] = NSNull()
        privateStats["self"] = currentUser
        XCTAssertThrowsError(try SocialPayloadParser.dashboard(from: jsonData(privateStats)))

        let oversized = Data(
            repeating: UInt8(ascii: " "),
            count: SocialPayloadParser.maximumResponseBytes + 1
        )
        XCTAssertThrowsError(try SocialPayloadParser.dashboard(from: oversized))
    }

    func testDashboardParserEnforcesCollectionAndIntegerBounds() throws {
        var tooManyFriends = dashboardObject()
        tooManyFriends["incoming"] = []
        tooManyFriends["outgoing"] = []
        tooManyFriends["blocked"] = []
        tooManyFriends["friends"] = (0 ... 200).map { index in
            friendObject(index: index + 2)
        }
        XCTAssertThrowsError(try SocialPayloadParser.dashboard(from: jsonData(tooManyFriends)))

        var excessiveXP = dashboardObject()
        var currentUser = try XCTUnwrap(excessiveXP["self"] as? [String: Any])
        currentUser["xp"] = 2_147_483_648 as Int64
        excessiveXP["self"] = currentUser
        XCTAssertThrowsError(try SocialPayloadParser.dashboard(from: jsonData(excessiveXP)))
    }

    func testFriendDetailsAreSelfReportedBoundedAndPrivacyConsistent() throws {
        let details = try SocialPayloadParser.friendDetails(from: jsonData(friendDetailsObject()))

        XCTAssertEqual(details.friend.profileID, profileID(2))
        XCTAssertEqual(details.recentWorkouts.count, 1)
        XCTAssertEqual(details.exerciseRecords.count, 1)
        XCTAssertEqual(details.exerciseRecords.first?.bestWeightKg, 140)
        XCTAssertEqual(details.exerciseRecords.first?.bestReps, 18)

        var sameDaySessions = friendDetailsObject()
        var workouts = try XCTUnwrap(sameDaySessions["recentWorkouts"] as? [[String: Any]])
        var laterSession = try XCTUnwrap(workouts.first)
        laterSession["exerciseCount"] = 2
        laterSession["setCount"] = 5
        laterSession["exercises"] = [
            ["catalogKey": "squat", "name": "Squat"],
            ["catalogKey": "plank", "name": "Plank"]
        ]
        workouts.append(laterSession)
        sameDaySessions["recentWorkouts"] = workouts
        let parsedSameDay = try SocialPayloadParser.friendDetails(from: jsonData(sameDaySessions))
        XCTAssertEqual(parsedSameDay.recentWorkouts.map(\.workoutDay), ["2026-08-09", "2026-08-09"])
        XCTAssertEqual(Set(socialRecentWorkoutRows(parsedSameDay.recentWorkouts).map(\.id)).count, 2)

        var incompleteExercisePreview = friendDetailsObject()
        var incompleteWorkouts = try XCTUnwrap(
            incompleteExercisePreview["recentWorkouts"] as? [[String: Any]]
        )
        incompleteWorkouts[0]["exerciseCount"] = 2
        incompleteExercisePreview["recentWorkouts"] = incompleteWorkouts
        XCTAssertThrowsError(
            try SocialPayloadParser.friendDetails(from: jsonData(incompleteExercisePreview))
        )

        var nonBreakingSpaceName = friendDetailsObject()
        var nonBreakingWorkouts = try XCTUnwrap(
            nonBreakingSpaceName["recentWorkouts"] as? [[String: Any]]
        )
        nonBreakingWorkouts[0]["exercises"] = [[
            "catalogKey": NSNull(),
            "name": "Incline\u{00A0}press"
        ]]
        nonBreakingSpaceName["recentWorkouts"] = nonBreakingWorkouts
        var nonBreakingRecords = try XCTUnwrap(
            nonBreakingSpaceName["exerciseRecords"] as? [[String: Any]]
        )
        nonBreakingRecords[0]["catalogKey"] = NSNull()
        nonBreakingRecords[0]["name"] = "Incline\u{00A0}press"
        nonBreakingSpaceName["exerciseRecords"] = nonBreakingRecords
        let parsedNonBreakingName = try SocialPayloadParser.friendDetails(
            from: jsonData(nonBreakingSpaceName)
        )
        XCTAssertEqual(
            parsedNonBreakingName.recentWorkouts.first?.exercises.first?.name,
            "Incline\u{00A0}press"
        )

        let record = try XCTUnwrap(details.exerciseRecords.first)
        let labels = socialRecordMetricLabels(record, languageCode: AppLanguage.english.rawValue)
        // The source sessions can be 140 kg x 2 and 60 kg x 18. The aggregate maxima
        // are independent and must never be presented as a fictitious 140 kg x 18 set.
        XCTAssertEqual(labels.maximumWeight, "Max weight: 140 kg")
        XCTAssertEqual(labels.maximumRepetitions, "Max reps: 18")
        XCTAssertFalse(labels.maximumWeight.contains("×"))
        XCTAssertFalse(labels.maximumRepetitions.contains("×"))

        var wrongIntegrity = friendDetailsObject()
        wrongIntegrity["integrity"] = "verified"
        XCTAssertThrowsError(try SocialPayloadParser.friendDetails(from: jsonData(wrongIntegrity)))

        var privateActivity = friendDetailsObject()
        privateActivity["sharing"] = [
            "progress": true,
            "recentWorkouts": false,
            "records": true
        ]
        XCTAssertThrowsError(try SocialPayloadParser.friendDetails(from: jsonData(privateActivity)))

        var missingActivityRevision = friendDetailsObject()
        missingActivityRevision["activityUpdatedAt"] = NSNull()
        XCTAssertThrowsError(
            try SocialPayloadParser.friendDetails(from: jsonData(missingActivityRevision))
        )

        var revisionWithoutSharedActivity = friendDetailsObject()
        revisionWithoutSharedActivity["sharing"] = [
            "progress": true,
            "recentWorkouts": false,
            "records": false
        ]
        revisionWithoutSharedActivity["recentWorkouts"] = []
        revisionWithoutSharedActivity["exerciseRecords"] = []
        XCTAssertThrowsError(
            try SocialPayloadParser.friendDetails(from: jsonData(revisionWithoutSharedActivity))
        )

        var temporarilyUnavailable = friendDetailsObject()
        temporarilyUnavailable["activityUpdatedAt"] = NSNull()
        temporarilyUnavailable["recentWorkouts"] = []
        temporarilyUnavailable["exerciseRecords"] = []
        let unavailable = try SocialPayloadParser.friendDetails(
            from: jsonData(temporarilyUnavailable)
        )
        XCTAssertEqual(
            socialActivityPresentationState(
                isShared: unavailable.sharing.recentWorkouts,
                activityUpdatedAt: unavailable.activityUpdatedAt,
                itemCount: unavailable.recentWorkouts.count
            ),
            .temporarilyUnavailable
        )
        XCTAssertEqual(
            socialActivityPresentationState(
                isShared: unavailable.sharing.records,
                activityUpdatedAt: unavailable.activityUpdatedAt,
                itemCount: unavailable.exerciseRecords.count
            ),
            .temporarilyUnavailable
        )
    }

    func testWorkoutInboxRequiresExactCanonicalPayloadAndSummary() throws {
        let inbox = try SocialPayloadParser.workoutInbox(from: jsonData(workoutInboxObject()))

        XCTAssertEqual(inbox.pendingIncomingCount, 1)
        XCTAssertEqual(inbox.incoming.first?.workout?.totalSetCount, 2)
        XCTAssertNil(inbox.outgoing.first?.workout)

        let edgeNonBreakingSpaceName = "\u{00A0}Bench press\u{00A0}"
        var nonBreakingSpaceName = workoutInboxObject()
        var nonBreakingIncoming = try XCTUnwrap(
            nonBreakingSpaceName["incoming"] as? [[String: Any]]
        )
        var nonBreakingInvite = try XCTUnwrap(nonBreakingIncoming.first)
        var nonBreakingWorkout = try XCTUnwrap(
            nonBreakingInvite["workout"] as? [String: Any]
        )
        var nonBreakingExercises = try XCTUnwrap(
            nonBreakingWorkout["exercises"] as? [[String: Any]]
        )
        nonBreakingExercises[0]["name"] = edgeNonBreakingSpaceName
        nonBreakingWorkout["exercises"] = nonBreakingExercises
        nonBreakingInvite["workout"] = nonBreakingWorkout
        var nonBreakingSummary = try XCTUnwrap(
            nonBreakingInvite["summary"] as? [String: Any]
        )
        nonBreakingSummary["exerciseNames"] = [edgeNonBreakingSpaceName]
        nonBreakingInvite["summary"] = nonBreakingSummary
        nonBreakingIncoming[0] = nonBreakingInvite
        nonBreakingSpaceName["incoming"] = nonBreakingIncoming
        let parsedNonBreakingName = try SocialPayloadParser.workoutInbox(
            from: jsonData(nonBreakingSpaceName)
        )
        XCTAssertEqual(
            parsedNonBreakingName.incoming.first?.workout?.exercises.first?.name,
            edgeNonBreakingSpaceName
        )
        XCTAssertEqual(
            parsedNonBreakingName.incoming.first?.summary.exerciseNames.first,
            edgeNonBreakingSpaceName
        )

        for asciiEdgeName in [" Bench Press", "Bench Press "] {
            var asciiEdgeInbox = workoutInboxObject()
            var asciiIncoming = try XCTUnwrap(
                asciiEdgeInbox["incoming"] as? [[String: Any]]
            )
            var asciiInvite = try XCTUnwrap(asciiIncoming.first)
            var asciiWorkout = try XCTUnwrap(asciiInvite["workout"] as? [String: Any])
            var asciiExercises = try XCTUnwrap(
                asciiWorkout["exercises"] as? [[String: Any]]
            )
            asciiExercises[0]["name"] = asciiEdgeName
            asciiWorkout["exercises"] = asciiExercises
            asciiInvite["workout"] = asciiWorkout
            var asciiSummary = try XCTUnwrap(asciiInvite["summary"] as? [String: Any])
            asciiSummary["exerciseNames"] = [asciiEdgeName]
            asciiInvite["summary"] = asciiSummary
            asciiIncoming[0] = asciiInvite
            asciiEdgeInbox["incoming"] = asciiIncoming
            XCTAssertThrowsError(
                try SocialPayloadParser.workoutInbox(from: jsonData(asciiEdgeInbox))
            )
        }

        var unexpectedPrivateField = workoutInboxObject()
        var incoming = try XCTUnwrap(unexpectedPrivateField["incoming"] as? [[String: Any]])
        var firstInvite = try XCTUnwrap(incoming.first)
        var workout = try XCTUnwrap(firstInvite["workout"] as? [String: Any])
        workout["note"] = "must not cross accounts"
        firstInvite["workout"] = workout
        incoming[0] = firstInvite
        unexpectedPrivateField["incoming"] = incoming
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(unexpectedPrivateField))
        )

        var mismatchedSummary = workoutInboxObject()
        incoming = try XCTUnwrap(mismatchedSummary["incoming"] as? [[String: Any]])
        firstInvite = try XCTUnwrap(incoming.first)
        var summary = try XCTUnwrap(firstInvite["summary"] as? [String: Any])
        summary["setCount"] = 3
        firstInvite["summary"] = summary
        incoming[0] = firstInvite
        mismatchedSummary["incoming"] = incoming
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(mismatchedSummary))
        )

        var terminalIncoming = workoutInboxObject()
        incoming = try XCTUnwrap(terminalIncoming["incoming"] as? [[String: Any]])
        firstInvite = try XCTUnwrap(incoming.first)
        firstInvite["status"] = "declined"
        firstInvite["respondedAt"] = "2026-08-09T19:00:00Z"
        incoming[0] = firstInvite
        terminalIncoming["incoming"] = incoming
        terminalIncoming["pendingIncomingCount"] = 0
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(terminalIncoming))
        )

        var pendingWithResponse = workoutInboxObject()
        incoming = try XCTUnwrap(pendingWithResponse["incoming"] as? [[String: Any]])
        firstInvite = try XCTUnwrap(incoming.first)
        firstInvite["respondedAt"] = "2026-08-09T19:00:00+00:00"
        incoming[0] = firstInvite
        pendingWithResponse["incoming"] = incoming
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(pendingWithResponse))
        )

        var acceptedWithoutResponse = workoutInboxObject()
        incoming = try XCTUnwrap(acceptedWithoutResponse["incoming"] as? [[String: Any]])
        firstInvite = try XCTUnwrap(incoming.first)
        firstInvite["status"] = "accepted"
        incoming[0] = firstInvite
        acceptedWithoutResponse["incoming"] = incoming
        acceptedWithoutResponse["pendingIncomingCount"] = 0
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(acceptedWithoutResponse))
        )

        var terminalOutgoingWithoutResponse = workoutInboxObject()
        var outgoing = try XCTUnwrap(
            terminalOutgoingWithoutResponse["outgoing"] as? [[String: Any]]
        )
        var firstOutgoing = try XCTUnwrap(outgoing.first)
        firstOutgoing["status"] = "expired"
        outgoing[0] = firstOutgoing
        terminalOutgoingWithoutResponse["outgoing"] = outgoing
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(terminalOutgoingWithoutResponse))
        )

        var acceptedInbox = workoutInboxObject()
        incoming = try XCTUnwrap(acceptedInbox["incoming"] as? [[String: Any]])
        firstInvite = try XCTUnwrap(incoming.first)
        firstInvite["status"] = "accepted"
        firstInvite["respondedAt"] = "2026-08-09T19:00:00+00:00"
        incoming[0] = firstInvite
        acceptedInbox["incoming"] = incoming
        acceptedInbox["pendingIncomingCount"] = 0
        XCTAssertEqual(
            try SocialPayloadParser.workoutInbox(from: jsonData(acceptedInbox))
                .incoming.first?.status,
            .accepted
        )
    }

    func testWorkoutInboxUsesPortableServerIdentityWithoutInferringLocalAliases() throws {
        let parsed = try SocialPayloadParser.workoutInbox(
            from: jsonData(try aliasPairWorkoutInboxObject())
        )
        let plan = try XCTUnwrap(parsed.incoming.first?.workout)

        XCTAssertEqual(plan.exercises.map(\.name), [
            "Bench Press",
            "Жим штанги лежачи"
        ])
        XCTAssertEqual(plan.exercises.map(\.catalogKey), [nil, nil])
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: plan.exercises[0].name), "bench_press")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: plan.exercises[1].name), "bench_press")
        XCTAssertThrowsError(try SharedWorkoutLinkValidator.validate(plan))

        var duplicatePortableName = try aliasPairWorkoutInboxObject()
        var incoming = try XCTUnwrap(duplicatePortableName["incoming"] as? [[String: Any]])
        var invite = try XCTUnwrap(incoming.first)
        var workout = try XCTUnwrap(invite["workout"] as? [String: Any])
        var exercises = try XCTUnwrap(workout["exercises"] as? [[String: Any]])
        let whitespaceEquivalentName = "\u{00A0}Bench\u{2007}\u{00A0}Press\u{00A0}"
        exercises[1]["name"] = whitespaceEquivalentName
        workout["exercises"] = exercises
        invite["workout"] = workout
        var summary = try XCTUnwrap(invite["summary"] as? [String: Any])
        summary["exerciseNames"] = ["Bench Press", whitespaceEquivalentName]
        invite["summary"] = summary
        incoming[0] = invite
        duplicatePortableName["incoming"] = incoming
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(duplicatePortableName))
        )

        var duplicateCatalogKey = try aliasPairWorkoutInboxObject()
        incoming = try XCTUnwrap(duplicateCatalogKey["incoming"] as? [[String: Any]])
        invite = try XCTUnwrap(incoming.first)
        workout = try XCTUnwrap(invite["workout"] as? [String: Any])
        exercises = try XCTUnwrap(workout["exercises"] as? [[String: Any]])
        exercises[0]["catalogKey"] = "bench_press"
        exercises[1]["catalogKey"] = "bench_press"
        workout["exercises"] = exercises
        invite["workout"] = workout
        incoming[0] = invite
        duplicateCatalogKey["incoming"] = incoming
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(duplicateCatalogKey))
        )

        var whitespaceOnly = workoutInboxObject()
        incoming = try XCTUnwrap(whitespaceOnly["incoming"] as? [[String: Any]])
        invite = try XCTUnwrap(incoming.first)
        workout = try XCTUnwrap(invite["workout"] as? [String: Any])
        exercises = try XCTUnwrap(workout["exercises"] as? [[String: Any]])
        exercises[0]["name"] = "\u{00A0}\u{2007}"
        workout["exercises"] = exercises
        invite["workout"] = workout
        summary = try XCTUnwrap(invite["summary"] as? [String: Any])
        summary["exerciseNames"] = ["\u{00A0}\u{2007}"]
        invite["summary"] = summary
        incoming[0] = invite
        whitespaceOnly["incoming"] = incoming
        XCTAssertThrowsError(
            try SocialPayloadParser.workoutInbox(from: jsonData(whitespaceOnly))
        )
    }

    func testCanonicalWorkoutRequestContainsOnlyV1ExerciseAndSetFields() throws {
        let plan = SharedWorkoutPlan(exercises: [
            SharedWorkoutPlanExercise(
                catalogKey: "bench_press",
                name: "Bench Press",
                sets: [
                    SharedWorkoutPlanSet(weight: 72.5, repetitions: 8),
                    SharedWorkoutPlanSet(weight: 75, repetitions: 6)
                ]
            )
        ])

        let object = try SocialPayloadParser.workoutObject(for: plan)
        XCTAssertEqual(Set(object.keys), Set(["version", "exercises"]))
        let exercises = try XCTUnwrap(object["exercises"] as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(exercises.first).keys), Set(["catalogKey", "name", "sets"]))
        let sets = try XCTUnwrap(exercises.first?["sets"] as? [[String: Any]])
        XCTAssertTrue(sets.allSatisfy { Set($0.keys) == Set(["weight", "reps"]) })
        let wire = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        for forbidden in ["note", "date", "account", "health", "coach", "exerciseID"] {
            XCTAssertFalse(wire.localizedCaseInsensitiveContains(forbidden), forbidden)
        }

        let invalid = SharedWorkoutPlan(exercises: [
            SharedWorkoutPlanExercise(
                catalogKey: nil,
                name: "Bad\u{200B}Name",
                sets: [SharedWorkoutPlanSet(weight: 1, repetitions: 1)]
            )
        ])
        XCTAssertThrowsError(try SocialPayloadParser.workoutObject(for: invalid))
    }

    func testWorkoutInvitePreparationBlocksActiveWorkoutAndConfirmsBothDraftPaths() throws {
        XCTAssertEqual(
            socialWorkoutInvitePreparationDecision(
                canAcceptWorkoutInvites: false,
                pendingSharedWorkoutID: nil
            ),
            .blockedByActiveWorkout
        )
        XCTAssertEqual(
            socialWorkoutInvitePreparationDecision(
                canAcceptWorkoutInvites: true,
                pendingSharedWorkoutID: nil
            ),
            .confirmEditableCopy
        )
        let pendingID = UUID()
        XCTAssertEqual(
            socialWorkoutInvitePreparationDecision(
                canAcceptWorkoutInvites: true,
                pendingSharedWorkoutID: pendingID
            ),
            .confirmPendingReplacement(pendingID)
        )
    }

    func testServiceUsesExactFriendAndWorkoutRPCBodies() async throws {
        let recorder = SocialRequestRecorder()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if request.url?.path == "/rest/v1/rpc/social_block_profile" {
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: self.jsonData([
                        "version": 1,
                        "profileId": self.profileID(3),
                        "blocked": true
                    ])
                )
            }
            return try SocialURLProtocolStub.response(
                for: request,
                json: #"{"version":1,"result":"submitted_or_unavailable"}"#
            )
        }
        let service = CloudSyncService(auth: auth, urlSession: urlSession)
        let requestID = try XCTUnwrap(UUID(uuidString: "12345678-1234-4abc-8def-1234567890ab"))
        let plan = SharedWorkoutPlan(exercises: [
            SharedWorkoutPlanExercise(
                catalogKey: "bench_press",
                name: "Bench Press",
                sets: [SharedWorkoutPlanSet(weight: 80, repetitions: 5)]
            )
        ])

        try await service.socialSendFriendRequest(
            friendCode: profileID(2),
            expectedUserID: cloudUserID
        )
        try await service.socialSendFriendRequest(
            friendCode: "g_a1b2c3d4e5f6",
            expectedUserID: cloudUserID
        )
        try await service.socialSendWorkoutInvite(
            profileID: profileID(2),
            clientRequestID: requestID,
            workout: plan,
            expectedUserID: cloudUserID
        )
        _ = try await service.socialBlockProfile(
            profileID: profileID(3),
            expectedUserID: cloudUserID
        )

        let requests = recorder.requests
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/rest/v1/rpc/social_send_friend_request",
            "/rest/v1/rpc/social_send_friend_request",
            "/rest/v1/rpc/social_send_workout_invite",
            "/rest/v1/rpc/social_block_profile"
        ])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" })
        let friendBody = try requestJSON(requests[0])
        XCTAssertEqual(Set(friendBody.keys), Set(["p_friend_code"]))
        XCTAssertEqual(friendBody["p_friend_code"] as? String, profileID(2))

        let shortCodeBody = try requestJSON(requests[1])
        XCTAssertEqual(Set(shortCodeBody.keys), Set(["p_friend_code"]))
        XCTAssertEqual(shortCodeBody["p_friend_code"] as? String, "g_a1b2c3d4e5f6")

        let inviteBody = try requestJSON(requests[2])
        XCTAssertEqual(
            Set(inviteBody.keys),
            Set(["p_profile_id", "p_client_request_id", "p_workout"])
        )
        XCTAssertEqual(inviteBody["p_profile_id"] as? String, profileID(2))
        XCTAssertEqual(
            inviteBody["p_client_request_id"] as? String,
            "12345678-1234-4abc-8def-1234567890ab"
        )
        let workout = try XCTUnwrap(inviteBody["p_workout"] as? [String: Any])
        XCTAssertEqual(Set(workout.keys), Set(["version", "exercises"]))
        let wire = String(decoding: try XCTUnwrap(requests[2].httpBody), as: UTF8.self)
        XCTAssertFalse(wire.contains("note"))
        XCTAssertFalse(wire.contains("date"))
        XCTAssertFalse(wire.contains("account"))
        XCTAssertFalse(wire.localizedCaseInsensitiveContains("health"))
        XCTAssertFalse(wire.localizedCaseInsensitiveContains("coach"))

        let blockBody = try requestJSON(requests[3])
        XCTAssertEqual(Set(blockBody.keys), Set(["p_profile_id"]))
        XCTAssertEqual(blockBody["p_profile_id"] as? String, profileID(3))
    }

    func testDashboardRefreshUsesShortCodeAndFallsBackToLegacyCode() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppFriendCodeFallback", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let server = SocialTestServerState()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let dashboardData = try jsonData(dashboardObject())
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if request.url?.path == "/rest/v1/rpc/social_my_friend_code" {
                if server.flag("available") {
                    return try SocialURLProtocolStub.response(
                        for: request,
                        json: #"{"version":1,"friendCode":"g_a1b2c3d4e5f6"}"#
                    )
                }
                if server.flag("postgres-code") {
                    return try SocialURLProtocolStub.response(
                        for: request,
                        statusCode: 404,
                        json: #"{"code":"42883","message":"function unavailable"}"#
                    )
                }
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: #"{"code":"PGRST202","message":"function unavailable"}"#
                )
            }
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: dashboardData)
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)

        let legacyDashboard = try await appState.refreshSocialDashboard()
        XCTAssertEqual(appState.socialFriendCode, legacyDashboard.currentUser.friendCode)

        server.set("postgres-code")
        _ = try await appState.refreshSocialDashboard()
        XCTAssertEqual(appState.socialFriendCode, legacyDashboard.currentUser.friendCode)

        server.set("available")
        _ = try await appState.refreshSocialDashboard()
        XCTAssertEqual(appState.socialFriendCode, "g_a1b2c3d4e5f6")

        let codeRequests = recorder.requests.filter {
            $0.url?.path == "/rest/v1/rpc/social_my_friend_code"
        }
        XCTAssertEqual(codeRequests.count, 3)
        XCTAssertTrue(codeRequests.allSatisfy { $0.httpMethod == "POST" })
        for request in codeRequests {
            XCTAssertTrue(try requestJSON(request).isEmpty)
        }
    }

    func testShortCode503AndMalformedResponsesDoNotPublishDashboardOrFallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppFriendCodeFailure", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = SocialTestServerState()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let dashboardData = try jsonData(dashboardObject())
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            if request.url?.path == "/rest/v1/rpc/social_my_friend_code" {
                if server.flag("malformed") {
                    return try SocialURLProtocolStub.response(
                        for: request,
                        json: #"{"version":1,"friendCode":"not-a-friend-code"}"#
                    )
                }
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 503,
                    json: #"{"code":"PGRST202","message":"temporarily unavailable"}"#
                )
            }
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: dashboardData)
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)

        do {
            _ = try await appState.refreshSocialDashboard()
            XCTFail("A 503 short-code response must not use the legacy fallback")
        } catch CloudSyncError.postgRESTFailure(let statusCode, let code, _) {
            XCTAssertEqual(statusCode, 503)
            XCTAssertEqual(code, "PGRST202")
        } catch {
            XCTFail("Unexpected 503 error: \(error)")
        }
        XCTAssertNil(appState.socialDashboard)
        XCTAssertNil(appState.socialFriendCode)

        server.set("malformed")
        do {
            _ = try await appState.refreshSocialDashboard()
            XCTFail("A malformed short-code response must not use the legacy fallback")
        } catch CloudSyncError.invalidResponse {
            // Expected: exact response parsing fails closed.
        } catch {
            XCTFail("Unexpected malformed-response error: \(error)")
        }
        XCTAssertNil(appState.socialDashboard)
        XCTAssertNil(appState.socialFriendCode)
    }

    func testLateShortCodeResponseCannotCrossAccountSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppFriendCodeAccountSwitch", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shortCodeStarted = expectation(description: "short friend-code request started")
        let deferredResponses = SocialDeferredResponseStore()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let dashboardData = try jsonData(dashboardObject())
        defer {
            deferredResponses.failAll(with: URLError(.cancelled))
            SocialURLProtocolStub.deferredHandler = nil
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.deferredHandler = { request, response in
            guard request.url?.path == "/rest/v1/rpc/social_my_friend_code",
                  request.httpMethod == "POST" else {
                return false
            }
            deferredResponses.store(response, for: "friend-code")
            shortCodeStarted.fulfill()
            return true
        }
        SocialURLProtocolStub.handler = { request in
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: dashboardData)
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)

        let refresh = Task { try await appState.refreshSocialDashboard() }
        await fulfillment(of: [shortCodeStarted], timeout: 2)
        try auth.installSessionForTesting(.local(id: "replacement", displayName: "Replacement"))
        let switchedAccountReady = await waitUntil {
            appState.isAccountReady && auth.session?.cloud == nil
        }
        XCTAssertTrue(switchedAccountReady)

        try XCTUnwrap(deferredResponses.take("friend-code")).succeed(
            jsonData: try jsonData([
                "version": 1,
                "friendCode": "g_a1b2c3d4e5f6"
            ])
        )
        do {
            _ = try await refresh.value
            XCTFail("A previous account's short code must not publish after switching accounts")
        } catch {
            // Expected: the account/session generation fence rejects the late response.
        }
        XCTAssertNil(appState.socialDashboard)
        XCTAssertNil(appState.socialFriendCode)
    }

    func testWorkoutInviteRetryIDsAreAccountBoundAndNeverEvictUnknownOutcomes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppWorkoutInviteRetry", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let server = SocialTestServerState()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let dashboardData = try jsonData(dashboardObject())
        let inboxData = try jsonData(workoutInboxObject())
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: dashboardData)
            case ("/rest/v1/rpc/social_workout_inbox", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: inboxData)
            case ("/rest/v1/rpc/social_send_workout_invite", "POST"):
                if server.flag("confirm-send") {
                    return try SocialURLProtocolStub.response(
                        for: request,
                        json: #"{"version":1,"result":"submitted_or_unavailable"}"#
                    )
                }
                throw URLError(.networkConnectionLost)
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        _ = try await appState.refreshSocialDashboard()

        func plan(weight: Double) -> SharedWorkoutPlan {
            SharedWorkoutPlan(exercises: [
                SharedWorkoutPlanExercise(
                    catalogKey: "bench_press",
                    name: "Bench Press",
                    sets: [SharedWorkoutPlanSet(weight: weight, repetitions: 5)]
                )
            ])
        }

        for _ in 0 ..< 2 {
            do {
                try await appState.sendWorkoutInvite(to: profileID(2), plan: plan(weight: 1))
                XCTFail("A lost response must remain outcome-unknown")
            } catch {
                // Expected: the same unresolved request UUID remains reserved for retry.
            }
        }
        var inviteRequests = recorder.requests.filter {
            $0.url?.path == "/rest/v1/rpc/social_send_workout_invite"
        }
        XCTAssertEqual(inviteRequests.count, 2)
        let firstRequestID = try XCTUnwrap(
            requestJSON(inviteRequests[0])["p_client_request_id"] as? String
        )
        XCTAssertEqual(
            try requestJSON(inviteRequests[1])["p_client_request_id"] as? String,
            firstRequestID
        )

        server.set("confirm-send")
        try await appState.sendWorkoutInvite(to: profileID(2), plan: plan(weight: 1))
        server.set("confirm-send", false)
        do {
            try await appState.sendWorkoutInvite(to: profileID(2), plan: plan(weight: 1))
            XCTFail("The synthetic retry should lose its response")
        } catch {
            // A confirmed outcome releases the old UUID, so a later explicit send is new.
        }
        inviteRequests = recorder.requests.filter {
            $0.url?.path == "/rest/v1/rpc/social_send_workout_invite"
        }
        XCTAssertEqual(inviteRequests.count, 4)
        XCTAssertEqual(
            try requestJSON(inviteRequests[2])["p_client_request_id"] as? String,
            firstRequestID
        )
        let secondRequestID = try XCTUnwrap(
            requestJSON(inviteRequests[3])["p_client_request_id"] as? String
        )
        XCTAssertNotEqual(secondRequestID, firstRequestID)

        for index in 2 ... AppState.maximumPendingWorkoutInviteRequests {
            do {
                try await appState.sendWorkoutInvite(
                    to: profileID(2),
                    plan: plan(weight: Double(index))
                )
                XCTFail("The synthetic request should lose its response")
            } catch {
                // Each distinct canonical plan reserves one bounded unresolved slot.
            }
        }
        let countAtCapacity = recorder.requests.filter {
            $0.url?.path == "/rest/v1/rpc/social_send_workout_invite"
        }.count
        do {
            try await appState.sendWorkoutInvite(
                to: profileID(2),
                plan: plan(weight: Double(AppState.maximumPendingWorkoutInviteRequests + 1))
            )
            XCTFail("A distinct request beyond the unresolved capacity must fail closed")
        } catch {
            // Expected: unresolved entries are never evicted to admit a distinct request.
        }
        XCTAssertEqual(
            recorder.requests.filter {
                $0.url?.path == "/rest/v1/rpc/social_send_workout_invite"
            }.count,
            countAtCapacity
        )

        let replacementUserID = "10000000-0000-4000-8000-000000000002"
        try auth.installSessionForTesting(.cloud(CloudAccountSession(
            userID: replacementUserID,
            email: "replacement@example.invalid",
            displayName: "Replacement",
            accessToken: "synthetic-replacement-access-token",
            refreshToken: "synthetic-replacement-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        let replacementReady = await waitUntil {
            appState.isAccountReady &&
                auth.session?.cloud?.userID == replacementUserID &&
                appState.activeAccountStorageKey == auth.session?.storageKey
        }
        XCTAssertTrue(replacementReady)
        _ = try await appState.refreshSocialDashboard()
        do {
            try await appState.sendWorkoutInvite(to: profileID(2), plan: plan(weight: 1))
            XCTFail("The replacement account's synthetic request should lose its response")
        } catch {
            // The account transition cleared the old account's bounded request map.
        }
        inviteRequests = recorder.requests.filter {
            $0.url?.path == "/rest/v1/rpc/social_send_workout_invite"
        }
        XCTAssertEqual(inviteRequests.count, countAtCapacity + 1)
        XCTAssertNotEqual(
            try requestJSON(try XCTUnwrap(inviteRequests.last))["p_client_request_id"] as? String,
            secondRequestID
        )
    }

    func testAccountTransitionRejectsLateSocialResponse() async throws {
        let started = expectation(description: "social request started")
        let release = DispatchSemaphore(value: 0)
        let responseData = try jsonData(dashboardObject())
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        defer {
            release.signal()
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            started.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return try SocialURLProtocolStub.response(
                for: request,
                jsonData: responseData
            )
        }
        let service = CloudSyncService(auth: auth, urlSession: urlSession)
        let task = Task {
            try await service.socialDashboard(expectedUserID: cloudUserID)
        }

        await fulfillment(of: [started], timeout: 2)
        service.resetForAccountTransition()
        release.signal()
        do {
            _ = try await task.value
            XCTFail("A response from the previous account generation must be rejected")
        } catch AuthServiceError.sessionChanged {
            // Expected: the response belongs to the invalidated operation generation.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAcceptedWorkoutRecoverySurvivesRelaunchWithoutRespondMutation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppAcceptedInviteRecovery", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let dashboardData = try jsonData(dashboardObject())
        let inboxData = try jsonData(acceptedWorkoutInboxObject())
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: dashboardData)
            case ("/rest/v1/rpc/social_workout_inbox", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: inboxData)
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }

        var firstLaunch: AppState? = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let firstLaunchReady = await waitUntil { firstLaunch?.isAccountReady == true }
        XCTAssertTrue(firstLaunchReady)
        _ = try await XCTUnwrap(firstLaunch).refreshSocialDashboard()
        _ = try await XCTUnwrap(firstLaunch).refreshSocialWorkoutInbox()
        XCTAssertEqual(firstLaunch?.socialWorkoutInbox?.incoming.first?.status, .accepted)
        firstLaunch = nil

        let relaunched = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let relaunchReady = await waitUntil { relaunched.isAccountReady }
        XCTAssertTrue(relaunchReady)
        _ = try await relaunched.refreshSocialDashboard()
        let inbox = try await relaunched.refreshSocialWorkoutInbox()
        let accepted = try XCTUnwrap(inbox.incoming.first)

        let stale = SocialWorkoutInvite(
            inviteID: accepted.inviteID,
            profileID: accepted.profileID,
            displayName: accepted.displayName,
            status: accepted.status,
            inviteRevision: accepted.inviteRevision + 1,
            createdAt: accepted.createdAt,
            expiresAt: accepted.expiresAt,
            respondedAt: accepted.respondedAt,
            summary: accepted.summary,
            workout: accepted.workout
        )
        XCTAssertThrowsError(try relaunched.recoverAcceptedWorkoutInvite(stale))

        let recovered = try relaunched.recoverAcceptedWorkoutInvite(accepted)
        XCTAssertEqual(relaunched.pendingSharedWorkout?.plan, recovered)

        let replacementPlan = SharedWorkoutPlan(exercises: [
            SharedWorkoutPlanExercise(
                catalogKey: "squat",
                name: "Squat",
                sets: [SharedWorkoutPlanSet(weight: 100, repetitions: 5)]
            )
        ])
        let recoveredPendingID = try XCTUnwrap(relaunched.pendingSharedWorkout?.id)
        try relaunched.stageSharedWorkoutPlan(
            replacementPlan,
            replacingPendingID: recoveredPendingID
        )
        let replacementPendingID = try XCTUnwrap(relaunched.pendingSharedWorkout?.id)
        XCTAssertThrowsError(try relaunched.recoverAcceptedWorkoutInvite(accepted))
        _ = try relaunched.recoverAcceptedWorkoutInvite(
            accepted,
            replacingPendingSharedWorkoutID: replacementPendingID
        )
        XCTAssertEqual(relaunched.pendingSharedWorkout?.plan, recovered)
        XCTAssertFalse(recorder.requests.contains {
            $0.url?.path == "/rest/v1/rpc/social_respond_workout_invite"
        })
    }

    func testAliasPairInviteImportFailureDoesNotPoisonSocialCachesOrMutateAcceptance() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppAliasPairInvite", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let server = SocialTestServerState()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let dashboardData = try jsonData(dashboardObject())
        let pendingInboxData = try jsonData(try aliasPairWorkoutInboxObject())
        let acceptedInboxData = try jsonData(try aliasPairWorkoutInboxObject(accepted: true))
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: dashboardData)
            case ("/rest/v1/rpc/social_workout_inbox", "POST"):
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: server.flag("accepted") ? acceptedInboxData : pendingInboxData
                )
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let dashboard = try await appState.refreshSocialDashboard()
        let pendingInbox = try await appState.refreshSocialWorkoutInbox()
        let pendingInvite = try XCTUnwrap(pendingInbox.incoming.first)

        do {
            _ = try await appState.respondWorkoutInvite(pendingInvite, accept: true)
            XCTFail("A locally ambiguous alias pair must not be accepted remotely")
        } catch CloudSyncError.invalidWorkoutInvite {
            // Expected: local import preflight fails before the mutation RPC.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(appState.socialDashboard, dashboard)
        XCTAssertEqual(appState.socialWorkoutInbox, pendingInbox)
        XCTAssertNil(appState.pendingSharedWorkout)
        XCTAssertFalse(recorder.requests.contains {
            $0.url?.path == "/rest/v1/rpc/social_respond_workout_invite"
        })

        server.set("accepted")
        let acceptedInbox = try await appState.refreshSocialWorkoutInbox()
        let acceptedInvite = try XCTUnwrap(acceptedInbox.incoming.first)
        do {
            _ = try appState.recoverAcceptedWorkoutInvite(acceptedInvite)
            XCTFail("A retained ambiguous plan must not open as a local draft")
        } catch CloudSyncError.invalidWorkoutInvite {
            // Expected: only this local import fails; social caches remain usable.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(appState.socialDashboard, dashboard)
        XCTAssertEqual(appState.socialWorkoutInbox, acceptedInbox)
        XCTAssertNil(appState.pendingSharedWorkout)

        let safeMessage = gymSafeEnglishErrorMessage(CloudSyncError.invalidWorkoutInvite)
        XCTAssertLessThanOrEqual(safeMessage.utf8.count, 120)
        XCTAssertFalse(safeMessage.contains("Bench Press"))
        XCTAssertFalse(safeMessage.contains("Жим штанги лежачи"))
    }

    func testDashboardRevisionRefetchesPrivacyFromSharedToPrivate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppFriendPrivacyRefresh", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let server = SocialTestServerState()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let dashboardData = try jsonData(dashboardObject())
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                if server.flag("dashboard-failure") {
                    return try SocialURLProtocolStub.response(
                        for: request,
                        statusCode: 503,
                        json: #"{"message":"temporarily unavailable"}"#
                    )
                }
                return try SocialURLProtocolStub.response(for: request, jsonData: dashboardData)
            case ("/rest/v1/rpc/social_friend_details", "POST"):
                var object = self.friendDetailsObject()
                if server.flag("private") {
                    object["sharing"] = [
                        "progress": true,
                        "recentWorkouts": false,
                        "records": false
                    ]
                    object["activityUpdatedAt"] = NSNull()
                    object["recentWorkouts"] = []
                    object["exerciseRecords"] = []
                }
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: self.jsonData(object)
                )
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        _ = try await appState.refreshSocialDashboard()
        let sharedRevision = appState.socialDashboardRefreshRevision
        let shared = try await appState.socialFriendDetails(profileID: profileID(2))
        XCTAssertTrue(shared.sharing.recentWorkouts)
        XCTAssertFalse(shared.recentWorkouts.isEmpty)

        server.set("private")
        _ = try await appState.refreshSocialDashboard()
        XCTAssertGreaterThan(appState.socialDashboardRefreshRevision, sharedRevision)
        let privateDetails = try await appState.socialFriendDetails(profileID: profileID(2))
        XCTAssertFalse(privateDetails.sharing.recentWorkouts)
        XCTAssertFalse(privateDetails.sharing.records)
        XCTAssertTrue(privateDetails.recentWorkouts.isEmpty)
        XCTAssertTrue(privateDetails.exerciseRecords.isEmpty)
        XCTAssertEqual(
            recorder.requests.filter {
                $0.url?.path == "/rest/v1/rpc/social_friend_details"
            }.count,
            2
        )

        server.set("dashboard-failure")
        let revisionBeforeFailedRefresh = appState.socialDashboardRefreshRevision
        do {
            _ = try await appState.refreshSocialDashboard()
            XCTFail("The synthetic dashboard refresh must fail")
        } catch {
            // Even a failed foreground/dashboard attempt invalidates cached detail state.
        }
        XCTAssertGreaterThan(
            appState.socialDashboardRefreshRevision,
            revisionBeforeFailedRefresh
        )
    }

    func testRemoveFriendClearsInboxFailClosedWhenRefreshFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppRemoveFriendFailClosed", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let server = SocialTestServerState()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let inboxData = try jsonData(workoutInboxObject())
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                var dashboard = self.dashboardObject()
                if server.flag("removed") { dashboard["friends"] = [] }
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: self.jsonData(dashboard)
                )
            case ("/rest/v1/rpc/social_workout_inbox", "POST"):
                if server.flag("removed") {
                    return try SocialURLProtocolStub.response(
                        for: request,
                        statusCode: 503,
                        json: #"{"message":"temporarily unavailable"}"#
                    )
                }
                return try SocialURLProtocolStub.response(for: request, jsonData: inboxData)
            case ("/rest/v1/rpc/social_remove_friend", "POST"):
                server.set("removed")
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: self.jsonData([
                        "version": 1,
                        "friendshipId": self.friendshipID(2),
                        "status": "removed",
                        "friendshipRevision": 3
                    ])
                )
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let dashboard = try await appState.refreshSocialDashboard()
        let friend = try XCTUnwrap(dashboard.friends.first)
        let initialInbox = try await appState.refreshSocialWorkoutInbox()
        let oldInvite = try XCTUnwrap(initialInbox.incoming.first)

        do {
            try await appState.removeFriend(friend)
            XCTFail("The failed inbox refresh must remain observable")
        } catch {
            // The relation mutation succeeded, but stale invite data must stay cleared.
        }
        XCTAssertNil(appState.socialWorkoutInbox)
        XCTAssertTrue(appState.socialDashboard?.friends.isEmpty == true)
        do {
            _ = try await appState.respondWorkoutInvite(oldInvite, accept: true)
            XCTFail("A stale invite must not reopen after relationship removal")
        } catch {
            // Expected: the current-account inbox no longer contains this request identity.
        }
        XCTAssertFalse(recorder.requests.contains {
            $0.url?.path == "/rest/v1/rpc/social_respond_workout_invite"
        })
    }

    func testBlockIncomingRequesterClearsInboxFailClosedWhenRefreshFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppBlockRequesterFailClosed", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let server = SocialTestServerState()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let inboxData = try jsonData(workoutInboxObject())
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                var dashboard = self.dashboardObject()
                if server.flag("blocked") {
                    dashboard["incoming"] = []
                    var blocked = try XCTUnwrap(dashboard["blocked"] as? [[String: Any]])
                    blocked.append([
                        "profileId": self.profileID(3),
                        "displayName": "Request 3",
                        "blockedAt": "2026-08-09T20:00:00+00:00"
                    ])
                    dashboard["blocked"] = blocked
                }
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: self.jsonData(dashboard)
                )
            case ("/rest/v1/rpc/social_workout_inbox", "POST"):
                if server.flag("blocked") {
                    return try SocialURLProtocolStub.response(
                        for: request,
                        statusCode: 503,
                        json: #"{"message":"temporarily unavailable"}"#
                    )
                }
                return try SocialURLProtocolStub.response(for: request, jsonData: inboxData)
            case ("/rest/v1/rpc/social_block_profile", "POST"):
                server.set("blocked")
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: self.jsonData([
                        "version": 1,
                        "profileId": self.profileID(3),
                        "blocked": true
                    ])
                )
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let dashboard = try await appState.refreshSocialDashboard()
        let request = try XCTUnwrap(dashboard.incoming.first)
        let initialInbox = try await appState.refreshSocialWorkoutInbox()
        let oldInvite = try XCTUnwrap(initialInbox.incoming.first)

        do {
            try await appState.blockSocialProfile(profileID: request.profileID)
            XCTFail("The failed inbox refresh must remain observable")
        } catch {
            // The block succeeded; stale invite memory must still remain unavailable.
        }
        XCTAssertNil(appState.socialWorkoutInbox)
        XCTAssertTrue(appState.socialDashboard?.incoming.isEmpty == true)
        XCTAssertTrue(appState.socialDashboard?.blocked.contains {
            $0.profileID == request.profileID
        } == true)
        do {
            _ = try await appState.respondWorkoutInvite(oldInvite, accept: true)
            XCTFail("A cached invite must not reopen after a block")
        } catch {
            // Expected: clearing the inbox rejects the old response/request identity.
        }
        XCTAssertFalse(recorder.requests.contains {
            $0.url?.path == "/rest/v1/rpc/social_respond_workout_invite"
        })
    }

    func testRemoveFriendLostResponseClearsDashboardAndRejectsLateDashboardRead() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppRemoveFriendLostResponse", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let server = SocialTestServerState()
        let lateDashboardStarted = expectation(description: "stale dashboard read started")
        let removeStarted = expectation(description: "remove request started")
        let deferredResponses = SocialDeferredResponseStore()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let staleDashboardData = try jsonData(dashboardObject())
        let inboxData = try jsonData(workoutInboxObject())
        defer {
            deferredResponses.failAll(with: URLError(.cancelled))
            SocialURLProtocolStub.deferredHandler = nil
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.deferredHandler = { request, response in
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST") where server.flag("hold-dashboard"):
                server.set("hold-dashboard", false)
                recorder.append(request)
                deferredResponses.store(response, for: "dashboard")
                lateDashboardStarted.fulfill()
                return true
            case ("/rest/v1/rpc/social_remove_friend", "POST"):
                server.set("removed")
                recorder.append(request)
                deferredResponses.store(response, for: "remove")
                removeStarted.fulfill()
                return true
            default:
                return false
            }
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                var dashboard = self.dashboardObject()
                if server.flag("removed") { dashboard["friends"] = [] }
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: self.jsonData(dashboard)
                )
            case ("/rest/v1/rpc/social_workout_inbox", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: inboxData)
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let dashboard = try await appState.refreshSocialDashboard()
        let friend = try XCTUnwrap(dashboard.friends.first)
        _ = try await appState.refreshSocialWorkoutInbox()

        server.set("hold-dashboard")
        let lateDashboardTask = Task { try await appState.refreshSocialDashboard() }
        await fulfillment(of: [lateDashboardStarted], timeout: 2)

        let revisionBeforeRemoval = appState.socialDashboardRefreshRevision
        let removeTask = Task { try await appState.removeFriend(friend) }
        await fulfillment(of: [removeStarted], timeout: 2)

        XCTAssertNil(appState.socialDashboard)
        XCTAssertNil(appState.socialWorkoutInbox)
        XCTAssertGreaterThan(appState.socialDashboardRefreshRevision, revisionBeforeRemoval)

        try XCTUnwrap(deferredResponses.take("remove"))
            .fail(with: URLError(.networkConnectionLost))
        do {
            try await removeTask.value
            XCTFail("A committed remove with a lost response must remain outcome-unknown")
        } catch {
            // Expected: caches were already invalidated before this response failed.
        }

        try XCTUnwrap(deferredResponses.take("dashboard"))
            .succeed(jsonData: staleDashboardData)
        do {
            _ = try await lateDashboardTask.value
            XCTFail("A dashboard read started before removal must not republish stale data")
        } catch {
            // Expected: the relationship-cache generation rejects this late read.
        }
        XCTAssertNil(appState.socialDashboard)
        XCTAssertNil(appState.socialWorkoutInbox)
        XCTAssertTrue(server.flag("removed"))
    }

    func testBlockLostResponseRejectsLateInboxAndPreservesUnknownInviteRequestID() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppBlockLostResponse", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = SocialRequestRecorder()
        let server = SocialTestServerState()
        let lateInboxStarted = expectation(description: "stale workout inbox read started")
        let blockStarted = expectation(description: "block request started")
        let deferredResponses = SocialDeferredResponseStore()
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let inboxData = try jsonData(workoutInboxObject())
        defer {
            deferredResponses.failAll(with: URLError(.cancelled))
            SocialURLProtocolStub.deferredHandler = nil
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.deferredHandler = { request, response in
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_workout_inbox", "POST") where server.flag("hold-inbox"):
                server.set("hold-inbox", false)
                recorder.append(request)
                deferredResponses.store(response, for: "inbox")
                lateInboxStarted.fulfill()
                return true
            case ("/rest/v1/rpc/social_block_profile", "POST"):
                server.set("blocked")
                recorder.append(request)
                deferredResponses.store(response, for: "block")
                blockStarted.fulfill()
                return true
            default:
                return false
            }
        }
        SocialURLProtocolStub.handler = { request in
            recorder.append(request)
            if let response = try self.baseCloudStateResponse(for: request) { return response }
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                var dashboard = self.dashboardObject()
                if server.flag("blocked") {
                    dashboard["incoming"] = []
                    var blocked = try XCTUnwrap(dashboard["blocked"] as? [[String: Any]])
                    blocked.append([
                        "profileId": self.profileID(3),
                        "displayName": "Request 3",
                        "blockedAt": "2026-08-09T20:00:00+00:00"
                    ])
                    dashboard["blocked"] = blocked
                }
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: self.jsonData(dashboard)
                )
            case ("/rest/v1/rpc/social_workout_inbox", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: inboxData)
            case ("/rest/v1/rpc/social_send_workout_invite", "POST"):
                throw URLError(.networkConnectionLost)
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let dashboard = try await appState.refreshSocialDashboard()
        let request = try XCTUnwrap(dashboard.incoming.first)
        _ = try await appState.refreshSocialWorkoutInbox()
        let plan = SharedWorkoutPlan(exercises: [
            SharedWorkoutPlanExercise(
                catalogKey: "bench_press",
                name: "Bench Press",
                sets: [SharedWorkoutPlanSet(weight: 80, repetitions: 5)]
            )
        ])

        do {
            try await appState.sendWorkoutInvite(to: profileID(2), plan: plan)
            XCTFail("The first invite send must have an unknown outcome")
        } catch {
            // Expected: its UUID remains reserved while the result is unknown.
        }
        var inviteRequests = recorder.requests.filter {
            $0.url?.path == "/rest/v1/rpc/social_send_workout_invite"
        }
        let unresolvedRequestID = try XCTUnwrap(
            try requestJSON(try XCTUnwrap(inviteRequests.first))["p_client_request_id"] as? String
        )

        server.set("hold-inbox")
        let lateInboxTask = Task { try await appState.refreshSocialWorkoutInbox() }
        await fulfillment(of: [lateInboxStarted], timeout: 2)

        let revisionBeforeBlock = appState.socialDashboardRefreshRevision
        let blockTask = Task {
            try await appState.blockSocialProfile(profileID: request.profileID)
        }
        await fulfillment(of: [blockStarted], timeout: 2)

        XCTAssertNil(appState.socialDashboard)
        XCTAssertNil(appState.socialWorkoutInbox)
        XCTAssertGreaterThan(appState.socialDashboardRefreshRevision, revisionBeforeBlock)

        try XCTUnwrap(deferredResponses.take("block"))
            .fail(with: URLError(.networkConnectionLost))
        do {
            try await blockTask.value
            XCTFail("A committed block with a lost response must remain outcome-unknown")
        } catch {
            // Expected: relationship-derived caches stay unavailable.
        }

        try XCTUnwrap(deferredResponses.take("inbox"))
            .succeed(jsonData: inboxData)
        do {
            _ = try await lateInboxTask.value
            XCTFail("An inbox read started before blocking must not republish stale invites")
        } catch {
            // Expected: the relationship-cache generation rejects this late read.
        }
        XCTAssertNil(appState.socialDashboard)
        XCTAssertNil(appState.socialWorkoutInbox)

        let refreshedDashboard = try await appState.refreshSocialDashboard()
        XCTAssertTrue(refreshedDashboard.incoming.isEmpty)
        XCTAssertTrue(refreshedDashboard.blocked.contains { $0.profileID == request.profileID })
        do {
            try await appState.sendWorkoutInvite(to: profileID(2), plan: plan)
            XCTFail("The retried synthetic invite must still have an unknown outcome")
        } catch {
            // The block invalidation must not evict a different friend's unresolved UUID.
        }
        inviteRequests = recorder.requests.filter {
            $0.url?.path == "/rest/v1/rpc/social_send_workout_invite"
        }
        XCTAssertEqual(inviteRequests.count, 2)
        XCTAssertEqual(
            try requestJSON(inviteRequests[1])["p_client_request_id"] as? String,
            unresolvedRequestID
        )
    }

    func testAppStateAccountSwitchClearsSocialAndInviteMemory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppSocialAccountSwitch", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (auth, urlSession, defaults, suiteName) = try authenticatedServiceDependencies()
        let dashboardData = try jsonData(dashboardObject())
        let inboxData = try jsonData(workoutInboxObject())
        defer {
            SocialURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
        }
        SocialURLProtocolStub.handler = { request in
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                return try SocialURLProtocolStub.response(for: request, json: "[]")
            case ("/rest/v1/user_states", "POST"):
                let bodyData = try XCTUnwrap(request.httpBody)
                let body = try JSONSerialization.jsonObject(with: bodyData)
                let rows = try XCTUnwrap(body as? [[String: Any]])
                let revision = try XCTUnwrap(rows.first?["updated_at"] as? String)
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: try JSONSerialization.data(withJSONObject: [["updated_at": revision]])
                )
            case ("/rest/v1/user_states", "PATCH"):
                let bodyData = try XCTUnwrap(request.httpBody)
                let body = try JSONSerialization.jsonObject(with: bodyData)
                let object = try XCTUnwrap(body as? [String: Any])
                let revision = try XCTUnwrap(object["updated_at"] as? String)
                return try SocialURLProtocolStub.response(
                    for: request,
                    jsonData: try JSONSerialization.data(withJSONObject: [["updated_at": revision]])
                )
            case ("/rest/v1/profiles", "POST"):
                return try SocialURLProtocolStub.response(for: request, json: "{}")
            case ("/rest/v1/rpc/social_dashboard", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: dashboardData)
            case ("/rest/v1/rpc/social_my_friend_code", "POST"):
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: #"{"code":"PGRST202","message":"function unavailable"}"#
                )
            case ("/rest/v1/rpc/social_workout_inbox", "POST"):
                return try SocialURLProtocolStub.response(for: request, jsonData: inboxData)
            default:
                return try SocialURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            garminBindingStore: GarminDeviceBindingStore(keychain: SocialTestKeychain())
        )

        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        _ = try await appState.refreshSocialDashboard()
        _ = try await appState.refreshSocialWorkoutInbox()
        try appState.stageSharedWorkoutPlan(
            try XCTUnwrap(appState.socialWorkoutInbox?.incoming.first?.workout)
        )
        XCTAssertNotNil(appState.socialDashboard)
        XCTAssertNotNil(appState.socialWorkoutInbox)
        XCTAssertNotNil(appState.pendingSharedWorkout)

        try auth.installSessionForTesting(.local(id: "replacement", displayName: "Replacement"))
        let switchedToLocal = await waitUntil { auth.session?.cloud == nil }
        XCTAssertTrue(switchedToLocal)
        let privateMemoryCleared = await waitUntil {
            appState.socialDashboard == nil &&
                appState.socialWorkoutInbox == nil &&
                appState.pendingSharedWorkout == nil
        }
        XCTAssertTrue(privateMemoryCleared)
        XCTAssertNil(appState.socialDashboard)
        XCTAssertNil(appState.socialWorkoutInbox)
        XCTAssertNil(appState.pendingSharedWorkout)
    }

    private let cloudUserID = "10000000-0000-4000-8000-000000000001"

    private func authenticatedServiceDependencies() throws -> (
        AuthService,
        URLSession,
        UserDefaults,
        String
    ) {
        let suiteName = "SocialContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SocialURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: SocialTestKeychain(),
            urlSession: session,
            defaults: defaults
        )
        try auth.installSessionForTesting(.cloud(CloudAccountSession(
            userID: cloudUserID,
            email: "social@example.invalid",
            displayName: "Social Tester",
            accessToken: "synthetic-access-token",
            refreshToken: "synthetic-refresh-token",
            expiresAt: Date().addingTimeInterval(3_600)
        )))
        return (auth, session, defaults, suiteName)
    }

    private func dashboardObject() -> [String: Any] {
        [
            "version": 1,
            "self": [
                "profileId": profileID(1),
                "friendCode": profileID(1),
                "displayName": "Social Tester",
                "xp": 1_200,
                "level": 7,
                "workouts": 12,
                "statsAvailable": true,
                "progressUpdatedAt": "2026-08-09T18:10:00+00:00",
                "privacy": [
                    "allowRequests": true,
                    "shareProgress": true,
                    "shareRecentWorkouts": true,
                    "shareRecords": true
                ],
                "settingsRevision": 4
            ],
            "friends": [friendObject(index: 2)],
            "incoming": [friendRequestObject(index: 3)],
            "outgoing": [friendRequestObject(index: 4)],
            "blocked": [[
                "profileId": profileID(5),
                "displayName": "Blocked Tester",
                "blockedAt": "2026-08-08T10:00:00Z"
            ]],
            "pendingWorkoutInviteCount": 1
        ]
    }

    private func friendObject(index: Int) -> [String: Any] {
        [
            "friendshipId": friendshipID(index),
            "profileId": profileID(index),
            "displayName": "Friend \(index)",
            "xp": index * 100,
            "level": 2,
            "workouts": 4,
            "progressShared": true,
            "statsAvailable": true,
            "progressUpdatedAt": "2026-08-09T18:00:00Z",
            "friendshipRevision": 2,
            "status": "accepted"
        ]
    }

    private func friendRequestObject(index: Int) -> [String: Any] {
        [
            "friendshipId": friendshipID(index),
            "profileId": profileID(index),
            "displayName": "Request \(index)",
            "requestedAt": "2026-08-09T17:00:00Z",
            "friendshipRevision": 1,
            "status": "pending"
        ]
    }

    private func friendDetailsObject() -> [String: Any] {
        [
            "version": 1,
            "friend": [
                "profileId": profileID(2),
                "displayName": "Friend 2",
                "xp": 200,
                "level": 2,
                "workouts": 4,
                "progressShared": true,
                "statsAvailable": true,
                "progressUpdatedAt": "2026-08-09T18:00:00Z"
            ],
            "sharing": [
                "progress": true,
                "recentWorkouts": true,
                "records": true
            ],
            "activityUpdatedAt": "2026-08-09T18:00:00Z",
            "recentWorkouts": [[
                "workoutDay": "2026-08-09",
                "exerciseCount": 1,
                "setCount": 2,
                "exercises": [["catalogKey": "bench_press", "name": "Bench Press"]]
            ]],
            "exerciseRecords": [[
                "catalogKey": "bench_press",
                "name": "Bench Press",
                "bestWeightKg": 140,
                "bestReps": 18,
                "workoutCount": 4,
                "lastWorkoutDay": "2026-08-09"
            ]],
            "integrity": "self_reported"
        ]
    }

    private func workoutInboxObject() -> [String: Any] {
        let workout: [String: Any] = [
            "version": 1,
            "exercises": [[
                "catalogKey": "bench_press",
                "name": "Bench Press",
                "sets": [
                    ["weight": 72.5, "reps": 8],
                    ["weight": 75, "reps": 6]
                ]
            ]]
        ]
        let summary: [String: Any] = [
            "exerciseCount": 1,
            "setCount": 2,
            "exerciseNames": ["Bench Press"]
        ]
        return [
            "version": 1,
            "pendingIncomingCount": 1,
            "incoming": [[
                "inviteId": inviteID(1),
                "profileId": profileID(2),
                "displayName": "Friend 2",
                "status": "pending",
                "inviteRevision": 1,
                "createdAt": "2026-08-09T18:00:00Z",
                "expiresAt": "2026-08-16T18:00:00Z",
                "respondedAt": NSNull(),
                "summary": summary,
                "workout": workout
            ]],
            "outgoing": [[
                "inviteId": inviteID(2),
                "profileId": profileID(3),
                "displayName": "Friend 3",
                "status": "pending",
                "inviteRevision": 1,
                "createdAt": "2026-08-09T17:00:00Z",
                "expiresAt": "2026-08-16T17:00:00Z",
                "respondedAt": NSNull(),
                "summary": summary
            ]]
        ]
    }

    private func aliasPairWorkoutInboxObject(
        accepted: Bool = false
    ) throws -> [String: Any] {
        var object = workoutInboxObject()
        var incoming = try XCTUnwrap(object["incoming"] as? [[String: Any]])
        var invite = try XCTUnwrap(incoming.first)
        invite["summary"] = [
            "exerciseCount": 2,
            "setCount": 2,
            "exerciseNames": ["Bench Press", "Жим штанги лежачи"]
        ]
        invite["workout"] = [
            "version": 1,
            "exercises": [
                [
                    "name": "Bench Press",
                    "sets": [["weight": 80, "reps": 5]]
                ],
                [
                    "name": "Жим штанги лежачи",
                    "sets": [["weight": 60, "reps": 10]]
                ]
            ]
        ]
        if accepted {
            invite["status"] = "accepted"
            invite["inviteRevision"] = 2
            invite["respondedAt"] = "2026-08-09T19:00:00+00:00"
            object["pendingIncomingCount"] = 0
        }
        incoming[0] = invite
        object["incoming"] = incoming
        return object
    }

    private func acceptedWorkoutInboxObject() throws -> [String: Any] {
        var object = workoutInboxObject()
        var incoming = try XCTUnwrap(object["incoming"] as? [[String: Any]])
        var invite = try XCTUnwrap(incoming.first)
        invite["status"] = "accepted"
        invite["inviteRevision"] = 2
        invite["respondedAt"] = "2026-08-09T19:00:00+00:00"
        incoming[0] = invite
        object["incoming"] = incoming
        object["pendingIncomingCount"] = 0
        return object
    }

    private func profileID(_ index: Int) -> String {
        "p_" + String(format: "%032x", index)
    }

    private func friendshipID(_ index: Int) -> String {
        "f_" + String(format: "%032x", index)
    }

    private func inviteID(_ index: Int) -> String {
        "wi_" + String(format: "%032x", index)
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func baseCloudStateResponse(
        for request: URLRequest
    ) throws -> (HTTPURLResponse, Data)? {
        switch (request.url?.path, request.httpMethod) {
        case ("/rest/v1/user_states", "GET"):
            return try SocialURLProtocolStub.response(for: request, json: "[]")
        case ("/rest/v1/user_states", "POST"), ("/rest/v1/user_states", "PATCH"):
            let body = try XCTUnwrap(request.httpBody)
            let json = try JSONSerialization.jsonObject(with: body)
            let revision: String?
            if let rows = json as? [[String: Any]] {
                revision = rows.first?["updated_at"] as? String
            } else {
                revision = (json as? [String: Any])?["updated_at"] as? String
            }
            let response = try JSONSerialization.data(withJSONObject: [[
                "updated_at": try XCTUnwrap(revision)
            ]])
            return try SocialURLProtocolStub.response(for: request, jsonData: response)
        case ("/rest/v1/profiles", "POST"):
            return try SocialURLProtocolStub.response(for: request, json: "{}")
        case ("/rest/v1/rpc/social_my_friend_code", "POST"):
            return try SocialURLProtocolStub.response(
                for: request,
                statusCode: 404,
                json: #"{"code":"PGRST202","message":"function unavailable"}"#
            )
        default:
            return nil
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

private final class SocialTestKeychain: KeychainStoring {
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

private final class SocialRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { stored }
    }

    func append(_ request: URLRequest) {
        lock.withLock { stored.append(request) }
    }
}

private final class SocialTestServerState: @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [String: Bool] = [:]

    func flag(_ key: String) -> Bool {
        lock.withLock { flags[key] ?? false }
    }

    func set(_ key: String, _ value: Bool = true) {
        lock.withLock { flags[key] = value }
    }
}

private final class SocialDeferredResponseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: SocialDeferredURLResponse] = [:]

    func store(_ response: SocialDeferredURLResponse, for key: String) {
        lock.withLock { responses[key] = response }
    }

    func take(_ key: String) -> SocialDeferredURLResponse? {
        lock.withLock { responses.removeValue(forKey: key) }
    }

    func failAll(with error: Error) {
        let pending = lock.withLock {
            let pending = Array(responses.values)
            responses.removeAll()
            return pending
        }
        pending.forEach { $0.fail(with: error) }
    }
}

private final class SocialDeferredURLResponse: @unchecked Sendable {
    let request: URLRequest
    private let lock = NSLock()
    private var loader: SocialURLProtocolStub?

    init(request: URLRequest, loader: SocialURLProtocolStub) {
        self.request = request
        self.loader = loader
    }

    func succeed(jsonData: Data, statusCode: Int = 200) throws {
        let response = try SocialURLProtocolStub.response(
            for: request,
            statusCode: statusCode,
            jsonData: jsonData
        )
        takeLoader()?.finish(response: response.0, data: response.1)
    }

    func fail(with error: Error) {
        takeLoader()?.finish(error: error)
    }

    private func takeLoader() -> SocialURLProtocolStub? {
        lock.withLock {
            defer { loader = nil }
            return loader
        }
    }
}

private final class SocialURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var deferredHandler:
        ((URLRequest, SocialDeferredURLResponse) throws -> Bool)?
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "owrcbsrectdgaotndtxy.supabase.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let materialized = try Self.materializedRequest(request)
            let deferred = SocialDeferredURLResponse(request: materialized, loader: self)
            if try Self.deferredHandler?(materialized, deferred) == true {
                return
            }
            guard let handler = Self.handler else {
                finish(error: URLError(.unsupportedURL))
                return
            }
            let (response, data) = try handler(materialized)
            finish(response: response, data: data)
        } catch {
            finish(error: error)
        }
    }

    override func stopLoading() {}

    fileprivate func finish(response: HTTPURLResponse, data: Data) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    fileprivate func finish(error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
    }

    static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        json: String
    ) throws -> (HTTPURLResponse, Data) {
        try response(for: request, statusCode: statusCode, jsonData: Data(json.utf8))
    }

    static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        jsonData: Data
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        return (response, jsonData)
    }

    private static func materializedRequest(_ request: URLRequest) throws -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
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
        var result = request
        result.httpBodyStream = nil
        result.httpBody = data
        return result
    }
}
