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

    private companion object {
        const val TEST_DATABASE = "room-migration-7-to-8"
        const val FAVORITE_TEST_DATABASE = "room-migration-8-to-9"
        const val GARMIN_INDEX_TEST_DATABASE = "room-migration-9-to-10"
        const val GARMIN_LIFECYCLE_TEST_DATABASE = "room-migration-10-to-11"
    }
}
