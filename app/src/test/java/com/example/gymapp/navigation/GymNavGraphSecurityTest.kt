package com.example.gymapp.navigation

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.CloudAccountDeletionSessionDisposition
import com.example.gymapp.auth.cloudAccountDeletionSessionDisposition
import com.example.gymapp.auth.databaseName
import com.example.gymapp.R
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.util.LocalizedText
import com.example.gymapp.data.repository.canonicalWorkoutPayloadMatches
import com.example.gymapp.data.repository.canonicalWorkoutPayloadDigest
import com.example.gymapp.sync.CloudSnapshotApplyDecision
import com.example.gymapp.sync.CloudSyncConflictSnapshot
import com.example.gymapp.sync.cloudSnapshotApplyDecision
import com.example.gymapp.sync.isCurrentCloudSyncConflict
import com.example.gymapp.sync.runCurrentCloudSyncConflictAction
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.coroutines.runBlocking

class GymNavGraphSecurityTest {
    private val userId = "123e4567-e89b-12d3-a456-426614174000"
    private val session = cloudSession("generation-a")

    @Test
    fun `PWA legacy state can be read but never arms destructive canonical autosave`() {
        val pwaState = JSONObject(
            """
            {
              "language": "uk",
              "profile": {"split": "Full Body", "days": 4},
              "mappings": {"Bench Press": ["chest"]},
              "exercises": [{"id": 1, "name": "Bench Press"}],
              "sessions": [{
                "id": 2,
                "startedAt": 1750000000000,
                "sets": [{"exerciseName": "Bench Press", "weight": 80.0, "reps": 8}]
              }]
            }
            """.trimIndent()
        )

        assertFalse(isCanonicalAndroidCloudEnvelope(pwaState, userId))
        assertFalse(
            shouldEnableCloudAutosave(
                pullSucceeded = true,
                canonicalRoundTripSafe = false,
                pulledSession = session,
                activeSession = session
            )
        )
    }

    @Test
    fun `native canonical state arms autosave only for the same session generation`() {
        val canonical = JSONObject(
            """
            {
              "schemaVersion": 2,
              "exportedAt": 1750000000000,
              "app": "GymApp",
              "diagnostics": false,
              "owner": {
                "accountId": "$userId",
                "userId": "$userId",
                "email": "user@example.test",
                "remote": true
              },
              "exercises": [{"name": "Bench Press", "catalogKey": "bench_press"}],
              "sessions": [{
                "date": 1750000000000,
                "note": "Workout",
                "exercises": [{
                  "name": "Bench Press",
                  "catalogKey": "bench_press",
                  "sets": [{"weight": 80.0, "reps": 8}]
                }]
              }],
              "summary": {
                "exerciseCount": 1,
                "sessionCount": 1,
                "setCount": 1,
                "totalVolume": 640.0
              }
            }
            """.trimIndent()
        )

        assertTrue(isCanonicalAndroidCloudEnvelope(canonical, userId))
        val iOSCanonical = JSONObject(canonical.toString()).apply {
            getJSONObject("owner").put("accountId", "cloud_$userId")
        }
        assertTrue(isCanonicalAndroidCloudEnvelope(iOSCanonical, userId))
        val forgedIOSAlias = JSONObject(canonical.toString()).apply {
            getJSONObject("owner").put(
                "accountId",
                "cloud_00000000-0000-4000-8000-000000000002"
            )
        }
        assertFalse(isCanonicalAndroidCloudEnvelope(forgedIOSAlias, userId))
        val unboundIOSAlias = JSONObject(iOSCanonical.toString()).apply {
            getJSONObject("owner").remove("userId")
        }
        assertFalse(isCanonicalAndroidCloudEnvelope(unboundIOSAlias, userId))
        val forgedPortableProvenance = JSONObject(canonical.toString()).apply {
            getJSONArray("sessions").getJSONObject(0).put("garminProvenance", true)
        }
        assertFalse(isCanonicalAndroidCloudEnvelope(forgedPortableProvenance, userId))
        canonical.put("catalogSeedVersion", 1)
        assertTrue(isCanonicalAndroidCloudEnvelope(canonical, userId))
        canonical.put("catalogSeedVersion", 2)
        assertTrue(isCanonicalAndroidCloudEnvelope(canonical, userId))
        canonical.put("catalogSeedVersion", BuiltInExerciseCatalog.SEED_VERSION)
        assertTrue(isCanonicalAndroidCloudEnvelope(canonical, userId))
        canonical.put("catalogSeedVersion", BuiltInExerciseCatalog.SEED_VERSION + 1)
        assertFalse(isCanonicalAndroidCloudEnvelope(canonical, userId))
        canonical.put("catalogSeedVersion", BuiltInExerciseCatalog.SEED_VERSION)
        assertTrue(canonicalWorkoutPayloadMatches(canonical, JSONObject(canonical.toString())))
        val legacyEightKeyEnvelope = JSONObject(canonical.toString()).apply {
            remove("catalogSeedVersion")
        }
        assertEquals(
            canonicalWorkoutPayloadDigest(legacyEightKeyEnvelope),
            canonicalWorkoutPayloadDigest(canonical)
        )
        val additiveLocalState = JSONObject(canonical.toString()).apply {
            getJSONArray("sessions").put(
                JSONObject()
                    .put("date", 1_750_000_001_000L)
                    .put("exercises", JSONArray().put(
                        JSONObject()
                            .put("name", "Squat")
                            .put("sets", JSONArray().put(
                                JSONObject().put("weight", 100.0).put("reps", 5)
                            ))
                    ))
            )
        }
        assertFalse(canonicalWorkoutPayloadMatches(canonical, additiveLocalState))
        assertTrue(shouldEnableCloudAutosave(true, true, session, session))
        assertFalse(
            shouldEnableCloudAutosave(
                pullSucceeded = true,
                canonicalRoundTripSafe = true,
                pulledSession = session,
                activeSession = cloudSession("generation-b")
            )
        )
        assertFalse(shouldEnableCloudAutosave(false, true, session, session))
    }

    @Test
    fun `account UI isolation key resets navigation and view models across auth boundaries`() {
        val refreshedSameGeneration = session.copy(
            accessToken = "replacement-token",
            refreshToken = "replacement-refresh"
        )
        val nextGeneration = cloudSession("generation-b")
        val otherUser = nextGeneration.copy(userId = "223e4567-e89b-12d3-a456-426614174000")

        val currentKey = accountUiIsolationKey(session, needsPasswordUpdate = false)
        assertEquals(
            currentKey,
            accountUiIsolationKey(refreshedSameGeneration, needsPasswordUpdate = false)
        )
        assertNotEquals(currentKey, accountUiIsolationKey(null, needsPasswordUpdate = false))
        assertNotEquals(currentKey, accountUiIsolationKey(nextGeneration, needsPasswordUpdate = false))
        assertNotEquals(currentKey, accountUiIsolationKey(otherUser, needsPasswordUpdate = false))
        assertNotEquals(currentKey, accountUiIsolationKey(session, needsPasswordUpdate = true))
        assertFalse(currentKey.contains(userId))
        assertFalse(currentKey.contains(session.accessToken))
    }

    @Test
    fun `only recoverable cloud synchronization notices expose retry`() {
        assertTrue(isRetryableCloudSyncMessage(LocalizedText(R.string.cloud_sync_load_failed)))
        assertTrue(isRetryableCloudSyncMessage(LocalizedText(R.string.cloud_sync_save_failed)))
        assertTrue(isRetryableCloudSyncMessage(LocalizedText(R.string.cloud_sync_conflict)))
        assertTrue(isRetryableCloudSyncMessage(LocalizedText(R.string.auth_error_connection)))
        assertTrue(isRetryableCloudSyncMessage(LocalizedText(R.string.auth_error_cloud_unavailable)))
        assertFalse(
            isRetryableCloudSyncMessage(LocalizedText(R.string.auth_message_password_updated))
        )
        assertFalse(isRetryableCloudSyncMessage(null))
        assertEquals(
            CloudSyncRetryMode.ResumeAutosave,
            cloudSyncRetryModeForSaveFailure(LocalizedText(R.string.cloud_sync_save_failed))
        )
        assertEquals(
            CloudSyncRetryMode.Pull,
            cloudSyncRetryModeForSaveFailure(LocalizedText(R.string.cloud_sync_conflict))
        )
    }

    @Test
    fun `native machine load profiles remain canonical but malformed profiles fail closed`() {
        val canonical = canonicalState()
        val exercise = canonical.getJSONArray("exercises").getJSONObject(0)
        exercise.put(
            "loadProfile",
            JSONObject()
                .put("direction", "higherIsHarder")
                .put("allowedWeightsKg", JSONArray(listOf(45.0, 50.0, 55.0)))
        )

        assertTrue(isCanonicalAndroidCloudEnvelope(canonical, userId))

        val redundantIOSProfile = JSONObject(canonical.toString()).apply {
            val catalogProfile = getJSONArray("exercises")
                .getJSONObject(0)
                .getJSONObject("loadProfile")
            getJSONArray("sessions")
                .getJSONObject(0)
                .getJSONArray("exercises")
                .getJSONObject(0)
                .put("loadProfile", JSONObject(catalogProfile.toString()))
        }
        assertTrue(isCanonicalAndroidCloudEnvelope(redundantIOSProfile, userId))

        val mismatchedIOSProfile = JSONObject(redundantIOSProfile.toString()).apply {
            getJSONArray("sessions")
                .getJSONObject(0)
                .getJSONArray("exercises")
                .getJSONObject(0)
                .getJSONObject("loadProfile")
                .put("allowedWeightsKg", JSONArray(listOf(40.0, 45.0)))
        }
        assertFalse(isCanonicalAndroidCloudEnvelope(mismatchedIOSProfile, userId))

        val unknownField = JSONObject(canonical.toString()).apply {
            getJSONArray("exercises").getJSONObject(0)
                .getJSONObject("loadProfile")
                .put("unsafe", true)
        }
        assertFalse(isCanonicalAndroidCloudEnvelope(unknownField, userId))

        val unsortedWeights = JSONObject(canonical.toString()).apply {
            getJSONArray("exercises").getJSONObject(0)
                .getJSONObject("loadProfile")
                .put("allowedWeightsKg", JSONArray(listOf(55.0, 50.0)))
        }
        assertFalse(isCanonicalAndroidCloudEnvelope(unsortedWeights, userId))
    }

    @Test
    fun `cloud baseline allows replace only for clean or empty local state`() {
        val baseline = "a".repeat(64)
        val remote = "b".repeat(64)

        assertEquals(
            CloudSnapshotApplyDecision.AlreadyCurrent,
            cloudSnapshotApplyDecision(remote, remote, baseline, localProjectionEmpty = false)
        )
        assertEquals(
            CloudSnapshotApplyDecision.ReplaceAuthoritatively,
            cloudSnapshotApplyDecision(baseline, remote, baseline, localProjectionEmpty = false)
        )
        assertEquals(
            CloudSnapshotApplyDecision.UploadLocal,
            cloudSnapshotApplyDecision(remote, baseline, baseline, localProjectionEmpty = false)
        )
        assertEquals(
            CloudSnapshotApplyDecision.ReplaceAuthoritatively,
            cloudSnapshotApplyDecision("c".repeat(64), remote, null, localProjectionEmpty = true)
        )
        assertEquals(
            CloudSnapshotApplyDecision.Conflict,
            cloudSnapshotApplyDecision("c".repeat(64), remote, baseline, localProjectionEmpty = false)
        )
        assertEquals(
            CloudSnapshotApplyDecision.Conflict,
            cloudSnapshotApplyDecision(null, remote, baseline, localProjectionEmpty = true)
        )
        assertTrue(shouldInitializeMissingRemoteState(localProjectionEmpty = true))
        assertFalse(shouldInitializeMissingRemoteState(localProjectionEmpty = false))
        assertTrue(shouldSeedCatalogAfterCloudPull(canonicalRoundTripSafe = true))
        assertFalse(shouldSeedCatalogAfterCloudPull(canonicalRoundTripSafe = false))
    }

    @Test
    fun `cloud conflict choice rejects stale context without side effects`() {
        val local = "a".repeat(64)
        val remote = "b".repeat(64)
        val conflict = CloudSyncConflictSnapshot(
            userId = userId,
            sessionGeneration = session.sessionGeneration,
            localDigest = local,
            remoteDigest = remote,
            remoteExists = true
        )

        assertTrue(isCurrentCloudSyncConflict(
            conflict, userId, session.sessionGeneration, local, remote, true
        ))
        assertFalse(isCurrentCloudSyncConflict(
            conflict,
            "223e4567-e89b-12d3-a456-426614174000",
            session.sessionGeneration,
            local,
            remote,
            true
        ))
        assertFalse(isCurrentCloudSyncConflict(
            conflict, userId, "new-generation", local, remote, true
        ))
        assertFalse(isCurrentCloudSyncConflict(
            conflict, userId, session.sessionGeneration, "c".repeat(64), remote, true
        ))
        assertFalse(isCurrentCloudSyncConflict(
            conflict, userId, session.sessionGeneration, local, "d".repeat(64), true
        ))
        assertFalse(isCurrentCloudSyncConflict(
            conflict, userId, session.sessionGeneration, local, remote, false
        ))

        var sideEffects = 0
        val accepted = runBlocking {
            runCurrentCloudSyncConflictAction(
                conflict,
                userId,
                session.sessionGeneration,
                local,
                remote,
                true
            ) {
                sideEffects += 1
                "accepted"
            }
        }
        assertEquals("accepted", accepted)
        assertEquals(1, sideEffects)

        val staleResult = runBlocking {
            runCatching {
                runCurrentCloudSyncConflictAction(
                    conflict,
                    userId,
                    session.sessionGeneration,
                    local,
                    "e".repeat(64),
                    true
                ) {
                    sideEffects += 1
                }
            }
        }
        assertTrue(staleResult.isFailure)
        assertEquals(1, sideEffects)

        val stalePresenceResult = runBlocking {
            runCatching {
                runCurrentCloudSyncConflictAction(
                    conflict,
                    userId,
                    session.sessionGeneration,
                    local,
                    remote,
                    false
                ) {
                    sideEffects += 1
                }
            }
        }
        assertTrue(stalePresenceResult.isFailure)
        assertEquals(1, sideEffects)

        val unverifiedRemote = conflict.copy(remoteDigest = null)
        assertTrue(isCurrentCloudSyncConflict(
            unverifiedRemote, userId, session.sessionGeneration, local, null, true
        ))
        assertFalse(isCurrentCloudSyncConflict(
            unverifiedRemote, userId, session.sessionGeneration, local, null, false
        ))
        assertFalse(isCurrentCloudSyncConflict(
            unverifiedRemote, userId, session.sessionGeneration, local, remote, true
        ))

        val missingRemote = conflict.copy(remoteDigest = null, remoteExists = false)
        assertTrue(isCurrentCloudSyncConflict(
            missingRemote, userId, session.sessionGeneration, local, null, false
        ))
        assertFalse(isCurrentCloudSyncConflict(
            missingRemote, userId, session.sessionGeneration, local, null, true
        ))
    }

    @Test
    fun `logout during debounce preserves Room data and resumes only against an unchanged remote`() {
        val remoteBaseline = "a".repeat(64)
        val unsyncedLocal = "b".repeat(64)
        val reloggedSession = session.copy(sessionGeneration = "generation-b")

        assertEquals(session.databaseName(), reloggedSession.databaseName())
        assertEquals(
            CloudSnapshotApplyDecision.UploadLocal,
            cloudSnapshotApplyDecision(
                localDigest = unsyncedLocal,
                remoteDigest = remoteBaseline,
                lastSyncedDigest = remoteBaseline,
                localProjectionEmpty = false
            )
        )
        assertEquals(
            CloudSnapshotApplyDecision.Conflict,
            cloudSnapshotApplyDecision(
                localDigest = unsyncedLocal,
                remoteDigest = "c".repeat(64),
                lastSyncedDigest = remoteBaseline,
                localProjectionEmpty = false
            )
        )
        assertFalse(shouldInitializeMissingRemoteState(localProjectionEmpty = false))
    }

    @Test
    fun `confirmed account deletion cleanup survives logout race and remains idempotent`() =
        runBlocking {
            assertTrue(accountActionsEnabled(authLoading = false, deletionInProgress = false))
            assertFalse(accountActionsEnabled(authLoading = true, deletionInProgress = false))
            assertFalse(accountActionsEnabled(authLoading = false, deletionInProgress = true))
            var roomRows = 3
            var baselinePresent = true
            var trainingProfilePresent = true
            var customMediaPresent = true
            var backupSharesPresent = true
            var restTimersPresent = true
            var liveStatePresent = true
            var garminAccountStatePresent = true

            repeat(2) {
                val failures = runConfirmedAccountDeletionLocalCleanup(
                    clearRoom = { roomRows = 0 },
                    clearBaseline = {
                        baselinePresent = false
                        true
                    },
                    clearTrainingProfile = {
                        trainingProfilePresent = false
                        true
                    },
                    clearCustomMedia = {
                        customMediaPresent = false
                        true
                    },
                    clearBackupShares = {
                        backupSharesPresent = false
                        true
                    },
                    clearRestTimers = {
                        restTimersPresent = false
                        true
                    },
                    clearLiveState = {
                        liveStatePresent = false
                        true
                    },
                    clearGarminState = {
                        garminAccountStatePresent = false
                        true
                    }
                )
                assertEquals(0, failures)
            }

            assertEquals(0, roomRows)
            assertFalse(baselinePresent)
            assertFalse(trainingProfilePresent)
            assertFalse(customMediaPresent)
            assertFalse(backupSharesPresent)
            assertFalse(restTimersPresent)
            assertFalse(liveStatePresent)
            assertFalse(garminAccountStatePresent)
            assertEquals(
                CloudAccountDeletionSessionDisposition.AlreadySignedOut,
                cloudAccountDeletionSessionDisposition(null, session)
            )
        }

    @Test
    fun `canonical workout digest ignores envelope metadata but detects data changes`() {
        val first = canonicalState()
        val envelopeOnlyChange = JSONObject(first.toString()).apply {
            put("exportedAt", 1_750_000_999_000L)
            getJSONObject("owner").put("email", "changed@example.test")
        }
        val workoutChange = JSONObject(first.toString()).apply {
            getJSONArray("sessions")
                .getJSONObject(0)
                .getJSONArray("exercises")
                .getJSONObject(0)
                .getJSONArray("sets")
                .getJSONObject(0)
                .put("reps", 9)
        }

        assertEquals(
            canonicalWorkoutPayloadDigest(first),
            canonicalWorkoutPayloadDigest(envelopeOnlyChange)
        )
        assertNotEquals(
            canonicalWorkoutPayloadDigest(first),
            canonicalWorkoutPayloadDigest(workoutChange)
        )
    }

    private fun canonicalState(): JSONObject = JSONObject(
        """
        {
          "schemaVersion": 2,
          "exportedAt": 1750000000000,
          "app": "GymApp",
          "diagnostics": false,
          "owner": {
            "accountId": "$userId",
            "userId": "$userId",
            "email": "user@example.test",
            "remote": true
          },
          "exercises": [{"name": "Bench Press", "catalogKey": "bench_press"}],
          "sessions": [{
            "date": 1750000000000,
            "note": "Workout",
            "exercises": [{
              "name": "Bench Press",
              "catalogKey": "bench_press",
              "sets": [{"weight": 80.0, "reps": 8}]
            }]
          }],
          "summary": {
            "exerciseCount": 1,
            "sessionCount": 1,
            "setCount": 1,
            "totalVolume": 640.0
          }
        }
        """.trimIndent()
    )

    private fun cloudSession(generation: String): AccountSession.Cloud = AccountSession.Cloud(
        userId = userId,
        email = "user@example.test",
        displayName = "User",
        accessToken = "token",
        refreshToken = "refresh",
        sessionGeneration = generation
    )
}
