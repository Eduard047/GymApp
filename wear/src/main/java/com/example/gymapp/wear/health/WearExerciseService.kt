package com.example.gymapp.wear.health

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import com.example.gymapp.wear.MainActivity
import com.example.gymapp.wear.R

/**
 * Keeps the process alive as a `health` foreground service while an exercise is being tracked,
 * so Health Services keeps delivering heart rate when the screen is off or the app is
 * backgrounded. It does no work itself; [WearExerciseTracker] owns the ExerciseClient.
 */
class WearExerciseService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_workout_channel),
                NotificationManager.IMPORTANCE_LOW
            )
        )
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(getString(R.string.notification_workout_title))
            .setContentText(getString(R.string.notification_workout_text))
            .setCategory(Notification.CATEGORY_WORKOUT)
            .setOngoing(true)
            .setContentIntent(openApp)
            .build()
        try {
            // ServiceCompat passes the health type only where the platform knows it (API 34+).
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
                } else {
                    0
                }
            )
        } catch (_: RuntimeException) {
            // Missing permission or a background start: tracking still works while the app is in
            // front, so give up the keep-alive instead of crashing the workout. Safe because the
            // service is started with startService(), which carries no startForeground() promise.
            stopSelf()
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL_ID = "workout"
        private const val NOTIFICATION_ID = 1001

        fun start(context: Context) {
            // Deliberately not startForegroundService(): if startForeground() is then refused
            // (permission revoked, type not allowed) the system would crash the app for the
            // broken promise. The tracker starts while the app is visible, where a plain start
            // is allowed and may still be promoted to the foreground.
            runCatching { context.startService(Intent(context, WearExerciseService::class.java)) }
        }

        fun stop(context: Context) {
            runCatching { context.stopService(Intent(context, WearExerciseService::class.java)) }
        }
    }
}
