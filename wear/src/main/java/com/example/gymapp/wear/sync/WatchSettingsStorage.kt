package com.example.gymapp.wear.sync

import android.content.Context
import com.example.gymapp.wear.health.RestTimerLogic

/** Small on-watch preferences. Nothing here is synced or account-scoped. */
object WatchSettingsStorage {
    private const val PREFS_NAME = "watch_settings"
    private const val KEY_REST_SECONDS = "rest_seconds"

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
