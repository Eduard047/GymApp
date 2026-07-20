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

    private companion object {
        const val TEST_DATABASE = "room-migration-7-to-8"
    }
}
