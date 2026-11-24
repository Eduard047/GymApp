import XCTest
@testable import GymApp

/// Runs the Apple Health cases of shared/health-import-v1.json (the same contract the
/// Android Health Connect suite runs) and checks the import service's ledger and binding.
@MainActor
final class HealthImportRulesTests: XCTestCase {
    // MARK: Golden contract

    func testContractConstantsMatchRules() throws {
        let contract = try loadContract()
        XCTAssertEqual(contract["windowDays"] as? Int, HealthImportRules.windowDays)
        XCTAssertEqual(contract["maxSessionsPerRun"] as? Int, HealthImportRules.maxSessionsPerRun)
        XCTAssertEqual(
            contract["maxRecordsScannedPerRun"] as? Int, HealthImportRules.maxRecordsScannedPerRun
        )
        XCTAssertEqual(contract["minDurationSeconds"] as? Int, HealthImportRules.minDurationSeconds)
        XCTAssertEqual(contract["maxDurationSeconds"] as? Int, HealthImportRules.maxDurationSeconds)
        XCTAssertEqual(
            contract["overlapToleranceSeconds"] as? Int, HealthImportRules.overlapToleranceSeconds
        )
        XCTAssertEqual(
            contract["minAutoImportIntervalSeconds"] as? Int,
            HealthImportRules.minAutoImportIntervalSeconds
        )
        XCTAssertEqual(contract["noteSeparator"] as? String, HealthImportRules.noteSeparator)
        let stores = try XCTUnwrap(contract["stores"] as? [String: Any])
        let kit = try XCTUnwrap(stores["healthKit"] as? [String: Any])
        XCTAssertEqual(kit["receiptKeyPrefix"] as? String, HealthImportRules.receiptKeyPrefix)
        XCTAssertEqual(kit["notePrefix"] as? String, HealthImportRules.notePrefix)
        XCTAssertEqual(kit["ownSourceIds"] as? [String], HealthImportRules.ownSourceIds)
        XCTAssertEqual(
            Set(kit["gymExerciseTypes"] as? [String] ?? []), HealthImportRules.gymExerciseTypes
        )
        let labels = try XCTUnwrap(kit["typeLabels"] as? [String: [String: String]])
        for type in HealthImportRules.gymExerciseTypes {
            for language in ["en", "uk", "ru"] {
                XCTAssertEqual(
                    HealthImportRules.typeLabel(type, language: language),
                    labels[type]?[language],
                    "\(type) \(language)"
                )
            }
        }
    }

    func testEveryAppleHealthGoldenCase() throws {
        let contract = try loadContract()
        let cases = try XCTUnwrap(contract["cases"] as? [[String: Any]])
        var ran = 0
        for item in cases where item["store"] as? String == "healthKit" {
            let id = try XCTUnwrap(item["id"] as? String)
            let language = try XCTUnwrap(item["language"] as? String)
            let session = try parseSession(try XCTUnwrap(item["session"] as? [String: Any]))
            let existing = (item["existingWorkouts"] as? [[String: Any]] ?? []).map {
                HealthImportExistingWorkout(
                    startMillis: ($0["startMillis"] as? NSNumber)?.int64Value ?? 0,
                    durationSeconds: ($0["durationSeconds"] as? NSNumber)?.intValue
                )
            }
            let receipts = Set(item["receipts"] as? [String] ?? [])
            let nowMillis = (item["nowMillis"] as? NSNumber)?.int64Value ?? Int64.max
            let expected = try XCTUnwrap(item["expected"] as? [String: Any])
            let outcome = HealthImportRules.evaluate(
                session,
                existingWorkouts: existing,
                receipts: receipts,
                languageCode: language,
                nowMillis: nowMillis
            )
            let name = try XCTUnwrap(expected["outcome"] as? String)
            if name == "imported" {
                guard case let .imported(key, workout) = outcome else {
                    XCTFail("\(id): expected import, got \(outcome)")
                    continue
                }
                let stored = try XCTUnwrap(expected["workout"] as? [String: Any])
                XCTAssertEqual(key, expected["receiptKey"] as? String, id)
                XCTAssertEqual(workout.workoutStartedAt, (stored["workoutStartedAt"] as? NSNumber)?.int64Value, id)
                XCTAssertEqual(workout.durationSeconds, stored["durationSeconds"] as? Int, id)
                XCTAssertEqual(workout.gymCalories, stored["gymCalories"] as? Int, id)
                XCTAssertEqual(workout.averageHeartRate, stored["averageHeartRate"] as? Int, id)
                XCTAssertEqual(workout.maximumHeartRate, stored["maximumHeartRate"] as? Int, id)
                XCTAssertEqual(workout.note, stored["note"] as? String, id)
            } else {
                let reasonName = String(name.dropFirst("skipped:".count))
                let reason = HealthImportSkipReason(rawValue: reasonName)
                XCTAssertNotNil(reason, "\(id): unknown reason \(reasonName)")
                XCTAssertEqual(outcome, .skipped(try XCTUnwrap(reason)), id)
            }
            ran += 1
        }
        XCTAssertGreaterThanOrEqual(ran, 10)
    }

    func testInvalidRecordAndInProgressRules() {
        let base = HealthImportSession(
            recordId: "ok",
            startMillis: 1_750_000_000_000,
            endMillis: 1_750_000_600_000,
            exerciseType: "coreTraining",
            sourceId: "com.example.watch",
            kilocalories: nil,
            heartRateSamples: []
        )
        func reason(_ session: HealthImportSession, now: Int64 = .max) -> HealthImportSkipReason? {
            HealthImportRules.skipReason(
                for: session, existingWorkouts: [], receipts: [], nowMillis: now
            )
        }
        XCTAssertNil(reason(base))
        XCTAssertNil(reason(HealthImportSession(
            recordId: String(repeating: "a", count: 243), startMillis: base.startMillis,
            endMillis: base.endMillis, exerciseType: base.exerciseType, sourceId: base.sourceId,
            kilocalories: nil, heartRateSamples: []
        )))
        for bad in ["", String(repeating: "a", count: 244), "a\nb", "a\u{85}b"] {
            let invalid = HealthImportSession(
                recordId: bad, startMillis: base.startMillis, endMillis: base.endMillis,
                exerciseType: base.exerciseType, sourceId: "com.setforge.gymapp.ios",
                kilocalories: nil, heartRateSamples: []
            )
            // Checked before every other rule, including the own-app check.
            XCTAssertEqual(reason(invalid), .invalidRecord)
        }
        XCTAssertEqual(reason(base, now: base.endMillis - 1), .inProgress)
        XCTAssertNil(reason(base, now: base.endMillis))
    }

    func testOwnSourceCoversDevelopmentVariants() {
        XCTAssertTrue(HealthImportRules.isOwnSource("com.setforge.gymapp.ios"))
        XCTAssertTrue(HealthImportRules.isOwnSource("com.setforge.gymapp.ios.dev"))
        XCTAssertFalse(HealthImportRules.isOwnSource("com.setforge.gymapp.iosx"))
        XCTAssertFalse(HealthImportRules.isOwnSource("com.garmin.connect.mobile"))
    }

    func testCapsReportTruncatedAndKeepNewestFirst() {
        let sessions = (0 ..< 205).map { index in
            HealthImportSession(
                recordId: "r\(index)",
                startMillis: 1_750_000_000_000 + Int64(index) * 10_000_000,
                endMillis: 1_750_000_000_000 + Int64(index) * 10_000_000 + 600_000,
                exerciseType: "coreTraining",
                sourceId: "com.example.watch",
                kilocalories: nil,
                heartRateSamples: []
            )
        }
        let plan = HealthImportRules.plan(
            sessions: sessions, existingWorkouts: [], receipts: [], languageCode: "en"
        )
        XCTAssertEqual(plan.imported.count, 200)
        XCTAssertEqual(plan.truncated, 5)
        XCTAssertEqual(plan.imported.first?.receiptKey, "apple_health:r204")
        XCTAssertNil(plan.skipped[.overlap])
    }

    // MARK: Note wording and reading

    func testNoteWritesTheNumberBeforeTheUnitAndHoursFromOneHourOn() {
        func note(_ seconds: Int, _ language: String) -> String {
            HealthImportRules.buildNote(
                type: "coreTraining",
                durationSeconds: seconds,
                gymCalories: 356,
                averageHeartRate: 124,
                maximumHeartRate: 158,
                languageCode: language
            )
        }
        XCTAssertEqual(
            note(2_825, "en"),
            "Apple Health · Core training · Duration 47:05 · 356 kcal · Avg HR 124 · Max HR 158"
        )
        XCTAssertEqual(
            note(5_700, "uk"),
            "Apple Health · Тренування м’язів кора · Тривалість 1:35:00 · 356 ккал · " +
                "Середній пульс 124 · Макс. пульс 158"
        )
        XCTAssertEqual(
            note(7_530, "ru"),
            "Apple Health · Тренировка мышц кора · Длительность 2:05:30 · 356 ккал · " +
                "Средний пульс 124 · Макс. пульс 158"
        )
        XCTAssertEqual(HealthImportRules.noteDuration(3_599), "59:59")
        XCTAssertEqual(HealthImportRules.noteDuration(3_600), "1:00:00")
        XCTAssertEqual(HealthImportRules.noteDuration(86_400), "24:00:00")
    }

    func testActivityPresentationReadsCurrentAndOlderNotesInEveryLanguage() {
        let notes = [
            // Current wording: number before the unit, h:mm:ss from one hour on.
            "Health Connect · Strength training · Duration 1:02:05 · 356 kcal · Avg HR 124 · Max HR 158",
            "Health Connect · Силове тренування · Тривалість 1:02:05 · 356 ккал · Середній пульс 124 · Макс. пульс 158",
            "Health Connect · Силовая тренировка · Длительность 1:02:05 · 356 ккал · Средний пульс 124 · Макс. пульс 158",
            // Wording stored before the note format changed; those notes are never rewritten.
            "Health Connect · Strength training · Duration 62:05 · kcal 356 · Avg HR 124 · Max HR 158",
            "Health Connect · Силове тренування · Тривалість 62:05 · ккал 356 · Сер пульс 124 · Макс пульс 158",
            "Health Connect · Силовая тренировка · Длительность 62:05 · ккал 356 · Средний пульс 124 · Макс. пульс 158"
        ]
        for note in notes {
            let presentation = ActivityWorkoutPresentation.parse(note)
            XCTAssertEqual(presentation.source, .healthConnect, note)
            XCTAssertEqual(presentation.durationSeconds, 3_725, note)
            XCTAssertEqual(presentation.kilocalories, 356, note)
            XCTAssertEqual(presentation.averageHeartRate, 124, note)
            XCTAssertEqual(presentation.maximumHeartRate, 158, note)
            // A known type follows the current app language, whatever language the note was saved in.
            XCTAssertEqual(presentation.typeLabel(languageCode: "en"), "Strength training", note)
            XCTAssertEqual(presentation.typeLabel(languageCode: "uk"), "Силове тренування", note)
            XCTAssertEqual(presentation.typeLabel(languageCode: "ru"), "Силовая тренировка", note)
            XCTAssertEqual(
                presentation.subtitle(languageCode: "ru"),
                "Тренировка из Health Connect · Силовая тренировка",
                note
            )
        }
    }

    func testActivityPresentationNamesTheRealSourceAndNeverInventsGarmin() {
        let appleHealth = ActivityWorkoutPresentation.parse(
            "Apple Health · Тренування м'язів кора · Тривалість 15:00"
        )
        XCTAssertEqual(appleHealth.source, .appleHealth)
        XCTAssertEqual(appleHealth.typeLabel(languageCode: "uk"), "Тренування м’язів кора")
        XCTAssertEqual(appleHealth.subtitle(languageCode: "en"), "Workout from Apple Health · Core training")
        XCTAssertEqual(appleHealth.subtitle(languageCode: "uk"), "Тренування з Apple Health · Тренування м’язів кора")
        XCTAssertEqual(appleHealth.durationSeconds, 900)
        XCTAssertNil(appleHealth.kilocalories)
        XCTAssertNil(appleHealth.averageHeartRate)

        let wearOS = ActivityWorkoutPresentation.parse("Wear OS · Avg HR 128 · Max HR 171")
        XCTAssertEqual(wearOS.source, .wearOS)
        XCTAssertEqual(wearOS.subtitle(languageCode: "ru"), "Тренировка с Wear OS")
        XCTAssertEqual(wearOS.averageHeartRate, 128)
        XCTAssertEqual(wearOS.maximumHeartRate, 171)
        let wearOSWithOwnNote = ActivityWorkoutPresentation.parse(
            "Leg day · Wear OS · Сер пульс 128 · Макс пульс 171"
        )
        XCTAssertEqual(wearOSWithOwnNote.source, .wearOS)
        XCTAssertEqual(wearOSWithOwnNote.averageHeartRate, 128)

        let appleWatch = ActivityWorkoutPresentation.parse(
            "Apple Watch · Avg HR 118 · Max HR 161 · kcal 312"
        )
        XCTAssertEqual(appleWatch.source, .appleWatch)
        XCTAssertEqual(appleWatch.subtitle(languageCode: "uk"), "Тренування з Apple Watch")
        XCTAssertEqual(appleWatch.kilocalories, 312)
        XCTAssertEqual(
            ActivityWorkoutPresentation.parse("Apple Watch · Средний пульс 118 · 312 ккал").kilocalories,
            312
        )

        let garmin = ActivityWorkoutPresentation.parse(
            "Garmin · Duration 45:00 · Gym kcal 250 · Garmin kcal 240 · Avg HR 140 · Max HR 175"
        )
        XCTAssertEqual(garmin.source, .garmin)
        XCTAssertEqual(garmin.subtitle(languageCode: "en"), "Garmin free workout")
        XCTAssertEqual(garmin.kilocalories, 250)

        XCTAssertEqual(ActivityWorkoutPresentation.parse(nil).source, .unknown)
        let ownNote = ActivityWorkoutPresentation.parse("Felt good")
        XCTAssertEqual(ownNote.source, .unknown)
        XCTAssertEqual(ownNote.subtitle(languageCode: "ru"), "Свободная тренировка")
        XCTAssertFalse(ownNote.subtitle(languageCode: "en").contains("Garmin"))

        // No type segment: the duration is not mistaken for a type label.
        XCTAssertNil(
            ActivityWorkoutPresentation.parse("Health Connect · Duration 10:00")
                .typeLabel(languageCode: "en")
        )
        // An impossible pair is dropped instead of being shown.
        let impossible = ActivityWorkoutPresentation.parse("Health Connect · Avg HR 180 · Max HR 120")
        XCTAssertNil(impossible.averageHeartRate)
        XCTAssertNil(impossible.maximumHeartRate)
    }

    // MARK: Service

    func testReimportIsIdempotentAndDeletedWorkoutNeverReturns() async throws {
        let fixture = try makeFixture(name: "idempotent")
        let client = FakeHealthKitClient(sessions: [fixture.session(id: "AAAA-1", hoursAgo: 3)])
        let service = fixture.service(client: client)

        await service.connect()
        XCTAssertTrue(service.isConnected)
        XCTAssertEqual(fixture.store.workouts.count, 1)
        let workout = try XCTUnwrap(fixture.store.workouts.first)
        XCTAssertTrue(fixture.store.hasRecordedActivityMetrics(workout))
        XCTAssertTrue(workout.note?.hasPrefix("Apple Health · Core training · Duration 30:00") == true)
        let item = try XCTUnwrap(
            fixture.store.activityOnlyCloudItems.first {
                $0.workoutStartedAt == workout.date.gymEpochMilliseconds
            }
        )
        XCTAssertNil(item.garminCalories)
        XCTAssertNil(item.endingHeartRateZone)
        XCTAssertEqual(item.averageHeartRate, 100)

        _ = await service.importNow()
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertEqual(service.lastSummary?.imported, 0)

        try fixture.store.deleteWorkout(id: workout.id)
        _ = await service.importNow()
        XCTAssertTrue(fixture.store.workouts.isEmpty, "a deleted import must not return")

        // The receipt ledger survives a restart of the service.
        let reopened = fixture.service(client: client)
        XCTAssertTrue(reopened.isConnected)
        _ = await reopened.importNow()
        XCTAssertTrue(fixture.store.workouts.isEmpty)
    }

    func testNothingImportsBeforeConnect() async throws {
        let fixture = try makeFixture(name: "not-connected")
        let client = FakeHealthKitClient(sessions: [fixture.session(id: "BBBB-1", hoursAgo: 3)])
        let service = fixture.service(client: client)
        _ = await service.importNow()
        await service.autoImportIfDue()
        XCTAssertTrue(fixture.store.workouts.isEmpty)
        XCTAssertEqual(client.fetchCount, 0)
    }

    func testAutoImportRespectsMinimumInterval() async throws {
        let fixture = try makeFixture(name: "interval")
        let client = FakeHealthKitClient(sessions: [])
        let service = fixture.service(client: client)
        await service.connect()
        XCTAssertEqual(client.fetchCount, 1)
        await service.autoImportIfDue()
        XCTAssertEqual(client.fetchCount, 1)
        _ = await service.importNow()
        XCTAssertEqual(client.fetchCount, 2)
    }

    func testAccountSwitchDuringImportWritesNothing() async throws {
        let fixture = try makeFixture(name: "switch")
        let client = FakeHealthKitClient(sessions: [fixture.session(id: "CCCC-1", hoursAgo: 3)])
        let service = fixture.service(client: client)
        await service.connect()
        try fixture.store.deleteWorkout(id: try XCTUnwrap(fixture.store.workouts.first).id)
        client.sessions = [fixture.session(id: "CCCC-2", hoursAgo: 6)]
        let other = AppAccountSession.local(
            id: "00000000-0000-4000-8000-000000000402",
            displayName: "Other account"
        )
        client.beforeFetchReturns = { [auth = fixture.auth] in
            try? auth.installSessionForTesting(other)
        }
        _ = await service.importNow()
        XCTAssertTrue(fixture.store.workouts.isEmpty, "the previous account's store must stay untouched")
        XCTAssertNil(service.lastSummary?.imported == 1 ? service.lastSummary : nil)
    }

    func testHeartRateFromOtherSourceIsNotRequested() async throws {
        let fixture = try makeFixture(name: "source")
        let client = FakeHealthKitClient(sessions: [fixture.session(id: "DDDD-1", hoursAgo: 3)])
        let service = fixture.service(client: client)
        await service.connect()
        XCTAssertEqual(client.heartRateSources, ["com.example.watch"])
    }

    // MARK: Heart rate source (workout statistics first)

    func testWorkoutStatisticsGiveHeartRateWithoutASourceFilteredQuery() async throws {
        let fixture = try makeFixture(name: "statistics")
        let client = FakeHealthKitClient(sessions: [fixture.session(id: "EEEE-1", hoursAgo: 3)])
        // A third-party watch app: the samples belong to the watch, the workout to the app.
        client.statistics = HealthImportHeartRateStatistics(average: 131.5, maximum: 172.4)
        let service = fixture.service(client: client)
        await service.connect()

        let workout = try XCTUnwrap(fixture.store.workouts.first)
        let item = try XCTUnwrap(fixture.store.activityOnlyCloudItems.first)
        XCTAssertEqual(item.averageHeartRate, 132)
        XCTAssertEqual(item.maximumHeartRate, 172)
        XCTAssertEqual(
            workout.note,
            "Apple Health · Core training · Duration 30:00 · Avg HR 132 · Max HR 172"
        )
        XCTAssertEqual(client.statisticsRequests, ["EEEE-1"])
        XCTAssertTrue(client.heartRateSources.isEmpty, "no sample query when the workout has statistics")
    }

    func testMissingOrImplausibleStatisticsFallBackToTheSourceFilteredSamples() async throws {
        XCTAssertNil(HealthKitImportService.heartRateSummary(nil))
        for statistics in [
            HealthImportHeartRateStatistics(average: 10, maximum: 120),
            HealthImportHeartRateStatistics(average: 120, maximum: 300),
            HealthImportHeartRateStatistics(average: 150, maximum: 120),
            HealthImportHeartRateStatistics(average: .nan, maximum: 120)
        ] {
            XCTAssertNil(HealthKitImportService.heartRateSummary(statistics))
        }
        let fixture = try makeFixture(name: "statistics-fallback")
        let client = FakeHealthKitClient(sessions: [fixture.session(id: "EEEE-2", hoursAgo: 3)])
        client.statistics = HealthImportHeartRateStatistics(average: 10, maximum: 300)
        let service = fixture.service(client: client)
        await service.connect()
        XCTAssertEqual(fixture.store.activityOnlyCloudItems.first?.averageHeartRate, 100)
        XCTAssertEqual(fixture.store.activityOnlyCloudItems.first?.maximumHeartRate, 110)
        XCTAssertEqual(client.heartRateSources, ["com.example.watch"])
    }

    // MARK: Watch transfer after the import

    func testWatchWorkoutStoredAfterTheImportReplacesTheImportedCopy() async throws {
        let fixture = try makeFixture(name: "watch-after-import")
        let same = fixture.session(id: "FFFF-1", hoursAgo: 3)
        let other = fixture.session(id: "FFFF-2", hoursAgo: 9)
        let client = FakeHealthKitClient(sessions: [same, other])
        let service = fixture.service(client: client)
        await service.connect()
        XCTAssertEqual(fixture.store.workouts.count, 2)

        // The store call the Garmin phone sync makes for a workout with sets.
        _ = try fixture.store.createWorkout(
            date: Date(gymEpochMilliseconds: same.startMillis + 45_000),
            note: "Garmin",
            namedSets: [NamedWorkoutSetDraft(exerciseName: "Bench press", weight: 60, reps: 8)],
            durationSeconds: 1_700
        )
        XCTAssertEqual(fixture.store.workouts.count, 2, "one session, one workout")
        XCTAssertEqual(fixture.store.workouts.filter { !$0.exercises.isEmpty }.count, 1)
        XCTAssertEqual(
            fixture.store.activityOnlyCloudItems.map(\.workoutStartedAt), [other.startMillis]
        )

        _ = await service.importNow()
        XCTAssertEqual(fixture.store.workouts.count, 2)
        XCTAssertEqual(service.lastSummary?.imported, 0)
        let ledger = HealthImportStateStore(root: fixture.stateRoot)
            .load(account: fixture.store.accountStorageKey)
        XCTAssertEqual(Set(ledger.receipts), ["apple_health:FFFF-1", "apple_health:FFFF-2"])

        // Also after a restart of the service.
        let reopened = fixture.service(client: client)
        _ = await reopened.importNow()
        XCTAssertEqual(fixture.store.workouts.count, 2)
    }

    func testGarminTimeOnlyWorkoutReplacesTheImportedCopy() async throws {
        let fixture = try makeFixture(name: "garmin-free-after-import")
        let same = fixture.session(id: "GGGG-1", hoursAgo: 3)
        let service = fixture.service(client: FakeHealthKitClient(sessions: [same]))
        await service.connect()
        XCTAssertEqual(fixture.store.workouts.count, 1)

        _ = try fixture.store.createActivityWorkout(
            date: Date(gymEpochMilliseconds: same.startMillis),
            note: "Garmin",
            durationSeconds: 1_800
        )
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertEqual(fixture.store.workouts.first?.note, "Garmin")
        XCTAssertTrue(fixture.store.activityOnlyCloudItems.isEmpty)
        _ = await service.importNow()
        XCTAssertEqual(fixture.store.workouts.count, 1)
    }

    func testWatchWorkoutNeverRemovesWhatTheImportDidNotCreate() async throws {
        let fixture = try makeFixture(name: "watch-keeps-foreign")
        let imported = fixture.session(id: "HHHH-1", hoursAgo: 3)
        let service = fixture.service(client: FakeHealthKitClient(sessions: [imported]))
        await service.connect()
        let start = Date(gymEpochMilliseconds: imported.startMillis)
        // Same wording, but not in the ledger: an activity that came from another device.
        _ = try fixture.store.createImportedActivityWorkout(
            date: start.addingTimeInterval(60),
            note: "Apple Health · Core training · Duration 30:00",
            durationSeconds: 1_800,
            gymCalories: 0,
            averageHeartRate: nil,
            maximumHeartRate: nil
        )
        // The user's own time-only entry.
        _ = try fixture.store.createImportedActivityWorkout(
            date: start.addingTimeInterval(120),
            note: "Felt good",
            durationSeconds: 1_800,
            gymCalories: 0,
            averageHeartRate: nil,
            maximumHeartRate: nil
        )
        XCTAssertEqual(fixture.store.workouts.count, 3)

        // A watch workout far outside the overlap tolerance removes nothing.
        _ = try fixture.store.createWorkout(
            date: start.addingTimeInterval(-36_000),
            note: "Garmin",
            namedSets: [NamedWorkoutSetDraft(exerciseName: "Bench press", weight: 60, reps: 8)],
            durationSeconds: 1_700
        )
        XCTAssertEqual(fixture.store.workouts.count, 4)

        // An overlapping one removes only the workout the import created.
        _ = try fixture.store.createWorkout(
            date: start.addingTimeInterval(30),
            note: "Garmin",
            namedSets: [NamedWorkoutSetDraft(exerciseName: "Bench press", weight: 60, reps: 8)],
            durationSeconds: 1_700
        )
        XCTAssertEqual(fixture.store.workouts.count, 4)
        XCTAssertFalse(fixture.store.workouts.contains {
            $0.date.gymEpochMilliseconds == imported.startMillis
        })
        XCTAssertEqual(fixture.store.activityOnlyCloudItems.count, 2)
    }

    func testLedgerWrittenBeforeImportedWorkoutsStillDecodesAndTrimsWithItsReceipts() throws {
        let old = Data(
            #"{"version":1,"connected":true,"receipts":["apple_health:OLD-1"],"lastImportAt":10,"importedTotal":1}"#.utf8
        )
        var ledger = try JSONDecoder().decode(HealthImportLedger.self, from: old)
        XCTAssertTrue(ledger.connected)
        XCTAssertEqual(ledger.receipts, ["apple_health:OLD-1"])
        XCTAssertEqual(ledger.importedTotal, 1)
        XCTAssertNil(ledger.importedWorkouts)
        XCTAssertTrue(ledger.importedWorkoutDurationsByStart.isEmpty)

        for index in 0 ..< HealthImportLedger.maximumReceipts {
            ledger.add(
                receipt: "apple_health:NEW-\(index)",
                workout: .init(startMillis: Int64(index) * 10_000_000, durationSeconds: 600)
            )
        }
        XCTAssertEqual(ledger.receipts.count, HealthImportLedger.maximumReceipts)
        XCTAssertFalse(ledger.receipts.contains("apple_health:OLD-1"))
        XCTAssertEqual(ledger.importedWorkouts?.count, HealthImportLedger.maximumReceipts)
        ledger.add(receipt: "apple_health:NEW-LAST", workout: .init(startMillis: -1, durationSeconds: 60))
        XCTAssertNil(ledger.importedWorkouts?["apple_health:NEW-0"], "an interval leaves with its receipt")
        XCTAssertEqual(ledger.importedWorkouts?.count, HealthImportLedger.maximumReceipts)
        let decoded = try JSONDecoder().decode(
            HealthImportLedger.self, from: JSONEncoder().encode(ledger)
        )
        XCTAssertEqual(decoded, ledger)
    }

    // MARK: Overlapping runs and the automatic throttle

    func testAutoImportRunsAgainAfterTheClockWasSetBack() async throws {
        let fixture = try makeFixture(name: "clock-back")
        let client = FakeHealthKitClient(sessions: [])
        let clock = HealthImportTestClock(Date())
        let service = HealthKitImportService(
            auth: fixture.auth,
            defaults: fixture.defaults,
            client: client,
            stateStore: HealthImportStateStore(root: fixture.stateRoot),
            now: { clock.now }
        )
        service.bind(workoutStore: fixture.store)
        await service.connect()
        XCTAssertEqual(client.fetchCount, 1)

        clock.now = clock.now.addingTimeInterval(-7_200)
        await service.autoImportIfDue()
        XCTAssertEqual(client.fetchCount, 2, "a last run that lies in the future never blocks")
        clock.now = clock.now.addingTimeInterval(1_800)
        await service.autoImportIfDue()
        XCTAssertEqual(client.fetchCount, 2, "30 minutes after that run is still throttled")
        clock.now = clock.now.addingTimeInterval(1_800)
        await service.autoImportIfDue()
        XCTAssertEqual(client.fetchCount, 3, "one hour later it is due")
    }

    func testRunLeftBehindByAnAccountSwitchCannotClearTheNewAccountsRun() async throws {
        let fixture = try makeFixture(name: "run-token")
        let client = FakeHealthKitClient(sessions: [])
        let service = fixture.service(client: client)
        await service.connect()

        let other = AppAccountSession.local(
            id: "00000000-0000-4000-8000-000000000403",
            displayName: "Second account"
        )
        XCTAssertTrue(
            HealthImportStateStore(root: fixture.stateRoot)
                .save(HealthImportLedger(connected: true), account: other.storageKey)
        )
        let otherRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthImportRulesTests-other-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: otherRoot) }
        let otherStore = try WorkoutStore(
            accountStorageKey: other.storageKey,
            directoryURL: otherRoot.appendingPathComponent("workouts", isDirectory: true)
        )

        client.suspendFetches = true
        let oldRun = Task { @MainActor in await service.importNow() }
        await waitUntil { client.suspendedFetchCount == 1 }
        XCTAssertTrue(service.isImporting)

        try fixture.auth.installSessionForTesting(other)
        await waitUntil { !service.isImporting }
        service.bind(workoutStore: otherStore)
        XCTAssertTrue(service.isConnected)
        let newRun = Task { @MainActor in await service.importNow() }
        await waitUntil { client.suspendedFetchCount == 2 }
        XCTAssertTrue(service.isImporting)

        client.resumeFetch(at: 0)
        let oldResult = await oldRun.value
        XCTAssertFalse(oldResult)
        XCTAssertTrue(service.isImporting, "only the run that owns the flag may clear it")
        let third = await service.importNow()
        XCTAssertFalse(third, "no second run while the new account's run is active")
        XCTAssertEqual(client.fetchCount, 3)

        client.resumeFetch(at: 1)
        let newResult = await newRun.value
        XCTAssertTrue(newResult)
        XCTAssertFalse(service.isImporting)
    }

    func testRunLeftBehindWritesNothingAfterReturningToTheSameAccount() async throws {
        let fixture = try makeFixture(name: "run-token-return")
        let first = try XCTUnwrap(fixture.auth.session)
        let client = FakeHealthKitClient(sessions: [])
        let service = fixture.service(client: client)
        await service.connect()
        client.sessions = [fixture.session(id: "IIII-1", hoursAgo: 3)]

        client.suspendFetches = true
        let oldRun = Task { @MainActor in await service.importNow() }
        await waitUntil { client.suspendedFetchCount == 1 }
        try fixture.auth.installSessionForTesting(
            .local(id: "00000000-0000-4000-8000-000000000404", displayName: "Passing by")
        )
        await waitUntil { !service.isConnected }
        try fixture.auth.installSessionForTesting(first)
        await waitUntil { service.isConnected }

        let newRun = Task { @MainActor in await service.importNow() }
        await waitUntil { client.suspendedFetchCount == 2 }
        client.resumeFetch(at: 0)
        let oldResult = await oldRun.value
        XCTAssertFalse(oldResult, "the earlier run was abandoned by the account change")
        XCTAssertTrue(fixture.store.workouts.isEmpty)
        XCTAssertTrue(service.isImporting)

        client.resumeFetch(at: 1)
        let newResult = await newRun.value
        XCTAssertTrue(newResult)
        XCTAssertEqual(fixture.store.workouts.count, 1)
        XCTAssertEqual(service.importedTotal, 1)
        XCTAssertFalse(service.isImporting)
    }

    // MARK: Helpers

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 3_000 where !condition() {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertTrue(condition(), "timed out waiting for the service")
    }

    private struct Fixture {
        let auth: AuthService
        let defaults: UserDefaults
        let store: WorkoutStore
        let stateRoot: URL

        @MainActor
        func service(client: FakeHealthKitClient) -> HealthKitImportService {
            let service = HealthKitImportService(
                auth: auth,
                defaults: defaults,
                client: client,
                stateStore: HealthImportStateStore(root: stateRoot)
            )
            service.bind(workoutStore: store)
            return service
        }

        func session(id: String, hoursAgo: Double) -> HealthImportSession {
            let end = Date().addingTimeInterval(-hoursAgo * 3_600 + 1_800)
            let start = end.addingTimeInterval(-1_800)
            return HealthImportSession(
                recordId: id,
                startMillis: start.gymEpochMilliseconds,
                endMillis: end.gymEpochMilliseconds,
                exerciseType: "coreTraining",
                sourceId: "com.example.watch",
                kilocalories: nil,
                heartRateSamples: []
            )
        }
    }

    private func makeFixture(name: String) throws -> Fixture {
        let suite = "HealthImportRulesTests-\(name)-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        // The note is written in the app language; pin it so the suite does not depend on the
        // simulator language (an empty suite falls back to `Locale.preferredLanguages`).
        defaults.set("en", forKey: "app-language")
        let auth = AuthService(keychain: HealthImportTestKeychain(), defaults: defaults)
        let account = AppAccountSession.local(
            id: "00000000-0000-4000-8000-000000000401",
            displayName: "Health import"
        )
        try auth.installSessionForTesting(account)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthImportRulesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = try WorkoutStore(
            accountStorageKey: account.storageKey,
            directoryURL: root.appendingPathComponent("workouts", isDirectory: true)
        )
        return Fixture(
            auth: auth,
            defaults: defaults,
            store: store,
            stateRoot: root.appendingPathComponent("state", isDirectory: true)
        )
    }

    private func loadContract() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/health-import-v1.json")
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func parseSession(_ raw: [String: Any]) throws -> HealthImportSession {
        let samples = (raw["heartRateSamples"] as? [[String: Any]] ?? []).map {
            HealthImportHeartRateSample(
                timeMillis: ($0["timeMillis"] as? NSNumber)?.int64Value ?? 0,
                bpm: ($0["bpm"] as? NSNumber)?.doubleValue ?? 0
            )
        }
        return HealthImportSession(
            recordId: try XCTUnwrap(raw["recordId"] as? String),
            startMillis: try XCTUnwrap((raw["startMillis"] as? NSNumber)?.int64Value),
            endMillis: try XCTUnwrap((raw["endMillis"] as? NSNumber)?.int64Value),
            exerciseType: raw["exerciseType"] as? String,
            sourceId: try XCTUnwrap(raw["sourceId"] as? String),
            kilocalories: (raw["kilocalories"] as? NSNumber)?.doubleValue,
            heartRateSamples: samples
        )
    }
}

private final class FakeHealthKitClient: HealthKitImportClient, @unchecked Sendable {
    var sessions: [HealthImportSession]
    var beforeFetchReturns: (() -> Void)?
    /// What Apple Health reports for the workout itself; nil means "no statistics".
    var statistics: HealthImportHeartRateStatistics?
    /// When true, every fetch waits until `resumeFetch(at:)` releases it.
    var suspendFetches = false
    private let lock = NSLock()
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var fetches = 0
    private var sources: [String] = []
    private var statisticsIds: [String] = []

    var fetchCount: Int { lock.withLock { fetches } }
    var heartRateSources: [String] { lock.withLock { sources } }
    var statisticsRequests: [String] { lock.withLock { statisticsIds } }
    var suspendedFetchCount: Int { lock.withLock { gates.count } }

    func resumeFetch(at index: Int) {
        lock.withLock { gates[index] }.resume()
    }

    init(sessions: [HealthImportSession]) {
        self.sessions = sessions
    }

    var isAvailable: Bool { true }

    func requestAuthorization() async throws {}

    func fetchWorkouts(since: Date, limit: Int) async throws -> [HealthImportSession] {
        lock.withLock { fetches += 1 }
        if suspendFetches {
            await withCheckedContinuation { continuation in
                lock.withLock { gates.append(continuation) }
            }
        }
        beforeFetchReturns?()
        return sessions
    }

    func heartRateStatistics(recordId: String) async throws -> HealthImportHeartRateStatistics? {
        lock.withLock { statisticsIds.append(recordId) }
        return statistics
    }

    func heartRateSamples(
        startMillis: Int64,
        endMillis: Int64,
        sourceId: String
    ) async throws -> [HealthImportHeartRateSample] {
        lock.withLock { sources.append(sourceId) }
        return [
            HealthImportHeartRateSample(timeMillis: startMillis + 1_000, bpm: 90),
            HealthImportHeartRateSample(timeMillis: startMillis + 2_000, bpm: 110)
        ]
    }
}

private final class HealthImportTestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private final class HealthImportTestKeychain: KeychainStoring {
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
