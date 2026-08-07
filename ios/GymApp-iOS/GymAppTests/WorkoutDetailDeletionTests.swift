import Foundation
import XCTest
@testable import GymApp

@MainActor
final class WorkoutDetailDeletionTests: XCTestCase {
    func testAddingExerciseToExistingWorkoutInsertsAtTopWithoutRemovingHistory() throws {
        let store = try makeStore(account: "add-exercise-at-top")
        let existing = try store.addExercise(name: "Existing Row")
        let added = try store.addExercise(name: "New Top Row")
        let workout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: existing.id,
                    sets: [WorkoutSetDraft(weight: 40, reps: 8)]
                )
            ]
        )

        _ = try store.addExercise(
            toWorkout: workout.id,
            exerciseID: added.id,
            initialSet: WorkoutSetDraft(weight: 20, reps: 12)
        )

        let refreshed = try XCTUnwrap(store.workout(id: workout.id))
        XCTAssertEqual(refreshed.exercises.map(\.exerciseID), [added.id, existing.id])
        XCTAssertEqual(refreshed.exercises[1].sets.first?.weight, 40)
        XCTAssertEqual(store.exercises.map(\.id).contains(existing.id), true)
    }

    func testAddingExerciseRejectsDuplicateAtStoreBoundaryWithoutMutation() throws {
        let store = try makeStore(account: "add-exercise-duplicate")
        let exercise = try store.addExercise(name: "Unique Saved Row")
        let workout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_050),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [WorkoutSetDraft(weight: 40, reps: 8)]
                )
            ]
        )
        let storageBefore = try Data(contentsOf: store.storageURL)

        XCTAssertThrowsError(
            try store.addExercise(
                toWorkout: workout.id,
                exerciseID: exercise.id,
                initialSet: WorkoutSetDraft(weight: 45, reps: 6)
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkoutStoreError,
                .invalidWorkout("The exercise is already in this workout.")
            )
        }

        XCTAssertEqual(store.workout(id: workout.id), workout)
        XCTAssertEqual(try Data(contentsOf: store.storageURL), storageBefore)
    }

    func testSetDeletionTargetBindsExactStoreAccountAndSnapshot() throws {
        let store = try makeStore(account: "delete-target")
        let exercise = try store.addExercise(name: "Safety Squat")
        let workout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [
                        WorkoutSetDraft(weight: 80, reps: 5),
                        WorkoutSetDraft(weight: 82.5, reps: 5)
                    ]
                )
            ]
        )
        let block = try XCTUnwrap(workout.exercises.first)
        let set = try XCTUnwrap(block.sets.first)
        let target = WorkoutDetailDeletionTarget.set(
            store: store,
            workout: workout,
            block: block,
            set: set,
            position: 0,
            exerciseName: exercise.name
        )

        XCTAssertTrue(target.isCurrent(in: store, expectedWorkoutID: workout.id))
        XCTAssertEqual(target.impact, .setOnly)
        XCTAssertEqual(
            target.confirmationTitle(languageCode: "en"),
            "Delete set 1 from “Safety Squat”?"
        )
        XCTAssertEqual(
            target.confirmationTitle(languageCode: "uk"),
            "Видалити підхід 1 із «Safety Squat»?"
        )
        XCTAssertEqual(
            target.confirmationTitle(languageCode: "ru"),
            "Удалить подход 1 из «Safety Squat»?"
        )
        XCTAssertEqual(store.workout(id: workout.id)?.exercises.first?.sets.count, 2)

        let replacementStore = try makeStore(account: store.accountStorageKey)
        XCTAssertFalse(target.isCurrent(in: replacementStore, expectedWorkoutID: workout.id))
        XCTAssertFalse(target.isCurrent(in: store, expectedWorkoutID: UUID()))

        try store.updateSet(
            workoutID: workout.id,
            workoutExerciseID: block.id,
            setID: set.id,
            weight: 85,
            reps: 5
        )
        XCTAssertFalse(target.isCurrent(in: store, expectedWorkoutID: workout.id))
        XCTAssertEqual(store.workout(id: workout.id)?.exercises.first?.sets.count, 2)
    }

    func testFinalSetConfirmationDisclosesAndMatchesWorkoutCascade() throws {
        let store = try makeStore(account: "delete-final-set")
        let exercise = try store.addExercise(name: "Final Press")
        let workout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_100),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [WorkoutSetDraft(weight: 60, reps: 8)]
                )
            ]
        )
        let block = try XCTUnwrap(workout.exercises.first)
        let set = try XCTUnwrap(block.sets.first)
        let target = WorkoutDetailDeletionTarget.set(
            store: store,
            workout: workout,
            block: block,
            set: set,
            position: 0,
            exerciseName: exercise.name
        )

        XCTAssertEqual(target.impact, .setExerciseAndWorkout)
        XCTAssertEqual(
            target.confirmationMessage(languageCode: "en"),
            "This is the final set in the workout, so the exercise and the entire workout will also be deleted. Undo is available briefly while you stay on this screen."
        )
        XCTAssertEqual(
            target.confirmationMessage(languageCode: "uk"),
            "Це останній підхід у тренуванні, тому вправу й усе тренування також буде видалено. Скасування доступне протягом короткого часу, поки ти залишаєшся на цьому екрані."
        )
        XCTAssertEqual(
            target.confirmationMessage(languageCode: "ru"),
            "Это последний подход в тренировке, поэтому упражнение и вся тренировка также будут удалены. Отмена доступна в течение короткого времени, пока ты остаёшься на этом экране."
        )
        XCTAssertTrue(target.isCurrent(in: store, expectedWorkoutID: workout.id))

        try store.updateWorkout(id: workout.id, date: workout.date, note: "Changed after confirmation")
        XCTAssertFalse(target.isCurrent(in: store, expectedWorkoutID: workout.id))
        XCTAssertNotNil(store.workout(id: workout.id))

        let refreshedWorkout = try XCTUnwrap(store.workout(id: workout.id))
        let refreshedBlock = try XCTUnwrap(refreshedWorkout.exercises.first)
        let refreshedSet = try XCTUnwrap(refreshedBlock.sets.first)
        let refreshedTarget = WorkoutDetailDeletionTarget.set(
            store: store,
            workout: refreshedWorkout,
            block: refreshedBlock,
            set: refreshedSet,
            position: 0,
            exerciseName: exercise.name
        )
        XCTAssertTrue(refreshedTarget.isCurrent(in: store, expectedWorkoutID: workout.id))

        try store.deleteSet(
            workoutID: refreshedTarget.workoutID,
            workoutExerciseID: refreshedTarget.blockID,
            setID: try XCTUnwrap(refreshedTarget.setID)
        )

        XCTAssertNil(store.workout(id: workout.id))
    }

    func testExerciseConfirmationRevalidatesExactCascadeImpact() throws {
        let store = try makeStore(account: "delete-exercise-block")
        let first = try store.addExercise(name: "First Pull")
        let second = try store.addExercise(name: "Second Pull")
        let workout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_200),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: first.id,
                    sets: [WorkoutSetDraft(weight: 70, reps: 6)]
                ),
                WorkoutExerciseDraft(
                    exerciseID: second.id,
                    sets: [WorkoutSetDraft(weight: 40, reps: 10)]
                )
            ]
        )
        let block = try XCTUnwrap(workout.exercises.first)
        let target = WorkoutDetailDeletionTarget.exercise(
            store: store,
            workout: workout,
            block: block,
            exerciseName: first.name
        )

        XCTAssertEqual(target.impact, .exerciseOnly)
        XCTAssertEqual(
            target.confirmationTitle(languageCode: "ru"),
            "Удалить «First Pull» из этой тренировки?"
        )
        XCTAssertEqual(
            target.confirmationMessage(languageCode: "uk"),
            "Цю вправу та всі її підходи буде видалено з тренування. Скасування доступне протягом короткого часу, поки ти залишаєшся на цьому екрані."
        )
        XCTAssertTrue(target.isCurrent(in: store, expectedWorkoutID: workout.id))

        _ = try store.addSet(
            workoutID: workout.id,
            workoutExerciseID: block.id,
            weight: 72.5,
            reps: 6
        )

        XCTAssertFalse(target.isCurrent(in: store, expectedWorkoutID: workout.id))
        XCTAssertEqual(store.workout(id: workout.id)?.exercises.count, 2)
    }

    func testRemainingCascadeImpactBranchesAreExplicit() throws {
        let store = try makeStore(account: "delete-impact-branches")
        let first = try store.addExercise(name: "First")
        let second = try store.addExercise(name: "Second")
        let twoExerciseWorkout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_250),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: first.id,
                    sets: [WorkoutSetDraft(weight: 10, reps: 10)]
                ),
                WorkoutExerciseDraft(
                    exerciseID: second.id,
                    sets: [WorkoutSetDraft(weight: 20, reps: 10)]
                )
            ]
        )
        let firstBlock = try XCTUnwrap(twoExerciseWorkout.exercises.first)
        let firstSet = try XCTUnwrap(firstBlock.sets.first)
        let setTarget = WorkoutDetailDeletionTarget.set(
            store: store,
            workout: twoExerciseWorkout,
            block: firstBlock,
            set: firstSet,
            position: 0,
            exerciseName: first.name
        )
        XCTAssertEqual(setTarget.impact, .setAndExercise)

        let oneExerciseWorkout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_275),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: first.id,
                    sets: [WorkoutSetDraft(weight: 30, reps: 8)]
                )
            ]
        )
        let onlyBlock = try XCTUnwrap(oneExerciseWorkout.exercises.first)
        let exerciseTarget = WorkoutDetailDeletionTarget.exercise(
            store: store,
            workout: oneExerciseWorkout,
            block: onlyBlock,
            exerciseName: first.name
        )
        XCTAssertEqual(exerciseTarget.impact, .exerciseAndWorkout)
    }

    func testWholeWorkoutTargetRejectsStoreAndMetadataChanges() throws {
        let store = try makeStore(account: "delete-whole-workout")
        let exercise = try store.addExercise(name: "Whole Target")
        let workout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_280),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: exercise.id,
                    sets: [WorkoutSetDraft(weight: 50, reps: 5)]
                )
            ]
        )
        let target = WorkoutDetailWorkoutDeletionTarget(store: store, workout: workout)

        XCTAssertTrue(target.isCurrent(in: store, expectedWorkoutID: workout.id))
        let replacementStore = try makeStore(account: store.accountStorageKey)
        XCTAssertFalse(target.isCurrent(in: replacementStore, expectedWorkoutID: workout.id))

        try store.updateWorkout(id: workout.id, date: workout.date, note: "New note")
        XCTAssertFalse(target.isCurrent(in: store, expectedWorkoutID: workout.id))
        XCTAssertNotNil(store.workout(id: workout.id))
    }

    func testExerciseLibraryTargetBindsIdentityAndLinkedImpactBeforeCascade() throws {
        let store = try makeStore(account: "delete-library-exercise")
        let targetExercise = try store.addExercise(name: "Library Target")
        let retainedExercise = try store.addExercise(name: "Retained Exercise")
        let deletedWorkout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_300),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: targetExercise.id,
                    sets: [
                        WorkoutSetDraft(weight: 30, reps: 10),
                        WorkoutSetDraft(weight: 35, reps: 8)
                    ]
                )
            ]
        )
        let retainedWorkout = try store.createWorkout(
            date: Date(timeIntervalSince1970: 1_700_000_400),
            exercises: [
                WorkoutExerciseDraft(
                    exerciseID: targetExercise.id,
                    sets: [WorkoutSetDraft(weight: 40, reps: 6)]
                ),
                WorkoutExerciseDraft(
                    exerciseID: retainedExercise.id,
                    sets: [WorkoutSetDraft(weight: 20, reps: 12)]
                )
            ]
        )
        let target = ExerciseLibraryDeletionTarget(
            store: store,
            exercise: targetExercise,
            displayName: targetExercise.name
        )

        XCTAssertTrue(target.isCurrent(in: store))
        XCTAssertEqual(target.linkedWorkoutCount, 2)
        XCTAssertEqual(target.linkedSetCount, 3)
        XCTAssertEqual(target.deletedWorkoutCount, 1)
        XCTAssertEqual(target.restTimerIDs.count, 2)
        XCTAssertEqual(
            target.confirmationMessage(languageCode: "en"),
            "The exercise will be permanently deleted. Linked impact: 2 workouts; 3 sets; empty workouts deleted: 1 workout. This cannot be undone."
        )
        XCTAssertEqual(
            target.confirmationMessage(languageCode: "ru"),
            "Упражнение будет удалено навсегда. Связанные данные: 2 тренировки; 3 подхода; пустых тренировок будет удалено: 1 тренировка. Это действие нельзя отменить."
        )

        let replacementStore = try makeStore(account: store.accountStorageKey)
        XCTAssertFalse(target.isCurrent(in: replacementStore))
        XCTAssertFalse(
            target.isCurrent(
                in: store,
                activeStore: replacementStore,
                activeAccountStorageKey: store.accountStorageKey,
                isAccountReady: true
            )
        )
        XCTAssertFalse(
            target.isCurrent(
                in: store,
                activeStore: store,
                activeAccountStorageKey: "different-account",
                isAccountReady: true
            )
        )
        XCTAssertFalse(
            target.isCurrent(
                in: store,
                activeStore: store,
                activeAccountStorageKey: store.accountStorageKey,
                isAccountReady: false
            )
        )
        XCTAssertTrue(
            target.isCurrent(
                in: store,
                activeStore: store,
                activeAccountStorageKey: store.accountStorageKey,
                isAccountReady: true
            )
        )

        let retainedBlock = try XCTUnwrap(
            store.workout(id: retainedWorkout.id)?.exercises.first(where: {
                $0.exerciseID == targetExercise.id
            })
        )
        _ = try store.addSet(
            workoutID: retainedWorkout.id,
            workoutExerciseID: retainedBlock.id,
            weight: 42.5,
            reps: 6
        )

        XCTAssertFalse(target.isCurrent(in: store))
        XCTAssertNotNil(store.exercise(id: targetExercise.id))
        XCTAssertNotNil(store.workout(id: deletedWorkout.id))

        let refreshedExercise = try XCTUnwrap(store.exercise(id: targetExercise.id))
        let refreshed = ExerciseLibraryDeletionTarget(
            store: store,
            exercise: refreshedExercise,
            displayName: refreshedExercise.name
        )
        XCTAssertTrue(refreshed.isCurrent(in: store))

        try store.updateWorkout(
            id: deletedWorkout.id,
            date: deletedWorkout.date,
            note: "Changed before cascade"
        )
        XCTAssertFalse(refreshed.isCurrent(in: store))
        XCTAssertNotNil(store.workout(id: deletedWorkout.id))

        let metadataRefreshedExercise = try XCTUnwrap(store.exercise(id: targetExercise.id))
        let metadataRefreshed = ExerciseLibraryDeletionTarget(
            store: store,
            exercise: metadataRefreshedExercise,
            displayName: metadataRefreshedExercise.name
        )
        XCTAssertTrue(metadataRefreshed.isCurrent(in: store))

        try store.renameExercise(id: targetExercise.id, to: "Renamed Library Target")
        XCTAssertFalse(metadataRefreshed.isCurrent(in: store))

        let finalExercise = try XCTUnwrap(store.exercise(id: targetExercise.id))
        let finalTarget = ExerciseLibraryDeletionTarget(
            store: store,
            exercise: finalExercise,
            displayName: finalExercise.name
        )
        XCTAssertTrue(finalTarget.isCurrent(in: store))

        try store.deleteExercise(id: finalTarget.exerciseID, cascadeFromWorkouts: true)

        XCTAssertNil(store.exercise(id: targetExercise.id))
        XCTAssertNil(store.workout(id: deletedWorkout.id))
        XCTAssertEqual(store.workout(id: retainedWorkout.id)?.exercises.map(\.exerciseID), [retainedExercise.id])
    }

    func testExerciseLibraryTargetRejectsFavoriteChangeBeforeCascade() throws {
        let store = try makeStore(account: "delete-library-favorite")
        let exercise = try store.addExercise(name: "Favorite Target")
        let target = ExerciseLibraryDeletionTarget(
            store: store,
            exercise: exercise,
            displayName: exercise.name
        )

        XCTAssertTrue(target.isCurrent(in: store))
        XCTAssertTrue(try store.toggleExerciseFavorite(id: exercise.id))

        XCTAssertFalse(target.isCurrent(in: store))
        XCTAssertEqual(store.exercise(id: exercise.id)?.isFavorite, true)
    }

    func testExerciseLibraryTargetRejectsMuscleMappingChangeBeforeCascade() throws {
        let store = try makeStore(account: "delete-library-muscle-mapping")
        let exercise = try store.addExercise(name: "Mapping Target")
        try store.saveExerciseMuscleMapping(
            exerciseName: exercise.name,
            muscleIDs: ["chest"]
        )
        let target = ExerciseLibraryDeletionTarget(
            store: store,
            exercise: exercise,
            displayName: exercise.name
        )

        XCTAssertTrue(target.isCurrent(in: store))
        try store.saveExerciseMuscleMapping(
            exerciseName: exercise.name,
            muscleIDs: ["shoulders"]
        )

        XCTAssertFalse(target.isCurrent(in: store))
        XCTAssertNotNil(store.exercise(id: exercise.id))
        XCTAssertEqual(store.muscleMappings.map(\.muscleID), ["shoulders"])
    }

    private func makeStore(account: String) throws -> WorkoutStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GymApp-WorkoutDetailDeletionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return try WorkoutStore(accountStorageKey: account, directoryURL: directory)
    }
}
