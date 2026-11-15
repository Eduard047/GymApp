package com.example.gymapp.util

import android.content.Context

/** Where [RestAlertsHintFlag] persists its single "already shown" bit. */
interface RestAlertsHintStorage {
    fun isSeen(): Boolean
    fun markSeen()
}

/**
 * The "notifications are off" note under the rest timer is shown at most once per install: the first
 * time it appears it is burned. Dismissing it, opening the settings from it, or finding the
 * notifications enabled all keep it from ever coming back.
 */
class RestAlertsHintFlag(private val storage: RestAlertsHintStorage) {
    /** True when the note may be shown now (alerts muted and never burned before). */
    fun mayShow(alertsMuted: Boolean): Boolean {
        if (!alertsMuted) {
            // Notifications are on: the note has no purpose any more, so it never returns.
            storage.markSeen()
            return false
        }
        return !storage.isSeen()
    }

    /** Burns the note; call when it first appears and when it is dismissed or its action used. */
    fun burn() = storage.markSeen()

    companion object {
        private const val PREFS = "gym_rest_alerts_hint"
        private const val KEY_SEEN = "seen"

        fun forContext(context: Context): RestAlertsHintFlag {
            val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return RestAlertsHintFlag(object : RestAlertsHintStorage {
                override fun isSeen(): Boolean = runCatching { prefs.getBoolean(KEY_SEEN, false) }.getOrDefault(false)
                override fun markSeen() {
                    runCatching { prefs.edit().putBoolean(KEY_SEEN, true).apply() }
                }
            })
        }
    }
}
