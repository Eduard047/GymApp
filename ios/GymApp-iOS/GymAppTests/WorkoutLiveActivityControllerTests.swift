import ActivityKit
import AppIntents
import XCTest
@testable import GymApp

// MARK: - Fake ActivityKit wrapper

@MainActor
private final class FakeLiveActivityHandle: LiveActivityHandle {
    fileprivate(set) var updates: [WorkoutActivityAttributes.ContentState] = []
    private(set) var endCount = 0
    private(set) var lastDismissalPolicy: ActivityUIDismissalPolicy?

    func update(_ content: ActivityContent<WorkoutActivityAttributes.ContentState>) async {
        updates.append(content.state)
    }

    func end(dismissalPolicy: ActivityUIDismissalPolicy) async {
        endCount += 1
        lastDismissalPolicy = dismissalPolicy
    }
}

@MainActor
private final class FakeLiveActivityRequester: LiveActivityRequesting {
    var enabled = true
    private(set) var requestedAttributes: [WorkoutActivityAttributes] = []
    /// The handle returned by the next `request(...)` call, so the test can
    /// keep observing it after handing it to the controller.
    var nextHandle = FakeLiveActivityHandle()
    private(set) var requestCount = 0
    /// Activities ActivityKit already "knows about" before the controller
    /// runs — simulating one a previous process started and left running
    /// through a relaunch/update. Seeded by the test via `seedExisting`.
    private(set) var existingActivities: [LiveActivitySnapshot] = []

    func areActivitiesEnabled() -> Bool { enabled }

    func currentActivities() -> [LiveActivitySnapshot] { existingActivities }

    /// Adds a pre-existing activity the controller has not started itself,
    /// returning its handle so the test can assert on it.
    @discardableResult
    func seedExisting(workoutID: UUID) -> FakeLiveActivityHandle {
        let handle = FakeLiveActivityHandle()
        existingActivities.append(LiveActivitySnapshot(workoutID: workoutID, handle: handle))
        return handle
    }

    func request(
        attributes: WorkoutActivityAttributes,
        content: ActivityContent<WorkoutActivityAttributes.ContentState>
    ) throws -> LiveActivityHandle {
        requestCount += 1
        requestedAttributes.append(attributes)
        nextHandle.updates.append(content.state)
        return nextHandle
    }
}

// MARK: - Draft fixtures

private enum Fixture {
    static func draft(
        exercises: [ActiveWorkoutExercise],
        restingUntil: Date? = nil,
        undoableSetID: UUID? = nil
    ) -> ActiveWorkoutDraft {
        ActiveWorkoutDraft(
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            workoutDate: Date(timeIntervalSince1970: 1_800_000_000),
            exercises: exercises,
            undoableSetID: undoableSetID,
            revision: 1,
            lastModifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            timing: ActiveWorkoutTimingState(restingUntil: restingUntil)
        )
    }

    static func exercise(name: String, sets: [ActiveWorkoutSet]) -> ActiveWorkoutExercise {
        ActiveWorkoutExercise(exerciseID: UUID(), exerciseName: name, sets: sets)
    }

    static func set(weight: Double, reps: Int, completed: Bool) -> ActiveWorkoutSet {
        ActiveWorkoutSet(weight: weight, reps: reps, completedAt: completed ? Date() : nil)
    }
}

// MARK: - ContentState mapping tests

@MainActor
final class WorkoutLiveActivityContentStateMappingTests: XCTestCase {
    func testNotRestingShowsNextSetSummaryAndCorrectProgress() {
        let bench = Fixture.exercise(
            name: "Bench Press",
            sets: [
                Fixture.set(weight: 60, reps: 8, completed: true),
                Fixture.set(weight: 60, reps: 8, completed: false),
                Fixture.set(weight: 60, reps: 8, completed: false)
            ]
        )
        let draft = Fixture.draft(exercises: [bench])

        let state = WorkoutLiveActivityController.contentState(for: draft, workoutStore: nil)

        XCTAssertEqual(state.exerciseName, "Bench Press")
        XCTAssertEqual(state.setIndex, 2)
        XCTAssertEqual(state.setCount, 3)
        XCTAssertEqual(state.completedSets, 1)
        XCTAssertEqual(state.totalSets, 3)
        XCTAssertFalse(state.isResting)
        XCTAssertNil(state.restEndsAt)
        XCTAssertTrue(state.nextSetSummary.contains("60"))
        XCTAssertTrue(state.nextSetSummary.contains("8"))
    }

    func testRestingExposesFutureRestEndsAt() {
        let future = Date().addingTimeInterval(90)
        let bench = Fixture.exercise(
            name: "Squat",
            sets: [
                Fixture.set(weight: 100, reps: 5, completed: true),
                Fixture.set(weight: 100, reps: 5, completed: false)
            ]
        )
        let draft = Fixture.draft(exercises: [bench], restingUntil: future)

        let state = WorkoutLiveActivityController.contentState(for: draft, workoutStore: nil)

        XCTAssertTrue(state.isResting)
        XCTAssertEqual(state.restEndsAt, future)
    }

    func testExpiredRestDeadlineIsTreatedAsNotResting() {
        let past = Date().addingTimeInterval(-30)
        let bench = Fixture.exercise(
            name: "Squat",
            sets: [Fixture.set(weight: 100, reps: 5, completed: false)]
        )
        let draft = Fixture.draft(exercises: [bench], restingUntil: past)

        let state = WorkoutLiveActivityController.contentState(for: draft, workoutStore: nil)

        XCTAssertFalse(state.isResting)
        XCTAssertNil(state.restEndsAt)
    }

    func testAllSetsCompletedFallsBackToFinishingSummary() {
        let bench = Fixture.exercise(
            name: "Row",
            sets: [
                Fixture.set(weight: 40, reps: 10, completed: true),
                Fixture.set(weight: 40, reps: 10, completed: true)
            ]
        )
        let draft = Fixture.draft(exercises: [bench])

        let state = WorkoutLiveActivityController.contentState(for: draft, workoutStore: nil)

        XCTAssertEqual(state.completedSets, 2)
        XCTAssertEqual(state.totalSets, 2)
        XCTAssertFalse(state.isResting)
        XCTAssertFalse(state.nextSetSummary.isEmpty)
    }

    func testCurrentSetPicksFirstUncompletedAcrossExercises() {
        let first = Fixture.exercise(
            name: "Bench Press",
            sets: [Fixture.set(weight: 60, reps: 8, completed: true)]
        )
        let second = Fixture.exercise(
            name: "Row",
            sets: [Fixture.set(weight: 40, reps: 10, completed: false)]
        )
        let draft = Fixture.draft(exercises: [first, second])

        let location = WorkoutLiveActivityController.currentSet(in: draft)

        XCTAssertEqual(location?.exercise.exerciseName, "Row")
        XCTAssertEqual(location?.set.weight, 40)
    }
}

// MARK: - Controller start/update/end decision tests

@MainActor
final class WorkoutLiveActivityControllerDecisionTests: XCTestCase {
    func testSyncWithDraftStartsActivityWhenNoneIsRunning() {
        let requester = FakeLiveActivityRequester()
        let controller = WorkoutLiveActivityController(requester: requester)
        let draft = Fixture.draft(exercises: [
            Fixture.exercise(name: "Bench Press", sets: [Fixture.set(weight: 60, reps: 8, completed: false)])
        ])

        controller.sync(draft: draft)

        XCTAssertEqual(requester.requestCount, 1)
        XCTAssertEqual(requester.requestedAttributes.first?.workoutID, draft.id)
    }

    func testSyncTwiceUpdatesRatherThanStartingASecondActivity() {
        let requester = FakeLiveActivityRequester()
        let controller = WorkoutLiveActivityController(requester: requester)
        let draft = Fixture.draft(exercises: [
            Fixture.exercise(name: "Bench Press", sets: [Fixture.set(weight: 60, reps: 8, completed: false)])
        ])

        controller.sync(draft: draft)
        controller.sync(draft: draft)

        XCTAssertEqual(requester.requestCount, 1, "A second sync while already running must update, not start again")
    }

    func testSyncWithNilDraftEndsWithDelayedDismissal() {
        let requester = FakeLiveActivityRequester()
        let controller = WorkoutLiveActivityController(requester: requester)
        let draft = Fixture.draft(exercises: [
            Fixture.exercise(name: "Bench Press", sets: [Fixture.set(weight: 60, reps: 8, completed: false)])
        ])
        controller.sync(draft: draft)
        let handle = requester.nextHandle

        controller.sync(draft: nil)

        let expectation = expectation(description: "activity ends")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(handle.endCount, 1)
        XCTAssertNotNil(handle.lastDismissalPolicy)
        XCTAssertNotEqual(
            handle.lastDismissalPolicy,
            .immediate,
            "Finishing should use a delayed dismissal policy, not immediate"
        )
    }

    func testEndImmediatelyUsesImmediateDismissalPolicy() {
        let requester = FakeLiveActivityRequester()
        let controller = WorkoutLiveActivityController(requester: requester)
        let draft = Fixture.draft(exercises: [
            Fixture.exercise(name: "Bench Press", sets: [Fixture.set(weight: 60, reps: 8, completed: false)])
        ])
        controller.sync(draft: draft)
        let handle = requester.nextHandle

        controller.endImmediately()

        let expectation = expectation(description: "activity ends immediately")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(handle.endCount, 1)
        XCTAssertEqual(handle.lastDismissalPolicy, .immediate)
    }

    func testDisabledAuthorizationNeverStartsAnActivity() {
        let requester = FakeLiveActivityRequester()
        requester.enabled = false
        let controller = WorkoutLiveActivityController(requester: requester)
        let draft = Fixture.draft(exercises: [
            Fixture.exercise(name: "Bench Press", sets: [Fixture.set(weight: 60, reps: 8, completed: false)])
        ])

        controller.sync(draft: draft)

        XCTAssertEqual(requester.requestCount, 0)
    }
}

// MARK: - Adoption of an already-running activity (relaunch/update recovery)

/// Covers the "Live Activity on the lock screen stops responding after the
/// app is relaunched or updated" bug: a fresh `WorkoutLiveActivityController`
/// instance never started the activity ActivityKit is still showing, so
/// without adoption it has no handle for it and never updates its
/// `ContentState` (no `currentSetID`), making "record set"/"skip rest"
/// silent no-ops.
@MainActor
final class WorkoutLiveActivityControllerAdoptionTests: XCTestCase {
    func testExistingMatchingActivityIsAdoptedAndUpdatedWithCurrentSetID() {
        let requester = FakeLiveActivityRequester()
        let draft = Fixture.draft(exercises: [
            Fixture.exercise(name: "Bench Press", sets: [Fixture.set(weight: 60, reps: 8, completed: false)])
        ])
        let existingHandle = requester.seedExisting(workoutID: draft.id)
        let controller = WorkoutLiveActivityController(requester: requester)

        controller.adoptRunningActivities(draft: draft)

        // The adoption update is dispatched via `Task { await handle.update }`,
        // same as every other handle mutation in this controller (see
        // `testSyncWithNilDraftEndsWithDelayedDismissal` etc.) — give it a
        // beat to land before asserting, instead of racing it.
        let adoptionUpdateExpectation = expectation(description: "adoption update lands")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            adoptionUpdateExpectation.fulfill()
        }
        wait(for: [adoptionUpdateExpectation], timeout: 1)

        XCTAssertEqual(requester.requestCount, 0, "an adopted activity must not also be freshly requested")
        XCTAssertEqual(existingHandle.endCount, 0, "the matching activity must not be ended")
        XCTAssertEqual(existingHandle.updates.count, 1, "the adopted activity must receive a fresh ContentState")
        XCTAssertEqual(existingHandle.updates.last?.currentSetID, draft.exercises.first?.sets.first?.id)

        // The adopted handle must become the controller's own handle: a
        // subsequent sync updates it rather than starting a second activity.
        controller.sync(draft: draft)
        let syncUpdateExpectation = expectation(description: "sync update lands")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            syncUpdateExpectation.fulfill()
        }
        wait(for: [syncUpdateExpectation], timeout: 1)

        XCTAssertEqual(requester.requestCount, 0)
        XCTAssertEqual(existingHandle.updates.count, 2)
    }

    func testNonMatchingActivityIsEnded() {
        let requester = FakeLiveActivityRequester()
        let draft = Fixture.draft(exercises: [
            Fixture.exercise(name: "Bench Press", sets: [Fixture.set(weight: 60, reps: 8, completed: false)])
        ])
        let staleHandle = requester.seedExisting(workoutID: UUID())

        let controller = WorkoutLiveActivityController(requester: requester)
        controller.adoptRunningActivities(draft: draft)

        let expectation = expectation(description: "stale activity ends")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(staleHandle.endCount, 1, "a non-matching workout id must be ended")
        XCTAssertEqual(staleHandle.lastDismissalPolicy, .immediate)
        XCTAssertTrue(staleHandle.updates.isEmpty, "a non-matching activity must never be adopted/updated")
    }

    func testWithNoDraftAllActivitiesAreEnded() {
        let requester = FakeLiveActivityRequester()
        let firstHandle = requester.seedExisting(workoutID: UUID())
        let secondHandle = requester.seedExisting(workoutID: UUID())

        let controller = WorkoutLiveActivityController(requester: requester)
        controller.adoptRunningActivities(draft: nil)

        let expectation = expectation(description: "all activities end")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(firstHandle.endCount, 1)
        XCTAssertEqual(secondHandle.endCount, 1)
        XCTAssertEqual(requester.requestCount, 0, "no draft must never start a fresh activity")
    }
}

// MARK: - LiveActivityActionBridge guard tests (the widget extension's
// LiveActivityIntent buttons call through this exact bridge)

@MainActor
final class WorkoutLiveActivityBridgeGuardTests: XCTestCase {
    private func makeStores(account: String) throws -> (
        history: WorkoutStore, active: ActiveWorkoutStore, exercise: Exercise
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-live-activity-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let history = try WorkoutStore(accountStorageKey: account, directoryURL: directory)
        let exercise = try history.addExercise(name: "Bridge Test Exercise \(UUID().uuidString)")
        let active = ActiveWorkoutStore(
            accountStorageKey: history.accountStorageKey,
            workoutStorageURL: history.storageURL
        )
        return (history, active, exercise)
    }

    private func inertRestTimers() -> RestTimerManager {
        RestTimerManager(defaults: UserDefaults(suiteName: "gym-live-activity-bridge-\(UUID().uuidString)")!)
    }

    override func tearDown() {
        LiveActivityActionBridge.recordCurrentSet = nil
        LiveActivityActionBridge.skipRest = nil
        super.tearDown()
    }

    func testRecordCurrentSetThroughBridgeRecordsExactlyOnce() throws {
        let (history, active, exercise) = try makeStores(account: "bridge-record-once")
        let setID = UUID()
        let draft = try active.start(
            workoutDate: Date(),
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCatalogKey: exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: setID, weight: 60, reps: 8)]
                )
            ],
            workoutStore: history,
            now: Date()
        )
        let controller = WorkoutLiveActivityController(requester: FakeLiveActivityRequester())
        controller.attach(workoutStore: history, activeWorkoutStore: active, restTimers: inertRestTimers())

        LiveActivityActionBridge.recordCurrentSet?(draft.id, setID)

        XCTAssertEqual(active.draft?.exercises.first?.sets.first?.completedAt != nil, true)
        let revisionAfterFirst = active.draft?.revision

        // A second tap with the SAME (now stale) setID — e.g. a duplicate/
        // replayed intent invocation for the tap already handled above —
        // must not record a second time: there is no next uncompleted set
        // any more, so the (setID, currentSet) match fails regardless.
        LiveActivityActionBridge.recordCurrentSet?(draft.id, setID)
        XCTAssertEqual(active.draft?.revision, revisionAfterFirst, "second call must no-op, not double-record")
    }

    func testMismatchedWorkoutIDNoOpsAndEndsTheStaleActivity() throws {
        let (history, active, exercise) = try makeStores(account: "bridge-mismatch")
        let setID = UUID()
        let draft = try active.start(
            workoutDate: Date(),
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCatalogKey: exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: setID, weight: 60, reps: 8)]
                )
            ],
            workoutStore: history,
            now: Date()
        )
        let requester = FakeLiveActivityRequester()
        let controller = WorkoutLiveActivityController(requester: requester)
        controller.attach(workoutStore: history, activeWorkoutStore: active, restTimers: inertRestTimers())
        // The controller's own `sync` already started an activity for this
        // draft inside `attach`.
        let handle = requester.nextHandle

        LiveActivityActionBridge.recordCurrentSet?(UUID(), setID)

        XCTAssertNil(active.draft?.exercises.first?.sets.first?.completedAt, "a mismatched id must not record")
        // `end(dismissalPolicy:)` is dispatched onto a `Task`, so give it a
        // beat before asserting (same pattern as
        // `WorkoutLiveActivityControllerDecisionTests`).
        let expectation = expectation(description: "stale activity ends")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(handle.endCount, 1, "a mismatched id must end the stale activity")
        XCTAssertEqual(handle.lastDismissalPolicy, .immediate)
    }

    func testSkipRestNoOpsWhenNotCurrentlyResting() throws {
        let (history, active, exercise) = try makeStores(account: "bridge-skip-not-resting")
        let draft = try active.start(
            workoutDate: Date(),
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCatalogKey: exercise.catalogKey,
                    sets: [ActiveWorkoutSet(weight: 60, reps: 8)]
                )
            ],
            workoutStore: history,
            now: Date()
        )
        let controller = WorkoutLiveActivityController(requester: FakeLiveActivityRequester())
        controller.attach(workoutStore: history, activeWorkoutStore: active, restTimers: inertRestTimers())
        let revisionBefore = active.draft?.revision

        LiveActivityActionBridge.skipRest?(draft.id, Date())

        XCTAssertEqual(active.draft?.revision, revisionBefore, "no rest running: skip must no-op")
    }

    func testColdLaunchReopensPersistedDraftAndTheBridgeActsOnIt() throws {
        // Simulates a background LiveActivityIntent launch: the first
        // `ActiveWorkoutStore` (like a previous app run) persists a draft to
        // disk and is then discarded; a brand-new instance — as `AppState`
        // would construct at process launch — reopens the same storage and
        // the bridge must act on that reopened instance, not a stale one.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-live-activity-cold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let history = try WorkoutStore(accountStorageKey: "bridge-cold-launch", directoryURL: directory)
        let exercise = try history.addExercise(name: "Cold Launch Exercise")
        let setID = UUID()
        do {
            let firstRunActive = ActiveWorkoutStore(
                accountStorageKey: history.accountStorageKey,
                workoutStorageURL: history.storageURL
            )
            _ = try firstRunActive.start(
                workoutDate: Date(),
                note: nil,
                exercises: [
                    ActiveWorkoutExercise(
                        exerciseID: exercise.id,
                        exerciseName: exercise.name,
                        exerciseCatalogKey: exercise.catalogKey,
                        sets: [ActiveWorkoutSet(id: setID, weight: 80, reps: 5)]
                    )
                ],
                workoutStore: history,
                now: Date()
            )
        }

        // "Cold launch": a fresh AppState-owned instance reopens the same file.
        let reopenedActive = ActiveWorkoutStore(
            accountStorageKey: history.accountStorageKey,
            workoutStorageURL: history.storageURL
        )
        XCTAssertNotNil(reopenedActive.draft, "the reopened, app-level-owned store must load the persisted draft")
        let draftID = try XCTUnwrap(reopenedActive.draft?.id)

        let controller = WorkoutLiveActivityController(requester: FakeLiveActivityRequester())
        controller.attach(workoutStore: history, activeWorkoutStore: reopenedActive, restTimers: inertRestTimers())

        LiveActivityActionBridge.recordCurrentSet?(draftID, setID)

        XCTAssertEqual(reopenedActive.draft?.exercises.first?.sets.first?.completedAt != nil, true)
    }

    /// Regression guard for the "tap does nothing on the Lock Screen" bug:
    /// `RecordCurrentSetIntent`/`SkipRestIntent` must be compiled into the
    /// `GymApp` app target (not just the `GymAppLiveActivity` extension),
    /// because `LiveActivityIntent.perform()` runs in the app's process and
    /// the system routes the tap by looking up the intent type inside the
    /// app's own binary. If these types were ever moved back into a
    /// GymAppLiveActivity-only file, this `@testable import GymApp` test
    /// file (which lives in the GymAppTests target alongside GymApp) would
    /// fail to compile, catching the regression at build time rather than
    /// silently no-opping on a physical Lock Screen tap.
    func testLiveActivityIntentTypesAreVisibleInTheAppTarget() {
        // A compile-time conformance check: this only type-checks if
        // RecordCurrentSetIntent/SkipRestIntent are LiveActivityIntent types
        // visible from the GymApp module that GymAppTests imports.
        func assertIsLiveActivityIntent<T: LiveActivityIntent>(_ type: T.Type) {}
        assertIsLiveActivityIntent(RecordCurrentSetIntent.self)
        assertIsLiveActivityIntent(SkipRestIntent.self)

        let recordIntent = RecordCurrentSetIntent(workoutID: UUID(), setID: UUID())
        let skipIntent = SkipRestIntent(workoutID: UUID(), restEndsAt: Date())
        XCTAssertFalse(recordIntent.workoutIDString.isEmpty)
        XCTAssertFalse(recordIntent.setIDString.isEmpty)
        XCTAssertFalse(skipIntent.workoutIDString.isEmpty)
    }

    /// Regression guard for the "English catalog name instead of localized
    /// name" bug: `ContentState` must go through `gymExerciseName`/
    /// `BuiltInExerciseCatalog.displayName`, the same localized lookup the
    /// in-app UI uses (see `ActiveWorkoutView.exercisePanel`), not the raw
    /// English catalog `Exercise.name`.
    func testSetProgressLabelIsLocalizedByTheAppInEveryLanguage() {
        let bench = Fixture.exercise(
            name: "Bench Press",
            sets: [
                Fixture.set(weight: 60, reps: 8, completed: true),
                Fixture.set(weight: 60, reps: 8, completed: true),
                Fixture.set(weight: 62.5, reps: 8, completed: false),
                Fixture.set(weight: 62.5, reps: 8, completed: false),
                Fixture.set(weight: 62.5, reps: 8, completed: false)
            ]
        )
        let draft = Fixture.draft(exercises: [bench])

        let english = WorkoutLiveActivityController.contentState(for: draft, workoutStore: nil, languageCode: "en")
        let ukrainian = WorkoutLiveActivityController.contentState(for: draft, workoutStore: nil, languageCode: "uk")
        let russian = WorkoutLiveActivityController.contentState(for: draft, workoutStore: nil, languageCode: "ru")

        XCTAssertEqual(english.setProgressLabel, "Set 3 of 5")
        XCTAssertEqual(ukrainian.setProgressLabel, "Підхід 3 з 5")
        XCTAssertEqual(russian.setProgressLabel, "Подход 3 из 5")
        XCTAssertEqual(english.nextSetSummary, "62.5 kg × 8")
        XCTAssertEqual(russian.nextSetSummary, "62,5 кг × 8")
    }

    func testButtonTitlesAreLocalizedByTheAppInEveryLanguage() {
        let bench = Fixture.exercise(
            name: "Bench Press",
            sets: [Fixture.set(weight: 60, reps: 8, completed: false)]
        )
        let draft = Fixture.draft(exercises: [bench])
        let expected: [(String, String, String)] = [
            ("en", "Record set", "Skip rest"),
            ("uk", "Записати підхід", "Пропустити відпочинок"),
            ("ru", "Записать подход", "Пропустить отдых")
        ]

        for (code, record, skip) in expected {
            let state = WorkoutLiveActivityController.contentState(
                for: draft, workoutStore: nil, languageCode: code
            )
            XCTAssertEqual(state.recordSetButtonTitle, record, code)
            XCTAssertEqual(state.skipRestButtonTitle, skip, code)
            XCTAssertEqual(state.resolvedRecordSetButtonTitle, record, code)
            XCTAssertEqual(state.resolvedSkipRestButtonTitle, skip, code)
        }
    }

    func testFinishedStateStillCarriesALocalizedSetProgressLabel() {
        let row = Fixture.exercise(
            name: "Row",
            sets: [
                Fixture.set(weight: 40, reps: 10, completed: true),
                Fixture.set(weight: 40, reps: 10, completed: true)
            ]
        )
        let state = WorkoutLiveActivityController.contentState(
            for: Fixture.draft(exercises: [row]),
            workoutStore: nil,
            languageCode: "uk"
        )

        XCTAssertEqual(state.setProgressLabel, "Підхід 2 з 2")
    }

    func testContentStateEncodedWithoutSetProgressLabelStillDecodes() throws {
        let legacyJSON = """
        {"exerciseName":"Squat","setIndex":2,"setCount":4,"completedSets":1,"totalSets":4,\
        "nextSetSummary":"100 kg × 5","isResting":false}
        """
        let state = try JSONDecoder().decode(
            WorkoutActivityAttributes.ContentState.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertNil(state.setProgressLabel)
        XCTAssertNil(state.recordSetButtonTitle)
        XCTAssertNil(state.skipRestButtonTitle)
        XCTAssertEqual(state.resolvedRecordSetButtonTitle, "Record set")
        XCTAssertEqual(state.resolvedSkipRestButtonTitle, "Skip rest")
        XCTAssertEqual(state.setIndex, 2)
        XCTAssertEqual(state.setCount, 4)
    }

    func testContentStateUsesLocalizedExerciseDisplayNameNotRawCatalogName() throws {
        let originalLanguage = UserDefaults.standard.string(forKey: "app-language")
        addTeardownBlock {
            UserDefaults.standard.set(originalLanguage, forKey: "app-language")
        }
        UserDefaults.standard.set("uk", forKey: "app-language")

        let (history, active, _) = try makeStores(account: "bridge-localized-name")
        _ = try history.seedBuiltInExercises()
        let barbellRow = try XCTUnwrap(
            history.exercises.first { $0.catalogKey == "barbell_row" || $0.name == "Barbell Row" },
            "seedBuiltInExercises() must have added the Barbell Row catalog exercise"
        )
        let setID = UUID()
        let draft = try active.start(
            workoutDate: Date(),
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: barbellRow.id,
                    exerciseName: barbellRow.name,
                    exerciseCatalogKey: barbellRow.catalogKey,
                    sets: [ActiveWorkoutSet(id: setID, weight: 60, reps: 8)]
                )
            ],
            workoutStore: history,
            now: Date()
        )

        let state = WorkoutLiveActivityController.contentState(for: draft, workoutStore: history)

        XCTAssertEqual(
            state.exerciseName,
            gymExerciseName(barbellRow, languageCode: "uk"),
            "must show the localized display name, not the raw English catalog name"
        )
        XCTAssertNotEqual(state.exerciseName, "Barbell Row")
    }

    // MARK: - Idempotency regression tests (duplicate/replayed intent delivery)

    /// The core fix for the "one tap advanced many sets" data-integrity bug:
    /// a `LiveActivityIntent` invocation can be redelivered by the system
    /// (cold-launch retry, or — before both targets compiled the intent
    /// type — a tap queued while it couldn't route at all, replayed once it
    /// could). Replaying the exact same tap must record once, not cascade
    /// into the next set.
    func testReplayingSameRecordCurrentSetIntentTwiceRecordsOnlyOnce() throws {
        let (history, active, exercise) = try makeStores(account: "bridge-idempotent-record")
        let firstSetID = UUID()
        let secondSetID = UUID()
        let draft = try active.start(
            workoutDate: Date(),
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCatalogKey: exercise.catalogKey,
                    sets: [
                        ActiveWorkoutSet(id: firstSetID, weight: 60, reps: 8),
                        ActiveWorkoutSet(id: secondSetID, weight: 60, reps: 8)
                    ]
                )
            ],
            workoutStore: history,
            now: Date()
        )
        let controller = WorkoutLiveActivityController(requester: FakeLiveActivityRequester())
        controller.attach(workoutStore: history, activeWorkoutStore: active, restTimers: inertRestTimers())

        // Two invocations carrying the SAME setID — simulating a duplicate/
        // replayed delivery of one tap, not two separate taps.
        LiveActivityActionBridge.recordCurrentSet?(draft.id, firstSetID)
        LiveActivityActionBridge.recordCurrentSet?(draft.id, firstSetID)

        XCTAssertTrue(active.draft?.exercises.first?.sets.first?.isCompleted ?? false)
        XCTAssertFalse(
            active.draft?.exercises.first?.sets.last?.isCompleted ?? true,
            "a replayed invocation of the FIRST tap must not cascade into recording the next set too"
        )
    }

    /// A button rendered for a set that is no longer current (the store has
    /// already moved on) must never record — this is what makes a redelivered
    /// intent with a stale target safe, and also guards against a genuinely
    /// out-of-order tap.
    func testStaleSetIDIsNoOp() throws {
        let (history, active, exercise) = try makeStores(account: "bridge-stale-setid")
        let firstSetID = UUID()
        let secondSetID = UUID()
        let draft = try active.start(
            workoutDate: Date(),
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCatalogKey: exercise.catalogKey,
                    sets: [
                        ActiveWorkoutSet(id: firstSetID, weight: 60, reps: 8),
                        ActiveWorkoutSet(id: secondSetID, weight: 60, reps: 8)
                    ]
                )
            ],
            workoutStore: history,
            now: Date()
        )
        let controller = WorkoutLiveActivityController(requester: FakeLiveActivityRequester())
        controller.attach(workoutStore: history, activeWorkoutStore: active, restTimers: inertRestTimers())
        let revisionBefore = active.draft?.revision

        // A button drawn for the SECOND set (stale: the current set is
        // still the first) must not record the first set out of order.
        LiveActivityActionBridge.recordCurrentSet?(draft.id, secondSetID)

        XCTAssertEqual(active.draft?.revision, revisionBefore, "a setID that isn't the current set must no-op")
    }

    /// `SkipRestIntent` must never be able to record a set, no matter how
    /// many times it is (re)delivered — recording and resting are separate
    /// store operations and the skip path must stay on the rest-only one.
    func testSkipRestNeverRecordsASet() throws {
        let (history, active, exercise) = try makeStores(account: "bridge-skip-never-records")
        let setID = UUID()
        let draft = try active.start(
            workoutDate: Date(),
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCatalogKey: exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: setID, weight: 60, reps: 8)]
                )
            ],
            workoutStore: history,
            now: Date()
        )
        let controller = WorkoutLiveActivityController(requester: FakeLiveActivityRequester())
        controller.attach(workoutStore: history, activeWorkoutStore: active, restTimers: inertRestTimers())
        let started = try active.beginRest(
            draftID: draft.id,
            expectedRevision: try XCTUnwrap(active.draft?.revision),
            seconds: 60
        )
        let restEndsAt = try XCTUnwrap(started.timing?.restingUntil)

        LiveActivityActionBridge.skipRest?(draft.id, restEndsAt)
        // A replayed invocation of the same skip-rest tap must also never
        // record a set.
        LiveActivityActionBridge.skipRest?(draft.id, restEndsAt)

        XCTAssertNil(active.draft?.timing?.restingUntil, "rest should be over")
        XCTAssertFalse(
            active.draft?.exercises.first?.sets.first?.isCompleted ?? true,
            "skipping rest must never record a set"
        )
    }

    /// A skip-rest button rendered for a rest period that is no longer the
    /// running one (the store has already moved to a different rest) must
    /// not end the new, unrelated rest early.
    func testStaleRestTokenIsNoOp() throws {
        let (history, active, exercise) = try makeStores(account: "bridge-stale-rest-token")
        let draft = try active.start(
            workoutDate: Date(),
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    exerciseCatalogKey: exercise.catalogKey,
                    sets: [ActiveWorkoutSet(weight: 60, reps: 8)]
                )
            ],
            workoutStore: history,
            now: Date()
        )
        let controller = WorkoutLiveActivityController(requester: FakeLiveActivityRequester())
        controller.attach(workoutStore: history, activeWorkoutStore: active, restTimers: inertRestTimers())
        _ = try active.beginRest(
            draftID: draft.id,
            expectedRevision: try XCTUnwrap(active.draft?.revision),
            seconds: 60
        )
        let revisionBefore = active.draft?.revision
        // A rest end date this button was never drawn for (far in the past,
        // nowhere near the real rest end).
        let staleToken = Date().addingTimeInterval(-9999)

        LiveActivityActionBridge.skipRest?(draft.id, staleToken)

        XCTAssertEqual(
            active.draft?.revision,
            revisionBefore,
            "a restEndsAt that doesn't match the current rest must no-op"
        )
        XCTAssertNotNil(active.draft?.timing?.restingUntil, "rest must still be running")
    }
}
