package com.example.gymapp.navigation

import com.example.gymapp.auth.AccountSession
import com.example.gymapp.data.repository.canonicalWorkoutPayloadMatches
import com.example.gymapp.data.repository.canonicalWorkoutPayloadDigest
import com.example.gymapp.sync.CloudSnapshotApplyDecision
import com.example.gymapp.sync.cloudSnapshotApplyDecision
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

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
        assertTrue(canonicalWorkoutPayloadMatches(canonical, JSONObject(canonical.toString())))
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
