package com.example.gymapp.wear.sync

import android.content.Context
import org.json.JSONObject

data class WatchSyncStage(
    val ownerId: String,
    val accountGeneration: Long,
    val revision: Long,
    val messageId: String
)

/** Durable pre-write replay fence used to prevent a delayed lower revision after a crash. */
object WatchSyncStageStorage {
    private const val PREFS_NAME = "watch_sync_stages"
    private const val KEY_FULL_SYNC = "full_sync_stage"
    private const val KEY_PLAN = "plan_stage"
    private const val MAX_IDENTIFIER_LENGTH = 128

    fun loadFullSync(context: Context): WatchSyncStage? = load(context, KEY_FULL_SYNC)

    fun loadPlan(context: Context): WatchSyncStage? = load(context, KEY_PLAN)

    fun stageFullSync(context: Context, envelope: WatchSyncEnvelope) {
        stage(context, KEY_FULL_SYNC, envelope)
    }

    fun stagePlan(context: Context, envelope: WatchSyncEnvelope) {
        stage(context, KEY_PLAN, envelope)
    }

    fun clearFullSyncIfMatches(context: Context, envelope: WatchSyncEnvelope) {
        clearIfMatches(context, KEY_FULL_SYNC, envelope)
    }

    fun clearPlanIfMatches(context: Context, envelope: WatchSyncEnvelope) {
        clearIfMatches(context, KEY_PLAN, envelope)
    }

    fun clearPlan(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.contains(KEY_PLAN)) {
            check(prefs.edit().remove(KEY_PLAN).commit()) { "Could not clear plan sync stage" }
        }
    }

    private fun load(context: Context, key: String): WatchSyncStage? {
        val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(key, null)
            ?.takeIf { it.toByteArray(Charsets.UTF_8).size <= 1_024 }
            ?: return null
        return runCatching {
            val root = JSONObject(raw)
            require(root.keys().asSequence().toSet() == setOf(
                "ownerId", "accountGeneration", "revision", "messageId"
            ))
            WatchSyncStage(
                ownerId = root.getString("ownerId"),
                accountGeneration = root.getLong("accountGeneration"),
                revision = root.getLong("revision"),
                messageId = root.getString("messageId")
            ).also(::requireValid)
        }.getOrNull()
    }

    private fun stage(context: Context, key: String, envelope: WatchSyncEnvelope) {
        val stage = WatchSyncStage(
            ownerId = envelope.ownerId,
            accountGeneration = envelope.accountGeneration,
            revision = envelope.revision,
            messageId = envelope.messageId
        ).also(::requireValid)
        val raw = JSONObject()
            .put("ownerId", stage.ownerId)
            .put("accountGeneration", stage.accountGeneration)
            .put("revision", stage.revision)
            .put("messageId", stage.messageId)
            .toString()
        check(
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(key, raw)
                .commit()
        ) { "Could not persist sync stage" }
    }

    private fun clearIfMatches(context: Context, key: String, envelope: WatchSyncEnvelope) {
        val existing = load(context, key) ?: return
        if (
            existing.ownerId == envelope.ownerId &&
            existing.accountGeneration == envelope.accountGeneration &&
            existing.revision == envelope.revision &&
            existing.messageId == envelope.messageId
        ) {
            check(
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .remove(key)
                    .commit()
            ) { "Could not clear sync stage" }
        }
    }

    private fun requireValid(stage: WatchSyncStage) {
        require(stage.ownerId.isNotBlank() && stage.ownerId.length <= MAX_IDENTIFIER_LENGTH)
        require(stage.messageId.isNotBlank() && stage.messageId.length <= MAX_IDENTIFIER_LENGTH)
        require(stage.accountGeneration in 1L..SyncPaths.MAX_PROTOCOL_COUNTER)
        require(stage.revision in 1L..SyncPaths.MAX_PROTOCOL_COUNTER)
    }
}
