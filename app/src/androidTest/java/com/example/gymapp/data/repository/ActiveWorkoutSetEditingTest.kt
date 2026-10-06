package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ActiveWorkoutSetEditingTest {
    private suspend fun start(
        repository: GymRepository,
        setsPerExercise: List<Int>
    ) {
        val drafts = setsPerExercise.mapIndexed { index, count ->
            WorkoutExerciseDraft(
                exerciseId = repository.addExercise("Synthetic exercise $index"),
                sets = List(count) { WorkoutSetDraft(weight = 40.0 + it, reps = 8) }
            )
        }
        assertEquals(
            StartActiveWorkoutResult.Started,
            repository.startActiveWorkout(date = NOW, note = null, workoutExercises = drafts)
        )
    }

    @Test
    fun nonCurrentSetCanBeRecordedAndCarriesWeightWithinItsExercise() = runBlocking {
        withDatabase("active-edit-record") { repository ->
            start(repository, listOf(2, 3))
            val initial = checkNotNull(repository.getActiveWorkoutSnapshot())
            val second = initial.exercises[1].sets.sortedBy { it.orderIndex }
            assertEquals(
                RecordActiveWorkoutSetResult.Recorded(revision = 1L),
                repository.recordActiveWorkoutSet(second[1].id, 0L, weight = 50.0, reps = 6)
            )
            val after = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(second[1].id, after.activeWorkout.undoableSetId)
            assertTrue(after.exercises[0].sets.all { it.completedAt == null })
            assertNotNull(after.exercises[1].sets.first { it.id == second[1].id }.completedAt)
        }
    }

    @Test
    fun deletingPendingSetRenumbersBumpsRevisionAndKeepsUndo() = runBlocking {
        withDatabase("active-edit-delete-set") { repository ->
            start(repository, listOf(3, 1))
            val initial = checkNotNull(repository.getActiveWorkoutSnapshot())
            val sets = initial.exercises[0].sets.sortedBy { it.orderIndex }
            assertEquals(
                RecordActiveWorkoutSetResult.Recorded(revision = 1L),
                repository.recordActiveWorkoutSet(sets[2].id, 0L, weight = 60.0, reps = 5)
            )
            assertEquals(
                DeleteActiveWorkoutSetResult.Deleted(revision = 2L),
                repository.deleteActiveWorkoutSet(sets[0].id, expectedRevision = 1L)
            )
            val after = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(2L, after.activeWorkout.revision)
            assertEquals(sets[2].id, after.activeWorkout.undoableSetId)
            val remaining = after.exercises[0].sets.sortedBy { it.orderIndex }
            assertEquals(listOf(sets[1].id, sets[2].id), remaining.map { it.id })
            assertEquals(listOf(0, 1), remaining.map { it.orderIndex })
        }
    }

    @Test
    fun deletingSetIsRejectedForStaleAndLastSet() = runBlocking {
        withDatabase("active-edit-delete-guards") { repository ->
            start(repository, listOf(2, 1))
            val initial = checkNotNull(repository.getActiveWorkoutSnapshot())
            val sets = initial.exercises[0].sets.sortedBy { it.orderIndex }
            val lone = initial.exercises[1].sets.single()
            assertEquals(
                DeleteActiveWorkoutSetResult.Stale,
                repository.deleteActiveWorkoutSet(sets[0].id, expectedRevision = 5L)
            )
            assertEquals(
                DeleteActiveWorkoutSetResult.LastSet,
                repository.deleteActiveWorkoutSet(lone.id, expectedRevision = 0L)
            )
            assertEquals(0L, repository.getActiveWorkoutSnapshot()?.activeWorkout?.revision)
        }
    }

    @Test
    fun deletingRecordedUndoTargetClearsUndoAndRenumbers() = runBlocking {
        withDatabase("active-edit-delete-recorded-target") { repository ->
            start(repository, listOf(3))
            val sets = checkNotNull(repository.getActiveWorkoutSnapshot())
                .exercises[0].sets.sortedBy { it.orderIndex }
            repository.recordActiveWorkoutSet(sets[0].id, 0L, weight = 40.0, reps = 8)
            assertEquals(
                DeleteActiveWorkoutSetResult.Deleted(revision = 2L, clearedUndo = true),
                repository.deleteActiveWorkoutSet(sets[0].id, expectedRevision = 1L)
            )
            val after = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertNull(after.activeWorkout.undoableSetId)
            val remaining = after.exercises[0].sets.sortedBy { it.orderIndex }
            assertEquals(listOf(sets[1].id, sets[2].id), remaining.map { it.id })
            assertEquals(listOf(0, 1), remaining.map { it.orderIndex })
        }
    }

    @Test
    fun deletingRecordedSetThatIsNotTheUndoTargetKeepsUndo() = runBlocking {
        withDatabase("active-edit-delete-recorded-other") { repository ->
            start(repository, listOf(3))
            val sets = checkNotNull(repository.getActiveWorkoutSnapshot())
                .exercises[0].sets.sortedBy { it.orderIndex }
            repository.recordActiveWorkoutSet(sets[0].id, 0L, weight = 40.0, reps = 8)
            repository.recordActiveWorkoutSet(sets[1].id, 1L, weight = 40.0, reps = 8)
            assertEquals(
                DeleteActiveWorkoutSetResult.Deleted(revision = 3L, clearedUndo = false),
                repository.deleteActiveWorkoutSet(sets[0].id, expectedRevision = 2L)
            )
            val after = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(sets[1].id, after.activeWorkout.undoableSetId)
            assertEquals(
                DeleteActiveWorkoutSetResult.Stale,
                repository.deleteActiveWorkoutSet(sets[2].id, expectedRevision = 2L)
            )
        }
    }

    @Test
    fun deletingTheLastRecordedSetOfAnExerciseIsRefused() = runBlocking {
        withDatabase("active-edit-delete-last-recorded") { repository ->
            start(repository, listOf(1, 1))
            val lone = checkNotNull(repository.getActiveWorkoutSnapshot()).exercises[0].sets.single()
            repository.recordActiveWorkoutSet(lone.id, 0L, weight = 40.0, reps = 8)
            assertEquals(
                DeleteActiveWorkoutSetResult.LastSet,
                repository.deleteActiveWorkoutSet(lone.id, expectedRevision = 1L)
            )
            assertEquals(lone.id, repository.getActiveWorkoutSnapshot()?.activeWorkout?.undoableSetId)
        }
    }

    @Test
    fun addingExerciseAppendsThreePendingSetsAndKeepsUndo() = runBlocking {
        withDatabase("active-edit-add-exercise") { repository ->
            start(repository, listOf(1))
            val first = checkNotNull(repository.getActiveWorkoutSnapshot()).exercises[0].sets.single()
            repository.recordActiveWorkoutSet(first.id, 0L, weight = 40.0, reps = 8)
            val added = repository.addExercise("Synthetic added")
            val result = repository.addActiveWorkoutExercise(added, expectedRevision = 1L)
            assertTrue(result is AddActiveWorkoutExerciseResult.Added)
            val after = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(2L, after.activeWorkout.revision)
            assertEquals(first.id, after.activeWorkout.undoableSetId)
            val appended = after.exercises.last()
            assertEquals("Synthetic added", appended.activeWorkoutExercise.exerciseName)
            assertEquals(1, appended.activeWorkoutExercise.orderIndex)
            val sets = appended.sets.sortedBy { it.orderIndex }
            assertEquals(listOf(0, 1, 2), sets.map { it.orderIndex })
            assertTrue(sets.all { it.completedAt == null && it.weight == 20.0 && it.reps == 10 })
        }
    }

    @Test
    fun addedExercisePrefillsFromLastLoggedSetAndRejectsStaleAndDuplicate() = runBlocking {
        withDatabase("active-edit-add-exercise-prefill") { repository ->
            start(repository, listOf(1))
            val added = repository.addExercise("Synthetic history")
            repository.createWorkoutSession(
                date = NOW - 86_400_000L,
                note = null,
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = added,
                        sets = listOf(WorkoutSetDraft(weight = 52.5, reps = 7))
                    )
                )
            )
            assertEquals(
                AddActiveWorkoutExerciseResult.Stale,
                repository.addActiveWorkoutExercise(added, expectedRevision = 9L)
            )
            assertTrue(
                repository.addActiveWorkoutExercise(added, expectedRevision = 0L)
                    is AddActiveWorkoutExerciseResult.Added
            )
            val sets = checkNotNull(repository.getActiveWorkoutSnapshot())
                .exercises.last().sets
            assertEquals(3, sets.size)
            assertTrue(sets.all { it.weight == 52.5 && it.reps == 7 })
            assertEquals(
                AddActiveWorkoutExerciseResult.AlreadyInWorkout,
                repository.addActiveWorkoutExercise(added, expectedRevision = 1L)
            )
            assertEquals(1L, repository.getActiveWorkoutSnapshot()?.activeWorkout?.revision)
        }
    }

    @Test
    fun removingExerciseWithRecordedSetsRenumbersAndClearsOwnedUndo() = runBlocking {
        withDatabase("active-edit-remove-exercise") { repository ->
            start(repository, listOf(2, 2, 1))
            val initial = checkNotNull(repository.getActiveWorkoutSnapshot())
            val middle = initial.exercises[1]
            repository.recordActiveWorkoutSet(middle.sets.minBy { it.orderIndex }.id, 0L, 70.0, 5)
            val result = repository.removeActiveWorkoutExercise(
                middle.activeWorkoutExercise.id,
                expectedRevision = 1L
            )
            assertEquals(
                RemoveActiveWorkoutExerciseResult.Removed(
                    revision = 2L,
                    removedRecordedSets = 1,
                    clearedUndo = true
                ),
                result
            )
            val after = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertNull(after.activeWorkout.undoableSetId)
            assertEquals(listOf(0, 1), after.exercises.map { it.activeWorkoutExercise.orderIndex }
                .sorted())
            assertTrue(after.exercises.none { it.activeWorkoutExercise.id == middle.activeWorkoutExercise.id })
        }
    }

    @Test
    fun removingExerciseKeepsUndoOfAnotherExerciseAndRejectsStaleAndLast() = runBlocking {
        withDatabase("active-edit-remove-guards") { repository ->
            start(repository, listOf(1, 1))
            val initial = checkNotNull(repository.getActiveWorkoutSnapshot())
            val first = initial.exercises[0]
            val second = initial.exercises[1]
            repository.recordActiveWorkoutSet(first.sets.single().id, 0L, 40.0, 8)
            assertEquals(
                RemoveActiveWorkoutExerciseResult.Stale,
                repository.removeActiveWorkoutExercise(second.activeWorkoutExercise.id, 0L)
            )
            assertEquals(
                RemoveActiveWorkoutExerciseResult.Removed(2L, removedRecordedSets = 0, clearedUndo = false),
                repository.removeActiveWorkoutExercise(second.activeWorkoutExercise.id, 1L)
            )
            val after = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(first.sets.single().id, after.activeWorkout.undoableSetId)
            assertEquals(
                RemoveActiveWorkoutExerciseResult.LastExercise,
                repository.removeActiveWorkoutExercise(first.activeWorkoutExercise.id, 2L)
            )
        }
    }

    private suspend fun withDatabase(prefix: String, block: suspend (GymRepository) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "$prefix-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        try {
            block(GymRepository(database, currentTimeMillis = { NOW }))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    private companion object {
        const val NOW = 1_750_000_000_000L
    }
}
