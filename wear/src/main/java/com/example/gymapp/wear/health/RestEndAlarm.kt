package com.example.gymapp.wear.health

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock

/**
 * The "rest finished" vibration outside the ViewModel: an alarm wakes [RestEndReceiver] at the
 * end of the rest even when the screen is off, the process was frozen or killed, or the
 * Activity is gone. The ViewModel ticker may notice the end first while it is alive; both go
 * through [deliver], which vibrates once per rest (the scheduled token is claimed atomically).
 *
 * The token is the rest's wall-clock end (epoch ms), the same value stored in the draft.
 */
object RestEndAlarm {
    private const val PREFS_NAME = "watch_rest_alarm"
    private const val KEY_SCHEDULED_TOKEN = "scheduled_token"
    private const val REQUEST_CODE = 4101
    internal const val ACTION_REST_END = "com.example.gymapp.wear.action.REST_END"
    internal const val EXTRA_TOKEN = "token"

    private val lock = Any()

    /** True when a vibration for [token] is still owed: it is the scheduled one, not yet claimed. */
    internal fun shouldDeliver(scheduledToken: Long?, token: Long): Boolean =
        token > 0L && scheduledToken == token

    /**
     * (Re)arms the alarm for the rest ending at [token] (wall clock), [remainingMs] from now.
     * Exact when the app may schedule exact alarms, otherwise allowed-while-idle (may be late).
     * The token is written first and durably, so a receiver in a new process still finds it.
     */
    fun schedule(context: Context, token: Long, remainingMs: Long) {
        val app = context.applicationContext
        synchronized(lock) {
            prefs(app).edit().putLong(KEY_SCHEDULED_TOKEN, token).commit()
        }
        runCatching {
            val alarmManager = app.getSystemService(AlarmManager::class.java) ?: return
            val triggerAt = SystemClock.elapsedRealtime() + remainingMs.coerceAtLeast(0L)
            val operation = pendingIntent(app, token, PendingIntent.FLAG_UPDATE_CURRENT) ?: return
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()) {
                try {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.ELAPSED_REALTIME_WAKEUP,
                        triggerAt,
                        operation
                    )
                    return
                } catch (_: SecurityException) {
                    // The permission was revoked in between: fall back to the inexact alarm.
                }
            }
            alarmManager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, operation)
        }
    }

    /** No rest is running any more (skip, undo, pause, finish, discard): nothing is owed. */
    fun cancel(context: Context) {
        val app = context.applicationContext
        synchronized(lock) {
            val prefs = prefs(app)
            // The alarm itself is cancelled below, so a token that misses the disk is harmless.
            if (prefs.contains(KEY_SCHEDULED_TOKEN)) {
                prefs.edit().remove(KEY_SCHEDULED_TOKEN).apply()
            }
        }
        cancelAlarm(app)
    }

    /**
     * The rest ending at [token] is over: vibrates when this rest's vibration has not been
     * given yet. Returns true when it vibrated. Called by the receiver and by the ticker.
     */
    fun deliver(context: Context, token: Long): Boolean {
        val app = context.applicationContext
        val claimed = synchronized(lock) {
            val prefs = prefs(app)
            val scheduled = if (prefs.contains(KEY_SCHEDULED_TOKEN)) {
                prefs.getLong(KEY_SCHEDULED_TOKEN, 0L)
            } else {
                null
            }
            // The in-memory map changes at once, so a second caller in this process sees the
            // claim; another process can only start after this one died (the ticker is gone then).
            shouldDeliver(scheduled, token).also { owed ->
                if (owed) prefs.edit().remove(KEY_SCHEDULED_TOKEN).apply()
            }
        }
        if (!claimed) return false
        // The ticker got there first: the alarm has nothing left to do.
        cancelAlarm(app)
        WearHaptics.restFinished(app)
        return true
    }

    private fun cancelAlarm(app: Context) {
        runCatching {
            val operation = pendingIntent(app, 0L, PendingIntent.FLAG_NO_CREATE) ?: return
            app.getSystemService(AlarmManager::class.java)?.cancel(operation)
            operation.cancel()
        }
    }

    private fun pendingIntent(app: Context, token: Long, flags: Int): PendingIntent? {
        val intent = Intent(app, RestEndReceiver::class.java)
            .setAction(ACTION_REST_END)
            .putExtra(EXTRA_TOKEN, token)
        return PendingIntent.getBroadcast(app, REQUEST_CODE, intent, flags or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun prefs(app: Context) = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}

/** Not exported: only this app's own alarm reaches it. Vibrates at the end of a rest. */
class RestEndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != RestEndAlarm.ACTION_REST_END) return
        val token = intent.getLongExtra(RestEndAlarm.EXTRA_TOKEN, 0L)
        RestEndAlarm.deliver(context, token)
    }
}
