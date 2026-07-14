package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.database.GymDatabase
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject

@RunWith(AndroidJUnit4::class)
class BackupCatalogKeyImportTest {
    @Test
    fun authoritativeRestorePreservesRepeatedBlocksAndIdenticalSessions() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "authoritative-exact-shape-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        val userId = "123e4567-e89b-12d3-a456-426614174000"

        try {
            val repository = GymRepository(database)
            val sessionJson =
                """
                {
                  "date": 1750000001000,
                  "note": "Repeated shape",
                  "exercises": [
                    {
                      "name": "Bench Press",
                      "catalogKey": "bench_press",
                      "sets": [{"weight": 80.0, "reps": 8}]
                    },
                    {
                      "name": "Bench Press",
                      "catalogKey": "bench_press",
                      "sets": [{"weight": 82.5, "reps": 6}]
                    }
                  ]
                }
                """.trimIndent()
            val remote = JSONObject(
                """
                {
                  "schemaVersion": 2,
                  "exportedAt": 1750000002000,
                  "app": "GymApp",
                  "diagnostics": false,
                  "owner": {
                    "accountId": "$userId",
                    "userId": "$userId",
                    "remote": true
                  },
                  "exercises": [{"name": "Bench Press", "catalogKey": "bench_press"}],
                  "sessions": [$sessionJson, $sessionJson],
                  "summary": {
                    "exerciseCount": 1,
                    "sessionCount": 2,
                    "setCount": 4,
                    "totalVolume": 2275.0
                  }
                }
                """.trimIndent()
            )

            assertEquals(
                2,
                repository.replaceWithBackupJsonObject(
                    root = remote,
                    expectedLocalState = repository.getCloudWorkoutProjectionState(),
                    activeUserId = userId,
                    activeRemote = true
                )
            )

            val restored = database.workoutDao().getAllSessionDetailsForBackup()
            assertEquals(2, restored.size)
            restored.forEach { session ->
                assertEquals(2, session.workoutExercises.size)
                assertEquals(
                    listOf(80.0, 82.5),
                    session.workoutExercises
                        .sortedBy { it.workoutExercise.orderIndex }
                        .map { it.sets.single().weight }
                )
            }
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun canonicalCloudSnapshotAuthoritativelyReplacesDeletedLocalRows() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "authoritative-cloud-replace-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        val userId = "123e4567-e89b-12d3-a456-426614174000"

        try {
            val repository = GymRepository(database)
            val staleExerciseId = repository.addExercise("Stale local exercise")
            repository.createWorkoutSession(
                date = 1_750_000_000_000L,
                note = "Must be deleted",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = staleExerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 10.0, reps = 10))
                    )
                )
            )
            val remote = JSONObject(
                """
                {
                  "schemaVersion": 2,
                  "exportedAt": 1750000001000,
                  "app": "GymApp",
                  "diagnostics": false,
                  "owner": {
                    "accountId": "$userId",
                    "userId": "$userId",
                    "remote": true
                  },
                  "exercises": [{"name": "Remote exercise"}],
                  "sessions": [{
                    "date": 1750000001000,
                    "note": "Remote only",
                    "exercises": [{
                      "name": "Remote exercise",
                      "sets": [{"weight": 20.0, "reps": 5}]
                    }]
                  }],
                  "summary": {
                    "exerciseCount": 1,
                    "sessionCount": 1,
                    "setCount": 1,
                    "totalVolume": 100.0
                  }
                }
                """.trimIndent()
            )

            assertEquals(
                1,
                repository.replaceWithBackupJsonObject(
                    root = remote,
                    expectedLocalState = repository.getCloudWorkoutProjectionState(),
                    activeUserId = userId,
                    activeRemote = true
                )
            )

            val exercises = database.exerciseDao().getExercisesSnapshot()
            val sessions = database.workoutDao().getAllSessionDetailsForBackup()
            assertEquals(listOf("Remote exercise"), exercises.map { it.name })
            assertEquals(1, sessions.size)
            assertEquals("Remote only", sessions.single().session.note)
            assertFalse(sessions.single().workoutExercises.any {
                it.exercise.name == "Stale local exercise"
            })
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun invalidCloudOwnerIsRejectedBeforeAuthoritativeDeletion() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "authoritative-cloud-owner-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val exerciseId = repository.addExercise("Preserved exercise")
            repository.createWorkoutSession(
                date = 1_750_000_000_000L,
                note = "Preserved workout",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = exerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 10.0, reps = 10))
                    )
                )
            )
            val wrongOwner = JSONObject(
                """
                {
                  "schemaVersion": 2,
                  "owner": {
                    "accountId": "other-user",
                    "userId": "other-user",
                    "remote": true
                  },
                  "exercises": [],
                  "sessions": []
                }
                """.trimIndent()
            )

            assertThrows(IllegalArgumentException::class.java) {
                runBlocking {
                    repository.replaceWithBackupJsonObject(
                        root = wrongOwner,
                        expectedLocalState = repository.getCloudWorkoutProjectionState(),
                        activeUserId = "current-user",
                        activeRemote = true
                    )
                }
            }

            assertEquals(1, database.exerciseDao().getExercisesSnapshot().size)
            assertEquals(1, database.workoutDao().getAllSessionDetailsForBackup().size)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun diagnosticsExportContainsCountsButNoWorkoutOrAccountContent() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "redacted-diagnostics-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val exerciseId = repository.addExercise("Private exercise name")
            repository.createWorkoutSession(
                date = 1_750_000_000_000L,
                note = "Private workout note",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = exerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 12.5, reps = 8))
                    )
                )
            )

            val raw = repository.exportDiagnosticsJson()
            val root = JSONObject(raw)
            val summary = root.getJSONObject("summary")

            assertEquals(
                setOf("schemaVersion", "exportedAt", "app", "diagnostics", "summary"),
                root.keys().asSequence().toSet()
            )
            assertEquals(1, summary.getInt("exerciseCount"))
            assertEquals(1, summary.getInt("sessionCount"))
            assertEquals(1, summary.getInt("setCount"))
            assertFalse(raw.contains("Private exercise name"))
            assertFalse(raw.contains("Private workout note"))
            assertFalse(raw.contains("owner"))
            assertFalse(raw.contains("12.5"))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun exerciseCrudRejectsBuiltInAliasesAsDuplicates() {
        runBlocking {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val databaseName = "catalog-key-duplicates-${UUID.randomUUID()}"
            val database = GymDatabase.getInstance(context, databaseName)

            try {
                val repository = GymRepository(database)
                repository.addExercise("Присідання зі штангою")
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { repository.addExercise("Squat") }
                }

                val customID = repository.addExercise("My custom movement")
                val custom = database.exerciseDao().getExercisesSnapshot().single { it.id == customID }
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { repository.renameExercise(custom, "Barbell Squat") }
                }
            } finally {
                database.close()
                context.deleteDatabase(databaseName)
            }
        }
    }

    @Test
    fun recognizedRawNamesAreNotRedirectedByHostileOrMalformedCatalogKeys() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "catalog-key-import-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val benchID = repository.addExercise("Bench Press")
            val squatID = repository.addExercise("Присідання зі штангою")
            val rawBackup =
                """
                {
                  "schemaVersion": 2,
                  "exportedAt": 1750000000000,
                  "app": "GymApp",
                  "diagnostics": false,
                  "exercises": [],
                  "sessions": [
                    {
                      "date": 1750000000000,
                      "exercises": [
                        {
                          "name": "Squat",
                          "catalogKey": "bench_press",
                          "sets": [{"weight": 80.0, "reps": 8}]
                        },
                        {
                          "name": "Barbell Squat",
                          "catalogKey": "not-a-real-catalog-key",
                          "sets": [{"weight": 82.5, "reps": 6}]
                        },
                        {
                          "name": "My unrecognized movement",
                          "catalogKey": "bench_press",
                          "sets": [{"weight": 12.5, "reps": 10}]
                        }
                      ]
                    }
                  ]
                }
                """.trimIndent()

            assertEquals(1, repository.importBackupJson(rawBackup))

            val importedWorkout = repository.getLatestWorkoutTemplate()
            assertNotNull(importedWorkout)
            val importedExercises = importedWorkout!!.workoutExercises
            assertEquals(2, importedExercises.size)
            val importedSquat = importedExercises.single { it.exercise.id == squatID }
            assertEquals(2, importedSquat.sets.size)
            val custom = importedExercises.single { it.exercise.id != squatID }
            assertEquals("My unrecognized movement", custom.exercise.name)
            assertEquals(1, custom.sets.size)
            assertFalse(importedExercises.any { it.exercise.id == benchID })
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun invalidLateSetRejectsWholeBackupBeforeAnyDatabaseMutation() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "bounded-import-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val rawBackup =
                """
                {
                  "schemaVersion": 2,
                  "exercises": [{"name": "Must not persist"}],
                  "sessions": [{
                    "date": 1750000000000,
                    "exercises": [{
                      "name": "Bench Press",
                      "sets": [
                        {"weight": 80.0, "reps": 8},
                        {"weight": 80.0, "reps": 10001}
                      ]
                    }]
                  }]
                }
                """.trimIndent()

            assertThrows(IllegalArgumentException::class.java) {
                runBlocking { repository.importBackupJson(rawBackup) }
            }
            assertTrue(database.exerciseDao().getExercisesSnapshot().isEmpty())
            assertTrue(database.workoutDao().getAllSessionDetailsForBackup().isEmpty())
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun malformedCollectionTypeIsRejectedInsteadOfTreatedAsEmpty() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "typed-import-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking {
                    repository.importBackupJson("{\"schemaVersion\":2,\"sessions\":{}}")
                }
            }
            assertTrue(database.workoutDao().getAllSessionDetailsForBackup().isEmpty())
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun namedGarminSetsReuseNormalizedExerciseAtAccountCapacity() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "named-set-capacity-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val benchId = repository.addExercise("Bench Press")
            val sqlite = database.openHelper.writableDatabase
            sqlite.beginTransaction()
            try {
                for (index in 1 until WorkoutDataLimits.MAX_EXERCISES) {
                    sqlite.execSQL(
                        "INSERT INTO exercises(name) VALUES (?)",
                        arrayOf<Any>("Capacity exercise $index")
                    )
                }
                sqlite.setTransactionSuccessful()
            } finally {
                sqlite.endTransaction()
            }

            val sessionId = repository.createWorkoutSessionFromNamedSets(
                date = 1_750_000_000_000L,
                note = "Garmin",
                sets = listOf(NamedWorkoutSetDraft("bench press", 80.0, 8))
            )

            assertNotNull(sessionId)
            assertEquals(WorkoutDataLimits.MAX_EXERCISES, database.exerciseDao().getExercisesSnapshot().size)
            assertEquals(
                benchId,
                repository.getLatestWorkoutTemplate()!!.workoutExercises.single().exercise.id
            )
            assertThrows(IllegalArgumentException::class.java) {
                runBlocking {
                    repository.createWorkoutSessionFromNamedSets(
                        date = 1_750_000_001_000L,
                        note = null,
                        sets = listOf(NamedWorkoutSetDraft("Capacity overflow", 10.0, 10))
                    )
                }
            }
            assertEquals(WorkoutDataLimits.MAX_EXERCISES, database.exerciseDao().getExercisesSnapshot().size)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
