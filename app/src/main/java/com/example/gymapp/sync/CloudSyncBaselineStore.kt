package com.example.gymapp.sync

import android.content.Context
import java.security.MessageDigest

internal enum class CloudSnapshotApplyDecision {
    AlreadyCurrent,
    ReplaceAuthoritatively,
    Conflict
}

internal fun cloudSnapshotApplyDecision(
    localDigest: String?,
    remoteDigest: String?,
    lastSyncedDigest: String?,
    localProjectionEmpty: Boolean
): CloudSnapshotApplyDecision {
    if (localDigest == null || remoteDigest == null) return CloudSnapshotApplyDecision.Conflict
    if (localDigest == remoteDigest) return CloudSnapshotApplyDecision.AlreadyCurrent
    if (localProjectionEmpty || (lastSyncedDigest != null && localDigest == lastSyncedDigest)) {
        return CloudSnapshotApplyDecision.ReplaceAuthoritatively
    }
    return CloudSnapshotApplyDecision.Conflict
}

/**
 * Stores only opaque hashes of the last server-confirmed workout projection.
 *
 * The baseline survives logout so the next login can distinguish unsynced local work from a
 * clean projection. It is excluded from cloud backup/device transfer because it describes this
 * installation's synchronization history.
 */
internal class CloudSyncBaselineStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE
    )

    fun read(userId: String): String? = preferences.getString(key(userId), null)
        ?.takeIf { it.matches(SHA256_PATTERN) }

    fun write(userId: String, digest: String): Boolean {
        require(digest.matches(SHA256_PATTERN))
        return preferences.edit().putString(key(userId), digest).commit()
    }

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
        const val PREFS_NAME = "gym_cloud_sync_baselines"
        val SHA256_PATTERN = Regex("^[0-9a-f]{64}$")
    }
}
