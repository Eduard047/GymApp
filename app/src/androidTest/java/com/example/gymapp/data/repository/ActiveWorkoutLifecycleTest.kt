package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ActiveWorkoutLifecycleTest {
    @Test
    fun zeroWeightPlanStartsActiveWithoutCreatingHistory() = runBlocking {
        withDatabase("active-workout-zero-weight") { database, repository ->
            val exerciseId = repository.addExercise("Synthetic bodyweight row")
            assertEquals(
                StartActiveWorkoutResult.Started,
                repository.startActiveWorkout(
                    date = NOW,
                    note = null,
                    workoutExercises = listOf(
                        WorkoutExerciseDraft(
                            exerciseId = exerciseId,
                            sets = listOf(WorkoutSetDraft(weight = 0.0, reps = 12))
                        )
                    )
                )
            )
            assertEquals(
                0.0,
                checkNotNull(repository.getActiveWorkoutSnapshot())
                    .exercises.single().sets.single().weight,
                0.0
            )
            assertEquals(0, database.workoutDao().getSessionCount())
            assertEquals(0, database.setDao().getTotalSetCount())
        }
    }

    @Test
    fun plannedSetsStayOutOfHistoryAndFinishCommitsOnlyCompletedSets() = runBlocking {
        withDatabase("active-workout-finish") { database, repository ->
            val exerciseId = repository.addExercise("Synthetic bench press")
            assertEquals(
                StartActiveWorkoutResult.Started,
                repository.startActiveWorkout(
                    date = NOW,
                    note = "synthetic active workout",
                    workoutExercises = listOf(
                        WorkoutExerciseDraft(
                            exerciseId = exerciseId,
                            sets = listOf(
                                WorkoutSetDraft(weight = 80.0, reps = 8),
                                WorkoutSetDraft(weight = 82.5, reps = 6)
                            )
                        )
                    )
                )
            )
            assertEquals(0, database.workoutDao().getSessionCount())
            assertEquals(0, database.setDao().getTotalSetCount())

            val initial = checkNotNull(repository.getActiveWorkoutSnapshot())
            val plannedSets = initial.exercises.single().sets
            assertEquals(2, plannedSets.size)
            assertNotEquals(plannedSets[0].id, plannedSets[1].id)
            assertNull(plannedSets[0].completedAt)
            assertEquals(
                FinishActiveWorkoutResult.NoCompletedSets,
                repository.finishActiveWorkout(expectedRevision = 0L)
            )
            assertNotNull(repository.getActiveWorkoutSnapshot())

            assertEquals(
                RecordActiveWorkoutSetResult.Recorded(revision = 1L),
                repository.recordActiveWorkoutSet(
                    setId = plannedSets[0].id,
                    expectedRevision = 0L,
                    weight = 81.0,
                    reps = 7
                )
            )
            assertEquals(0, database.workoutDao().getSessionCount())
            assertEquals(0, database.setDao().getTotalSetCount())
            assertEquals(
                RecordActiveWorkoutSetResult.AlreadyCompleted,
                repository.recordActiveWorkoutSet(
                    setId = plannedSets[0].id,
                    expectedRevision = 1L,
                    weight = 99.0,
                    reps = 1
                )
            )
            assertEquals(1L, repository.getActiveWorkoutSnapshot()?.activeWorkout?.revision)

            val finish = repository.finishActiveWorkout(expectedRevision = 1L)
            assertTrue(finish is FinishActiveWorkoutResult.Finished)
            val sessionId = (finish as FinishActiveWorkoutResult.Finished).sessionId
            val history = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            val savedSets = history.workoutExercises.single().sets
            assertEquals(1, savedSets.size)
            assertEquals(81.0, savedSets.single().weight, 0.0)
            assertEquals(7, savedSets.single().reps)
            assertNull(repository.getActiveWorkoutSnapshot())
        }
    }

    @Test
    fun activeWorkoutRestoresWithStableIdsAndRejectsStaleReplay() = runBlocking {
        withDatabase("active-workout-replay") { database, repository ->
            val exerciseId = repository.addExercise("Synthetic row")
            repository.startActiveWorkout(
                date = NOW,
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = exerciseId,
                        sets = listOf(
                            WorkoutSetDraft(weight = 40.0, reps = 10),
                            WorkoutSetDraft(weight = 42.0, reps = 8)
                        )
                    )
                )
            )
            val beforeRestart = checkNotNull(repository.getActiveWorkoutSnapshot())
            val restoredRepository = GymRepository(
                database = database,
                currentTimeMillis = { NOW + 1_000L }
            )
            val afterRestart = checkNotNull(restoredRepository.getActiveWorkoutSnapshot())
            assertEquals(
                beforeRestart.exercises.single().sets.map { it.id },
                afterRestart.exercises.single().sets.map { it.id }
            )

            val firstSet = afterRestart.exercises.single().sets[0]
            val secondSet = afterRestart.exercises.single().sets[1]
            assertEquals(
                RecordActiveWorkoutSetResult.Recorded(1L),
                restoredRepository.recordActiveWorkoutSet(firstSet.id, 0L, 40.0, 10)
            )
            assertEquals(
                RecordActiveWorkoutSetResult.Stale,
                restoredRepository.recordActiveWorkoutSet(secondSet.id, 0L, 42.0, 8)
            )
            val unchanged = checkNotNull(restoredRepository.getActiveWorkoutSnapshot())
            assertNull(unchanged.exercises.single().sets[1].completedAt)
            assertEquals(
                DiscardActiveWorkoutResult.Stale,
                restoredRepository.discardActiveWorkout(expectedRevision = 0L)
            )
            assertNotNull(restoredRepository.getActiveWorkoutSnapshot())
            assertEquals(
                DiscardActiveWorkoutResult.Discarded,
                restoredRepository.discardActiveWorkout(expectedRevision = 1L)
            )
            assertNull(restoredRepository.getActiveWorkoutSnapshot())
        }
    }

    @Test
    fun undoReopensOnlyTheNewestRecordedSetAndCannotCascadeToOlderSets() = runBlocking {
        withDatabase("active-workout-undo") { database, repository ->
            val exerciseId = repository.addExercise("Synthetic undo row")
            repository.startActiveWorkout(
                NOW,
                null,
                listOf(
                    WorkoutExerciseDraft(
                        exerciseId,
                        listOf(
                            WorkoutSetDraft(40.0, 10),
                            WorkoutSetDraft(42.0, 8)
                        )
                    )
                )
            )
            val sets = checkNotNull(repository.getActiveWorkoutSnapshot())
                .exercises.single().sets
            assertEquals(
                RecordActiveWorkoutSetResult.Recorded(1L),
                repository.recordActiveWorkoutSet(sets[0].id, 0L, 41.0, 9)
            )
            assertEquals(
                RecordActiveWorkoutSetResult.Recorded(2L),
                repository.recordActiveWorkoutSet(sets[1].id, 1L, 43.0, 7)
            )
            assertEquals(
                sets[1].id,
                repository.getActiveWorkoutSnapshot()?.activeWorkout?.undoableSetId
            )

            val restoredRepository = GymRepository(database, currentTimeMillis = { NOW })
            assertEquals(
                UndoActiveWorkoutSetResult.Undone(3L),
                restoredRepository.undoLatestActiveWorkoutSet(sets[1].id, 2L)
            )
            assertEquals(
                UndoActiveWorkoutSetResult.NotLatest,
                restoredRepository.undoLatestActiveWorkoutSet(sets[0].id, 3L)
            )

            val restored = checkNotNull(restoredRepository.getActiveWorkoutSnapshot())
            assertNull(restored.activeWorkout.undoableSetId)
            assertNotNull(restored.exercises.single().sets[0].completedAt)
            assertNull(restored.exercises.single().sets[1].completedAt)
            assertEquals(43.0, restored.exercises.single().sets[1].weight, 0.0)
            assertEquals(7, restored.exercises.single().sets[1].reps)
        }
    }

    @Test
    fun oneActiveWorkoutPerDatabaseAndCatalogReplacementDoesNotEraseDraft() = runBlocking {
        withDatabase("active-workout-isolation") { database, repository ->
            val exerciseId = repository.addExercise("Synthetic cable row")
            val originalPlan = listOf(
                WorkoutExerciseDraft(
                    exerciseId = exerciseId,
                    sets = listOf(WorkoutSetDraft(weight = 55.0, reps = 9))
                )
            )
            assertEquals(
                StartActiveWorkoutResult.Started,
                repository.startActiveWorkout(NOW, "first", originalPlan)
            )
            assertEquals(
                StartActiveWorkoutResult.AlreadyActive,
                repository.startActiveWorkout(NOW + 1_000L, "must not replace", originalPlan)
            )
            assertEquals("first", repository.getActiveWorkoutSnapshot()?.activeWorkout?.note)

            database.exerciseDao().deleteAllExercises()
            val activeAfterCatalogDelete = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(
                "Synthetic cable row",
                activeAfterCatalogDelete.exercises.single().activeWorkoutExercise.exerciseName
            )
            val setId = activeAfterCatalogDelete.exercises.single().sets.single().id
            assertTrue(
                repository.recordActiveWorkoutSet(setId, 0L, 56.0, 8) is
                    RecordActiveWorkoutSetResult.Recorded
            )
            val finished = repository.finishActiveWorkout(1L)
            assertTrue(finished is FinishActiveWorkoutResult.Finished)
            val session = checkNotNull(
                database.workoutDao().getSessionDetailsSnapshot(
                    (finished as FinishActiveWorkoutResult.Finished).sessionId
                )
            )
            assertEquals("Synthetic cable row", session.workoutExercises.single().exercise.name)
        }
    }

    @Test
    fun invalidNumbersFailBeforeMutatingActiveWorkout() = runBlocking {
        withDatabase("active-workout-bounds") { _, repository ->
            val exerciseId = repository.addExercise("Synthetic bounds")
            val invalidStart = runCatching {
                repository.startActiveWorkout(
                    NOW,
                    null,
                    listOf(
                        WorkoutExerciseDraft(
                            exerciseId,
                            listOf(WorkoutSetDraft(Double.NaN, 8))
                        )
                    )
                )
            }
            assertTrue(invalidStart.isFailure)
            assertNull(repository.getActiveWorkoutSnapshot())

            repository.startActiveWorkout(
                NOW,
                null,
                listOf(
                    WorkoutExerciseDraft(
                        exerciseId,
                        listOf(WorkoutSetDraft(20.0, 8))
                    )
                )
            )
            val snapshot = checkNotNull(repository.getActiveWorkoutSnapshot())
            val invalidRecord = runCatching {
                repository.recordActiveWorkoutSet(
                    snapshot.exercises.single().sets.single().id,
                    expectedRevision = 0L,
                    weight = Double.POSITIVE_INFINITY,
                    reps = 8
                )
            }
            assertTrue(invalidRecord.isFailure)
            val unchanged = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(0L, unchanged.activeWorkout.revision)
            assertFalse(unchanged.exercises.single().sets.single().completedAt != null)
        }
    }

    @Test
    fun bulkRecordRejectsChangedTargetsWithoutPartialWrites() = runBlocking {
        withDatabase("active-workout-bulk") { _, repository ->
            val exerciseId = repository.addExercise("Synthetic bulk row")
            repository.startActiveWorkout(
                NOW,
                null,
                listOf(
                    WorkoutExerciseDraft(
                        exerciseId,
                        listOf(
                            WorkoutSetDraft(40.0, 10),
                            WorkoutSetDraft(42.0, 8),
                            WorkoutSetDraft(44.0, 6)
                        )
                    )
                )
            )
            val sets = checkNotNull(repository.getActiveWorkoutSnapshot())
                .exercises.single().sets
            assertTrue(
                repository.recordActiveWorkoutSet(sets[0].id, 0L, 41.0, 9) is
                    RecordActiveWorkoutSetResult.Recorded
            )

            assertEquals(
                RecordActiveWorkoutSetsResult.AlreadyCompleted,
                repository.recordActiveWorkoutSets(
                    updates = listOf(
                        ActiveWorkoutSetUpdate(sets[0].id, 50.0, 5),
                        ActiveWorkoutSetUpdate(sets[1].id, 43.0, 7)
                    ),
                    expectedRevision = 1L
                )
            )
            var unchanged = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(1L, unchanged.activeWorkout.revision)
            assertNull(unchanged.exercises.single().sets[1].completedAt)

            assertEquals(
                RecordActiveWorkoutSetsResult.TargetChanged,
                repository.recordActiveWorkoutSets(
                    updates = listOf(
                        ActiveWorkoutSetUpdate(UUID.randomUUID().toString(), 43.0, 7),
                        ActiveWorkoutSetUpdate(sets[2].id, 45.0, 5)
                    ),
                    expectedRevision = 1L
                )
            )
            unchanged = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(1L, unchanged.activeWorkout.revision)
            assertNull(unchanged.exercises.single().sets[1].completedAt)
            assertNull(unchanged.exercises.single().sets[2].completedAt)

            val recorded = repository.recordActiveWorkoutSets(
                updates = listOf(
                    ActiveWorkoutSetUpdate(sets[1].id, 43.0, 7),
                    ActiveWorkoutSetUpdate(sets[2].id, 45.0, 5)
                ),
                expectedRevision = 1L
            )
            assertEquals(RecordActiveWorkoutSetsResult.Recorded(2L, 2), recorded)
            val completed = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(2L, completed.activeWorkout.revision)
            assertNull(completed.activeWorkout.undoableSetId)
            assertNotNull(completed.exercises.single().sets[1].completedAt)
            assertEquals(
                completed.exercises.single().sets[1].completedAt,
                completed.exercises.single().sets[2].completedAt
            )
        }
    }

    @Test
    fun exerciseAddedToSavedWorkoutMovesToTopWithoutChangingExistingHistory() = runBlocking {
        withDatabase("workout-add-exercise-top") { database, repository ->
            val firstExerciseId = repository.addExercise("Existing first exercise")
            val secondExerciseId = repository.addExercise("Existing second exercise")
            val newExerciseId = repository.addExercise("New top exercise")
            val sessionId = repository.createWorkoutSession(
                date = NOW,
                note = "preserve rows",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(firstExerciseId, listOf(WorkoutSetDraft(10.0, 10))),
                    WorkoutExerciseDraft(secondExerciseId, listOf(WorkoutSetDraft(20.0, 8)))
                )
            )
            val before = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            val existingSetIds = before.workoutExercises.flatMap { it.sets }.map { it.id }

            repository.addExerciseToSession(
                sessionId = sessionId,
                exerciseId = newExerciseId,
                initialWeight = 30.0,
                initialReps = 6
            )

            val after = checkNotNull(database.workoutDao().getSessionDetailsSnapshot(sessionId))
            assertEquals(newExerciseId, after.workoutExercises.first().exercise.id)
            assertEquals(listOf(0, 1, 2), after.workoutExercises.map { it.workoutExercise.orderIndex })
            assertTrue(after.workoutExercises.flatMap { it.sets }.map { it.id }.containsAll(existingSetIds))
            assertEquals("preserve rows", after.session.note)
        }
    }

    @Test
    fun accountScopedDatabasesCannotReadOrMutateEachOthersActiveWorkout() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val firstName = "active-workout-account-a-${UUID.randomUUID()}"
        val secondName = "active-workout-account-b-${UUID.randomUUID()}"
        val firstDatabase = GymDatabase.getInstance(context, firstName)
        val secondDatabase = GymDatabase.getInstance(context, secondName)
        try {
            val firstRepository = GymRepository(firstDatabase, currentTimeMillis = { NOW })
            val secondRepository = GymRepository(secondDatabase, currentTimeMillis = { NOW })
            val firstExerciseId = firstRepository.addExercise("Account A exercise")
            firstRepository.startActiveWorkout(
                NOW,
                "account A",
                listOf(
                    WorkoutExerciseDraft(
                        firstExerciseId,
                        listOf(WorkoutSetDraft(30.0, 10))
                    )
                )
            )
            val firstActive = checkNotNull(firstRepository.getActiveWorkoutSnapshot())
            assertNull(secondRepository.getActiveWorkoutSnapshot())
            assertEquals(
                RecordActiveWorkoutSetResult.Missing,
                secondRepository.recordActiveWorkoutSet(
                    setId = firstActive.exercises.single().sets.single().id,
                    expectedRevision = 0L,
                    weight = 30.0,
                    reps = 10
                )
            )
            assertNull(secondRepository.getActiveWorkoutSnapshot())
            assertEquals(0L, firstRepository.getActiveWorkoutSnapshot()?.activeWorkout?.revision)
        } finally {
            firstDatabase.close()
            secondDatabase.close()
            context.deleteDatabase(firstName)
            context.deleteDatabase(secondName)
        }
    }

    private suspend fun withDatabase(
        prefix: String,
        block: suspend (GymDatabase, GymRepository) -> Unit
    ) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "$prefix-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        try {
            block(database, GymRepository(database, currentTimeMillis = { NOW }))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    private companion object {
        const val NOW = 1_750_000_000_000L
    }
}
