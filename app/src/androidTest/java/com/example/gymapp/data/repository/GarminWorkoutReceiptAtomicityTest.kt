package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.entity.GarminWorkoutReceiptEntity
import com.example.gymapp.garmin.parseTrustedGarminWorkoutMetrics
import com.example.gymapp.navigation.isCanonicalAndroidCloudEnvelope
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject

@RunWith(AndroidJUnit4::class)
class GarminWorkoutReceiptAtomicityTest {
    private val ownerBinding = "a".repeat(64)
    private val deviceBinding = "123456789"
    private val pairingGeneration = "1".repeat(64)
    private val requestId = "request-1234567890"

    @Test
    fun workoutAndReceiptCommitOnceAndChangedPayloadIsRejected() = runBlocking {
        withDatabase("garmin-receipt") { database, repository ->
            val first = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
                requestId = requestId,
                payloadDigest = "b".repeat(64),
                date = 1_750_000_000_000L,
                note = "Garmin",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val duplicate = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
                requestId = requestId,
                payloadDigest = "b".repeat(64),
                date = 1_750_000_000_000L,
                note = "Garmin",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val changedReplay = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
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
                pairingGeneration,
                requestId
            )
            assertNotNull(receipt)
            checkNotNull(receipt)
            assertEquals("b".repeat(64), receipt.payloadDigest)
            assertTrue(database.workoutDao().getSessions().first().single().hasGarminReceipt)

            val sessionId = database.workoutDao().getSessions().first().single().session.id
            repository.deleteWorkoutSessionById(sessionId)
            val retryAfterUserDeletion = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
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
    fun partialWorkoutPersistsEveryCompletedSetWithItsOwnLoadAndReps() = runBlocking {
        withDatabase("garmin-partial-sets") { database, repository ->
            val note = "Garmin · Duration 4:00 · Completed 2/4 sets · " +
                "S1 I0-42s K5.5/6 Z0/0/12/20/10/0s · " +
                "S2 I90-128s K4.25/- Z0/3/15/15/5/0s"

            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = requestId,
                    payloadDigest = "d".repeat(64),
                    date = 1_750_000_002_000L,
                    note = note,
                    sets = listOf(
                        NamedWorkoutSetDraft("Bench Press", 82.5, 8),
                        NamedWorkoutSetDraft("Bench Press", 80.0, 7)
                    )
                )
            )

            val summary = database.workoutDao().getSessions().first().single()
            val details = checkNotNull(repository.getWorkoutTemplate(summary.session.id))
            val persistedSets = details.workoutExercises.single().sets
            assertEquals(listOf(82.5 to 8, 80.0 to 7), persistedSets.map { it.weight to it.reps })
            assertEquals(listOf(0, 1), persistedSets.map { it.orderIndex })
            assertTrue(summary.hasGarminReceipt)

            val metrics = parseTrustedGarminWorkoutMetrics(
                note = checkNotNull(details.session.note),
                hasGarminReceipt = summary.hasGarminReceipt
            )
            assertEquals(4, metrics?.plannedSetCount)
            assertEquals(2, metrics?.setIntervals?.size)
        }
    }

    @Test
    fun importedGarminMarkerHasNoReceiptProvenance() = runBlocking {
        withDatabase("garmin-imported-note") { database, repository ->
            val forgedNote = "Garmin · Duration 45:00 · Garmin kcal 250 · Avg HR 140"
            val imported = repository.importBackupJsonObject(
                JSONObject(
                    """
                    {
                      "schemaVersion": 2,
                      "sessions": [{
                        "date": 1750000030000,
                        "note": "$forgedNote",
                        "garminProvenance": true,
                        "exercises": [{
                          "name": "Bench Press",
                          "sets": [{"weight": 80.0, "reps": 8}]
                        }]
                      }]
                    }
                    """.trimIndent()
                )
            )

            val summary = database.workoutDao().getSessions().first().single()
            assertEquals(1, imported)
            assertEquals(forgedNote, summary.session.note)
            assertFalse(summary.hasGarminReceipt)
            assertEquals(0, database.garminWorkoutReceiptDao().count())
        }
    }

    @Test
    fun authoritativeReplacementReassociatesOnlyExactGarminSessions() = runBlocking {
        withDatabase("garmin-cloud-reassociation") { database, repository ->
            val userId = UUID.randomUUID().toString()
            val garminNote = "Garmin · Duration 45:00 · Garmin kcal 250 · Avg HR 140"
            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = requestId,
                    payloadDigest = "7".repeat(64),
                    date = 1_750_000_030_000L,
                    note = garminNote,
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
            )
            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = "$requestId-second",
                    payloadDigest = "8".repeat(64),
                    date = 1_750_000_030_000L,
                    note = garminNote,
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
            )

            val owner = BackupOwner(accountId = userId, userId = userId, remote = true)
            val cloud = repository.buildCloudBackupJson(owner)
            val exportedSession = cloud.getJSONArray("sessions").getJSONObject(0)
            assertFalse(exportedSession.has("garminProvenance"))
            cloud.getJSONArray("sessions").put(JSONObject(exportedSession.toString()))
            assertTrue(isCanonicalAndroidCloudEnvelope(cloud, userId))

            assertEquals(
                3,
                repository.replaceWithBackupJsonObject(
                    root = cloud,
                    expectedLocalState = repository.getCloudWorkoutProjectionState(),
                    activeUserId = userId,
                    activeRemote = true
                )
            )
            val exactRestored = database.workoutDao().getSessions().first()
            assertEquals(3, exactRestored.size)
            assertEquals(2, exactRestored.count { it.hasGarminReceipt })
            assertNotNull(
                parseTrustedGarminWorkoutMetrics(
                    note = checkNotNull(
                        exactRestored.first { it.hasGarminReceipt }.session.note
                    ),
                    hasGarminReceipt = true
                )
            )
            assertEquals(2, database.garminWorkoutReceiptDao().getProvenanceSessionIds().size)
            assertEquals(2, database.garminWorkoutReceiptDao().count())

            val changedCloud = repository.buildCloudBackupJson(owner)
            val changedSessions = changedCloud.getJSONArray("sessions")
            repeat(changedSessions.length()) { index ->
                changedSessions.getJSONObject(index).put("note", "$garminNote · edited")
            }
            assertEquals(
                3,
                repository.replaceWithBackupJsonObject(
                    root = changedCloud,
                    expectedLocalState = repository.getCloudWorkoutProjectionState(),
                    activeUserId = userId,
                    activeRemote = true
                )
            )
            assertTrue(database.workoutDao().getSessions().first().none { it.hasGarminReceipt })
            assertTrue(database.garminWorkoutReceiptDao().getProvenanceSessionIds().isEmpty())
            assertEquals(2, database.garminWorkoutReceiptDao().count())
        }
    }

    @Test
    fun authoritativeReplacementCanonicalizesPaddedNoteAndRetainsGarminProvenance() = runBlocking {
        withDatabase("garmin-cloud-rollback") { database, repository ->
            val userId = UUID.randomUUID().toString()
            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = requestId,
                    payloadDigest = "9".repeat(64),
                    date = 1_750_000_040_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
            )
            val original = database.workoutDao().getSessions().first().single()
            val cloud = repository.buildCloudBackupJson(
                BackupOwner(accountId = userId, userId = userId, remote = true)
            )
            // Canonical validation and persistence both trim note boundaries, matching iOS.
            cloud.getJSONArray("sessions").getJSONObject(0).put("note", " Garmin ")

            assertEquals(
                1,
                repository.replaceWithBackupJsonObject(
                    root = cloud,
                    expectedLocalState = repository.getCloudWorkoutProjectionState(),
                    activeUserId = userId,
                    activeRemote = true
                )
            )

            val restoredOriginal = database.workoutDao().getSessions().first().single()
            assertTrue(restoredOriginal.session.id != original.session.id)
            assertEquals("Garmin", restoredOriginal.session.note)
            assertTrue(restoredOriginal.hasGarminReceipt)
            assertEquals(
                listOf(restoredOriginal.session.id),
                database.garminWorkoutReceiptDao().getProvenanceSessionIds()
            )
        }
    }

    @Test
    fun receiptScopeIncludesBothCanonicalOwnerAndTransportDevice() = runBlocking {
        withDatabase("garmin-scope") { database, repository ->
            val common = "d".repeat(64)
            val first = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
                requestId = requestId,
                payloadDigest = common,
                date = 1_750_000_010_000L,
                note = null,
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            val otherDevice = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = "987654321",
                pairingGeneration = pairingGeneration,
                requestId = requestId,
                payloadDigest = common,
                date = 1_750_000_011_000L,
                note = null,
                sets = listOf(NamedWorkoutSetDraft("Squat", 100.0, 5))
            )
            val otherOwner = repository.applyGarminCreateWorkout(
                ownerBinding = "e".repeat(64),
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
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
                    .get(ownerBinding, deviceBinding, pairingGeneration, requestId),
                database.garminWorkoutReceiptDao()
                    .get(ownerBinding, "987654321", pairingGeneration, requestId)
            )
        }
    }

    @Test
    fun rejectedWorkoutDoesNotConsumeDurableRequestId() = runBlocking {
        withDatabase("garmin-rejected") { database, repository ->
            val rejected = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
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
                    pairingGeneration,
                    requestId
                )
            )
        }
    }

    @Test
    fun freshRequestsAreRateAndLifetimeBoundButDuplicatesStillRetry() = runBlocking {
        var now = 1_750_000_100_000L
        withDatabase("garmin-admission", nowProvider = { now }) { database, repository ->
            repeat(MAX_GARMIN_WORKOUTS_PER_ROLLING_DAY) { index ->
                val result = repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = "rate-request-${index.toString().padStart(4, '0')}",
                    payloadDigest = index.toString().padStart(64, 'a'),
                    date = 1_750_000_000_000L + index,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
                assertEquals(GarminWorkoutApplyResult.Applied, result)
            }

            val rateLimited = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
                requestId = "rate-request-over-limit",
                payloadDigest = "f".repeat(64),
                date = 1_750_000_010_000L,
                note = "Garmin",
                sets = listOf(NamedWorkoutSetDraft("Squat", 100.0, 5))
            )
            assertEquals(GarminWorkoutApplyResult.RateLimited, rateLimited)
            assertEquals(MAX_GARMIN_WORKOUTS_PER_ROLLING_DAY, database.workoutDao().getSessionCount())

            val duplicateAtLimit = repository.applyGarminCreateWorkout(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration,
                requestId = "rate-request-0000",
                payloadDigest = "0".padStart(64, 'a'),
                date = 1_750_000_000_000L,
                note = "Garmin",
                sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
            )
            assertEquals(GarminWorkoutApplyResult.AlreadyApplied, duplicateAtLimit)

            now += GARMIN_WORKOUT_RATE_WINDOW_MS + 1L
            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = "rate-request-next-day",
                    payloadDigest = "e".repeat(64),
                    date = 1_750_000_020_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Deadlift", 120.0, 5))
                )
            )
        }
    }

    @Test
    fun pairingGenerationCapAndAcknowledgedResetKeepReceiptStorageBounded() = runBlocking {
        val now = 1_750_000_200_000L
        withDatabase("garmin-pairing-cap", nowProvider = { now }) { database, repository ->
            repeat(MAX_GARMIN_WORKOUTS_PER_PAIRING_GENERATION) { index ->
                database.garminWorkoutReceiptDao().insert(
                    GarminWorkoutReceiptEntity(
                        ownerBinding = ownerBinding,
                        deviceBinding = deviceBinding,
                        pairingGeneration = pairingGeneration,
                        requestId = "seed-request-${index.toString().padStart(4, '0')}",
                        payloadDigest = index.toString().padStart(64, 'a'),
                        createdAt = now - GARMIN_WORKOUT_RATE_WINDOW_MS - index
                    )
                )
            }

            assertEquals(
                GarminWorkoutApplyResult.PairingLimitReached,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = "pairing-cap-request",
                    payloadDigest = "b".repeat(64),
                    date = 1_750_000_000_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
            )

            val nextGeneration = "2".repeat(64)
            repository.activateGarminPairingGeneration(
                ownerBinding = ownerBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = nextGeneration
            )
            assertEquals(0, database.garminWorkoutReceiptDao().count())
            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = nextGeneration,
                    requestId = "next-generation-request",
                    payloadDigest = "c".repeat(64),
                    date = 1_750_000_000_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
            )
            assertEquals(1, database.garminWorkoutReceiptDao().count())
        }
    }

    @Test
    fun releasedGenerationlessWatchUsesNormalDailyRateAndRecoversNextDay() = runBlocking {
        var now = 1_750_000_300_000L
        val fallbackGeneration = "f".repeat(64)
        withDatabase("garmin-legacy-budget", nowProvider = { now }) { database, repository ->
            repeat(MAX_GARMIN_WORKOUTS_PER_ROLLING_DAY) { index ->
                assertEquals(
                    GarminWorkoutApplyResult.Applied,
                    repository.applyGarminCreateWorkout(
                        ownerBinding = ownerBinding,
                        deviceBinding = deviceBinding,
                        pairingGeneration = fallbackGeneration,
                        requestId = "legacy-request-${index.toString().padStart(4, '0')}",
                        payloadDigest = index.toString().padStart(64, 'a'),
                        date = 1_750_000_000_000L + index,
                        note = "Garmin",
                        sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                    )
                )
            }

            assertEquals(
                GarminWorkoutApplyResult.RateLimited,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = fallbackGeneration,
                    requestId = "legacy-request-over-limit",
                    payloadDigest = "d".repeat(64),
                    date = 1_750_000_010_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Squat", 100.0, 5))
                )
            )
            assertEquals(MAX_GARMIN_WORKOUTS_PER_ROLLING_DAY, database.workoutDao().getSessionCount())

            now += GARMIN_WORKOUT_RATE_WINDOW_MS + 1L
            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = fallbackGeneration,
                    requestId = "legacy-request-next-day",
                    payloadDigest = "e".repeat(64),
                    date = 1_750_000_020_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Deadlift", 120.0, 5))
                )
            )
        }
    }

    @Test
    fun generationlessReceiptHorizonPrunesOnlyReplayStateAndAvoidsPermanentLockout() = runBlocking {
        var now = 1_750_000_400_000L
        val fallbackGeneration = "f".repeat(64)
        withDatabase("garmin-legacy-horizon", nowProvider = { now }) { database, repository ->
            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = fallbackGeneration,
                    requestId = "legacy-live-request-0000",
                    payloadDigest = "a".repeat(64),
                    date = 1_750_000_000_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
            )
            repeat(MAX_LEGACY_GARMIN_RECEIPTS_WITHIN_HORIZON - 1) { index ->
                database.garminWorkoutReceiptDao().insert(
                    GarminWorkoutReceiptEntity(
                        ownerBinding = ownerBinding,
                        deviceBinding = deviceBinding,
                        pairingGeneration = fallbackGeneration,
                        requestId = "legacy-window-seed-${index.toString().padStart(4, '0')}",
                        payloadDigest = "b".repeat(64),
                        createdAt = now - GARMIN_WORKOUT_RATE_WINDOW_MS - 1L
                    )
                )
            }

            assertEquals(
                GarminWorkoutApplyResult.PairingLimitReached,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = fallbackGeneration,
                    requestId = "legacy-window-over-limit",
                    payloadDigest = "c".repeat(64),
                    date = 1_750_000_010_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Squat", 100.0, 5))
                )
            )

            now += LEGACY_GARMIN_RECEIPT_HORIZON_MS + 1L
            assertEquals(
                GarminWorkoutApplyResult.Applied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = fallbackGeneration,
                    requestId = "legacy-after-horizon-0000",
                    payloadDigest = "d".repeat(64),
                    date = 1_750_000_020_000L,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Deadlift", 120.0, 5))
                )
            )
            assertEquals(1, database.garminWorkoutReceiptDao().count())
            assertEquals(2, database.workoutDao().getSessionCount())
            assertTrue(database.workoutDao().getSessions().first().all { it.hasGarminReceipt })
        }
    }

    @Test
    fun absoluteReceiptCapIsAtomicUnderConcurrentFreshRequestsAndStillAllowsRetry() = runBlocking {
        val now = 1_750_000_500_000L
        val migratedLegacyGeneration = "0".repeat(64)
        withDatabase("garmin-absolute-cap", nowProvider = { now }) { database, repository ->
            repeat(MAX_GARMIN_DURABLE_RECEIPTS - 1) { index ->
                database.garminWorkoutReceiptDao().insert(
                    GarminWorkoutReceiptEntity(
                        ownerBinding = ownerBinding,
                        deviceBinding = deviceBinding,
                        pairingGeneration = migratedLegacyGeneration,
                        requestId = "absolute-cap-seed-${index.toString().padStart(4, '0')}",
                        payloadDigest = "a".repeat(64),
                        createdAt = now - GARMIN_WORKOUT_RATE_WINDOW_MS - 1L
                    )
                )
            }

            val results = coroutineScope {
                listOf(0, 1).map { index ->
                    async(Dispatchers.Default) {
                        repository.applyGarminCreateWorkout(
                            ownerBinding = ownerBinding,
                            deviceBinding = deviceBinding,
                            pairingGeneration = pairingGeneration,
                            requestId = "concurrent-cap-request-${index.toString().padStart(4, '0')}",
                            payloadDigest = if (index == 0) "b".repeat(64) else "c".repeat(64),
                            date = 1_750_000_030_000L + index,
                            note = "Garmin",
                            sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                        )
                    }
                }.awaitAll()
            }

            assertEquals(1, results.count { it == GarminWorkoutApplyResult.Applied })
            assertEquals(1, results.count { it == GarminWorkoutApplyResult.PairingLimitReached })
            assertEquals(MAX_GARMIN_DURABLE_RECEIPTS, database.garminWorkoutReceiptDao().count())

            val appliedIndex = results.indexOf(GarminWorkoutApplyResult.Applied)
            assertEquals(
                GarminWorkoutApplyResult.AlreadyApplied,
                repository.applyGarminCreateWorkout(
                    ownerBinding = ownerBinding,
                    deviceBinding = deviceBinding,
                    pairingGeneration = pairingGeneration,
                    requestId = "concurrent-cap-request-${appliedIndex.toString().padStart(4, '0')}",
                    payloadDigest = if (appliedIndex == 0) "b".repeat(64) else "c".repeat(64),
                    date = 1_750_000_030_000L + appliedIndex,
                    note = "Garmin",
                    sets = listOf(NamedWorkoutSetDraft("Bench Press", 80.0, 8))
                )
            )
        }
    }

    private suspend fun withDatabase(
        prefix: String,
        nowProvider: () -> Long = System::currentTimeMillis,
        block: suspend (GymDatabase, GymRepository) -> Unit
    ) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "$prefix-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        try {
            block(database, GymRepository(database, nowProvider))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
