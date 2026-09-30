package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.entity.ActiveWorkoutEntity
import com.example.gymapp.data.entity.ActiveWorkoutExerciseEntity
import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Locks in that active workout block and set identifiers stay unique and well formed. */
@RunWith(AndroidJUnit4::class)
class ActiveWorkoutIdentityTest {
    private val idA = "11111111-1111-4111-8111-111111111111"
    private val idB = "22222222-2222-4222-8222-222222222222"
    private val idC = "33333333-3333-4333-8333-333333333333"

    @Test
    fun idGenerationSkipsCollidingAndMalformedCandidates() = runBlocking {
        val candidates = ArrayDeque(listOf(idA, idA, idB, "not-a-uuid", idC, idA, idB, idC))
        withDatabase("active-identity-retry", { candidates.removeFirst() }) { _, repository ->
            val exerciseId = repository.addExercise("Synthetic identity row")
            assertEquals(StartActiveWorkoutResult.Started, repository.startActiveWorkout(NOW, null, plan(exerciseId)))

            val active = checkNotNull(repository.getActiveWorkoutSnapshot())
            val block = active.exercises.single()
            val ids = listOf(block.activeWorkoutExercise.id) + block.sets.map { it.id }
            assertEquals(listOf(idA, idB, idC), ids)
            assertEquals(ids.size, ids.toSet().size)
        }
    }

    @Test
    fun idGenerationThatKeepsCollidingFailsWithoutStoringAnActiveWorkout() = runBlocking {
        withDatabase("active-identity-exhausted", { idA }) { _, repository ->
            val exerciseId = repository.addExercise("Synthetic identity row")

            val failure = runCatching {
                repository.startActiveWorkout(NOW, null, plan(exerciseId))
            }.exceptionOrNull()

            assertNotNull(failure)
            assertNull(repository.getActiveWorkoutSnapshot())
        }
    }

    @Test
    fun storedBlockAndSetSharingAnIdFailsValidation() = runBlocking {
        withDatabase("active-identity-shared-id") { database, repository ->
            seedStoredWorkout(database, blockId = idA, setId = idA)

            val failure = runCatching {
                repository.recordActiveWorkoutSet(setId = idA, expectedRevision = 0L, weight = 40.0, reps = 10)
            }.exceptionOrNull()

            assertNotNull(failure)
            assertTrue(failure is IllegalArgumentException)
            assertNull(checkNotNull(repository.getActiveWorkoutSnapshot()).exercises.single().sets.single().completedAt)
        }
    }

    @Test
    fun storedMalformedIdFailsValidation() = runBlocking {
        withDatabase("active-identity-malformed") { database, repository ->
            seedStoredWorkout(database, blockId = idA, setId = "set-1")

            val failure = runCatching {
                repository.recordActiveWorkoutSet(setId = "set-1", expectedRevision = 0L, weight = 40.0, reps = 10)
            }.exceptionOrNull()

            assertNotNull(failure)
            assertTrue(failure is IllegalArgumentException)
        }
    }

    @Test
    fun storedWorkoutWithDistinctIdsPassesValidation() = runBlocking {
        withDatabase("active-identity-control") { database, repository ->
            seedStoredWorkout(database, blockId = idA, setId = idB)

            assertEquals(
                RecordActiveWorkoutSetResult.Recorded(revision = 1L),
                repository.recordActiveWorkoutSet(setId = idB, expectedRevision = 0L, weight = 40.0, reps = 10)
            )
        }
    }

    private fun plan(exerciseId: Long) = listOf(
        WorkoutExerciseDraft(
            exerciseId = exerciseId,
            sets = listOf(
                WorkoutSetDraft(weight = 40.0, reps = 10),
                WorkoutSetDraft(weight = 42.0, reps = 8)
            )
        )
    )

    // Two rows in one table cannot share a primary key, so shared ids can only be stored across
    // the block and set tables; the validator must still reject them.
    private suspend fun seedStoredWorkout(database: GymDatabase, blockId: String, setId: String) {
        val dao = database.activeWorkoutDao()
        dao.insert(
            ActiveWorkoutEntity(
                id = 1L,
                date = NOW,
                note = null,
                startedAt = NOW,
                revision = 0L,
                undoableSetId = null
            )
        )
        dao.insertExercises(
            listOf(
                ActiveWorkoutExerciseEntity(
                    id = blockId,
                    activeWorkoutId = 1L,
                    exerciseName = "Synthetic identity row",
                    catalogKey = null,
                    orderIndex = 0
                )
            )
        )
        dao.insertSets(
            listOf(
                ActiveWorkoutSetEntity(
                    id = setId,
                    activeWorkoutExerciseId = blockId,
                    weight = 40.0,
                    reps = 10,
                    orderIndex = 0,
                    completedAt = null
                )
            )
        )
    }

    private suspend fun withDatabase(
        prefix: String,
        stableIdFactory: () -> String = { UUID.randomUUID().toString() },
        block: suspend (GymDatabase, GymRepository) -> Unit
    ) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "$prefix-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        try {
            block(
                database,
                GymRepository(database, currentTimeMillis = { NOW }, stableIdFactory = stableIdFactory)
            )
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    private companion object {
        const val NOW = 1_750_000_000_000L
    }
}
