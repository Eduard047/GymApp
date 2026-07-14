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
            assertNotNull(database.wearMutationDao().get(ownerId, 5L, operationId))
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
            assertNull(database.wearMutationDao().get(ownerId, 8L, operationId))
            assertEquals(0, database.setDao().getTotalSetCount())
        }
    }

    @Test
    fun newAccountGenerationPrunesOnlyUnreachableOldReceipts() = runBlocking {
        withDatabase("wear-generation-prune") { database, repository ->
            val oldOperation = "123e4567-e89b-42d3-a456-426614174010"
            val newOperation = "123e4567-e89b-42d3-a456-426614174011"
            assertEquals(
                WearMutationApplyResult.Applied,
                repository.applyWearCreateWorkout(
                    ownerId = ownerId,
                    accountGeneration = 10L,
                    operationId = oldOperation,
                    sourceNodeId = sourceNodeId,
                    payloadDigest = "e".repeat(64),
                    date = 1_750_000_010_000L,
                    note = null,
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
            )
            assertNotNull(database.wearMutationDao().get(ownerId, 10L, oldOperation))

            assertEquals(
                WearMutationApplyResult.Applied,
                repository.applyWearCreateWorkout(
                    ownerId = ownerId,
                    accountGeneration = 11L,
                    operationId = newOperation,
                    sourceNodeId = sourceNodeId,
                    payloadDigest = "f".repeat(64),
                    date = 1_750_000_011_000L,
                    note = null,
                    sets = listOf(NamedWorkoutSetDraft("Squat", 100.0, 5))
                )
            )

            assertNull(database.wearMutationDao().get(ownerId, 10L, oldOperation))
            assertNotNull(database.wearMutationDao().get(ownerId, 11L, newOperation))
            assertEquals(1, database.wearMutationDao().count(ownerId, 11L))
            assertEquals(2, database.workoutDao().getSessionCount())
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
