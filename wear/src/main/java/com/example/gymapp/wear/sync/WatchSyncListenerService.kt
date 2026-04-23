package com.example.gymapp.wear.sync

import com.example.gymapp.wear.WearGymApplication
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class WatchSyncListenerService : WearableListenerService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)
        when (messageEvent.path) {
            SyncPaths.FULL_SYNC_PAYLOAD -> {
                val rawPayload = messageEvent.data.toString(Charsets.UTF_8)
                val sessions = WatchSyncJson.parseFullSyncPayload(rawPayload)
                val exerciseCatalog = WatchSyncJson.parseExerciseCatalogFromFullSync(rawPayload)

                WatchExerciseCatalogStorage.save(
                    context = applicationContext,
                    exerciseNames = exerciseCatalog
                )

                serviceScope.launch {
                    val app = applicationContext as WearGymApplication
                    app.repository.replaceSessionsFromSync(sessions)
                }
            }

            SyncPaths.PUSH_WORKOUT_PLAN -> {
                val rawPayload = messageEvent.data.toString(Charsets.UTF_8)
                WatchPlanStorage.save(applicationContext, rawPayload)
                val exerciseCatalog = WatchSyncJson.parseExerciseCatalogFromWorkoutPlan(rawPayload)
                if (exerciseCatalog.isNotEmpty()) {
                    WatchExerciseCatalogStorage.save(
                        context = applicationContext,
                        exerciseNames = exerciseCatalog
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }
}
