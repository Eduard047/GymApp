package com.example.gymapp.data.database

import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GymDatabaseMigrationSecurityTest {
    @Test
    fun migrationFiveToSixAddsDurableGarminReceiptsWithoutDroppingWearReceipts() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "migration-garmin-receipts-${UUID.randomUUID()}"
        context.deleteDatabase(databaseName)
        val initial = openHelper(databaseName, 5, onCreate = { db ->
            db.execSQL(
                """
                CREATE TABLE wear_mutation_receipts (
                    ownerId TEXT NOT NULL,
                    accountGeneration INTEGER NOT NULL,
                    operationId TEXT NOT NULL,
                    sourceNodeId TEXT NOT NULL,
                    mutationType TEXT NOT NULL,
                    payloadDigest TEXT NOT NULL,
                    createdAt INTEGER NOT NULL,
                    PRIMARY KEY(ownerId, accountGeneration, operationId)
                )
                """.trimIndent()
            )
        })
        try {
            initial.writableDatabase.execSQL(
                """
                INSERT INTO wear_mutation_receipts(
                    ownerId, accountGeneration, operationId, sourceNodeId,
                    mutationType, payloadDigest, createdAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """.trimIndent(),
                arrayOf<Any>(
                    "a".repeat(64),
                    7L,
                    "123e4567-e89b-42d3-a456-426614174000",
                    "trusted-watch",
                    "create_workout",
                    "b".repeat(64),
                    1_750_000_000_000L
                )
            )
        } finally {
            initial.close()
        }

        val upgraded = openHelper(
            databaseName,
            6,
            onCreate = { error("Existing database should be upgraded") },
            onUpgrade = { db, oldVersion, newVersion ->
                assertEquals(5, oldVersion)
                assertEquals(6, newVersion)
                GymDatabase.MIGRATION_5_6.migrate(db)
            }
        )
        try {
            val db = upgraded.writableDatabase
            db.query("SELECT COUNT(*) FROM wear_mutation_receipts").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(1, cursor.getInt(0))
            }
            db.query("PRAGMA table_info(garmin_workout_receipts)").use { cursor ->
                val primaryKeys = linkedMapOf<String, Int>()
                while (cursor.moveToNext()) {
                    primaryKeys[cursor.getString(cursor.getColumnIndexOrThrow("name"))] =
                        cursor.getInt(cursor.getColumnIndexOrThrow("pk"))
                }
                assertEquals(1, primaryKeys["ownerBinding"])
                assertEquals(2, primaryKeys["deviceBinding"])
                assertEquals(3, primaryKeys["requestId"])
                assertEquals(0, primaryKeys["payloadDigest"])
                assertEquals(0, primaryKeys["workoutSessionId"])
            }
        } finally {
            upgraded.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun migrationFourToFiveAddsDurableWearReceiptTableWithoutDroppingExistingData() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "migration-wear-receipts-${UUID.randomUUID()}"
        context.deleteDatabase(databaseName)
        val initial = openHelper(databaseName, 4, onCreate = { db ->
            db.execSQL(
                "CREATE TABLE workout_sessions (id INTEGER PRIMARY KEY, date INTEGER NOT NULL, note TEXT)"
            )
        })
        try {
            initial.writableDatabase.execSQL(
                "INSERT INTO workout_sessions(id, date, note) VALUES (1, 1750000000000, 'keep')"
            )
        } finally {
            initial.close()
        }

        val upgraded = openHelper(
            databaseName,
            5,
            onCreate = { error("Existing database should be upgraded") },
            onUpgrade = { db, oldVersion, newVersion ->
                assertEquals(4, oldVersion)
                assertEquals(5, newVersion)
                GymDatabase.MIGRATION_4_5.migrate(db)
            }
        )
        try {
            val db = upgraded.writableDatabase
            db.query("SELECT note FROM workout_sessions WHERE id = 1").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("keep", cursor.getString(0))
            }
            db.query("PRAGMA table_info(wear_mutation_receipts)").use { cursor ->
                val primaryKeys = linkedMapOf<String, Int>()
                while (cursor.moveToNext()) {
                    primaryKeys[cursor.getString(cursor.getColumnIndexOrThrow("name"))] =
                        cursor.getInt(cursor.getColumnIndexOrThrow("pk"))
                }
                assertEquals(1, primaryKeys["ownerId"])
                assertEquals(2, primaryKeys["accountGeneration"])
                assertEquals(3, primaryKeys["operationId"])
                assertEquals(0, primaryKeys["payloadDigest"])
            }
            db.query("PRAGMA index_list(wear_mutation_receipts)").use { cursor ->
                val nameColumn = cursor.getColumnIndexOrThrow("name")
                var foundCreatedAtIndex = false
                while (cursor.moveToNext()) {
                    foundCreatedAtIndex = foundCreatedAtIndex ||
                        cursor.getString(nameColumn) == "index_wear_mutation_receipts_createdAt"
                }
                assertTrue(foundCreatedAtIndex)
            }
        } finally {
            upgraded.close()
            context.deleteDatabase(databaseName)
        }
    }

    @Test
    fun migrationTwoToThreePreservesMappingWhenOnlyDisplayCaseChanges() {
        assertCaseOnlyMappingSurvives(
            fromVersion = 2,
            toVersion = 3,
            beforeName = "гіперекстензія",
            afterName = "Гіперекстензія",
            migrate = GymDatabase.MIGRATION_2_3::migrate
        )
    }

    @Test
    fun migrationThreeToFourPreservesMappingWhenOnlyDisplayCaseChanges() {
        assertCaseOnlyMappingSurvives(
            fromVersion = 3,
            toVersion = 4,
            beforeName = "Гіперекстензія",
            afterName = "гіперекстензія",
            migrate = GymDatabase.MIGRATION_3_4::migrate
        )
    }

    @Test
    fun migrationTwoToThreeDoesNotMoveMappingsWhenRenameTargetAlreadyExists() {
        assertConflictingRenameKeepsBothMappings(
            fromVersion = 2,
            toVersion = 3,
            oldName = "Присід зі штангою",
            newName = "Присідання зі штангою",
            migrate = GymDatabase.MIGRATION_2_3::migrate
        )
    }

    @Test
    fun migrationThreeToFourDoesNotMoveMappingsWhenRenameTargetAlreadyExists() {
        assertConflictingRenameKeepsBothMappings(
            fromVersion = 3,
            toVersion = 4,
            oldName = "Присідання зі штангою",
            newName = "Присід зі штангою",
            migrate = GymDatabase.MIGRATION_3_4::migrate
        )
    }

    private fun assertCaseOnlyMappingSurvives(
        fromVersion: Int,
        toVersion: Int,
        beforeName: String,
        afterName: String,
        migrate: (SupportSQLiteDatabase) -> Unit
    ) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "migration-security-${UUID.randomUUID()}"
        context.deleteDatabase(databaseName)

        val initial = openHelper(databaseName, fromVersion, onCreate = { db ->
            db.execSQL("CREATE TABLE exercises (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
            db.execSQL(
                """
                CREATE TABLE exercise_muscle_mappings (
                    exerciseNameKey TEXT NOT NULL,
                    exerciseName TEXT NOT NULL,
                    muscleId TEXT NOT NULL,
                    weight REAL NOT NULL,
                    updatedAt INTEGER NOT NULL,
                    PRIMARY KEY(exerciseNameKey, muscleId)
                )
                """.trimIndent()
            )
        })

        try {
            initial.writableDatabase.apply {
                execSQL("INSERT INTO exercises (id, name) VALUES (?, ?)", arrayOf<Any>(1L, beforeName))
                execSQL(
                    """
                    INSERT INTO exercise_muscle_mappings
                        (exerciseNameKey, exerciseName, muscleId, weight, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """.trimIndent(),
                    arrayOf<Any>("гіперекстензія", beforeName, "lower_back", 1.0, 123L)
                )
            }
        } finally {
            initial.close()
        }

        val upgraded = openHelper(
            databaseName,
            toVersion,
            onCreate = { error("Existing database should be upgraded") },
            onUpgrade = { db, oldVersion, newVersion ->
                assertEquals(fromVersion, oldVersion)
                assertEquals(toVersion, newVersion)
                migrate(db)
            }
        )

        try {
            val db = upgraded.writableDatabase
            db.query("SELECT name FROM exercises WHERE id = 1").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(afterName, cursor.getString(0))
            }
            db.query(
                """
                SELECT exerciseNameKey, exerciseName, muscleId, weight
                FROM exercise_muscle_mappings
                """.trimIndent()
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("гіперекстензія", cursor.getString(0))
                assertEquals(afterName, cursor.getString(1))
                assertEquals("lower_back", cursor.getString(2))
                assertEquals(1.0, cursor.getDouble(3), 0.0)
                assertFalse(cursor.moveToNext())
            }
        } finally {
            upgraded.close()
            context.deleteDatabase(databaseName)
        }
    }

    private fun assertConflictingRenameKeepsBothMappings(
        fromVersion: Int,
        toVersion: Int,
        oldName: String,
        newName: String,
        migrate: (SupportSQLiteDatabase) -> Unit
    ) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val databaseName = "migration-conflict-${UUID.randomUUID()}"
        context.deleteDatabase(databaseName)
        val oldKey = oldName.lowercase()
        val newKey = newName.lowercase()

        val initial = openHelper(databaseName, fromVersion, onCreate = { db ->
            db.execSQL("CREATE TABLE exercises (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
            db.execSQL(
                """
                CREATE TABLE exercise_muscle_mappings (
                    exerciseNameKey TEXT NOT NULL,
                    exerciseName TEXT NOT NULL,
                    muscleId TEXT NOT NULL,
                    weight REAL NOT NULL,
                    updatedAt INTEGER NOT NULL,
                    PRIMARY KEY(exerciseNameKey, muscleId)
                )
                """.trimIndent()
            )
        })
        try {
            initial.writableDatabase.apply {
                execSQL("INSERT INTO exercises (id, name) VALUES (?, ?)", arrayOf<Any>(1L, oldName))
                execSQL("INSERT INTO exercises (id, name) VALUES (?, ?)", arrayOf<Any>(2L, newName))
                execSQL(
                    "INSERT INTO exercise_muscle_mappings VALUES (?, ?, ?, ?, ?)",
                    arrayOf<Any>(oldKey, oldName, "old-muscle", 0.25, 101L)
                )
                execSQL(
                    "INSERT INTO exercise_muscle_mappings VALUES (?, ?, ?, ?, ?)",
                    arrayOf<Any>(newKey, newName, "new-muscle", 0.75, 202L)
                )
            }
        } finally {
            initial.close()
        }

        val upgraded = openHelper(
            databaseName,
            toVersion,
            onCreate = { error("Existing database should be upgraded") },
            onUpgrade = { db, _, _ -> migrate(db) }
        )
        try {
            val db = upgraded.writableDatabase
            db.query("SELECT id, name FROM exercises ORDER BY id").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(1L, cursor.getLong(0))
                assertEquals(oldName, cursor.getString(1))
                assertTrue(cursor.moveToNext())
                assertEquals(2L, cursor.getLong(0))
                assertEquals(newName, cursor.getString(1))
                assertFalse(cursor.moveToNext())
            }
            db.query(
                "SELECT exerciseNameKey, exerciseName, muscleId, weight FROM exercise_muscle_mappings ORDER BY muscleId"
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(newKey, cursor.getString(0))
                assertEquals(newName, cursor.getString(1))
                assertEquals("new-muscle", cursor.getString(2))
                assertEquals(0.75, cursor.getDouble(3), 0.0)
                assertTrue(cursor.moveToNext())
                assertEquals(oldKey, cursor.getString(0))
                assertEquals(oldName, cursor.getString(1))
                assertEquals("old-muscle", cursor.getString(2))
                assertEquals(0.25, cursor.getDouble(3), 0.0)
                assertFalse(cursor.moveToNext())
            }
        } finally {
            upgraded.close()
            context.deleteDatabase(databaseName)
        }
    }

    private fun openHelper(
        name: String,
        version: Int,
        onCreate: (SupportSQLiteDatabase) -> Unit,
        onUpgrade: (SupportSQLiteDatabase, Int, Int) -> Unit = { _, _, _ -> }
    ): SupportSQLiteOpenHelper {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val callback = object : SupportSQLiteOpenHelper.Callback(version) {
            override fun onCreate(db: SupportSQLiteDatabase) = onCreate(db)

            override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) =
                onUpgrade(db, oldVersion, newVersion)
        }
        return FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name(name)
                .callback(callback)
                .build()
        )
    }
}
