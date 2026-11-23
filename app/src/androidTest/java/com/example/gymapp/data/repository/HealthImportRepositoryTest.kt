package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.health.HealthImportPersistResult
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HealthImportRepositoryTest {
    private val startedAt = 1_750_000_000_000L

    private fun item(start: Long = startedAt) = ActivityOnlyWorkoutItem(
        workoutStartedAt = start,
        durationSeconds = 1_800,
        gymCalories = 250.0,
        averageHeartRate = 120,
        maximumHeartRate = 150,
        note = "Health Connect · Strength training · Duration 30:00"
    )

    @Test
    fun importWritesWorkoutSidecarAndReceiptWithoutGarminRows() = runBlocking {
        withDatabase { database, repository ->
            assertEquals(
                HealthImportPersistResult.IMPORTED,
                repository.importHealthActivity(item(), "health_connect:a")
            )
            val session = database.workoutDao().getSessions().first().single()
            assertEquals(0, session.exerciseCount)
            assertEquals(1_800L, session.session.durationSeconds)
            assertEquals(item(), database.activityOnlyWorkoutDao().getAll().single().toItem())
            assertEquals(1, database.healthImportDao().countReceipt("health_connect:a"))
            assertEquals(0, database.garminWorkoutReceiptDao().count())
        }
    }

    @Test
    fun repeatedImportIsIdempotent() = runBlocking {
        withDatabase { database, repository ->
            repository.importHealthActivity(item(), "health_connect:a")
            assertEquals(
                HealthImportPersistResult.DUPLICATE_RECEIPT,
                repository.importHealthActivity(item(), "health_connect:a")
            )
            assertEquals(1, database.workoutDao().getSessions().first().size)
        }
    }

    @Test
    fun deletedImportDoesNotComeBack() = runBlocking {
        withDatabase { database, repository ->
            repository.importHealthActivity(item(), "health_connect:a")
            repository.deleteWorkoutSessionById(database.workoutDao().getSessions().first().single().session.id)

            assertEquals(
                HealthImportPersistResult.DUPLICATE_RECEIPT,
                repository.importHealthActivity(item(), "health_connect:a")
            )
            assertEquals(0, database.workoutDao().getSessions().first().size)
        }
    }

    @Test
    fun overlapWithAnyLocalWorkoutIsRefusedWithinTolerance() = runBlocking {
        withDatabase { database, repository ->
            repository.importHealthActivity(item(), "health_connect:a")
            // Ends at start + 1800 s; 120 s tolerance is inclusive, 121 s is free.
            val edge = startedAt + 1_800_000L + 120_000L
            assertEquals(
                HealthImportPersistResult.OVERLAP,
                repository.importHealthActivity(item(edge), "health_connect:b")
            )
            assertEquals(
                HealthImportPersistResult.IMPORTED,
                repository.importHealthActivity(item(edge + 1_000L), "health_connect:c")
            )
            assertNull(database.healthImportDao().getState())
            repository.healthImportSetLastImportAt(5L)
            assertEquals(5L, repository.healthImportLastImportAt())
        }
    }

    @Test
    fun importCommittingBetweenSidecarReadAndReconcileIsNotDeleted() = runBlocking {
        withDatabase { database, repository ->
            // The sync read its snapshot, merged it with the cloud, and is about to reconcile.
            val snapshot = repository.getActivityOnlyWorkoutSnapshot()
            assertEquals(emptyList<ActivityOnlyWorkoutItem>(), snapshot.items)
            assertEquals(
                HealthImportPersistResult.IMPORTED,
                repository.importHealthActivity(item(), "health_connect:a")
            )

            val reconciled = repository.reconcileActivityOnlyWorkoutSidecar(snapshot.items)

            assertEquals(listOf(item()), reconciled.items)
            assertEquals(1, database.workoutDao().getSessions().first().size)
            assertEquals(1, database.healthImportDao().countReceipt("health_connect:a"))
            assertEquals(item(), database.activityOnlyWorkoutDao().getAll().single().toItem())
        }
    }

    @Test
    fun reconcileStillDeletesAMirrorThatWasPartOfTheSnapshotItRead() = runBlocking {
        withDatabase { database, repository ->
            repository.importHealthActivity(item(), "health_connect:a")
            val snapshot = repository.getActivityOnlyWorkoutSnapshot()
            assertEquals(listOf(item()), snapshot.items)

            // The cloud removed it, so the merged target is empty.
            val reconciled = repository.reconcileActivityOnlyWorkoutSidecar(emptyList())

            assertEquals(emptyList<ActivityOnlyWorkoutItem>(), reconciled.items)
            assertEquals(0, database.workoutDao().getSessions().first().size)
            // The receipt stays, so the workout is not imported again.
            assertEquals(
                HealthImportPersistResult.DUPLICATE_RECEIPT,
                repository.importHealthActivity(item(), "health_connect:a")
            )
        }
    }

    @Test
    fun optInIsPerAccountDatabaseOffByDefaultAndKeepsTheImportTime() = runBlocking {
        withDatabase { database, repository ->
            assertFalse(repository.healthImportIsEnabled())
            repository.healthImportSetLastImportAt(7L)
            assertFalse(repository.healthImportIsEnabled())
            repository.healthImportSetEnabled(true)
            assertTrue(repository.healthImportIsEnabled())
            assertEquals(7L, repository.healthImportLastImportAt())
            repository.healthImportSetLastImportAt(9L)
            assertTrue(repository.healthImportIsEnabled())
            repository.healthImportSetEnabled(false)
            assertFalse(repository.healthImportIsEnabled())
            assertEquals(9L, repository.healthImportLastImportAt())

            val other = "health-import-other-${UUID.randomUUID()}"
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val otherDatabase = GymDatabase.getInstance(context, other)
            try {
                val otherRepository = GymRepository(otherDatabase)
                repository.healthImportSetEnabled(true)
                assertFalse(otherRepository.healthImportIsEnabled())
            } finally {
                otherDatabase.close()
                context.deleteDatabase(other)
            }
        }
    }

    @Test
    fun receiptCountCountsImportedWorkoutsEvenAfterDeletion() = runBlocking {
        withDatabase { database, repository ->
            assertEquals(0, repository.healthImportReceiptCount())
            repository.importHealthActivity(item(), "health_connect:a")
            repository.deleteWorkoutSessionById(database.workoutDao().getSessions().first().single().session.id)
            assertEquals(1, repository.healthImportReceiptCount())
        }
    }

    private suspend fun withDatabase(block: suspend (GymDatabase, GymRepository) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "health-import-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        try {
            block(database, GymRepository(database))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
