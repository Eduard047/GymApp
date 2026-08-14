import Foundation
import UserNotifications
import XCTest
@testable import GymApp

@MainActor
final class ActiveWorkoutStoreTests: XCTestCase {
    func testOwnerReservationBlocksOrdinaryStartAcrossRelaunchWithoutMutation() throws {
        let context = try makeContext(account: "active-live-slot-restart")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let liveContext = LiveWorkoutSessionContext(
            userID: "11111111-1111-4111-8111-111111111111",
            sessionID: "22222222-2222-4222-8222-222222222222",
            accessToken: "synthetic-live-token"
        )
        let reservation = LiveWorkoutSlotReservation(
            version: 1,
            userID: liveContext.userID,
            sessionID: liveContext.sessionID,
            role: .owner,
            operationID: UUID(),
            roomID: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            phase: .waiting,
            createdAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 * 60)
        )
        try context.active.liveSlotReservationStore.reserve(
            reservation,
            context: liveContext,
            now: now
        ) { context.active.draft == nil }

        let exercise = ActiveWorkoutExercise(
            exerciseID: context.exercise.id,
            sets: [ActiveWorkoutSet(weight: 20, reps: 10)]
        )
        XCTAssertThrowsError(try context.active.start(
            workoutDate: now,
            note: nil,
            exercises: [exercise],
            workoutStore: context.history,
            now: now
        )) { XCTAssertEqual($0 as? ActiveWorkoutStoreError, .liveWorkoutReserved) }
        XCTAssertNil(context.active.draft)

        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        XCTAssertThrowsError(try reopened.start(
            workoutDate: now,
            note: nil,
            exercises: [exercise],
            workoutStore: context.history,
            now: now
        )) { XCTAssertEqual($0 as? ActiveWorkoutStoreError, .liveWorkoutReserved) }
        XCTAssertNil(reopened.draft)
        XCTAssertEqual(
            try reopened.liveSlotReservationStore.current(context: liveContext, now: now),
            reservation
        )
    }

    func testExpiredReservationReleasesButWrongSessionDoesNotMutate() throws {
        let context = try makeContext(account: "active-live-slot-expiry")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let liveContext = LiveWorkoutSessionContext(
            userID: "11111111-1111-4111-8111-111111111111",
            sessionID: "22222222-2222-4222-8222-222222222222",
            accessToken: "synthetic-live-token"
        )
        let reservation = LiveWorkoutSlotReservation(
            version: 1,
            userID: liveContext.userID,
            sessionID: liveContext.sessionID,
            role: .participant,
            operationID: UUID(),
            roomID: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            phase: .waiting,
            createdAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        try context.active.liveSlotReservationStore.reserve(
            reservation,
            context: liveContext,
            now: now
        ) { true }
        let wrongSession = LiveWorkoutSessionContext(
            userID: liveContext.userID,
            sessionID: "33333333-3333-4333-8333-333333333333",
            accessToken: "replacement-token"
        )
        XCTAssertThrowsError(
            try context.active.liveSlotReservationStore.current(
                context: wrongSession,
                now: now
            )
        ) { XCTAssertEqual($0 as? LiveWorkoutSlotReservationError, .sessionMismatch) }
        XCTAssertEqual(
            try context.active.liveSlotReservationStore.current(context: liveContext, now: now),
            reservation
        )

        let started = try context.active.start(
            workoutDate: now,
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    sets: [ActiveWorkoutSet(weight: 0, reps: 10)]
                )
            ],
            workoutStore: context.history,
            now: now.addingTimeInterval(61)
        )
        XCTAssertNotNil(started)
        XCTAssertNil(try context.active.liveSlotReservationStore.current(
            context: liveContext,
            now: now.addingTimeInterval(61)
        ))
    }

    func testAuthoritativeSessionRebindRequiresExactOperationAndPreservesAccount() throws {
        let context = try makeContext(account: "active-live-slot-session-rebind")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldContext = LiveWorkoutSessionContext(
            userID: "11111111-1111-4111-8111-111111111111",
            sessionID: "22222222-2222-4222-8222-222222222222",
            accessToken: "old-synthetic-token"
        )
        let newContext = LiveWorkoutSessionContext(
            userID: oldContext.userID,
            sessionID: "33333333-3333-4333-8333-333333333333",
            accessToken: "new-synthetic-token"
        )
        let previous = LiveWorkoutSlotReservation(
            version: 1,
            userID: oldContext.userID,
            sessionID: oldContext.sessionID,
            role: .participant,
            operationID: UUID(),
            roomID: "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            phase: .waiting,
            createdAt: now,
            expiresAt: now.addingTimeInterval(24 * 60 * 60)
        )
        let store = context.active.liveSlotReservationStore
        try store.reserve(previous, context: oldContext, now: now) { true }
        XCTAssertThrowsError(try store.reconcileAfterSessionChange(
            expectedOperationID: UUID(),
            with: nil,
            context: newContext
        ))
        XCTAssertEqual(try store.current(context: oldContext, now: now), previous)

        let rebound = LiveWorkoutSlotReservation(
            version: previous.version,
            userID: previous.userID,
            sessionID: newContext.sessionID,
            role: previous.role,
            operationID: previous.operationID,
            roomID: previous.roomID,
            phase: previous.phase,
            createdAt: previous.createdAt,
            expiresAt: previous.expiresAt
        )
        try store.reconcileAfterSessionChange(
            expectedOperationID: previous.operationID,
            with: rebound,
            context: newContext
        )
        XCTAssertEqual(try store.current(context: newContext, now: now), rebound)
    }

    func testRecoveredLiveStartDoesNotPublishDraftWhenBindingPersistenceFails() throws {
        let context = try makeContext(account: "active-live-binding-first")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let setID = UUID()
        let liveContext = LiveWorkoutSessionContext(
            userID: "11111111-1111-4111-8111-111111111111",
            sessionID: "22222222-2222-4222-8222-222222222222",
            accessToken: "synthetic-live-token"
        )
        let roomID = "lr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        try context.active.liveSlotReservationStore.reserve(
            LiveWorkoutSlotReservation(
                version: 1,
                userID: liveContext.userID,
                sessionID: liveContext.sessionID,
                role: .participant,
                operationID: UUID(),
                roomID: roomID,
                phase: .active,
                createdAt: startedAt,
                expiresAt: startedAt.addingTimeInterval(24 * 60 * 60)
            ),
            context: liveContext,
            now: startedAt
        ) { true }

        XCTAssertThrowsError(
            try context.active.startRecoveredLiveWorkout(
                startedAt: startedAt,
                exercises: [
                    ActiveWorkoutExercise(
                        exerciseID: context.exercise.id,
                        sets: [ActiveWorkoutSet(id: setID, weight: 80, reps: 8)]
                    )
                ],
                undoableSetID: nil,
                workoutStore: context.history,
                reservationContext: liveContext,
                roomID: roomID,
                now: startedAt,
                persistBindingBeforeCommit: { _ in throw SyntheticActiveStoreError() }
            )
        )
        XCTAssertNil(context.active.draft)
        XCTAssertTrue(context.history.workouts.isEmpty)
        XCTAssertNotNil(try context.active.liveSlotReservationStore.current(
            context: liveContext,
            now: startedAt
        ))
    }

    func testStartAndRecordPersistStableDraftAcrossRelaunch() throws {
        let context = try makeContext(account: "active-relaunch")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let blockID = UUID()
        let setID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: "  Local progress  ",
            exercises: [
                ActiveWorkoutExercise(
                    id: blockID,
                    exerciseID: context.exercise.id,
                    sets: [ActiveWorkoutSet(id: setID, weight: 82.5, reps: 8)]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )

        XCTAssertEqual(started.note, "Local progress")
        XCTAssertEqual(started.exercises.first?.id, blockID)
        XCTAssertEqual(started.exercises.first?.sets.first?.id, setID)
        XCTAssertFalse(try XCTUnwrap(started.exercises.first?.sets.first).isCompleted)

        let recorded = try context.active.recordSet(
            draftID: started.id,
            setID: setID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(45)
        )
        XCTAssertEqual(recorded.revision, 1)
        XCTAssertTrue(try XCTUnwrap(recorded.exercises.first?.sets.first).isCompleted)
        XCTAssertEqual(recorded.undoableSetID, setID)
        let storageValues = try context.active.storageURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(storageValues.isExcludedFromBackup, true)

        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        XCTAssertEqual(reopened.draft, recorded)
        XCTAssertNil(reopened.recoveryMessage)
        XCTAssertTrue(context.history.workouts.isEmpty)
    }

    func testTimingSidecarExcludesRestWhileDisplayedWorkoutTimeRemainsContinuousAcrossRelaunch() throws {
        let context = try makeContext(account: "active-stopwatch")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_050)
        let setID = UUID()
        let started = try startSingleSet(
            context,
            setID: setID,
            weight: 60,
            reps: 8,
            now: startedAt
        )

        let resting = try context.active.recordSet(
            draftID: started.id,
            setID: setID,
            expectedRevision: started.revision,
            restSeconds: 90,
            now: startedAt.addingTimeInterval(40)
        )
        XCTAssertEqual(resting.activeElapsedSeconds(at: startedAt.addingTimeInterval(70)), 40)
        XCTAssertEqual(resting.totalElapsedSeconds(at: startedAt.addingTimeInterval(70)), 70)

        let adjusted = try context.active.adjustRest(
            draftID: resting.id,
            expectedRevision: resting.revision,
            remainingSeconds: 120,
            now: startedAt.addingTimeInterval(70)
        )
        XCTAssertEqual(adjusted.activeElapsedSeconds(at: startedAt.addingTimeInterval(100)), 40)
        XCTAssertEqual(adjusted.totalElapsedSeconds(at: startedAt.addingTimeInterval(100)), 100)

        let resumed = try context.active.endRest(
            draftID: adjusted.id,
            expectedRevision: adjusted.revision,
            now: startedAt.addingTimeInterval(110)
        )
        XCTAssertEqual(resumed.activeElapsedSeconds(at: startedAt.addingTimeInterval(125)), 55)
        XCTAssertEqual(resumed.totalElapsedSeconds(at: startedAt.addingTimeInterval(125)), 125)

        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        let restored = try XCTUnwrap(reopened.draft)
        XCTAssertEqual(restored.activeElapsedSeconds(at: startedAt.addingTimeInterval(125)), 55)
        XCTAssertEqual(restored.totalElapsedSeconds(at: startedAt.addingTimeInterval(125)), 125)
    }

    func testRestProjectionReconcilesStartAdjustAndStopCrashWindows() throws {
        let context = try makeContext(account: "active-rest-reconciliation")
        let base = Date()
        let setID = UUID()
        let started = try startSingleSet(
            context,
            setID: setID,
            weight: 60,
            reps: 8,
            now: base
        )
        let resting = try context.active.recordSet(
            draftID: started.id,
            setID: setID,
            expectedRevision: started.revision,
            restSeconds: 90,
            now: base.addingTimeInterval(10)
        )
        let timerID = ActiveWorkoutRestReconciler.timerID(for: resting.id)
        let clock = ActiveWorkoutRestTestClock(base.addingTimeInterval(20))
        let defaults = makeRestTimerDefaults()
        let manager = RestTimerManager(
            notificationCenter: SilentActiveWorkoutRestNotifications(),
            defaults: defaults,
            currentDateProvider: { clock.date }
        )
        manager.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(
                for: context.history.accountStorageKey
            )
        )

        // Crash after committing the draft deadline but before writing the timer.
        XCTAssertNil(manager.timers[timerID])
        XCTAssertEqual(
            try ActiveWorkoutRestReconciler.reconcile(
                draft: resting,
                store: context.active,
                manager: manager,
                title: "Reconciliation test",
                now: clock.date
            ),
            .synchronized
        )
        XCTAssertEqual(manager.timers[timerID]?.endDate, resting.timing?.restingUntil)
        let reopenedAfterStart = RestTimerManager(
            notificationCenter: SilentActiveWorkoutRestNotifications(),
            defaults: defaults,
            currentDateProvider: { clock.date }
        )
        reopenedAfterStart.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(
                for: context.history.accountStorageKey
            )
        )
        XCTAssertEqual(reopenedAfterStart.timers[timerID]?.endDate, resting.timing?.restingUntil)

        // Crash after adjusting the draft while the durable timer still has the old deadline.
        clock.date = base.addingTimeInterval(30)
        let oldDeadline = manager.timers[timerID]?.endDate
        let adjusted = try context.active.adjustRest(
            draftID: resting.id,
            expectedRevision: resting.revision,
            remainingSeconds: 120,
            now: clock.date
        )
        XCTAssertNotEqual(adjusted.timing?.restingUntil, oldDeadline)
        XCTAssertEqual(manager.timers[timerID]?.endDate, oldDeadline)
        XCTAssertEqual(
            try ActiveWorkoutRestReconciler.reconcile(
                draft: adjusted,
                store: context.active,
                manager: manager,
                title: "Reconciliation test",
                now: clock.date
            ),
            .synchronized
        )
        XCTAssertEqual(manager.timers[timerID]?.endDate, adjusted.timing?.restingUntil)
        let reopenedAfterAdjust = RestTimerManager(
            notificationCenter: SilentActiveWorkoutRestNotifications(),
            defaults: defaults,
            currentDateProvider: { clock.date }
        )
        reopenedAfterAdjust.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(
                for: context.history.accountStorageKey
            )
        )
        XCTAssertEqual(reopenedAfterAdjust.timers[timerID]?.endDate, adjusted.timing?.restingUntil)

        // Crash after stopping rest in the draft while the timer remains durable.
        clock.date = base.addingTimeInterval(40)
        let resumed = try context.active.endRest(
            draftID: adjusted.id,
            expectedRevision: adjusted.revision,
            now: clock.date
        )
        XCTAssertNotNil(manager.timers[timerID])
        XCTAssertEqual(
            try ActiveWorkoutRestReconciler.reconcile(
                draft: resumed,
                store: context.active,
                manager: manager,
                title: "Reconciliation test",
                now: clock.date
            ),
            .synchronized
        )
        XCTAssertNil(manager.timers[timerID])

        let reopenedManager = RestTimerManager(
            notificationCenter: SilentActiveWorkoutRestNotifications(),
            defaults: defaults,
            currentDateProvider: { clock.date }
        )
        reopenedManager.bindToAccount(
            ownerFingerprint: RestTimerManager.ownerFingerprint(
                for: context.history.accountStorageKey
            )
        )
        XCTAssertNil(reopenedManager.timers[timerID])
    }

    func testUnavailableRestProjectionStopsRestWithoutRollingBackRecordedSet() throws {
        let context = try makeContext(account: "active-rest-projection-failure")
        let base = Date()
        let setID = UUID()
        let started = try startSingleSet(
            context,
            setID: setID,
            weight: 72.5,
            reps: 6,
            now: base
        )
        let resting = try context.active.recordSet(
            draftID: started.id,
            setID: setID,
            expectedRevision: started.revision,
            restSeconds: 90,
            now: base.addingTimeInterval(10)
        )
        let unboundManager = RestTimerManager(
            notificationCenter: SilentActiveWorkoutRestNotifications(),
            defaults: makeRestTimerDefaults(),
            currentDateProvider: { base.addingTimeInterval(20) }
        )

        XCTAssertEqual(
            try ActiveWorkoutRestReconciler.reconcile(
                draft: resting,
                store: context.active,
                manager: unboundManager,
                title: "Projection failure",
                now: base.addingTimeInterval(20)
            ),
            .timerCleanupPending
        )

        let recovered = try XCTUnwrap(context.active.draft)
        XCTAssertTrue(try XCTUnwrap(recovered.exercises.first?.sets.first).isCompleted)
        XCTAssertNil(recovered.timing?.restingUntil)
        XCTAssertEqual(recovered.timing?.activeSince, base.addingTimeInterval(20))
    }

    func testRecordAllSetsCommitsOneRevisionAndStopsExistingRest() throws {
        var writeCount = 0
        let context = try makeContext(
            account: "active-record-all",
            envelopeWriter: { data, url in
                writeCount += 1
                try data.write(
                    to: url,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            }
        )
        let startedAt = Date(timeIntervalSince1970: 1_800_000_075)
        let firstSetID = UUID()
        let secondSetID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    sets: [
                        ActiveWorkoutSet(id: firstSetID, weight: 80, reps: 8),
                        ActiveWorkoutSet(id: secondSetID, weight: 82.5, reps: 6)
                    ]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        let resting = try context.active.beginRest(
            draftID: started.id,
            expectedRevision: started.revision,
            seconds: 120,
            now: startedAt.addingTimeInterval(20)
        )
        let writesBeforeBatch = writeCount
        let completedAt = startedAt.addingTimeInterval(35)

        let completed = try context.active.recordAllSets(
            draftID: resting.id,
            expectedRevision: resting.revision,
            inputs: [
                firstSetID: ActiveWorkoutSetInput(weight: 81.5, reps: 7),
                secondSetID: ActiveWorkoutSetInput(weight: 84, reps: 5)
            ],
            now: completedAt
        )

        XCTAssertEqual(writeCount, writesBeforeBatch + 1)
        XCTAssertEqual(completed.revision, resting.revision + 1)
        XCTAssertEqual(completed.exercises[0].sets.map(\.weight), [81.5, 84])
        XCTAssertEqual(completed.exercises[0].sets.map(\.reps), [7, 5])
        XCTAssertEqual(completed.exercises[0].sets.map(\.completedAt), [completedAt, completedAt])
        XCTAssertNil(completed.undoableSetID)
        XCTAssertNil(completed.timing?.restingUntil)
        XCTAssertEqual(completed.timing?.activeSince, completedAt)
        XCTAssertEqual(completed.activeElapsedSeconds(at: completedAt.addingTimeInterval(10)), 30)
    }

    func testRecordAllSetsRollsBackMissingOrInvalidInputAndRejectsStaleRevision() throws {
        let context = try makeContext(account: "active-record-all-rollback")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_090)
        let firstSetID = UUID()
        let secondSetID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    sets: [
                        ActiveWorkoutSet(id: firstSetID, weight: 50, reps: 10),
                        ActiveWorkoutSet(id: secondSetID, weight: 55, reps: 8)
                    ]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        let originalData = try Data(contentsOf: context.active.storageURL)

        XCTAssertThrowsError(
            try context.active.recordAllSets(
                draftID: started.id,
                expectedRevision: started.revision,
                inputs: [firstSetID: ActiveWorkoutSetInput(weight: 52.5, reps: 9)],
                now: startedAt.addingTimeInterval(10)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .invalidDraft)
        }
        XCTAssertEqual(context.active.draft, started)
        XCTAssertEqual(try Data(contentsOf: context.active.storageURL), originalData)

        XCTAssertThrowsError(
            try context.active.recordAllSets(
                draftID: started.id,
                expectedRevision: started.revision,
                inputs: [
                    firstSetID: ActiveWorkoutSetInput(weight: 52.5, reps: 9),
                    secondSetID: ActiveWorkoutSetInput(weight: .infinity, reps: 7)
                ],
                now: startedAt.addingTimeInterval(11)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .invalidWeight)
        }
        XCTAssertEqual(context.active.draft, started)
        XCTAssertEqual(try Data(contentsOf: context.active.storageURL), originalData)

        let newer = try context.active.updateSet(
            draftID: started.id,
            setID: firstSetID,
            weight: 60,
            reps: 6,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(12)
        )
        let newerData = try Data(contentsOf: context.active.storageURL)
        XCTAssertThrowsError(
            try context.active.recordAllSets(
                draftID: started.id,
                expectedRevision: started.revision,
                inputs: [
                    firstSetID: ActiveWorkoutSetInput(weight: 61, reps: 5),
                    secondSetID: ActiveWorkoutSetInput(weight: 57.5, reps: 7)
                ],
                now: startedAt.addingTimeInterval(13)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .staleDraft)
        }
        XCTAssertEqual(context.active.draft, newer)
        XCTAssertEqual(try Data(contentsOf: context.active.storageURL), newerData)
        XCTAssertTrue(newer.exercises[0].sets.allSatisfy { !$0.isCompleted })
    }

    func testStaleRevisionIsRejectedWithoutMutatingRecordedSet() throws {
        let context = try makeContext(account: "active-stale")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let setID = UUID()
        let started = try startSingleSet(
            context,
            setID: setID,
            weight: 40,
            reps: 12,
            now: startedAt
        )
        let recorded = try context.active.recordSet(
            draftID: started.id,
            setID: setID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(30)
        )

        XCTAssertThrowsError(
            try context.active.updateSet(
                draftID: started.id,
                setID: setID,
                weight: 999,
                reps: 1,
                expectedRevision: started.revision,
                now: startedAt.addingTimeInterval(31)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .staleDraft)
        }
        XCTAssertEqual(context.active.draft, recorded)

        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        XCTAssertEqual(reopened.draft, recorded)
    }

    func testUndoRestoresOnlyLatestRecordedSetAndKeepsValues() throws {
        let context = try makeContext(account: "active-undo-latest")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_150)
        let firstSetID = UUID()
        let secondSetID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    sets: [
                        ActiveWorkoutSet(id: firstSetID, weight: 80, reps: 8),
                        ActiveWorkoutSet(id: secondSetID, weight: 82.5, reps: 7)
                    ]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        let first = try context.active.recordSet(
            draftID: started.id,
            setID: firstSetID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(10)
        )
        let second = try context.active.recordSet(
            draftID: started.id,
            setID: secondSetID,
            expectedRevision: first.revision,
            now: startedAt.addingTimeInterval(20)
        )

        XCTAssertThrowsError(
            try context.active.undoLatestRecordedSet(
                draftID: started.id,
                setID: firstSetID,
                expectedRevision: second.revision,
                now: startedAt.addingTimeInterval(21)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .setIsNotLatest)
        }
        let undone = try context.active.undoLatestRecordedSet(
            draftID: started.id,
            setID: secondSetID,
            expectedRevision: second.revision,
            now: startedAt.addingTimeInterval(22)
        )

        let sets = try XCTUnwrap(undone.exercises.first?.sets)
        XCTAssertTrue(sets[0].isCompleted)
        XCTAssertFalse(sets[1].isCompleted)
        XCTAssertEqual(sets[1].weight, 82.5)
        XCTAssertEqual(sets[1].reps, 7)
        XCTAssertNil(undone.undoableSetID)

        XCTAssertThrowsError(
            try context.active.undoLatestRecordedSet(
                draftID: started.id,
                setID: firstSetID,
                expectedRevision: undone.revision,
                now: startedAt.addingTimeInterval(23)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .setIsNotLatest)
        }
        XCTAssertEqual(context.active.draft, undone)
    }

    func testFinishKeepsOnlyCompletedSetsAndClearsLocalDraft() throws {
        let context = try makeContext(account: "active-finish")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_200)
        let blockID = UUID()
        let completedSetID = UUID()
        let plannedSetID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: "Partial session",
            exercises: [
                ActiveWorkoutExercise(
                    id: blockID,
                    exerciseID: context.exercise.id,
                    exerciseName: context.exercise.name,
                    exerciseCatalogKey: context.exercise.catalogKey,
                    sets: [
                        ActiveWorkoutSet(id: completedSetID, weight: 100, reps: 5),
                        ActiveWorkoutSet(id: plannedSetID, weight: 105, reps: 3)
                    ]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        let recorded = try context.active.recordSet(
            draftID: started.id,
            setID: completedSetID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(20)
        )

        let completed = try context.active.finish(
            draftID: recorded.id,
            expectedRevision: recorded.revision,
            into: context.history
        )

        XCTAssertEqual(completed.id, recorded.id)
        XCTAssertEqual(completed.exercises.first?.id, blockID)
        XCTAssertEqual(completed.exercises.first?.sets.map(\.id), [completedSetID])
        XCTAssertFalse(completed.exercises.first?.sets.contains(where: { $0.id == plannedSetID }) ?? true)
        XCTAssertEqual(context.history.workouts, [completed])
        XCTAssertNil(context.active.draft)

        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        XCTAssertNil(reopened.draft)
    }

    func testRepeatedExerciseBlocksRemainValidAndFinishSeparately() throws {
        let context = try makeContext(account: "active-repeated-exercise")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_300)
        let firstSetID = UUID()
        let secondSetID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    exerciseName: context.exercise.name,
                    exerciseCatalogKey: context.exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: firstSetID, weight: 60, reps: 8)]
                ),
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    exerciseName: context.exercise.name,
                    exerciseCatalogKey: context.exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: secondSetID, weight: 55, reps: 10)]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        let firstRecorded = try context.active.recordSet(
            draftID: started.id,
            setID: firstSetID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(10)
        )
        let secondRecorded = try context.active.recordSet(
            draftID: started.id,
            setID: secondSetID,
            expectedRevision: firstRecorded.revision,
            now: startedAt.addingTimeInterval(20)
        )
        let completed = try context.active.finish(
            draftID: started.id,
            expectedRevision: secondRecorded.revision,
            into: context.history
        )

        XCTAssertEqual(completed.exercises.count, 2)
        XCTAssertEqual(completed.exercises.map(\.exerciseID), [context.exercise.id, context.exercise.id])
    }

    func testSecondStartAndFinishWithoutCompletedSetsFailWithoutSideEffects() throws {
        let context = try makeContext(account: "active-singleton")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_350)
        let setID = UUID()
        let started = try startSingleSet(
            context,
            setID: setID,
            weight: 45,
            reps: 8,
            now: startedAt
        )

        XCTAssertThrowsError(
            try context.active.start(
                workoutDate: startedAt,
                note: nil,
                exercises: [
                    ActiveWorkoutExercise(
                        exerciseID: context.exercise.id,
                        sets: [ActiveWorkoutSet(weight: 50, reps: 5)]
                    )
                ],
                workoutStore: context.history,
                now: startedAt
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .alreadyActive)
        }
        XCTAssertThrowsError(
            try context.active.finish(
                draftID: started.id,
                expectedRevision: started.revision,
                into: context.history
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .noCompletedSets)
        }
        XCTAssertEqual(context.active.draft, started)
        XCTAssertTrue(context.history.workouts.isEmpty)
    }

    func testDiscardClearsDraftWithoutCreatingHistory() throws {
        let context = try makeContext(account: "active-discard")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_375)
        let setID = UUID()
        let started = try startSingleSet(
            context,
            setID: setID,
            weight: 35,
            reps: 10,
            now: startedAt
        )
        let recorded = try context.active.recordSet(
            draftID: started.id,
            setID: setID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(30)
        )

        try context.active.discard(
            draftID: recorded.id,
            expectedRevision: recorded.revision
        )

        XCTAssertNil(context.active.draft)
        XCTAssertTrue(context.history.workouts.isEmpty)
        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        XCTAssertNil(reopened.draft)
    }

    func testFinishRetryAfterHistoryWriteIsIdempotent() throws {
        let context = try makeContext(account: "active-finish-retry")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_390)
        let blockID = UUID()
        let setID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: "Retry",
            exercises: [
                ActiveWorkoutExercise(
                    id: blockID,
                    exerciseID: context.exercise.id,
                    exerciseName: context.exercise.name,
                    exerciseCatalogKey: context.exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: setID, weight: 70, reps: 6)]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        let recorded = try context.active.recordSet(
            draftID: started.id,
            setID: setID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(20)
        )
        let expectedWorkout = try context.history.commitActiveWorkout(
            ActiveWorkoutCommitIntent(
                workoutID: recorded.id,
                workoutDate: recorded.workoutDate,
                note: recorded.note,
                preparedAt: startedAt.addingTimeInterval(25),
                exercises: [
                    ActiveWorkoutCommitExercise(
                        id: blockID,
                        preferredExerciseID: context.exercise.id,
                        exerciseName: context.exercise.name,
                        exerciseCatalogKey: context.exercise.catalogKey,
                        sets: [WorkoutSet(id: setID, weight: 70, reps: 6)]
                    )
                ]
            ),
            expectedAccountStorageKey: context.history.accountStorageKey
        )

        let retried = try context.active.finish(
            draftID: recorded.id,
            expectedRevision: recorded.revision,
            into: context.history
        )

        XCTAssertEqual(retried, expectedWorkout)
        XCTAssertEqual(context.history.workouts, [expectedWorkout])
        XCTAssertNil(context.active.draft)
    }

    func testFinishAtomicallyRestoresExerciseDeletedAfterWorkoutStarted() throws {
        let context = try makeContext(account: "active-finish-restores-exercise")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_392)
        let setID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: "Deleted exercise recovery",
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    exerciseName: context.exercise.name,
                    exerciseCatalogKey: context.exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: setID, weight: 72.5, reps: 7)]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        let recorded = try context.active.recordSet(
            draftID: started.id,
            setID: setID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(30)
        )
        try context.history.deleteExercise(id: context.exercise.id)
        XCTAssertNil(context.history.exercise(id: context.exercise.id))

        let completed = try context.active.finish(
            draftID: recorded.id,
            expectedRevision: recorded.revision,
            into: context.history,
            now: startedAt.addingTimeInterval(40)
        )

        XCTAssertEqual(completed.exercises.first?.exerciseID, context.exercise.id)
        XCTAssertEqual(context.history.exercise(id: context.exercise.id)?.name, context.exercise.name)
        XCTAssertEqual(context.history.workouts, [completed])
        XCTAssertNil(context.active.draft)
    }

    func testCleanupFailureLocksCommitAgainstMutationAndRetryDoesNotDuplicate() throws {
        var activeWriteCount = 0
        let context = try makeContext(
            account: "active-locked-cleanup-retry",
            envelopeWriter: { data, url in
                activeWriteCount += 1
                if activeWriteCount == 4 {
                    throw InjectedFailure.cleanupWrite
                }
                try data.write(
                    to: url,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            }
        )
        let startedAt = Date(timeIntervalSince1970: 1_800_000_394)
        let completedSetID = UUID()
        let pendingSetID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: "Locked completion",
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    exerciseName: context.exercise.name,
                    exerciseCatalogKey: context.exercise.catalogKey,
                    sets: [
                        ActiveWorkoutSet(id: completedSetID, weight: 80, reps: 6),
                        ActiveWorkoutSet(id: pendingSetID, weight: 82.5, reps: 5)
                    ]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        let recorded = try context.active.recordSet(
            draftID: started.id,
            setID: completedSetID,
            expectedRevision: started.revision,
            now: startedAt.addingTimeInterval(20)
        )

        XCTAssertThrowsError(
            try context.active.finish(
                draftID: recorded.id,
                expectedRevision: recorded.revision,
                into: context.history,
                now: startedAt.addingTimeInterval(30)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .storageUnavailable)
        }
        let locked = try XCTUnwrap(context.active.draft)
        XCTAssertNotNil(locked.commitIntent)
        XCTAssertEqual(context.history.workouts.count, 1)
        XCTAssertEqual(context.history.workouts.first?.exercises.first?.sets.map(\.id), [completedSetID])

        XCTAssertThrowsError(
            try context.active.recordSet(
                draftID: locked.id,
                setID: pendingSetID,
                expectedRevision: locked.revision,
                now: startedAt.addingTimeInterval(31)
            )
        ) { error in
            XCTAssertEqual(error as? ActiveWorkoutStoreError, .workoutFinishing)
        }
        XCTAssertEqual(context.active.draft, locked)
        XCTAssertEqual(context.history.workouts.count, 1)

        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        let reopenedDraft = try XCTUnwrap(reopened.draft)
        XCTAssertNotNil(reopenedDraft.commitIntent)
        let retried = try reopened.finish(
            draftID: reopenedDraft.id,
            expectedRevision: reopenedDraft.revision,
            into: context.history,
            now: startedAt.addingTimeInterval(40)
        )
        XCTAssertEqual(retried, context.history.workouts.first)
        XCTAssertEqual(context.history.workouts.count, 1)
        XCTAssertNil(reopened.draft)
    }

    func testExerciseIdentityRebindSurvivesAuthoritativeUUIDReplacement() throws {
        let context = try makeContext(account: "active-rebind")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_395)
        let setID = UUID()
        let started = try context.active.start(
            workoutDate: startedAt,
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    exerciseName: context.exercise.name,
                    exerciseCatalogKey: context.exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: setID, weight: 65, reps: 8)]
                )
            ],
            workoutStore: context.history,
            now: startedAt
        )
        try context.history.clearAllData()
        let replacement = try context.history.addExercise(name: context.exercise.name)
        XCTAssertNotEqual(replacement.id, context.exercise.id)

        try context.active.rebindExercises(
            to: context.history,
            now: startedAt.addingTimeInterval(10)
        )
        let rebound = try XCTUnwrap(context.active.draft)
        XCTAssertEqual(rebound.id, started.id)
        XCTAssertEqual(rebound.exercises.first?.exerciseID, replacement.id)
        XCTAssertEqual(rebound.revision, started.revision + 1)

        let recorded = try context.active.recordSet(
            draftID: rebound.id,
            setID: setID,
            expectedRevision: rebound.revision,
            now: startedAt.addingTimeInterval(20)
        )
        let completed = try context.active.finish(
            draftID: recorded.id,
            expectedRevision: recorded.revision,
            into: context.history
        )
        XCTAssertEqual(completed.exercises.first?.exerciseID, replacement.id)
    }

    func testActiveDraftIsAbsentFromBackupUntilFinish() throws {
        let context = try makeContext(account: "active-backup")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_400)
        _ = try startSingleSet(
            context,
            setID: UUID(),
            weight: 30,
            reps: 10,
            now: startedAt
        )

        let backupData = try context.history.exportBackupData(
            owner: BackupOwner(accountID: context.history.accountStorageKey, remote: false)
        )
        let backup = try JSONDecoder().decode(GymBackup.self, from: backupData)
        XCTAssertTrue(backup.sessions.isEmpty)
        XCTAssertTrue(context.history.workouts.isEmpty)
        XCTAssertNotNil(context.active.draft)
    }

    func testWrongAccountEnvelopeIsQuarantinedWithoutExposure() throws {
        let directory = try temporaryDirectory()
        let accountA = try WorkoutStore(accountStorageKey: "active-account-a", directoryURL: directory)
        let exercise = try accountA.addExercise(name: "Account Isolation Press")
        let activeA = ActiveWorkoutStore(
            accountStorageKey: accountA.accountStorageKey,
            workoutStorageURL: accountA.storageURL
        )
        _ = try activeA.start(
            workoutDate: Date(timeIntervalSince1970: 1_800_000_500),
            note: "Private A",
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: exercise.id,
                    sets: [ActiveWorkoutSet(weight: 50, reps: 8)]
                )
            ],
            workoutStore: accountA,
            now: Date(timeIntervalSince1970: 1_800_000_500)
        )

        let accountB = try WorkoutStore(accountStorageKey: "active-account-b", directoryURL: directory)
        let accountBActiveURL = ActiveWorkoutStore.storageURL(
            forWorkoutStorageURL: accountB.storageURL
        )
        try FileManager.default.copyItem(at: activeA.storageURL, to: accountBActiveURL)
        let activeB = ActiveWorkoutStore(
            accountStorageKey: accountB.accountStorageKey,
            workoutStorageURL: accountB.storageURL
        )

        XCTAssertNil(activeB.draft)
        XCTAssertNotNil(activeB.recoveryMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountBActiveURL.path))
        XCTAssertNotNil(activeA.draft)
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains("active-workout.recovery-") }
        XCTAssertEqual(quarantined.count, 1)
    }

    func testOutOfRangeWeightIsRejectedDuringBoundedLoad() throws {
        let context = try makeContext(account: "active-malformed")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_600)
        _ = try startSingleSet(
            context,
            setID: UUID(),
            weight: 20,
            reps: 10,
            now: startedAt
        )

        let data = try Data(contentsOf: context.active.storageURL)
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var draft = try XCTUnwrap(root["draft"] as? [String: Any])
        var exercises = try XCTUnwrap(draft["exercises"] as? [[String: Any]])
        var firstExercise = try XCTUnwrap(exercises.first)
        var sets = try XCTUnwrap(firstExercise["sets"] as? [[String: Any]])
        sets[0]["weight"] = 1_000_001
        firstExercise["sets"] = sets
        exercises[0] = firstExercise
        draft["exercises"] = exercises
        root["draft"] = draft
        try JSONSerialization.data(withJSONObject: root).write(
            to: context.active.storageURL,
            options: .atomic
        )

        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        XCTAssertNil(reopened.draft)
        XCTAssertNotNil(reopened.recoveryMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.active.storageURL.path))
    }

    func testExcessiveJSONNestingIsRejectedBeforeTypedDecode() throws {
        let context = try makeContext(account: "active-nesting")
        let prefix = "{\"schemaVersion\":1,\"accountStorageKey\":\"active-nesting\",\"savedAt\":0,\"draft\":null,\"unknown\":"
        let nested = String(repeating: "{\"value\":", count: 20) +
            "0" + String(repeating: "}", count: 20)
        let payload = try XCTUnwrap((prefix + nested + "}").data(using: .utf8))
        try payload.write(to: context.active.storageURL, options: .atomic)

        let reopened = ActiveWorkoutStore(
            accountStorageKey: context.history.accountStorageKey,
            workoutStorageURL: context.history.storageURL
        )
        XCTAssertNil(reopened.draft)
        XCTAssertNotNil(reopened.recoveryMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.active.storageURL.path))
    }

    func testAccountFileCleanupAlsoRemovesActiveDraft() throws {
        let context = try makeContext(account: "active-cleanup")
        _ = try startSingleSet(
            context,
            setID: UUID(),
            weight: 25,
            reps: 15,
            now: Date(timeIntervalSince1970: 1_800_000_700)
        )
        let liveURL = LiveWorkoutSidecarStore.storageURL(
            forWorkoutStorageURL: context.history.storageURL
        )
        let liveRecoveryURL = liveURL
            .deletingPathExtension()
            .appendingPathExtension("recovery-\(UUID().uuidString.lowercased()).json")
        try Data("private live state".utf8).write(to: liveURL, options: .atomic)
        try Data("private recovery state".utf8).write(to: liveRecoveryURL, options: .atomic)
        let liveSlotURL = LiveWorkoutSlotReservationStore.storageURL(
            forWorkoutStorageURL: context.history.storageURL
        )
        let workoutInviteJournalURL = WorkoutInviteRequestStore.storageURL(
            forWorkoutStorageURL: context.history.storageURL
        )
        try Data("private live slot".utf8).write(to: liveSlotURL, options: .atomic)
        try Data("private invite retry state".utf8).write(
            to: workoutInviteJournalURL,
            options: .atomic
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.active.storageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveRecoveryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveSlotURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workoutInviteJournalURL.path))

        try WorkoutStore.destroyAccountFiles(
            accountStorageKey: context.history.accountStorageKey,
            directoryURL: context.directory
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: context.history.storageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.active.storageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveRecoveryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveSlotURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: workoutInviteJournalURL.path))
    }

    private struct Context {
        let directory: URL
        let history: WorkoutStore
        let active: ActiveWorkoutStore
        let exercise: Exercise
    }

    private enum InjectedFailure: Error {
        case cleanupWrite
    }

    private func makeContext(
        account: String,
        envelopeWriter: ((Data, URL) throws -> Void)? = nil
    ) throws -> Context {
        let directory = try temporaryDirectory()
        let history = try WorkoutStore(
            accountStorageKey: account,
            directoryURL: directory
        )
        let exercise = try history.addExercise(name: "Active Test Exercise \(UUID().uuidString)")
        let active = ActiveWorkoutStore(
            accountStorageKey: history.accountStorageKey,
            workoutStorageURL: history.storageURL,
            envelopeWriter: envelopeWriter
        )
        return Context(
            directory: directory,
            history: history,
            active: active,
            exercise: exercise
        )
    }

    private func startSingleSet(
        _ context: Context,
        setID: UUID,
        weight: Double,
        reps: Int,
        now: Date
    ) throws -> ActiveWorkoutDraft {
        try context.active.start(
            workoutDate: now,
            note: nil,
            exercises: [
                ActiveWorkoutExercise(
                    exerciseID: context.exercise.id,
                    exerciseName: context.exercise.name,
                    exerciseCatalogKey: context.exercise.catalogKey,
                    sets: [ActiveWorkoutSet(id: setID, weight: weight, reps: reps)]
                )
            ],
            workoutStore: context.history,
            now: now
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-active-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeRestTimerDefaults() -> UserDefaults {
        let suiteName = "GymApp-active-rest-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private struct SyntheticActiveStoreError: Error {}

@MainActor
private final class ActiveWorkoutRestTestClock {
    var date: Date

    init(_ date: Date) {
        self.date = date
    }
}

@MainActor
private final class SilentActiveWorkoutRestNotifications: RestNotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization() async -> Bool { false }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    func removeAllPendingNotificationRequests() {}
    func removeAllDeliveredNotifications() {}
}
