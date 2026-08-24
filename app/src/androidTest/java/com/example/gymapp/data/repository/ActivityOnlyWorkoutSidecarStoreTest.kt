package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ActivityOnlyWorkoutSidecarStoreTest {
    @Test
    fun canonicalReconcilePropagatesDeletionAndUnrelatedAddition() = runBlocking {
        withDatabase("activity-sidecar-reconcile") { database, repository ->
            val local = item(startedAt = 1_750_000_000_000L, gymCalories = 10.0)
            val remote = item(startedAt = 1_750_000_100_000L, gymCalories = 20.0)
            repository.applyGarminCreateWorkout(
                ownerBinding = "a".repeat(64),
                deviceBinding = "123456789",
                pairingGeneration = "b".repeat(64),
                requestId = "activity-sidecar-local-request",
                payloadDigest = "c".repeat(64),
                date = local.workoutStartedAt,
                note = local.note,
                sets = emptyList(),
                durationSeconds = local.durationSeconds,
                isFreeWorkout = true,
                activityOnlyWorkout = local
            )

            val reconciled = repository.reconcileActivityOnlyWorkoutSidecar(listOf(remote))

            assertEquals(listOf(remote), reconciled.items)
            assertEquals(listOf(remote), database.activityOnlyWorkoutDao().getAll().map { it.toItem() })
            assertEquals(listOf(remote.workoutStartedAt),
                database.workoutDao().getSessions().first().map { it.session.date })
        }
    }

    @Test
    fun validCoreCollisionKeepsCoreVisibleAndPrivateActivityExact() = runBlocking {
        withDatabase("activity-sidecar-core-collision") { database, repository ->
            val startedAt = 1_750_000_000_000L
            repository.createWorkoutSessionFromNamedSets(
                date = startedAt,
                note = "Core",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val remote = item(startedAt = startedAt, gymCalories = 35.5)

            val merged = repository.reconcileActivityOnlyWorkoutSidecar(listOf(remote))

            assertEquals(listOf(remote), merged.items)
            assertEquals(remote, database.activityOnlyWorkoutDao().getAll().single().toItem())
            val visible = database.workoutDao().getSessions().first().single()
            assertEquals(1, visible.exerciseCount)
            assertEquals(1, visible.setCount)
            assertEquals("Core", visible.session.note)

            repository.deleteWorkoutSessionById(visible.session.id)
            val restoredActivity = database.workoutDao().getSessions().first().single()
            assertEquals(0, restoredActivity.exerciseCount)
            assertEquals(remote.durationSeconds, restoredActivity.session.durationSeconds)
            assertEquals(remote.note, restoredActivity.session.note)
            assertEquals(remote, database.activityOnlyWorkoutDao().getAll().single().toItem())
        }
    }

    @Test
    fun canonicalReconcilePreservesExactNullZeroAndNoteSemantics() = runBlocking {
        withDatabase("activity-sidecar-exact") { database, repository ->
            val first = item(startedAt = 1_750_000_000_000L, gymCalories = 10.0).copy(
                note = null
            )
            repository.reconcileActivityOnlyWorkoutSidecar(listOf(first))
            val updated = first.copy(
                garminCalories = 0,
                averageHeartRate = 0,
                maximumHeartRate = 0,
                endingHeartRateZone = 0,
                note = ""
            )

            val reconciled = repository.reconcileActivityOnlyWorkoutSidecar(listOf(updated))

            assertEquals(listOf(updated), reconciled.items)
            assertEquals(updated, database.activityOnlyWorkoutDao().getAll().single().toItem())
            assertEquals("", database.workoutDao().getSessions().first().single().session.note)
            assertEquals(1, database.workoutDao().getSessions().first().size)
        }
    }

    @Test
    fun durableBaselineIsExactAndCannotCrossAccounts() = runBlocking {
        withDatabase("activity-sidecar-baseline") { _, repository ->
            val owner = "123e4567-e89b-12d3-a456-426614174000"
            val otherOwner = "123e4567-e89b-12d3-a456-426614174099"
            val exact = item(startedAt = 1_750_000_000_000L, gymCalories = 10.125).copy(
                garminCalories = null,
                averageHeartRate = 0,
                maximumHeartRate = null,
                endingHeartRateZone = 0,
                note = ""
            )
            val itemsJson = com.example.gymapp.sync.activityOnlyWorkoutItemsJson(
                listOf(exact)
            ).toString()
            val baseline = ActivityOnlyWorkoutSyncBaselineRecord(
                ownerUserId = owner,
                revision = 7,
                itemsJson = itemsJson,
                itemsDigest = activityOnlyWorkoutDigest(listOf(exact))
            )

            repository.persistActivityOnlyWorkoutSyncBaseline(baseline)

            assertEquals(baseline, repository.getActivityOnlyWorkoutSyncBaseline(owner))
            assertTrue(
                runCatching { repository.getActivityOnlyWorkoutSyncBaseline(otherOwner) }
                    .exceptionOrNull() is IllegalArgumentException
            )
            assertTrue(
                runCatching {
                    repository.persistActivityOnlyWorkoutSyncBaseline(
                        baseline.copy(ownerUserId = otherOwner)
                    )
                }.exceptionOrNull() is IllegalArgumentException
            )
            assertTrue(
                runCatching {
                    repository.persistActivityOnlyWorkoutSyncBaseline(
                        baseline.copy(revision = baseline.revision - 1)
                    )
                }.exceptionOrNull() is IllegalArgumentException
            )
            assertTrue(
                runCatching {
                    repository.persistActivityOnlyWorkoutSyncBaseline(
                        baseline.copy(
                            itemsJson = "[]",
                            itemsDigest = activityOnlyWorkoutDigest(emptyList())
                        )
                    )
                }.exceptionOrNull() is IllegalArgumentException
            )
            assertEquals(baseline, repository.getActivityOnlyWorkoutSyncBaseline(owner))
        }
    }

    @Test
    fun durableJournalCanOnlyBeReusedOrClearedExactly() = runBlocking {
        withDatabase("activity-sidecar-journal") { _, repository ->
            val record = ActivityOnlyWorkoutSyncJournalRecord(
                ownerUserId = "123e4567-e89b-12d3-a456-426614174000",
                expectedRevision = 4,
                requestId = "123e4567-e89b-12d3-a456-426614174001",
                itemsJson = "[]",
                itemsDigest = activityOnlyWorkoutDigest(emptyList())
            )
            repository.persistActivityOnlyWorkoutSyncJournal(record)
            repository.persistActivityOnlyWorkoutSyncJournal(record)
            assertEquals(record, repository.getActivityOnlyWorkoutSyncJournal())
            assertTrue(
                runCatching {
                    repository.persistActivityOnlyWorkoutSyncJournal(
                        record.copy(requestId = "123e4567-e89b-12d3-a456-426614174002")
                    )
                }.exceptionOrNull() is IllegalArgumentException
            )
            assertFalse(
                repository.clearActivityOnlyWorkoutSyncJournal(
                    record.copy(itemsDigest = "d".repeat(64))
                )
            )
            assertEquals(record, repository.getActivityOnlyWorkoutSyncJournal())
            assertTrue(repository.clearActivityOnlyWorkoutSyncJournal(record))
            assertEquals(null, repository.getActivityOnlyWorkoutSyncJournal())
        }
    }

    private fun item(startedAt: Long, gymCalories: Double): ActivityOnlyWorkoutItem =
        ActivityOnlyWorkoutItem(
            workoutStartedAt = startedAt,
            durationSeconds = 1_234,
            gymCalories = gymCalories,
            garminCalories = null,
            averageHeartRate = null,
            maximumHeartRate = null,
            endingHeartRateZone = null,
            note = "Garmin · Free workout"
        )

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
