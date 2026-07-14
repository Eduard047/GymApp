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
    val planRevision: Long
)

object WatchSyncBindingStorage {
    private const val PREFS_NAME = "watch_sync_binding"
    private const val KEY_SOURCE_NODE_ID = "source_node_id"
    private const val KEY_OWNER_ID = "owner_id"
    private const val KEY_ACCOUNT_GENERATION = "account_generation"
    private const val KEY_FULL_SYNC_REVISION = "full_sync_revision"
    private const val KEY_PLAN_REVISION = "plan_revision"
    private const val MAX_OWNER_ID_LENGTH = 128
    private const val MAX_NODE_ID_LENGTH = 256

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
            planRevision = planRevision
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

    fun acceptFullSync(
        context: Context,
        sourceNodeId: String,
        ownerId: String,
        accountGeneration: Long,
        revision: Long
    ) {
        require(sourceNodeId.isNotBlank() && sourceNodeId.length <= MAX_NODE_ID_LENGTH)
        require(ownerId.isNotBlank() && ownerId.length <= MAX_OWNER_ID_LENGTH)
        require(accountGeneration in 1L..SyncPaths.MAX_PROTOCOL_COUNTER)
        require(revision in 0L..SyncPaths.MAX_PROTOCOL_COUNTER)
        val binding = load(context)
        require(binding == null || binding.sourceNodeId == sourceNodeId)
        val ownerChanged = binding?.ownerId != ownerId ||
            binding?.accountGeneration != accountGeneration
        if (ownerChanged) {
            WatchPendingWorkoutStorage.clear(context)
        }
        val committed = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SOURCE_NODE_ID, sourceNodeId)
            .putString(KEY_OWNER_ID, ownerId)
            .putLong(KEY_ACCOUNT_GENERATION, accountGeneration)
            .putLong(KEY_FULL_SYNC_REVISION, revision)
            .putLong(
                KEY_PLAN_REVISION,
                if (
                    binding?.ownerId == ownerId &&
                    binding.accountGeneration == accountGeneration
                ) {
                    binding.planRevision
                } else {
                    0L
                }
            )
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
}
