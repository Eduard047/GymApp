package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.sync.SharedCloudStateSource
import com.example.gymapp.sync.attachSharedCloudExtensions
import com.example.gymapp.sync.prepareSharedCloudState
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SharedCloudStateMigrationTest {
    @Test
    fun freshDeviceTreatsMissingSharedCloudSeedMarkerAsCurrent() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "shared-cloud-fresh-seed-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        val userId = "123e4567-e89b-12d3-a456-426614174000"

        try {
            val repository = GymRepository(database)
            val remote = JSONObject(
                """
                {
                  "schemaVersion": 2,
                  "exportedAt": 1750000000000,
                  "app": "GymApp",
                  "diagnostics": false,
                  "owner": {
                    "accountId": "$userId",
                    "userId": "$userId",
                    "remote": true
                  },
                  "exercises": [{"name": "Cloud Custom Move"}],
                  "sessions": [],
                  "summary": {
                    "exerciseCount": 1,
                    "sessionCount": 0,
                    "setCount": 0,
                    "totalVolume": 0.0
                  }
                }
                """.trimIndent()
            )

            repository.replaceWithBackupJsonObject(
                root = remote,
                expectedLocalState = repository.getCloudWorkoutProjectionState(),
                activeUserId = userId,
                activeRemote = true
            )

            assertEquals(
                BuiltInExerciseCatalog.SEED_VERSION,
                repository.buildBackupJson().getInt("catalogSeedVersion")
            )
            assertEquals(0, repository.seedBuiltInExercises())
            assertEquals(
                listOf("Cloud Custom Move"),
                database.exerciseDao().getExercisesSnapshot().map { it.name }
            )
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun ownerlessPwaWorkoutRoundTripsThroughRoomIntoV229CompatibleSharedState() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "shared-cloud-pwa-migration-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        val userId = "123e4567-e89b-12d3-a456-426614174000"

        try {
            val repository = GymRepository(database)
            val legacy = JSONObject(
                """
                {
                  "language": "uk",
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
                  }],
                  "mappings": {"Bench Press": ["chest"]},
                  "profile": {
                    "split": "Full Body",
                    "days": 4,
                    "goal": "Balanced",
                    "calories": "Maintenance"
                  }
                }
                """.trimIndent()
            )
            val preparedLegacy = prepareSharedCloudState(legacy, userId)
            val initialState = repository.getCloudWorkoutProjectionState()

            repository.replaceWithBackupJsonObject(
                root = legacy,
                expectedLocalState = initialState,
                activeUserId = userId,
                activeRemote = true
            )

            val importedState = repository.getCloudWorkoutProjectionState()
            assertEquals(preparedLegacy.workoutDigest, importedState.digest)
            val stored = database.workoutDao().getAllSessionDetailsForBackup().single()
            assertEquals("PWA workout", stored.session.note)
            assertEquals("Bench Press", stored.workoutExercises.single().exercise.name)
            assertEquals(80.0, stored.workoutExercises.single().sets.single().weight, 0.0)

            val canonical = attachSharedCloudExtensions(
                canonicalCore = repository.buildCloudBackupJson(
                    BackupOwner(
                        accountId = userId,
                        userId = userId,
                        remote = true
                    )
                ),
                extensions = preparedLegacy.extensions
            )
            val preparedCanonical = prepareSharedCloudState(canonical, userId)
            assertEquals(SharedCloudStateSource.CanonicalV2, preparedCanonical.source)
            assertEquals(importedState.digest, preparedCanonical.workoutDigest)
            assertFalse(canonical.has("extensions"))
            assertNull(preparedCanonical.extensions)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun backdatedWorkoutExportsBeforeNewerWorkout() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "shared-cloud-backdated-export-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        val userId = "123e4567-e89b-12d3-a456-426614174000"

        try {
            val repository = GymRepository(database)
            val newerDate = 1750000001000
            val backdatedDate = 1750000000000
            val set = listOf(
                NamedWorkoutSetDraft(exerciseName = "Bench Press", weight = 80.0, reps = 8)
            )
            repository.createWorkoutSessionFromNamedSets(newerDate, "newer", set)
            repository.createWorkoutSessionFromNamedSets(backdatedDate, "backdated", set)

            val cloud = repository.buildCloudBackupJson(
                BackupOwner(accountId = userId, userId = userId, remote = true)
            )
            val sessions = cloud.getJSONArray("sessions")

            assertEquals(backdatedDate, sessions.getJSONObject(0).getLong("date"))
            assertEquals(newerDate, sessions.getJSONObject(1).getLong("date"))
            assertEquals("backdated", sessions.getJSONObject(0).getString("note"))
            assertEquals("newer", sessions.getJSONObject(1).getString("note"))
            assertEquals(
                SharedCloudStateSource.CanonicalV2,
                prepareSharedCloudState(cloud, userId).source
            )
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
