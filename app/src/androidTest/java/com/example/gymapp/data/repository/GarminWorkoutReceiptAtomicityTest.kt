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
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GarminWorkoutReceiptAtomicityTest {
    private val ownerBinding = "a".repeat(64)
    private val deviceBinding = "123456789"
    private val requestId = "request-1234567890"

    @Test
    fun workoutAndReceiptCommitOnceAndChangedPayloadIsRejected() = runBlocking {
        withDatabase("garmin-receipt") { database, repository ->
            val first = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                requestId = requestId,
                payloadDigest = "b".repeat(64),
                date = 1_750_000_000_000L,
                note = "Garmin",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val duplicate = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                requestId = requestId,
                payloadDigest = "b".repeat(64),
                date = 1_750_000_000_000L,
                note = "Garmin",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val changedReplay = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                requestId = requestId,
                payloadDigest = "c".repeat(64),
                date = 1_750_000_001_000L,
                note = "changed",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 9))
            )

            assertEquals(GarminWorkoutApplyResult.Applied, first)
            assertEquals(GarminWorkoutApplyResult.AlreadyApplied, duplicate)
            assertEquals(GarminWorkoutApplyResult.Rejected, changedReplay)
            assertEquals(1, database.workoutDao().getSessionCount())
            assertEquals(1, database.garminWorkoutReceiptDao().count())
            val receipt = database.garminWorkoutReceiptDao().get(
                ownerBinding,
                deviceBinding,
                requestId
            )
            assertNotNull(receipt)
            checkNotNull(receipt)
            assertEquals("b".repeat(64), receipt.payloadDigest)
            assertTrue(receipt.workoutSessionId > 0L)

            repository.deleteWorkoutSessionById(receipt.workoutSessionId)
            val retryAfterUserDeletion = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                requestId = requestId,
                payloadDigest = "b".repeat(64),
                date = 1_750_000_000_000L,
                note = "Garmin",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            assertEquals(GarminWorkoutApplyResult.AlreadyApplied, retryAfterUserDeletion)
            assertEquals(0, database.workoutDao().getSessionCount())
            assertEquals(1, database.garminWorkoutReceiptDao().count())
        }
    }

    @Test
    fun receiptScopeIncludesBothCanonicalOwnerAndTransportDevice() = runBlocking {
        withDatabase("garmin-scope") { database, repository ->
            val common = "d".repeat(64)
            val first = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                requestId = requestId,
                payloadDigest = common,
                date = 1_750_000_010_000L,
                note = null,
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val otherDevice = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = "987654321",
                requestId = requestId,
                payloadDigest = common,
                date = 1_750_000_011_000L,
                note = null,
                sets = listOf(NamedWorkoutSetDraft("Squat", 100.0, 5))
            )
            val otherOwner = repository.applyGarminCreateWorkout(
                ownerBinding = "e".repeat(64),
                deviceBinding = deviceBinding,
                requestId = requestId,
                payloadDigest = common,
                date = 1_750_000_012_000L,
                note = null,
                sets = listOf(NamedWorkoutSetDraft("Deadlift", 120.0, 5))
            )

            assertEquals(GarminWorkoutApplyResult.Applied, first)
            assertEquals(GarminWorkoutApplyResult.Applied, otherDevice)
            assertEquals(GarminWorkoutApplyResult.Applied, otherOwner)
            assertEquals(3, database.workoutDao().getSessionCount())
            assertEquals(3, database.garminWorkoutReceiptDao().count())
            assertNotEquals(
                database.garminWorkoutReceiptDao()
                    .get(ownerBinding, deviceBinding, requestId)?.workoutSessionId,
                database.garminWorkoutReceiptDao()
                    .get(ownerBinding, "987654321", requestId)?.workoutSessionId
            )
        }
    }

    @Test
    fun rejectedWorkoutDoesNotConsumeDurableRequestId() = runBlocking {
        withDatabase("garmin-rejected") { database, repository ->
            val rejected = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                requestId = requestId,
                payloadDigest = "f".repeat(64),
                date = 1_750_000_020_000L,
                note = null,
                sets = emptyList()
            )

            assertEquals(GarminWorkoutApplyResult.Rejected, rejected)
            assertEquals(0, database.workoutDao().getSessionCount())
            assertEquals(0, database.garminWorkoutReceiptDao().count())
            assertNull(
                database.garminWorkoutReceiptDao().get(
                    ownerBinding,
                    deviceBinding,
                    requestId
                )
            )
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
