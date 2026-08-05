package com.example.gymapp.data.repository

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.data.catalog.BuiltInExerciseCatalog
import com.example.gymapp.data.database.GymDatabase
import com.example.gymapp.data.entity.AppMetadataEntity
import com.example.gymapp.data.entity.ExerciseEntity
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONArray
import org.json.JSONObject

@RunWith(AndroidJUnit4::class)
class BackupCatalogKeyImportTest {
    @Test
    fun duplicateTopLevelBuiltInAliasIsRejectedBeforeCloudReplacementMutation() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "duplicate-cloud-catalog-identity-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        val userId = "123e4567-e89b-12d3-a456-426614174000"

        try {
            val repository = GymRepository(database)
            val exerciseId = repository.addExercise("Bench Press")
            repository.createWorkoutSession(
                date = 1_750_000_000_000L,
                note = "Must survive rejected replacement",
                workoutExercises = listOf(
                    WorkoutExerciseDraft(
                        exerciseId = exerciseId,
                        sets = listOf(WorkoutSetDraft(weight = 80.0, reps = 8))
                    )
                )
            )

            val exercisesBefore = database.exerciseDao().getExercisesSnapshot()
            val sessionsBefore = database.workoutDao().getAllSessionDetailsForBackup()
            val projectionBefore = repository.getCloudWorkoutProjectionState()
            val remote = repository.buildCloudBackupJson(
                BackupOwner(
                    accountId = userId,
                    userId = userId,
                    remote = true
                )
            ).apply {
                // "жим лежачи" is a legacy alias of the already-exported bench_press row.
                // The two differently-spelled rows therefore have one canonical identity.
                getJSONArray("exercises").put(JSONObject().put("name", "жим лежачи"))
            }

            assertThrows(IllegalArgumentException::class.java) {
                runBlocking {
                    repository.replaceWithBackupJsonObject(
                        root = remote,
                        expectedLocalState = projectionBefore,
                        activeUserId = userId,
                        activeRemote = true
                    )
                }
            }

            val projectionAfter = repository.getCloudWorkoutProjectionState()
            assertEquals(exercisesBefore, database.exerciseDao().getExercisesSnapshot())
            assertEquals(sessionsBefore, database.workoutDao().getAllSessionDetailsForBackup())
            assertEquals(projectionBefore.digest, projectionAfter.digest)
            assertEquals(projectionBefore, projectionAfter)
            assertEquals(1, projectionAfter.exerciseCount)
            assertEquals(1, projectionAfter.sessionCount)
            assertEquals(1, projectionAfter.workoutExerciseCount)
            assertEquals(1, projectionAfter.setCount)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun iosLocalizedCatalogOrderRoundTripsThroughAndroidRoom() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "ios-catalog-order-${UUID.randomUUID()}"
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
                  "exercises": [
                    {"name": "Жим у тренажері"},
                    {"name": "Bench Press", "catalogKey": "bench_press"}
                  ],
                  "sessions": [],
                  "summary": {
                    "exerciseCount": 2,
                    "sessionCount": 0,
                    "setCount": 0,
                    "totalVolume": 0.0
                  }
                }
                """.trimIndent()
            )
            val remoteDigest = checkNotNull(canonicalWorkoutPayloadDigest(remote))

            assertEquals(
                0,
                repository.replaceWithBackupJsonObject(
                    root = remote,
                    expectedLocalState = repository.getCloudWorkoutProjectionState(),
                    activeUserId = userId,
                    activeRemote = true
                )
            )

            assertEquals(remoteDigest, repository.getCloudWorkoutProjectionState().digest)
            assertEquals(
                listOf("Bench Press", "Жим у тренажері"),
                database.exerciseDao().getExercisesSnapshot().map { it.name }
            )
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun favoriteRoundTripsInManualBackupButIsExcludedFromCloudProjection() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "favorite-backup-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        val userId = "123e4567-e89b-12d3-a456-426614174000"

        try {
            val repository = GymRepository(database)
            val exerciseId = repository.addExercise("Favorite row")
            repository.setExerciseFavorite(exerciseId, true)

            val manual = repository.buildBackupJson()
            assertTrue(manual.getJSONArray("exercises").getJSONObject(0).getBoolean("favorite"))

            val cloud = repository.buildCloudBackupJson(
                BackupOwner(
                    accountId = userId,
                    userId = userId,
                    remote = true
                )
            )
            assertFalse(cloud.getJSONArray("exercises").getJSONObject(0).has("favorite"))

            repository.setExerciseFavorite(exerciseId, false)
            repository.importBackupJsonObject(manual)
            assertTrue(database.exerciseDao().getById(exerciseId)?.isFavorite == true)

            val legacyManual = JSONObject(manual.toString()).apply {
                getJSONArray("exercises").getJSONObject(0).remove("favorite")
            }
            repository.importBackupJsonObject(legacyManual)
            assertTrue(database.exerciseDao().getById(exerciseId)?.isFavorite == true)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun loadProfileStaysLocalAcrossV229CloudReplacementAndIsExcludedFromDigest() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "local-load-profile-v229-cloud-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)
        val userId = "123e4567-e89b-12d3-a456-426614174000"

        try {
            val repository = GymRepository(database)
            val exerciseId = repository.addExercise("Plate-loaded machine")
            val localProfile = ExerciseLoadProfile(
                direction = ExerciseLoadDirection.HigherIsHarder,
                allowedWeightsKg = listOf(20.0, 40.0, 60.0)
            )
            repository.saveExerciseLoadProfile(exerciseId, localProfile)

            val projectionBefore = repository.getCloudWorkoutProjectionState()
            val manual = repository.buildBackupJson()
            val cloud = repository.buildCloudBackupJson(
                BackupOwner(accountId = userId, userId = userId, remote = true)
            )

            assertTrue(
                manual.getJSONArray("exercises").getJSONObject(0).has("loadProfile")
            )
            assertFalse(
                cloud.getJSONArray("exercises").getJSONObject(0).has("loadProfile")
            )
            assertEquals(canonicalWorkoutPayloadDigest(cloud), projectionBefore.digest)

            repository.replaceWithBackupJsonObject(
                root = cloud,
                expectedLocalState = projectionBefore,
                activeUserId = userId,
                activeRemote = true
            )

            val restoredManual = repository.buildBackupJson()
            val restoredProfile = restoredManual.getJSONArray("exercises").getJSONObject(0)
                .getJSONObject("loadProfile")
            assertEquals("higherIsHarder", restoredProfile.getString("direction"))
            assertEquals(
                listOf(20.0, 40.0, 60.0),
                List(restoredProfile.getJSONArray("allowedWeightsKg").length()) { index ->
                    restoredProfile.getJSONArray("allowedWeightsKg").getDouble(index)
                }
            )

            val restoredExerciseId = database.exerciseDao().getExercisesSnapshot().single().id
            repository.saveExerciseLoadProfile(
                restoredExerciseId,
                ExerciseLoadProfile(
                    direction = ExerciseLoadDirection.LowerIsHarder,
                    allowedWeightsKg = listOf(10.0, 20.0, 30.0)
                )
            )
            assertEquals(
                projectionBefore.digest,
                repository.getCloudWorkoutProjectionState().digest
            )
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun catalogSeedMarkerPreservesDeletedBuiltInExercise() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "catalog-seed-once-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            assertEquals(BuiltInExerciseCatalog.definitions.size, repository.seedBuiltInExercises())
            val bench = database.exerciseDao().getExercisesSnapshot()
                .first { it.name == "Bench Press" }

            repository.deleteExercise(bench)

            assertEquals(0, repository.seedBuiltInExercises())
            assertFalse(
                database.exerciseDao().getExercisesSnapshot().any { it.name == "Bench Press" }
            )
            assertEquals(
                BuiltInExerciseCatalog.SEED_VERSION,
                repository.buildBackupJson().getInt("catalogSeedVersion")
            )

            val cloud = repository.buildCloudBackupJson(
                BackupOwner(
                    accountId = "123e4567-e89b-12d3-a456-426614174000",
                    userId = "123e4567-e89b-12d3-a456-426614174000",
                    remote = true
                )
            )
            val cloudKeys = buildSet {
                val keys = cloud.keys()
                while (keys.hasNext()) add(keys.next())
            }
            assertEquals(
                setOf(
                    "schemaVersion",
                    "exportedAt",
                    "app",
                    "diagnostics",
                    "owner",
                    "exercises",
                    "sessions",
                    "summary"
                ),
                cloudKeys
            )
            assertFalse(cloud.has("catalogSeedVersion"))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun catalogUpgradeFromVersionOneRestoresOnlyMissingDefinitions() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "catalog-seed-v2-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            assertEquals(BuiltInExerciseCatalog.definitions.size, repository.seedBuiltInExercises())
            val exercises = database.exerciseDao().getExercisesSnapshot()
            repository.deleteExercise(exercises.first { it.name == "Bench Press" })
            repository.deleteExercise(exercises.first { it.name == "Hip Abduction" })
            database.appMetadataDao().upsert(AppMetadataEntity(catalogSeedVersion = 1))

            assertEquals(1, repository.seedBuiltInExercises())
            val upgraded = database.exerciseDao().getExercisesSnapshot()
            assertTrue(upgraded.any { it.name == "Hip Abduction" })
            assertFalse(upgraded.any { it.name == "Bench Press" })
            assertEquals(
                BuiltInExerciseCatalog.SEED_VERSION,
                repository.buildBackupJson().getInt("catalogSeedVersion")
            )
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun fullLegacyCatalogRemainsUsableAndRetriesSeedingLater() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "catalog-seed-capacity-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val backup = repository.buildBackupJson().apply {
                put(
                    "exercises",
                    JSONArray().apply {
                        repeat(WorkoutDataLimits.MAX_EXERCISES) { index ->
                            put(JSONObject().put("name", "Capacity exercise $index"))
                        }
                    }
                )
                getJSONObject("summary").put(
                    "exerciseCount",
                    WorkoutDataLimits.MAX_EXERCISES
                )
            }
            assertEquals(
                0,
                repository.importBackupJsonObject(backup)
            )

            assertEquals(0, repository.seedBuiltInExercises())
            assertEquals(
                WorkoutDataLimits.MAX_EXERCISES,
                database.exerciseDao().getExerciseCount()
            )
            assertEquals(0, repository.buildBackupJson().getInt("catalogSeedVersion"))
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }

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
                        "INSERT INTO exercises(name, isFavorite) VALUES (?, ?)",
                        arrayOf<Any>("Capacity exercise $index", 0)
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

    @Test
    fun legacyPortableNameCollisionRequiresAnExactExerciseNameWithoutMutation() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "legacy-name-collision-${UUID.randomUUID()}"
        val database = GymDatabase.getInstance(context, databaseName)

        try {
            val repository = GymRepository(database)
            val plainId = database.exerciseDao().insert(ExerciseEntity(name = "Legacy Custom"))
            val nbspId = database.exerciseDao().insert(ExerciseEntity(name = "Legacy\u00a0Custom"))

            assertThrows(IllegalArgumentException::class.java) {
                runBlocking {
                    repository.createWorkoutSessionFromNamedSets(
                        date = 1_750_000_000_000L,
                        note = "Must not be saved",
                        sets = listOf(
                            NamedWorkoutSetDraft("Legacy\u2007Custom", 40.0, 8)
                        )
                    )
                }
            }
            assertTrue(database.workoutDao().getAllSessionDetailsForBackup().isEmpty())
            assertEquals(
                setOf(plainId, nbspId),
                database.exerciseDao().getExercisesSnapshot().mapTo(linkedSetOf()) { it.id }
            )

            val sessionId = repository.createWorkoutSessionFromNamedSets(
                date = 1_750_000_001_000L,
                note = "Exact legacy name",
                sets = listOf(NamedWorkoutSetDraft("Legacy\u00a0Custom", 42.5, 8))
            )
            assertNotNull(sessionId)
            val stored = database.workoutDao().getAllSessionDetailsForBackup().single()
            assertEquals(nbspId, stored.workoutExercises.single().exercise.id)
            assertEquals("Exact legacy name", stored.session.note)
        } finally {
            database.close()
            context.deleteDatabase(databaseName)
        }
    }
}
