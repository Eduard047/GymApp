package com.example.gymapp.wear.sync

import android.content.Context
import com.example.gymapp.wear.data.WearWorkoutSetDraft
import org.json.JSONArray
import org.json.JSONObject

/**
 * Duration and heart rate frozen at the moment the user pressed Save. Every later retry sends
 * exactly these values, however long the workout then waits for the phone.
 */
data class FinishedWorkoutSnapshot(
    val durationSeconds: Long?,
    val averageHeartRate: Int?,
    val maxHeartRate: Int?
)

/** The workout being recorded (or finished and waiting for the phone), as stored on disk. */
data class WatchWorkoutDraft(
    val draftId: String,
    val startedAt: Long,
    val pausedTotalMs: Long,
    val pausedAtMs: Long?,
    val usingPlan: Boolean,
    val selectedExercise: String?,
    val sets: List<WearWorkoutSetDraft>,
    /** Null while the workout is running; set once the user pressed Save. */
    val finished: FinishedWorkoutSnapshot?
)

/** JSON form of [WatchWorkoutDraft]. Decoding validates every bound and returns null otherwise. */
object WatchWorkoutDraftCodec {
    private const val MAX_IDENTIFIER_LENGTH = 128
    /** A pause can outlast the 24 h duration cap; anything beyond a month is corrupt data. */
    private const val MAX_PAUSED_MS = 31L * 86_400_000L

    fun encode(draft: WatchWorkoutDraft): String {
        val sets = JSONArray()
        draft.sets.forEach { set ->
            sets.put(
                JSONObject()
                    .put("exerciseName", set.exerciseName)
                    .put("weight", set.weight)
                    .put("reps", set.reps)
            )
        }
        val root = JSONObject()
            .put("draftId", draft.draftId)
            .put("startedAt", draft.startedAt)
            .put("pausedTotalMs", draft.pausedTotalMs)
            .put("usingPlan", draft.usingPlan)
            .put("sets", sets)
        draft.pausedAtMs?.let { root.put("pausedAtMs", it) }
        draft.selectedExercise?.let { root.put("selectedExercise", it) }
        draft.finished?.let { finished ->
            val item = JSONObject()
            finished.durationSeconds?.let { item.put("durationSeconds", it) }
            finished.averageHeartRate?.let { item.put("avgHeartRate", it) }
            finished.maxHeartRate?.let { item.put("maxHeartRate", it) }
            root.put("finished", item)
        }
        return root.toString()
    }

    fun decode(raw: String): WatchWorkoutDraft? = runCatching {
        require(raw.toByteArray(Charsets.UTF_8).size <= SyncPaths.MAX_MESSAGE_BYTES)
        val root = JSONObject(raw)
        val draftId = root.getString("draftId")
        require(draftId.isNotBlank() && draftId.length <= MAX_IDENTIFIER_LENGTH)
        val startedAt = root.getLong("startedAt")
        require(startedAt > 0L)
        val pausedTotalMs = root.optLong("pausedTotalMs", 0L)
        require(pausedTotalMs in 0L..MAX_PAUSED_MS)
        val pausedAtMs = if (root.has("pausedAtMs")) root.getLong("pausedAtMs") else null
        require(pausedAtMs == null || pausedAtMs >= startedAt)
        val selectedExercise = if (root.has("selectedExercise")) {
            root.getString("selectedExercise").trim().takeIf { it.isNotEmpty() }
        } else {
            null
        }
        require(selectedExercise == null || selectedExercise.length <= SyncPaths.MAX_EXERCISE_NAME_LENGTH)
        val items = root.getJSONArray("sets")
        require(items.length() <= SyncPaths.MAX_WORKOUT_SETS)
        val sets = buildList(items.length()) {
            for (index in 0 until items.length()) {
                val item = items.getJSONObject(index)
                val set = WearWorkoutSetDraft(
                    exerciseName = item.getString("exerciseName"),
                    weight = item.getDouble("weight"),
                    reps = item.getInt("reps")
                )
                require(set.exerciseName.isNotBlank())
                require(set.exerciseName.length <= SyncPaths.MAX_EXERCISE_NAME_LENGTH)
                require(set.weight.isFinite() && set.weight in 0.0..SyncPaths.MAX_WEIGHT)
                require(set.reps in 1..SyncPaths.MAX_REPS)
                add(set)
            }
        }
        val finished = root.optJSONObject("finished")?.let(::decodeFinished)
        // A finished workout always has sets; one without them is not worth keeping queued.
        require(finished == null || sets.isNotEmpty())
        WatchWorkoutDraft(
            draftId = draftId,
            startedAt = startedAt,
            pausedTotalMs = pausedTotalMs,
            pausedAtMs = pausedAtMs,
            usingPlan = root.optBoolean("usingPlan", false),
            selectedExercise = selectedExercise,
            sets = sets,
            finished = finished
        )
    }.getOrNull()

    /** Out-of-range optional values are dropped instead of failing the whole workout. */
    private fun decodeFinished(item: JSONObject): FinishedWorkoutSnapshot {
        val duration = if (item.has("durationSeconds")) {
            item.getLong("durationSeconds").takeIf { it in 0L..SyncPaths.MAX_DURATION_SECONDS }
        } else {
            null
        }
        val heartRates = SyncPaths.MIN_HEART_RATE..SyncPaths.MAX_HEART_RATE
        val average = if (item.has("avgHeartRate")) item.getInt("avgHeartRate").takeIf { it in heartRates } else null
        val max = if (item.has("maxHeartRate")) item.getInt("maxHeartRate").takeIf { it in heartRates } else null
        val consistent = average == null || max == null || max >= average
        return FinishedWorkoutSnapshot(
            durationSeconds = duration,
            averageHeartRate = average.takeIf { consistent },
            maxHeartRate = max.takeIf { consistent }
        )
    }
}

/** A stored draft with the owner it was recorded for (null only for data without a stamp). */
data class StoredWatchDraft(val draft: WatchWorkoutDraft, val ownerId: String?)

/**
 * Persists the workout in progress after every change, so a process death (low memory, a crash,
 * a revoked permission) loses neither the logged sets nor the start and pause times. The draft is
 * stamped with the owner it was recorded for and survives sign-out, account switches and
 * relinking: it is on hold until that owner is bound again, and only the user's Discard (or a
 * delivered send) removes it.
 */
object WatchWorkoutDraftStorage {
    private const val PREFS_NAME = "watch_workout_draft"
    private const val KEY_DRAFT = "draft"
    private const val KEY_OWNER_ID = "owner_id"

    /** [durable] waits for the write (set and finish changes); otherwise it is queued. */
    fun save(context: Context, ownerId: String?, draft: WatchWorkoutDraft, durable: Boolean): Boolean {
        val editor = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .putString(KEY_DRAFT, WatchWorkoutDraftCodec.encode(draft))
        ownerId?.let { editor.putString(KEY_OWNER_ID, it) }
        if (durable) return editor.commit()
        editor.apply()
        return true
    }

    fun load(context: Context): StoredWatchDraft? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_DRAFT, null) ?: return null
        val draft = WatchWorkoutDraftCodec.decode(raw)
        // Only an unreadable draft is dropped; another owner's draft stays on hold.
        if (draft == null) {
            clear(context)
            return null
        }
        return StoredWatchDraft(draft, prefs.getString(KEY_OWNER_ID, null))
    }

    /** Owner of the stored draft; null when there is no draft. */
    fun heldOwnerId(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_DRAFT)) return null
        return prefs.getString(KEY_OWNER_ID, null)
    }

    /** True when no draft is stored any more (the removal reached the disk). */
    fun clear(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.all.isEmpty() || prefs.edit().clear().commit()
    }
}
