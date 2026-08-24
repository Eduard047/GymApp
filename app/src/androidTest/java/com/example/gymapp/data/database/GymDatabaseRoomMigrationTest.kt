package com.example.gymapp.data.database

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GymDatabaseRoomMigrationTest {
    @get:Rule
    val migrationHelper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        GymDatabase::class.java
    )

    @Test
    fun migrationSevenToEightMatchesRoomSchemaAndPreservesUserData() {
        migrationHelper.createDatabase(TEST_DATABASE, 7).apply {
            execSQL("INSERT INTO exercises(id, name) VALUES (1, 'Keep exercise')")
            execSQL(
                "INSERT INTO workout_sessions(id, date, note) VALUES (2, 1750000000000, 'Keep workout')"
            )
            execSQL(
                "INSERT INTO workout_exercises(id, sessionId, exerciseId, orderIndex) VALUES (3, 2, 1, 0)"
            )
            execSQL(
                "INSERT INTO set_entries(id, workoutExerciseId, weight, reps, orderIndex) VALUES (4, 3, 82.5, 8, 0)"
            )
            execSQL("INSERT INTO app_metadata(id, catalogSeedVersion) VALUES (1, 7)")
            execSQL(
                """
                INSERT INTO garmin_workout_receipts(
                    ownerBinding, deviceBinding, requestId, payloadDigest,
                    workoutSessionId, createdAt
                ) VALUES (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf<Any>(
                    "a".repeat(64),
                    "12345",
                    "request-id-00001",
                    "b".repeat(64),
                    2L,
                    1_750_000_000_000L
                )
            )
            execSQL(
                """
                INSERT INTO wear_mutation_receipts(
                    ownerId, accountGeneration, operationId, sourceNodeId,
                    mutationType, payloadDigest, createdAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf<Any>(
                    "c".repeat(64),
                    1L,
                    "123e4567-e89b-42d3-a456-426614174000",
                    "retired-watch",
                    "create_workout",
                    "d".repeat(64),
                    1_750_000_000_000L
                )
            )
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            TEST_DATABASE,
            8,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query("SELECT name FROM exercises WHERE id = 1").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Keep exercise", cursor.getString(0))
            }
            migrated.query("SELECT note FROM workout_sessions WHERE id = 2").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Keep workout", cursor.getString(0))
            }
            migrated.query("SELECT weight, reps FROM set_entries WHERE id = 4").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(82.5, cursor.getDouble(0), 0.0)
                assertEquals(8, cursor.getInt(1))
            }
            migrated.query("SELECT catalogSeedVersion FROM app_metadata WHERE id = 1").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(7, cursor.getInt(0))
            }
            migrated.query("SELECT workoutSessionId FROM garmin_workout_receipts").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(2L, cursor.getLong(0))
            }
            migrated.query(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' " +
                    "AND name = 'wear_mutation_receipts'"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
            migrated.query(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' " +
                    "AND name = 'index_wear_mutation_receipts_createdAt'"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationEightToNineAddsFavoriteWithoutChangingExistingRows() {
        migrationHelper.createDatabase(FAVORITE_TEST_DATABASE, 8).apply {
            execSQL("INSERT INTO exercises(id, name) VALUES (1, 'Keep exercise')")
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            FAVORITE_TEST_DATABASE,
            9,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query("SELECT name, isFavorite FROM exercises WHERE id = 1").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Keep exercise", cursor.getString(0))
                assertEquals(0, cursor.getInt(1))
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationNineToTenIndexesGarminProvenanceWithoutChangingReceipts() {
        migrationHelper.createDatabase(GARMIN_INDEX_TEST_DATABASE, 9).apply {
            execSQL(
                """
                INSERT INTO garmin_workout_receipts(
                    ownerBinding, deviceBinding, requestId, payloadDigest,
                    workoutSessionId, createdAt
                ) VALUES (?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf<Any>(
                    "a".repeat(64),
                    "12345",
                    "request-id-00001",
                    "b".repeat(64),
                    42L,
                    1_750_000_000_000L
                )
            )
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            GARMIN_INDEX_TEST_DATABASE,
            10,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query(
                """
                SELECT ownerBinding, deviceBinding, requestId, payloadDigest,
                    workoutSessionId, createdAt
                FROM garmin_workout_receipts
                """.trimIndent()
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("a".repeat(64), cursor.getString(0))
                assertEquals("12345", cursor.getString(1))
                assertEquals("request-id-00001", cursor.getString(2))
                assertEquals("b".repeat(64), cursor.getString(3))
                assertEquals(42L, cursor.getLong(4))
                assertEquals(1_750_000_000_000L, cursor.getLong(5))
            }
            migrated.query(
                """
                EXPLAIN QUERY PLAN
                SELECT s.id,
                    CASE WHEN EXISTS (
                        SELECT 1
                        FROM garmin_workout_receipts receipt
                        WHERE receipt.workoutSessionId = s.id
                    ) THEN 1 ELSE 0 END AS hasGarminReceipt
                FROM workout_sessions s
                """.trimIndent()
            ).use { cursor ->
                val planDetails = buildList {
                    while (cursor.moveToNext()) add(cursor.getString(3))
                }
                assertTrue(
                    planDetails.any { detail ->
                        detail.contains(
                            "USING COVERING INDEX index_garmin_workout_receipts_workoutSessionId"
                        )
                    }
                )
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationTenToElevenBoundsReceiptsAndPreservesLiveGarminProvenance() {
        migrationHelper.createDatabase(GARMIN_LIFECYCLE_TEST_DATABASE, 10).apply {
            execSQL(
                "INSERT INTO workout_sessions(id, date, note) VALUES (42, 1750000000000, 'Garmin')"
            )
            repeat(GymDatabase.LEGACY_GARMIN_RECEIPT_LIMIT + 8) { index ->
                execSQL(
                    """
                    INSERT INTO garmin_workout_receipts(
                        ownerBinding, deviceBinding, requestId, payloadDigest,
                        workoutSessionId, createdAt
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """.trimIndent(),
                    arrayOf<Any>(
                        "a".repeat(64),
                        "12345",
                        "legacy-request-${index.toString().padStart(4, '0')}",
                        index.toString().padStart(64, 'a'),
                        42L,
                        1_750_000_000_000L + index
                    )
                )
            }
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            GARMIN_LIFECYCLE_TEST_DATABASE,
            11,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query(
                """
                SELECT COUNT(*), MIN(createdAt), MAX(createdAt), MIN(pairingGeneration)
                FROM garmin_workout_receipts
                """.trimIndent()
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(GymDatabase.LEGACY_GARMIN_RECEIPT_LIMIT, cursor.getInt(0))
                assertEquals(1_750_000_000_008L, cursor.getLong(1))
                assertEquals(1_750_000_000_519L, cursor.getLong(2))
                assertEquals(GymDatabase.LEGACY_GARMIN_PAIRING_GENERATION, cursor.getString(3))
            }
            migrated.query(
                "SELECT workoutSessionId FROM garmin_workout_provenance"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(42L, cursor.getLong(0))
            }
            migrated.setForeignKeyConstraintsEnabled(true)
            migrated.execSQL("DELETE FROM workout_sessions WHERE id = 42")
            migrated.query("SELECT COUNT(*) FROM garmin_workout_provenance").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
            migrated.query("SELECT COUNT(*) FROM garmin_workout_receipts").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(GymDatabase.LEGACY_GARMIN_RECEIPT_LIMIT, cursor.getInt(0))
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationElevenToTwelveAddsBoundedMachineProfilesAndPreservesExercises() {
        migrationHelper.createDatabase(LOAD_PROFILE_TEST_DATABASE, 11).apply {
            execSQL(
                "INSERT INTO exercises(id, name, isFavorite) VALUES (7, 'Lat Pulldown', 1)"
            )
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            LOAD_PROFILE_TEST_DATABASE,
            12,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query("SELECT name, isFavorite FROM exercises WHERE id = 7").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Lat Pulldown", cursor.getString(0))
                assertEquals(1, cursor.getInt(1))
            }
            migrated.execSQL(
                """
                INSERT INTO exercise_load_profiles(exerciseId, direction, updatedAt)
                VALUES (7, 'higherIsHarder', 1750000000000)
                """.trimIndent()
            )
            listOf(69.0, 73.0, 77.0).forEachIndexed { index, weight ->
                migrated.execSQL(
                    """
                    INSERT INTO exercise_weight_options(exerciseId, ordinal, weight)
                    VALUES (?, ?, ?)
                    """.trimIndent(),
                    arrayOf<Any>(7L, index, weight)
                )
            }
            migrated.query(
                "SELECT weight FROM exercise_weight_options WHERE exerciseId = 7 ORDER BY ordinal"
            ).use { cursor ->
                val weights = buildList {
                    while (cursor.moveToNext()) add(cursor.getDouble(0))
                }
                assertEquals(listOf(69.0, 73.0, 77.0), weights)
            }
            migrated.setForeignKeyConstraintsEnabled(true)
            migrated.execSQL("DELETE FROM exercises WHERE id = 7")
            migrated.query("SELECT COUNT(*) FROM exercise_load_profiles").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
            migrated.query("SELECT COUNT(*) FROM exercise_weight_options").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationTwelveToThirteenAddsEmptyLocalActiveWorkoutStoreAndPreservesHistory() {
        migrationHelper.createDatabase(ACTIVE_WORKOUT_TEST_DATABASE, 12).apply {
            execSQL(
                "INSERT INTO exercises(id, name, isFavorite) VALUES (7, 'Keep exercise', 1)"
            )
            execSQL(
                "INSERT INTO workout_sessions(id, date, note) VALUES (8, 1750000000000, 'Keep history')"
            )
            execSQL(
                """
                INSERT INTO workout_exercises(id, sessionId, exerciseId, orderIndex)
                VALUES (9, 8, 7, 0)
                """.trimIndent()
            )
            execSQL(
                """
                INSERT INTO set_entries(id, workoutExerciseId, weight, reps, orderIndex)
                VALUES (10, 9, 72.5, 9, 0)
                """.trimIndent()
            )
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            ACTIVE_WORKOUT_TEST_DATABASE,
            13,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query("SELECT name, isFavorite FROM exercises WHERE id = 7").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Keep exercise", cursor.getString(0))
                assertEquals(1, cursor.getInt(1))
            }
            migrated.query("SELECT note FROM workout_sessions WHERE id = 8").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Keep history", cursor.getString(0))
            }
            migrated.query("SELECT weight, reps FROM set_entries WHERE id = 10").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(72.5, cursor.getDouble(0), 0.0)
                assertEquals(9, cursor.getInt(1))
            }
            listOf(
                "active_workouts",
                "active_workout_exercises",
                "active_workout_sets"
            ).forEach { table ->
                migrated.query("SELECT COUNT(*) FROM $table").use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals(0, cursor.getInt(0))
                }
            }

            val exerciseRowId = "123e4567-e89b-42d3-a456-426614174000"
            val setRowId = "123e4567-e89b-42d3-a456-426614174001"
            migrated.execSQL(
                """
                INSERT INTO active_workouts(id, date, note, startedAt, revision)
                VALUES (1, 1750000000000, 'Local only', 1750000000000, 0)
                """.trimIndent()
            )
            migrated.execSQL(
                """
                INSERT INTO active_workout_exercises(
                    id, activeWorkoutId, exerciseName, catalogKey, orderIndex
                ) VALUES (?, 1, 'Keep exercise', NULL, 0)
                """.trimIndent(),
                arrayOf<Any>(exerciseRowId)
            )
            migrated.execSQL(
                """
                INSERT INTO active_workout_sets(
                    id, activeWorkoutExerciseId, weight, reps, orderIndex, completedAt
                ) VALUES (?, ?, 75.0, 8, 0, NULL)
                """.trimIndent(),
                arrayOf<Any>(setRowId, exerciseRowId)
            )
            migrated.setForeignKeyConstraintsEnabled(true)
            migrated.execSQL("DELETE FROM exercises WHERE id = 7")
            migrated.query("SELECT exerciseName FROM active_workout_exercises").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Keep exercise", cursor.getString(0))
            }
            migrated.execSQL("DELETE FROM active_workouts WHERE id = 1")
            migrated.query("SELECT COUNT(*) FROM active_workout_sets").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationThirteenToFourteenAddsDurableUndoMarkerAndPreservesActiveWorkout() {
        migrationHelper.createDatabase(UNDO_MARKER_TEST_DATABASE, 13).apply {
            val exerciseRowId = "123e4567-e89b-42d3-a456-426614174100"
            val setRowId = "123e4567-e89b-42d3-a456-426614174101"
            execSQL(
                """
                INSERT INTO active_workouts(id, date, note, startedAt, revision)
                VALUES (1, 1750000000000, 'Keep active workout', 1750000000000, 4)
                """.trimIndent()
            )
            execSQL(
                """
                INSERT INTO active_workout_exercises(
                    id, activeWorkoutId, exerciseName, catalogKey, orderIndex
                ) VALUES (?, 1, 'Keep exercise', NULL, 0)
                """.trimIndent(),
                arrayOf<Any>(exerciseRowId)
            )
            execSQL(
                """
                INSERT INTO active_workout_sets(
                    id, activeWorkoutExerciseId, weight, reps, orderIndex, completedAt
                ) VALUES (?, ?, 75.0, 8, 0, 1750000000100)
                """.trimIndent(),
                arrayOf<Any>(setRowId, exerciseRowId)
            )
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            UNDO_MARKER_TEST_DATABASE,
            14,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query(
                "SELECT revision, undoableSetId FROM active_workouts WHERE id = 1"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(4L, cursor.getLong(0))
                assertTrue(cursor.isNull(1))
            }
            migrated.query(
                "SELECT weight, reps, completedAt FROM active_workout_sets"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(75.0, cursor.getDouble(0), 0.0)
                assertEquals(8, cursor.getInt(1))
                assertEquals(1_750_000_000_100L, cursor.getLong(2))
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationFourteenToFifteenAddsDurationAndDatabaseBoundPlanDraft() {
        migrationHelper.createDatabase(DURATION_DRAFT_TEST_DATABASE, 14).apply {
            execSQL("INSERT INTO workout_sessions(id, date, note) VALUES (9, 1750000000000, 'Keep history')")
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            DURATION_DRAFT_TEST_DATABASE,
            15,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query(
                "SELECT note, durationSeconds FROM workout_sessions WHERE id = 9"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Keep history", cursor.getString(0))
                assertTrue(cursor.isNull(1))
            }
            migrated.execSQL(
                """
                INSERT INTO workout_plan_draft(id, payload, updatedAt)
                VALUES (1, '{"version":1}', 1750000000100)
                """.trimIndent()
            )
            migrated.query(
                "SELECT payload, updatedAt FROM workout_plan_draft WHERE id = 1"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("{\"version\":1}", cursor.getString(0))
                assertEquals(1_750_000_000_100L, cursor.getLong(1))
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationFifteenToSixteenAddsPrivateActivitySidecarWithoutChangingHistory() {
        migrationHelper.createDatabase(ACTIVITY_SIDECAR_TEST_DATABASE, 15).apply {
            execSQL(
                "INSERT INTO workout_sessions(id, date, note, durationSeconds) " +
                    "VALUES (21, 1750000000000, 'Existing activity', 1234)"
            )
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            ACTIVITY_SIDECAR_TEST_DATABASE,
            16,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query(
                "SELECT note, durationSeconds FROM workout_sessions WHERE id = 21"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Existing activity", cursor.getString(0))
                assertEquals(1_234L, cursor.getLong(1))
            }
            migrated.execSQL(
                """
                INSERT INTO activity_only_workouts(
                    workoutStartedAt, durationSeconds, gymCaloriesMillis, garminCalories,
                    averageHeartRate, maximumHeartRate, endingHeartRateZone, note
                ) VALUES (1750000000000, 1234, 87125, 92, 131, 168, 3, 'Existing activity')
                """.trimIndent()
            )
            migrated.execSQL(
                """
                INSERT INTO activity_only_workout_sync_journal(
                    id, ownerUserId, expectedRevision, requestId, itemsJson, itemsDigest
                ) VALUES (
                    1,
                    '11111111-1111-1111-1111-111111111111',
                    7,
                    '22222222-2222-2222-2222-222222222222',
                    '[]',
                    '${"a".repeat(64)}'
                )
                """.trimIndent()
            )
            migrated.query("SELECT COUNT(*) FROM activity_only_workouts").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(1, cursor.getInt(0))
            }
            migrated.query("SELECT expectedRevision FROM activity_only_workout_sync_journal")
                .use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals(7L, cursor.getLong(0))
                }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationSixteenToSeventeenPreservesSidecarAndJournalAndAddsExactBaseline() {
        val owner = "11111111-1111-1111-1111-111111111111"
        val request = "22222222-2222-2222-2222-222222222222"
        val digest = "a".repeat(64)
        migrationHelper.createDatabase(ACTIVITY_BASELINE_TEST_DATABASE, 16).apply {
            execSQL(
                """
                INSERT INTO activity_only_workouts(
                    workoutStartedAt, durationSeconds, gymCaloriesMillis, garminCalories,
                    averageHeartRate, maximumHeartRate, endingHeartRateZone, note
                ) VALUES (1750000000000, 1234, 87125, NULL, NULL, NULL, NULL, 'exact note')
                """.trimIndent()
            )
            execSQL(
                """
                INSERT INTO activity_only_workout_sync_journal(
                    id, ownerUserId, expectedRevision, requestId, itemsJson, itemsDigest
                ) VALUES (1, '$owner', 7, '$request', '[]', '$digest')
                """.trimIndent()
            )
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            ACTIVITY_BASELINE_TEST_DATABASE,
            17,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query(
                "SELECT gymCaloriesMillis, garminCalories, note FROM activity_only_workouts"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(87_125L, cursor.getLong(0))
                assertTrue(cursor.isNull(1))
                assertEquals("exact note", cursor.getString(2))
            }
            migrated.query(
                "SELECT ownerUserId, expectedRevision, requestId, itemsJson, itemsDigest " +
                    "FROM activity_only_workout_sync_journal"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(owner, cursor.getString(0))
                assertEquals(7L, cursor.getLong(1))
                assertEquals(request, cursor.getString(2))
                assertEquals("[]", cursor.getString(3))
                assertEquals(digest, cursor.getString(4))
            }
            val exactItems =
                "[{\"workoutStartedAt\":1750000000000,\"durationSeconds\":1234," +
                    "\"gymCalories\":87.125,\"note\":\"exact note\"}]"
            migrated.execSQL(
                """
                INSERT INTO activity_only_workout_sync_baseline(
                    id, ownerUserId, revision, itemsJson, itemsDigest
                ) VALUES (1, ?, 7, ?, ?)
                """.trimIndent(),
                arrayOf<Any>(owner, exactItems, digest)
            )
            migrated.query(
                "SELECT ownerUserId, revision, itemsJson, itemsDigest " +
                    "FROM activity_only_workout_sync_baseline"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(owner, cursor.getString(0))
                assertEquals(7L, cursor.getLong(1))
                assertEquals(exactItems, cursor.getString(2))
                assertEquals(digest, cursor.getString(3))
            }
        } finally {
            migrated.close()
        }
    }

    @Test
    fun migrationElevenToFourteenMatchesV229UpgradeAndPreservesHistory() {
        migrationHelper.createDatabase(V229_TO_ACTIVE_WORKOUT_TEST_DATABASE, 11).apply {
            execSQL(
                "INSERT INTO exercises(id, name, isFavorite) VALUES (17, 'v2.2.9 exercise', 1)"
            )
            execSQL(
                "INSERT INTO workout_sessions(id, date, note) VALUES (18, 1750000000000, 'v2.2.9 history')"
            )
            execSQL(
                """
                INSERT INTO workout_exercises(id, sessionId, exerciseId, orderIndex)
                VALUES (19, 18, 17, 0)
                """.trimIndent()
            )
            execSQL(
                """
                INSERT INTO set_entries(id, workoutExerciseId, weight, reps, orderIndex)
                VALUES (20, 19, 80.0, 6, 0)
                """.trimIndent()
            )
            close()
        }

        val migrated = migrationHelper.runMigrationsAndValidate(
            V229_TO_ACTIVE_WORKOUT_TEST_DATABASE,
            14,
            true,
            *GymDatabase.REGISTERED_MIGRATIONS
        )
        try {
            migrated.query("SELECT name, isFavorite FROM exercises WHERE id = 17").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("v2.2.9 exercise", cursor.getString(0))
                assertEquals(1, cursor.getInt(1))
            }
            migrated.query("SELECT note FROM workout_sessions WHERE id = 18").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("v2.2.9 history", cursor.getString(0))
            }
            migrated.query("SELECT weight, reps FROM set_entries WHERE id = 20").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(80.0, cursor.getDouble(0), 0.0)
                assertEquals(6, cursor.getInt(1))
            }
            listOf(
                "exercise_load_profiles",
                "exercise_weight_options",
                "active_workouts",
                "active_workout_exercises",
                "active_workout_sets"
            ).forEach { table ->
                migrated.query("SELECT COUNT(*) FROM $table").use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals(0, cursor.getInt(0))
                }
            }
        } finally {
            migrated.close()
        }
    }

    private companion object {
        const val TEST_DATABASE = "room-migration-7-to-8"
        const val FAVORITE_TEST_DATABASE = "room-migration-8-to-9"
        const val GARMIN_INDEX_TEST_DATABASE = "room-migration-9-to-10"
        const val GARMIN_LIFECYCLE_TEST_DATABASE = "room-migration-10-to-11"
        const val LOAD_PROFILE_TEST_DATABASE = "room-migration-11-to-12"
        const val ACTIVE_WORKOUT_TEST_DATABASE = "room-migration-12-to-13"
        const val UNDO_MARKER_TEST_DATABASE = "room-migration-13-to-14"
        const val DURATION_DRAFT_TEST_DATABASE = "room-migration-14-to-15"
        const val ACTIVITY_SIDECAR_TEST_DATABASE = "room-migration-15-to-16"
        const val ACTIVITY_BASELINE_TEST_DATABASE = "room-migration-16-to-17"
        const val V229_TO_ACTIVE_WORKOUT_TEST_DATABASE = "room-migration-11-to-14"
    }
}
