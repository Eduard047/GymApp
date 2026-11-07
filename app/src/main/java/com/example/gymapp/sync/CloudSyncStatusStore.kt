package com.example.gymapp.sync

import android.content.Context
import com.example.gymapp.R
import com.example.gymapp.util.LocalizedText
import java.security.MessageDigest

enum class CloudSyncPhase {
    Checking,
    Pending,
    Synced,
    Conflict,
    Error
}

/**
 * In-memory sync state for the UI. [message] is the localized reason shown while [phase] is
 * [CloudSyncPhase.Error]; it is never persisted and never carries free-form server text.
 */
data class CloudSyncUiStatus(
    val phase: CloudSyncPhase,
    val lastSuccessAt: Long? = null,
    val message: LocalizedText? = null
)

/** Localized failure reasons that may be kept on the persistent sync card. */
private val CLOUD_SYNC_ERROR_REASONS = setOf(
    R.string.auth_error_connection,
    R.string.auth_error_cloud_unavailable,
    R.string.cloud_sync_load_failed,
    R.string.cloud_sync_conflict,
    R.string.cloud_sync_save_failed,
    R.string.cloud_sync_account_changed,
    R.string.cloud_sync_baseline_failed,
    R.string.cloud_sync_round_trip_failed,
    R.string.cloud_sync_resolution_failed
)

/**
 * Builds the status for [phase]. The reason is kept only for [CloudSyncPhase.Error] and only
 * when it is one of the known argument-free localized sync reasons, so entering any other phase
 * (a new attempt, success, conflict) clears it.
 */
fun cloudSyncUiStatus(
    phase: CloudSyncPhase,
    lastSuccessAt: Long?,
    errorReason: LocalizedText? = null
): CloudSyncUiStatus = CloudSyncUiStatus(
    phase = phase,
    lastSuccessAt = lastSuccessAt,
    message = errorReason?.takeIf {
        phase == CloudSyncPhase.Error &&
            it.formatArguments.isEmpty() &&
            it.resourceId in CLOUD_SYNC_ERROR_REASONS
    }
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
