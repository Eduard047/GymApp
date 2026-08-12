import Foundation
import XCTest
@testable import GymApp

@MainActor
final class SharedWorkoutLinkTests: XCTestCase {
    private let goldenPayload =
        "eyJ2IjoxLCJlIjpbWyJsYXRfcHVsbGRvd24iLCJMYXQgUHVsbGRvd24iLFtbNTAsOF0sWzUyLjUsN11dXSxbIiIsIk15IEN1c3RvbSIsW1swLDEyXV1dXX0"

    func testPWACompactVectorDecodesFromCanonicalAndCustomDestinations() throws {
        let canonical = try XCTUnwrap(
            URL(string: "https://gymapptracker.com/workout/#workout=\(goldenPayload)")
        )
        let custom = try XCTUnwrap(
            URL(string: "com.setforge.gymapp.ios://workout/#workout=\(goldenPayload)")
        )

        let plan = try SharedWorkoutLinkDecoder.decode(canonical)
        XCTAssertEqual(try SharedWorkoutLinkDecoder.decode(custom), plan)
        XCTAssertEqual(plan.exercises.count, 2)
        XCTAssertEqual(plan.totalSetCount, 3)
        XCTAssertEqual(plan.exercises[0].catalogKey, "lat_pulldown")
        XCTAssertEqual(plan.exercises[0].sets[1].weight, 52.5)
        XCTAssertEqual(plan.exercises[1].name, "My Custom")
        XCTAssertNil(plan.exercises[1].catalogKey)
    }

    func testEncoderUsesAppLinkPathAndWebsiteFallbackStaysAtRoot() throws {
        let exerciseID = UUID()
        let workout = WorkoutSession(
            date: Date(),
            exercises: [
                WorkoutExercise(
                    exerciseID: exerciseID,
                    sets: [WorkoutSet(weight: 40, reps: 8)]
                )
            ]
        )
        let appLink = try SharedWorkoutLinkEncoder.makeURL(
            workout: workout,
            exercises: [exerciseID: Exercise(name: "Bench Press")]
        )
        let plan = try SharedWorkoutLinkDecoder.decode(appLink)
        let websiteLink = try SharedWorkoutLinkEncoder.makeWebsiteURL(plan: plan)

        XCTAssertEqual(appLink.absoluteString.split(separator: "#").first, "https://gymapptracker.com/workout/")
        XCTAssertEqual(websiteLink.absoluteString.split(separator: "#").first, "https://gymapptracker.com/")
        XCTAssertThrowsError(try SharedWorkoutLinkDecoder.decode(websiteLink))
        XCTAssertEqual(
            try SharedWorkoutLinkDecoder.decode(websiteLink, allowLegacyHTTPSRoot: true),
            plan
        )
    }

    func testEditorDraftEncoderUsesCurrentV1PlanAndExcludesExerciseMetadata() throws {
        let exerciseID = UUID()
        let loadProfile = try MachineLoadProfile(
            direction: .higherIsHarder,
            allowedWeightsKg: [20, 30, 40]
        )
        let exercise = Exercise(
            id: exerciseID,
            name: "Bench Press",
            machineLoadProfile: loadProfile,
            isFavorite: true
        )
        let drafts = [
            WorkoutEditorExerciseDraft(
                exerciseID: exerciseID,
                sets: [
                    WorkoutEditorSetDraft(weight: 72.5, reps: 8),
                    WorkoutEditorSetDraft(weight: 75, reps: 6)
                ]
            )
        ]

        let url = try makeSharedWorkoutDraftURL(
            drafts: drafts,
            exercises: [exerciseID: exercise]
        )
        let plan = try SharedWorkoutLinkDecoder.decode(url)
        let payload = try decodedPayload(from: url)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )

        XCTAssertEqual(url.absoluteString.split(separator: "#").first, "https://gymapptracker.com/workout/")
        XCTAssertEqual(Set(root.keys), Set(["v", "e"]))
        XCTAssertEqual((root["v"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(plan.exercises.count, 1)
        XCTAssertEqual(plan.exercises[0].sets.map(\.weight), [72.5, 75])
        XCTAssertEqual(plan.exercises[0].sets.map(\.repetitions), [8, 6])
        XCTAssertNil(payload.range(of: Data(exerciseID.uuidString.utf8)))
        XCTAssertNil(payload.range(of: Data("allowedWeightsKg".utf8)))
        XCTAssertNil(payload.range(of: Data("isFavorite".utf8)))
    }

    func testEditorDraftEncoderAcceptsZeroAndRejectsInvalidWeight() throws {
        let exerciseID = UUID()
        let zeroDraft = WorkoutEditorExerciseDraft(
            exerciseID: exerciseID,
            sets: [
                WorkoutEditorSetDraft(
                    weight: 0,
                    reps: 10
                )
            ]
        )
        let exercise = Exercise(id: exerciseID, name: "Bench Press")
        let zeroPlan = try makeSharedWorkoutDraftPlan(
            drafts: [zeroDraft],
            exercises: [exerciseID: exercise]
        )
        XCTAssertEqual(zeroPlan.exercises[0].sets[0].weight, 0)

        var invalidDraft = zeroDraft
        invalidDraft.sets[0].weight = -1

        XCTAssertThrowsError(
            try makeSharedWorkoutDraftURL(
                drafts: [invalidDraft],
                exercises: [exerciseID: exercise]
            )
        ) { error in
            XCTAssertEqual(error as? SharedWorkoutLinkError, .invalidWeight)
        }
    }

    func testDecoderRejectsNonCanonicalRoutesAndFragments() throws {
        let invalidURLs = [
            "http://gymapptracker.com/workout/#workout=\(goldenPayload)",
            "https://gymapptracker.com.evil.test/workout/#workout=\(goldenPayload)",
            "https://user@gymapptracker.com/workout/#workout=\(goldenPayload)",
            "https://gymapptracker.com:444/workout/#workout=\(goldenPayload)",
            "https://gymapptracker.com/workout/?source=test#workout=\(goldenPayload)",
            "https://gymapptracker.com/workout#workout=\(goldenPayload)",
            "https://gymapptracker.com/workout/#workout=\(goldenPayload)&next=private",
            "https://gymapptracker.com/workout/#workout=\(goldenPayload)&workout=\(goldenPayload)",
            "https://gymapptracker.com/workout/#workout%3D\(goldenPayload)",
            "https://%67ymapptracker.com/workout/#workout=\(goldenPayload)",
            "https://gymapptracker.com/%77orkout/#workout=\(goldenPayload)",
            "com.setforge.gymapp.ios://%77orkout/#workout=\(goldenPayload)",
            "com.setforge.gymapp.ios://workout/import#workout=\(goldenPayload)",
            "com.setforge.gymapp.ios://other/#workout=\(goldenPayload)"
        ]

        for rawURL in invalidURLs {
            let url = try XCTUnwrap(URL(string: rawURL), rawURL)
            XCTAssertThrowsError(try SharedWorkoutLinkDecoder.decode(url), rawURL)
        }
    }

    func testStrictDecoderRejectsMalformedPrivateAndDuplicateJSON() throws {
        let rejectedJSON = [
            "{\"v\":1,\"v\":1,\"e\":[]}",
            "{\"v\":1,\"e\":[],\"owner\":\"private\"}",
            "{\"v\":true,\"e\":[]}",
            "{\"v\":1,\"e\":[[\"\",\"Exercise\",[[10,8]],\"extra\"]]}",
            "{\"v\":1,\"e\":[[\"\",\"Exercise\",[[10,8,1]]]]}",
            "{\"v\":1,\"e\":[[\"../private\",\"Exercise\",[[10,8]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Bad\\u202ename\",[[10,8]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Bad\\u0080name\",[[10,8]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Bad\\u009fname\",[[10,8]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Bad\\u200bname\",[[10,8]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Bad\\u2060name\",[[10,8]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Bad\\ufeffname\",[[10,8]]]]}",
            "{\"v\":1,\"e\":[[\"\",\"Exercise\",[[10,true]]]]}"
        ]

        for json in rejectedJSON {
            XCTAssertThrowsError(
                try SharedWorkoutLinkDecoder.decode(try canonicalURL(json: json)),
                json
            )
        }

        let unsupported = try canonicalURL(
            json: "{\"v\":2,\"e\":[[\"\",\"Exercise\",[[10,8]]]]}"
        )
        XCTAssertThrowsError(try SharedWorkoutLinkDecoder.decode(unsupported)) { error in
            XCTAssertEqual(error as? SharedWorkoutLinkError, .unsupportedVersion)
        }
    }

    func testDecoderRejectsDuplicatePortableExerciseIdentities() throws {
        let duplicateBuiltIn = try canonicalURL(
            json: "{\"v\":1,\"e\":[[\"bench_press\",\"Bench Press\",[[10,8]]],[\"\",\"Жим штанги лежачи\",[[12,8]]]]}"
        )
        let duplicateCustom = try canonicalURL(
            json: "{\"v\":1,\"e\":[[\"\",\"My Machine\",[[10,8]]],[\"future_key\",\"my machine\",[[12,8]]]]}"
        )

        for url in [duplicateBuiltIn, duplicateCustom] {
            XCTAssertThrowsError(try SharedWorkoutLinkDecoder.decode(url)) { error in
                XCTAssertEqual(error as? SharedWorkoutLinkError, .duplicateExercise)
            }
        }
    }

    func testUnknownCatalogKeyIsForwardedButNeverTrustedForLocalIdentity() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkoutStore(
            accountStorageKey: "shared-link-unknown-key",
            directoryURL: directory
        )
        let plan = try SharedWorkoutLinkDecoder.decode(
            try canonicalURL(
                json: "{\"v\":1,\"e\":[[\"future_machine_v2\",\"Custom Future Machine\",[[25,10]]]]}"
            )
        )

        XCTAssertEqual(plan.exercises[0].catalogKey, "future_machine_v2")
        XCTAssertTrue(store.exercises.isEmpty)
        let drafts = try store.materializeSharedWorkoutDraft(plan)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(store.exercises.count, 1)
        XCTAssertEqual(store.exercises[0].name, "Custom Future Machine")
        XCTAssertNil(store.exercises[0].catalogKey)
        XCTAssertTrue(store.workouts.isEmpty)
    }

    func testMaterializationOccursOnlyAfterConfirmationAndIsAtomic() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkoutStore(
            accountStorageKey: "shared-link-materialize",
            directoryURL: directory
        )
        let plan = try SharedWorkoutLinkDecoder.decode(
            try canonicalURL(
                json: "{\"v\":1,\"e\":[[\"bench_press\",\"Bench Press\",[[50,8],[52.5,7]]],[\"\",\"Cable Rotation Custom\",[[10,12]]]]}"
            )
        )

        XCTAssertTrue(store.exercises.isEmpty, "Decoding and preview must not mutate storage.")
        XCTAssertTrue(store.workouts.isEmpty)

        let drafts = try store.materializeSharedWorkoutDraft(plan)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].sets.map(\.reps), [8, 7])
        XCTAssertEqual(store.exercises.count, 2)
        XCTAssertTrue(store.workouts.isEmpty, "Confirmation creates only an editable draft.")

        let invalidPlan = SharedWorkoutPlan(
            exercises: [
                SharedWorkoutPlanExercise(
                    catalogKey: nil,
                    name: "Must Not Persist",
                    sets: [SharedWorkoutPlanSet(weight: 10, repetitions: 8)]
                ),
                SharedWorkoutPlanExercise(
                    catalogKey: nil,
                    name: "Invalid Later Block",
                    sets: [SharedWorkoutPlanSet(weight: .nan, repetitions: 8)]
                )
            ]
        )
        let countBeforeFailure = store.exercises.count
        XCTAssertThrowsError(try store.materializeSharedWorkoutDraft(invalidPlan))
        XCTAssertEqual(store.exercises.count, countBeforeFailure)
        XCTAssertNil(store.exercise(named: "Must Not Persist"))
    }

    func testAppStateConsumesMalformedShareRoutesAndDoesNotReplacePendingPreview() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "SharedWorkoutLinkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = SharedWorkoutTestKeychain()
        let auth = AuthService(keychain: keychain, defaults: defaults)
        let appState = try AppState(
            auth: auth,
            defaults: defaults,
            workoutDirectoryURL: directory,
            garminBindingStore: GarminDeviceBindingStore(keychain: keychain)
        )
        let firstURL = try canonicalURL(
            json: "{\"v\":1,\"e\":[[\"\",\"First Custom\",[[10,8]]]]}"
        )
        let secondURL = try canonicalURL(
            json: "{\"v\":1,\"e\":[[\"\",\"Second Custom\",[[12,8]]]]}"
        )

        XCTAssertTrue(appState.handleSharedWorkoutURL(firstURL))
        let firstPending = try XCTUnwrap(appState.pendingSharedWorkout)
        XCTAssertTrue(appState.handleSharedWorkoutURL(secondURL))
        XCTAssertEqual(appState.pendingSharedWorkout?.id, firstPending.id)
        XCTAssertEqual(appState.pendingSharedWorkout?.plan, firstPending.plan)

        let replacementPlan = try SharedWorkoutLinkDecoder.decode(secondURL)
        try appState.stageSharedWorkoutPlan(
            replacementPlan,
            replacingPendingID: firstPending.id
        )
        let replacedPending = try XCTUnwrap(appState.pendingSharedWorkout)
        XCTAssertNotEqual(replacedPending.id, firstPending.id)
        XCTAssertEqual(replacedPending.plan, replacementPlan)

        XCTAssertThrowsError(
            try appState.stageSharedWorkoutPlan(
                firstPending.plan,
                replacingPendingID: UUID()
            )
        )
        XCTAssertEqual(appState.pendingSharedWorkout?.id, replacedPending.id)
        XCTAssertEqual(appState.pendingSharedWorkout?.plan, replacementPlan)

        let malformed = try XCTUnwrap(
            URL(string: "https://gymapptracker.com/workout/#workout=not+base64")
        )
        XCTAssertTrue(appState.handleSharedWorkoutURL(malformed))
        XCTAssertEqual(appState.pendingSharedWorkout?.id, replacedPending.id)

        let malformedNamespaceURLs = [
            "com.setforge.gymapp.ios://workout/import#workout=\(goldenPayload)",
            "com.setforge.gymapp.ios://workout/?source=test#workout=\(goldenPayload)",
            "https://gymapptracker.com/workout/import#workout=\(goldenPayload)"
        ]
        for rawURL in malformedNamespaceURLs {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertTrue(SharedWorkoutLinkDecoder.isRecognizedDestination(url), rawURL)
            XCTAssertTrue(appState.handleSharedWorkoutURL(url), rawURL)
            XCTAssertEqual(appState.pendingSharedWorkout?.id, replacedPending.id, rawURL)
        }

        let authURL = try XCTUnwrap(URL(string: "com.setforge.gymapp.ios://auth/callback?code=test"))
        XCTAssertFalse(appState.handleSharedWorkoutURL(authURL))
        appState.dismissPendingSharedWorkout(id: replacedPending.id)
        XCTAssertNil(appState.pendingSharedWorkout)
    }

    private func canonicalURL(json: String) throws -> URL {
        let encoded = Data(json.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=+$", with: "", options: .regularExpression)
        return try XCTUnwrap(
            URL(string: "https://gymapptracker.com/workout/#workout=\(encoded)")
        )
    }

    private func decodedPayload(from url: URL) throws -> Data {
        let fragment = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
        )
        XCTAssertTrue(fragment.hasPrefix("workout="))
        var base64 = String(fragment.dropFirst("workout=".count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return try XCTUnwrap(Data(base64Encoded: base64))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymAppSharedWorkoutTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class SharedWorkoutTestKeychain: KeychainStoring {
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws {
        values[account] = data
    }

    func read(account: String) throws -> Data? {
        values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }
}
