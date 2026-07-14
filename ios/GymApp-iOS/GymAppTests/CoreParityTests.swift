import SwiftUI
import CryptoKit
import Foundation
import XCTest
@testable import GymApp

@MainActor
final class CoreParityTests: XCTestCase {
    func testIOSAuthUsesHTTPSBridgeWithStrictNestedQueryEncoding() throws {
        let state = "abcdefghijklmnopqrstuvwxyzABCDEF"
        let redirect = AuthCallbackRouting.webRedirectURL(state: state, purpose: .recovery)
        let components = try XCTUnwrap(URLComponents(string: redirect))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "gymapptracker.com")
        XCTAssertEqual(components.path, "/confirmed.html")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "platform" })?.value, "ios")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "state" })?.value, state)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "purpose" })?.value, "recovery")

        let encoded = AuthCallbackRouting.percentEncodedQueryValue(redirect)
        XCTAssertFalse(encoded.contains("?"))
        XCTAssertFalse(encoded.contains("&"))
        XCTAssertTrue(encoded.contains("%3A%2F%2Fgymapptracker.com%2Fconfirmed.html%3F"))
    }

    func testIOSAuthAcceptsOnlyExpectedCodeCallbacksAndRejectsRawTokens() {
        let state = "abcdefghijklmnopqrstuvwxyzABCDEF"
        let custom = URL(
            string: "com.setforge.gymapp.ios://auth/callback/\(state)?code=one-time-code"
        )!
        let universal = URL(
            string: "https://gymapptracker.com/confirmed.html?platform=ios&state=\(state)&code=one-time-code"
        )!
        let rawToken = URL(
            string: "com.setforge.gymapp.ios://auth/callback/\(state)?access_token=unsafe&refresh_token=unsafe"
        )!
        let wrongState = URL(
            string: "https://gymapptracker.com/confirmed.html?platform=ios&state=attacker&code=one-time-code"
        )!

        XCTAssertTrue(
            AuthCallbackRouting.isExpectedCallback(
                custom,
                state: state,
                values: AuthCallbackRouting.callbackValues(custom)
            )
        )
        XCTAssertTrue(
            AuthCallbackRouting.isExpectedCallback(
                universal,
                state: state,
                values: AuthCallbackRouting.callbackValues(universal)
            )
        )
        XCTAssertFalse(
            AuthCallbackRouting.isExpectedCallback(
                rawToken,
                state: state,
                values: AuthCallbackRouting.callbackValues(rawToken)
            )
        )
        XCTAssertFalse(
            AuthCallbackRouting.isExpectedCallback(
                wrongState,
                state: state,
                values: AuthCallbackRouting.callbackValues(wrongState)
            )
        )
    }

    func testUnsolicitedAuthCallbackIsRejectedWithoutNetworkAccess() async {
        let keychain = InMemoryKeychainStore()
        let auth = AuthService(keychain: keychain)
        try? auth.clearSession()
        let callback = URL(
            string: "com.setforge.gymapp.ios://auth/callback/attacker?access_token=fake&refresh_token=fake"
        )!

        XCTAssertTrue(AuthCallbackRouting.isAuthDestination(callback))
        await auth.handleOpenURL(callback)

        XCTAssertNil(auth.session)
        XCTAssertTrue(auth.messageIsError)
        XCTAssertEqual(auth.message, AuthServiceError.callbackNotExpected.errorDescription)
    }

    func testPasswordRecoveryCompletesPKCEExchangeAndUpdatesPassword() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let keychain = InMemoryKeychainStore()
        let auth = AuthService(keychain: keychain, urlSession: session)

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let path = request.url?.path ?? ""
            let json: String
            switch path {
            case "/auth/v1/recover":
                json = "{}"
            case "/auth/v1/token":
                json = #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600,"user":{"id":"00000000-0000-0000-0000-000000000001","email":"ed@example.com","user_metadata":{"display_name":"Eduard"}}}"#
            case "/auth/v1/user":
                json = #"{"id":"00000000-0000-0000-0000-000000000001"}"#
            default:
                XCTFail("Unexpected auth request: \(request.url?.absoluteString ?? path)")
                json = #"{"message":"unexpected request"}"#
            }
            return try AuthURLProtocolStub.response(for: request, json: json)
        }
        defer {
            AuthURLProtocolStub.handler = nil
            session.invalidateAndCancel()
            try? auth.clearSession()
        }

        await auth.requestPasswordReset(email: " Ed@Example.COM ")
        XCTAssertFalse(auth.messageIsError)
        XCTAssertTrue(auth.message?.contains("newest email") == true)

        let recoverRequest = try XCTUnwrap(recorder.requests.first(where: { $0.url?.path == "/auth/v1/recover" }))
        let recoverURL = try XCTUnwrap(recoverRequest.url)
        let recoverQuery = try XCTUnwrap(URLComponents(url: recoverURL, resolvingAgainstBaseURL: false))
        let redirect = try XCTUnwrap(recoverQuery.queryItems?.first(where: { $0.name == "redirect_to" })?.value)
        let redirectComponents = try XCTUnwrap(URLComponents(string: redirect))
        let state = try XCTUnwrap(redirectComponents.queryItems?.first(where: { $0.name == "state" })?.value)
        XCTAssertEqual(state.count, 32)
        XCTAssertEqual(redirectComponents.queryItems?.first(where: { $0.name == "platform" })?.value, "ios")
        XCTAssertEqual(redirectComponents.queryItems?.first(where: { $0.name == "purpose" })?.value, "recovery")

        let recoverBody = try jsonObject(from: recoverRequest)
        let challenge = try XCTUnwrap(recoverBody["code_challenge"] as? String)
        XCTAssertEqual(recoverBody["email"] as? String, "ed@example.com")
        XCTAssertEqual(recoverBody["code_challenge_method"] as? String, "s256")

        let callback = try XCTUnwrap(
            URL(string: "com.setforge.gymapp.ios://auth/callback/\(state)?code=test-auth-code")
        )
        await auth.handleOpenURL(callback)

        XCTAssertTrue(auth.needsPasswordUpdate)
        XCTAssertEqual(auth.session?.cloud?.email, "ed@example.com")
        let tokenRequest = try XCTUnwrap(recorder.requests.first(where: {
            $0.url?.path == "/auth/v1/token" && $0.url?.query?.contains("grant_type=pkce") == true
        }))
        let tokenBody = try jsonObject(from: tokenRequest)
        let verifier = try XCTUnwrap(tokenBody["code_verifier"] as? String)
        XCTAssertEqual(tokenBody["auth_code"] as? String, "test-auth-code")
        XCTAssertEqual(pkceChallenge(for: verifier), challenge)

        await auth.updatePassword("UpdatedPass9")

        XCTAssertFalse(auth.needsPasswordUpdate)
        XCTAssertEqual(auth.message, "Password updated.")
        let updateRequest = try XCTUnwrap(recorder.requests.first(where: { $0.url?.path == "/auth/v1/user" }))
        XCTAssertEqual(updateRequest.httpMethod, "PUT")
        XCTAssertEqual(updateRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        XCTAssertEqual(try jsonObject(from: updateRequest)["password"] as? String, "UpdatedPass9")
    }

    func testAndroidBackupRoundTripAndDuplicateProtection() throws {
        let sourceDirectory = try temporaryDirectory(named: "source")
        let targetDirectory = try temporaryDirectory(named: "target")
        let source = try WorkoutStore(accountStorageKey: "local_test", directoryURL: sourceDirectory)
        let bench = try source.addExercise(name: "Bench Press")
        _ = try source.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            note: "Push day",
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: bench.id,
                    sets: [
                        WorkoutSetDraft(weight: 80, reps: 8),
                        WorkoutSetDraft(weight: 82.5, reps: 6)
                    ]
                )
            ]
        )

        let owner = BackupOwner(accountID: "local_test", remote: false)
        let data = try source.exportBackupData(owner: owner)
        let target = try WorkoutStore(accountStorageKey: "local_test", directoryURL: targetDirectory)
        let first = try target.importBackup(data: data, activeOwner: owner)
        let second = try target.importBackup(data: data, activeOwner: owner)

        XCTAssertEqual(first.importedSessions, 1)
        XCTAssertEqual(first.addedExercises, 1)
        XCTAssertEqual(second.importedSessions, 0)
        XCTAssertEqual(second.skippedDuplicateSessions, 1)
        XCTAssertEqual(target.workouts.first?.exercises.first?.sets.count, 2)
    }

    func testBuiltInExerciseCatalogUsesStableKeysAndExactAliases() throws {
        XCTAssertEqual(BuiltInExerciseCatalog.definitions.count, 15)
        XCTAssertEqual(Set(BuiltInExerciseCatalog.definitions.map(\.key)).count, 15)
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Bench Press"), "bench_press")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Жим штанги лежачи"), "bench_press")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Barbell Squat"), "squat")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Присід зі штангою"), "squat")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "жим лежачи"), "bench_press")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Жим сидячи над головою"), "shoulder_press")
        XCTAssertNil(BuiltInExerciseCatalog.canonicalKey(forName: "My Bench Press Variation"))

        let legacy = Exercise(name: "Barbell Squat")
        XCTAssertEqual(legacy.name, "Barbell Squat")
        XCTAssertEqual(legacy.catalogKey, "squat")
        XCTAssertEqual(gymExerciseName(legacy, languageCode: "en"), "Squat")
        XCTAssertEqual(gymExerciseName(legacy, languageCode: "uk"), "Присідання зі штангою")

        let custom = Exercise(name: "Eduard Special Press")
        XCTAssertNil(custom.catalogKey)
        XCTAssertEqual(gymExerciseName(custom, languageCode: "uk"), custom.name)
    }

    func testLegacyExerciseJSONInfersCatalogKeyWithoutChangingRawName() throws {
        let id = UUID()
        let legacyJSON = #"{"id":"\#(id.uuidString)","name":"Станова тяга"}"#.data(using: .utf8)!

        let exercise = try JSONDecoder().decode(Exercise.self, from: legacyJSON)

        XCTAssertEqual(exercise.id, id)
        XCTAssertEqual(exercise.name, "Станова тяга")
        XCTAssertEqual(exercise.catalogKey, "deadlift")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(exercise)) as? [String: Any]
        XCTAssertEqual(encoded?["catalogKey"] as? String, "deadlift")
    }

    func testBackupCarriesCatalogKeyAndLegacyBackupInfersIt() throws {
        let source = try WorkoutStore(
            accountStorageKey: "catalog-source",
            directoryURL: try temporaryDirectory(named: "catalog-source")
        )
        let squat = try source.addExercise(name: "Присідання зі штангою")
        _ = try source.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: squat.id,
                    sets: [.init(weight: 80, reps: 8)]
                )
            ]
        )
        let owner = BackupOwner(accountID: "catalog-source", remote: false)
        let data = try source.exportBackupData(owner: owner)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exercises = try XCTUnwrap(object["exercises"] as? [[String: Any]])
        XCTAssertEqual(exercises.first?["catalogKey"] as? String, "squat")
        let sessions = try XCTUnwrap(object["sessions"] as? [[String: Any]])
        let workoutExercises = try XCTUnwrap(sessions.first?["exercises"] as? [[String: Any]])
        XCTAssertEqual(workoutExercises.first?["catalogKey"] as? String, "squat")

        object["exercises"] = exercises.map { item in
            var legacy = item
            legacy.removeValue(forKey: "catalogKey")
            return legacy
        }
        object["sessions"] = sessions.map { session in
            var legacySession = session
            if let blocks = session["exercises"] as? [[String: Any]] {
                legacySession["exercises"] = blocks.map { block in
                    var legacyBlock = block
                    legacyBlock.removeValue(forKey: "catalogKey")
                    return legacyBlock
                }
            }
            return legacySession
        }
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let target = try WorkoutStore(
            accountStorageKey: "catalog-target",
            directoryURL: try temporaryDirectory(named: "catalog-target")
        )
        let result = try target.importBackup(
            data: legacyData,
            activeOwner: BackupOwner(accountID: "catalog-target", remote: false)
        )

        XCTAssertEqual(result.addedExercises, 1)
        XCTAssertEqual(target.exercises.first?.name, "Присідання зі штангою")
        XCTAssertEqual(target.exercises.first?.catalogKey, "squat")
        XCTAssertEqual(target.exercises.first.map { gymExerciseName($0, languageCode: "en") }, "Squat")
    }

    func testImportReusesExistingBuiltInAcrossLanguages() throws {
        let target = try WorkoutStore(
            accountStorageKey: "catalog-bilingual-target",
            directoryURL: try temporaryDirectory(named: "catalog-bilingual-target")
        )
        let existing = try target.addExercise(name: "Присідання зі штангою")
        let owner = BackupOwner(accountID: "catalog-bilingual-target", remote: false)
        let backup = GymBackup(
            exportedAt: 1_750_000_000_000,
            diagnostics: false,
            owner: owner,
            exercises: [BackupExercise(name: "Squat", catalogKey: "squat")],
            sessions: [
                BackupSession(
                    date: 1_750_000_000_000,
                    exercises: [
                        BackupWorkoutExercise(
                            name: "Squat",
                            catalogKey: "squat",
                            sets: [BackupSet(weight: 80, reps: 8)]
                        )
                    ]
                )
            ],
            summary: nil
        )

        let result = try target.importBackup(
            data: JSONEncoder().encode(backup),
            activeOwner: owner
        )

        XCTAssertEqual(result.addedExercises, 0)
        XCTAssertEqual(target.exercises.count, 1)
        XCTAssertEqual(target.exercises.first?.id, existing.id)
        XCTAssertEqual(target.exercises.first?.name, "Присідання зі штангою")
        XCTAssertEqual(target.workouts.first?.exercises.first?.exerciseID, existing.id)
    }

    func testExerciseCrudRejectsBuiltInAliasesAsDuplicates() throws {
        let store = try WorkoutStore(
            accountStorageKey: "catalog-duplicate-target",
            directoryURL: try temporaryDirectory(named: "catalog-duplicate-target")
        )
        let squat = try store.addExercise(name: "Присідання зі штангою")

        XCTAssertThrowsError(try store.addExercise(name: "Squat")) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .duplicateExerciseName)
        }
        let custom = try store.addExercise(name: "My custom movement")
        XCTAssertThrowsError(try store.renameExercise(id: custom.id, to: "Barbell Squat")) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .duplicateExerciseName)
        }
        XCTAssertEqual(store.exercises.map(\.id).sorted { $0.uuidString < $1.uuidString }, [squat.id, custom.id].sorted { $0.uuidString < $1.uuidString })
    }

    func testImportDoesNotRedirectRecognizedNamesWithHostileCatalogKeys() throws {
        let target = try WorkoutStore(
            accountStorageKey: "catalog-conflict-target",
            directoryURL: try temporaryDirectory(named: "catalog-conflict-target")
        )
        let bench = try target.addExercise(name: "Bench Press")
        let squat = try target.addExercise(name: "Присідання зі штангою")
        let owner = BackupOwner(accountID: "catalog-conflict-target", remote: false)
        let hostileBackup: [String: Any] = [
            "schemaVersion": GymBackup.currentSchemaVersion,
            "exportedAt": 1_750_000_000_000 as Int64,
            "app": "GymApp",
            "diagnostics": false,
            "owner": [
                "accountId": "catalog-conflict-target",
                "remote": false
            ],
            "exercises": [],
            "sessions": [[
                "date": 1_750_000_000_000 as Int64,
                "exercises": [
                    [
                        "name": "Squat",
                        "catalogKey": "bench_press",
                        "sets": [["weight": 80.0, "reps": 8]]
                    ],
                    [
                        "name": "Barbell Squat",
                        "catalogKey": "not-a-real-catalog-key",
                        "sets": [["weight": 82.5, "reps": 6]]
                    ]
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: hostileBackup, options: [.sortedKeys])

        let result = try target.importBackup(data: data, activeOwner: owner)

        XCTAssertEqual(result.addedExercises, 0)
        XCTAssertEqual(result.importedSessions, 1)
        XCTAssertEqual(target.exercises.count, 2)
        let importedWorkout = try XCTUnwrap(target.workouts.first)
        XCTAssertEqual(importedWorkout.exercises.count, 1)
        XCTAssertEqual(importedWorkout.exercises.first?.exerciseID, squat.id)
        XCTAssertEqual(importedWorkout.exercises.first?.sets.count, 2)
        XCTAssertFalse(importedWorkout.exercises.contains { $0.exerciseID == bench.id })
    }

    func testRemoteBackupCannotCrossAccounts() throws {
        let source = try WorkoutStore(accountStorageKey: "cloud_a", directoryURL: try temporaryDirectory(named: "cloud-a"))
        let exercise = try source.addExercise(name: "Squat")
        _ = try source.createWorkout(
            date: Date(),
            exercises: [WorkoutExerciseDraft(exerciseID: exercise.id, sets: [.init(weight: 100, reps: 5)])]
        )
        let data = try source.exportBackupData(
            owner: BackupOwner(accountID: "cloud_a", userID: "user-a", email: "a@example.com", remote: true)
        )
        let target = try WorkoutStore(accountStorageKey: "cloud_b", directoryURL: try temporaryDirectory(named: "cloud-b"))

        XCTAssertThrowsError(
            try target.importBackup(
                data: data,
                activeOwner: BackupOwner(accountID: "cloud_b", userID: "user-b", email: "b@example.com", remote: true)
            )
        ) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .backupOwnerMismatch)
        }
        XCTAssertThrowsError(
            try target.restoreBackup(
                data: data,
                activeOwner: BackupOwner(accountID: "cloud_b", userID: "user-b", email: "b@example.com", remote: true)
            )
        ) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .backupOwnerMismatch)
        }

        let matchingOwner = BackupOwner(
            accountID: "cloud_a",
            userID: "user-a",
            email: "a@example.com",
            remote: true
        )
        let matchingTarget = try WorkoutStore(
            accountStorageKey: "cloud_a",
            directoryURL: try temporaryDirectory(named: "cloud-owner-required")
        )
        var ownerlessObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        ownerlessObject.removeValue(forKey: "owner")
        let ownerlessData = try JSONSerialization.data(withJSONObject: ownerlessObject)
        XCTAssertThrowsError(
            try matchingTarget.importBackup(data: ownerlessData, activeOwner: matchingOwner)
        ) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .backupOwnerMismatch)
        }

        var falselyLocalObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var falselyLocalOwner = try XCTUnwrap(falselyLocalObject["owner"] as? [String: Any])
        falselyLocalOwner["remote"] = false
        falselyLocalObject["owner"] = falselyLocalOwner
        let falselyLocalData = try JSONSerialization.data(withJSONObject: falselyLocalObject)
        XCTAssertThrowsError(
            try matchingTarget.importBackup(data: falselyLocalData, activeOwner: matchingOwner)
        ) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .backupOwnerMismatch)
        }
        XCTAssertEqual(matchingTarget.snapshot, WorkoutDataSnapshot())
    }

    func testAuthenticatedPWACloudBackupsAreOwnerBoundAndReadOnly() throws {
        let owner = BackupOwner(
            accountID: "cloud_pwa-user",
            userID: "pwa-user",
            email: "pwa-user@example.com",
            remote: true
        )

        let flat = try pwaFlatCloudData(exerciseName: "PWA Bench")
        let preparedFlat = try WorkoutStore.prepareCloudBackup(flat, activeOwner: owner)
        XCTAssertFalse(preparedFlat.roundTripSafe)

        let flatTarget = try WorkoutStore(
            accountStorageKey: owner.accountID!,
            directoryURL: try temporaryDirectory(named: "pwa-flat-target")
        )
        let flatResult = try flatTarget.restoreBackup(
            data: preparedFlat.data,
            activeOwner: owner
        )
        XCTAssertEqual(flatResult.importedSessions, 1)
        XCTAssertEqual(flatTarget.exercises.map(\.name), ["PWA Bench"])

        let schemaBackup = try pwaSchemaCloudData(
            exerciseName: "PWA Squat",
            userID: "pwa-user"
        )
        let preparedSchema = try WorkoutStore.prepareCloudBackup(
            schemaBackup,
            activeOwner: owner
        )
        XCTAssertFalse(preparedSchema.roundTripSafe)
        let schemaTarget = try WorkoutStore(
            accountStorageKey: owner.accountID!,
            directoryURL: try temporaryDirectory(named: "pwa-schema-target")
        )
        _ = try schemaTarget.restoreBackup(data: preparedSchema.data, activeOwner: owner)
        XCTAssertEqual(schemaTarget.exercises.map(\.name), ["PWA Squat"])

        let native = try remoteBackupData(exerciseName: "Native Deadlift", owner: owner)
        XCTAssertTrue(
            try WorkoutStore.prepareCloudBackup(native, activeOwner: owner).roundTripSafe
        )

        let foreign = try pwaSchemaCloudData(
            exerciseName: "Foreign Secret",
            userID: "other-user"
        )
        XCTAssertThrowsError(
            try WorkoutStore.prepareCloudBackup(foreign, activeOwner: owner)
        ) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .backupOwnerMismatch)
        }
    }

    func testAuthoritativeRestoreReplacesStaleLocalSnapshot() throws {
        let owner = BackupOwner(
            accountID: "cloud_user-a",
            userID: "user-a",
            email: "a@example.com",
            remote: true
        )
        let source = try WorkoutStore(
            accountStorageKey: "cloud_source",
            directoryURL: try temporaryDirectory(named: "restore-source")
        )
        let remoteExercise = try source.addExercise(name: "Remote Squat")
        _ = try source.createWorkout(
            date: Date(timeIntervalSince1970: 1_760_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: remoteExercise.id,
                    sets: [.init(weight: 110, reps: 5)]
                )
            ]
        )
        let backup = try source.exportBackupData(owner: owner)

        let target = try WorkoutStore(
            accountStorageKey: "cloud_target",
            directoryURL: try temporaryDirectory(named: "restore-target")
        )
        let staleExercise = try target.addExercise(name: "Stale Bench")
        _ = try target.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: staleExercise.id,
                    sets: [.init(weight: 80, reps: 8)]
                )
            ]
        )
        try target.saveExerciseMuscleMapping(
            exerciseName: staleExercise.name,
            muscleIDs: ["chest"]
        )

        let result = try target.restoreBackup(data: backup, activeOwner: owner)

        XCTAssertEqual(result.importedSessions, 1)
        XCTAssertEqual(target.exercises.map(\.name), ["Remote Squat"])
        XCTAssertEqual(target.workouts.count, 1)
        XCTAssertFalse(target.workouts.contains { workout in
            workout.exercises.contains { $0.exerciseID == staleExercise.id }
        })
        XCTAssertTrue(target.muscleMappings.isEmpty)
    }

    func testFreshLocalProfileCanImportBackupFromDifferentLocalProfile() throws {
        let sourceOwner = BackupOwner(accountID: "local_source", remote: false)
        let source = try WorkoutStore(
            accountStorageKey: "local_source",
            directoryURL: try temporaryDirectory(named: "local-transfer-source")
        )
        let exercise = try source.addExercise(name: "Portable Deadlift")
        _ = try source.createWorkout(
            date: Date(timeIntervalSince1970: 1_755_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [.init(weight: 125, reps: 4)]
                )
            ]
        )
        let backup = try source.exportBackupData(owner: sourceOwner)

        let destinationOwner = BackupOwner(accountID: "local_destination", remote: false)
        let freshDestination = try WorkoutStore(
            accountStorageKey: "local_destination",
            directoryURL: try temporaryDirectory(named: "local-transfer-destination")
        )
        let result = try freshDestination.importBackup(
            data: backup,
            activeOwner: destinationOwner
        )

        XCTAssertEqual(result.importedSessions, 1)
        XCTAssertEqual(freshDestination.exercises.map(\.name), ["Portable Deadlift"])

        let occupiedDestination = try WorkoutStore(
            accountStorageKey: "local_occupied",
            directoryURL: try temporaryDirectory(named: "local-transfer-occupied")
        )
        _ = try occupiedDestination.addExercise(name: "Existing Exercise")
        XCTAssertThrowsError(
            try occupiedDestination.importBackup(
                data: backup,
                activeOwner: BackupOwner(accountID: "local_occupied", remote: false)
            )
        ) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .backupOwnerMismatch)
        }
    }

    func testExerciseDeletionCascadesWorkoutData() throws {
        let store = try WorkoutStore(accountStorageKey: "cascade", directoryURL: try temporaryDirectory(named: "cascade"))
        let exercise = try store.addExercise(name: "Deadlift")
        _ = try store.createWorkout(
            date: Date(),
            exercises: [WorkoutExerciseDraft(exerciseID: exercise.id, sets: [.init(weight: 120, reps: 5)])]
        )

        try store.deleteExercise(id: exercise.id, cascadeFromWorkouts: true)

        XCTAssertTrue(store.exercises.isEmpty)
        XCTAssertTrue(store.workouts.isEmpty)
    }

    func testDestroyAccountDataRemovesPayloadAndBackingFile() throws {
        let store = try WorkoutStore(
            accountStorageKey: "delete-me",
            directoryURL: try temporaryDirectory(named: "destroy-account")
        )
        _ = try store.addExercise(name: "Private Exercise")
        let storageURL = store.storageURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        try store.destroyAccountData()

        XCTAssertTrue(store.exercises.isEmpty)
        XCTAssertTrue(store.workouts.isEmpty)
        XCTAssertTrue(store.muscleMappings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testDestroyAccountDataLeavesOnlyEmptyEnvelopeWhenUnlinkFails() throws {
        let directory = try temporaryDirectory(named: "destroy-account-retry")
        let fileManager = RemovalFailingFileManager()
        let store = try WorkoutStore(
            accountStorageKey: "delete-me-retry",
            directoryURL: directory,
            fileManager: fileManager
        )
        _ = try store.addExercise(name: "Sensitive Exercise")
        let storageURL = store.storageURL

        XCTAssertThrowsError(try store.destroyAccountData())
        XCTAssertTrue(store.exercises.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        let reloaded = try WorkoutStore(
            accountStorageKey: "delete-me-retry",
            directoryURL: directory
        )
        XCTAssertTrue(reloaded.exercises.isEmpty)
        XCTAssertTrue(reloaded.workouts.isEmpty)
        XCTAssertTrue(reloaded.muscleMappings.isEmpty)

        fileManager.failRemoval = false
        try store.destroyAccountData()
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testCorruptStoreIsPreservedBeforeFreshStoreOpens() throws {
        let directory = try temporaryDirectory(named: "corrupt-store-recovery")
        let original = try WorkoutStore(
            accountStorageKey: "recover-me",
            directoryURL: directory
        )
        _ = try original.addExercise(name: "Preserve Me")
        let originalURL = original.storageURL
        let damagedPayload = Data("{damaged-json".utf8)
        try damagedPayload.write(to: originalURL, options: .atomic)

        let result = try WorkoutStore.openRecoveringCorruptStore(
            accountStorageKey: "recover-me",
            directoryURL: directory
        )

        let quarantineURL = try XCTUnwrap(result.quarantinedFileURL)
        XCTAssertEqual(try Data(contentsOf: quarantineURL), damagedPayload)
        XCTAssertTrue(result.store.exercises.isEmpty)
        XCTAssertTrue(result.store.workouts.isEmpty)

        _ = try result.store.addExercise(name: "Fresh Store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantineURL.path))
    }

    func testMuscleMappingMatchesAndroidBenchPressWeights() {
        let map = Dictionary(uniqueKeysWithValues: MuscleMappingEngine.defaultContributions(for: "Bench Press").map { ($0.muscleID, $0.weight) })
        XCTAssertEqual(map["chest"], 0.85)
        XCTAssertEqual(map["triceps"], 0.55)
        XCTAssertEqual(map["shoulders"], 0.45)
    }

    func testActivityHeatmapShowsEveryDayOfCurrentFiveWeekMonth() throws {
        let calendar = utcCalendar()
        let month = try utcDate(year: 2026, month: 7, day: 15, calendar: calendar)
        let now = try utcDate(year: 2026, month: 7, day: 11, calendar: calendar)
        let firstSessionDate = try utcDate(year: 2026, month: 7, day: 1, calendar: calendar)
        let lastSessionDate = try utcDate(year: 2026, month: 7, day: 31, calendar: calendar)
        let sessions = [
            WorkoutSessionSummary(
                workoutID: UUID(),
                date: firstSessionDate,
                note: nil,
                exerciseCount: 1,
                setCount: 1,
                totalVolume: 100
            ),
            WorkoutSessionSummary(
                workoutID: UUID(),
                date: lastSessionDate,
                note: nil,
                exerciseCount: 1,
                setCount: 1,
                totalVolume: 500
            )
        ]

        let days = WorkoutActivityHeatmapLayout.days(
            month: month,
            sessions: sessions,
            now: now,
            calendar: calendar
        )
        let monthDays = days.filter(\.isInMonth)

        XCTAssertEqual(days.count, 35)
        XCTAssertEqual(monthDays.count, 31)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(monthDays.first?.date)), 1)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(monthDays.last?.date)), 31)
        XCTAssertEqual(days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: firstSessionDate) }), 2)
        XCTAssertEqual(monthDays.first(where: { calendar.isDate($0.date, inSameDayAs: firstSessionDate) })?.sessionCount, 1)
        XCTAssertEqual(monthDays.first(where: { calendar.isDate($0.date, inSameDayAs: lastSessionDate) })?.sessionCount, 1)
        XCTAssertEqual(days.filter(\.isToday).map { calendar.component(.day, from: $0.date) }, [11])
    }

    func testActivityHeatmapUsesSixRowsWhenMonthSpansSixWeeks() throws {
        let calendar = utcCalendar()
        let month = try utcDate(year: 2026, month: 8, day: 15, calendar: calendar)
        let now = try utcDate(year: 2026, month: 8, day: 17, calendar: calendar)

        let days = WorkoutActivityHeatmapLayout.days(
            month: month,
            sessions: [],
            now: now,
            calendar: calendar
        )
        let monthDays = days.filter(\.isInMonth)

        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(monthDays.count, 31)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(monthDays.first?.date)), 1)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(monthDays.last?.date)), 31)
        XCTAssertEqual(days.filter(\.isToday).map { calendar.component(.day, from: $0.date) }, [17])
    }

    func testAnatomicalSourceGeometryParsesAndMapsCoreRegions() {
        XCTAssertEqual(OpenSourceMuscleRegions.front.count, 40)
        XCTAssertEqual(OpenSourceMuscleRegions.back.count, 49)

        for region in OpenSourceMuscleRegions.front + OpenSourceMuscleRegions.back {
            let path = SVGPathParser.path(from: region.pathData)
            XCTAssertFalse(path.isEmpty, "Expected a path for \(region.id)")
            XCTAssertGreaterThan(path.boundingRect.width, 0, "Expected width for \(region.id)")
            XCTAssertGreaterThan(path.boundingRect.height, 0, "Expected height for \(region.id)")
        }

        XCTAssertEqual(MuscleBodyRegionMapping.muscleID(for: "chest-upper-left"), "chest")
        XCTAssertEqual(MuscleBodyRegionMapping.muscleID(for: "traps-mid-right"), "upperBack")
        XCTAssertEqual(MuscleBodyRegionMapping.muscleID(for: "gluteus-maximus-left"), "glutes")
        XCTAssertEqual(MuscleBodyRegionMapping.muscleID(for: "tibialis-anterior-right"), "calves")
        XCTAssertNil(MuscleBodyRegionMapping.muscleID(for: "head"))
    }

    func testNewExerciseRecommendationUsesThreeTenRepSets() {
        let exercise = Exercise(name: "Cable Fly")
        let recommendation = RecommendationEngine.buildForExercise(exerciseID: exercise.id, history: [])
        XCTAssertEqual(recommendation.kind, .newExercise)
        XCTAssertEqual(recommendation.sets.count, 3)
        XCTAssertEqual(recommendation.sets.map(\.reps), [10, 10, 10])
        XCTAssertTrue(recommendation.sets.allSatisfy { $0.weight == nil })
    }

    func testPostWorkoutXPFormulaParity() {
        let summary = WorkoutSessionSummary(
            workoutID: UUID(),
            date: Date(),
            note: nil,
            exerciseCount: 2,
            setCount: 5,
            totalVolume: 1_200
        )
        XCTAssertEqual(GamificationEngine.xpForSession(summary), 177)
    }

    func testProgressionIgnoresEmptySessionsAndCapsSessionXP() {
        let empty = WorkoutSessionSummary(
            workoutID: UUID(),
            date: Date(),
            note: nil,
            exerciseCount: 1,
            setCount: 0,
            totalVolume: 10_000
        )
        let oversized = WorkoutSessionSummary(
            workoutID: UUID(),
            date: Date(),
            note: nil,
            exerciseCount: Int.max,
            setCount: Int.max,
            totalVolume: .greatestFiniteMagnitude
        )

        XCTAssertEqual(GamificationEngine.xpForSession(empty), 0)
        XCTAssertEqual(GamificationEngine.xpForSession(oversized), 5_000)
    }

    func testWorkoutStoreAllowsMoreThanFiveSessionsOnOneDay() throws {
        let calendar = utcCalendar()
        let day = try utcDate(year: 2026, month: 7, day: 13, calendar: calendar)
        let store = try WorkoutStore(
            accountStorageKey: "six-sessions-one-day",
            directoryURL: try temporaryDirectory(named: "six-sessions-one-day")
        )
        let exercise = try store.addExercise(name: "Bench Press")

        for offset in 0..<6 {
            _ = try store.createWorkout(
                date: day.addingTimeInterval(Double(offset * 60)),
                exercises: [
                    WorkoutExerciseDraft(
                        exerciseID: exercise.id,
                        sets: [WorkoutSetDraft(weight: 10, reps: 10)]
                    )
                ]
            )
        }

        let sessions = store.workoutSummaries
        let snapshot = GamificationEngine.buildSnapshot(
            sessions: sessions,
            now: day,
            calendar: calendar
        )
        XCTAssertEqual(sessions.count, 6)
        XCTAssertEqual(snapshot.summary.workoutCount, 6)
        XCTAssertEqual(snapshot.summary.workoutDayCount, 1)
        XCTAssertEqual(
            snapshot.progression.totalXP,
            sessions.reduce(0) { $0 + GamificationEngine.xpForSession($1) }
        )
    }

    func testCanonicalProgressionMatchesCrossPlatformGoldenFixture() throws {
        let calendar = utcCalendar()

        for row in try progressionGoldenRows() {
            let sessions = row.sessions.enumerated().map { index, input in
                WorkoutSessionSummary(
                    workoutID: UUID(),
                    date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 86_400)),
                    note: nil,
                    exerciseCount: input.exerciseCount,
                    setCount: input.setCount,
                    totalVolume: input.volume
                )
            }
            let snapshot = GamificationEngine.buildSnapshot(
                sessions: sessions,
                now: Date(timeIntervalSince1970: 1_800_000_000),
                calendar: calendar
            )

            XCTAssertEqual(sessions.reduce(0) { $0 + GamificationEngine.xpForSession($1) }, row.totalXP, row.id)
            XCTAssertEqual(snapshot.progression.totalXP, row.totalXP, row.id)
            XCTAssertEqual(snapshot.progression.baseXP, row.totalXP, row.id)
            XCTAssertEqual(snapshot.progression.bonusXP, 0, row.id)
            XCTAssertEqual(snapshot.progression.level, row.level, row.id)
            XCTAssertEqual(GamificationEngine.xpForLevelStart(row.level), row.levelStartXP, row.id)
            XCTAssertEqual(GamificationEngine.xpForLevelStart(row.level + 1), row.nextLevelXP, row.id)
        }
    }

    func testProgressionHandlesMaximumXPWithoutLinearLevelScanning() {
        XCTAssertEqual(GamificationEngine.level(for: Int.max), 1_512_304)
        XCTAssertEqual(
            GamificationEngine.xpForLevelStart(1_512_304),
            9_223_363_383_716_056_445
        )
        XCTAssertEqual(GamificationEngine.xpForLevelStart(1_512_305), Int.max)
    }

    func testWorkoutStorageAndFilesAreExcludedFromBackup() throws {
        let directory = try temporaryDirectory(named: "backup-exclusion")
        let store = try WorkoutStore(accountStorageKey: "private-account", directoryURL: directory)
        _ = try store.addExercise(name: "Private Exercise")

        XCTAssertEqual(
            try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        XCTAssertEqual(
            try store.storageURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
    }

    func testDestroyAccountDataRemovesOnlyMatchingRecoveryCopies() throws {
        let directory = try temporaryDirectory(named: "recovery-deletion")
        let store = try WorkoutStore(accountStorageKey: "delete-recovery", directoryURL: directory)
        _ = try store.addExercise(name: "Private Exercise")
        let stem = store.storageURL.deletingPathExtension().lastPathComponent
        let matchingRecovery = directory.appendingPathComponent(
            "\(stem).recovery-\(UUID().uuidString.lowercased()).json"
        )
        try Data("private recovery".utf8).write(to: matchingRecovery)

        let otherStore = try WorkoutStore(accountStorageKey: "keep-recovery", directoryURL: directory)
        let otherStem = otherStore.storageURL.deletingPathExtension().lastPathComponent
        let otherRecovery = directory.appendingPathComponent(
            "\(otherStem).recovery-\(UUID().uuidString.lowercased()).json"
        )
        try Data("other account".utf8).write(to: otherRecovery)

        try store.destroyAccountData()

        XCTAssertFalse(FileManager.default.fileExists(atPath: matchingRecovery.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherRecovery.path))
    }

    func testBackupImportRejectsOversizedUnicodeBeforeMutation() throws {
        let store = try WorkoutStore(
            accountStorageKey: "unicode-limit",
            directoryURL: try temporaryDirectory(named: "unicode-limit")
        )
        let maliciousName = "a" + String(repeating: "\u{0301}", count: 321)
        XCTAssertEqual(maliciousName.count, 1)
        XCTAssertGreaterThan(maliciousName.utf8.count, BackupImportLimits.standard.maximumExerciseNameBytes)
        let object: [String: Any] = [
            "schemaVersion": GymBackup.currentSchemaVersion,
            "exportedAt": 1_750_000_000_000 as Int64,
            "app": "GymApp",
            "diagnostics": false,
            "exercises": [["name": maliciousName]],
            "sessions": []
        ]
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try store.importBackup(data: data))
        XCTAssertEqual(store.snapshot, WorkoutDataSnapshot())
    }

    func testBackupImportRejectsDeepJSONAndOversizedFileBeforeMutation() throws {
        let store = try WorkoutStore(
            accountStorageKey: "json-limits",
            directoryURL: try temporaryDirectory(named: "json-limits")
        )
        let nested = String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)
        let deepJSON = """
        {"schemaVersion":2,"exportedAt":1750000000000,"diagnostics":false,"exercises":[],"sessions":[],"unknown":\(nested)}
        """
        XCTAssertThrowsError(try store.importBackup(json: deepJSON))

        let escapedString = String(
            repeating: "\\u0061",
            count: BackupImportLimits.standard.maximumJSONStringBytes / 6 + 1
        )
        let escapedJSON = """
        {"schemaVersion":2,"exportedAt":1750000000000,"diagnostics":false,"exercises":[],"sessions":[],"unknown":"\(escapedString)"}
        """
        XCTAssertThrowsError(try store.importBackup(json: escapedJSON))

        let oversized = Data(
            repeating: 0x20,
            count: BackupImportLimits.standard.maximumFileBytes + 1
        )
        XCTAssertThrowsError(try store.importBackup(data: oversized))
        XCTAssertEqual(store.snapshot, WorkoutDataSnapshot())
    }

    func testBackupFileReaderEnforcesActualByteCount() throws {
        let directory = try temporaryDirectory(named: "bounded-reader")
        let file = directory.appendingPathComponent("backup.json")
        try Data(repeating: 0x41, count: 1_025).write(to: file)

        XCTAssertThrowsError(try BackupFileReader.read(from: file, maximumBytes: 1_024))
        XCTAssertEqual(
            try BackupFileReader.read(from: file, maximumBytes: 1_025).count,
            1_025
        )
    }

    func testLegacyBackupImportLimitsDecodeWithNewSecurityDefaults() throws {
        let legacy = Data("""
        {"maximumFileBytes":1024,"maximumExercises":10,"maximumSessions":20,"maximumExercisesPerSession":5,"maximumSetsPerExercise":6,"maximumTotalSets":30,"maximumExerciseNameLength":80,"maximumNoteLength":500}
        """.utf8)
        let decoded = try JSONDecoder().decode(BackupImportLimits.self, from: legacy)

        XCTAssertEqual(decoded.maximumFileBytes, 1_024)
        XCTAssertEqual(decoded.maximumExerciseNameBytes, BackupImportLimits.standard.maximumExerciseNameBytes)
        XCTAssertEqual(decoded.maximumNoteBytes, BackupImportLimits.standard.maximumNoteBytes)
        XCTAssertEqual(decoded.maximumJSONStringBytes, BackupImportLimits.standard.maximumJSONStringBytes)
        XCTAssertEqual(decoded.maximumJSONNestingDepth, BackupImportLimits.standard.maximumJSONNestingDepth)
    }

    func testExtremeBackupTimestampsAreRejectedWithoutTrapping() throws {
        let store = try WorkoutStore(
            accountStorageKey: "timestamp-limits",
            directoryURL: try temporaryDirectory(named: "timestamp-limits")
        )
        let floatingTimestamp = Data("""
        {"schemaVersion":2,"exportedAt":1e308,"diagnostics":false,"exercises":[],"sessions":[]}
        """.utf8)
        XCTAssertThrowsError(try store.importBackup(data: floatingTimestamp))

        let extremeSession = Data("""
        {"schemaVersion":2,"exportedAt":1750000000000,"diagnostics":false,"exercises":[],"sessions":[{"date":9223372036854775807,"exercises":[]}]}
        """.utf8)
        XCTAssertThrowsError(try store.importBackup(data: extremeSession))
        XCTAssertThrowsError(
            try store.makeBackup(exportedAt: Date(timeIntervalSince1970: .infinity))
        )
        XCTAssertEqual(store.snapshot, WorkoutDataSnapshot())
    }

    func testGarminPlanAcceptsSixtySetsAndRejectsSixtyOneAndInvalidNumbers() throws {
        let valid = garminPlan(setCount: 60)
        XCTAssertNoThrow(try GarminPlanValidator.validate(valid))
        XCTAssertThrowsError(try GarminPlanValidator.validate(garminPlan(setCount: 61)))

        let twoHundredByteName = String(repeating: "🙂", count: 50)
        let exactlyBoundedNames = garminPlan(setCount: 60, exerciseName: twoHundredByteName)
        let oversizedFlattenedNames = garminPlan(
            setCount: 60,
            exerciseName: twoHundredByteName + "a"
        )
        XCTAssertNoThrow(try GarminPlanValidator.validate(exactlyBoundedNames))
        XCTAssertThrowsError(try GarminPlanValidator.validate(oversizedFlattenedNames))

        let invalidNumber = GarminWorkoutPlan(
            source: valid.source,
            version: valid.version,
            title: valid.title,
            createdAt: valid.createdAt,
            startedAt: valid.startedAt,
            note: valid.note,
            exercises: [
                GarminPlanExercise(
                    name: "Squat",
                    sets: [GarminPlanSet(weight: .nan, reps: 8, orderIndex: 0)]
                )
            ]
        )
        XCTAssertThrowsError(try GarminPlanValidator.validate(invalidNumber))

        let oversizedName = "a" + String(repeating: "\u{0301}", count: 321)
        let invalidName = GarminWorkoutPlan(
            source: valid.source,
            version: valid.version,
            title: valid.title,
            createdAt: valid.createdAt,
            startedAt: valid.startedAt,
            note: valid.note,
            exercises: [
                GarminPlanExercise(
                    name: oversizedName,
                    sets: [GarminPlanSet(weight: 100, reps: 8, orderIndex: 0)]
                )
            ]
        )
        XCTAssertThrowsError(try GarminPlanValidator.validate(invalidName))

        let oversizedMetadata = GarminWorkoutPlan(
            source: valid.source,
            version: valid.version,
            title: String(repeating: "T", count: 121),
            createdAt: valid.createdAt,
            startedAt: valid.startedAt,
            note: String(repeating: "n", count: 2_001),
            exercises: valid.exercises
        )
        XCTAssertThrowsError(try GarminPlanValidator.validate(oversizedMetadata))
    }

    func testFailedKeychainDeletionCannotResurrectSessionAfterRelaunch() throws {
        let keychain = InMemoryKeychainStore()
        let defaults = temporaryDefaults(named: "keychain-delete")
        let cloud = cloudSession(userID: "keychain-user")
        try keychain.save(
            JSONEncoder().encode(AppAccountSession.cloud(cloud)),
            account: "current-session"
        )
        let auth = AuthService(keychain: keychain, defaults: defaults)
        XCTAssertEqual(auth.session?.cloud?.userID, cloud.userID)

        keychain.accountsThatFailDeletion = ["current-session"]
        XCTAssertThrowsError(try auth.clearSession())
        XCTAssertNil(auth.session)

        let relaunched = AuthService(keychain: keychain, defaults: defaults)
        XCTAssertNil(relaunched.session)
        keychain.accountsThatFailDeletion = []
        try relaunched.clearSession()

        let cleanedRelaunch = AuthService(keychain: keychain, defaults: defaults)
        XCTAssertNil(cleanedRelaunch.session)
        XCTAssertNil(try keychain.read(account: "current-session"))
    }

    func testLateTokenRefreshCannotResurrectSignedOutSession() async throws {
        let keychain = InMemoryKeychainStore()
        let defaults = temporaryDefaults(named: "late-refresh")
        var expired = cloudSession(userID: "refresh-user")
        expired.expiresAt = Date(timeIntervalSince1970: 0)
        try keychain.save(
            JSONEncoder().encode(AppAccountSession.cloud(expired)),
            account: "current-session"
        )

        let started = expectation(description: "refresh started")
        let release = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let auth = AuthService(keychain: keychain, urlSession: session, defaults: defaults)
        AuthURLProtocolStub.handler = { request in
            started.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"user":{"id":"refresh-user","email":"refresh@example.com","user_metadata":{"display_name":"Refresh"}}}"#
            )
        }
        defer {
            release.signal()
            AuthURLProtocolStub.handler = nil
            session.invalidateAndCancel()
        }

        let refresh = Task { try await auth.validCloudSession() }
        await fulfillment(of: [started], timeout: 2)
        try auth.clearSession()
        release.signal()

        do {
            _ = try await refresh.value
            XCTFail("A stale refresh must not restore the session.")
        } catch AuthServiceError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected refresh error: \(error)")
        }
        XCTAssertNil(auth.session)
        XCTAssertNil(try keychain.read(account: "current-session"))
    }

    func testCloudAccountDeletionCannotTargetAReplacementSession() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "delete-identity")
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: "replacement-user")))
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            return try AuthURLProtocolStub.response(for: request, json: "{}")
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        do {
            try await auth.deleteCloudAccountOnServer(expectedUserID: "original-user")
            XCTFail("Deletion must not follow a replacement authenticated session.")
        } catch AuthServiceError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected deletion error: \(error)")
        }
        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertEqual(auth.session?.cloud?.userID, "replacement-user")
    }

    func testPendingDeletionCleanupDoesNotClearAReplacementAccount() async throws {
        let directory = try temporaryDirectory(named: "pending-delete-replacement")
        let defaults = temporaryDefaults(named: "pending-delete-replacement")
        let deletedSession = AppAccountSession.local(id: "deleted", displayName: "Deleted")
        let replacementSession = AppAccountSession.local(id: "replacement", displayName: "Replacement")
        let deletedStore = try WorkoutStore(
            accountStorageKey: deletedSession.storageKey,
            directoryURL: directory
        )
        _ = try deletedStore.addExercise(name: "Deleted Secret")
        defaults.set(
            deletedSession.storageKey,
            forKey: "gymapp.pending-account-deletion-storage-key"
        )

        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            defaults: defaults
        )
        try auth.installSessionForTesting(replacementSession)
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory
        )

        XCTAssertEqual(auth.session?.storageKey, replacementSession.storageKey)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedStore.storageURL.path))
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
        let replacementReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(replacementReady)
        XCTAssertEqual(appState.workoutStore.accountStorageKey, replacementSession.storageKey)
    }

    func testPWACloudActivationPausesAutomaticAndManualNativeWrites() async throws {
        let directory = try temporaryDirectory(named: "pwa-read-only-activation")
        let defaults = temporaryDefaults(named: "pwa-read-only-activation")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "pwa-read-only-user")
        let pwaData = try pwaFlatCloudData(exerciseName: "Browser Workout")
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            return try AuthURLProtocolStub.response(for: request, json: "[]")
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return pwaData
            }
        )

        try auth.installSessionForTesting(.cloud(cloud))
        let accountReady = await waitUntil {
            appState.isAccountReady &&
                appState.workoutStore.exercises.map(\.name) == ["Browser Workout"]
        }
        XCTAssertTrue(accountReady)
        XCTAssertTrue(appState.isCloudWritePaused)

        _ = try appState.workoutStore.addExercise(name: "Native Local Change")
        appState.saveBeforeBackgrounding()
        await appState.forceCloudSync()
        let leaderboard = try await appState.refreshCloudLeaderboard()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(leaderboard.isEmpty)
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(recorder.requests.first?.httpMethod, "GET")
        XCTAssertEqual(recorder.requests.first?.url?.path, "/rest/v1/leaderboard_public")
        XCTAssertTrue(appState.isCloudWritePaused)
    }

    func testForeignPWAOwnerCannotReplacePersistedAccountState() async throws {
        let directory = try temporaryDirectory(named: "pwa-owner-mismatch")
        let defaults = temporaryDefaults(named: "pwa-owner-mismatch")
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            defaults: defaults
        )
        let cloud = cloudSession(userID: "expected-user")
        let session = AppAccountSession.cloud(cloud)
        let persisted = try WorkoutStore(
            accountStorageKey: session.storageKey,
            directoryURL: directory
        )
        _ = try persisted.addExercise(name: "Persisted Private Exercise")
        let foreign = try pwaSchemaCloudData(
            exerciseName: "Foreign Exercise",
            userID: "other-user"
        )
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { _ in foreign }
        )

        try auth.installSessionForTesting(session)
        let accountReady = await waitUntil { appState.isAccountReady }

        XCTAssertTrue(accountReady)
        XCTAssertEqual(
            appState.workoutStore.exercises.map(\.name),
            ["Persisted Private Exercise"]
        )
        XCTAssertTrue(appState.isCloudWritePaused)
        XCTAssertTrue(appState.statusIsError)
    }

    func testAccountActivationHidesPriorStoreAndDiscardsLateOwnerlessRestore() async throws {
        let directory = try temporaryDirectory(named: "account-race")
        let defaults = temporaryDefaults(named: "account-race")
        let keychain = InMemoryKeychainStore()
        let auth = AuthService(keychain: keychain, defaults: defaults)
        let ownerlessA = try remoteBackupData(exerciseName: "Late Account A", owner: nil)
        let cloudB = cloudSession(userID: "user-b")
        let ownerB = BackupOwner(
            accountID: AppAccountSession.cloud(cloudB).storageKey,
            userID: cloudB.userID,
            email: cloudB.email,
            remote: true
        )
        let remoteB = try remoteBackupData(exerciseName: "Account B", owner: ownerB)
        let gate = RemoteStateGate(
            values: ["user-a": ownerlessA, "user-b": remoteB],
            expectations: [
                "user-a": expectation(description: "account A load started"),
                "user-b": expectation(description: "account B load started")
            ]
        )
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { userID in try await gate.load(userID: userID) }
        )

        try auth.installSessionForTesting(.local(id: "prior", displayName: "Prior"))
        let priorReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(priorReady)
        _ = try appState.workoutStore.addExercise(name: "Prior Account Secret")

        let cloudA = cloudSession(userID: "user-a")
        try auth.installSessionForTesting(.cloud(cloudA))
        await fulfillment(of: [gate.expectation(for: "user-a")], timeout: 2)
        XCTAssertFalse(appState.isAccountReady)
        XCTAssertEqual(appState.workoutStore.exercises.map(\.name), ["Prior Account Secret"])

        try auth.installSessionForTesting(.cloud(cloudB))
        await fulfillment(of: [gate.expectation(for: "user-b")], timeout: 2)
        XCTAssertFalse(appState.isAccountReady)
        gate.release(userID: "user-b")
        let accountBReady = await waitUntil {
            appState.isAccountReady && appState.workoutStore.exercises.map(\.name) == ["Account B"]
        }
        XCTAssertTrue(accountBReady)

        gate.release(userID: "user-a")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(auth.session?.cloud?.userID, "user-b")
        XCTAssertTrue(appState.isAccountReady)
        XCTAssertEqual(appState.workoutStore.exercises.map(\.name), ["Account B"])
    }

    func testDemoDataIsExplicitAndIdempotent() throws {
        let store = try WorkoutStore(accountStorageKey: "demo", directoryURL: try temporaryDirectory(named: "demo"))
        XCTAssertTrue(store.exercises.isEmpty)
        XCTAssertTrue(try store.seedDemoData())
        XCTAssertFalse(try store.seedDemoData())
        XCTAssertEqual(store.workouts.count, 2)
    }

    private func jsonObject(from request: URLRequest) throws -> [String: Any] {
        let body = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func pkceChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func utcDate(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private func progressionGoldenRows() throws -> [ProgressionGoldenRow] {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(
            forResource: "progression-v1",
            withExtension: "tsv",
            subdirectory: "Fixtures"
        ) ?? bundle.url(forResource: "progression-v1", withExtension: "tsv")
        let fixtureURL = try XCTUnwrap(url, "Missing progression-v1.tsv")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("case_id") }
            .map { rawLine in
                let columns = rawLine.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count == 6 else {
                    throw NSError(
                        domain: "ProgressionFixture",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid fixture row: \(rawLine)"]
                    )
                }
                let sessions = try columns[1].split(separator: ";").map { encoded in
                    let values = encoded.split(separator: ",")
                    guard values.count == 3,
                          let exerciseCount = Int(values[0]),
                          let setCount = Int(values[1]),
                          let volume = Double(values[2]) else {
                        throw NSError(
                            domain: "ProgressionFixture",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid session tuple: \(encoded)"]
                        )
                    }
                    return ProgressionSessionInput(
                        exerciseCount: exerciseCount,
                        setCount: setCount,
                        volume: volume
                    )
                }
                guard let totalXP = Int(columns[2]),
                      let level = Int(columns[3]),
                      let levelStartXP = Int(columns[4]),
                      let nextLevelXP = Int(columns[5]) else {
                    throw NSError(
                        domain: "ProgressionFixture",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid expected values: \(rawLine)"]
                    )
                }
                return ProgressionGoldenRow(
                    id: String(columns[0]),
                    sessions: sessions,
                    totalXP: totalXP,
                    level: level,
                    levelStartXP: levelStartXP,
                    nextLevelXP: nextLevelXP
                )
            }
    }

    private func garminPlan(setCount: Int, exerciseName: String = "Squat") -> GarminWorkoutPlan {
        GarminWorkoutPlan(
            source: "gymapp-ios",
            version: 1,
            title: "Workout",
            createdAt: "2026-07-13T20:00:00.000Z",
            startedAt: "2026-07-13T20:00:00.000Z",
            note: "",
            exercises: [
                GarminPlanExercise(
                    name: exerciseName,
                    sets: (0 ..< setCount).map {
                        GarminPlanSet(weight: 100, reps: 8, orderIndex: $0)
                    }
                )
            ]
        )
    }

    private func cloudSession(userID: String) -> CloudAccountSession {
        CloudAccountSession(
            userID: userID,
            email: "\(userID)@example.com",
            displayName: userID,
            accessToken: "access-\(userID)",
            refreshToken: "refresh-\(userID)",
            expiresAt: Date().addingTimeInterval(3_600)
        )
    }

    private func remoteBackupData(exerciseName: String, owner: BackupOwner?) throws -> Data {
        let store = try WorkoutStore(
            accountStorageKey: "remote-source-\(UUID().uuidString)",
            directoryURL: try temporaryDirectory(named: "remote-source")
        )
        let exercise = try store.addExercise(name: exerciseName)
        _ = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [.init(weight: 100, reps: 8)]
                )
            ]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: store.exportBackupData(owner: owner)) as? [String: Any]
        )
        if owner == nil { object.removeValue(forKey: "owner") }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func pwaFlatCloudData(exerciseName: String) throws -> Data {
        let object: [String: Any] = [
            "language": "uk",
            "exercises": [["id": 1, "name": exerciseName]],
            "sessions": [[
                "id": 10,
                "startedAt": 1_750_000_000_000 as Int64,
                "note": "Browser session",
                "exerciseNames": [exerciseName],
                "sets": [[
                    "id": 11,
                    "exerciseName": exerciseName,
                    "weight": 80.0,
                    "reps": 8,
                    "orderIndex": 0
                ]]
            ]],
            "mappings": [exerciseName.lowercased(): ["chest"]],
            "profile": [
                "split": "Upper / Lower",
                "days": 4,
                "goal": "Strength",
                "calories": "Maintenance"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func pwaSchemaCloudData(exerciseName: String, userID: String) throws -> Data {
        let object: [String: Any] = [
            "schemaVersion": GymBackup.currentSchemaVersion,
            "exportedAt": 1_750_000_000_000 as Int64,
            "source": "gym-pwa",
            "owner": [
                "accountId": "remote-\(userID)",
                "userId": userID,
                "email": "\(userID)@example.com",
                "remote": "supabase"
            ],
            "exercises": [["id": 1, "name": exerciseName]],
            "sessions": [[
                "id": 10,
                "date": 1_750_000_000_000 as Int64,
                "startedAt": 1_750_000_000_000 as Int64,
                "note": "Browser export",
                "exercises": [[
                    "name": exerciseName,
                    "sets": [["id": 11, "weight": 100.0, "reps": 5]]
                ]],
                "sets": [[
                    "id": 11,
                    "exerciseName": exerciseName,
                    "weight": 100.0,
                    "reps": 5,
                    "orderIndex": 0
                ]]
            ]],
            "exerciseCatalog": [exerciseName],
            "mappings": [exerciseName.lowercased(): ["chest"]],
            "profile": [
                "split": "Upper / Lower",
                "days": 4,
                "goal": "Strength",
                "calories": "Maintenance"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func temporaryDefaults(named name: String) -> UserDefaults {
        let suiteName = "GymAppTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0 ..< 300 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private struct ProgressionSessionInput {
    let exerciseCount: Int
    let setCount: Int
    let volume: Double
}

private struct ProgressionGoldenRow {
    let id: String
    let sessions: [ProgressionSessionInput]
    let totalXP: Int
    let level: Int
    let levelStartXP: Int
    let nextLevelXP: Int
}

private final class InMemoryKeychainStore: KeychainStoring {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    var accountsThatFailDeletion = Set<String>()

    func save(_ data: Data, account: String) throws {
        lock.withLock { values[account] = data }
    }

    func read(account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func delete(account: String) throws {
        try lock.withLock {
            if accountsThatFailDeletion.contains(account) {
                throw NSError(domain: "GymAppTests.KeychainDelete", code: 1)
            }
            _ = values.removeValue(forKey: account)
        }
    }
}

@MainActor
private final class RemoteStateGate {
    private let values: [String: Data]
    private let expectations: [String: XCTestExpectation]
    private var continuations: [String: CheckedContinuation<Data?, Error>] = [:]

    init(values: [String: Data], expectations: [String: XCTestExpectation]) {
        self.values = values
        self.expectations = expectations
    }

    func expectation(for userID: String) -> XCTestExpectation {
        expectations[userID]!
    }

    func load(userID: String) async throws -> Data? {
        guard values[userID] != nil else {
            throw NSError(domain: "GymAppTests.RemoteState", code: 1)
        }
        expectations[userID]?.fulfill()
        return try await withCheckedThrowingContinuation { continuation in
            continuations[userID] = continuation
        }
    }

    func release(userID: String) {
        guard let continuation = continuations.removeValue(forKey: userID) else { return }
        continuation.resume(returning: values[userID])
    }
}

private final class AuthRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    func append(_ request: URLRequest) {
        lock.withLock { storedRequests.append(request) }
    }
}

private final class AuthURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "owrcbsrectdgaotndtxy.supabase.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let materializedRequest = try Self.materializedRequest(request)
            let (response, data) = try handler(materializedRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

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

    static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        json: String
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, Data(json.utf8))
    }
}

private final class RemovalFailingFileManager: FileManager, @unchecked Sendable {
    var failRemoval = true

    override func removeItem(at URL: URL) throws {
        if failRemoval {
            throw NSError(domain: "GymAppTests.ForcedRemovalFailure", code: 1)
        }
        try super.removeItem(at: URL)
    }
}
