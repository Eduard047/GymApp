package com.example.gymapp.wear.sync

import android.content.Context
import com.example.gymapp.wear.data.WearWorkoutSetDraft
import java.security.MessageDigest
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

data class PendingWorkoutMutation(
    val operationId: String,
    val draftId: String,
    val fingerprint: String,
    val startedAt: Long,
    val note: String?,
    val sets: List<WearWorkoutSetDraft>,
    val sourcePlanRaw: String?
)

/**
 * Persists the exact logical draft being submitted. Lost-ACK retries reuse its operation
 * id; after a process restart the same draft is restored instead of mistaking a later,
 * identical routine for the old mutation.
 */
object WatchPendingWorkoutStorage {
    private const val PREFS_NAME = "watch_pending_workout"
    private const val KEY_OPERATION_ID = "operation_id"
    private const val KEY_DRAFT_ID = "draft_id"
    private const val KEY_FINGERPRINT = "fingerprint"
    private const val KEY_STARTED_AT = "started_at"
    private const val KEY_OWNER_ID = "owner_id"
    private const val KEY_ACCOUNT_GENERATION = "account_generation"
    private const val KEY_DRAFT_JSON = "draft_json"
    private const val KEY_SOURCE_PLAN_RAW = "source_plan_raw"
    private const val MAX_IDENTIFIER_LENGTH = 128
    private const val MAX_NOTE_LENGTH = 2_000

    fun getOrCreate(
        context: Context,
        binding: WatchSyncBinding,
        draftId: String,
        startedAt: Long,
        note: String?,
        sets: List<WearWorkoutSetDraft>,
        sourcePlanRaw: String?
    ): PendingWorkoutMutation {
        require(draftId.isNotBlank() && draftId.length <= MAX_IDENTIFIER_LENGTH)
        require(sourcePlanRaw == null || sourcePlanRaw.toByteArray(Charsets.UTF_8).size <= SyncPaths.MAX_MESSAGE_BYTES)
        val fingerprint = fingerprint(binding, draftId, note, sets, sourcePlanRaw)
        val existing = load(context, binding)
        if (existing?.draftId == draftId && existing.fingerprint == fingerprint) {
            return existing
        }

        require(startedAt > 0L)
        requireValidDraft(note, sets)
        val pending = PendingWorkoutMutation(
            operationId = UUID.randomUUID().toString(),
            draftId = draftId,
            fingerprint = fingerprint,
            startedAt = startedAt,
            note = note,
            sets = sets.map { it.copy() },
            sourcePlanRaw = sourcePlanRaw
        )
        val ownerId = requireNotNull(binding.ownerId)
        val draftJson = serializeDraft(note, sets)
        check(draftJson.toByteArray(Charsets.UTF_8).size <= SyncPaths.MAX_MESSAGE_BYTES)
        check(
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_OPERATION_ID, pending.operationId)
                .putString(KEY_DRAFT_ID, pending.draftId)
                .putString(KEY_FINGERPRINT, pending.fingerprint)
                .putLong(KEY_STARTED_AT, pending.startedAt)
                .putString(KEY_OWNER_ID, ownerId)
                .putLong(KEY_ACCOUNT_GENERATION, binding.accountGeneration)
                .putString(KEY_DRAFT_JSON, draftJson)
                .apply {
                    if (sourcePlanRaw == null) remove(KEY_SOURCE_PLAN_RAW)
                    else putString(KEY_SOURCE_PLAN_RAW, sourcePlanRaw)
                }
                .commit()
        ) { "Could not persist pending workout mutation" }
        return pending
    }

    fun load(context: Context, binding: WatchSyncBinding?): PendingWorkoutMutation? {
        if (binding?.ownerId == null || binding.accountGeneration <= 0L) return null
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val operationId = prefs.getString(KEY_OPERATION_ID, null)
            ?.takeIf { it.isNotBlank() && it.length <= MAX_IDENTIFIER_LENGTH }
            ?: return null
        val draftId = prefs.getString(KEY_DRAFT_ID, null)
            ?.takeIf { it.isNotBlank() && it.length <= MAX_IDENTIFIER_LENGTH }
            ?: return null
        val storedFingerprint = prefs.getString(KEY_FINGERPRINT, null)
            ?.takeIf { it.matches(Regex("[0-9a-f]{64}")) }
            ?: return null
        val startedAt = prefs.getLong(KEY_STARTED_AT, 0L).takeIf { it > 0L } ?: return null
        if (
            prefs.getString(KEY_OWNER_ID, null) != binding.ownerId ||
            prefs.getLong(KEY_ACCOUNT_GENERATION, 0L) != binding.accountGeneration
        ) {
            return null
        }
        val draftJson = prefs.getString(KEY_DRAFT_JSON, null)
            ?.takeIf { it.toByteArray(Charsets.UTF_8).size <= SyncPaths.MAX_MESSAGE_BYTES }
            ?: return null
        val (note, sets) = parseDraft(draftJson) ?: return null
        val sourcePlanRaw = prefs.getString(KEY_SOURCE_PLAN_RAW, null)?.takeIf {
            it.toByteArray(Charsets.UTF_8).size <= SyncPaths.MAX_MESSAGE_BYTES
        }
        val expectedFingerprint = fingerprint(binding, draftId, note, sets, sourcePlanRaw)
        if (storedFingerprint != expectedFingerprint) return null
        return PendingWorkoutMutation(
            operationId = operationId,
            draftId = draftId,
            fingerprint = storedFingerprint,
            startedAt = startedAt,
            note = note,
            sets = sets,
            sourcePlanRaw = sourcePlanRaw
        )
    }

    fun clearIfMatches(context: Context, pending: PendingWorkoutMutation) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (
            prefs.getString(KEY_OPERATION_ID, null) == pending.operationId &&
            prefs.getString(KEY_DRAFT_ID, null) == pending.draftId &&
            prefs.getString(KEY_FINGERPRINT, null) == pending.fingerprint
        ) {
            check(prefs.edit().clear().commit()) { "Could not clear pending workout mutation" }
        }
    }

    fun clear(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.all.isNotEmpty()) {
            check(prefs.edit().clear().commit()) { "Could not clear pending workout mutation" }
        }
    }

    private fun serializeDraft(note: String?, sets: List<WearWorkoutSetDraft>): String {
        val root = JSONObject()
        if (note == null) root.put("note", JSONObject.NULL) else root.put("note", note)
        val items = JSONArray()
        sets.forEach { set ->
            items.put(
                JSONObject()
                    .put("exerciseName", set.exerciseName)
                    .put("weight", set.weight)
                    .put("reps", set.reps)
            )
        }
        return root.put("sets", items).toString()
    }

    private fun parseDraft(raw: String): Pair<String?, List<WearWorkoutSetDraft>>? = runCatching {
        val root = JSONObject(raw)
        val note = if (root.isNull("note")) null else root.getString("note")
        val items = root.getJSONArray("sets")
        val sets = buildList(items.length()) {
            for (index in 0 until items.length()) {
                val item = items.getJSONObject(index)
                add(
                    WearWorkoutSetDraft(
                        exerciseName = item.getString("exerciseName"),
                        weight = item.getDouble("weight"),
                        reps = item.getInt("reps")
                    )
                )
            }
        }
        requireValidDraft(note, sets)
        note to sets
    }.getOrNull()

    private fun requireValidDraft(note: String?, sets: List<WearWorkoutSetDraft>) {
        require(note == null || note.length <= MAX_NOTE_LENGTH)
        require(sets.size in 1..SyncPaths.MAX_WORKOUT_SETS)
        sets.forEach { set ->
            require(set.exerciseName.isNotBlank())
            require(set.exerciseName.length <= SyncPaths.MAX_EXERCISE_NAME_LENGTH)
            require(set.weight.isFinite() && set.weight in 0.0..SyncPaths.MAX_WEIGHT)
            require(set.reps in 1..SyncPaths.MAX_REPS)
        }
    }

    private fun fingerprint(
        binding: WatchSyncBinding,
        draftId: String,
        note: String?,
        sets: List<WearWorkoutSetDraft>,
        sourcePlanRaw: String?
    ): String {
        val ownerId = requireNotNull(binding.ownerId)
        val canonical = buildString {
            append(ownerId.length).append(':').append(ownerId)
            append('|').append(binding.accountGeneration)
            append('|').append(draftId.length).append(':').append(draftId)
            append('|').append(note?.length ?: -1).append(':').append(note.orEmpty())
            append('|').append(sourcePlanRaw?.length ?: -1).append(':').append(sourcePlanRaw.orEmpty())
            sets.forEach { set ->
                append('|').append(set.exerciseName.length).append(':').append(set.exerciseName)
                append('|').append(java.lang.Double.doubleToLongBits(set.weight))
                append('|').append(set.reps)
            }
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(canonical.toByteArray(Charsets.UTF_8))
            .joinToString(separator = "") { byte -> "%02x".format(byte) }
    }
}
