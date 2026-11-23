package com.example.gymapp.wear.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.example.gymapp.wear.data.dao.WearWorkoutDao
import com.example.gymapp.wear.data.entity.WearSetEntryEntity
import com.example.gymapp.wear.data.entity.WearWorkoutSessionEntity

@Database(
    entities = [
        WearWorkoutSessionEntity::class,
        WearSetEntryEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class WearDatabase : RoomDatabase() {
    abstract fun workoutDao(): WearWorkoutDao

    companion object {
        @Volatile
        private var INSTANCE: WearDatabase? = null

        fun getInstance(context: Context): WearDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    WearDatabase::class.java,
                    "gym_wear_database"
                ).build().also { INSTANCE = it }
            }
        }
    }
}
