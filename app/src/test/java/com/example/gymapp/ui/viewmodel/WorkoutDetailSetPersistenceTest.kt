package com.example.gymapp.ui.viewmodel

import com.example.gymapp.util.ExerciseRestTimerKey
import com.example.gymapp.util.ExerciseRestTimerLedger
import com.example.gymapp.util.ExerciseRestTimerPersistence
import com.example.gymapp.util.ExerciseRestTimerSnapshot
import java.util.concurrent.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutDetailSetPersistenceTest {
    @Test
    fun savedDetailSetPersistsWithoutStartingRestTimer() = runBlocking {
        val gate = PerExerciseSetAdditionGate()
        var persisted = false

        val result = persistWorkoutDetailSet(
            workoutExerciseId = 42L,
            gate = gate,
            persist = {
                persisted = true
            }
        )

        assertEquals(WorkoutDetailSetPersistenceResult.SetSaved, result)
        assertTrue(persisted)
    }

    @Test
    fun savedDetailSetPersistenceFailureIsReported() = runBlocking {
        val gate = PerExerciseSetAdditionGate()

        val result = persistWorkoutDetailSet(
            workoutExerciseId = 42L,
            gate = gate,
            persist = { error("database-private detail") }
        )

        assertEquals(WorkoutDetailSetPersistenceResult.PersistenceFailed, result)
    }

    @Test
    fun immediateDoubleInvocationCreatesOneSavedDetailSet() = runBlocking {
        val gate = PerExerciseSetAdditionGate()
        val firstPersistenceStarted = CompletableDeferred<Unit>()
        val releaseFirstPersistence = CompletableDeferred<Unit>()
        var persistedSetCount = 0

        val first = async {
            persistWorkoutDetailSet(
                workoutExerciseId = 42L,
                gate = gate,
                persist = {
                    firstPersistenceStarted.complete(Unit)
                    releaseFirstPersistence.await()
                    persistedSetCount += 1
                }
            )
        }
        firstPersistenceStarted.await()
        val duplicate = async {
            persistWorkoutDetailSet(
                workoutExerciseId = 42L,
                gate = gate,
                persist = { persistedSetCount += 1 }
            )
        }.await()
        releaseFirstPersistence.complete(Unit)

        assertEquals(WorkoutDetailSetPersistenceResult.AlreadyInFlight, duplicate)
        assertEquals(WorkoutDetailSetPersistenceResult.SetSaved, first.await())
        assertEquals(1, persistedSetCount)
    }

    @Test(expected = CancellationException::class)
    fun explicitPersistenceCancellationIsNotConvertedIntoFailure() {
        runBlocking {
            persistWorkoutDetailSet(
                workoutExerciseId = 42L,
                gate = PerExerciseSetAdditionGate(),
                persist = { throw CancellationException("database cancelled") }
            )
        }
    }

    @Test
    fun externalCancellationBeforeCommitCreatesNoSavedDetailSet() = runBlocking {
        val gate = PerExerciseSetAdditionGate()
        val persistenceStarted = CompletableDeferred<Unit>()
        var persistedSetCount = 0
        val operation = async {
            persistWorkoutDetailSet(
                workoutExerciseId = 42L,
                gate = gate,
                persist = {
                    persistenceStarted.complete(Unit)
                    awaitCancellation()
                    persistedSetCount += 1
                }
            )
        }
        persistenceStarted.await()

        operation.cancel()
        runCatching { operation.await() }

        assertEquals(0, persistedSetCount)
        assertTrue(gate.inFlight.value.isEmpty())
    }

    @Test
    fun immediateDuplicateExerciseAddPersistsOnce() = runBlocking {
        val gate = PerExerciseSetAdditionGate()
        val firstPersistenceStarted = CompletableDeferred<Unit>()
        val releaseFirstPersistence = CompletableDeferred<Unit>()
        var persistedExerciseCount = 0

        val first = async {
            persistWorkoutDetailExercise(exerciseId = 7L, gate = gate) {
                firstPersistenceStarted.complete(Unit)
                releaseFirstPersistence.await()
                persistedExerciseCount += 1
            }
        }
        firstPersistenceStarted.await()
        val duplicate = persistWorkoutDetailExercise(exerciseId = 7L, gate = gate) {
            persistedExerciseCount += 1
        }
        releaseFirstPersistence.complete(Unit)

        assertEquals(WorkoutDetailExercisePersistenceResult.AlreadyInFlight, duplicate)
        assertEquals(WorkoutDetailExercisePersistenceResult.ExerciseSaved, first.await())
        assertEquals(1, persistedExerciseCount)
        assertTrue(gate.inFlight.value.isEmpty())
    }

    @Test
    fun exerciseAddFailureIsBoundedAndReleasesGate() = runBlocking {
        val gate = PerExerciseSetAdditionGate()

        val result = persistWorkoutDetailExercise(exerciseId = 7L, gate = gate) {
            error("database-private detail")
        }

        assertEquals(WorkoutDetailExercisePersistenceResult.PersistenceFailed, result)
        assertTrue(gate.inFlight.value.isEmpty())
    }

    @Test
    fun durableDeadlineSurvivesControllerRecreationAndClearsOnAccountSwitch() {
        val persistence = InMemoryExerciseRestTimerPersistence()
        val firstAccount = "a".repeat(64)
        val secondAccount = "b".repeat(64)
        val key = ExerciseRestTimerKey(firstAccount, sessionId = 10L, workoutExerciseId = 42L)
        val first = ExerciseRestTimerLedger(persistence, nowMillis = { 10_000L })
        first.switchAccount(firstAccount)

        assertTrue(
            first.start(
                expectedAccountKey = firstAccount,
                sessionId = 10L,
                workoutExerciseId = 42L,
                seconds = 90
            )
        )
        assertEquals(100_000L, first.deadlines.value[key])

        val reopened = ExerciseRestTimerLedger(persistence, nowMillis = { 25_000L })
        reopened.switchAccount(firstAccount)
        assertEquals(100_000L, reopened.deadlines.value[key])

        reopened.switchAccount(secondAccount)
        assertTrue(reopened.deadlines.value.isEmpty())
        assertFalse(
            reopened.start(
                expectedAccountKey = firstAccount,
                sessionId = 10L,
                workoutExerciseId = 42L,
                seconds = 90
            )
        )
        val switchedBack = ExerciseRestTimerLedger(persistence, nowMillis = { 30_000L })
        switchedBack.switchAccount(firstAccount)
        assertTrue(switchedBack.deadlines.value.isEmpty())
    }

    private class InMemoryExerciseRestTimerPersistence : ExerciseRestTimerPersistence {
        private var snapshot = ExerciseRestTimerSnapshot(null, emptyMap())

        override fun load(): ExerciseRestTimerSnapshot = snapshot.copy(
            deadlines = snapshot.deadlines.toMap()
        )

        override fun save(snapshot: ExerciseRestTimerSnapshot): Boolean {
            this.snapshot = snapshot.copy(deadlines = snapshot.deadlines.toMap())
            return true
        }
    }
}
