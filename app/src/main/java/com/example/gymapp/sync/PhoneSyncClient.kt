package com.example.gymapp.sync

import android.content.Context
import com.example.gymapp.garmin.GARMIN_PLAN_QUEUED_STATUS
import com.example.gymapp.gymApplication
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.util.TrainingProfile

/** Outcome of a plan push that did not fail: sent to the watch, or saved and waiting for it. */
enum class PlanPushResult { Delivered, Queued }

/** Maps the Garmin manager result to a non-error outcome, or throws the manager status. */
internal fun planPushResult(delivered: Boolean, status: String): PlanPushResult = when {
    delivered -> PlanPushResult.Delivered
    status == GARMIN_PLAN_QUEUED_STATUS -> PlanPushResult.Queued
    else -> throw IllegalStateException(status)
}

class PhoneSyncClient(
    context: Context
) {
    private val appContext = context.applicationContext

    suspend fun pushWorkoutPlan(
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>,
        trainingProfile: TrainingProfile
    ): PlanPushResult {
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

        return planPushResult(garminDelivered, garminSyncManager.lastPlanSyncStatus)
    }
}
