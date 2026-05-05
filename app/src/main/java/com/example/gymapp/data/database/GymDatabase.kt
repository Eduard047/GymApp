package com.example.gymapp.data.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.example.gymapp.data.dao.ExerciseDao
import com.example.gymapp.data.dao.MuscleMappingDao
import com.example.gymapp.data.dao.SetDao
import com.example.gymapp.data.dao.WorkoutDao
import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseMuscleMappingEntity
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutSessionEntity

@Database(
    entities = [
        ExerciseEntity::class,
        WorkoutSessionEntity::class,
        WorkoutExerciseEntity::class,
        SetEntryEntity::class,
        ExerciseMuscleMappingEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class GymDatabase : RoomDatabase() {
    abstract fun exerciseDao(): ExerciseDao
    abstract fun workoutDao(): WorkoutDao
    abstract fun setDao(): SetDao
    abstract fun muscleMappingDao(): MuscleMappingDao

    companion object {
        @Volatile
        private var INSTANCE: GymDatabase? = null

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

        fun getInstance(context: Context): GymDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    GymDatabase::class.java,
                    "gym_database"
                )
                    .addMigrations(MIGRATION_1_2)
                    .build()
                    .also { INSTANCE = it }
            }
        }
    }
}

