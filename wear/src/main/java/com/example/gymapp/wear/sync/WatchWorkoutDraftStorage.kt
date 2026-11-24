package com.example.gymapp.wear.sync

import android.content.Context
import com.example.gymapp.wear.data.WearWorkoutSetDraft
import com.example.gymapp.wear.health.RestTimerLogic
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
    val finished: FinishedWorkoutSnapshot?,
    /** Wall-clock end (epoch ms) of the running rest countdown; null when no rest runs. */
    val restEndsAtMs: Long? = null,
    /** Rest left when the workout was paused during a rest (0 = none). */
    val pausedRestRemainingSeconds: Int = 0,
    /**
     * SHA-256 (hex) of the plan the workout was started from; null for a free workout and for
     * drafts written before it existed. The plan itself is kept by [WatchWorkoutDraftStorage].
     */
    val sourcePlanDigest: String? = null
)

/**
 * Which plan a workout follows. A plan workout keeps the plan it was started from, even when the
 * phone has stored a newer one in the meantime (applied only after this workout).
 */
object WorkoutSourcePlan {
    private val digestPattern = Regex("^[0-9a-f]{64}$")

    fun digest(raw: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(raw.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    fun isDigest(value: String?): Boolean = value != null && digestPattern.matches(value)

    /**
     * The raw plan a restored draft follows (a stored operation carries its own plan instead).
     * The draft names its plan by digest and finds it in its own snapshot, or in the stored plan
     * if that is still the same one. A draft written before the digest existed falls back to the
     * stored plan, as before. Null: free workout, or the plan it used is gone.
     */
    fun forRestore(
        draftUsingPlan: Boolean,
        draftDigest: String?,
        snapshotRaw: String?,
        storedPlanRaw: String?
    ): String? {
        if (!draftUsingPlan) return null
        if (draftDigest == null) return storedPlanRaw
        return listOfNotNull(snapshotRaw, storedPlanRaw).firstOrNull { digest(it) == draftDigest }
    }

    /** After a delivered save: drop the stored plan only when it is the one this workout used. */
    fun shouldClearStoredPlan(storedPlanRaw: String?, sourcePlanRaw: String?): Boolean =
        sourcePlanRaw != null && storedPlanRaw == sourcePlanRaw
}

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
        draft.restEndsAtMs?.let { root.put("restEndsAtMs", it) }
        if (draft.pausedRestRemainingSeconds > 0) {
            root.put("pausedRestRemainingSeconds", draft.pausedRestRemainingSeconds)
        }
        draft.sourcePlanDigest?.takeIf(WorkoutSourcePlan::isDigest)?.let { root.put("sourcePlanDigest", it) }
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
            finished = finished,
            // Rest state is optional: a bad value drops the countdown, never the workout.
            restEndsAtMs = root.optLong("restEndsAtMs", 0L).takeIf { it > 0L },
            pausedRestRemainingSeconds = root.optInt("pausedRestRemainingSeconds", 0)
                .takeIf { it in 0..RestTimerLogic.MAX_REST_SECONDS } ?: 0,
            // Optional too: an unreadable digest only loses the plan targets, never the workout.
            sourcePlanDigest = root.optString("sourcePlanDigest", "")
                .takeIf(WorkoutSourcePlan::isDigest)
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

    /**
     * The plan a running plan workout was started from. A file of its own: it is written once
     * at Start, not with every set, and the draft names it by [WatchWorkoutDraft.sourcePlanDigest].
     */
    private const val SOURCE_PLAN_PREFS_NAME = "watch_workout_source_plan"
    private const val KEY_SOURCE_PLAN = "plan_json"

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

    /** Keeps [rawPlan] as the plan of the workout being started (null: free workout). */
    fun saveSourcePlan(context: Context, rawPlan: String?): Boolean {
        val prefs = context.getSharedPreferences(SOURCE_PLAN_PREFS_NAME, Context.MODE_PRIVATE)
        if (rawPlan == null && !prefs.contains(KEY_SOURCE_PLAN)) return true
        val editor = prefs.edit()
        if (rawPlan == null) editor.remove(KEY_SOURCE_PLAN) else editor.putString(KEY_SOURCE_PLAN, rawPlan)
        return editor.commit()
    }

    fun loadSourcePlan(context: Context): String? =
        context.getSharedPreferences(SOURCE_PLAN_PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_SOURCE_PLAN, null)
            ?.takeIf { it.isNotBlank() }

    /** The plan [draft] follows (see [WorkoutSourcePlan.forRestore]); null for a free workout. */
    fun sourcePlanFor(context: Context, draft: WatchWorkoutDraft, storedPlanRaw: String?): String? =
        WorkoutSourcePlan.forRestore(
            draftUsingPlan = draft.usingPlan,
            draftDigest = draft.sourcePlanDigest,
            snapshotRaw = if (draft.usingPlan && draft.sourcePlanDigest != null) loadSourcePlan(context) else null,
            storedPlanRaw = storedPlanRaw
        )

    /** True when no draft is stored any more (the removal reached the disk). */
    fun clear(context: Context): Boolean {
        // The plan snapshot goes with the draft; a leftover one is harmless (named by digest).
        runCatching { saveSourcePlan(context, null) }
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.all.isEmpty() || prefs.edit().clear().commit()
    }
}
