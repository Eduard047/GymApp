package com.example.gymapp.sync

import android.content.Context
import com.example.gymapp.gymApplication
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.util.TrainingProfile

class PhoneSyncClient(
    context: Context
) {
    private val appContext = context.applicationContext

    suspend fun pushWorkoutPlan(
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>,
        trainingProfile: TrainingProfile
    ) {
        if (sets.isEmpty()) {
            throw IllegalArgumentException("Workout plan is empty")
        }

        val garminSyncManager = appContext.gymApplication.garminSyncManager
        val garminDelivered = runCatching {
            garminSyncManager.cacheAndPushPlan(
                sets = sets,
                exerciseCatalog = exerciseCatalog
            )
        }.getOrDefault(false)

        if (!garminDelivered) {
            throw IllegalStateException(garminSyncManager.lastPlanSyncStatus)
        }
    }
}
