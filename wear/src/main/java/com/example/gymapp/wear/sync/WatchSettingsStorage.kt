package com.example.gymapp.wear.sync

import android.content.Context
import com.example.gymapp.wear.health.RestTimerLogic

/**
 * Small on-watch preferences, never account-scoped. Only [restEndAlert] comes from the phone (its
 * device-local "Rest end alert" switch, carried in the plan and full-sync messages); the rest stays here.
 */
object WatchSettingsStorage {
    private const val PREFS_NAME = "watch_settings"
    private const val KEY_REST_SECONDS = "rest_seconds"
    private const val KEY_REST_END_ALERT = "rest_end_alert"
    const val DEFAULT_REST_END_ALERT = true

    /** Whether the end of a rest vibrates. Default on (a phone that never sent it keeps the vibration). */
    fun restEndAlert(context: Context): Boolean =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_REST_END_ALERT, DEFAULT_REST_END_ALERT)

    fun setRestEndAlert(context: Context, enabled: Boolean) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.contains(KEY_REST_END_ALERT) && prefs.getBoolean(KEY_REST_END_ALERT, DEFAULT_REST_END_ALERT) == enabled) return
        prefs.edit().putBoolean(KEY_REST_END_ALERT, enabled).apply()
    }

    fun restSeconds(context: Context): Int =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_REST_SECONDS, RestTimerLogic.DEFAULT_REST_SECONDS)
            .coerceIn(RestTimerLogic.MIN_REST_SECONDS, RestTimerLogic.MAX_REST_SECONDS)

    fun setRestSeconds(context: Context, seconds: Int) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(
                KEY_REST_SECONDS,
                seconds.coerceIn(RestTimerLogic.MIN_REST_SECONDS, RestTimerLogic.MAX_REST_SECONDS)
            )
            .apply()
    }
}
