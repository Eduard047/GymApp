package com.example.gymapp.wear.sync

import android.content.Context

data class DeletedOwnerMarker(val ownerId: String, val deletedAtMs: Long)

/**
 * The last owner the phone reported as deleted (an unlink with reason account_deleted). The
 * listener drops that owner's stored work itself; this marker tells an open app that still holds
 * the live workout in memory to drop it too instead of saving it again.
 */
object WatchDeletedOwnerMarker {
    private const val PREFS_NAME = "watch_deleted_owner"
    private const val KEY_OWNER_ID = "owner_id"
    private const val KEY_DELETED_AT = "deleted_at_ms"
    private const val MAX_OWNER_ID_LENGTH = 256

    fun record(context: Context, ownerId: String, deletedAtMs: Long = System.currentTimeMillis()): Boolean {
        if (ownerId.isBlank() || ownerId.length > MAX_OWNER_ID_LENGTH) return false
        return context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_OWNER_ID, ownerId)
            .putLong(KEY_DELETED_AT, deletedAtMs)
            .commit()
    }

    /** A new binding for this owner id was established after the deletion: the owner exists again. */
    fun clearIfSuperseded(context: Context, newBindingOwnerId: String?) {
        val marker = load(context) ?: return
        if (!WatchBindingRules.deletedOwnerMarkerSuperseded(marker.ownerId, newBindingOwnerId)) return
        context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    fun load(context: Context): DeletedOwnerMarker? {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val ownerId = prefs.getString(KEY_OWNER_ID, null)
            ?.takeIf { it.isNotBlank() && it.length <= MAX_OWNER_ID_LENGTH }
            ?: return null
        val deletedAtMs = prefs.getLong(KEY_DELETED_AT, 0L).takeIf { it > 0L } ?: return null
        return DeletedOwnerMarker(ownerId, deletedAtMs)
    }
}
