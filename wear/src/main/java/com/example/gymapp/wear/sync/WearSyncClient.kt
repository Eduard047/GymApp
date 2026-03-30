package com.example.gymapp.wear.sync

import android.content.Context
import com.example.gymapp.wear.data.WearWorkoutSetDraft
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

class WearSyncClient(
    context: Context
) {
    private val appContext = context.applicationContext

    suspend fun requestFullSync() {
        sendToPhone(SyncPaths.REQUEST_FULL_SYNC, ByteArray(0))
    }

    suspend fun createWorkout(
        startedAt: Long,
        note: String?,
        sets: List<WearWorkoutSetDraft>
    ) {
        val payload = WatchSyncJson
            .buildCreateWorkoutPayload(startedAt = startedAt, note = note, sets = sets)
            .toByteArray(Charsets.UTF_8)
        sendToPhone(SyncPaths.CREATE_WORKOUT, payload)
    }

    suspend fun updateSet(setId: Long, weight: Double, reps: Int) {
        val payload = WatchSyncJson
            .buildUpdateSetPayload(setId = setId, weight = weight, reps = reps)
            .toByteArray(Charsets.UTF_8)
        sendToPhone(SyncPaths.UPDATE_SET, payload)
    }

    suspend fun deleteSet(setId: Long) {
        val payload = WatchSyncJson
            .buildDeleteSetPayload(setId = setId)
            .toByteArray(Charsets.UTF_8)
        sendToPhone(SyncPaths.DELETE_SET, payload)
    }

    private suspend fun sendToPhone(path: String, payload: ByteArray) {
        val nodes = Wearable.getNodeClient(appContext).connectedNodes.await()
        if (nodes.isEmpty()) {
            throw IllegalStateException("Phone not connected")
        }

        nodes.forEach { node ->
            Wearable.getMessageClient(appContext)
                .sendMessage(node.id, path, payload)
                .await()
        }
    }
}
