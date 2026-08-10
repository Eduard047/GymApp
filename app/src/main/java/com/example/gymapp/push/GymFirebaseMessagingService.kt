package com.example.gymapp.push

import com.example.gymapp.gymApplication
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class GymFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        gymApplication.pushManager.handleIncomingData(
            data = message.data,
            hasNotificationPayload = message.notification != null
        )
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        gymApplication.pushManager.onNewProviderToken(token)
    }
}
