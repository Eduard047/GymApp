package com.example.gymapp.wear

import android.app.Application
import com.example.gymapp.wear.data.WearWorkoutRepository
import com.example.gymapp.wear.data.db.WearDatabase

class WearGymApplication : Application() {
    val database: WearDatabase by lazy { WearDatabase.getInstance(this) }
    val repository: WearWorkoutRepository by lazy { WearWorkoutRepository(database) }
}
