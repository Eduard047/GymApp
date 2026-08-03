import Combine
import SwiftUI
import CryptoKit
import Foundation
import XCTest
@testable import GymApp

@MainActor
final class CoreParityTests: XCTestCase {
    func testHistoricalMonthKeepsTheBestWeeklyStreakReachedInThatMonth() throws {
        let calendar = utcCalendar()
        let dates = [
            (1, 6), (2, 6), (4, 6),
            (9, 6), (11, 6), (12, 6),
            (15, 6), (16, 6)
        ]
        let sessions = try dates.map { day, month in
            WorkoutSessionSummary(
                workoutID: UUID(),
                date: try utcDate(year: 2026, month: month, day: day, calendar: calendar),
                note: nil,
                exerciseCount: 1,
                setCount: 1,
                totalVolume: 100
            )
        }

        XCTAssertEqual(
            WeeklyStreakCalculator.bestDuringPeriod(
                sessions: sessions,
                from: try utcDate(year: 2026, month: 6, day: 1, calendar: calendar),
                through: try utcDate(year: 2026, month: 6, day: 30, calendar: calendar),
                calendar: calendar
            ),
            2
        )
        XCTAssertEqual(
            WeeklyStreakCalculator.current(
                sessions: sessions,
                now: try utcDate(year: 2026, month: 7, day: 23, calendar: calendar),
                calendar: calendar
            ),
            0
        )
    }

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
        let defaults = temporaryDefaults(named: "password-recovery-relaunch")
        let auth = AuthService(keychain: keychain, urlSession: session, defaults: defaults)

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let path = request.url?.path ?? ""
            let json: String
            switch path {
            case "/auth/v1/recover":
                json = "{}"
            case "/auth/v1/token":
                if request.url?.query?.contains("grant_type=refresh_token") == true {
                    json = #"{"access_token":"refreshed-access","refresh_token":"refreshed-refresh","expires_in":3600,"user":{"id":"00000000-0000-0000-0000-000000000001","email":"ed@example.com","user_metadata":{"display_name":"Eduard"}}}"#
                } else {
                    json = #"{"access_token":"test-access","refresh_token":"test-refresh","expires_in":0,"user":{"id":"00000000-0000-0000-0000-000000000001","email":"ed@example.com","user_metadata":{"display_name":"Eduard"}}}"#
                }
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

        let relaunched = AuthService(
            keychain: keychain,
            urlSession: session,
            defaults: defaults
        )
        XCTAssertTrue(relaunched.needsPasswordUpdate)
        XCTAssertEqual(relaunched.session?.cloud?.userID, "00000000-0000-0000-0000-000000000001")

        _ = try await relaunched.validCloudSession()
        let afterRefreshRelaunch = AuthService(
            keychain: keychain,
            urlSession: session,
            defaults: defaults
        )
        XCTAssertTrue(afterRefreshRelaunch.needsPasswordUpdate)
        XCTAssertEqual(afterRefreshRelaunch.session?.cloud?.accessToken, "refreshed-access")

        await afterRefreshRelaunch.updatePassword("UpdatedPass9!")

        XCTAssertFalse(afterRefreshRelaunch.needsPasswordUpdate)
        XCTAssertEqual(afterRefreshRelaunch.message, "Password updated.")
        let completedRelaunch = AuthService(
            keychain: keychain,
            urlSession: session,
            defaults: defaults
        )
        XCTAssertFalse(completedRelaunch.needsPasswordUpdate)
        XCTAssertEqual(completedRelaunch.session?.cloud?.userID, "00000000-0000-0000-0000-000000000001")
        let updateRequest = try XCTUnwrap(recorder.requests.first(where: { $0.url?.path == "/auth/v1/user" }))
        XCTAssertEqual(updateRequest.httpMethod, "PUT")
        XCTAssertEqual(updateRequest.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-access")
        let updateBody = try jsonObject(from: updateRequest)
        XCTAssertEqual(updateBody["password"] as? String, "UpdatedPass9!")
        XCTAssertNil(updateBody["current_password"])
    }

    func testSignedInPasswordChangeSendsCurrentPasswordAndKeepsSession() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "signed-in-password-change")
        )
        let cloud = cloudSession(userID: "password-change-user")
        try auth.installSessionForTesting(.cloud(cloud))
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"id":"password-change-user"}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let updated = await auth.updatePassword(
            "UpdatedSecurePass9!",
            currentPassword: "CurrentSecurePass8!"
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(auth.session?.cloud?.userID, cloud.userID)
        XCTAssertEqual(auth.message, "Password updated.")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/user")
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(cloud.accessToken)")
        let body = try jsonObject(from: request)
        XCTAssertEqual(body["password"] as? String, "UpdatedSecurePass9!")
        XCTAssertEqual(body["current_password"] as? String, "CurrentSecurePass8!")
    }

    func testPasswordChangeForcesOneRefreshAfterDirectUnauthorized() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "password-forced-refresh")
        )
        let cloud = cloudSession(userID: "password-forced-refresh-user")
        try auth.installSessionForTesting(.cloud(cloud))
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/auth/v1/user":
                let bearer = request.value(forHTTPHeaderField: "Authorization")
                if bearer == "Bearer \(cloud.accessToken)" {
                    return try AuthURLProtocolStub.response(
                        for: request,
                        statusCode: 401,
                        json: #"{"message":"JWT expired"}"#
                    )
                }
                XCTAssertEqual(bearer, "Bearer refreshed-password-access")
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"id":"password-forced-refresh-user"}"#
                )
            case "/auth/v1/token":
                XCTAssertTrue(request.url?.query?.contains("grant_type=refresh_token") == true)
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"access_token":"refreshed-password-access","refresh_token":"refreshed-password-refresh","expires_in":3600,"user":{"id":"password-forced-refresh-user","email":"password-forced-refresh-user@example.com","user_metadata":{"display_name":"Password"}}}"#
                )
            default:
                XCTFail("Unexpected forced-refresh request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let updated = await auth.updatePassword(
            "UpdatedSecurePass9!",
            currentPassword: "CurrentSecurePass8!"
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(
            recorder.requests.map(\.url?.path),
            ["/auth/v1/user", "/auth/v1/token", "/auth/v1/user"]
        )
        XCTAssertEqual(auth.session?.cloud?.accessToken, "refreshed-password-access")
    }

    func testSignOutRevokesOnlyCurrentSupabaseSession() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "local-scope-sign-out")
        )
        let cloud = cloudSession(userID: "local-sign-out-user")
        try auth.installSessionForTesting(.cloud(cloud))
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            return try AuthURLProtocolStub.response(for: request, json: "{}")
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        await auth.signOut()

        XCTAssertNil(auth.session)
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/auth/v1/logout")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "scope" })?.value,
            "local"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(cloud.accessToken)")
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
        XCTAssertEqual(BuiltInExerciseCatalog.definitions.count, 53)
        XCTAssertEqual(Set(BuiltInExerciseCatalog.definitions.map(\.key)).count, 53)
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Bench Press"), "bench_press")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Жим штанги лежачи"), "bench_press")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Barbell Squat"), "squat")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Присід зі штангою"), "squat")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "жим лежачи"), "bench_press")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Жим сидячи над головою"), "shoulder_press")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "разведение ног"), "hip_abduction")
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "Разведение ног в тренажере"), "hip_abduction")
        for alias in [
            "підтягування з брусьями",
            "підтягування з брусами",
            "підтягування с брусьями",
            "підтягування с брусами",
            "подтягивания с брусьями",
            "подтягивание с брусьями"
        ] {
            XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: alias), "assisted_dip")
        }
        XCTAssertEqual(BuiltInExerciseCatalog.canonicalKey(forName: "брусья"), "dips")
        let legacyAssistedDip = Exercise(name: "підтягування с брусьями")
        XCTAssertEqual(legacyAssistedDip.catalogKey, "assisted_dip")
        XCTAssertEqual(gymExerciseName(legacyAssistedDip, languageCode: "en"), "Assisted Dip")
        XCTAssertEqual(
            gymExerciseName(legacyAssistedDip, languageCode: "uk"),
            "Віджимання на брусах у гравітроні"
        )
        XCTAssertEqual(
            gymExerciseName(legacyAssistedDip, languageCode: "ru"),
            "Отжимания на брусьях в гравитроне"
        )
        let assistedMuscles = Set(
            MuscleMappingEngine.defaultContributions(for: legacyAssistedDip.name).map(\.muscleID)
        )
        XCTAssertTrue(assistedMuscles.contains("triceps"))
        XCTAssertFalse(assistedMuscles.contains("lats"))
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

    func testMachineLoadProfileUsesBoundedCrossClientJSONAndLegacyExerciseStillDecodes() throws {
        let profile = try MachineLoadProfile(
            direction: .higherIsHarder,
            allowedWeightsKg: [45, 47.5, 50, 55]
        )
        let exercise = Exercise(name: "Lat Pulldown", machineLoadProfile: profile)
        let encoded = try JSONEncoder().encode(exercise)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNotNil(object["loadProfile"])
        XCTAssertNil(object["machineLoadProfile"])
        XCTAssertEqual(try JSONDecoder().decode(Exercise.self, from: encoded), exercise)

        let legacy = #"{"id":"00000000-0000-4000-8000-000000000001","name":"Lat Pulldown"}"#
        XCTAssertNil(
            try JSONDecoder().decode(Exercise.self, from: Data(legacy.utf8)).machineLoadProfile
        )

        XCTAssertThrowsError(try MachineLoadProfile(
            direction: .higherIsHarder,
            allowedWeightsKg: [50, 45]
        ))
        XCTAssertThrowsError(try MachineLoadProfile(
            direction: .higherIsHarder,
            allowedWeightsKg: [45, 45]
        ))
        XCTAssertThrowsError(try MachineLoadProfile(
            direction: .higherIsHarder,
            allowedWeightsKg: Array(repeating: 1, count: 129)
        ))

        let malformed = #"{"id":"00000000-0000-4000-8000-000000000001","name":"Lat Pulldown","loadProfile":{"direction":"higherIsHarder","allowedWeightsKg":[50,45]}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Exercise.self, from: Data(malformed.utf8)))
    }

    func testMachineLoadProfileUpdateAndBackupPreserveExerciseIdentityAndHistory() throws {
        let directory = try temporaryDirectory(named: "machine-profile-source")
        let source = try WorkoutStore(accountStorageKey: "machine-profile", directoryURL: directory)
        let initial = try MachineLoadProfile(
            direction: .higherIsHarder,
            allowedWeightsKg: [45, 50, 55]
        )
        let exercise = try source.addExercise(name: "Custom Pulldown", machineLoadProfile: initial)
        try source.saveExerciseMuscleMapping(exerciseName: exercise.name, muscleIDs: ["lats"])
        _ = try source.createWorkout(
            date: Date(timeIntervalSince1970: 1_780_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [.init(weight: 50, reps: 8)]
                )
            ]
        )
        let updated = try MachineLoadProfile(
            direction: .higherIsHarder,
            allowedWeightsKg: [40, 45, 50, 55, 60]
        )

        try source.updateExerciseMachineLoadProfile(
            id: exercise.id,
            machineLoadProfile: updated
        )

        XCTAssertEqual(source.exercises.first?.id, exercise.id)
        XCTAssertEqual(source.exercises.first?.machineLoadProfile, updated)
        XCTAssertEqual(source.workouts.first?.exercises.first?.exerciseID, exercise.id)
        XCTAssertEqual(source.muscleMappings.map(\.muscleID), ["lats"])

        let owner = BackupOwner(accountID: "machine-profile", remote: false)
        let backupData = try source.exportBackupData(owner: owner)
        let backupString = try XCTUnwrap(String(data: backupData, encoding: .utf8))
        XCTAssertTrue(backupString.contains("\"loadProfile\""))
        XCTAssertFalse(backupString.contains("machineLoadProfile"))

        let restored = try WorkoutStore(
            accountStorageKey: "machine-profile",
            directoryURL: try temporaryDirectory(named: "machine-profile-target")
        )
        _ = try restored.restoreBackup(data: backupData, activeOwner: owner)
        XCTAssertEqual(restored.exercises.first?.machineLoadProfile, updated)
        XCTAssertEqual(restored.workouts.first?.exercises.first?.sets.first?.weight, 50)
    }

    func testRussianDynamicDeletionFallbackDoesNotLeakUkrainianText() {
        let exerciseName = "Жим штанги лёжа"
        XCTAssertEqual(
            gymText(
                "Delete \(exerciseName) from workout",
                "Видалити «\(exerciseName)» із тренування",
                languageCode: "ru"
            ),
            "Удалить «\(exerciseName)» из тренировки"
        )

        let date = "20 июля 2026 г."
        XCTAssertEqual(
            gymText(
                "The workout from \(date) and all of its sets will be removed from this device.",
                "Тренування за \(date) і всі його підходи буде видалено з цього пристрою.",
                languageCode: "ru"
            ),
            "Тренировка за \(date) и все её подходы будут удалены с этого устройства."
        )
    }

    func testRussianDynamicDashboardAndGarminFallbacksAreFullyLocalized() {
        let muscleName = gymText("Shoulders", "Плечі", languageCode: "ru")
        XCTAssertEqual(muscleName, "Плечи")
        XCTAssertEqual(
            gymText(
                "\(muscleName) loaded by",
                "Навантаження для «\(muscleName)»",
                languageCode: "ru"
            ),
            "Нагрузка для «Плечи»"
        )

        let error = "Сервер недоступен."
        XCTAssertEqual(
            gymText(
                "Workout saved, but Garmin queue failed: \(error)",
                "Тренування збережено, але додати до черги Garmin не вдалося: \(error)",
                languageCode: "ru"
            ),
            "Тренировка сохранена, но не удалось добавить в очередь Garmin: \(error)"
        )

        let date = "20 июля 2026 г."
        XCTAssertEqual(
            gymText(
                "Workout · \(date)",
                "Тренування · \(date)",
                languageCode: "ru"
            ),
            "Тренировка · \(date)"
        )

        XCTAssertEqual(
            gymText(
                "Adds or removes \(muscleName) from the manual mapping",
                "Додає або видаляє «\(muscleName)» у ручному зіставленні",
                languageCode: "ru"
            ),
            "Добавляет или удаляет «Плечи» в ручном сопоставлении"
        )
    }

    func testRussianDynamicFallbackLocalizesEveryMuscleTitle() {
        let titles = [
            ("Chest", "Груди", "Грудь"),
            ("Shoulders", "Плечі", "Плечи"),
            ("Biceps", "Біцепс", "Бицепс"),
            ("Triceps", "Тріцепс", "Трицепс"),
            ("Forearms", "Передпліччя", "Предплечья"),
            ("Abs", "Прес", "Пресс"),
            ("Obliques", "Косі мʼязи", "Косые мышцы"),
            ("Lats", "Широчайші", "Широчайшие"),
            ("Upper back", "Верх спини", "Верх спины"),
            ("Lower back", "Поперек", "Поясница"),
            ("Glutes", "Сідниці", "Ягодицы"),
            ("Quads", "Квадрицепси", "Квадрицепсы"),
            ("Hamstrings", "Біцепс стегна", "Бицепс бедра"),
            ("Adductors", "Привідні", "Приводящие мышцы"),
            ("Calves", "Ікри", "Икры")
        ]

        for (english, ukrainian, russian) in titles {
            XCTAssertEqual(
                gymText(english, ukrainian, languageCode: "ru"),
                russian,
                english
            )
        }
    }

    func testRussianExactFallbackLocalizesProtectedProgressCopy() {
        let copies = [
            (
                "Protected progress",
                "Захищений прогрес",
                "Защищённый прогресс"
            ),
            (
                "Report sent. The display name was added to the moderation queue.",
                "Скаргу надіслано. Ім’я додано до черги модерації.",
                "Жалоба отправлена. Имя добавлено в очередь модерации."
            ),
            (
                "This is an offline account. Sign in with a cloud account to protect and synchronize your progress; your workouts remain available on this device.",
                "Це офлайн-акаунт. Увійди у хмарний акаунт, щоб захистити й синхронізувати прогрес; твої тренування залишаються на цьому пристрої.",
                "Это офлайн-аккаунт. Войди в облачный аккаунт, чтобы защитить и синхронизировать прогресс; твои тренировки останутся доступными на этом устройстве."
            ),
            (
                "Exercise",
                "Вправа",
                "Упражнение"
            ),
            (
                "Volume = weight × reps across all completed sets.",
                "Обсяг = вага × повтори в усіх виконаних підходах.",
                "Объём = вес × повторения во всех завершённых подходах."
            ),
            (
                "This list changes with the selected month and exercise.",
                "Список оновлюється для вибраного місяця і вправи.",
                "Список меняется в зависимости от выбранных месяца и упражнения."
            ),
            (
                "Delete this set?",
                "Видалити цей підхід?",
                "Удалить этот подход?"
            ),
            (
                "Session volume chart",
                "Графік обсягу сесій",
                "График объёма по сессиям"
            )
        ]

        for (english, ukrainian, russian) in copies {
            XCTAssertEqual(
                gymText(english, ukrainian, languageCode: "ru"),
                russian,
                english
            )
        }
    }

    func testFinalCatalogQACopyIsExactInRussianAndUkrainian() {
        let russian: [String: String] = [
            "Shows exercise contributions for this muscle": "Показывает вклад упражнений в нагрузку на эту мышцу",
            "This removes the workout and every set. This action cannot be undone.": "Тренировка и все её подходы будут удалены. Это действие нельзя отменить.",
            "Build smart workout": "Создать умную тренировку",
            "+2.5": "+2,5",
            "Email": "Электронная почта",
            "Momentum": "Темп",
            "Achievements": "Достижения",
            "Resend confirmation email": "Повторно отправить письмо с подтверждением",
            "Your training history and next best move.": "Твоя история тренировок и следующий лучший шаг.",
            "Import backup": "Импорт резервной копии",
            "Balanced": "Баланс",
            "Sign in to keep workouts synchronized across your devices.": "Войди, чтобы синхронизировать тренировки между устройствами.",
            "Avg volume": "Сред. объём",
            "Recent unlocks and the next solo milestones.": "Последние достижения и ближайшие личные цели.",
            "Total Reps": "Всего повторений",
            "Last": "Последний вес",
            "Previous": "Предыдущий подход"
        ]
        for (english, expected) in russian {
            XCTAssertEqual(gymLocalized(english, languageCode: "ru"), expected, english)
        }

        let ukrainian: [String: String] = [
            "Previous workout copied. Adjust any set before saving.": "Попереднє тренування скопійовано. За потреби зміни підходи перед збереженням.",
            "Email": "Електронна пошта",
            "Last": "Остання вага",
            "Previous": "Попередній підхід"
        ]
        for (english, expected) in ukrainian {
            XCTAssertEqual(gymLocalized(english, languageCode: "uk"), expected, english)
        }
    }

    func testRussianDynamicFallbackLocalizesLeaderboardAndProgressValues() {
        let values = [
            (
                "Your current place: #4",
                "Твоє поточне місце: №4",
                "Твоё текущее место: №4"
            ),
            (
                "Updated just now",
                "Оновлено только что",
                "Обновлено только что"
            ),
            (
                "Place 2, Athlete",
                "Місце 2, Athlete",
                "Место 2, Athlete"
            ),
            (
                "120 XP, level 3, 4 workouts, current user",
                "120 XP, рівень 3, 4 тренировки, поточний користувач",
                "120 XP, уровень 3, 4 тренировки, текущий пользователь"
            ),
            (
                "3 this month",
                "3 цього місяця",
                "3 в этом месяце"
            ),
            (
                "3 sets",
                "3 підх.",
                "3 подх."
            ),
            (
                "8 reps",
                "8 повторів",
                "8 повторов"
            ),
            (
                "3 sessions in the selected month.",
                "3 сес. у вибраному місяці.",
                "3 сес. в выбранном месяце."
            ),
            (
                "No лучший вес in this month",
                "Немає показника «лучший вес» цього місяця",
                "Нет показателя «лучший вес» в этом месяце"
            ),
            (
                "First month for объём",
                "Перший місяць для «объём»",
                "Первый месяц для «объём»"
            ),
            (
                "+10 кг vs prior month",
                "+10 кг до попереднього місяця",
                "+10 кг по сравнению с предыдущим месяцем"
            ),
            (
                "80 кг × 8 reps will be removed. If it is the final set, its exercise or workout will also be removed.",
                "80 кг × 8 повт. буде видалено. Якщо це останній підхід, вправу або тренування також буде видалено.",
                "80 кг × 8 повторений будет удалено. Если это последний подход, упражнение или тренировка также будут удалены."
            ),
            (
                "Last 4 sessions in the selected month.",
                "Останні 4 сес. у вибраному місяці.",
                "Последние 4 сес. в выбранном месяце."
            ),
            (
                "+5 кг vs first session",
                "+5 кг до першої сесії",
                "+5 кг по сравнению с первой сессией"
            ),
            (
                "2 load, 3 sets, selected",
                "навантаження 2, 3 подхода, вибрано",
                "нагрузка 2, 3 подхода, выбрано"
            ),
            (
                "Hide password",
                "Сховати поле «пароль»",
                "Скрыть поле «пароль»"
            )
        ]

        for (english, ukrainian, russian) in values {
            XCTAssertEqual(
                gymText(english, ukrainian, languageCode: "ru"),
                russian,
                english
            )
        }
    }

    func testUnknownAndRawErrorsUseLocalizedGenericCopyWithoutLeakingDetails() {
        let marker = "provider-private-marker-do-not-display"
        let rawErrors: [Error] = [
            NSError(
                domain: "GymAppTests.RawProvider",
                code: 418,
                userInfo: [NSLocalizedDescriptionKey: marker]
            ),
            AuthServiceError.server(marker),
            CloudSyncError.requestFailed(marker),
            GarminCloudError.requestFailed(statusCode: 502, message: marker),
            KeychainStoreError.unexpectedStatus(-25_300),
            WorkoutStoreError.corruptStore(marker),
            WorkoutStoreError.invalidWorkout(marker),
            WorkoutStoreError.unsupportedBackupSchema(999),
            WorkoutStoreError.malformedBackup(marker),
            WorkoutStoreError.importLimitExceeded(marker),
            WorkoutStoreError.persistenceFailure(marker)
        ]
        let expected = [
            "en": "Something went wrong. Try again.",
            "uk": "Щось пішло не так. Спробуй ще раз.",
            "ru": "Что-то пошло не так. Попробуй ещё раз."
        ]

        for error in rawErrors {
            for (languageCode, message) in expected {
                let rendered = gymErrorMessage(error, languageCode: languageCode)
                XCTAssertEqual(rendered, message)
                XCTAssertFalse(rendered.contains(marker))
                XCTAssertFalse(rendered.contains("502"))
                XCTAssertFalse(rendered.contains("999"))
                XCTAssertFalse(rendered.contains("25300"))
            }
        }

        let rawDynamicMessages = [
            "The local workout store is invalid: \(marker)",
            "The workout is invalid: \(marker)",
            "The backup is invalid: \(marker)",
            "Workout data could not be saved: \(marker)",
            "Unsupported local schema 999.",
            "Backup schema version 999 is not supported.",
            "The backup exceeds the allowed \(marker) limit.",
            "The secure session could not be accessed (-25300).",
            "Cloud sync failed (HTTP 502).",
            "Garmin cloud sync failed (HTTP 502)."
        ]
        for rawMessage in rawDynamicMessages {
            for (languageCode, message) in expected {
                let rendered = gymLocalized(rawMessage, languageCode: languageCode)
                XCTAssertEqual(rendered, message)
                XCTAssertFalse(rendered.contains(marker))
                XCTAssertFalse(rendered.contains("502"))
                XCTAssertFalse(rendered.contains("999"))
                XCTAssertFalse(rendered.contains("25300"))
            }
        }
    }

    func testSafeTypedAndRecognizedAuthErrorsRemainLocalized() {
        for languageCode in ["en", "uk", "ru"] {
            XCTAssertEqual(
                gymErrorMessage(AuthServiceError.invalidEmail, languageCode: languageCode),
                gymLocalized("Enter a valid email address.", languageCode: languageCode)
            )
            XCTAssertEqual(
                gymErrorMessage(
                    AuthServiceError.server("Invalid login credentials: provider detail"),
                    languageCode: languageCode
                ),
                gymLocalized("Email or password is incorrect.", languageCode: languageCode)
            )
        }
    }

    func testAuthProviderFailureDoesNotReachPublishedMessage() async {
        let marker = "provider-private-marker-do-not-display"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: session,
            defaults: temporaryDefaults(named: "safe-auth-provider-error")
        )
        AuthURLProtocolStub.handler = { request in
            try AuthURLProtocolStub.response(
                for: request,
                statusCode: 400,
                json: #"{"message":"provider-private-marker-do-not-display"}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            session.invalidateAndCancel()
        }

        await auth.signIn(email: "athlete@example.com", password: "Password9")

        XCTAssertTrue(auth.messageIsError)
        XCTAssertEqual(auth.message, "Something went wrong. Try again.")
        XCTAssertFalse(auth.message?.contains(marker) == true)
    }

    func testNewPasswordPolicyMatchesSupabaseCharacterGroupsAndBounds() {
        XCTAssertTrue(GymPasswordPolicy.accepts("SecurePass9!"))
        XCTAssertTrue(GymPasswordPolicy.accepts("Aa1!" + String(repeating: "x", count: 68)))
        XCTAssertTrue(GymPasswordPolicy.accepts("Aa1!" + String(repeating: "x", count: 8) + String(repeating: "🙂", count: 15)))
        XCTAssertFalse(GymPasswordPolicy.accepts("Short1!Aa"))
        XCTAssertFalse(GymPasswordPolicy.accepts("Aa1!" + String(repeating: "x", count: 69)))
        XCTAssertFalse(GymPasswordPolicy.accepts("Aa1!" + String(repeating: "x", count: 8) + String(repeating: "🙂", count: 16)))
        XCTAssertFalse(GymPasswordPolicy.accepts("SECUREPASS9!"))
        XCTAssertFalse(GymPasswordPolicy.accepts("securepass9!"))
        XCTAssertFalse(GymPasswordPolicy.accepts("SecurePass!!"))
        XCTAssertFalse(GymPasswordPolicy.accepts("SecurePass9🙂"))

        for symbol in "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~" {
            XCTAssertTrue(GymPasswordPolicy.accepts("SecurePass9\(symbol)"), "Expected \(symbol) to be supported")
        }
    }

    func testSignInAllowsLegacyPasswordWithoutApplyingNewPasswordPolicy() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: session,
            defaults: temporaryDefaults(named: "legacy-password-sign-in")
        )
        AuthURLProtocolStub.handler = { request in
            let bodyData = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            XCTAssertEqual(body["password"] as? String, "legacy1")
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"access_token":"legacy-access","refresh_token":"legacy-refresh","expires_in":3600,"user":{"id":"00000000-0000-0000-0000-000000000001","email":"athlete@example.com","user_metadata":{"display_name":"Athlete"}}}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            session.invalidateAndCancel()
        }

        await auth.signIn(email: "athlete@example.com", password: "legacy1")

        XCTAssertEqual(auth.session?.cloud?.email, "athlete@example.com")
        XCTAssertNil(auth.message)
    }

    func testSignUpShowsPersistentEmailConfirmationStateAndResendKeepsPKCE() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: session,
            defaults: temporaryDefaults(named: "pending-email-confirmation")
        )
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/auth/v1/signup":
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"id":"00000000-0000-0000-0000-000000000001","email":"athlete@example.com"}"#
                )
            case "/auth/v1/token":
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 400,
                    json: #"{"message":"Email not confirmed"}"#
                )
            case "/auth/v1/resend":
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            default:
                XCTFail("Unexpected auth request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            session.invalidateAndCancel()
        }

        let signedIn = await auth.signUp(
            email: " Athlete@Example.com ",
            password: "SecurePass9!",
            displayName: "Athlete"
        )

        XCTAssertFalse(signedIn)
        XCTAssertNil(auth.session)
        XCTAssertEqual(auth.message, "Account created. Check your email, then return to GymApp.")
        XCTAssertFalse(auth.messageIsError)
        XCTAssertEqual(auth.pendingConfirmationEmail, "athlete@example.com")
        XCTAssertTrue(auth.pendingConfirmationEmailWasSent)

        let signupRequest = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/auth/v1/signup" })
        )
        let signupBody = try jsonObject(from: signupRequest)
        let signupChallenge = try XCTUnwrap(signupBody["code_challenge"] as? String)
        XCTAssertEqual(signupBody["code_challenge_method"] as? String, "s256")

        await auth.signIn(email: "athlete@example.com", password: "SecurePass9!")

        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/auth/v1/resend" }.count,
            0,
            "An unconfirmed sign-in must not silently consume the email-send rate limit."
        )
        XCTAssertEqual(auth.pendingConfirmationEmail, "athlete@example.com")
        XCTAssertTrue(auth.pendingConfirmationEmailWasSent)
        XCTAssertNil(auth.message)

        await auth.resendConfirmation(email: "athlete@example.com")

        let resendRequest = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/auth/v1/resend" })
        )
        let resendBody = try jsonObject(from: resendRequest)
        XCTAssertEqual(resendBody["type"] as? String, "signup")
        XCTAssertEqual(resendBody["email"] as? String, "athlete@example.com")
        XCTAssertEqual(resendBody["code_challenge"] as? String, signupChallenge)
        XCTAssertEqual(resendBody["code_challenge_method"] as? String, "s256")
        XCTAssertFalse(auth.messageIsError)

        auth.dismissEmailConfirmation(clearPendingRequest: false)
        XCTAssertNil(auth.pendingConfirmationEmail)
    }

    func testUnconfirmedSignInPersistsExplicitResendStateAndCompletesPKCE() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let keychain = InMemoryKeychainStore()
        let defaults = temporaryDefaults(named: "unconfirmed-sign-in")
        let auth = AuthService(
            keychain: keychain,
            urlSession: session,
            defaults: defaults
        )
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/auth/v1/token" where request.url?.query?.contains("grant_type=password") == true:
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 400,
                    json: #"{"message":"Email not confirmed"}"#
                )
            case "/auth/v1/resend":
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            case "/auth/v1/token" where request.url?.query?.contains("grant_type=pkce") == true:
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"access_token":"confirmed-access","refresh_token":"confirmed-refresh","expires_in":3600,"user":{"id":"00000000-0000-0000-0000-000000000001","email":"athlete@example.com","user_metadata":{"display_name":"Athlete"}}}"#
                )
            default:
                XCTFail("Unexpected auth request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            session.invalidateAndCancel()
        }

        await auth.signIn(email: "athlete@example.com", password: "Password9")

        XCTAssertNil(auth.session)
        XCTAssertNil(auth.message)
        XCTAssertFalse(auth.messageIsError)
        XCTAssertEqual(auth.pendingConfirmationEmail, "athlete@example.com")
        XCTAssertFalse(auth.pendingConfirmationEmailWasSent)
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/auth/v1/resend" }.count,
            0,
            "Sign-in must expose an explicit resend action instead of sending duplicate email."
        )

        let relaunched = AuthService(keychain: keychain, urlSession: session, defaults: defaults)
        XCTAssertEqual(relaunched.pendingConfirmationEmail, "athlete@example.com")
        XCTAssertFalse(relaunched.pendingConfirmationEmailWasSent)

        await relaunched.resendConfirmation(email: "athlete@example.com")

        let resendRequest = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/auth/v1/resend" })
        )
        let resendBody = try jsonObject(from: resendRequest)
        let challenge = try XCTUnwrap(resendBody["code_challenge"] as? String)
        XCTAssertEqual(challenge.count, 43)
        XCTAssertEqual(resendBody["code_challenge_method"] as? String, "s256")
        XCTAssertEqual(resendBody["email"] as? String, "athlete@example.com")
        XCTAssertEqual(resendBody["type"] as? String, "signup")
        XCTAssertTrue(relaunched.pendingConfirmationEmailWasSent)
        XCTAssertEqual(relaunched.message, "Confirmation email sent. Check inbox and spam.")

        let afterResendRelaunch = AuthService(
            keychain: keychain,
            urlSession: session,
            defaults: defaults
        )
        XCTAssertEqual(afterResendRelaunch.pendingConfirmationEmail, "athlete@example.com")
        XCTAssertTrue(afterResendRelaunch.pendingConfirmationEmailWasSent)

        let resendURL = try XCTUnwrap(resendRequest.url)
        let resendQuery = try XCTUnwrap(URLComponents(url: resendURL, resolvingAgainstBaseURL: false))
        let redirect = try XCTUnwrap(
            resendQuery.queryItems?.first(where: { $0.name == "redirect_to" })?.value
        )
        let redirectComponents = try XCTUnwrap(URLComponents(string: redirect))
        let state = try XCTUnwrap(
            redirectComponents.queryItems?.first(where: { $0.name == "state" })?.value
        )
        let callback = try XCTUnwrap(
            URL(string: "com.setforge.gymapp.ios://auth/callback/\(state)?code=confirmation-code")
        )

        await afterResendRelaunch.handleOpenURL(callback)

        let tokenRequest = try XCTUnwrap(recorder.requests.first(where: {
            $0.url?.path == "/auth/v1/token"
                && $0.url?.query?.contains("grant_type=pkce") == true
        }))
        let tokenBody = try jsonObject(from: tokenRequest)
        let verifier = try XCTUnwrap(tokenBody["code_verifier"] as? String)
        XCTAssertEqual(tokenBody["auth_code"] as? String, "confirmation-code")
        XCTAssertEqual(pkceChallenge(for: verifier), challenge)
        XCTAssertEqual(afterResendRelaunch.session?.cloud?.email, "athlete@example.com")
        XCTAssertNil(afterResendRelaunch.pendingConfirmationEmail)
    }

    func testLostSignupResponsePreservesPKCETransactionForExplicitResend() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let keychain = InMemoryKeychainStore()
        let defaults = temporaryDefaults(named: "signup-outcome-unknown")
        let auth = AuthService(keychain: keychain, urlSession: urlSession, defaults: defaults)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/auth/v1/signup":
                throw URLError(.networkConnectionLost)
            case "/auth/v1/resend":
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            default:
                XCTFail("Unexpected signup recovery request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let signedIn = await auth.signUp(
            email: "athlete@example.com",
            password: "SecurePass9!",
            displayName: "Athlete"
        )

        XCTAssertFalse(signedIn)
        XCTAssertEqual(auth.pendingConfirmationEmail, "athlete@example.com")
        XCTAssertFalse(auth.pendingConfirmationEmailWasSent)
        let signupRequest = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/auth/v1/signup" })
        )
        let signupChallenge = try XCTUnwrap(
            try jsonObject(from: signupRequest)["code_challenge"] as? String
        )

        let relaunched = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        XCTAssertEqual(relaunched.pendingConfirmationEmail, "athlete@example.com")
        await relaunched.resendConfirmation(email: "athlete@example.com")

        let resendRequest = try XCTUnwrap(
            recorder.requests.first(where: { $0.url?.path == "/auth/v1/resend" })
        )
        let resendBody = try jsonObject(from: resendRequest)
        XCTAssertEqual(resendBody["code_challenge"] as? String, signupChallenge)
        XCTAssertEqual(resendBody["code_challenge_method"] as? String, "s256")
        XCTAssertTrue(relaunched.pendingConfirmationEmailWasSent)
    }

    func testLostRecoveryResponseReusesSamePKCETransactionOnRetry() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "recovery-outcome-unknown")
        )
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let recoveryRequests = recorder.requests.filter { $0.url?.path == "/auth/v1/recover" }
            if recoveryRequests.count == 1 {
                throw URLError(.networkConnectionLost)
            }
            return try AuthURLProtocolStub.response(for: request, json: "{}")
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        await auth.requestPasswordReset(email: "athlete@example.com")
        XCTAssertTrue(auth.messageIsError)
        await auth.requestPasswordReset(email: "athlete@example.com")

        let requests = recorder.requests.filter { $0.url?.path == "/auth/v1/recover" }
        XCTAssertEqual(requests.count, 2)
        let first = try jsonObject(from: try XCTUnwrap(requests.first))
        let second = try jsonObject(from: try XCTUnwrap(requests.last))
        XCTAssertEqual(first["code_challenge"] as? String, second["code_challenge"] as? String)
        XCTAssertEqual(first["code_challenge_method"] as? String, "s256")
        XCTAssertFalse(auth.messageIsError)
        XCTAssertTrue(auth.message?.contains("Password reset email sent") == true)
    }

    func testCloudSyncIndicatorPublishesSafeMessageAndRethrowsOriginalError() async {
        let marker = "provider-private-marker-do-not-display"
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            defaults: temporaryDefaults(named: "safe-cloud-indicator-error")
        )
        let cloud = CloudSyncService(auth: auth)

        do {
            let _: Void = try await cloud.withSyncIndicator {
                throw CloudSyncError.requestFailed(marker)
            }
            XCTFail("The original cloud error must be rethrown.")
        } catch CloudSyncError.requestFailed(let detail) {
            XCTAssertEqual(detail, marker)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(cloud.isSyncing)
        XCTAssertEqual(cloud.lastError, "Something went wrong. Try again.")
        XCTAssertFalse(cloud.lastError?.contains(marker) == true)
    }

    func testCloudSaveForcesOneRefreshAndReusesNewBearer() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "cloud-forced-refresh")
        )
        let account = cloudSession(userID: "cloud-forced-refresh-user")
        try auth.installSessionForTesting(.cloud(account))
        let cloud = CloudSyncService(auth: auth, urlSession: urlSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let bearer = request.value(forHTTPHeaderField: "Authorization")
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                XCTAssertEqual(bearer, "Bearer \(account.accessToken)")
                return try AuthURLProtocolStub.response(for: request, json: "[]")
            case ("/rest/v1/user_states", "POST") where bearer == "Bearer \(account.accessToken)":
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 401,
                    json: #"{"message":"JWT expired"}"#
                )
            case ("/auth/v1/token", "POST"):
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"access_token":"refreshed-cloud-access","refresh_token":"refreshed-cloud-refresh","expires_in":3600,"user":{"id":"cloud-forced-refresh-user","email":"cloud-forced-refresh-user@example.com","user_metadata":{"display_name":"Cloud"}}}"#
                )
            case ("/rest/v1/user_states", "POST"):
                XCTAssertEqual(bearer, "Bearer refreshed-cloud-access")
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"2026-07-22T12:00:00.000000Z"}]"#
                )
            case ("/rest/v1/profiles", "POST"):
                XCTAssertEqual(bearer, "Bearer refreshed-cloud-access")
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            default:
                XCTFail("Unexpected cloud forced-refresh request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let initialState = try await cloud.loadRemoteState(expectedUserID: account.userID)
        XCTAssertNil(initialState)
        try await cloud.saveRemoteState(
            backupData: Data("{}".utf8),
            xp: 10,
            level: 2,
            workouts: 1,
            expectedUserID: account.userID
        )

        XCTAssertEqual(
            recorder.requests.filter {
                $0.url?.path == "/auth/v1/token"
                    && $0.url?.query?.contains("grant_type=refresh_token") == true
            }.count,
            1
        )
        XCTAssertEqual(auth.session?.cloud?.accessToken, "refreshed-cloud-access")
        XCTAssertEqual(
            recorder.requests.last?.value(forHTTPHeaderField: "Authorization"),
            "Bearer refreshed-cloud-access"
        )
    }

    func testCloudRepeatedForbiddenRefreshesOnceAndKeepsSession() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "cloud-repeated-forbidden")
        )
        let account = cloudSession(userID: "cloud-repeated-forbidden-user")
        try auth.installSessionForTesting(.cloud(account))
        let cloud = CloudSyncService(auth: auth, urlSession: urlSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            if request.url?.path == "/auth/v1/token" {
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"access_token":"forbidden-refreshed-access","refresh_token":"forbidden-refreshed-refresh","expires_in":3600,"user":{"id":"cloud-repeated-forbidden-user","email":"cloud-repeated-forbidden-user@example.com","user_metadata":{"display_name":"Cloud"}}}"#
                )
            }
            XCTAssertEqual(request.url?.path, "/rest/v1/user_states")
            return try AuthURLProtocolStub.response(
                for: request,
                statusCode: 403,
                json: #"{"message":"policy denied"}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        do {
            _ = try await cloud.loadRemoteState(expectedUserID: account.userID)
            XCTFail("A repeated 403 must surface after one refresh and one retry.")
        } catch CloudSyncError.requestFailed(let message) {
            XCTAssertEqual(message, "policy denied")
        } catch {
            XCTFail("Unexpected repeated-forbidden error: \(error)")
        }

        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/rest/v1/user_states" }.count,
            2
        )
        XCTAssertEqual(
            recorder.requests.filter { $0.url?.path == "/auth/v1/token" }.count,
            1
        )
        XCTAssertEqual(auth.session?.cloud?.accessToken, "forbidden-refreshed-access")
    }

    func testCatalogSeedMarkerPreservesDeletedBuiltInExercise() throws {
        let directory = try temporaryDirectory(named: "catalog-seed-once")
        let store = try WorkoutStore(
            accountStorageKey: "catalog-seed-once",
            directoryURL: directory
        )

        XCTAssertEqual(try store.seedBuiltInExercises(), 53)
        XCTAssertEqual(store.catalogSeedVersion, BuiltInExerciseCatalog.seedVersion)
        let bench = try XCTUnwrap(store.exercises.first { $0.catalogKey == "bench_press" })
        try store.deleteExercise(id: bench.id)

        XCTAssertEqual(try store.seedBuiltInExercises(), 0)
        XCTAssertFalse(store.exercises.contains { $0.catalogKey == "bench_press" })

        let reopened = try WorkoutStore(
            accountStorageKey: "catalog-seed-once",
            directoryURL: directory
        )
        XCTAssertEqual(reopened.catalogSeedVersion, BuiltInExerciseCatalog.seedVersion)
        XCTAssertEqual(try reopened.seedBuiltInExercises(), 0)
        XCTAssertFalse(reopened.exercises.contains { $0.catalogKey == "bench_press" })
        XCTAssertEqual(try reopened.makeBackup().catalogSeedVersion, BuiltInExerciseCatalog.seedVersion)
    }

    func testAssistedDipLegacyAliasMigratesInPlaceWithoutMergingStandardDips() throws {
        let store = try WorkoutStore(
            accountStorageKey: "assisted-dip-alias",
            directoryURL: try temporaryDirectory(named: "assisted-dip-alias")
        )
        let legacy = try store.addExercise(name: "підтягування с брусьями")
        _ = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_780_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: legacy.id,
                    sets: [.init(weight: 45, reps: 8)]
                )
            ]
        )

        XCTAssertEqual(try store.seedBuiltInExercises(), 52)

        let migrated = try XCTUnwrap(store.exercises.first { $0.catalogKey == "assisted_dip" })
        XCTAssertEqual(migrated.id, legacy.id)
        XCTAssertEqual(migrated.name, "підтягування с брусьями")
        XCTAssertEqual(store.workouts.first?.exercises.first?.exerciseID, legacy.id)
        XCTAssertEqual(store.exercises.filter { $0.catalogKey == "assisted_dip" }.count, 1)
        XCTAssertEqual(store.exercises.filter { $0.catalogKey == "dips" }.count, 1)
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

    func testImportKeepsUnknownNonblankNameCustomDespiteHostileCatalogKey() throws {
        XCTAssertNil(
            BuiltInExerciseCatalog.resolvedKey(
                catalogKey: "bench_press",
                name: "Imported custom label"
            )
        )
        XCTAssertEqual(
            BuiltInExerciseCatalog.resolvedKey(catalogKey: "bench_press", name: "   "),
            "bench_press"
        )

        let target = try WorkoutStore(
            accountStorageKey: "catalog-custom-hostile-key-target",
            directoryURL: try temporaryDirectory(named: "catalog-custom-hostile-key-target")
        )
        let bench = try target.addExercise(name: "Bench Press")
        let owner = BackupOwner(accountID: "catalog-custom-hostile-key-target", remote: false)
        let hostileBackup: [String: Any] = [
            "schemaVersion": GymBackup.currentSchemaVersion,
            "exportedAt": 1_750_000_000_000 as Int64,
            "app": "GymApp",
            "diagnostics": false,
            "owner": [
                "accountId": "catalog-custom-hostile-key-target",
                "remote": false
            ],
            "exercises": [],
            "sessions": [[
                "date": 1_750_000_000_000 as Int64,
                "exercises": [[
                    "name": "Imported custom label",
                    "catalogKey": "bench_press",
                    "sets": [["weight": 42.5, "reps": 9]]
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: hostileBackup, options: [.sortedKeys])

        let result = try target.importBackup(data: data, activeOwner: owner)

        XCTAssertEqual(result.addedExercises, 1)
        XCTAssertEqual(result.importedSessions, 1)
        let custom = try XCTUnwrap(target.exercises.first { $0.name == "Imported custom label" })
        XCTAssertNil(custom.catalogKey)
        XCTAssertNotEqual(custom.id, bench.id)
        let importedExercise = try XCTUnwrap(target.workouts.first?.exercises.first)
        XCTAssertEqual(importedExercise.exerciseID, custom.id)
        XCTAssertEqual(importedExercise.sets.count, 1)
        XCTAssertEqual(importedExercise.sets.first?.weight, 42.5)
        XCTAssertEqual(importedExercise.sets.first?.reps, 9)
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
        let exercise = try store.addExercise(name: "Custom Deadlift Variation")
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

    func testHipAbductionMapsToGlutesWithoutShoulders() {
        for name in ["Hip Abduction", "Розведення ніг", "Разведение ног в тренажере"] {
            let muscleIDs = Set(MuscleMappingEngine.defaultContributions(for: name).map(\.muscleID))
            XCTAssertTrue(muscleIDs.contains("glutes"), "\(name) should map to glutes")
            XCTAssertFalse(muscleIDs.contains("shoulders"), "\(name) should not map to shoulders")
        }
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

    func testNewExerciseRecommendationUsesCutDeficitBudget() {
        let exercise = Exercise(name: "Cable Fly")
        let recommendation = RecommendationEngine.buildForExercise(exerciseID: exercise.id, history: [])
        XCTAssertEqual(recommendation.kind, .newExercise)
        XCTAssertEqual(recommendation.sets.count, 3)
        XCTAssertEqual(recommendation.sets.map(\.reps), [10, 10, 10])
        XCTAssertTrue(recommendation.sets.allSatisfy { $0.weight == nil })
    }

    func testStrengthFiveRepSetsHoldInsteadOfAutoDeloading() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let history = coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-86_400),
            weights: [100, 100, 100, 100, 100],
            reps: [5, 5, 5, 5, 5]
        )
        let profile = TrainingProfile(
            split: .upperLower,
            workoutsPerWeek: 4,
            goal: .strength,
            calorieMode: .maintenance
        )

        let recommendation = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history,
            trainingProfile: profile,
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(recommendation.kind, .holdAndBuild)
        XCTAssertEqual(recommendation.sets.compactMap(\.weight), [100, 100, 100, 100])
        XCTAssertEqual(recommendation.sets.map(\.reps), [6, 6, 6, 6])
    }

    func testCutDeficitCanEarnPerSetDoubleProgressionAtReducedVolume() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let history = coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-3 * 86_400),
            weights: [20, 40, 60],
            reps: [10, 10, 10]
        ) + coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-86_400),
            weights: [20, 40, 60],
            reps: [10, 10, 10]
        )
        let profile = TrainingProfile(
            split: .upperLower,
            workoutsPerWeek: 4,
            goal: .aestheticFatLoss,
            calorieMode: .deficit
        )

        let recommendation = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history,
            trainingProfile: profile,
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(recommendation.kind, .progressiveOverload)
        XCTAssertEqual(recommendation.sets.count, 3)
        XCTAssertEqual(recommendation.sets.compactMap(\.weight), [22.5, 42.5, 62.5])
        XCTAssertEqual(recommendation.sets.map(\.reps), [6, 6, 6])
    }

    func testMuscleGainDoubleProgressionHoldsAtMinimumAndLoadsAtMaximum() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let profile = TrainingProfile(
            workoutsPerWeek: 4,
            goal: .muscleGain,
            calorieMode: .maintenance
        )
        func recommendation(reps: Int) -> WorkoutRecommendation {
            RecommendationEngine.buildForExercise(
                exerciseID: exercise.id,
                history: coachSession(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    date: now.addingTimeInterval(-86_400),
                    weights: [50, 50, 50],
                    reps: [reps, reps, reps]
                ),
                trainingProfile: profile,
                now: now,
                calendar: utcCalendar()
            )
        }

        let minimum = recommendation(reps: 8)
        XCTAssertEqual(minimum.kind, .holdAndBuild)
        XCTAssertEqual(minimum.sets.compactMap(\.weight), [50, 50, 50, 50])
        XCTAssertEqual(minimum.sets.map(\.reps), [9, 9, 9, 9])

        let maximumHistory = coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-3 * 86_400),
            weights: [50, 50, 50, 50],
            reps: [10, 10, 10, 10]
        ) + coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-86_400),
            weights: [50, 50, 50, 50],
            reps: [10, 10, 10, 10]
        )
        let maximum = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: maximumHistory,
            trainingProfile: profile,
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(maximum.kind, .progressiveOverload)
        XCTAssertEqual(maximum.sets.compactMap(\.weight), [52.5, 52.5, 52.5, 52.5])
        XCTAssertEqual(maximum.sets.map(\.reps), [6, 6, 6, 6])
    }

    func testCoachSetBudgetRespondsToGoalCaloriesAndWeeklyFrequency() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let history = coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-86_400),
            weights: [20, 20, 20],
            reps: [9, 9, 9]
        )
        func recommendation(_ profile: TrainingProfile) -> WorkoutRecommendation {
            RecommendationEngine.buildForExercise(
                exerciseID: exercise.id,
                history: history,
                trainingProfile: profile,
                now: now,
                calendar: utcCalendar()
            )
        }

        let muscleSurplus = recommendation(TrainingProfile(
            workoutsPerWeek: 4,
            goal: .muscleGain,
            calorieMode: .surplus
        ))
        let balancedTwoDays = recommendation(TrainingProfile(
            workoutsPerWeek: 2,
            goal: .balanced,
            calorieMode: .maintenance
        ))
        let balancedSixDays = recommendation(TrainingProfile(
            workoutsPerWeek: 6,
            goal: .balanced,
            calorieMode: .maintenance
        ))

        XCTAssertEqual(muscleSurplus.sets.count, 4)
        XCTAssertEqual(balancedTwoDays.sets.count, 4)
        XCTAssertEqual(balancedSixDays.sets.count, 3)
    }

    func testBuiltInProgrammingMetadataCoversEveryCanonicalExercise() throws {
        let metadata = RecommendationEngine.builtInProgramming
        XCTAssertEqual(metadata.count, 53)
        XCTAssertEqual(Set(metadata.keys), Set(BuiltInExerciseCatalog.definitions.map(\.key)))
        XCTAssertEqual(Set(metadata.filter { $0.value.role == .primary }.map { $0.key }), [
            "bench_press", "barbell_row", "squat", "romanian_deadlift", "deadlift", "shoulder_press"
        ])
        XCTAssertEqual(metadata.values.filter { $0.role == .secondary }.count, 16)
        XCTAssertEqual(metadata.values.filter { $0.role == .isolation }.count, 24)
        XCTAssertEqual(metadata.values.filter { $0.role == .core }.count, 6)
        XCTAssertEqual(metadata.values.filter { $0.role == .warmup }.count, 1)
        XCTAssertEqual(metadata.values.filter { $0.loadMode == .bodyweight }.count, 6)
        XCTAssertEqual(metadata.values.filter { $0.loadMode == .assistance }.count, 2)
        XCTAssertEqual(metadata.values.filter { $0.loadMode == .none }.count, 1)
        XCTAssertEqual(metadata.values.filter { $0.category == .push }.count, 15)
        XCTAssertEqual(metadata.values.filter { $0.category == .pull }.count, 17)
        XCTAssertEqual(metadata.values.filter { $0.category == .legs }.count, 14)
        XCTAssertEqual(metadata.values.filter { $0.category == .fullBody }.count, 7)

        XCTAssertEqual(try XCTUnwrap(metadata["incline_dumbbell_press"]).patterns, [.horizontalPress])
        XCTAssertEqual(try XCTUnwrap(metadata["push_up"]).patterns, [.horizontalPress])
        XCTAssertEqual(try XCTUnwrap(metadata["face_pull"]).category, .pull)
        XCTAssertEqual(try XCTUnwrap(metadata["lateral_raise"]).patterns, [.accessory])
        XCTAssertEqual(try XCTUnwrap(metadata["machine_lateral_raise"]).role, .isolation)
        XCTAssertEqual(try XCTUnwrap(metadata["rear_delt_fly"]).category, .pull)
        XCTAssertEqual(try XCTUnwrap(metadata["french_press"]).patterns, [.accessory])
        XCTAssertEqual(try XCTUnwrap(metadata["hyperextension"]).role, .isolation)
        XCTAssertEqual(try XCTUnwrap(metadata["side_hyperextension"]).category, .fullBody)
    }

    func testPrimarySecondaryAndIsolationRolesDriveSetsAndRepRanges() {
        let profile = TrainingProfile(
            split: .fullBody,
            workoutsPerWeek: 3,
            goal: .balanced,
            calorieMode: .maintenance
        )
        func recommendation(_ name: String) -> WorkoutRecommendation {
            let exercise = Exercise(name: name)
            return RecommendationEngine.buildForExercise(
                exerciseID: exercise.id,
                history: [],
                exerciseCatalogKey: exercise.catalogKey,
                exerciseName: exercise.name,
                trainingProfile: profile
            )
        }

        XCTAssertEqual(recommendation("Bench Press").sets.map(\.reps), [8, 8, 8, 8])
        XCTAssertEqual(recommendation("Incline Dumbbell Press").sets.map(\.reps), [8, 8, 8])
        XCTAssertEqual(recommendation("Lateral Raise").sets.map(\.reps), [10, 10, 10])
        XCTAssertEqual(recommendation("French Press").sets.map(\.reps), [10, 10, 10])
        XCTAssertEqual(recommendation("Hyperextension").sets.map(\.reps), [10, 10, 10])
    }

    func testBodyweightUsesRepRegressionWithoutFakeLoadProgression() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Pull Up")
        let profile = TrainingProfile(
            split: .fullBody,
            workoutsPerWeek: 3,
            goal: .balanced,
            calorieMode: .maintenance
        )
        let ceilingHistory = coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-3 * 86_400),
            weights: [0, 0, 0],
            reps: [8, 8, 8]
        ) + coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-86_400),
            weights: [0, 0, 0],
            reps: [8, 8, 8]
        )
        let ceiling = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: ceilingHistory,
            exerciseCatalogKey: exercise.catalogKey,
            exerciseName: exercise.name,
            trainingProfile: profile,
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(ceiling.kind, .holdAndBuild)
        XCTAssertEqual(ceiling.sets.compactMap(\.weight), [0, 0, 0])
        XCTAssertEqual(ceiling.sets.map(\.reps), [8, 8, 8])

        let regressionHistory = [
            (days: 5, reps: 10),
            (days: 3, reps: 8),
            (days: 1, reps: 6)
        ].flatMap { item in
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-Double(item.days) * 86_400),
                weights: [0, 0, 0],
                reps: [item.reps, item.reps, item.reps]
            )
        }
        let regression = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: regressionHistory,
            exerciseCatalogKey: exercise.catalogKey,
            exerciseName: exercise.name,
            trainingProfile: profile,
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(regression.kind, .deload)
        XCTAssertEqual(regression.sets.compactMap(\.weight), [0, 0, 0])
    }

    func testAssistanceProgressionAndComebackMoveDifficultyInTheRightDirection() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Assisted Pull Up")
        let profile = TrainingProfile(
            split: .fullBody,
            workoutsPerWeek: 3,
            goal: .balanced,
            calorieMode: .maintenance
        )
        let progressionHistory = coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-3 * 86_400),
            weights: [50, 50, 50],
            reps: [8, 8, 8]
        ) + coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-86_400),
            weights: [45, 45, 45],
            reps: [8, 8, 8]
        )
        let progression = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: progressionHistory,
            exerciseCatalogKey: exercise.catalogKey,
            exerciseName: exercise.name,
            trainingProfile: profile,
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(progression.kind, .progressiveOverload)
        XCTAssertEqual(progression.sets.compactMap(\.weight), [42.5, 42.5, 42.5])

        let comeback = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-30 * 86_400),
                weights: [45, 45, 45],
                reps: [6, 6, 6]
            ),
            exerciseCatalogKey: exercise.catalogKey,
            exerciseName: exercise.name,
            trainingProfile: profile,
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(comeback.kind, .comeback)
        XCTAssertEqual(comeback.sets.compactMap(\.weight), [47.5, 47.5, 47.5])
    }

    func testExactMachineWeightsSnapDirectionallyAndHoldAtStackBoundaries() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let standard = Exercise(name: "Lat Pulldown")
        let standardProfile = try MachineLoadProfile(
            direction: .higherIsHarder,
            allowedWeightsKg: [45, 50, 55]
        )
        let standardHistory = coachSession(
            exerciseID: standard.id,
            exerciseName: standard.name,
            date: now.addingTimeInterval(-3 * 86_400),
            weights: [50, 50, 50],
            reps: [10, 10, 10]
        ) + coachSession(
            exerciseID: standard.id,
            exerciseName: standard.name,
            date: now.addingTimeInterval(-86_400),
            weights: [51, 51, 51],
            reps: [10, 10, 10]
        )
        let standardProgression = RecommendationEngine.buildForExercise(
            exerciseID: standard.id,
            history: standardHistory,
            exerciseCatalogKey: standard.catalogKey,
            exerciseName: standard.name,
            machineLoadProfile: standardProfile,
            trainingProfile: TrainingProfile(goal: .muscleGain, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(standardProgression.kind, .progressiveOverload)
        XCTAssertEqual(standardProgression.sets.compactMap(\.weight), [55, 55, 55])

        let boundaryHistory = coachSession(
            exerciseID: standard.id,
            exerciseName: standard.name,
            date: now.addingTimeInterval(-3 * 86_400),
            weights: [55, 55, 55],
            reps: [10, 10, 10]
        ) + coachSession(
            exerciseID: standard.id,
            exerciseName: standard.name,
            date: now.addingTimeInterval(-86_400),
            weights: [55, 55, 55],
            reps: [10, 10, 10]
        )
        let boundary = RecommendationEngine.buildForExercise(
            exerciseID: standard.id,
            history: boundaryHistory,
            exerciseCatalogKey: standard.catalogKey,
            exerciseName: standard.name,
            machineLoadProfile: standardProfile,
            trainingProfile: TrainingProfile(goal: .muscleGain, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(boundary.kind, .holdAndBuild)
        XCTAssertEqual(boundary.sets.compactMap(\.weight), [55, 55, 55])

        let assisted = Exercise(name: "Assisted Dip")
        let assistanceProfile = try MachineLoadProfile(
            direction: .lowerIsHarder,
            allowedWeightsKg: [40, 45, 50]
        )
        let assistanceHistory = coachSession(
            exerciseID: assisted.id,
            exerciseName: assisted.name,
            exerciseCatalogKey: assisted.catalogKey,
            date: now.addingTimeInterval(-3 * 86_400),
            weights: [50, 50, 50],
            reps: [10, 10, 10]
        ) + coachSession(
            exerciseID: assisted.id,
            exerciseName: assisted.name,
            exerciseCatalogKey: assisted.catalogKey,
            date: now.addingTimeInterval(-86_400),
            weights: [45, 45, 45],
            reps: [10, 10, 10]
        )
        let assistanceProgression = RecommendationEngine.buildForExercise(
            exerciseID: assisted.id,
            history: assistanceHistory,
            exerciseCatalogKey: assisted.catalogKey,
            exerciseName: assisted.name,
            machineLoadProfile: assistanceProfile,
            trainingProfile: TrainingProfile(goal: .muscleGain, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(assistanceProgression.kind, .progressiveOverload)
        XCTAssertEqual(assistanceProgression.sets.compactMap(\.weight), [40, 40, 40])

        let comeback = RecommendationEngine.buildForExercise(
            exerciseID: assisted.id,
            history: coachSession(
                exerciseID: assisted.id,
                exerciseName: assisted.name,
                exerciseCatalogKey: assisted.catalogKey,
                date: now.addingTimeInterval(-30 * 86_400),
                weights: [40, 40, 40],
                reps: [6, 6, 6]
            ),
            exerciseCatalogKey: assisted.catalogKey,
            exerciseName: assisted.name,
            machineLoadProfile: assistanceProfile,
            trainingProfile: TrainingProfile(goal: .balanced, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(comeback.sets.compactMap(\.weight), [45, 45, 45])
    }

    func testFallbackProgressionSnapsOffGridHistoryToTwoPointFiveKilograms() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Lat Pulldown")
        let history = coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-3 * 86_400),
            weights: [48.5, 48.5, 48.5],
            reps: [10, 10, 10]
        ) + coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-86_400),
            weights: [48.5, 48.5, 48.5],
            reps: [10, 10, 10]
        )

        let recommendation = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history,
            exerciseCatalogKey: exercise.catalogKey,
            exerciseName: exercise.name,
            trainingProfile: TrainingProfile(
                workoutsPerWeek: 4,
                goal: .aestheticFatLoss,
                calorieMode: .deficit
            ),
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(recommendation.kind, .progressiveOverload)
        XCTAssertEqual(recommendation.sets.compactMap(\.weight), [50, 50, 50])
    }

    func testAssistanceRegressionUsesDirectionSpecificRecoveryWithoutVolumeSignals() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Assisted Dip")
        let profile = try MachineLoadProfile(
            direction: .lowerIsHarder,
            allowedWeightsKg: [40, 45, 50, 55, 60, 70]
        )
        func history(_ weights: [Double]) -> [ExerciseHistoryEntry] {
            weights.enumerated().flatMap { index, weight in
                coachSession(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCatalogKey: exercise.catalogKey,
                    date: now.addingTimeInterval(-Double(5 - index * 2) * 86_400),
                    weights: [weight, weight, weight],
                    reps: [8, 8, 8]
                )
            }
        }

        let regression = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history([40, 45, 50]),
            exerciseCatalogKey: exercise.catalogKey,
            exerciseName: exercise.name,
            machineLoadProfile: profile,
            trainingProfile: TrainingProfile(goal: .balanced, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(regression.kind, .deload)
        XCTAssertEqual(regression.sets.compactMap(\.weight), [55, 55, 55])
        XCTAssertFalse(regression.reasons.contains(.volumeDropped))
        XCTAssertFalse(regression.reasons.contains(.nearPersonalBest))

        let improvement = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history([70, 60, 50]),
            exerciseCatalogKey: exercise.catalogKey,
            exerciseName: exercise.name,
            machineLoadProfile: profile,
            trainingProfile: TrainingProfile(goal: .balanced, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertNotEqual(improvement.kind, .deload)
        XCTAssertEqual(improvement.kind, .progressiveOverload)
        XCTAssertEqual(improvement.sets.compactMap(\.weight), [45, 45, 45])
    }

    func testProgressionRequiresTwoCompleteTargetSetSessionsWithoutLoadDrop() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let profile = TrainingProfile(
            split: .upperLower,
            workoutsPerWeek: 4,
            goal: .balanced,
            calorieMode: .maintenance
        )
        func recommendation(weights: [[Double]]) -> WorkoutRecommendation {
            let history = weights.enumerated().flatMap { index, sessionWeights in
                coachSession(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    date: now.addingTimeInterval(-Double(3 - index * 2) * 86_400),
                    weights: sessionWeights,
                    reps: Array(repeating: 8, count: sessionWeights.count)
                )
            }
            return RecommendationEngine.buildForExercise(
                exerciseID: exercise.id,
                history: history,
                exerciseCatalogKey: exercise.catalogKey,
                exerciseName: exercise.name,
                trainingProfile: profile,
                now: now,
                calendar: utcCalendar()
            )
        }

        XCTAssertEqual(recommendation(weights: [[60, 60, 60], [60, 60, 60]]).kind, .holdAndBuild)
        XCTAssertEqual(recommendation(weights: [[60, 60, 60, 60], [50, 50, 50, 50]]).kind, .holdAndBuild)
        XCTAssertEqual(recommendation(weights: [[60, 60, 60, 60], [60, 60, 60, 60]]).kind, .progressiveOverload)
    }

    func testFullBodyExerciseBudgetRespondsToWeeklyFrequency() {
        let exercises = [
            Exercise(name: "Bench Press"),
            Exercise(name: "Shoulder Press"),
            Exercise(name: "Barbell Row"),
            Exercise(name: "Pull Up"),
            Exercise(name: "Squat"),
            Exercise(name: "Romanian Deadlift"),
            Exercise(name: "Leg Press"),
            Exercise(name: "Lateral Raise"),
            Exercise(name: "Biceps Curl"),
            Exercise(name: "Plank"),
            Exercise(name: "Hyperextension")
        ]
        let twoDays = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: [],
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 2,
                goal: .balanced,
                calorieMode: .maintenance
            )
        )
        let sixDays = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: [],
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 6,
                goal: .balanced,
                calorieMode: .maintenance
            )
        )

        XCTAssertEqual(twoDays.exercises.count, 10)
        XCTAssertEqual(sixDays.exercises.count, 6)
        func exerciseCount(
            days: Int,
            goal: TrainingGoal = .balanced,
            calories: CalorieMode = .maintenance
        ) -> Int {
            RecommendationEngine.buildWorkoutPlan(
                exercises: exercises,
                history: [],
                trainingProfile: TrainingProfile(
                    split: .fullBody,
                    workoutsPerWeek: days,
                    goal: goal,
                    calorieMode: calories
                )
            ).exercises.count
        }
        XCTAssertEqual(exerciseCount(days: 3), 9)
        XCTAssertEqual(exerciseCount(days: 4), 8)
        XCTAssertEqual(exerciseCount(days: 5), 7)
        XCTAssertEqual(exerciseCount(days: 3, goal: .strength), 9)
        XCTAssertEqual(exerciseCount(days: 3, calories: .deficit), 9)
        XCTAssertEqual(exerciseCount(days: 3, goal: .strength, calories: .deficit), 9)

        let duplicateID = UUID()
        let duplicatePlan = RecommendationEngine.buildWorkoutPlan(
            exercises: [
                Exercise(id: duplicateID, name: "Unmapped first entry"),
                Exercise(id: duplicateID, name: "Bench Press")
            ],
            history: [],
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 3,
                goal: .balanced,
                calorieMode: .maintenance
            )
        )
        XCTAssertEqual(duplicatePlan.exercises.map { $0.exercise.name }, ["Unmapped first entry"])

        let repeatedID = UUID()
        var oversizedCatalog = (0 ..< 2_000).map { index in
            Exercise(id: repeatedID, name: "Unmapped catalog entry \(index)")
        }
        oversizedCatalog.append(Exercise(name: "Bench Press"))
        let cappedPlan = RecommendationEngine.buildWorkoutPlan(
            exercises: oversizedCatalog,
            history: [],
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 3,
                goal: .balanced,
                calorieMode: .maintenance
            )
        )
        XCTAssertEqual(cappedPlan.exercises.map { $0.exercise.name }, ["Unmapped catalog entry 0"])
    }

    func testWeeklyEffectiveSetsUseExactRollingWindowAndBoundedManualFractions() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exerciseID = UUID()
        let datedSets: [(TimeInterval, Int)] = [
            (-7 * 24 * 60 * 60.0, 0),
            (-3 * 24 * 60 * 60.0, 1),
            (0.0, 2),
            (-7 * 24 * 60 * 60.0 - 0.001, 3),
            (0.001, 4)
        ]
        var history: [ExerciseHistoryEntry] = []
        for (offset, index) in datedSets {
            let source = coachSession(
                exerciseID: exerciseID,
                exerciseName: "My cable move",
                workoutID: UUID(),
                date: now.addingTimeInterval(offset),
                weights: [20],
                reps: [8]
            )[0]
            history.append(ExerciseHistoryEntry(
                setID: source.setID,
                workoutID: source.workoutID,
                sessionDate: source.sessionDate,
                exerciseID: source.exerciseID,
                exerciseName: source.exerciseName,
                weight: source.weight,
                reps: source.reps,
                setOrderIndex: index
            ))
        }
        let mappings = [
            ExerciseMuscleMapping(
                exerciseNameKey: MuscleMappingEngine.normalizeExerciseName("My cable move"),
                exerciseName: "My cable move",
                muscleID: "biceps",
                weight: 0.4
            ),
            ExerciseMuscleMapping(
                exerciseNameKey: MuscleMappingEngine.normalizeExerciseName("My cable move"),
                exerciseName: "My cable move",
                muscleID: "not-a-muscle",
                weight: 1
            ),
            ExerciseMuscleMapping(
                exerciseNameKey: MuscleMappingEngine.normalizeExerciseName("My cable move"),
                exerciseName: "My cable move",
                muscleID: "chest",
                weight: .nan
            )
        ]

        let sets = RecommendationEngine.weeklyEffectiveSets(
            history: history,
            muscleMappings: mappings,
            now: now
        )

        XCTAssertEqual(try XCTUnwrap(sets["biceps"]), 1.2, accuracy: 0.000_001)
        XCTAssertNil(sets["not-a-muscle"])
        XCTAssertNil(sets["chest"])
    }

    func testWeeklyTargetsFollowGoalAndCalorieRecoveryBudget() {
        XCTAssertEqual(RecommendationEngine.weeklyTargetSets(profile: .init(
            goal: .muscleGain,
            calorieMode: .surplus
        )), 11)
        XCTAssertEqual(RecommendationEngine.weeklyTargetSets(profile: .init(
            goal: .muscleGain,
            calorieMode: .deficit
        )), 8)
        XCTAssertEqual(RecommendationEngine.weeklyTargetSets(profile: .init(
            goal: .strength,
            calorieMode: .maintenance
        )), 8)
        XCTAssertEqual(RecommendationEngine.weeklyTargetSets(profile: .init(
            goal: .aestheticFatLoss,
            calorieMode: .deficit
        )), 6)
    }

    func testWeeklyCoverageRewardsNeglectedMusclesAndPenalizesSaturatedOnes() {
        let contributions = [
            MuscleContribution(muscleID: "chest", weight: 1),
            MuscleContribution(muscleID: "triceps", weight: 0.5)
        ]
        let neglected = RecommendationEngine.weeklyCoverageScore(
            contributions: contributions,
            plannedSetCount: 3,
            projectedSets: [:],
            targetSets: 8
        )
        let almostCovered = RecommendationEngine.weeklyCoverageScore(
            contributions: contributions,
            plannedSetCount: 3,
            projectedSets: ["chest": 7, "triceps": 7],
            targetSets: 8
        )
        let saturated = RecommendationEngine.weeklyCoverageScore(
            contributions: contributions,
            plannedSetCount: 3,
            projectedSets: ["chest": 8, "triceps": 8],
            targetSets: 8
        )

        XCTAssertEqual(neglected, 81, accuracy: 0.000_001)
        XCTAssertEqual(almostCovered, 36, accuracy: 0.000_001)
        XCTAssertEqual(saturated, -18, accuracy: 0.000_001)
    }

    func testEveryBuiltInExerciseHasTwoBundledPreviewFrames() {
        for definition in BuiltInExerciseCatalog.definitions {
            XCTAssertEqual(
                ExerciseMediaStore.bundledImages(exerciseName: definition.englishName).count,
                2,
                "Missing preview frames for \(definition.key)"
            )
        }
    }

    func testCustomExerciseMediaRemainsAccountScoped() throws {
        let exerciseID = UUID()
        let ownerA = "media-owner-a-\(UUID().uuidString)"
        let ownerB = "media-owner-b-\(UUID().uuidString)"
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.systemBlue.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        defer { ExerciseMediaStore.deleteCustomImage(ownerKey: ownerA, exerciseID: exerciseID) }

        try ExerciseMediaStore.saveCustomImage(data, ownerKey: ownerA, exerciseID: exerciseID)

        XCTAssertNotNil(ExerciseMediaStore.customImage(ownerKey: ownerA, exerciseID: exerciseID))
        XCTAssertNil(ExerciseMediaStore.customImage(ownerKey: ownerB, exerciseID: exerciseID))
    }

    func testSmartPlanRotatesOneTrunkSlotInEveryWorkout() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercises = [
            Exercise(name: "Bench Press"),
            Exercise(name: "Shoulder Press"),
            Exercise(name: "Barbell Row"),
            Exercise(name: "Pull Up"),
            Exercise(name: "Squat"),
            Exercise(name: "Romanian Deadlift"),
            Exercise(name: "Leg Press"),
            Exercise(name: "Plank"),
            Exercise(name: "Hyperextension"),
            Exercise(name: "Dumbbell Bench Press"),
            Exercise(name: "Lat Pulldown"),
            Exercise(name: "Biceps Curl")
        ]
        let trunkKeys: Set<String> = ["plank", "hyperextension", "side_hyperextension"]
        func selectedTrunkKeys(_ plan: SmartWorkoutPlan) -> Set<String> {
            Set(plan.exercises.compactMap(\.exercise.catalogKey)).intersection(trunkKeys)
        }

        let fullBodyA = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: [],
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 3,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(fullBodyA.variant, .a)
        XCTAssertEqual(selectedTrunkKeys(fullBodyA), ["plank"])

        let bench = try! XCTUnwrap(exercises.first { $0.catalogKey == "bench_press" })
        let oneCompletedSession = coachSession(
            exerciseID: bench.id,
            exerciseName: bench.name,
            exerciseCatalogKey: bench.catalogKey,
            date: now.addingTimeInterval(-86_400),
            weights: [50, 50, 50],
            reps: [8, 8, 8]
        )
        let fullBodyB = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: oneCompletedSession,
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 3,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(fullBodyB.variant, .b)
        XCTAssertEqual(selectedTrunkKeys(fullBodyB), ["hyperextension"])

        let upperWithoutRecentTrunk = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: [],
            trainingProfile: TrainingProfile(
                split: .upperLower,
                workoutsPerWeek: 4,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(upperWithoutRecentTrunk.exercises.count, 8)
        XCTAssertEqual(selectedTrunkKeys(upperWithoutRecentTrunk).count, 1)

        let plank = try! XCTUnwrap(exercises.first { $0.catalogKey == "plank" })
        let recentTrunkHistory = coachSession(
            exerciseID: plank.id,
            exerciseName: plank.name,
            exerciseCatalogKey: plank.catalogKey,
            date: now.addingTimeInterval(-86_400),
            weights: [0, 0, 0],
            reps: [10, 10, 10]
        )
        let upperWithRecentTrunk = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: recentTrunkHistory,
            trainingProfile: TrainingProfile(
                split: .upperLower,
                workoutsPerWeek: 4,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(upperWithRecentTrunk.exercises.count, 8)
        XCTAssertEqual(selectedTrunkKeys(upperWithRecentTrunk), ["hyperextension"])

        let hyperextension = try! XCTUnwrap(exercises.first { $0.catalogKey == "hyperextension" })
        let recentHyperHistory = coachSession(
            exerciseID: hyperextension.id,
            exerciseName: hyperextension.name,
            exerciseCatalogKey: hyperextension.catalogKey,
            date: now.addingTimeInterval(-86_400),
            weights: [20, 20, 20],
            reps: [10, 10, 10]
        )
        let upperWithRecentHyper = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: recentHyperHistory,
            trainingProfile: TrainingProfile(
                split: .upperLower,
                workoutsPerWeek: 4,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(upperWithRecentHyper.exercises.count, 8)
        XCTAssertEqual(selectedTrunkKeys(upperWithRecentHyper), ["plank"])
    }

    func testTwoDayProfileForcesFullBodyAndBalancedPlansPreferCompounds() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercises = [
            Exercise(name: "Machine Chest Fly"),
            Exercise(name: "Bench Press"),
            Exercise(name: "Face Pull"),
            Exercise(name: "Barbell Row"),
            Exercise(name: "Leg Extension"),
            Exercise(name: "Squat"),
            Exercise(name: "Plank")
        ]
        let lowerHistory = coachSession(
            exerciseID: UUID(),
            exerciseName: "Squat",
            date: now.addingTimeInterval(-86_400),
            weights: [80, 80, 80],
            reps: [8, 8, 8]
        )
        let twoDay = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: lowerHistory,
            trainingProfile: TrainingProfile(
                split: .upperLower,
                workoutsPerWeek: 2,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(twoDay.focus, .fullBody)
        let selectedKeys = Set(twoDay.exercises.compactMap { $0.exercise.catalogKey })
        XCTAssertTrue(selectedKeys.contains("bench_press"))
        XCTAssertTrue(selectedKeys.contains("barbell_row"))
        XCTAssertTrue(selectedKeys.contains("squat"))
    }

    func testUpperPlanAlwaysContainsAPressAndAPullPattern() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercises = [
            Exercise(name: "Machine Chest Fly"),
            Exercise(name: "Lateral Raise"),
            Exercise(name: "Bench Press"),
            Exercise(name: "Face Pull"),
            Exercise(name: "Biceps Curl"),
            Exercise(name: "Barbell Row")
        ]
        let plan = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: coachSession(
                exerciseID: UUID(),
                exerciseName: "Squat",
                date: now.addingTimeInterval(-86_400),
                weights: [80, 80, 80],
                reps: [8, 8, 8]
            ),
            trainingProfile: TrainingProfile(
                split: .upperLower,
                workoutsPerWeek: 4,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )
        let selectedKeys = Set(plan.exercises.compactMap { $0.exercise.catalogKey })
        XCTAssertEqual(plan.focus, .upper)
        XCTAssertTrue(selectedKeys.contains("bench_press"))
        XCTAssertTrue(selectedKeys.contains("barbell_row"))
    }

    func testCoachDeloadRequiresTwoComparableRegressions() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let profile = TrainingProfile(goal: .balanced, calorieMode: .maintenance)
        let history = [
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-86_400),
                weights: [100, 100, 100],
                reps: [6, 6, 6]
            ),
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-3 * 86_400),
                weights: [100, 100, 100],
                reps: [8, 8, 8]
            ),
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-5 * 86_400),
                weights: [100, 100, 100],
                reps: [10, 10, 10]
            )
        ].flatMap { $0 }

        let recommendation = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history,
            trainingProfile: profile,
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(recommendation.kind, .deload)
        XCTAssertEqual(recommendation.sets.compactMap(\.weight), [92.5, 92.5, 92.5, 92.5])
    }

    func testSingleRegressionDoesNotTriggerDeload() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let history = [
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-86_400),
                weights: [100, 100, 100],
                reps: [8, 8, 8]
            ),
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-3 * 86_400),
                weights: [100, 100, 100],
                reps: [10, 10, 10]
            )
        ].flatMap { $0 }

        let recommendation = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history,
            trainingProfile: TrainingProfile(goal: .balanced, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(recommendation.kind, .holdAndBuild)
    }

    func testImprovingRepsAtSameWeightAreNotClassifiedAsPlateau() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let history = [5, 6, 7, 8].enumerated().flatMap { offset, reps in
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-Double(7 - offset * 2) * 86_400),
                weights: [80, 80, 80],
                reps: [reps, reps, reps]
            )
        }

        let recommendation = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history,
            trainingProfile: TrainingProfile(goal: .balanced, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(recommendation.kind, .holdAndBuild)
        XCTAssertEqual(recommendation.sets.map(\.reps), [8, 8, 8, 8])
    }

    func testFourUnchangedSessionsUsePlateauBreakRepVariation() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let history = (1 ... 4).flatMap { daysAgo in
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                weights: [80, 80, 80],
                reps: [7, 7, 7]
            )
        }

        let recommendation = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history,
            trainingProfile: TrainingProfile(goal: .balanced, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(recommendation.kind, .plateauBreak)
        XCTAssertEqual(recommendation.sets.compactMap(\.weight), [80, 80, 80, 80])
        XCTAssertEqual(recommendation.sets.map(\.reps), [5, 5, 5, 5])
    }

    func testFullBodyVariantRotatesABCAndLegacyPlansDecodeAsA() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let profile = TrainingProfile(
            split: .fullBody,
            workoutsPerWeek: 3,
            goal: .balanced,
            calorieMode: .maintenance
        )
        let sessions = (1 ... 3).map { offset in
            coachSession(
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                date: now.addingTimeInterval(-Double(offset) * 86_400),
                weights: [50, 50, 50],
                reps: [8, 8, 8]
            )
        }

        func variant(sessionCount: Int) -> SmartWorkoutVariant {
            RecommendationEngine.buildWorkoutPlan(
                exercises: [exercise],
                history: Array(sessions.prefix(sessionCount)).flatMap { $0 },
                trainingProfile: profile,
                now: now,
                calendar: utcCalendar()
            ).variant
        }

        XCTAssertEqual(variant(sessionCount: 0), .a)
        XCTAssertEqual(variant(sessionCount: 1), .b)
        XCTAssertEqual(variant(sessionCount: 2), .c)
        XCTAssertEqual(variant(sessionCount: 3), .a)

        let rotationExercises = [
            Exercise(name: "Bench Press"),
            Exercise(name: "Shoulder Press"),
            Exercise(name: "Barbell Row"),
            Exercise(name: "Pull Up"),
            Exercise(name: "Squat"),
            Exercise(name: "Romanian Deadlift"),
            Exercise(name: "Leg Press"),
            Exercise(name: "Leg Extension"),
            Exercise(name: "Calf Raise"),
            Exercise(name: "Plank")
        ]
        let rotationHistory = (1 ... 2).map { daysAgo in
            coachSession(
                exerciseID: UUID(),
                exerciseName: "Unmapped rotation marker",
                date: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                weights: [1],
                reps: [1]
            )
        }
        let rotationProfile = TrainingProfile(
            split: .fullBody,
            workoutsPerWeek: 6,
            goal: .balanced,
            calorieMode: .maintenance
        )
        func composition(sessionCount: Int) -> Set<String> {
            Set(RecommendationEngine.buildWorkoutPlan(
                exercises: rotationExercises,
                history: Array(rotationHistory.prefix(sessionCount)).flatMap { $0 },
                trainingProfile: rotationProfile,
                now: now,
                calendar: utcCalendar()
            ).exercises.map { $0.exercise.catalogKey ?? $0.exercise.name })
        }
        let compositionA = composition(sessionCount: 0)
        let compositionB = composition(sessionCount: 1)
        let compositionC = composition(sessionCount: 2)
        XCTAssertGreaterThanOrEqual(
            Set([compositionA, compositionB, compositionC]).count,
            2,
            "Weekly muscle deficits may converge two variants, but rotation must still change composition"
        )

        let legacy = Data(#"{"focus":"fullBody","exercises":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SmartWorkoutPlan.self, from: legacy).variant, .a)
    }

    func testCatalogAliasesShareHistoryAndDriveFocusClassification() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let canonicalExercise = Exercise(name: "Bench Press")
        let aliasHistory = coachSession(
            exerciseID: UUID(),
            exerciseName: "Жим штанги лежачи",
            date: now.addingTimeInterval(-86_400),
            weights: [60, 60, 60],
            reps: [8, 8, 8]
        )
        let fullBodyPlan = RecommendationEngine.buildWorkoutPlan(
            exercises: [canonicalExercise],
            history: aliasHistory,
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 3,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertNotEqual(try XCTUnwrap(fullBodyPlan.exercises.first).recommendation.kind, .newExercise)

        let pplPlan = RecommendationEngine.buildWorkoutPlan(
            exercises: [Exercise(name: "Pull Up")],
            history: aliasHistory,
            trainingProfile: TrainingProfile(
                split: .pushPullLegs,
                workoutsPerWeek: 6,
                goal: .balanced,
                calorieMode: .maintenance
            ),
            now: now,
            calendar: utcCalendar()
        )
        XCTAssertEqual(pplPlan.focus, .pull)
    }

    func testCoachIgnoresNonFiniteHistoryAndProducesDeterministicSetIDs() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let invalidHistory = coachSession(
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            date: now.addingTimeInterval(-86_400),
            weights: [.nan],
            reps: [10]
        )

        let first = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: invalidHistory,
            now: now,
            calendar: utcCalendar()
        )
        let second = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: invalidHistory,
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(first.kind, .newExercise)
        XCTAssertEqual(first.sets.map(\.id), second.sets.map(\.id))
    }

    func testCoachCapsOversizedSessionAndProgressiveWeight() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let exercise = Exercise(name: "Bench Press")
        let workoutID = UUID()
        let olderWorkoutID = UUID()
        var history = (0 ..< 100).map { index in
            ExerciseHistoryEntry(
                setID: UUID(),
                workoutID: workoutID,
                sessionDate: now.addingTimeInterval(-86_400),
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                weight: 1_000_000,
                reps: 8,
                setOrderIndex: index
            )
        }
        history += (0 ..< 100).map { index in
            ExerciseHistoryEntry(
                setID: UUID(),
                workoutID: olderWorkoutID,
                sessionDate: now.addingTimeInterval(-3 * 86_400),
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                weight: 1_000_000,
                reps: 8,
                setOrderIndex: index
            )
        }
        history.append(ExerciseHistoryEntry(
            setID: try XCTUnwrap(UUID(uuidString: "ffffffff-ffff-4fff-bfff-ffffffffffff")),
            workoutID: workoutID,
            sessionDate: now.addingTimeInterval(-86_400),
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            weight: 1_000_000,
            reps: 1,
            setOrderIndex: 99
        ))

        let recommendation = RecommendationEngine.buildForExercise(
            exerciseID: exercise.id,
            history: history,
            trainingProfile: TrainingProfile(goal: .balanced, calorieMode: .maintenance),
            now: now,
            calendar: utcCalendar()
        )

        XCTAssertEqual(recommendation.kind, .progressiveOverload)
        XCTAssertEqual(recommendation.sets.count, 4)
        XCTAssertEqual(recommendation.sets.compactMap(\.weight), Array(repeating: 1_000_000, count: 4))
        XCTAssertEqual(recommendation.sets.map(\.reps), Array(repeating: 5, count: 4))
    }

    func testEveryProfileKeepsPrescriptionsWithinThreeToFourSetsAndTenReps() {
        for goal in TrainingGoal.allCases {
            for calorieMode in CalorieMode.allCases {
                for workoutsPerWeek in 2 ... 6 {
                    let profile = TrainingProfile(
                        split: workoutsPerWeek <= 3 ? .fullBody : workoutsPerWeek == 4 ? .upperLower : .pushPullLegs,
                        workoutsPerWeek: workoutsPerWeek,
                        goal: goal,
                        calorieMode: calorieMode
                    )
                    for exercise in [Exercise(name: "Bench Press"), Exercise(name: "Biceps Curl")] {
                        let recommendation = RecommendationEngine.buildForExercise(
                            exerciseID: exercise.id,
                            history: [],
                            exerciseCatalogKey: exercise.catalogKey,
                            exerciseName: exercise.name,
                            trainingProfile: profile
                        )
                        XCTAssertTrue((3 ... 4).contains(recommendation.sets.count))
                        XCTAssertTrue(recommendation.sets.allSatisfy { (3 ... 10).contains($0.reps) })
                    }
                }
            }
        }
    }

    func testBuiltInCatalogFillsEveryProfileBudgetWithExactlyOneTrunkExercise() {
        let exercises = BuiltInExerciseCatalog.definitions.map {
            Exercise(name: $0.englishName, catalogKey: $0.key)
        }
        let trunkKeys: Set<String> = [
            "hyperextension",
            "side_hyperextension",
            "plank",
            "weighted_crunch",
            "hanging_leg_raise",
            "plate_twist",
            "weighted_side_bend"
        ]

        for goal in TrainingGoal.allCases {
            for calorieMode in CalorieMode.allCases {
                for workoutsPerWeek in 2 ... 6 {
                    for split in TrainingSplit.allCases {
                        let context = "\(goal)/\(calorieMode)/\(workoutsPerWeek)/\(split)"
                        let plan = RecommendationEngine.buildWorkoutPlan(
                            exercises: exercises,
                            history: [],
                            trainingProfile: TrainingProfile(
                                split: split,
                                workoutsPerWeek: workoutsPerWeek,
                                goal: goal,
                                calorieMode: calorieMode
                            )
                        )
                        let expectedCount = 12 - workoutsPerWeek

                        XCTAssertEqual(plan.exercises.count, expectedCount, context)
                        XCTAssertEqual(
                            plan.exercises.filter { exercise in
                                exercise.exercise.catalogKey.map(trunkKeys.contains) ?? false
                            }.count,
                            1,
                            "\(context) trunk"
                        )
                        XCTAssertEqual(
                            Set(plan.exercises.map { $0.exercise.id }).count,
                            plan.exercises.count,
                            "\(context) unique"
                        )
                        XCTAssertTrue(
                            plan.exercises.allSatisfy { (3 ... 4).contains($0.recommendation.sets.count) },
                            "\(context) sets"
                        )
                        XCTAssertTrue(
                            plan.exercises.allSatisfy { exercise in
                                exercise.recommendation.sets.allSatisfy { (3 ... 10).contains($0.reps) }
                            },
                            "\(context) reps"
                        )
                    }
                }
            }
        }
    }

    func testSmartPlanNeverTreatsWarmUpAsAWorkingExercise() {
        let exercises = [
            Exercise(name: "Warm Up"),
            Exercise(name: "Bench Press"),
            Exercise(name: "Barbell Row"),
            Exercise(name: "Squat"),
            Exercise(name: "Shoulder Press"),
            Exercise(name: "Pull Up"),
            Exercise(name: "Romanian Deadlift")
        ]
        let plan = RecommendationEngine.buildWorkoutPlan(
            exercises: exercises,
            history: [],
            trainingProfile: TrainingProfile(
                split: .fullBody,
                workoutsPerWeek: 3,
                goal: .balanced,
                calorieMode: .maintenance
            )
        )

        XCTAssertFalse(plan.exercises.contains { $0.exercise.catalogKey == "warm_up" })
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

    func testGarminRequestForcesOneRefreshAfterDirectUnauthorized() async throws {
        let userID = "00000000-0000-4000-8000-0000000000f1"
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-forced-refresh")
        )
        let account = cloudSession(userID: userID)
        try auth.installSessionForTesting(.cloud(account))
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        )
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/functions/v1/garmin-sync":
                let bearer = request.value(forHTTPHeaderField: "Authorization")
                if bearer == "Bearer \(account.accessToken)" {
                    return try AuthURLProtocolStub.response(
                        for: request,
                        statusCode: 401,
                        json: #"{"error":"JWT expired"}"#
                    )
                }
                XCTAssertEqual(bearer, "Bearer refreshed-garmin-access")
                return try AuthURLProtocolStub.response(for: request, json: #"{"devices":[]}"#)
            case "/auth/v1/token":
                XCTAssertTrue(request.url?.query?.contains("grant_type=refresh_token") == true)
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"access_token":"refreshed-garmin-access","refresh_token":"refreshed-garmin-refresh","expires_in":3600,"user":{"id":"00000000-0000-4000-8000-0000000000f1","email":"garmin@example.com","user_metadata":{"display_name":"Garmin"}}}"#
                )
            default:
                XCTFail("Unexpected Garmin forced-refresh request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        try await garmin.refreshDevices()

        XCTAssertTrue(garmin.availableDevices.isEmpty)
        XCTAssertEqual(
            recorder.requests.map(\.url?.path),
            ["/functions/v1/garmin-sync", "/auth/v1/token", "/functions/v1/garmin-sync"]
        )
        XCTAssertEqual(auth.session?.cloud?.accessToken, "refreshed-garmin-access")
    }

    func testGarminSubmitRequiresAndUsesPersistedAccountDeviceBinding() async throws {
        let userID = "00000000-0000-4000-8000-0000000000a1"
        let deviceID = "00000000-0000-4000-8000-0000000000d1"
        let requestID = try XCTUnwrap(UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
        let rawToken = String(repeating: "ab", count: 32)
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-submit")
        )
        let bindingKeychain = InMemoryKeychainStore()
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: GarminDeviceBindingStore(keychain: bindingKeychain)
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userID)))

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            if request.url?.path == "/functions/v1/garmin-sync" {
                let body = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
                )
                XCTAssertEqual(body["action"] as? String, "createDevice")
                XCTAssertEqual(body["displayName"] as? String, "Gym Watch")
                XCTAssertEqual(body["capabilityVersion"] as? Int, 2)
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: """
                    {"device":{"id":"\(deviceID)","device_token":"\(rawToken)","display_name":"Gym Watch","created_at":"2026-07-14T01:00:00Z","last_seen_at":null,"binding_version":2,"token_revision":1}}
                    """
                )
            }
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/garmin_enqueue_plan")
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"status":"queued","planId":"20000000-0000-4000-8000-000000000001","planRevision":1,"planStatus":"pending"}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        do {
            try await garmin.submit(
                plan: garminPlan(setCount: 1),
                clientRequestID: requestID
            )
            XCTFail("A plan without an account-scoped Garmin binding must not be sent.")
        } catch GarminCloudError.pairingRequired {
            // Expected.
        } catch {
            XCTFail("Unexpected pre-pairing error: \(error)")
        }
        XCTAssertTrue(recorder.requests.isEmpty)

        let credential = try await garmin.createDevice(displayName: "Gym Watch")
        XCTAssertEqual(credential.id, deviceID)
        XCTAssertEqual(credential.deviceToken, rawToken)
        XCTAssertEqual(garmin.selectedDevice?.userID, userID)
        XCTAssertEqual(garmin.selectedDevice?.deviceID, deviceID)
        XCTAssertFalse(bindingKeychain.allData.contains {
            String(decoding: $0, as: UTF8.self).contains(rawToken)
        })

        try await garmin.submit(
            plan: garminPlan(setCount: 1),
            clientRequestID: requestID
        )

        let planRequest = try XCTUnwrap(
            recorder.requests.first(where: {
                $0.url?.path == "/rest/v1/rpc/garmin_enqueue_plan"
            })
        )
        XCTAssertEqual(planRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access-\(userID)")
        XCTAssertNil(planRequest.value(forHTTPHeaderField: "Prefer"))
        let row = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(planRequest.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(row["p_device_id"] as? String, deviceID)
        XCTAssertEqual(row["p_client_request_id"] as? String, requestID.uuidString.lowercased())
        XCTAssertNotNil(row["p_plan"] as? [String: Any])
        XCTAssertNil(row["user_id"])
        XCTAssertNil(row["status"])
    }

    func testGarminEnqueueRetriesLostResponseWithSameDurableWorkoutID() async throws {
        let userID = "00000000-0000-4000-8000-0000000000a1"
        let deviceID = "00000000-0000-4000-8000-0000000000d1"
        let requestID = try XCTUnwrap(UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-enqueue-retry")
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userID)))
        let bindingStore = GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        try bindingStore.save(
            binding: GarminDeviceBinding(
                version: GarminDeviceBinding.currentVersion,
                userID: userID,
                deviceID: deviceID
            )
        )
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: bindingStore
        )

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/garmin_enqueue_plan")
            if recorder.requests.count == 1 {
                throw URLError(.networkConnectionLost)
            }
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"status":"already_queued","planId":"20000000-0000-4000-8000-000000000001","planRevision":1,"planStatus":"downloaded"}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        try await garmin.submit(
            plan: garminPlan(setCount: 1),
            clientRequestID: requestID
        )

        XCTAssertEqual(recorder.requests.count, 2)
        let bodies = try recorder.requests.map { request in
            try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
            )
        }
        for body in bodies {
            XCTAssertEqual(body["p_device_id"] as? String, deviceID)
            XCTAssertEqual(body["p_client_request_id"] as? String, requestID.uuidString.lowercased())
            XCTAssertNotNil(body["p_plan"] as? [String: Any])
            XCTAssertNil(body["user_id"])
            XCTAssertNil(body["status"])
        }
        XCTAssertEqual(
            try JSONSerialization.data(withJSONObject: bodies[0], options: [.sortedKeys]),
            try JSONSerialization.data(withJSONObject: bodies[1], options: [.sortedKeys])
        )
        XCTAssertEqual(
            garmin.lastMessage,
            "This workout was already submitted to the selected Garmin watch."
        )
    }

    func testGarminEnqueueRejectsNonV4IDAndDoesNotDuplicateConflict() async throws {
        let userID = "00000000-0000-4000-8000-0000000000a1"
        let deviceID = "00000000-0000-4000-8000-0000000000d1"
        let validRequestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-4000-8000-000000000001")
        )
        let nonV4RequestID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-3000-8000-000000000001")
        )
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-enqueue-conflict")
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userID)))
        let bindingStore = GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        try bindingStore.save(
            binding: GarminDeviceBinding(
                version: GarminDeviceBinding.currentVersion,
                userID: userID,
                deviceID: deviceID
            )
        )
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: bindingStore
        )

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"status":"conflict"}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        do {
            try await garmin.submit(
                plan: garminPlan(setCount: 1),
                clientRequestID: nonV4RequestID
            )
            XCTFail("A non-v4 idempotency key must be rejected locally.")
        } catch GarminCloudError.invalidRequest {
            // Expected.
        } catch {
            XCTFail("Unexpected non-v4 request-ID error: \(error)")
        }
        XCTAssertTrue(recorder.requests.isEmpty)

        do {
            try await garmin.submit(
                plan: garminPlan(setCount: 1),
                clientRequestID: validRequestID
            )
            XCTFail("A definitive enqueue conflict must not be retried with a new ID.")
        } catch GarminCloudError.enqueueConflict {
            // Expected.
        } catch {
            XCTFail("Unexpected enqueue-conflict error: \(error)")
        }
        XCTAssertEqual(recorder.requests.count, 1)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(recorder.requests.first?.httpBody)
            ) as? [String: Any]
        )
        XCTAssertEqual(
            body["p_client_request_id"] as? String,
            validRequestID.uuidString.lowercased()
        )
    }

    func testGarminExistingDeviceSelectionIsIsolatedAcrossAccountSwitches() async throws {
        let userA = "00000000-0000-4000-8000-0000000000a1"
        let userB = "00000000-0000-4000-8000-0000000000b2"
        let deviceA = "00000000-0000-4000-8000-0000000000d1"
        let deviceB = "00000000-0000-4000-8000-0000000000d2"
        let requestA = try XCTUnwrap(UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
        let requestB = try XCTUnwrap(UUID(uuidString: "10000000-0000-4000-8000-000000000002"))
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-account-isolation")
        )
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userA)))

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            if request.url?.path == "/rest/v1/rpc/garmin_enqueue_plan" {
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"status":"queued","planId":"20000000-0000-4000-8000-000000000001","planRevision":1,"planStatus":"pending"}"#
                )
            }
            let authorization = request.value(forHTTPHeaderField: "Authorization")
            let device = authorization == "Bearer access-\(userA)" ? deviceA : deviceB
            let name = device == deviceA ? "Watch A" : "Watch B"
            return try AuthURLProtocolStub.response(
                for: request,
                json: """
                {"devices":[{"id":"\(device)","display_name":"\(name)","created_at":"2026-07-14T01:00:00Z","last_seen_at":null,"binding_version":2,"token_revision":1}]}
                """
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        try await garmin.refreshDevices()
        try garmin.selectDevice(try XCTUnwrap(garmin.availableDevices.first))
        XCTAssertEqual(garmin.selectedDevice?.deviceID, deviceA)

        try auth.installSessionForTesting(.cloud(cloudSession(userID: userB)))
        let clearedAfterAccountSwitch = await waitUntil { garmin.selectedDevice == nil }
        XCTAssertTrue(clearedAfterAccountSwitch)
        let requestCountBeforeBlockedSubmit = recorder.requests.count
        do {
            try await garmin.submit(
                plan: garminPlan(setCount: 1),
                clientRequestID: requestB
            )
            XCTFail("Account B must not reuse account A's selected device.")
        } catch GarminCloudError.pairingRequired {
            // Expected.
        } catch {
            XCTFail("Unexpected account-isolation error: \(error)")
        }
        XCTAssertEqual(recorder.requests.count, requestCountBeforeBlockedSubmit)

        try await garmin.refreshDevices()
        try garmin.selectDevice(try XCTUnwrap(garmin.availableDevices.first))
        try await garmin.submit(
            plan: garminPlan(setCount: 1),
            clientRequestID: requestB
        )
        XCTAssertEqual(garmin.selectedDevice?.deviceID, deviceB)

        try auth.installSessionForTesting(.cloud(cloudSession(userID: userA)))
        let restoredAccountABinding = await waitUntil {
            garmin.selectedDevice?.deviceID == deviceA
        }
        XCTAssertTrue(restoredAccountABinding)
        try await garmin.submit(
            plan: garminPlan(setCount: 1),
            clientRequestID: requestA
        )

        let planRequests = recorder.requests.filter {
            $0.url?.path == "/rest/v1/rpc/garmin_enqueue_plan"
        }
        XCTAssertEqual(planRequests.count, 2)
        let planRows = try planRequests.map { request in
            try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
            )
        }
        XCTAssertEqual(planRequests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access-\(userB)")
        XCTAssertEqual(planRows[0]["p_device_id"] as? String, deviceB)
        XCTAssertEqual(planRows[0]["p_client_request_id"] as? String, requestB.uuidString.lowercased())
        XCTAssertEqual(planRequests[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-\(userA)")
        XCTAssertEqual(planRows[1]["p_device_id"] as? String, deviceA)
        XCTAssertEqual(planRows[1]["p_client_request_id"] as? String, requestA.uuidString.lowercased())
    }

    func testLateGarminCreateRevokesWithOriginalAccountAndCannotBindReplacement() async throws {
        let userA = "00000000-0000-4000-8000-0000000000a1"
        let userB = "00000000-0000-4000-8000-0000000000b2"
        let deviceA = "00000000-0000-4000-8000-0000000000d1"
        let rawToken = String(repeating: "cd", count: 32)
        let recorder = AuthRequestRecorder()
        let started = expectation(description: "Garmin create started")
        let release = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-stale-create")
        )
        let bindingKeychain = InMemoryKeychainStore()
        let bindingStore = GarminDeviceBindingStore(keychain: bindingKeychain)
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: bindingStore
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userA)))

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
            )
            if body["action"] as? String == "createDevice" {
                started.fulfill()
                _ = release.wait(timeout: .now() + 5)
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: """
                    {"device":{"id":"\(deviceA)","device_token":"\(rawToken)","display_name":"Watch A","created_at":"2026-07-14T01:00:00Z","last_seen_at":null,"binding_version":2,"token_revision":1}}
                    """
                )
            }
            XCTAssertEqual(body["action"] as? String, "revokeDevice")
            XCTAssertEqual(body["deviceId"] as? String, deviceA)
            return try AuthURLProtocolStub.response(for: request, json: #"{"status":"revoked"}"#)
        }
        defer {
            release.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let pending = Task { try await garmin.createDevice(displayName: "Watch A") }
        await fulfillment(of: [started], timeout: 2)
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userB)))
        release.signal()

        do {
            _ = try await pending.value
            XCTFail("A late create response must not bind a replacement account.")
        } catch AuthServiceError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected stale-create error: \(error)")
        }

        XCTAssertNil(garmin.selectedDevice)
        XCTAssertNil(try bindingStore.binding(for: userA))
        XCTAssertNil(try bindingStore.binding(for: userB))
        XCTAssertNil(try bindingStore.pendingRevocation(for: userA))
        XCTAssertFalse(bindingKeychain.allData.contains {
            String(decoding: $0, as: UTF8.self).contains(rawToken)
        })
        let revokeRequest = try XCTUnwrap(recorder.requests.last)
        XCTAssertEqual(revokeRequest.value(forHTTPHeaderField: "Authorization"), "Bearer access-\(userA)")
    }

    func testGarminBindingSaveFailureRevokesUnseenTokenAndClearsPendingRecovery() async throws {
        let userID = "00000000-0000-4000-8000-0000000000a1"
        let deviceID = "00000000-0000-4000-8000-0000000000d1"
        let rawToken = String(repeating: "ef", count: 32)
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-binding-failure")
        )
        let bindingKeychain = InMemoryKeychainStore()
        bindingKeychain.accountsThatFailSave = ["selected-device-v2.\(userID)"]
        let bindingStore = GarminDeviceBindingStore(keychain: bindingKeychain)
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: bindingStore
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userID)))

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
            )
            if body["action"] as? String == "createDevice" {
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: """
                    {"device":{"id":"\(deviceID)","device_token":"\(rawToken)","display_name":"Watch","created_at":"2026-07-14T01:00:00Z","last_seen_at":null,"binding_version":2,"token_revision":1}}
                    """
                )
            }
            XCTAssertEqual(body["action"] as? String, "revokeDevice")
            XCTAssertEqual(body["deviceId"] as? String, deviceID)
            return try AuthURLProtocolStub.response(for: request, json: #"{"status":"revoked"}"#)
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        do {
            _ = try await garmin.createDevice(displayName: "Watch")
            XCTFail("The raw token must not be exposed when durable binding storage fails.")
        } catch GarminCloudError.bindingPersistenceFailed {
            // Expected.
        } catch {
            XCTFail("Unexpected binding-persistence error: \(error)")
        }

        XCTAssertNil(garmin.selectedDevice)
        XCTAssertNil(try bindingStore.binding(for: userID))
        XCTAssertNil(try bindingStore.pendingRevocation(for: userID))
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertFalse(bindingKeychain.allData.contains {
            String(decoding: $0, as: UTF8.self).contains(rawToken)
        })
    }

    func testGarminTokenRotationRetriesNonObject5xxWithSameEphemeralCSPRNGToken() async throws {
        let userID = "00000000-0000-4000-8000-0000000000a1"
        let deviceID = "00000000-0000-4000-8000-0000000000d1"
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-rotation-retry")
        )
        let bindingKeychain = InMemoryKeychainStore()
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: GarminDeviceBindingStore(keychain: bindingKeychain)
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userID)))

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
            )
            if body["action"] as? String == "listDevices" {
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: """
                    {"devices":[{"id":"\(deviceID)","display_name":"Watch","created_at":"2026-07-14T01:00:00Z","last_seen_at":null,"binding_version":2,"token_revision":7}]}
                    """
                )
            }

            XCTAssertEqual(body["action"] as? String, "rotateDeviceToken")
            XCTAssertEqual(body["deviceId"] as? String, deviceID)
            XCTAssertEqual(body["expectedTokenRevision"] as? Int, 7)
            XCTAssertEqual(body["capabilityVersion"] as? Int, 2)
            let replacement = try XCTUnwrap(body["replacementToken"] as? String)
            let rotationCount = recorder.requests.filter { request in
                guard let data = request.httpBody,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return false }
                return object["action"] as? String == "rotateDeviceToken"
            }.count
            if rotationCount == 1 {
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 500,
                    json: #"["Temporary gateway failure"]"#
                )
            }
            return try AuthURLProtocolStub.response(
                for: request,
                json: """
                {"status":"already_rotated","device":{"id":"\(deviceID)","device_token":"\(replacement)","display_name":"Watch","created_at":"2026-07-14T01:00:00Z","last_seen_at":null,"binding_version":2,"token_revision":8}}
                """
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        try await garmin.refreshDevices()
        try garmin.selectDevice(try XCTUnwrap(garmin.availableDevices.first))
        let credential = try await garmin.rotateSelectedDeviceToken()

        XCTAssertEqual(credential.id, deviceID)
        XCTAssertEqual(credential.deviceToken.utf8.count, 64)
        XCTAssertNotNil(
            credential.deviceToken.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            )
        )
        let rotationBodies = try recorder.requests.compactMap { request -> [String: Any]? in
            guard let data = request.httpBody,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["action"] as? String == "rotateDeviceToken" else {
                return nil
            }
            return object
        }
        XCTAssertEqual(rotationBodies.count, 2)
        XCTAssertEqual(
            rotationBodies[0]["replacementToken"] as? String,
            rotationBodies[1]["replacementToken"] as? String
        )
        XCTAssertEqual(garmin.availableDevices.first?.tokenRevision, 8)
        XCTAssertFalse(bindingKeychain.allData.contains {
            String(decoding: $0, as: UTF8.self).contains(credential.deviceToken)
        })
    }

    func testGarminRotationConflictRefreshesRevisionWithoutExposingReplacementToken() async throws {
        let userID = "00000000-0000-4000-8000-0000000000a1"
        let deviceID = "00000000-0000-4000-8000-0000000000d1"
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-rotation-conflict")
        )
        let bindingKeychain = InMemoryKeychainStore()
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: GarminDeviceBindingStore(keychain: bindingKeychain)
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userID)))

        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
            )
            if body["action"] as? String == "rotateDeviceToken" {
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 409,
                    json: #"{"error":"Device token rotation conflict","status":"conflict","tokenRevision":8}"#
                )
            }
            let listCount = recorder.requests.filter { request in
                guard let data = request.httpBody,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return false }
                return object["action"] as? String == "listDevices"
            }.count
            let revision = listCount == 1 ? 7 : 8
            return try AuthURLProtocolStub.response(
                for: request,
                json: """
                {"devices":[{"id":"\(deviceID)","display_name":"Watch","created_at":"2026-07-14T01:00:00Z","last_seen_at":null,"binding_version":2,"token_revision":\(revision)}]}
                """
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        try await garmin.refreshDevices()
        try garmin.selectDevice(try XCTUnwrap(garmin.availableDevices.first))
        do {
            _ = try await garmin.rotateSelectedDeviceToken()
            XCTFail("A stale token revision must not return a replacement token.")
        } catch GarminCloudError.rotationConflict {
            // Expected.
        } catch {
            XCTFail("Unexpected rotation-conflict error: \(error)")
        }

        XCTAssertEqual(garmin.availableDevices.first?.tokenRevision, 8)
        XCTAssertEqual(garmin.selectedDevice?.deviceID, deviceID)
        let attemptedToken = try XCTUnwrap(
            recorder.requests.compactMap { request -> String? in
                guard let data = request.httpBody,
                      let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      body["action"] as? String == "rotateDeviceToken" else {
                    return nil
                }
                return body["replacementToken"] as? String
            }.first
        )
        XCTAssertFalse(bindingKeychain.allData.contains {
            String(decoding: $0, as: UTF8.self).contains(attemptedToken)
        })
    }

    func testLateGarminRotationConflictDoesNotRepublishDeviceListAfterAccountSwitch() async throws {
        let userA = "00000000-0000-4000-8000-0000000000a1"
        let userB = "00000000-0000-4000-8000-0000000000b2"
        let deviceA = "00000000-0000-4000-8000-0000000000d1"
        let rotationStarted = expectation(description: "Garmin rotation started")
        let releaseRotation = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-late-rotation-conflict")
        )
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userA)))

        AuthURLProtocolStub.handler = { request in
            let body = try XCTUnwrap(
                JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any]
            )
            if body["action"] as? String == "listDevices" {
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: """
                    {"devices":[{"id":"\(deviceA)","display_name":"Watch A","created_at":"2026-07-14T01:00:00Z","last_seen_at":null,"binding_version":2,"token_revision":7}]}
                    """
                )
            }

            XCTAssertEqual(body["action"] as? String, "rotateDeviceToken")
            XCTAssertEqual(body["deviceId"] as? String, deviceA)
            rotationStarted.fulfill()
            _ = releaseRotation.wait(timeout: .now() + 5)
            return try AuthURLProtocolStub.response(
                for: request,
                statusCode: 409,
                json: #"{"error":"Device token rotation conflict","status":"conflict","tokenRevision":8}"#
            )
        }
        defer {
            releaseRotation.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        try await garmin.refreshDevices()
        try garmin.selectDevice(try XCTUnwrap(garmin.availableDevices.first))

        var deviceListEmissions = [[GarminDeviceSummary]]()
        let deviceListSubscription = garmin.$availableDevices
            .dropFirst()
            .sink { deviceListEmissions.append($0) }

        let pendingRotation = Task {
            try await garmin.rotateSelectedDeviceToken()
        }
        await fulfillment(of: [rotationStarted], timeout: 2)

        try auth.installSessionForTesting(.cloud(cloudSession(userID: userB)))
        XCTAssertEqual(deviceListEmissions.count, 1)
        XCTAssertTrue(try XCTUnwrap(deviceListEmissions.first).isEmpty)
        releaseRotation.signal()

        do {
            _ = try await pendingRotation.value
            XCTFail("A late rotation conflict must not succeed after an account switch.")
        } catch GarminCloudError.rotationConflict {
            // Expected. The stale account's refresh must not publish any device list.
        } catch {
            XCTFail("Unexpected late rotation-conflict error: \(error)")
        }

        XCTAssertEqual(deviceListEmissions.count, 1)
        XCTAssertTrue(try XCTUnwrap(deviceListEmissions.first).isEmpty)
        withExtendedLifetime(deviceListSubscription) {}
    }

    func testGarminStreamingTransportRejectsResponseAbove256KiB() async throws {
        let userID = "00000000-0000-4000-8000-0000000000a1"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "garmin-response-limit")
        )
        let garmin = GarminCloudService(
            auth: auth,
            urlSession: urlSession,
            bindingStore: GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        )
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userID)))

        AuthURLProtocolStub.handler = { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, Data(repeating: 0x61, count: 256 * 1_024 + 1))
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        do {
            try await garmin.refreshDevices()
            XCTFail("An oversized response must be cancelled before JSON parsing.")
        } catch GarminCloudError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected response-limit error: \(error)")
        }
        XCTAssertFalse(garmin.isWorking)
        XCTAssertTrue(garmin.availableDevices.isEmpty)
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
        XCTAssertFalse(auth.needsPasswordUpdate)

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

    func testTerminalRefreshFailureClearsMatchingPersistedSession() async throws {
        for statusCode in [400, 401] {
            let keychain = InMemoryKeychainStore()
            let defaults = temporaryDefaults(named: "terminal-refresh-\(statusCode)")
            var expired = cloudSession(userID: "terminal-refresh-user")
            expired.expiresAt = Date(timeIntervalSince1970: 0)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AuthURLProtocolStub.self]
            let urlSession = URLSession(configuration: configuration)
            let auth = AuthService(keychain: keychain, urlSession: urlSession, defaults: defaults)
            try auth.installSessionForTesting(.cloud(expired))
            AuthURLProtocolStub.handler = { request in
                XCTAssertTrue(request.url?.query?.contains("grant_type=refresh_token") == true)
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: statusCode,
                    json: #"{"error_code":"refresh_token_not_found","message":"Invalid Refresh Token"}"#
                )
            }

            do {
                _ = try await auth.validCloudSession()
                XCTFail("A terminal refresh rejection must require a new sign-in.")
            } catch AuthServiceError.sessionExpired {
                // Expected.
            } catch {
                XCTFail("Unexpected terminal refresh error: \(error)")
            }

            XCTAssertNil(auth.session)
            XCTAssertEqual(auth.message, "Your session expired. Sign in again.")
            XCTAssertTrue(auth.messageIsError)
            XCTAssertNil(try keychain.read(account: "current-session"))
            XCTAssertNil(
                AuthService(keychain: keychain, urlSession: urlSession, defaults: defaults).session
            )

            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }
    }

    func testTransientRefreshFailurePreservesPersistedSession() async throws {
        for offline in [false, true] {
            let keychain = InMemoryKeychainStore()
            let defaults = temporaryDefaults(named: "transient-refresh-\(offline)")
            var expired = cloudSession(userID: "transient-refresh-user")
            expired.expiresAt = Date(timeIntervalSince1970: 0)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AuthURLProtocolStub.self]
            let urlSession = URLSession(configuration: configuration)
            let auth = AuthService(keychain: keychain, urlSession: urlSession, defaults: defaults)
            try auth.installSessionForTesting(.cloud(expired))
            AuthURLProtocolStub.handler = { request in
                if offline { throw URLError(.notConnectedToInternet) }
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 503,
                    json: #"{"message":"temporarily unavailable"}"#
                )
            }

            do {
                _ = try await auth.validCloudSession()
                XCTFail("A failed refresh must not return a usable refreshed session.")
            } catch {
                // Expected; only terminal 400/401 responses clear the session.
            }

            XCTAssertEqual(auth.session?.cloud, expired)
            let relaunched = AuthService(
                keychain: keychain,
                urlSession: urlSession,
                defaults: defaults
            )
            XCTAssertEqual(relaunched.session?.cloud, expired)

            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }
    }

    func testLateTerminalRefreshCannotClearReplacementSession() async throws {
        let keychain = InMemoryKeychainStore()
        let defaults = temporaryDefaults(named: "late-terminal-refresh")
        var expired = cloudSession(userID: "same-refresh-user")
        expired.expiresAt = Date(timeIntervalSince1970: 0)

        let started = expectation(description: "terminal refresh started")
        let release = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(keychain: keychain, urlSession: urlSession, defaults: defaults)
        try auth.installSessionForTesting(.cloud(expired))
        AuthURLProtocolStub.handler = { request in
            started.fulfill()
            _ = release.wait(timeout: .now() + 5)
            return try AuthURLProtocolStub.response(
                for: request,
                statusCode: 400,
                json: #"{"error_code":"refresh_token_not_found","message":"Invalid Refresh Token"}"#
            )
        }
        defer {
            release.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let refresh = Task { try await auth.validCloudSession() }
        await fulfillment(of: [started], timeout: 2)
        var replacement = cloudSession(userID: expired.userID)
        replacement.accessToken = "replacement-access"
        replacement.refreshToken = "replacement-refresh"
        try auth.installSessionForTesting(.cloud(replacement))
        release.signal()

        do {
            _ = try await refresh.value
            XCTFail("A stale terminal response must not clear the replacement session.")
        } catch AuthServiceError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected late terminal refresh error: \(error)")
        }

        XCTAssertEqual(auth.session?.cloud, replacement)
        XCTAssertEqual(
            AuthService(keychain: keychain, defaults: defaults).session?.cloud,
            replacement
        )
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

        var requestDispositions: [AccountDeletionRequestDisposition] = []
        do {
            try await auth.deleteCloudAccountOnServer(
                expectedUserID: "original-user",
                onRequestDispositionChange: { disposition in
                    requestDispositions.append(disposition)
                }
            )
            XCTFail("Deletion must not follow a replacement authenticated session.")
        } catch AuthServiceError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected deletion error: \(error)")
        }
        XCTAssertTrue(requestDispositions.isEmpty)
        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertEqual(auth.session?.cloud?.userID, "replacement-user")
    }

    func testAppStateDeletionRequiresTheConfirmedStorageKeyAndCloudUserID() async throws {
        let directory = try temporaryDirectory(named: "delete-confirmed-identity")
        let defaults = temporaryDefaults(named: "delete-confirmed-identity")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "confirmed-delete-user")
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: accountSession.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try remoteBackupData(exerciseName: "Confirmed Account Data", owner: owner)
        try auth.installSessionForTesting(accountSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"deleted":true}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            }
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let storageURL = appState.workoutStore.storageURL
        let unconfirmedTargets: [(storageKey: String, cloudUserID: String?)] = [
            (accountSession.storageKey, "different-cloud-user"),
            ("cloud_different-storage-key", cloud.userID)
        ]

        for target in unconfirmedTargets {
            do {
                try await appState.deleteCurrentAccountAndData(
                    expectedStorageKey: target.storageKey,
                    expectedCloudUserID: target.cloudUserID
                )
                XCTFail("Deletion must not follow an identity that was not confirmed.")
            } catch AuthServiceError.sessionChanged {
                // Expected.
            } catch {
                XCTFail("Unexpected confirmed-identity error: \(error)")
            }
        }

        XCTAssertTrue(recorder.requests.isEmpty)
        XCTAssertEqual(auth.session, accountSession)
        XCTAssertTrue(appState.isAccountReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
    }

    func testAppStateDeletionStopsLocalCleanupWhenAccountChangesDuringServerAwait() async throws {
        let directory = try temporaryDirectory(named: "delete-account-switch")
        let defaults = temporaryDefaults(named: "delete-account-switch")
        let recorder = AuthRequestRecorder()
        let requestStarted = expectation(description: "delete request started")
        let releaseRequest = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let originalCloud = cloudSession(userID: "delete-original-user")
        let replacementCloud = cloudSession(userID: "delete-replacement-user")
        let originalSession = AppAccountSession.cloud(originalCloud)
        let replacementSession = AppAccountSession.cloud(replacementCloud)
        let originalOwner = BackupOwner(
            accountID: originalSession.storageKey,
            userID: originalCloud.userID,
            email: originalCloud.email,
            remote: true
        )
        let replacementOwner = BackupOwner(
            accountID: replacementSession.storageKey,
            userID: replacementCloud.userID,
            email: replacementCloud.email,
            remote: true
        )
        let remoteByUserID = [
            originalCloud.userID: try remoteBackupData(
                exerciseName: "Original Account Data",
                owner: originalOwner
            ),
            replacementCloud.userID: try remoteBackupData(
                exerciseName: "Replacement Account Data",
                owner: replacementOwner
            )
        ]
        try auth.installSessionForTesting(originalSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            requestStarted.fulfill()
            _ = releaseRequest.wait(timeout: .now() + 5)
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"deleted":true}"#
            )
        }
        defer {
            releaseRequest.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                try XCTUnwrap(remoteByUserID[requestedUserID])
            }
        )
        let originalReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(originalReady)
        let originalStorageURL = appState.workoutStore.storageURL

        let deletion = Task {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: originalSession.storageKey,
                expectedCloudUserID: originalCloud.userID
            )
        }
        await fulfillment(of: [requestStarted], timeout: 2)
        try auth.installSessionForTesting(replacementSession)
        releaseRequest.signal()

        do {
            try await deletion.value
            XCTFail("A response for the old account must not continue local cleanup.")
        } catch AuthServiceError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected account-switch deletion error: \(error)")
        }

        let replacementReady = await waitUntil {
            appState.isAccountReady
                && appState.workoutStore.accountStorageKey == replacementSession.storageKey
        }
        XCTAssertTrue(replacementReady)
        XCTAssertEqual(auth.session, replacementSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalStorageURL.path))
        XCTAssertTrue(
            customExerciseNames(in: appState.workoutStore).contains("Replacement Account Data")
        )
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(
            defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"),
            originalSession.storageKey
        )
    }

    func testAppStateDeletionCoalescesDuplicateTasksForTheConfirmedAccount() async throws {
        let directory = try temporaryDirectory(named: "delete-single-flight")
        let defaults = temporaryDefaults(named: "delete-single-flight")
        let recorder = AuthRequestRecorder()
        let requestStarted = expectation(description: "delete request started")
        let releaseRequest = DispatchSemaphore(value: 0)
        let gateLock = NSLock()
        var hasBlockedRequest = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "00000000-0000-4000-8000-0000000000a1")
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: accountSession.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try remoteBackupData(exerciseName: "Single Flight Data", owner: owner)
        try auth.installSessionForTesting(accountSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            let shouldBlock = gateLock.withLock {
                guard !hasBlockedRequest else { return false }
                hasBlockedRequest = true
                return true
            }
            if shouldBlock {
                requestStarted.fulfill()
                _ = releaseRequest.wait(timeout: .now() + 5)
            }
            return try AuthURLProtocolStub.response(
                for: request,
                json: #"{"deleted":true}"#
            )
        }
        defer {
            releaseRequest.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            },
            garminBindingStore: GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let storageURL = appState.workoutStore.storageURL

        let firstDeletion = Task {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: accountSession.storageKey,
                expectedCloudUserID: cloud.userID
            )
        }
        await fulfillment(of: [requestStarted], timeout: 2)

        do {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: "cloud_unconfirmed-replacement",
                expectedCloudUserID: "unconfirmed-replacement"
            )
            XCTFail("An in-flight deletion must not be reused for another target.")
        } catch AuthServiceError.sessionChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected in-flight target error: \(error)")
        }

        let duplicateDeletion = Task {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: accountSession.storageKey,
                expectedCloudUserID: cloud.userID
            )
        }
        await Task.yield()
        releaseRequest.signal()

        try await firstDeletion.value
        try await duplicateDeletion.value
        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertNil(auth.session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
    }

    func testMalformedDeleteSuccessPreservesPendingCleanupMarker() async throws {
        let directory = try temporaryDirectory(named: "malformed-delete-success")
        let defaults = temporaryDefaults(named: "malformed-delete-success")
        let keychain = InMemoryKeychainStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "delete-contract-user")
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: accountSession.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try remoteBackupData(exerciseName: "Remote Before Delete", owner: owner)
        try auth.installSessionForTesting(accountSession)
        AuthURLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/functions/v1/delete-account")
            return try AuthURLProtocolStub.response(for: request, json: "{}")
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            }
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        _ = try appState.workoutStore.addExercise(name: "Local Before Delete")
        let storageURL = appState.workoutStore.storageURL

        do {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: accountSession.storageKey,
                expectedCloudUserID: cloud.userID
            )
            XCTFail("A 2xx response without {deleted:true} must be treated as outcome unknown.")
        } catch AuthServiceError.malformedResponse {
            // Expected.
        } catch {
            XCTFail("Unexpected deletion error: \(error)")
        }

        XCTAssertEqual(auth.session?.cloud?.userID, cloud.userID)
        XCTAssertTrue(appState.isAccountReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertTrue(customExerciseNames(in: appState.workoutStore).contains("Local Before Delete"))
        XCTAssertEqual(
            defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"),
            accountSession.storageKey
        )

        let relaunchedAuth = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        _ = try AppState(
            auth: relaunchedAuth,
            defaults: defaults,
            workoutDirectoryURL: directory
        )

        XCTAssertNil(relaunchedAuth.session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
    }

    func testLostDeleteResponsePreservesPendingCleanupMarker() async throws {
        let directory = try temporaryDirectory(named: "lost-delete-response")
        let defaults = temporaryDefaults(named: "lost-delete-response")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "lost-delete-response-user")
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: accountSession.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try remoteBackupData(exerciseName: "Remote Before Lost Delete", owner: owner)
        try auth.installSessionForTesting(accountSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            XCTAssertEqual(request.url?.path, "/functions/v1/delete-account")
            throw URLError(.networkConnectionLost)
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            }
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let storageURL = appState.workoutStore.storageURL

        do {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: accountSession.storageKey,
                expectedCloudUserID: cloud.userID
            )
            XCTFail("A lost response must not be interpreted as a failed server deletion.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(auth.session, accountSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertEqual(
            defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"),
            accountSession.storageKey
        )
    }

    func testDefinitiveDeleteRejectionClearsPendingMarkerWithoutErasingLocalData() async throws {
        let directory = try temporaryDirectory(named: "definitive-delete-rejection")
        let defaults = temporaryDefaults(named: "definitive-delete-rejection")
        let recorder = AuthRequestRecorder()
        let keychain = InMemoryKeychainStore()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "definitive-delete-rejection-user")
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: accountSession.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try remoteBackupData(exerciseName: "Rejected Delete Data", owner: owner)
        try auth.installSessionForTesting(accountSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            XCTAssertEqual(request.url?.path, "/functions/v1/delete-account")
            return try AuthURLProtocolStub.response(
                for: request,
                statusCode: 422,
                json: #"{"message":"Deletion confirmation was rejected."}"#
            )
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            }
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        _ = try appState.workoutStore.addExercise(name: "Local Rejected Delete Data")
        let storageURL = appState.workoutStore.storageURL

        do {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: accountSession.storageKey,
                expectedCloudUserID: cloud.userID
            )
            XCTFail("An authoritative 4xx must reject account deletion.")
        } catch AuthServiceError.requestFailed(let status, _) {
            XCTAssertEqual(status, 422)
        } catch {
            XCTFail("Unexpected definitive deletion rejection: \(error)")
        }

        XCTAssertEqual(recorder.requests.count, 1)
        XCTAssertEqual(auth.session, accountSession)
        XCTAssertTrue(appState.isAccountReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertTrue(
            customExerciseNames(in: appState.workoutStore).contains(
                "Local Rejected Delete Data"
            )
        )
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))

        let relaunchRemote = try appState.workoutStore.exportCloudBackupData(owner: owner)
        let relaunchedAuth = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        let relaunchedState = try AppState(
            auth: relaunchedAuth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return relaunchRemote
            }
        )
        let relaunchedReady = await waitUntil {
            relaunchedState.isAccountReady
                && relaunchedState.workoutStore.accountStorageKey == accountSession.storageKey
        }

        XCTAssertTrue(relaunchedReady)
        XCTAssertEqual(relaunchedAuth.session, accountSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertTrue(
            customExerciseNames(in: relaunchedState.workoutStore).contains(
                "Local Rejected Delete Data"
            )
        )
    }

    func testDelete401WithFailedRefreshClearsPendingMarkerAndKeepsLocalData() async throws {
        let directory = try temporaryDirectory(named: "delete-401-refresh-failure")
        let defaults = temporaryDefaults(named: "delete-401-refresh-failure")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "delete-401-refresh-failure-user")
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: accountSession.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try remoteBackupData(
            exerciseName: "401 Refresh Failure Data",
            owner: owner
        )
        try auth.installSessionForTesting(accountSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/functions/v1/delete-account":
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 401,
                    json: #"{"message":"JWT expired"}"#
                )
            case "/auth/v1/token":
                throw URLError(.notConnectedToInternet)
            default:
                XCTFail("Unexpected 401-refresh request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            }
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        _ = try appState.workoutStore.addExercise(name: "Local 401 Refresh Failure Data")
        let storageURL = appState.workoutStore.storageURL

        do {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: accountSession.storageKey,
                expectedCloudUserID: cloud.userID
            )
            XCTFail("A failed refresh must not dispatch or imply a second delete attempt.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }

        XCTAssertEqual(
            recorder.requests.map(\.url?.path),
            ["/functions/v1/delete-account", "/auth/v1/token"]
        )
        XCTAssertEqual(auth.session, accountSession)
        XCTAssertTrue(appState.isAccountReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertTrue(
            customExerciseNames(in: appState.workoutStore).contains(
                "Local 401 Refresh Failure Data"
            )
        )
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
    }

    func testInitialTokenRefreshDoesNotCreateDeletionMarkerBeforeDispatch() async throws {
        let directory = try temporaryDirectory(named: "delete-initial-refresh-window")
        let defaults = temporaryDefaults(named: "delete-initial-refresh-window")
        let keychain = InMemoryKeychainStore()
        let recorder = AuthRequestRecorder()
        let refreshStarted = expectation(description: "initial delete token refresh started")
        let releaseRefresh = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        var cloud = cloudSession(userID: "delete-initial-refresh-window-user")
        cloud.expiresAt = Date(timeIntervalSince1970: 0)
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: accountSession.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try pwaFlatCloudData(
            exerciseName: "Initial Refresh Preserved Data"
        )
        try auth.installSessionForTesting(accountSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            guard request.url?.path == "/auth/v1/token" else {
                XCTFail("Delete must not dispatch before the initial refresh: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
            refreshStarted.fulfill()
            _ = releaseRefresh.wait(timeout: .now() + 5)
            return try AuthURLProtocolStub.response(
                for: request,
                statusCode: 503,
                json: #"{"message":"Refresh temporarily unavailable"}"#
            )
        }
        defer {
            releaseRefresh.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            }
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let storageURL = appState.workoutStore.storageURL
        let relaunchRemote = try appState.workoutStore.exportCloudBackupData(owner: owner)

        let deletion = Task {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: accountSession.storageKey,
                expectedCloudUserID: cloud.userID
            )
        }
        await fulfillment(of: [refreshStarted], timeout: 2)

        // No delete attempt exists yet, so relaunch must not interpret the refresh as an
        // outcome-unknown account deletion.
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        let relaunchedAuth = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        let relaunchedState = try AppState(
            auth: relaunchedAuth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return relaunchRemote
            }
        )
        let relaunchedReady = await waitUntil {
            relaunchedState.isAccountReady
                && relaunchedState.workoutStore.accountStorageKey == accountSession.storageKey
        }

        XCTAssertTrue(relaunchedReady)
        XCTAssertEqual(relaunchedAuth.session, accountSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertTrue(
            customExerciseNames(in: relaunchedState.workoutStore).contains(
                "Initial Refresh Preserved Data"
            )
        )

        releaseRefresh.signal()
        do {
            try await deletion.value
            XCTFail("A failed initial refresh must not complete account deletion.")
        } catch AuthServiceError.requestFailed(let status, _) {
            XCTAssertEqual(status, 503)
        } catch {
            XCTFail("Unexpected initial refresh error: \(error)")
        }

        XCTAssertEqual(recorder.requests.map(\.url?.path), ["/auth/v1/token"])
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testDefinitive401ClearsMarkerWhileRefreshIsStillSuspended() async throws {
        let directory = try temporaryDirectory(named: "delete-refresh-crash-window")
        let defaults = temporaryDefaults(named: "delete-refresh-crash-window")
        let keychain = InMemoryKeychainStore()
        let recorder = AuthRequestRecorder()
        let refreshStarted = expectation(description: "delete token refresh started")
        let releaseRefresh = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "delete-refresh-crash-window-user")
        let accountSession = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: accountSession.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try remoteBackupData(
            exerciseName: "Refresh Crash Window Remote Data",
            owner: owner
        )
        try auth.installSessionForTesting(accountSession)
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/functions/v1/delete-account":
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 401,
                    json: #"{"message":"JWT expired"}"#
                )
            case "/auth/v1/token":
                refreshStarted.fulfill()
                _ = releaseRefresh.wait(timeout: .now() + 5)
                throw URLError(.notConnectedToInternet)
            default:
                XCTFail("Unexpected crash-window request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        defer {
            releaseRefresh.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            }
        )
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        _ = try appState.workoutStore.addExercise(name: "Refresh Crash Window Local Data")
        try appState.workoutStore.saveNow()
        let storageURL = appState.workoutStore.storageURL

        let deletion = Task {
            try await appState.deleteCurrentAccountAndData(
                expectedStorageKey: accountSession.storageKey,
                expectedCloudUserID: cloud.userID
            )
        }
        await fulfillment(of: [refreshStarted], timeout: 2)

        // The first delete was rejected. This must already be durable before the refresh
        // completes, otherwise a termination in this window would erase valid local data.
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))

        let relaunchRemote = try appState.workoutStore.exportCloudBackupData(owner: owner)
        let relaunchedAuth = AuthService(
            keychain: keychain,
            urlSession: urlSession,
            defaults: defaults
        )
        let relaunchedState = try AppState(
            auth: relaunchedAuth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return relaunchRemote
            }
        )
        let relaunchedReady = await waitUntil {
            relaunchedState.isAccountReady
                && relaunchedState.workoutStore.accountStorageKey == accountSession.storageKey
        }

        XCTAssertTrue(relaunchedReady)
        XCTAssertEqual(relaunchedAuth.session, accountSession)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        XCTAssertTrue(
            customExerciseNames(in: relaunchedState.workoutStore).contains(
                "Refresh Crash Window Local Data"
            )
        )

        releaseRefresh.signal()
        do {
            try await deletion.value
            XCTFail("A failed refresh must not complete account deletion.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }

        XCTAssertEqual(
            recorder.requests.map(\.url?.path),
            ["/functions/v1/delete-account", "/auth/v1/token"]
        )
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testDeleteDispositionReturnsToUnknownWhenRefreshedRequestIsDispatched() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "delete-retry-disposition")
        )
        let cloud = cloudSession(userID: "delete-retry-disposition-user")
        try auth.installSessionForTesting(.cloud(cloud))
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/functions/v1/delete-account"
                    where request.value(forHTTPHeaderField: "Authorization")
                        == "Bearer \(cloud.accessToken)":
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 401,
                    json: #"{"message":"JWT expired"}"#
                )
            case "/auth/v1/token":
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"{"access_token":"refreshed-delete-access","refresh_token":"refreshed-delete-refresh","expires_in":3600,"user":{"id":"delete-retry-disposition-user","email":"delete-retry-disposition-user@example.com","user_metadata":{"display_name":"Delete"}}}"#
                )
            case "/functions/v1/delete-account":
                throw URLError(.networkConnectionLost)
            default:
                XCTFail("Unexpected delete retry request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        var dispositions: [AccountDeletionRequestDisposition] = []
        do {
            try await auth.deleteCloudAccountOnServer(
                expectedUserID: cloud.userID,
                onRequestDispositionChange: { dispositions.append($0) }
            )
            XCTFail("A lost refreshed deletion response must remain outcome-unknown.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        XCTAssertEqual(
            recorder.requests.map(\.url?.path),
            [
                "/functions/v1/delete-account",
                "/auth/v1/token",
                "/functions/v1/delete-account"
            ]
        )
        XCTAssertEqual(
            dispositions,
            [.outcomeUnknown, .definitivelyRejected, .outcomeUnknown]
        )
        XCTAssertEqual(auth.session?.cloud?.accessToken, "refreshed-delete-access")
    }

    func testDeleteDispositionStaysRejectedWhenRefreshFailsBeforeRetry() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "delete-refresh-failure-disposition")
        )
        let cloud = cloudSession(userID: "delete-refresh-failure-user")
        try auth.installSessionForTesting(.cloud(cloud))
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch request.url?.path {
            case "/functions/v1/delete-account":
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 401,
                    json: #"{"message":"JWT expired"}"#
                )
            case "/auth/v1/token":
                throw URLError(.notConnectedToInternet)
            default:
                XCTFail("Unexpected refresh-failure request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        var dispositions: [AccountDeletionRequestDisposition] = []
        do {
            try await auth.deleteCloudAccountOnServer(
                expectedUserID: cloud.userID,
                onRequestDispositionChange: { dispositions.append($0) }
            )
            XCTFail("A failed refresh must not dispatch a second deletion request.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }

        XCTAssertEqual(
            recorder.requests.map(\.url?.path),
            ["/functions/v1/delete-account", "/auth/v1/token"]
        )
        XCTAssertEqual(dispositions, [.outcomeUnknown, .definitivelyRejected])
        XCTAssertEqual(auth.session?.cloud, cloud)
    }

    func testDeleteAccountAcceptsExactServerContract() async throws {
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: temporaryDefaults(named: "valid-delete-contract")
        )
        let cloud = cloudSession(userID: "valid-delete-user")
        try auth.installSessionForTesting(.cloud(cloud))
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            return try AuthURLProtocolStub.response(for: request, json: #"{"deleted":true}"#)
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        try await auth.deleteCloudAccountOnServer(expectedUserID: cloud.userID)

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/functions/v1/delete-account")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GymApp-Delete"), "confirmed")
        XCTAssertEqual(try jsonObject(from: request)["confirmation"] as? String, "DELETE")
    }

    func testPendingDeletionCleanupDoesNotClearAReplacementAccount() async throws {
        let directory = try temporaryDirectory(named: "pending-delete-replacement")
        let defaults = temporaryDefaults(named: "pending-delete-replacement")
        let deletedGarminUserID = "00000000-0000-4000-8000-0000000000a1"
        let deletedGarminDeviceID = "00000000-0000-4000-8000-0000000000d1"
        let deletedSession = AppAccountSession.cloud(cloudSession(userID: deletedGarminUserID))
        let replacementSession = AppAccountSession.local(id: "replacement", displayName: "Replacement")
        let garminBindingStore = GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        try garminBindingStore.save(
            binding: GarminDeviceBinding(
                version: GarminDeviceBinding.currentVersion,
                userID: deletedGarminUserID,
                deviceID: deletedGarminDeviceID
            )
        )
        try garminBindingStore.savePendingRevocation(
            userID: deletedGarminUserID,
            deviceID: deletedGarminDeviceID
        )
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
            workoutDirectoryURL: directory,
            garminBindingStore: garminBindingStore
        )

        XCTAssertEqual(auth.session?.storageKey, replacementSession.storageKey)
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedStore.storageURL.path))
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-storage-key"))
        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-garmin-user-id"))
        XCTAssertNil(try garminBindingStore.binding(for: deletedGarminUserID))
        XCTAssertNil(try garminBindingStore.pendingRevocation(for: deletedGarminUserID))
        let replacementReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(replacementReady)
        XCTAssertEqual(appState.workoutStore.accountStorageKey, replacementSession.storageKey)
    }

    func testOrphanLegacyGarminDeletionMarkerCannotDeleteAWorkingBinding() async throws {
        let directory = try temporaryDirectory(named: "orphan-garmin-delete-marker")
        let defaults = temporaryDefaults(named: "orphan-garmin-delete-marker")
        let userID = "00000000-0000-4000-8000-0000000000a1"
        let deviceID = "00000000-0000-4000-8000-0000000000d1"
        let bindingStore = GarminDeviceBindingStore(keychain: InMemoryKeychainStore())
        try bindingStore.save(
            binding: GarminDeviceBinding(
                version: GarminDeviceBinding.currentVersion,
                userID: userID,
                deviceID: deviceID
            )
        )
        defaults.set(userID, forKey: "gymapp.pending-account-deletion-garmin-user-id")

        let auth = AuthService(keychain: InMemoryKeychainStore(), defaults: defaults)
        try auth.installSessionForTesting(.cloud(cloudSession(userID: userID)))
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { _ in throw URLError(.notConnectedToInternet) },
            garminBindingStore: bindingStore
        )

        XCTAssertNil(defaults.string(forKey: "gymapp.pending-account-deletion-garmin-user-id"))
        XCTAssertEqual(try bindingStore.binding(for: userID)?.deviceID, deviceID)
        let activationFailed = await waitUntil { appState.accountPreparationError != nil }
        XCTAssertTrue(activationFailed)
        XCTAssertFalse(appState.isAccountReady)
    }

    func testTransientCloudLoadFailureRequiresRetryBeforePublishingAccount() async throws {
        let directory = try temporaryDirectory(named: "transient-cloud-activation")
        let defaults = temporaryDefaults(named: "transient-cloud-activation")
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            defaults: defaults
        )
        let cloud = cloudSession(userID: "transient-cloud-user")
        let session = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: session.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let remote = try remoteBackupData(exerciseName: "Remote After Retry", owner: owner)
        let firstLoad = expectation(description: "first remote load failed")
        var loadAttempts = 0
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                loadAttempts += 1
                if loadAttempts == 1 {
                    firstLoad.fulfill()
                    throw URLError(.notConnectedToInternet)
                }
                return remote
            }
        )

        try auth.installSessionForTesting(session)
        await fulfillment(of: [firstLoad], timeout: 2)
        let activationFailed = await waitUntil { appState.accountPreparationError != nil }

        XCTAssertTrue(activationFailed)
        XCTAssertFalse(appState.isAccountReady)
        XCTAssertNil(appState.activeAccountStorageKey)
        XCTAssertNotEqual(appState.workoutStore.accountStorageKey, session.storageKey)

        appState.retryAccountActivation()
        let accountReady = await waitUntil {
            appState.isAccountReady &&
                self.customExerciseNames(in: appState.workoutStore) == ["Remote After Retry"]
        }

        XCTAssertTrue(accountReady)
        XCTAssertEqual(loadAttempts, 2)
        XCTAssertNil(appState.accountPreparationError)
        XCTAssertFalse(appState.isCloudWritePaused)
    }

    func testCanonicalCloudConflictRequiresChoiceAndCanLoadVerifiedCloudHistory() async throws {
        let directory = try temporaryDirectory(named: "cloud-conflict-use-cloud")
        let defaults = temporaryDefaults(named: "cloud-conflict-use-cloud")
        let auth = AuthService(keychain: InMemoryKeychainStore(), defaults: defaults)
        let cloud = cloudSession(userID: "cloud-conflict-use-cloud-user")
        let session = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: session.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let localStore = try WorkoutStore(
            accountStorageKey: session.storageKey,
            directoryURL: directory
        )
        let localExercise = try localStore.addExercise(name: "Local Conflict Exercise")
        _ = try localStore.createWorkout(
            date: Date(timeIntervalSince1970: 1_750_000_100),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: localExercise.id,
                    sets: [.init(weight: 80, reps: 8)]
                )
            ]
        )
        let remote = try remoteBackupData(
            exerciseName: "Cloud Conflict Exercise",
            owner: owner
        )
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { requestedUserID in
                XCTAssertEqual(requestedUserID, cloud.userID)
                return remote
            }
        )

        try auth.installSessionForTesting(session)
        let conflictReady = await waitUntil { appState.cloudSyncConflict != nil }

        XCTAssertTrue(conflictReady)
        XCTAssertFalse(appState.isAccountReady)
        XCTAssertEqual(appState.cloudSyncConflict?.localWorkoutCount, 1)
        XCTAssertEqual(appState.cloudSyncConflict?.cloudWorkoutCount, 1)
        let localBackup = String(decoding: try appState.cloudSyncConflictBackupData(), as: UTF8.self)
        XCTAssertTrue(localBackup.contains("Local Conflict Exercise"))
        XCTAssertFalse(localBackup.contains("Cloud Conflict Exercise"))

        appState.resolveCloudSyncConflict(useCloudVersion: true)
        let accountReady = await waitUntil {
            appState.isAccountReady &&
                self.customExerciseNames(in: appState.workoutStore) ==
                    ["Cloud Conflict Exercise"]
        }

        XCTAssertTrue(accountReady)
        XCTAssertNil(appState.cloudSyncConflict)
    }

    func testCloudConflictChoiceRejectsAChangedRemoteWithoutReplacingLocalHistory() async throws {
        let directory = try temporaryDirectory(named: "cloud-conflict-stale-remote")
        let defaults = temporaryDefaults(named: "cloud-conflict-stale-remote")
        let auth = AuthService(keychain: InMemoryKeychainStore(), defaults: defaults)
        let cloud = cloudSession(userID: "cloud-conflict-stale-user")
        let session = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: session.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let localStore = try WorkoutStore(
            accountStorageKey: session.storageKey,
            directoryURL: directory
        )
        _ = try localStore.addExercise(name: "Preserved Local Exercise")
        let firstRemote = try remoteBackupData(exerciseName: "First Cloud Exercise", owner: owner)
        let changedRemote = try remoteBackupData(exerciseName: "Changed Cloud Exercise", owner: owner)
        var loads = 0
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            remoteStateLoader: { _ in
                loads += 1
                return loads == 1 ? firstRemote : changedRemote
            }
        )

        try auth.installSessionForTesting(session)
        let conflictReady = await waitUntil { appState.cloudSyncConflict != nil }
        XCTAssertTrue(conflictReady)

        appState.resolveCloudSyncConflict(useCloudVersion: true)
        let rejected = await waitUntil {
            appState.accountPreparationError != nil &&
                !appState.isResolvingCloudSyncConflict
        }

        XCTAssertTrue(rejected)
        XCTAssertFalse(appState.isAccountReady)
        XCTAssertNotNil(appState.cloudSyncConflict)
        let preserved = try WorkoutStore(
            accountStorageKey: session.storageKey,
            directoryURL: directory
        )
        XCTAssertEqual(customExerciseNames(in: preserved), ["Preserved Local Exercise"])
    }

    func testCloudConflictCanKeepLocalHistoryWithFreshRevisionCAS() async throws {
        let directory = try temporaryDirectory(named: "cloud-conflict-keep-local")
        let defaults = temporaryDefaults(named: "cloud-conflict-keep-local")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "cloud-conflict-keep-local-user")
        let session = AppAccountSession.cloud(cloud)
        let owner = BackupOwner(
            accountID: session.storageKey,
            userID: cloud.userID,
            email: cloud.email,
            remote: true
        )
        let localStore = try WorkoutStore(
            accountStorageKey: session.storageKey,
            directoryURL: directory
        )
        _ = try localStore.addExercise(name: "Keep Local Exercise")
        let remoteData = try remoteBackupData(exerciseName: "Replace Cloud Exercise", owner: owner)
        let remoteObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: remoteData) as? [String: Any]
        )
        let revision0 = "2026-07-23T09:00:00.000000Z"
        let revision1 = "2026-07-23T09:00:01.000000Z"
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                let response: [[String: Any]] = [[
                    "state": remoteObject,
                    "updated_at": revision0
                ]]
                let data = try JSONSerialization.data(withJSONObject: response)
                return (HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!, data)
            case ("/rest/v1/user_states", "PATCH"):
                let revisionFilter = URLComponents(
                    url: try XCTUnwrap(request.url),
                    resolvingAgainstBaseURL: false
                )?.queryItems?.first(where: { $0.name == "updated_at" })?.value
                XCTAssertEqual(revisionFilter, "eq.\(revision0)")
                let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
                XCTAssertTrue(body.contains("Keep Local Exercise"))
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"\#(revision1)"}]"#
                )
            case ("/rest/v1/profiles", "POST"):
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            default:
                XCTFail("Unexpected conflict request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 404,
                    json: "{}"
                )
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession
        )

        try auth.installSessionForTesting(session)
        let conflictReady = await waitUntil { appState.cloudSyncConflict != nil }
        XCTAssertTrue(conflictReady)
        appState.resolveCloudSyncConflict(useCloudVersion: false)
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)

        XCTAssertEqual(
            customExerciseNames(in: appState.workoutStore),
            ["Keep Local Exercise"]
        )
        XCTAssertEqual(
            recorder.requests.filter {
                $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
            }.count,
            1
        )
    }

    func testSignOutFlushesPendingWritableCloudStateBeforeLogout() async throws {
        let directory = try temporaryDirectory(named: "signout-cloud-flush")
        let defaults = temporaryDefaults(named: "signout-cloud-flush")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "signout-flush-user")
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                return try AuthURLProtocolStub.response(for: request, json: "[]")
            case ("/rest/v1/user_states", "POST"):
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"2026-07-22T12:00:00.000000Z"}]"#
                )
            case ("/rest/v1/user_states", "PATCH"):
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"2026-07-22T12:00:01.000000Z"}]"#
                )
            case ("/rest/v1/profiles", "POST"), ("/auth/v1/logout", "POST"):
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            default:
                XCTFail("Unexpected cloud/logout request: \(request.httpMethod ?? "nil") \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession
        )
        try auth.installSessionForTesting(.cloud(cloud))
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let baselineRequestCount = recorder.requests.count

        _ = try appState.workoutStore.addExercise(name: "Last-second cloud edit")
        await Task.yield()
        let signedOut = await appState.signOut()

        XCTAssertTrue(signedOut)
        XCTAssertNil(auth.session)
        let finalRequests = Array(recorder.requests.dropFirst(baselineRequestCount))
        let stateWrites = finalRequests.filter {
            $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
        }
        XCTAssertFalse(stateWrites.isEmpty)
        let finalStateWrite = try XCTUnwrap(stateWrites.last)
        let finalBody = String(decoding: try XCTUnwrap(finalStateWrite.httpBody), as: UTF8.self)
        XCTAssertTrue(finalBody.contains("Last-second cloud edit"))

        let patchIndex = try XCTUnwrap(finalRequests.lastIndex(where: {
            $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
        }))
        let profileIndex = try XCTUnwrap(finalRequests.lastIndex(where: {
            $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "POST"
        }))
        let logoutIndex = try XCTUnwrap(finalRequests.firstIndex(where: {
            $0.url?.path == "/auth/v1/logout" && $0.httpMethod == "POST"
        }))
        XCTAssertLessThan(patchIndex, profileIndex)
        XCTAssertLessThan(profileIndex, logoutIndex)
    }

    func testSignOutUploadFailureKeepsCurrentAccountForRetry() async throws {
        let directory = try temporaryDirectory(named: "signout-cloud-failure")
        let defaults = temporaryDefaults(named: "signout-cloud-failure")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let cloud = cloudSession(userID: "signout-failure-user")
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                return try AuthURLProtocolStub.response(for: request, json: "[]")
            case ("/rest/v1/user_states", "POST"):
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"2026-07-22T12:00:00.000000Z"}]"#
                )
            case ("/rest/v1/user_states", "PATCH"):
                return try AuthURLProtocolStub.response(
                    for: request,
                    statusCode: 503,
                    json: #"{"message":"temporarily unavailable"}"#
                )
            case ("/rest/v1/profiles", "POST"):
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            default:
                XCTFail("Logout must not be requested after a failed final upload: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession
        )
        try auth.installSessionForTesting(.cloud(cloud))
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let baselineRequestCount = recorder.requests.count

        _ = try appState.workoutStore.addExercise(name: "Unsynced logout edit")
        await Task.yield()
        let signedOut = await appState.signOut()

        XCTAssertFalse(signedOut)
        XCTAssertEqual(auth.session?.cloud?.userID, cloud.userID)
        XCTAssertTrue(appState.isAccountReady)
        XCTAssertTrue(customExerciseNames(in: appState.workoutStore).contains("Unsynced logout edit"))
        XCTAssertTrue(appState.statusIsError)
        XCTAssertNotNil(appState.statusMessage)
        let finalRequests = Array(recorder.requests.dropFirst(baselineRequestCount))
        let failedStateWrites = finalRequests.filter {
            $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
        }
        XCTAssertFalse(failedStateWrites.isEmpty)
        let finalFailedBody = String(
            decoding: try XCTUnwrap(failedStateWrites.last?.httpBody),
            as: UTF8.self
        )
        XCTAssertTrue(finalFailedBody.contains("Unsynced logout edit"))
        XCTAssertFalse(finalRequests.contains(where: { $0.url?.path == "/auth/v1/logout" }))
    }

    func testSignOutRepeatsFinalUploadWhenStoreChangesDuringAwait() async throws {
        let directory = try temporaryDirectory(named: "signout-stable-snapshot")
        let defaults = temporaryDefaults(named: "signout-stable-snapshot")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let account = cloudSession(userID: "signout-stable-snapshot-user")
        let accountSession = AppAccountSession.cloud(account)
        let seededStore = try WorkoutStore(
            accountStorageKey: accountSession.storageKey,
            directoryURL: directory
        )
        _ = try seededStore.seedBuiltInExercises()
        _ = try seededStore.seedDefaultMuscleMappings()

        let firstFinalPatchStarted = expectation(description: "first final PATCH started")
        let firstFinalPatchGate = DispatchSemaphore(value: 0)
        let revision0 = "2026-07-22T12:10:00.000000Z"
        let revision1 = "2026-07-22T12:10:01.000000Z"
        let revision2 = "2026-07-22T12:10:02.000000Z"
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                return try AuthURLProtocolStub.response(for: request, json: "[]")
            case ("/rest/v1/user_states", "POST"):
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"\#(revision0)"}]"#
                )
            case ("/rest/v1/user_states", "PATCH"):
                let patchCount = recorder.requests.filter {
                    $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
                }.count
                if patchCount == 1 {
                    firstFinalPatchStarted.fulfill()
                    _ = firstFinalPatchGate.wait(timeout: .now() + 5)
                }
                let revision = patchCount == 1 ? revision1 : revision2
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"\#(revision)"}]"#
                )
            case ("/rest/v1/profiles", "POST"), ("/auth/v1/logout", "POST"):
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            default:
                XCTFail("Unexpected stable-signout request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            firstFinalPatchGate.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession
        )
        try auth.installSessionForTesting(accountSession)
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let baselineRequestCount = recorder.requests.count

        _ = try appState.workoutStore.addExercise(name: "Before final sign-out upload")
        let signOutTask = Task { await appState.signOut() }
        await fulfillment(of: [firstFinalPatchStarted], timeout: 3)
        _ = try appState.workoutStore.addExercise(name: "Added during final upload")
        firstFinalPatchGate.signal()

        let signedOut = await signOutTask.value
        XCTAssertTrue(signedOut)
        let finalRequests = Array(recorder.requests.dropFirst(baselineRequestCount))
        let patches = finalRequests.filter {
            $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
        }
        XCTAssertGreaterThanOrEqual(patches.count, 2)
        let firstBody = String(decoding: try XCTUnwrap(patches.first?.httpBody), as: UTF8.self)
        let lastBody = String(decoding: try XCTUnwrap(patches.last?.httpBody), as: UTF8.self)
        XCTAssertFalse(firstBody.contains("Added during final upload"))
        XCTAssertTrue(lastBody.contains("Added during final upload"))
        let lastPatchIndex = try XCTUnwrap(finalRequests.lastIndex(where: {
            $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
        }))
        let logoutIndex = try XCTUnwrap(finalRequests.firstIndex(where: {
            $0.url?.path == "/auth/v1/logout"
        }))
        XCTAssertLessThan(lastPatchIndex, logoutIndex)
    }

    func testSignOutWaitsForInFlightAutosaveAndUsesReturnedRevision() async throws {
        let directory = try temporaryDirectory(named: "signout-inflight-cas")
        let defaults = temporaryDefaults(named: "signout-inflight-cas")
        let recorder = AuthRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthURLProtocolStub.self]
        let urlSession = URLSession(configuration: configuration)
        let auth = AuthService(
            keychain: InMemoryKeychainStore(),
            urlSession: urlSession,
            defaults: defaults
        )
        let account = cloudSession(userID: "signout-inflight-cas-user")
        let accountSession = AppAccountSession.cloud(account)
        let seededStore = try WorkoutStore(
            accountStorageKey: accountSession.storageKey,
            directoryURL: directory
        )
        _ = try seededStore.seedBuiltInExercises()
        _ = try seededStore.seedDefaultMuscleMappings()

        let inFlightPatchStarted = expectation(description: "autosave PATCH started")
        let inFlightPatchGate = DispatchSemaphore(value: 0)
        let revision0 = "2026-07-22T12:20:00.000000Z"
        let revision1 = "2026-07-22T12:20:01.000000Z"
        let revision2 = "2026-07-22T12:20:02.000000Z"
        AuthURLProtocolStub.handler = { request in
            recorder.append(request)
            switch (request.url?.path, request.httpMethod) {
            case ("/rest/v1/user_states", "GET"):
                return try AuthURLProtocolStub.response(for: request, json: "[]")
            case ("/rest/v1/user_states", "POST"):
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"\#(revision0)"}]"#
                )
            case ("/rest/v1/user_states", "PATCH"):
                let patchCount = recorder.requests.filter {
                    $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
                }.count
                let revisionFilter = URLComponents(
                    url: try XCTUnwrap(request.url),
                    resolvingAgainstBaseURL: false
                )?.queryItems?.first(where: { $0.name == "updated_at" })?.value
                if patchCount == 1 {
                    XCTAssertEqual(revisionFilter, "eq.\(revision0)")
                    inFlightPatchStarted.fulfill()
                    _ = inFlightPatchGate.wait(timeout: .now() + 5)
                    return try AuthURLProtocolStub.response(
                        for: request,
                        json: #"[{"updated_at":"\#(revision1)"}]"#
                    )
                }
                guard revisionFilter == "eq.\(revision1)" else {
                    return try AuthURLProtocolStub.response(for: request, json: "[]")
                }
                return try AuthURLProtocolStub.response(
                    for: request,
                    json: #"[{"updated_at":"\#(revision2)"}]"#
                )
            case ("/rest/v1/profiles", "POST"), ("/auth/v1/logout", "POST"):
                return try AuthURLProtocolStub.response(for: request, json: "{}")
            default:
                XCTFail("Unexpected in-flight-signout request: \(request.url?.absoluteString ?? "nil")")
                return try AuthURLProtocolStub.response(for: request, statusCode: 404, json: "{}")
            }
        }
        defer {
            inFlightPatchGate.signal()
            AuthURLProtocolStub.handler = nil
            urlSession.invalidateAndCancel()
        }

        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            cloudURLSession: urlSession
        )
        try auth.installSessionForTesting(accountSession)
        let accountReady = await waitUntil { appState.isAccountReady }
        XCTAssertTrue(accountReady)
        let baselineRequestCount = recorder.requests.count

        _ = try appState.workoutStore.addExercise(name: "In-flight autosave")
        await Task.yield()
        appState.saveBeforeBackgrounding()
        await fulfillment(of: [inFlightPatchStarted], timeout: 3)
        _ = try appState.workoutStore.addExercise(name: "Queued behind autosave")
        let signOutTask = Task { await appState.signOut() }
        let signOutStarted = await waitUntil { appState.isSigningOut }
        XCTAssertTrue(signOutStarted)
        inFlightPatchGate.signal()

        let signedOut = await signOutTask.value
        XCTAssertTrue(signedOut)
        let finalRequests = Array(recorder.requests.dropFirst(baselineRequestCount))
        let patches = finalRequests.filter {
            $0.url?.path == "/rest/v1/user_states" && $0.httpMethod == "PATCH"
        }
        XCTAssertEqual(patches.count, 2)
        let firstBody = String(decoding: try XCTUnwrap(patches.first?.httpBody), as: UTF8.self)
        let lastBody = String(decoding: try XCTUnwrap(patches.last?.httpBody), as: UTF8.self)
        XCTAssertTrue(firstBody.contains("In-flight autosave"))
        XCTAssertFalse(firstBody.contains("Queued behind autosave"))
        XCTAssertTrue(lastBody.contains("Queued behind autosave"))
        XCTAssertNil(auth.session)
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
                self.customExerciseNames(in: appState.workoutStore) == ["Browser Workout"]
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
            customExerciseNames(in: appState.workoutStore),
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
        XCTAssertEqual(customExerciseNames(in: appState.workoutStore), ["Prior Account Secret"])

        try auth.installSessionForTesting(.cloud(cloudB))
        await fulfillment(of: [gate.expectation(for: "user-b")], timeout: 2)
        XCTAssertFalse(appState.isAccountReady)
        gate.release(userID: "user-b")
        let accountBReady = await waitUntil {
            appState.isAccountReady && self.customExerciseNames(in: appState.workoutStore) == ["Account B"]
        }
        XCTAssertTrue(accountBReady)

        gate.release(userID: "user-a")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(auth.session?.cloud?.userID, "user-b")
        XCTAssertTrue(appState.isAccountReady)
        XCTAssertEqual(customExerciseNames(in: appState.workoutStore), ["Account B"])
    }

    func testDemoDataIsExplicitAndIdempotent() throws {
        let store = try WorkoutStore(accountStorageKey: "demo", directoryURL: try temporaryDirectory(named: "demo"))
        XCTAssertTrue(store.exercises.isEmpty)
        XCTAssertTrue(try store.seedDemoData())
        XCTAssertFalse(try store.seedDemoData())
        XCTAssertEqual(store.workouts.count, 2)
    }

    private func coachSession(
        exerciseID: UUID,
        exerciseName: String,
        exerciseCatalogKey: String? = nil,
        workoutID: UUID = UUID(),
        date: Date,
        weights: [Double],
        reps: [Int]
    ) -> [ExerciseHistoryEntry] {
        precondition(weights.count == reps.count)
        return weights.indices.map { index in
            ExerciseHistoryEntry(
                setID: UUID(),
                workoutID: workoutID,
                sessionDate: date,
                exerciseID: exerciseID,
                exerciseName: exerciseName,
                exerciseCatalogKey: exerciseCatalogKey,
                weight: weights[index],
                reps: reps[index],
                setOrderIndex: index
            )
        }
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

    func testGarminPhoneParserAcceptsBoundWorkoutMetrics() throws {
        let binding = GarminPhoneBinding(
            account: String(repeating: "a", count: 64),
            device: "11111111-2222-3333-4444-555555555555",
            pairingGeneration: String(repeating: "b", count: 64)
        )
        let message: [String: Any] = [
            "type": "create_workout",
            "bindingVersion": 2,
            "accountBinding": binding.account,
            "deviceBinding": binding.device,
            "pairingGeneration": binding.pairingGeneration,
            "requestId": "request-1234567890",
            "startedAtSeconds": 1_750_000_000,
            "sets": [
                ["exerciseName": "Bench Press", "weight": 100.5, "reps": 5],
                ["exerciseName": "Bench Press", "weight": 92.5, "reps": 8]
            ],
            "plannedSetCount": 3,
            "plannedTargetSetCount": 3,
            "completedPlannedSetCount": 1,
            "durationSeconds": 1_800,
            "gymCalories": 225.5,
            "garminCalories": 240,
            "avgHeartRate": 132,
            "maxHeartRate": 168,
            "heartRateZone": 3,
            "setMetrics": [
                [42, 90, 118, 154, 136, 18, 92],
                [NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull(), NSNull()]
            ],
            "setIntervals": [
                [0, 42, 4.5, 5, 0, 0, 12, 20, 10, 0],
                [132, 160, 3.0, NSNull(), 0, 0, 8, 15, 5, 0]
            ]
        ]

        let command = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(
                message,
                expectedBinding: binding,
                now: Date(timeIntervalSince1970: 1_750_001_000)
            )
        )

        XCTAssertEqual(command.requestID, "request-1234567890")
        XCTAssertEqual(command.sets, [
            NamedWorkoutSetDraft(exerciseName: "Bench Press", weight: 100.5, reps: 5),
            NamedWorkoutSetDraft(exerciseName: "Bench Press", weight: 92.5, reps: 8)
        ])
        XCTAssertEqual(command.plannedSetCount, 3)
        XCTAssertEqual(command.plannedTargetSetCount, 3)
        XCTAssertEqual(command.completedPlannedSetCount, 1)
        XCTAssertEqual(
            command.setStatistics,
            [
                GarminPhoneSetStatistics(
                    activeSeconds: 42,
                    restBeforeSeconds: 90,
                    startHeartRate: 118,
                    peakHeartRate: 154,
                    endHeartRate: 136,
                    recoveryHeartRateDrop: 18,
                    detectionConfidence: 92
                ),
                nil
            ]
        )
        XCTAssertEqual(
            command.setIntervals,
            [
                GarminPhoneSetInterval(
                    startSeconds: 0,
                    endSeconds: 42,
                    gymCalories: 4.5,
                    garminCalories: 5,
                    heartRateZoneSeconds: [0, 0, 12, 20, 10, 0]
                ),
                GarminPhoneSetInterval(
                    startSeconds: 132,
                    endSeconds: 160,
                    gymCalories: 3,
                    garminCalories: nil,
                    heartRateZoneSeconds: [0, 0, 8, 15, 5, 0]
                )
            ]
        )
        XCTAssertTrue(
            GarminPhoneSyncService.formattedWorkoutNote(command, language: "en")
                .contains("Completed 1/3 sets")
        )

        var legacyMessage = message
        legacyMessage.removeValue(forKey: "plannedSetCount")
        legacyMessage.removeValue(forKey: "plannedTargetSetCount")
        legacyMessage.removeValue(forKey: "completedPlannedSetCount")
        legacyMessage.removeValue(forKey: "setIntervals")
        let legacyCommand = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(
                legacyMessage,
                expectedBinding: binding,
                now: Date(timeIntervalSince1970: 1_750_001_000)
            )
        )
        XCTAssertEqual(command.digest, legacyCommand.digest)
        XCTAssertNil(legacyCommand.plannedSetCount)
        XCTAssertNil(legacyCommand.plannedTargetSetCount)
        XCTAssertNil(legacyCommand.completedPlannedSetCount)
        XCTAssertEqual(legacyCommand.setIntervals, [nil, nil])

        var resumedSegmentMessage = legacyMessage
        for key in [
            "durationSeconds",
            "gymCalories",
            "garminCalories",
            "avgHeartRate",
            "maxHeartRate",
            "heartRateZone"
        ] {
            resumedSegmentMessage.removeValue(forKey: key)
        }
        let resumedSegment = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(
                resumedSegmentMessage,
                expectedBinding: binding,
                now: Date(timeIntervalSince1970: 1_750_001_000)
            )
        )
        XCTAssertNil(resumedSegment.durationSeconds)
        XCTAssertNil(resumedSegment.gymCalories)
        XCTAssertNil(resumedSegment.garminCalories)
        XCTAssertNil(resumedSegment.averageHeartRate)
        XCTAssertNil(resumedSegment.maximumHeartRate)
        XCTAssertNil(resumedSegment.endingHeartRateZone)
    }

    func testGarminPhoneParserRejectsWrongBindingAndMalformedMetrics() {
        let binding = GarminPhoneBinding(
            account: String(repeating: "a", count: 64),
            device: "11111111-2222-3333-4444-555555555555",
            pairingGeneration: String(repeating: "b", count: 64)
        )
        var message: [String: Any] = [
            "type": "create_workout",
            "bindingVersion": 2,
            "accountBinding": binding.account,
            "deviceBinding": binding.device,
            "pairingGeneration": binding.pairingGeneration,
            "requestId": "request-1234567890",
            "sets": [
                ["exerciseName": "Squat", "weight": 120.0, "reps": 5]
            ],
            "setMetrics": [[35, 75, 110, 160, 140, 20, 95]]
        ]

        message["accountBinding"] = String(repeating: "c", count: 64)
        XCTAssertNil(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )

        message["accountBinding"] = binding.account
        message["pairingGeneration"] = String(repeating: "d", count: 64)
        XCTAssertNil(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )

        message["pairingGeneration"] = binding.pairingGeneration
        message["setMetrics"] = [[35, 75, 170, 160, 140, 20, 95]]
        XCTAssertNil(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )

        message["setMetrics"] = [[35, 75, 110, 160, 140, 20, Double.nan]]
        XCTAssertNil(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )

        message["setMetrics"] = [[35, 75, 110, 160, 140, 20, 95]]
        message["plannedSetCount"] = 0
        XCTAssertNil(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )

        message["plannedSetCount"] = 2
        message["setIntervals"] = [[0, 7_201, 1.0, 1, 0, 0, 0, 0, 0, 0]]
        XCTAssertNil(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )

        message["setIntervals"] = [[0, 10, 1.0, 1, 0, 0, 0, 0, 11, 0]]
        XCTAssertNil(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )

        message.removeValue(forKey: "setIntervals")
        message.removeValue(forKey: "plannedSetCount")
        message["completedPlannedSetCount"] = 0
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message["plannedSetCount"] = 1
        message["plannedTargetSetCount"] = 1
        message["completedPlannedSetCount"] = 2
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message["plannedSetCount"] = 3
        message["plannedTargetSetCount"] = 3
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message["completedPlannedSetCount"] = NSNull()
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))
    }

    func testGarminPendingReceiptRecoveryMatchesGroupedMixedExerciseWorkoutAcrossNoteVersions() throws {
        let binding = GarminPhoneBinding(
            account: String(repeating: "a", count: 64),
            device: "11111111-2222-3333-4444-555555555555",
            pairingGeneration: String(repeating: "b", count: 64)
        )
        let legacyMessage: [String: Any] = [
            "type": "create_workout",
            "bindingVersion": 2,
            "accountBinding": binding.account,
            "deviceBinding": binding.device,
            "pairingGeneration": binding.pairingGeneration,
            "requestId": "request-mixed-recovery-1234",
            "startedAtSeconds": 1_750_000_000,
            "sets": [
                ["exerciseName": "Bench Press", "weight": 100.0, "reps": 5],
                ["exerciseName": "Squat", "weight": 120.0, "reps": 5],
                ["exerciseName": "Bench Press", "weight": 92.5, "reps": 8],
                ["exerciseName": "Squat", "weight": 110.0, "reps": 7]
            ],
            "durationSeconds": 40,
            "gymCalories": 10.0,
            "garminCalories": 10
        ]
        let legacyCommand = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(
                legacyMessage,
                expectedBinding: binding,
                now: Date(timeIntervalSince1970: 1_750_001_000)
            )
        )
        var enrichedMessage = legacyMessage
        enrichedMessage["plannedSetCount"] = 5
        enrichedMessage["plannedTargetSetCount"] = 5
        enrichedMessage["completedPlannedSetCount"] = 4
        enrichedMessage["setIntervals"] = [
            [0, 10, 2.5, 2, 0, 0, 5, 5, 0, 0],
            [10, 20, 2.5, 2, 0, 0, 5, 5, 0, 0],
            [20, 30, 2.5, 2, 0, 0, 5, 5, 0, 0],
            [30, 40, 2.5, 2, 0, 0, 5, 5, 0, 0]
        ]
        let enrichedCommand = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(
                enrichedMessage,
                expectedBinding: binding,
                now: Date(timeIntervalSince1970: 1_750_001_000)
            )
        )
        XCTAssertEqual(legacyCommand.digest, enrichedCommand.digest)

        let store = try WorkoutStore(
            accountStorageKey: "garmin-pending-mixed",
            directoryURL: try temporaryDirectory(named: "garmin-pending-mixed")
        )
        let legacyLocalizedNote = GarminPhoneSyncService.formattedWorkoutNote(
            legacyCommand,
            language: "uk"
        )
        _ = try store.createWorkout(
            date: Date(timeIntervalSince1970: TimeInterval(legacyCommand.startedAtSeconds)),
            note: legacyLocalizedNote,
            namedSets: legacyCommand.sets
        )
        let persistedWorkout = try XCTUnwrap(store.workouts.first)
        let names = Dictionary(uniqueKeysWithValues: store.exercises.map { ($0.id, $0.name) })
        let persistedOrder = persistedWorkout.exercises.flatMap { block in
            block.sets.map { _ in names[block.exerciseID] ?? "" }
        }
        XCTAssertEqual(persistedOrder, ["Bench Press", "Bench Press", "Squat", "Squat"])
        XCTAssertNotEqual(
            legacyLocalizedNote,
            GarminPhoneSyncService.formattedWorkoutNote(enrichedCommand, language: "en")
        )

        XCTAssertTrue(
            GarminPhoneSyncService.matchesPersistedWorkout(enrichedCommand, in: store)
        )

        var conflictingMessage = enrichedMessage
        var conflictingSets = try XCTUnwrap(conflictingMessage["sets"] as? [[String: Any]])
        conflictingSets[2]["weight"] = 91.0
        conflictingMessage["sets"] = conflictingSets
        let conflictingCommand = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(
                conflictingMessage,
                expectedBinding: binding,
                now: Date(timeIntervalSince1970: 1_750_001_000)
            )
        )
        XCTAssertFalse(
            GarminPhoneSyncService.matchesPersistedWorkout(conflictingCommand, in: store)
        )
    }

    func testGarminPhoneExactTargetKeepsLegacyPlannedCountCompatibleWithExtraSets() throws {
        let binding = GarminPhoneBinding(
            account: String(repeating: "a", count: 64),
            device: "11111111-2222-3333-4444-555555555555",
            pairingGeneration: String(repeating: "b", count: 64)
        )
        var message: [String: Any] = [
            "type": "create_workout",
            "bindingVersion": 2,
            "accountBinding": binding.account,
            "deviceBinding": binding.device,
            "pairingGeneration": binding.pairingGeneration,
            "requestId": "request-legacy-plan-1",
            "sets": (0 ..< 4).map { index in
                ["exerciseName": "Squat", "weight": 120.0 - Double(index), "reps": 5]
            },
            "plannedSetCount": 4,
            "plannedTargetSetCount": 3,
            "completedPlannedSetCount": 2
        ]
        let command = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )
        XCTAssertEqual(command.plannedSetCount, 4)
        XCTAssertEqual(command.plannedTargetSetCount, 3)
        XCTAssertEqual(command.completedPlannedSetCount, 2)
        XCTAssertTrue(
            GarminPhoneSyncService.formattedWorkoutNote(command, language: "en")
                .contains("Completed 2/3 sets")
        )

        message.removeValue(forKey: "plannedTargetSetCount")
        message.removeValue(forKey: "completedPlannedSetCount")
        let legacyCommand = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )
        XCTAssertEqual(legacyCommand.plannedSetCount, 4)
        XCTAssertEqual(command.digest, legacyCommand.digest)
    }

    func testGarminPhoneParserEnforcesStructuredIntervalConsistency() throws {
        let binding = GarminPhoneBinding(
            account: String(repeating: "a", count: 64),
            device: "11111111-2222-3333-4444-555555555555",
            pairingGeneration: String(repeating: "b", count: 64)
        )
        var message: [String: Any] = [
            "type": "create_workout",
            "bindingVersion": 2,
            "accountBinding": binding.account,
            "deviceBinding": binding.device,
            "pairingGeneration": binding.pairingGeneration,
            "requestId": "request-interval-1234",
            "sets": [
                ["exerciseName": "Squat", "weight": 120.0, "reps": 5],
                ["exerciseName": "Squat", "weight": 110.0, "reps": 7]
            ],
            "plannedSetCount": 2,
            "plannedTargetSetCount": 1,
            "completedPlannedSetCount": 1,
            "durationSeconds": 50,
            "gymCalories": 9.91,
            "garminCalories": 10,
            "setIntervals": [
                [0, 42, 5.0, 5, 0, 0, 12, 20, 10, 0],
                [42, 50, 5.0, 5, 0, 0, 0, 8, 0, 0]
            ]
        ]

        XCTAssertNotNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))
        var zeroCompletedMessage = message
        zeroCompletedMessage["plannedSetCount"] = 3
        zeroCompletedMessage["plannedTargetSetCount"] = 3
        zeroCompletedMessage["completedPlannedSetCount"] = 0
        let zeroCompletedCommand = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(zeroCompletedMessage, expectedBinding: binding)
        )
        XCTAssertTrue(
            GarminPhoneSyncService.formattedWorkoutNote(
                zeroCompletedCommand,
                language: "en"
            ).contains("Completed 0/3 sets")
        )

        message["setIntervals"] = [
            [0, 42, 5.0, 5, 0, 0, 12, 20, 10, 0],
            [41, 50, 5.0, 5, 0, 0, 0, 8, 0, 0]
        ]
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message["setIntervals"] = [
            [0, 42, 5.0, 5, 0, 0, 12, 20, 10, 0],
            [42, 51, 5.0, 5, 0, 0, 0, 8, 0, 0]
        ]
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message["setIntervals"] = [
            [0, 42, 5.0, 5, 0, 0, 12, 20, 10, 0],
            [42, 50, 5.0, 5, 0, 0, 0, 8, 0, 0]
        ]
        message.removeValue(forKey: "durationSeconds")
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))
        message["durationSeconds"] = 50

        message["setIntervals"] = [
            [0, 42, 5.0, 5, 0, 0, 12, 20, 10, 0],
            [42, 50, 5.0, NSNull(), 0, 0, 0, 8, 0, 0]
        ]
        message["gymCalories"] = 9.89
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message.removeValue(forKey: "gymCalories")
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message["gymCalories"] = 10.0
        message.removeValue(forKey: "garminCalories")
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message["setIntervals"] = [
            [0, 42, 5.0, NSNull(), 0, 0, 12, 20, 10, 0],
            [42, 50, 5.0, NSNull(), 0, 0, 0, 8, 0, 0]
        ]
        XCTAssertNotNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))

        message["setIntervals"] = [
            [0, 42, 5.0, 5, 0, 0, 12, 20, 10, 0],
            [42, 50, 5.0, 5, 0, 0, 0, 8, 0, 0]
        ]
        message["garminCalories"] = 9
        XCTAssertNil(GarminPhoneWorkoutParser.parse(message, expectedBinding: binding))
    }

    func testGarminPhoneMaximumMetricNoteStaysImportableAndMarksOmittedRows() throws {
        let binding = GarminPhoneBinding(
            account: String(repeating: "a", count: 64),
            device: "11111111-2222-3333-4444-555555555555",
            pairingGeneration: String(repeating: "b", count: 64)
        )
        let message: [String: Any] = [
            "type": "create_workout",
            "bindingVersion": 2,
            "accountBinding": binding.account,
            "deviceBinding": binding.device,
            "pairingGeneration": binding.pairingGeneration,
            "requestId": "request-max-note-1234",
            "sets": Array(
                repeating: ["exerciseName": "Bench Press", "weight": 100.5, "reps": 5],
                count: 60
            ),
            "plannedSetCount": 60,
            "durationSeconds": 432_000,
            "gymCalories": 100_000.0,
            "garminCalories": 100_000,
            "setMetrics": Array(
                repeating: [7200, 86400, 240, 240, 240, 240, 100],
                count: 60
            ),
            "setIntervals": (0 ..< 60).map { index in
                [
                    index * 7_200,
                    (index + 1) * 7_200,
                    1_666.66,
                    1_666,
                    1_200,
                    1_200,
                    1_200,
                    1_200,
                    1_200,
                    1_200
                ] as [Any]
            }
        ]
        let command = try XCTUnwrap(
            GarminPhoneWorkoutParser.parse(message, expectedBinding: binding)
        )

        let note = GarminPhoneSyncService.formattedWorkoutNote(command, language: "en")

        XCTAssertLessThanOrEqual(note.count, 4_000)
        XCTAssertLessThanOrEqual(note.utf8.count, 16_000)
        XCTAssertNotNil(note.range(of: #"S\+[1-9][0-9]*"#, options: .regularExpression))
        XCTAssertNotNil(GarminWorkoutNoteParser.parse(note)?.omittedMetricRows)
    }

    func testGarminWorkoutNoteParserReadsPartialIntervalsAndRejectsInvalidSlices() throws {
        let summary = try XCTUnwrap(
            GarminWorkoutNoteParser.parse(
                "Garmin · Частично 2/3 подходов · " +
                    "S1 42s I0-42s K4.5/5 Z0/0/12/20/10/0s · " +
                    "S2 I132-160s K3/- Z0/0/8/15/5/0s"
            )
        )

        XCTAssertEqual(summary.completedSetCount, 2)
        XCTAssertEqual(summary.plannedSetCount, 3)
        XCTAssertNil(summary.omittedMetricRows)
        XCTAssertEqual(
            summary.intervals,
            [
                GarminWorkoutNoteInterval(
                    setIndex: 1,
                    startSeconds: 0,
                    endSeconds: 42,
                    gymCalories: 4.5,
                    garminCalories: 5,
                    heartRateZoneSeconds: [0, 0, 12, 20, 10, 0]
                ),
                GarminWorkoutNoteInterval(
                    setIndex: 2,
                    startSeconds: 132,
                    endSeconds: 160,
                    gymCalories: 3,
                    garminCalories: nil,
                    heartRateZoneSeconds: [0, 0, 8, 15, 5, 0]
                )
            ]
        )
        XCTAssertNil(
            GarminWorkoutNoteParser.parse(
                "Garmin · S1 I0-10s K1/1 Z0/0/0/0/11/0s"
            )
        )
        XCTAssertNil(
            GarminWorkoutNoteParser.parse(
                "Garmin · S1 I0-7201s K1/1 Z0/0/0/0/0/0s"
            )
        )
        XCTAssertNil(
            GarminWorkoutNoteParser.parse(
                "Garmin · " + String(repeating: "x", count: 4_000)
            )
        )
        XCTAssertEqual(
            GarminWorkoutNoteParser.parse(
                "Garmin · S1 I0-10s K1/1 Z0/0/0/0/10/0s · S+2"
            )?.omittedMetricRows,
            2
        )
        XCTAssertNil(GarminWorkoutNoteParser.parse("Garmin · S+0"))
        XCTAssertNil(GarminWorkoutNoteParser.parse("Garmin · S+61"))
        XCTAssertNil(GarminWorkoutNoteParser.parse("Garmin · S+1 · S+2"))
        XCTAssertNil(
            GarminWorkoutNoteParser.parse(
                "Garmin · Duration 0:20 · " +
                    "S1 I0-10s K1/1 Z0/0/0/0/10/0s · " +
                    "S2 I9-15s K1/1 Z0/0/0/0/6/0s"
            )
        )
        XCTAssertNil(
            GarminWorkoutNoteParser.parse(
                "Garmin · Duration 0:20 · " +
                    "S1 I10-15s K1/1 Z0/0/0/0/5/0s · " +
                    "S2 I0-5s K1/1 Z0/0/0/0/5/0s"
            )
        )
        XCTAssertNil(
            GarminWorkoutNoteParser.parse(
                "Garmin · Duration 0:20 · S1 I0-21s K1/1 Z0/0/0/0/21/0s"
            )
        )
        XCTAssertNil(
            GarminWorkoutNoteParser.parse(
                "Garmin · Duration 0:20 · " +
                    "S2 I0-5s K1/1 Z0/0/0/0/5/0s · " +
                    "S1 I5-10s K1/1 Z0/0/0/0/5/0s"
            )
        )
        XCTAssertEqual(
            GarminWorkoutNoteParser.parse("Garmin · Completed 0/3 sets")?.completedSetCount,
            0
        )
    }

    func testGarminWorkoutDetailCopyIdentifiesChronologicalWatchSetOrderInEveryLanguage() {
        XCTAssertEqual(
            GarminWorkoutDetailCopy.intervalsTitle(languageCode: "en"),
            "Chronological watch sets"
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.intervalsTitle(languageCode: "uk"),
            "Хронологічні підходи з годинника"
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.intervalsTitle(languageCode: "ru"),
            "Хронологические подходы с часов"
        )
        XCTAssertTrue(
            GarminWorkoutDetailCopy.intervalsSupporting(languageCode: "en")
                .contains("may differ from exercise-grouped set order")
        )
        XCTAssertTrue(
            GarminWorkoutDetailCopy.intervalsSupporting(languageCode: "uk")
                .contains("може відрізнятися")
        )
        XCTAssertTrue(
            GarminWorkoutDetailCopy.intervalsSupporting(languageCode: "ru")
                .contains("может отличаться")
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.originalPartial(
                completed: 0,
                planned: 3,
                languageCode: "ru"
            ),
            "Исходный результат Garmin: выполнено 0 из 3 запланированных подходов."
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.intervalLabel(
                setIndex: 2,
                startSeconds: 42,
                endSeconds: 50,
                languageCode: "ru"
            ),
            "Подход с часов S2 · 42–50с"
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.intervalLabel(
                setIndex: 2,
                startSeconds: 42,
                endSeconds: 50,
                languageCode: "en"
            ),
            "Watch set S2 · 42–50s"
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.intervalLabel(
                setIndex: 2,
                startSeconds: 42,
                endSeconds: 50,
                languageCode: "uk"
            ),
            "Підхід з годинника S2 · 42–50с"
        )
        XCTAssertEqual(
            GarminWorkoutDetailCopy.noTimedHeartRateZone(languageCode: "ru"),
            "Нет зафиксированного времени в пульсовых зонах"
        )
        XCTAssertEqual(GarminWorkoutDetailCopy.calorieUnit(languageCode: "ru"), "ккал")
        XCTAssertEqual(GarminWorkoutDetailCopy.secondsUnit(languageCode: "ru"), "с")
    }

    func testGarminPhoneRequestTypeAndAccountCleanupAreBounded() {
        XCTAssertEqual(
            GarminPhoneWorkoutParser.messageType(["type": "request_sync"]),
            "request_sync"
        )

        let defaults = temporaryDefaults(named: "garmin-phone-cleanup")
        let storageKey = "cloud_00000000-0000-0000-0000-000000000001"
        let digest = SHA256.hash(data: Data(storageKey.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let indexKey = "garmin-phone-state-index.v1.\(digest)"
        let deviceKey = "garmin-phone-devices.v1.\(digest)"
        let ownedStateKey = "garmin-phone-receipts.v1.owned"
        let unrelatedKey = "unrelated-setting"
        defaults.set([ownedStateKey, unrelatedKey], forKey: indexKey)
        defaults.set(Data([1, 2, 3]), forKey: deviceKey)
        defaults.set(Data([4, 5, 6]), forKey: ownedStateKey)
        defaults.set("keep", forKey: unrelatedKey)

        GarminPhoneSyncService.clearStoredData(
            defaults: defaults,
            storageKey: storageKey
        )

        XCTAssertNil(defaults.object(forKey: indexKey))
        XCTAssertNil(defaults.object(forKey: deviceKey))
        XCTAssertNil(defaults.object(forKey: ownedStateKey))
        XCTAssertEqual(defaults.string(forKey: unrelatedKey), "keep")
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

    private func customExerciseNames(in store: WorkoutStore) -> [String] {
        store.exercises.filter { exercise in
            BuiltInExerciseCatalog.resolvedKey(
                catalogKey: exercise.catalogKey,
                name: exercise.name
            ) == nil
        }.map(\.name)
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
    var accountsThatFailSave = Set<String>()
    var accountsThatFailDeletion = Set<String>()

    var allData: [Data] {
        lock.withLock { Array(values.values) }
    }

    func save(_ data: Data, account: String) throws {
        try lock.withLock {
            if accountsThatFailSave.contains(account) {
                throw NSError(domain: "GymAppTests.KeychainSave", code: 1)
            }
            values[account] = data
        }
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
