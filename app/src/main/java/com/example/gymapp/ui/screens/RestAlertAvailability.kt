package com.example.gymapp.ui.screens

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import com.example.gymapp.service.RestTimerService

/**
 * True when RestTimerService's finished notification cannot alert right now: system notifications are
 * off for the app, or the rest-timer finished channel is blocked. A missing channel (the service has
 * not created it yet) is not blocked.
 */
internal fun restAlertsCurrentlyMuted(context: Context): Boolean {
    val appContext = context.applicationContext
    val notificationsEnabled = NotificationManagerCompat.from(appContext).areNotificationsEnabled()
    val channelBlocked = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        appContext.getSystemService(NotificationManager::class.java)
            ?.getNotificationChannel(RestTimerService.CHANNEL_FINISHED_ID)
            ?.importance == NotificationManager.IMPORTANCE_NONE
    return restAlertsMuted(notificationsEnabled, channelBlocked)
}

/** Opens the app's system notification settings (app details before Android 8). Never throws. */
internal fun openAppNotificationSettings(context: Context) {
    val packageName = context.applicationContext.packageName
    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
    } else {
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
    }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.applicationContext.startActivity(intent) }
}
