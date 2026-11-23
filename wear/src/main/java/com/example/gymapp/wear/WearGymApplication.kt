package com.example.gymapp.wear

import android.app.Application
import com.example.gymapp.wear.data.WearWorkoutRepository
import com.example.gymapp.wear.data.db.WearDatabase
import com.example.gymapp.wear.health.WearExerciseTracker

class WearGymApplication : Application() {
    val database: WearDatabase by lazy { WearDatabase.getInstance(this) }
    val repository: WearWorkoutRepository by lazy { WearWorkoutRepository(database) }

    /** Process-wide: the Health Services exercise outlives any one ViewModel or Activity. */
    val exerciseTracker: WearExerciseTracker by lazy { WearExerciseTracker(this) }
}
