package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import com.example.gymapp.wearsync.PhoneWearParseResult
import com.example.gymapp.wearsync.PhoneWearPaths
import com.example.gymapp.wearsync.PhoneWearProtocol

@RunWith(AndroidJUnit4::class)
class WearMutationAtomicityTest {
    private val ownerId = "a".repeat(64)
    private val sourceNodeId = "trusted-watch"

    @Test
    fun createReceiptAndWorkoutCommitOnceAndChangedReplayIsRejected() = runBlocking {
        withDatabase("wear-create") { database, repository ->
            val operationId = "123e4567-e89b-42d3-a456-426614174000"
            fun digest(sentAt: Long, reps: Int): String {
                val raw =
                    """
                    {"type":"create_workout","protocolVersion":1,"operationId":"$operationId",
                     "sentAt":$sentAt,"ownerId":"$ownerId","accountGeneration":5,
                     "startedAt":1750000000000,
                     "sets":[{"exerciseName":"Bench Press","weight":80.0,"reps":$reps}]}
                    """.trimIndent()
                return (
                    PhoneWearProtocol.parse(
                        PhoneWearPaths.CREATE_WORKOUT,
                        raw.toByteArray(),
                        1_750_000_003_000L
                    ) as PhoneWearParseResult.Valid
                ).canonicalPayloadDigest
            }
            val firstDigest = digest(1_750_000_000_000L, 8)
            val retryDigest = digest(1_750_000_001_000L, 8)
            val changedDigest = digest(1_750_000_002_000L, 9)
            assertEquals(firstDigest, retryDigest)
            assertNotEquals(firstDigest, changedDigest)
            val first = repository.applyWearCreateWorkout(
                ownerId = ownerId,
                accountGeneration = 5L,
                operationId = operationId,
                sourceNodeId = sourceNodeId,
                payloadDigest = firstDigest,
                date = 1_750_000_000_000L,
                note = "watch",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val duplicate = repository.applyWearCreateWorkout(
                ownerId = ownerId,
                accountGeneration = 5L,
                operationId = operationId,
                sourceNodeId = sourceNodeId,
                payloadDigest = retryDigest,
                date = 1_750_000_000_000L,
                note = "watch",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val changedReplay = repository.applyWearCreateWorkout(
                ownerId = ownerId,
                accountGeneration = 5L,
                operationId = operationId,
                sourceNodeId = sourceNodeId,
                payloadDigest = changedDigest,
                date = 1_750_000_001_000L,
                note = "changed",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 9))
            )

            assertEquals(WearMutationApplyResult.Applied, first)
            assertEquals(WearMutationApplyResult.AlreadyApplied, duplicate)
            assertEquals(WearMutationApplyResult.Rejected, changedReplay)
            assertEquals(1, database.workoutDao().getSessionCount())
            assertNotNull(database.wearMutationDao().get(ownerId, operationId))
        }
    }

    @Test
    fun rejectedTargetDoesNotConsumeOperationIdOrCreateReceipt() = runBlocking {
        withDatabase("wear-rejected") { database, repository ->
            val operationId = "123e4567-e89b-42d3-a456-426614174001"
            val result = repository.applyWearUpdateSet(
                ownerId = ownerId,
                accountGeneration = 8L,
                operationId = operationId,
                sourceNodeId = sourceNodeId,
                payloadDigest = "d".repeat(64),
                setId = 999L,
                weight = 20.0,
                reps = 10
            )

            assertEquals(WearMutationApplyResult.Rejected, result)
            assertNull(database.wearMutationDao().get(ownerId, operationId))
            assertEquals(0, database.setDao().getTotalSetCount())
        }
    }

    @Test
    fun sameOwnerReplayUnderNewGenerationIsIdempotentAndReceiptsSurviveRelogin() = runBlocking {
        withDatabase("wear-relogin") { database, repository ->
            val operation = "123e4567-e89b-42d3-a456-426614174010"
            val sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            suspend fun create(generation: Long) = repository.applyWearCreateWorkout(
                ownerId = ownerId,
                accountGeneration = generation,
                operationId = operation,
                sourceNodeId = sourceNodeId,
                payloadDigest = "e".repeat(64),
                date = 1_750_000_010_000L,
                note = null,
                sets = sets,
                durationSeconds = 1_800L
            )
            assertEquals(WearMutationApplyResult.Applied, create(10L))
            assertEquals(WearMutationApplyResult.AlreadyApplied, create(11L))
            assertNotNull(database.wearMutationDao().get(ownerId, operation))
            assertEquals(1, database.wearMutationDao().count(ownerId))
            assertEquals(1, database.workoutDao().getSessionCount())
        }
    }

    @Test
    fun lateIdenticalCreateIsAppliedWithoutSecondWorkoutAndDifferingCreateKeepsBoth() = runBlocking {
        withDatabase("wear-late-dup") { database, repository ->
            val start = 1_750_000_020_000L
            val sets = listOf(
                NamedWorkoutSetDraft("Bench Press", 80.0, 8),
                NamedWorkoutSetDraft("Bench Press", 82.5, 6)
            )
            // The phone already saved this workout.
            assertNotNull(
                repository.createWorkoutSessionFromNamedSets(
                    date = start,
                    note = null,
                    sets = sets,
                    durationSeconds = 1_800L
                )
            )
            val identicalOperation = "123e4567-e89b-42d3-a456-426614174020"
            suspend fun createIdentical() = repository.applyWearCreateWorkout(
                ownerId = ownerId,
                accountGeneration = 1L,
                operationId = identicalOperation,
                sourceNodeId = sourceNodeId,
                payloadDigest = "f".repeat(64),
                date = start + 60_000L,
                note = null,
                sets = listOf(
                    NamedWorkoutSetDraft(" bench press", 80.0, 8),
                    NamedWorkoutSetDraft("Bench Press", 82.5, 6)
                ),
                durationSeconds = 1_740L
            )
            assertEquals(WearMutationApplyResult.Applied, createIdentical())
            assertNotNull(database.wearMutationDao().get(ownerId, identicalOperation))
            assertEquals(1, database.workoutDao().getSessionCount())
            assertEquals(WearMutationApplyResult.AlreadyApplied, createIdentical())
            assertEquals(1, database.workoutDao().getSessionCount())

            val differing = repository.applyWearCreateWorkout(
                ownerId = ownerId,
                accountGeneration = 1L,
                operationId = "123e4567-e89b-42d3-a456-426614174021",
                sourceNodeId = sourceNodeId,
                payloadDigest = "0".repeat(64),
                date = start + 60_000L,
                note = null,
                sets = listOf(
                    NamedWorkoutSetDraft("Bench Press", 80.0, 8),
                    NamedWorkoutSetDraft("Bench Press", 82.5, 7)
                ),
                durationSeconds = 1_740L
            )
            assertEquals(WearMutationApplyResult.Applied, differing)
            assertEquals(2, database.workoutDao().getSessionCount())
        }
    }

    @Test
    fun dailyCreateCapIsADeterministicResultAndStoreFullIsNotAThrow() = runBlocking {
        withDatabase("wear-cap") { database, repository ->
            val sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            val now = System.currentTimeMillis()
            repeat(50) { index ->
                database.wearMutationDao().insert(
                    com.example.gymapp.data.entity.WearMutationReceiptEntity(
                        ownerId = ownerId,
                        accountGeneration = 1L,
                        operationId = "123e4567-e89b-42d3-a456-4266141740%02d".format(index),
                        sourceNodeId = sourceNodeId,
                        mutationType = "create_workout",
                        payloadDigest = "c".repeat(64),
                        createdAt = now
                    )
                )
            }
            val result = repository.applyWearCreateWorkout(
                ownerId = ownerId,
                accountGeneration = 1L,
                operationId = "123e4567-e89b-42d3-a456-426614174999",
                sourceNodeId = sourceNodeId,
                payloadDigest = "d".repeat(64),
                date = 1_750_000_010_000L,
                note = null,
                sets = sets
            )
            assertEquals(WearMutationApplyResult.RateLimited, result)
            assertEquals(0, database.workoutDao().getSessionCount())
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
            block(database, GymRepository(database))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
