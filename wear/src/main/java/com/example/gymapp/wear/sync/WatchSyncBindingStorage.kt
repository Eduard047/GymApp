package com.example.gymapp.wear.sync

import android.content.Context
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged

data class WatchSyncBinding(
    val sourceNodeId: String,
    val ownerId: String?,
    val accountGeneration: Long,
    val fullSyncRevision: Long,
    val planRevision: Long,
    /** Install id of the phone authority; null until its first message was accepted. */
    val authorityEpoch: String? = null,
    /** Phone clock of the last accepted authority message; fences a dead install's late messages. */
    val lastAcceptedSentAt: Long = 0L
)

object WatchSyncBindingStorage {
    private const val PREFS_NAME = "watch_sync_binding"
    private const val KEY_SOURCE_NODE_ID = "source_node_id"
    private const val KEY_OWNER_ID = "owner_id"
    private const val KEY_ACCOUNT_GENERATION = "account_generation"
    private const val KEY_FULL_SYNC_REVISION = "full_sync_revision"
    private const val KEY_PLAN_REVISION = "plan_revision"
    private const val KEY_AUTHORITY_EPOCH = "authority_epoch"
    private const val KEY_LAST_ACCEPTED_SENT_AT = "last_accepted_sent_at"
    private const val KEY_UNLINKED = "unlinked"
    private const val MAX_OWNER_ID_LENGTH = 128
    private const val MAX_NODE_ID_LENGTH = 256
    private const val MAX_EPOCH_LENGTH = 64

    fun load(context: Context): WatchSyncBinding? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val sourceNodeId = prefs.getString(KEY_SOURCE_NODE_ID, null)
            ?.takeIf { it.isNotBlank() && it.length <= MAX_NODE_ID_LENGTH }
            ?: return null
        val ownerId = prefs.getString(KEY_OWNER_ID, null)
            ?.takeIf { it.isNotBlank() && it.length <= MAX_OWNER_ID_LENGTH }
        val accountGeneration = prefs.getLong(KEY_ACCOUNT_GENERATION, 0L)
        val fullSyncRevision = prefs.getLong(KEY_FULL_SYNC_REVISION, 0L)
        val planRevision = prefs.getLong(KEY_PLAN_REVISION, 0L)
        if (
            accountGeneration !in 0L..SyncPaths.MAX_PROTOCOL_COUNTER ||
            fullSyncRevision !in 0L..SyncPaths.MAX_PROTOCOL_COUNTER ||
            planRevision !in 0L..SyncPaths.MAX_PROTOCOL_COUNTER ||
            (ownerId != null && accountGeneration == 0L)
        ) {
            return null
        }
        return WatchSyncBinding(
            sourceNodeId = sourceNodeId,
            ownerId = ownerId,
            accountGeneration = accountGeneration,
            fullSyncRevision = fullSyncRevision,
            planRevision = planRevision,
            authorityEpoch = prefs.getString(KEY_AUTHORITY_EPOCH, null)
                ?.takeIf { it.isNotBlank() && it.length <= MAX_EPOCH_LENGTH },
            lastAcceptedSentAt = prefs.getLong(KEY_LAST_ACCEPTED_SENT_AT, 0L).coerceAtLeast(0L)
        )
    }

    fun observe(context: Context): Flow<WatchSyncBinding?> = callbackFlow {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
            trySend(load(appContext))
        }
        // Register before the initial read so an account transition cannot be missed
        // between snapshotting the binding and subscribing for changes.
        prefs.registerOnSharedPreferenceChangeListener(listener)
        trySend(load(appContext))
        awaitClose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }.distinctUntilChanged()

    /** True after an explicit unlink (phone or watch): the watch must not ask to link by itself. */
    fun isUnlinked(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_UNLINKED, false)
    }

    fun observeUnlinked(context: Context): Flow<Boolean> = callbackFlow {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
            trySend(isUnlinked(appContext))
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)
        trySend(isUnlinked(appContext))
        awaitClose { prefs.unregisterOnSharedPreferenceChangeListener(listener) }
    }.distinctUntilChanged()

    /** The user's "Link to phone": the next sync request may link again. */
    fun markLinkRequested(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.contains(KEY_UNLINKED)) {
            check(prefs.edit().remove(KEY_UNLINKED).commit()) { "Could not persist link request" }
        }
    }

    fun pinSourceNode(context: Context, sourceNodeId: String): WatchSyncBinding {
        require(sourceNodeId.isNotBlank() && sourceNodeId.length <= MAX_NODE_ID_LENGTH)
        val existing = load(context)
        require(existing == null || existing.sourceNodeId == sourceNodeId) {
            "Unexpected sync source"
        }
        if (existing != null) return existing

        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SOURCE_NODE_ID, sourceNodeId)
            .commit()
        check(committed) { "Could not persist sync source" }
        return requireNotNull(load(context))
    }

    /**
     * Stores an accepted full sync. The caller has already decided (WatchBindingRules) that this
     * node, owner, generation and epoch are acceptable. Work kept on the watch is never touched
     * here: it stays stamped with its own owner and is sent only when that owner is bound again.
     */
    fun acceptFullSync(
        context: Context,
        sourceNodeId: String,
        ownerId: String,
        accountGeneration: Long,
        revision: Long,
        authorityEpoch: String,
        sentAt: Long
    ) {
        require(sourceNodeId.isNotBlank() && sourceNodeId.length <= MAX_NODE_ID_LENGTH)
        require(ownerId.isNotBlank() && ownerId.length <= MAX_OWNER_ID_LENGTH)
        require(accountGeneration in 1L..SyncPaths.MAX_PROTOCOL_COUNTER)
        require(revision in 0L..SyncPaths.MAX_PROTOCOL_COUNTER)
        require(authorityEpoch.isNotBlank() && authorityEpoch.length <= MAX_EPOCH_LENGTH)
        require(sentAt >= 0L)
        val binding = load(context)
        val sameAuthority = binding != null &&
            binding.sourceNodeId == sourceNodeId &&
            binding.authorityEpoch == authorityEpoch
        val sameAccount = sameAuthority &&
            binding?.ownerId == ownerId &&
            binding.accountGeneration == accountGeneration
        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SOURCE_NODE_ID, sourceNodeId)
            .putString(KEY_OWNER_ID, ownerId)
            .putLong(KEY_ACCOUNT_GENERATION, accountGeneration)
            .putLong(KEY_FULL_SYNC_REVISION, revision)
            .putLong(KEY_PLAN_REVISION, if (sameAccount) binding?.planRevision ?: 0L else 0L)
            .putString(KEY_AUTHORITY_EPOCH, authorityEpoch)
            .putLong(
                KEY_LAST_ACCEPTED_SENT_AT,
                if (sameAuthority) maxOf(sentAt, binding?.lastAcceptedSentAt ?: 0L) else sentAt
            )
            .remove(KEY_UNLINKED)
            .commit()
        check(committed) { "Could not persist account binding" }
    }

    fun acceptPlan(context: Context, revision: Long) {
        require(revision in 1L..SyncPaths.MAX_PROTOCOL_COUNTER)
        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_PLAN_REVISION, revision)
            .commit()
        check(committed) { "Could not persist plan revision" }
    }

    /** The phone signed out: keep the pinned phone, forget the owner, remember the generation. */
    fun unbind(context: Context, accountGeneration: Long, authorityEpoch: String, sentAt: Long) {
        require(accountGeneration in 1L..SyncPaths.MAX_PROTOCOL_COUNTER)
        require(authorityEpoch.isNotBlank() && authorityEpoch.length <= MAX_EPOCH_LENGTH)
        val binding = requireNotNull(load(context)) { "No sync source" }
        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_OWNER_ID)
            .putLong(KEY_ACCOUNT_GENERATION, accountGeneration)
            .putLong(KEY_FULL_SYNC_REVISION, 0L)
            .putLong(KEY_PLAN_REVISION, 0L)
            .putString(KEY_AUTHORITY_EPOCH, authorityEpoch)
            .putLong(KEY_LAST_ACCEPTED_SENT_AT, maxOf(sentAt, 0L).let { value ->
                if (binding.authorityEpoch == authorityEpoch) maxOf(value, binding.lastAcceptedSentAt) else value
            })
            .commit()
        check(committed) { "Could not persist unbound state" }
    }

    /** Explicit unlink (phone message or the watch's own action): forget the phone entirely. */
    fun clearForUnlink(context: Context) {
        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .putBoolean(KEY_UNLINKED, true)
            .commit()
        check(committed) { "Could not clear sync binding" }
    }
}
