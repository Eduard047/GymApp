package com.example.gymapp.util

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.databaseName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RestTimerOwnerCleanupTest {
    @Test
    fun cloudTimerOwnerIncludesSessionGenerationAndCanBeRebuiltAfterRestart() {
        val session = cloudSession(USER_A, GENERATION_A)
        val sameOwnerNewLogin = cloudSession(USER_A, GENERATION_B)

        val accountKey = restTimerAccountKey(session)
        assertEquals(
            accountKey,
            restTimerAccountKey(session.databaseName(), session.sessionGeneration)
        )
        assertNotEquals(accountKey, restTimerAccountKey(sameOwnerNewLogin))
    }

    @Test
    fun ownerCleanupClearsOnlyMatchingExerciseAndActiveWorkoutSidecars() {
        val exerciseKey = ExerciseRestTimerKey(ACCOUNT_A, sessionId = 7L, workoutExerciseId = 9L)
        val exercisePersistence = MemoryExerciseTimerPersistence(
            ExerciseRestTimerSnapshot(ACCOUNT_A, mapOf(exerciseKey to 90_000L))
        )
        val activePersistence = MemoryActiveTimerPersistence(
            ActiveWorkoutTimerSnapshot(
                accountKey = ACCOUNT_A,
                sessionStartedAt = 10_000L,
                accumulatedActiveMillis = 0L,
                activeSegmentStartedAt = 10_000L,
                restEndsAt = null
            )
        )
        val exerciseLedger = ExerciseRestTimerLedger(exercisePersistence, nowMillis = { 20_000L })
        val activeLedger = ActiveWorkoutTimerLedger(activePersistence, nowMillis = { 20_000L })

        assertTrue(exerciseLedger.clearAccount(ACCOUNT_B))
        assertTrue(activeLedger.clearAccount(ACCOUNT_B))
        assertEquals(ACCOUNT_A, exercisePersistence.load().accountKey)
        assertEquals(ACCOUNT_A, activePersistence.load()?.accountKey)

        assertTrue(exerciseLedger.clearAccount(ACCOUNT_A))
        assertTrue(activeLedger.clearAccount(ACCOUNT_A))
        assertNull(exercisePersistence.load().accountKey)
        assertNull(activePersistence.load())
    }

    @Test
    fun activeOwnerCleanupPublishesEmptyStateOnlyAfterPersistenceSucceeds() {
        val exercisePersistence = MemoryExerciseTimerPersistence()
        val activePersistence = MemoryActiveTimerPersistence()
        val exerciseLedger = ExerciseRestTimerLedger(exercisePersistence, nowMillis = { 10_000L })
        val activeLedger = ActiveWorkoutTimerLedger(activePersistence, nowMillis = { 10_000L })
        exerciseLedger.switchAccount(ACCOUNT_A)
        activeLedger.switchAccount(ACCOUNT_A)
        assertTrue(exerciseLedger.start(ACCOUNT_A, 1L, 2L, seconds = 30))
        assertTrue(activeLedger.ensureSession(ACCOUNT_A, sessionStartedAt = 10_000L))

        assertTrue(exerciseLedger.clearAccount(ACCOUNT_A))
        assertTrue(activeLedger.clearAccount(ACCOUNT_A))
        assertTrue(exerciseLedger.deadlines.value.isEmpty())
        assertNull(activeLedger.snapshot.value)
    }

    private class MemoryExerciseTimerPersistence(
        private var stored: ExerciseRestTimerSnapshot =
            ExerciseRestTimerSnapshot(null, emptyMap())
    ) : ExerciseRestTimerPersistence {
        override fun load(): ExerciseRestTimerSnapshot = stored.copy(
            deadlines = stored.deadlines.toMap()
        )

        override fun save(snapshot: ExerciseRestTimerSnapshot): Boolean {
            stored = snapshot.copy(deadlines = snapshot.deadlines.toMap())
            return true
        }
    }

    private class MemoryActiveTimerPersistence(
        private var stored: ActiveWorkoutTimerSnapshot? = null
    ) : ActiveWorkoutTimerPersistence {
        override fun load(): ActiveWorkoutTimerSnapshot? = stored?.copy()

        override fun save(snapshot: ActiveWorkoutTimerSnapshot?): Boolean {
            stored = snapshot?.copy()
            return true
        }
    }

    private fun cloudSession(userId: String, generation: String) = AccountSession.Cloud(
        userId = userId,
        email = "synthetic@example.test",
        displayName = "Synthetic",
        accessToken = "synthetic-token",
        refreshToken = "synthetic-refresh",
        sessionGeneration = generation
    )

    private companion object {
        const val USER_A = "00000000-0000-4000-8000-000000000001"
        const val GENERATION_A = "00000000-0000-4000-8000-000000000011"
        const val GENERATION_B = "00000000-0000-4000-8000-000000000012"
        val ACCOUNT_A = "a".repeat(64)
        val ACCOUNT_B = "b".repeat(64)
    }
}
