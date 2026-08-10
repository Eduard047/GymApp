package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.auth.LiveCanonicalExercise
import com.example.gymapp.auth.LiveCanonicalPlan
import com.example.gymapp.auth.LiveCanonicalSet
import com.example.gymapp.auth.LiveCompletedSet
import com.example.gymapp.auth.LiveProgress
import com.example.gymapp.data.database.GymDatabase
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiveWorkoutImportAtomicityTest {
    @Test
    fun canonicalPlanAndServerSetMappingAreCreatedAtomically() = runBlocking {
        withDatabase("live-import") { database ->
            val repository = GymRepository(database, currentTimeMillis = { NOW })

            val result = repository.startLiveCanonicalWorkout(plan(), NOW)

            assertTrue(result is StartLiveCanonicalWorkoutResult.Started)
            val started = result as StartLiveCanonicalWorkoutResult.Started
            assertEquals(setOf("s_01_01", "s_01_02"), started.serverToLocalSetIds.keys)
            assertEquals(2, started.serverToLocalSetIds.values.toSet().size)
            val active = checkNotNull(repository.getActiveWorkoutSnapshot())
            assertEquals(
                started.serverToLocalSetIds.values.toSet(),
                active.exercises.flatMap { it.sets }.map { it.id }.toSet()
            )
            assertEquals(0, database.workoutDao().getSessionCount())
            assertEquals(0, database.setDao().getTotalSetCount())
        }
    }

    @Test
    fun identifierGenerationFailureRollsBackCatalogAndActiveRows() = runBlocking {
        withDatabase("live-import-rollback") { database ->
            val repeatedId = "12345678-1234-4123-8123-123456789abc"
            val repository = GymRepository(
                database = database,
                currentTimeMillis = { NOW },
                stableIdFactory = { repeatedId }
            )

            val failure = runCatching {
                repository.startLiveCanonicalWorkout(plan(), NOW)
            }.exceptionOrNull()

            assertNotNull(failure)
            assertNull(repository.getActiveWorkoutSnapshot())
            assertFalse(
                database.exerciseDao().getExercisesSnapshot().any {
                    it.name == "Synthetic live press"
                }
            )
        }
    }

    @Test
    fun sidecarPersistenceFailureRollsBackCatalogAndActiveRows() = runBlocking {
        withDatabase("live-import-sidecar-rollback") { database ->
            val repository = GymRepository(database, currentTimeMillis = { NOW })
            var persistenceAttempts = 0

            val failure = runCatching {
                repository.startLiveCanonicalWorkout(plan(), NOW) {
                    persistenceAttempts += 1
                    false
                }
            }.exceptionOrNull()

            assertNotNull(failure)
            assertEquals(1, persistenceAttempts)
            assertNull(repository.getActiveWorkoutSnapshot())
            assertFalse(
                database.exerciseDao().getExercisesSnapshot().any {
                    it.name == "Synthetic live press"
                }
            )
        }
    }

    @Test
    fun reconnectImportMirrorsCanonicalOwnProgress() = runBlocking {
        withDatabase("live-import-progress") { database ->
            val repository = GymRepository(database, currentTimeMillis = { NOW })
            val progress = LiveProgress(
                revision = 2,
                completedSets = listOf(
                    LiveCompletedSet(
                        setId = "s_01_01",
                        weight = 85.0,
                        reps = 5,
                        completedAt = Instant.ofEpochMilli(NOW + 1_000L).toString()
                    )
                ),
                undoableSetId = "s_01_01",
                finishedAt = null
            )

            val started = repository.startLiveCanonicalWorkout(
                plan = plan(),
                startedAt = NOW,
                initialProgress = progress
            ) as StartLiveCanonicalWorkoutResult.Started

            val active = checkNotNull(repository.getActiveWorkoutSnapshot())
            val first = active.exercises.single().sets.first()
            assertEquals(1L, active.activeWorkout.revision)
            assertEquals(started.serverToLocalSetIds.getValue("s_01_01"), first.id)
            assertEquals(first.id, active.activeWorkout.undoableSetId)
            assertEquals(85.0, first.weight, 0.0)
            assertEquals(5, first.reps)
            assertEquals(NOW + 1_000L, first.completedAt)
            assertNull(active.exercises.single().sets.last().completedAt)
        }
    }

    private fun plan() = LiveCanonicalPlan(
        listOf(
            LiveCanonicalExercise(
                exerciseId = "e_01",
                name = "Synthetic live press",
                catalogKey = null,
                sets = listOf(
                    LiveCanonicalSet("s_01_01", 80.0, 8),
                    LiveCanonicalSet("s_01_02", 82.5, 6)
                )
            )
        )
    )

    private suspend fun withDatabase(prefix: String, block: suspend (GymDatabase) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "$prefix-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, name)
        try {
            block(database)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

    private companion object {
        const val NOW = 1_786_330_800_000L
    }
}
