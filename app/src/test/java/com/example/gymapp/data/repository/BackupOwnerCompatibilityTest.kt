package com.example.gymapp.data.repository

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class BackupOwnerCompatibilityTest {
    private val userId = "123e4567-e89b-12d3-a456-426614174000"

    @Test
    fun `flat ownerless PWA cloud state remains a bounded legacy import`() {
        val root = JSONObject(
            """
            {
              "language": "en",
              "exercises": [{"id": 1, "name": "Bench Press"}],
              "sessions": [{
                "id": 2,
                "startedAt": 1750000000000,
                "note": "PWA workout",
                "exerciseNames": ["Bench Press"],
                "sets": [{
                  "id": 3,
                  "exerciseName": "Bench Press",
                  "weight": 80.0,
                  "reps": 8,
                  "orderIndex": 0
                }]
              }]
            }
            """.trimIndent()
        )

        val backup = BackupImportValidator.validate(root)
        validateBackupOwnerContext(
            root = root,
            activeAccountId = null,
            activeUserId = userId,
            activeRemote = true
        )

        assertEquals(1, backup.sessions.size)
        assertEquals("Bench Press", backup.sessions.single().blocks.single().exercise.name)
        assertEquals(80.0, backup.sessions.single().blocks.single().sets.single().weight, 0.0)
        assertEquals(8, backup.sessions.single().blocks.single().sets.single().reps)
    }

    @Test
    fun `PWA export owner alias is accepted only for the same Supabase user`() {
        val matching = backupWithOwner(
            accountId = "remote-$userId",
            ownerUserId = userId,
            remote = "supabase"
        )
        BackupImportValidator.validate(matching)
        validateBackupOwnerContext(matching, null, userId, activeRemote = true)

        val wrongUser = backupWithOwner(
            accountId = "remote-00000000-0000-4000-8000-000000000002",
            ownerUserId = "00000000-0000-4000-8000-000000000002",
            remote = "supabase"
        )
        assertThrows(IllegalArgumentException::class.java) {
            validateBackupOwnerContext(wrongUser, null, userId, activeRemote = true)
        }

        val unboundAlias = backupWithOwner(
            accountId = "remote-$userId",
            ownerUserId = null,
            remote = "supabase"
        )
        assertThrows(IllegalArgumentException::class.java) {
            validateBackupOwnerContext(unboundAlias, null, userId, activeRemote = true)
        }
    }

    @Test
    fun `arbitrary legacy remote markers remain rejected`() {
        val root = backupWithOwner(
            accountId = "remote-$userId",
            ownerUserId = userId,
            remote = "attacker-controlled"
        )

        assertThrows(IllegalArgumentException::class.java) {
            BackupImportValidator.validate(root)
        }
    }

    @Test
    fun `portable Garmin provenance marker is ignored and cannot change canonical identity`() {
        val ordinary = JSONObject(
            """
            {
              "schemaVersion": 2,
              "sessions": [{
                "date": 1750000030000,
                "note": "Garmin · Duration 45:00 · Garmin kcal 250 · Avg HR 140",
                "exercises": [{
                  "name": "Bench Press",
                  "catalogKey": "bench_press",
                  "sets": [{"weight": 80.0, "reps": 8}]
                }]
              }]
            }
            """.trimIndent()
        )
        val marked = JSONObject(ordinary.toString()).apply {
            getJSONArray("sessions").getJSONObject(0).put("garminProvenance", true)
        }

        assertEquals(
            BackupImportValidator.validate(ordinary),
            BackupImportValidator.validate(marked)
        )
        assertEquals(
            canonicalWorkoutPayloadDigest(ordinary),
            canonicalWorkoutPayloadDigest(marked)
        )
    }

    private fun backupWithOwner(
        accountId: String,
        ownerUserId: String?,
        remote: Any
    ): JSONObject = JSONObject()
        .put("schemaVersion", 2)
        .put(
            "owner",
            JSONObject()
                .put("accountId", accountId)
                .put("userId", ownerUserId)
                .put("remote", remote)
        )
        .put("exercises", JSONArray())
        .put("sessions", JSONArray())
}
