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
        if (messageEvent.path != SyncPaths.FULL_SYNC_PAYLOAD) {
            return
        }

        val rawPayload = messageEvent.data.toString(Charsets.UTF_8)
        val sessions = WatchSyncJson.parseFullSyncPayload(rawPayload)

        serviceScope.launch {
            val app = applicationContext as WearGymApplication
            app.repository.replaceSessionsFromSync(sessions)
        }
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }
}
