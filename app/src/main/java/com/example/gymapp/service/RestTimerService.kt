package com.example.gymapp.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.IBinder
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
        notifySafely(NOTIFICATION_FINISHED_ID, buildFinishedNotification())
        stopSelf()
    }

    private fun stopTimer() {
        countdownJob?.cancel()
        countdownJob = null
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
            .setContentIntent(createOpenAppPendingIntent())
            .addAction(
                android.R.drawable.ic_media_pause,
                getString(R.string.action_stop_timer),
                createStopTimerPendingIntent()
            )
            .build()
    }

    private fun buildFinishedNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_FINISHED_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(getString(R.string.timer_notification_finished_title))
            .setContentText(getString(R.string.timer_notification_finished_text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(createOpenAppPendingIntent())
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.action_stop_timer),
                createDismissAlertPendingIntent()
            )
            .build()
    }

    private fun createOpenAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            REQUEST_OPEN_APP,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createStopTimerPendingIntent(): PendingIntent {
        val intent = Intent(this, RestTimerService::class.java).apply {
            action = ACTION_STOP
        }
        return PendingIntent.getService(
            this,
            REQUEST_STOP_TIMER,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createDismissAlertPendingIntent(): PendingIntent {
        val intent = Intent(this, RestTimerService::class.java).apply {
            action = ACTION_DISMISS_ALERT
        }
        return PendingIntent.getService(
            this,
            REQUEST_DISMISS_ALERT,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createNotificationChannels() {
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
        runCatching {
            NotificationManagerCompat.from(this).notify(id, notification)
        }
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
        private const val ACTION_START = "com.example.gymapp.action.REST_TIMER_START"
        private const val ACTION_STOP = "com.example.gymapp.action.REST_TIMER_STOP"
        private const val ACTION_DISMISS_ALERT = "com.example.gymapp.action.REST_TIMER_DISMISS_ALERT"
        private const val EXTRA_DURATION_SECONDS = "extra_duration_seconds"

        private const val CHANNEL_RUNNING_ID = "rest_timer_running"
        private const val CHANNEL_FINISHED_ID = "rest_timer_finished"
        private const val NOTIFICATION_RUNNING_ID = 4001
        private const val NOTIFICATION_FINISHED_ID = 4002

        private const val REQUEST_OPEN_APP = 4010
        private const val REQUEST_STOP_TIMER = 4011
        private const val REQUEST_DISMISS_ALERT = 4012

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
            val intent = Intent(appContext, RestTimerService::class.java).apply {
                action = ACTION_STOP
            }
            appContext.startService(intent)
        }
    }
}
