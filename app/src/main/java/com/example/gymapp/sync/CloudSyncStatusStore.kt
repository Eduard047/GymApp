package com.example.gymapp.sync

import android.content.Context
import java.security.MessageDigest

enum class CloudSyncPhase {
    Checking,
    Pending,
    Synced,
    Conflict,
    Error
}

data class CloudSyncUiStatus(
    val phase: CloudSyncPhase,
    val lastSuccessAt: Long? = null
)

/** Persists only a bounded timestamp under a one-way account key; no account identifier is stored. */
internal class CloudSyncStatusStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE
    )

    fun readLastSuccess(userId: String, nowMillis: Long = System.currentTimeMillis()): Long? {
        val timestamp = preferences.getLong(key(userId), 0L)
        return timestamp.takeIf { it in 1L..(nowMillis + MAX_FUTURE_SKEW_MILLIS) }
    }

    fun writeLastSuccess(userId: String, timestamp: Long = System.currentTimeMillis()): Boolean {
        require(timestamp > 0L)
        return preferences.edit().putLong(key(userId), timestamp).commit()
    }

    fun clear(userId: String): Boolean = preferences.edit().remove(key(userId)).commit()

    private fun key(userId: String): String {
        require(userId.isNotBlank() && userId.length <= 256)
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(userId.toByteArray(Charsets.UTF_8))
            .joinToString(separator = "") { byte ->
                (byte.toInt() and 0xff).toString(16).padStart(2, '0')
            }
        return "user_$digest"
    }

    private companion object {
        const val PREFS_NAME = "gym_cloud_sync_status"
        const val MAX_FUTURE_SKEW_MILLIS = 24L * 60L * 60L * 1_000L
    }
}
