package com.example.gymapp.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.gymapp.MainActivity
import com.example.gymapp.R
import com.example.gymapp.util.RestTimerState
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class RestTimerService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var countdownJob: Job? = null
    private var remainingSeconds: Int = 0
    private val notificationManager by lazy { getSystemService(NotificationManager::class.java) }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val durationSeconds = intent.getIntExtra(EXTRA_DURATION_SECONDS, 0)
                startTimer(durationSeconds)
            }

            ACTION_STOP,
            ACTION_DISMISS_ALERT -> stopTimer()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // Android 14+ ends a short foreground service after about three minutes, and a rest can run
    // longer. Without stopping here the system reports an ANR, so the rest continues as a plain
    // countdown notification and an alarm posts the finished alert.
    @Deprecated("Replaced by onTimeout(startId, fgsType) on Android 15")
    override fun onTimeout(startId: Int) {
        handOffAfterTimeout()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        handOffAfterTimeout()
    }

    private fun handOffAfterTimeout() {
        val seconds = remainingSeconds
        countdownJob?.cancel()
        countdownJob = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (seconds > 0) {
            val endsAt = System.currentTimeMillis() + seconds * 1_000L
            notifySafely(NOTIFICATION_RUNNING_ID, buildHandedOffNotification(endsAt, seconds))
            scheduleFinishedAlarm(this, endsAt)
        }
        stopSelf()
    }

    override fun onDestroy() {
        countdownJob?.cancel()
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun startTimer(durationSeconds: Int) {
        if (durationSeconds <= 0) {
            stopTimer()
            return
        }

        countdownJob?.cancel()
        cancelFinishedAlarm(this)
        cancelNotification(NOTIFICATION_FINISHED_ID)

        remainingSeconds = durationSeconds
        RestTimerState.update(remainingSeconds)
        startForeground(NOTIFICATION_RUNNING_ID, buildRunningNotification(remainingSeconds))

        countdownJob = serviceScope.launch {
            while (remainingSeconds > 0 && isActive) {
                delay(1_000)
                remainingSeconds -= 1
                RestTimerState.update(remainingSeconds)

                if (remainingSeconds > 0) {
                    notifySafely(
                        NOTIFICATION_RUNNING_ID,
                        buildRunningNotification(remainingSeconds)
                    )
                } else {
                    onTimerFinished()
                }
            }
        }
    }

    private fun onTimerFinished() {
        RestTimerState.update(0)
        stopForeground(STOP_FOREGROUND_REMOVE)
        cancelNotification(NOTIFICATION_RUNNING_ID)
        notifySafely(NOTIFICATION_FINISHED_ID, buildFinishedNotification(this))
        stopSelf()
    }

    private fun stopTimer() {
        countdownJob?.cancel()
        countdownJob = null
        cancelFinishedAlarm(this)
        remainingSeconds = 0
        RestTimerState.update(0)
        cancelNotification(NOTIFICATION_FINISHED_ID)
        cancelNotification(NOTIFICATION_RUNNING_ID)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildRunningNotification(remainingSeconds: Int): Notification {
        return NotificationCompat.Builder(this, CHANNEL_RUNNING_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(getString(R.string.timer_notification_running_title))
            .setContentText(
                getString(
                    R.string.timer_notification_running_text,
                    formatSeconds(remainingSeconds)
                )
            )
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(createOpenAppPendingIntent(this))
            .addAction(
                android.R.drawable.ic_media_pause,
                getString(R.string.action_stop_timer),
                createStopTimerPendingIntent(this)
            )
            .build()
    }

    /** The running notification after the service stopped: the system counts down on its own. */
    private fun buildHandedOffNotification(endsAt: Long, remainingSeconds: Int): Notification {
        return NotificationCompat.Builder(this, CHANNEL_RUNNING_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(getString(R.string.timer_notification_running_title))
            .setWhen(endsAt)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setTimeoutAfter(remainingSeconds * 1_000L)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(createOpenAppPendingIntent(this))
            .addAction(
                android.R.drawable.ic_media_pause,
                getString(R.string.action_stop_timer),
                createStopTimerPendingIntent(this)
            )
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val runningChannel = NotificationChannel(
            CHANNEL_RUNNING_ID,
            getString(R.string.timer_channel_running_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(R.string.timer_channel_running_description)
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        val finishedSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val finishedAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val finishedChannel = NotificationChannel(
            CHANNEL_FINISHED_ID,
            getString(R.string.timer_channel_finished_name),
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = getString(R.string.timer_channel_finished_description)
            setSound(finishedSound, finishedAttributes)
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        notificationManager.createNotificationChannel(runningChannel)
        notificationManager.createNotificationChannel(finishedChannel)
    }

    private fun notifySafely(id: Int, notification: Notification) {
        notifySafely(this, id, notification)
    }

    private fun cancelNotification(id: Int) {
        NotificationManagerCompat.from(this).cancel(id)
    }

    private fun formatSeconds(totalSeconds: Int): String {
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format(Locale.getDefault(), "%02d:%02d", minutes, seconds)
    }

    companion object {
        private const val ACTION_START = "com.setforge.gymapp.action.REST_TIMER_START"
        private const val ACTION_STOP = "com.setforge.gymapp.action.REST_TIMER_STOP"
        private const val ACTION_DISMISS_ALERT = "com.setforge.gymapp.action.REST_TIMER_DISMISS_ALERT"
        private const val EXTRA_DURATION_SECONDS = "extra_duration_seconds"

        private const val CHANNEL_RUNNING_ID = "rest_timer_running"
        private const val CHANNEL_FINISHED_ID = "rest_timer_finished"
        private const val NOTIFICATION_RUNNING_ID = 4001
        private const val NOTIFICATION_FINISHED_ID = 4002

        private const val REQUEST_OPEN_APP = 4010
        private const val REQUEST_STOP_TIMER = 4011
        private const val REQUEST_DISMISS_ALERT = 4012
        private const val REQUEST_FINISHED_ALARM = 4013

        fun start(context: Context, seconds: Int) {
            if (seconds <= 0) return
            val appContext = context.applicationContext
            val intent = Intent(appContext, RestTimerService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_DURATION_SECONDS, seconds)
            }
            ContextCompat.startForegroundService(appContext, intent)
        }

        fun stop(context: Context) {
            val appContext = context.applicationContext
            // After a timeout hand-off no service is running: clear its countdown and alarm here.
            cancelFinishedAlarm(appContext)
            NotificationManagerCompat.from(appContext).cancel(NOTIFICATION_RUNNING_ID)
            NotificationManagerCompat.from(appContext).cancel(NOTIFICATION_FINISHED_ID)
            val intent = Intent(appContext, RestTimerService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                appContext.startService(intent)
            } catch (_: IllegalStateException) {
                // The app is in the background and the service is not running: nothing to stop.
            }
        }

        internal fun postFinished(context: Context) {
            RestTimerState.update(0)
            val notifications = NotificationManagerCompat.from(context)
            notifications.cancel(NOTIFICATION_RUNNING_ID)
            notifySafely(context, NOTIFICATION_FINISHED_ID, buildFinishedNotification(context))
        }

        private fun buildFinishedNotification(context: Context): Notification {
            return NotificationCompat.Builder(context, CHANNEL_FINISHED_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(context.getString(R.string.timer_notification_finished_title))
                .setContentText(context.getString(R.string.timer_notification_finished_text))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(createOpenAppPendingIntent(context))
                .addAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    context.getString(R.string.action_stop_timer),
                    createDismissAlertPendingIntent(context)
                )
                .build()
        }

        private fun createOpenAppPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                REQUEST_OPEN_APP,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun createStopTimerPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, RestTimerService::class.java).apply {
                action = ACTION_STOP
            }
            return PendingIntent.getService(
                context,
                REQUEST_STOP_TIMER,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun createDismissAlertPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, RestTimerService::class.java).apply {
                action = ACTION_DISMISS_ALERT
            }
            return PendingIntent.getService(
                context,
                REQUEST_DISMISS_ALERT,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun finishedAlarmIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_FINISHED_ALARM,
            Intent(context, RestTimerAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        private fun scheduleFinishedAlarm(context: Context, endsAt: Long) {
            val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
            val pendingIntent = finishedAlarmIntent(context)
            // Exact alarms need a permission the app does not request, so fall back to the
            // closest allowed time when it is missing.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAt, pendingIntent)
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endsAt, pendingIntent)
            }
        }

        private fun cancelFinishedAlarm(context: Context) {
            context.getSystemService(AlarmManager::class.java)?.cancel(finishedAlarmIntent(context))
        }

        private fun notifySafely(context: Context, id: Int, notification: Notification) {
            if (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
            ) {
                return
            }

            try {
                NotificationManagerCompat.from(context).notify(id, notification)
            } catch (_: SecurityException) {
                // Notifications were turned off between the check and the post.
            }
        }
    }
}

/** Posts the "rest finished" alert for a rest that outlived the short foreground service. */
class RestTimerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RestTimerService.postFinished(context.applicationContext)
    }
}
