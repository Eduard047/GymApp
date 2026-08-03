package com.example.gymapp.data.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.example.gymapp.data.dao.ExerciseDao
import com.example.gymapp.data.dao.ExerciseLoadProfileDao
import com.example.gymapp.data.dao.AppMetadataDao
import com.example.gymapp.data.dao.GarminWorkoutReceiptDao
import com.example.gymapp.data.dao.MuscleMappingDao
import com.example.gymapp.data.dao.SetDao
import com.example.gymapp.data.dao.WorkoutDao
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseLoadProfileEntity
import com.example.gymapp.data.entity.ExerciseWeightOptionEntity
import com.example.gymapp.data.entity.AppMetadataEntity
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.entity.GarminWorkoutReceiptEntity
import com.example.gymapp.data.entity.GarminWorkoutProvenanceEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutSessionEntity
import java.util.concurrent.ConcurrentHashMap

@Database(
    entities = [
        ExerciseEntity::class,
        ExerciseLoadProfileEntity::class,
        ExerciseWeightOptionEntity::class,
        AppMetadataEntity::class,
        WorkoutSessionEntity::class,
        WorkoutExerciseEntity::class,
        SetEntryEntity::class,
        ExerciseMuscleMappingEntity::class,
        GarminWorkoutReceiptEntity::class,
        GarminWorkoutProvenanceEntity::class
    ],
    version = 12,
    exportSchema = true
)
abstract class GymDatabase : RoomDatabase() {
    abstract fun exerciseDao(): ExerciseDao
    abstract fun exerciseLoadProfileDao(): ExerciseLoadProfileDao
    abstract fun appMetadataDao(): AppMetadataDao
    abstract fun workoutDao(): WorkoutDao
    abstract fun setDao(): SetDao
    abstract fun muscleMappingDao(): MuscleMappingDao
    abstract fun garminWorkoutReceiptDao(): GarminWorkoutReceiptDao

    companion object {
        private val INSTANCES = ConcurrentHashMap<String, GymDatabase>()

        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS exercise_muscle_mappings (
                        exerciseNameKey TEXT NOT NULL,
                        exerciseName TEXT NOT NULL,
                        muscleId TEXT NOT NULL,
                        weight REAL NOT NULL,
                        updatedAt INTEGER NOT NULL,
                        PRIMARY KEY(exerciseNameKey, muscleId)
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE INDEX IF NOT EXISTS index_exercise_muscle_mappings_exerciseName
                    ON exercise_muscle_mappings(exerciseName)
                    """.trimIndent()
                )
            }
        }

        private val EXERCISE_RENAMES = listOf(
            "Присід зі штангою" to "Присідання зі штангою",
            "жим лежачи" to "Жим штанги лежачи",
            "гіперекстензія" to "Гіперекстензія",
            "прес(підйом ніг)" to "Підйом ніг у висі",
            "прес з диском в сторони" to "Повороти корпусу з диском",
            "прес звичайний з диском" to "Скручування з диском",
            "жим ногами" to "Жим ногами у тренажері",
            "згибання ніг" to "Згинання ніг у тренажері",
            "розгинання ніг" to "Розгинання ніг у тренажері",
            "підйом на носки" to "Підйом на носки стоячи",
            "румунська тяга" to "Румунська тяга",
            "зведення ніг" to "Зведення ніг у тренажері",
            "підтягування з резинкою" to "Підтягування з еспандером",
            "журавель" to "Тяга верхніх блоків у тренажері",
            "горизонтальна важільна тяга" to "Горизонтальна тяга у важільному тренажері",
            "штанга на біцепс" to "Згинання рук зі штангою",
            "фронтальна тяга" to "Тяга верхнього блока до грудей",
            "тренажер скота(біцепс)" to "Згинання рук на лаві Скотта",
            "метелик в сторони" to "Зворотні розведення у тренажері",
            "метелик в середину" to "Зведення рук у тренажері",
            "гантелі лежачи" to "Жим гантелей лежачи",
            "брусья" to "Віджимання на брусах",
            "трицепс трикутник" to "Розгинання рук на блоці з V-рукояттю",
            "протяжка" to "Тяга штанги до підборіддя",
            "махи в сторони" to "Підйоми гантелей через сторони",
            "гантеля над головою" to "Розгинання гантелі над головою",
            "станова тяга" to "Станова тяга",
            "жим сидячи" to "Жим сидячи над головою",
            "біцепс з гантелями сидячи" to "Згинання рук з гантелями сидячи",
            "підтягування в гравітроні" to "Підтягування у гравітроні",
            "французький жим" to "Французький жим",
            "бокові нахили" to "Бокові нахили з обтяженням",
            "Нахили в сторони на гіперекстензії" to "Бокові нахили на гіперекстензії"
        )

        internal val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                EXERCISE_RENAMES.forEach { (oldName, newName) ->
                    val oldKey = oldName.toExerciseMappingKey()
                    val newKey = newName.toExerciseMappingKey()
                    db.execSQL(
                        """
                        UPDATE exercises
                        SET name = '${newName.sqlEscaped()}'
                        WHERE name = '${oldName.sqlEscaped()}'
                            AND NOT EXISTS (
                                SELECT 1
                                FROM exercises
                                WHERE name = '${newName.sqlEscaped()}'
                            )
                        """.trimIndent()
                    )
                    val exerciseWasRenamed = db.query("SELECT changes()").use { cursor ->
                        cursor.moveToFirst() && cursor.getInt(0) > 0
                    }
                    if (!exerciseWasRenamed) return@forEach
                    if (oldKey == newKey) {
                        db.execSQL(
                            """
                            UPDATE exercise_muscle_mappings
                            SET exerciseName = '${newName.sqlEscaped()}',
                                updatedAt = strftime('%s', 'now') * 1000
                            WHERE exerciseNameKey = '${oldKey.sqlEscaped()}'
                            """.trimIndent()
                        )
                    } else {
                        db.execSQL(
                            """
                            UPDATE exercise_muscle_mappings
                            SET exerciseNameKey = '${newKey.sqlEscaped()}',
                                exerciseName = '${newName.sqlEscaped()}',
                                updatedAt = strftime('%s', 'now') * 1000
                            WHERE exerciseNameKey = '${oldKey.sqlEscaped()}'
                                AND NOT EXISTS (
                                    SELECT 1
                                    FROM exercise_muscle_mappings existing
                                    WHERE existing.exerciseNameKey = '${newKey.sqlEscaped()}'
                                        AND existing.muscleId = exercise_muscle_mappings.muscleId
                                )
                            """.trimIndent()
                        )
                        db.execSQL(
                            """
                            DELETE FROM exercise_muscle_mappings
                            WHERE exerciseNameKey = '${oldKey.sqlEscaped()}'
                            """.trimIndent()
                        )
                    }
                }
            }
        }

        internal val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                EXERCISE_RENAMES.forEach { (oldName, newName) ->
                    val oldKey = oldName.toExerciseMappingKey()
                    val newKey = newName.toExerciseMappingKey()
                    db.execSQL(
                        """
                        UPDATE exercises
                        SET name = '${oldName.sqlEscaped()}'
                        WHERE name = '${newName.sqlEscaped()}'
                            AND NOT EXISTS (
                                SELECT 1
                                FROM exercises
                                WHERE name = '${oldName.sqlEscaped()}'
                            )
                        """.trimIndent()
                    )
                    val exerciseWasRenamed = db.query("SELECT changes()").use { cursor ->
                        cursor.moveToFirst() && cursor.getInt(0) > 0
                    }
                    if (!exerciseWasRenamed) return@forEach
                    if (oldKey == newKey) {
                        db.execSQL(
                            """
                            UPDATE exercise_muscle_mappings
                            SET exerciseName = '${oldName.sqlEscaped()}',
                                updatedAt = strftime('%s', 'now') * 1000
                            WHERE exerciseNameKey = '${newKey.sqlEscaped()}'
                            """.trimIndent()
                        )
                    } else {
                        db.execSQL(
                            """
                            UPDATE exercise_muscle_mappings
                            SET exerciseNameKey = '${oldKey.sqlEscaped()}',
                                exerciseName = '${oldName.sqlEscaped()}',
                                updatedAt = strftime('%s', 'now') * 1000
                            WHERE exerciseNameKey = '${newKey.sqlEscaped()}'
                                AND NOT EXISTS (
                                    SELECT 1
                                    FROM exercise_muscle_mappings existing
                                    WHERE existing.exerciseNameKey = '${oldKey.sqlEscaped()}'
                                        AND existing.muscleId = exercise_muscle_mappings.muscleId
                                )
                            """.trimIndent()
                        )
                        db.execSQL(
                            """
                            DELETE FROM exercise_muscle_mappings
                            WHERE exerciseNameKey = '${newKey.sqlEscaped()}'
                            """.trimIndent()
                        )
                    }
                }
            }
        }

        internal val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS wear_mutation_receipts (
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
                db.execSQL(
                    """
                    CREATE INDEX IF NOT EXISTS index_wear_mutation_receipts_createdAt
                    ON wear_mutation_receipts(createdAt)
                    """.trimIndent()
                )
            }
        }

        internal val MIGRATION_5_6 = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS garmin_workout_receipts (
                        ownerBinding TEXT NOT NULL,
                        deviceBinding TEXT NOT NULL,
                        requestId TEXT NOT NULL,
                        payloadDigest TEXT NOT NULL,
                        workoutSessionId INTEGER NOT NULL,
                        createdAt INTEGER NOT NULL,
                        PRIMARY KEY(ownerBinding, deviceBinding, requestId)
                    )
                    """.trimIndent()
                )
            }
        }

        internal val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS app_metadata (
                        id INTEGER NOT NULL,
                        catalogSeedVersion INTEGER NOT NULL,
                        PRIMARY KEY(id)
                    )
                    """.trimIndent()
                )
            }
        }

        internal val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("DROP INDEX IF EXISTS index_wear_mutation_receipts_createdAt")
                db.execSQL("DROP TABLE IF EXISTS wear_mutation_receipts")
            }
        }

        internal val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "ALTER TABLE exercises ADD COLUMN isFavorite INTEGER NOT NULL DEFAULT 0"
                )
            }
        }

        internal val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE INDEX IF NOT EXISTS index_garmin_workout_receipts_workoutSessionId
                    ON garmin_workout_receipts(workoutSessionId)
                    """.trimIndent()
                )
            }
        }

        internal val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS garmin_workout_provenance (
                        workoutSessionId INTEGER NOT NULL,
                        PRIMARY KEY(workoutSessionId),
                        FOREIGN KEY(workoutSessionId) REFERENCES workout_sessions(id)
                            ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT OR IGNORE INTO garmin_workout_provenance(workoutSessionId)
                    SELECT DISTINCT receipt.workoutSessionId
                    FROM garmin_workout_receipts receipt
                    INNER JOIN workout_sessions session
                        ON session.id = receipt.workoutSessionId
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TABLE garmin_workout_receipts_v11 (
                        ownerBinding TEXT NOT NULL,
                        deviceBinding TEXT NOT NULL,
                        pairingGeneration TEXT NOT NULL,
                        requestId TEXT NOT NULL,
                        payloadDigest TEXT NOT NULL,
                        createdAt INTEGER NOT NULL,
                        PRIMARY KEY(ownerBinding, deviceBinding, pairingGeneration, requestId)
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    INSERT INTO garmin_workout_receipts_v11(
                        ownerBinding, deviceBinding, pairingGeneration, requestId,
                        payloadDigest, createdAt
                    )
                    SELECT ownerBinding, deviceBinding, '$LEGACY_GARMIN_PAIRING_GENERATION',
                        requestId, payloadDigest, createdAt
                    FROM garmin_workout_receipts
                    ORDER BY createdAt DESC, rowid DESC
                    LIMIT $LEGACY_GARMIN_RECEIPT_LIMIT
                    """.trimIndent()
                )
                db.execSQL("DROP TABLE garmin_workout_receipts")
                db.execSQL(
                    "ALTER TABLE garmin_workout_receipts_v11 RENAME TO garmin_workout_receipts"
                )
                db.execSQL(
                    """
                    CREATE INDEX index_garmin_workout_receipts_ownerBinding_deviceBinding_pairingGeneration_createdAt
                    ON garmin_workout_receipts(
                        ownerBinding, deviceBinding, pairingGeneration, createdAt
                    )
                    """.trimIndent()
                )
            }
        }

        internal val MIGRATION_11_12 = object : Migration(11, 12) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS exercise_load_profiles (
                        exerciseId INTEGER NOT NULL,
                        direction TEXT NOT NULL,
                        updatedAt INTEGER NOT NULL,
                        PRIMARY KEY(exerciseId),
                        FOREIGN KEY(exerciseId) REFERENCES exercises(id)
                            ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS exercise_weight_options (
                        exerciseId INTEGER NOT NULL,
                        ordinal INTEGER NOT NULL,
                        weight REAL NOT NULL,
                        PRIMARY KEY(exerciseId, ordinal),
                        FOREIGN KEY(exerciseId) REFERENCES exercises(id)
                            ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE UNIQUE INDEX IF NOT EXISTS
                        index_exercise_weight_options_exerciseId_weight
                    ON exercise_weight_options(exerciseId, weight)
                    """.trimIndent()
                )
            }
        }

        internal val REGISTERED_MIGRATIONS: Array<Migration> = arrayOf(
            MIGRATION_1_2,
            MIGRATION_2_3,
            MIGRATION_3_4,
            MIGRATION_4_5,
            MIGRATION_5_6,
            MIGRATION_6_7,
            MIGRATION_7_8,
            MIGRATION_8_9,
            MIGRATION_9_10,
            MIGRATION_10_11,
            MIGRATION_11_12
        )

        fun getInstance(context: Context, databaseName: String = "gym_database"): GymDatabase {
            val safeName = databaseName
                .replace(Regex("[^A-Za-z0-9_.-]"), "_")
                .ifBlank { "gym_database" }
            return INSTANCES.getOrPut(safeName) {
                Room.databaseBuilder(
                    context.applicationContext,
                    GymDatabase::class.java,
                    safeName
                )
                    .addMigrations(*REGISTERED_MIGRATIONS)
                    .build()
            }
        }

        private fun String.toExerciseMappingKey(): String {
            return lowercase()
                .replace('ʼ', '\'')
                .replace('’', '\'')
                .replace('ё', 'е')
                .replace(Regex("\\s+"), " ")
                .trim()
        }

        private fun String.sqlEscaped(): String = replace("'", "''")

        internal const val LEGACY_GARMIN_PAIRING_GENERATION =
            "0000000000000000000000000000000000000000000000000000000000000000"
        internal const val LEGACY_GARMIN_RECEIPT_LIMIT = 512
    }
}
