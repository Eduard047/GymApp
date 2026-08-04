package com.example.gymapp.sync

import android.content.Context
import java.security.MessageDigest

internal enum class CloudSnapshotApplyDecision {
    AlreadyCurrent,
    ReplaceAuthoritatively,
    UploadLocal,
    Conflict
}

internal data class CloudSyncConflictSnapshot(
    val userId: String,
    val sessionGeneration: String,
    val localDigest: String,
    val remoteDigest: String?,
    val remoteExists: Boolean
)

internal fun isCurrentCloudSyncConflict(
    conflict: CloudSyncConflictSnapshot,
    userId: String,
    sessionGeneration: String,
    localDigest: String,
    remoteDigest: String?,
    remoteExists: Boolean
): Boolean = conflict.userId == userId &&
    conflict.sessionGeneration == sessionGeneration &&
    conflict.localDigest == localDigest &&
    conflict.remoteDigest == remoteDigest &&
    conflict.remoteExists == remoteExists

/** Runs a destructive choice only for the exact account and local/remote pair the user reviewed. */
internal suspend fun <T> runCurrentCloudSyncConflictAction(
    conflict: CloudSyncConflictSnapshot,
    userId: String,
    sessionGeneration: String,
    localDigest: String,
    remoteDigest: String?,
    remoteExists: Boolean,
    action: suspend () -> T
): T {
    check(isCurrentCloudSyncConflict(
        conflict = conflict,
        userId = userId,
        sessionGeneration = sessionGeneration,
        localDigest = localDigest,
        remoteDigest = remoteDigest,
        remoteExists = remoteExists
    )) { "Cloud data changed on another device. Reload it before syncing again." }
    return action()
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
    if (lastSyncedDigest != null && remoteDigest == lastSyncedDigest) {
        return CloudSnapshotApplyDecision.UploadLocal
    }
    return CloudSnapshotApplyDecision.Conflict
}

internal fun encodeCloudSyncBaseline(digest: String): String {
    require(digest.matches(SHA256_PATTERN))
    return "$CLOUD_SYNC_BASELINE_PREFIX$digest"
}

internal fun decodeCloudSyncBaseline(value: String?): String? {
    if (value == null || !value.startsWith(CLOUD_SYNC_BASELINE_PREFIX)) return null
    return value.removePrefix(CLOUD_SYNC_BASELINE_PREFIX).takeIf { it.matches(SHA256_PATTERN) }
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

    fun read(userId: String): String? = decodeCloudSyncBaseline(
        preferences.getString(key(userId), null)
    )

    fun write(userId: String, digest: String): Boolean {
        return preferences.edit().putString(key(userId), encodeCloudSyncBaseline(digest)).commit()
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
        const val PREFS_NAME = "gym_cloud_sync_baselines"
    }
}

private const val CLOUD_SYNC_BASELINE_PREFIX = "v3:"
private val SHA256_PATTERN = Regex("^[0-9a-f]{64}$")
