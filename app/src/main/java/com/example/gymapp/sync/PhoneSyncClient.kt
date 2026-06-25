package com.example.gymapp.sync

import android.content.Context
import com.example.gymapp.gymApplication
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.util.TrainingProfile
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

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

        val garminDelivered = runCatching {
            appContext.gymApplication.garminSyncManager.cacheAndPushPlan(
                sets = sets,
                exerciseCatalog = exerciseCatalog
            )
        }.getOrDefault(false)

        val payload = PhoneSyncJson.encodeWorkoutPlanPayload(
            sets = sets,
            exerciseCatalog = exerciseCatalog,
            trainingProfile = trainingProfile
        )
            .toByteArray(Charsets.UTF_8)

        val nodes = runCatching {
            Wearable.getNodeClient(appContext).connectedNodes.await()
        }.getOrElse { error ->
            if (garminDelivered) {
                emptyList()
            } else {
                throw error
            }
        }

        if (nodes.isEmpty()) {
            if (garminDelivered) return
            throw IllegalStateException("Watch not connected")
        }

        val wearSendFailed = nodes.any { node ->
            runCatching {
                Wearable.getMessageClient(appContext)
                    .sendMessage(node.id, SyncPaths.PUSH_WORKOUT_PLAN, payload)
                    .await()
            }.isFailure
        }

        if (wearSendFailed && !garminDelivered) {
            throw IllegalStateException("Watch not connected")
        }
    }
}
