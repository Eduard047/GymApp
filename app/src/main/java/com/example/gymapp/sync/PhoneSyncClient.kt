package com.example.gymapp.sync

import android.content.Context
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

        val payload = PhoneSyncJson.encodeWorkoutPlanPayload(
            sets = sets,
            exerciseCatalog = exerciseCatalog,
            trainingProfile = trainingProfile
        )
            .toByteArray(Charsets.UTF_8)
        val nodes = Wearable.getNodeClient(appContext).connectedNodes.await()
        if (nodes.isEmpty()) {
            throw IllegalStateException("Watch not connected")
        }

        nodes.forEach { node ->
            Wearable.getMessageClient(appContext)
                .sendMessage(node.id, SyncPaths.PUSH_WORKOUT_PLAN, payload)
                .await()
        }
    }
}
