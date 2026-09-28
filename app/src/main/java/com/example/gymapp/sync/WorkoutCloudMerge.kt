package com.example.gymapp.sync

import org.json.JSONArray
import org.json.JSONObject

/**
 * Per-workout three-way merge of the shared cloud workout row, as specified by
 * `shared/workout-sync-merge-v1.json`.
 *
 * The shared v2 row must stay readable by released 2.2.9 clients, which rewrite it whole and drop
 * unknown fields, so it cannot carry per-workout revisions or deletion markers. Instead each client
 * keeps the exact canonical core it last agreed with the cloud (the base) and compares every workout
 * by start time: a change on one side applies, additions and deletions on both sides combine, and
 * divergent changes to one workout go to the newer side. The local change time comes from the
 * per-workout journal; the remote change time is the fetched row's `updated_at`, because the row has
 * no per-workout edit time. A tie or a missing local time keeps the remote copy.
 */
internal data class WorkoutMergeExercise(
    val name: String,
    val catalogKey: String?
)

internal data class WorkoutMergeSet(
    val weight: Double,
    val reps: Int
)

internal data class WorkoutMergeBlock(
    val name: String,
    val catalogKey: String?,
    val sets: List<WorkoutMergeSet>
)

internal data class WorkoutMergeSession(
    val date: Long,
    val note: String?,
    val blocks: List<WorkoutMergeBlock>
)

internal data class WorkoutMergeCore(
    val exercises: List<WorkoutMergeExercise>,
    val sessions: List<WorkoutMergeSession>
)

internal data class WorkoutMergeResult(
    val merged: WorkoutMergeCore,
    /** Start times of divergent workouts that the newer local copy decided. */
    val localWins: Set<Long>,
    /** Start times of divergent workouts that the newer remote copy decided. */
    val remoteWins: Set<Long>
)

internal class WorkoutMergeException(message: String) : IllegalStateException(message)

internal object WorkoutCloudMerge {
    /**
     * @param exerciseIdentity Matches catalog entries across devices.
     * @param requiresCatalogEntry Whether a surviving workout block must keep its exercise in the
     * merged catalog. Android's shared catalog lists every exercise, so production keeps all.
     */
    fun merge(
        base: WorkoutMergeCore,
        local: WorkoutMergeCore,
        remote: WorkoutMergeCore,
        localChangedAt: Map<Long, Long>,
        remoteRowUpdatedAt: Long,
        exerciseIdentity: (WorkoutMergeExercise) -> String,
        requiresCatalogEntry: (WorkoutMergeBlock) -> Boolean = { true }
    ): WorkoutMergeResult {
        val baseSessions = sessionsByStart(base.sessions)
        val localSessions = sessionsByStart(local.sessions)
        val remoteSessions = sessionsByStart(remote.sessions)

        val mergedSessions = mutableMapOf<Long, WorkoutMergeSession>()
        val localWins = mutableSetOf<Long>()
        val remoteWins = mutableSetOf<Long>()
        val sessionKeys = baseSessions.keys + localSessions.keys + remoteSessions.keys
        for (key in sessionKeys) {
            val baseSession = baseSessions[key]
            val localSession = localSessions[key]
            val remoteSession = remoteSessions[key]
            val localTime = localChangedAt[key]
            val chosen = when {
                localSession == remoteSession -> localSession
                localSession == baseSession -> remoteSession
                remoteSession == baseSession -> localSession
                localTime != null && localTime > remoteRowUpdatedAt -> {
                    localWins += key
                    localSession
                }
                else -> {
                    remoteWins += key
                    remoteSession
                }
            }
            if (chosen != null) mergedSessions[key] = chosen
        }

        val baseExercises = exercisesByIdentity(base.exercises, exerciseIdentity)
        val localExercises = exercisesByIdentity(local.exercises, exerciseIdentity)
        val remoteExercises = exercisesByIdentity(remote.exercises, exerciseIdentity)
        val mergedExercises = mutableMapOf<String, WorkoutMergeExercise>()
        val exerciseKeys = baseExercises.keys + localExercises.keys + remoteExercises.keys
        for (key in exerciseKeys) {
            val baseExercise = baseExercises[key]
            val localExercise = localExercises[key]
            val remoteExercise = remoteExercises[key]
            // Catalog entries only appear or disappear; when both sides still have one with
            // different spelling details, the local copy is kept.
            val chosen = when {
                localExercise == remoteExercise -> localExercise
                localExercise == baseExercise -> remoteExercise
                remoteExercise == baseExercise -> localExercise
                else -> localExercise ?: remoteExercise
            }
            if (chosen != null) mergedExercises[key] = chosen
        }

        // A workout that survives the merge keeps every catalog entry it uses.
        for (session in mergedSessions.values) {
            for (block in session.blocks) {
                if (!requiresCatalogEntry(block)) continue
                val blockExercise = WorkoutMergeExercise(block.name, block.catalogKey)
                val key = exerciseIdentity(blockExercise)
                if (key in mergedExercises) continue
                mergedExercises[key] = localExercises[key] ?: remoteExercises[key] ?: blockExercise
            }
        }

        val sessions = mergedSessions.keys.sorted().map { mergedSessions.getValue(it) }
        val exercises = mergedExercises.entries
            .sortedBy { it.key }
            .map { it.value }
        return WorkoutMergeResult(
            merged = WorkoutMergeCore(exercises = exercises, sessions = sessions),
            localWins = localWins,
            remoteWins = remoteWins
        )
    }

    /** Start times of workouts that were added, removed, or changed between two cores. */
    fun changedSessionStarts(before: WorkoutMergeCore, after: WorkoutMergeCore): Set<Long> {
        val beforeByStart = before.sessions.associateBy { it.date }
        val afterByStart = after.sessions.associateBy { it.date }
        return (beforeByStart.keys + afterByStart.keys)
            .filterTo(mutableSetOf()) { start -> beforeByStart[start] != afterByStart[start] }
    }

    private fun sessionsByStart(sessions: List<WorkoutMergeSession>): Map<Long, WorkoutMergeSession> {
        val result = mutableMapOf<Long, WorkoutMergeSession>()
        for (session in sessions) {
            if (result.put(session.date, session) != null) {
                throw WorkoutMergeException("Two workouts share one start time.")
            }
        }
        return result
    }

    private fun exercisesByIdentity(
        exercises: List<WorkoutMergeExercise>,
        identity: (WorkoutMergeExercise) -> String
    ): Map<String, WorkoutMergeExercise> {
        val result = mutableMapOf<String, WorkoutMergeExercise>()
        for (exercise in exercises) {
            if (result.put(identity(exercise), exercise) != null) {
                throw WorkoutMergeException("Two catalog entries share one identity.")
            }
        }
        return result
    }
}

/**
 * Owner-bound per-workout sync state kept on this installation only: the exact core last agreed
 * with the cloud, its digest (checked against the stored sync baseline before use), and when each
 * workout last changed on this device.
 */
internal data class WorkoutCloudSyncState(
    val ownerUserId: String,
    val baselineDigest: String?,
    val baseline: WorkoutMergeCore?,
    /** Epoch milliseconds of the latest local change, keyed by workout start time. */
    val localChangedAt: Map<Long, Long>
) {
    init {
        require(ownerUserId.isNotBlank() && ownerUserId.length <= 256)
        require(localChangedAt.size <= MAX_JOURNAL_ENTRIES)
        require((baselineDigest == null) == (baseline == null))
    }

    fun toJson(): JSONObject = JSONObject()
        .put("version", VERSION)
        .put("ownerUserId", ownerUserId)
        .apply {
            if (baseline != null && baselineDigest != null) {
                put("baselineDigest", baselineDigest)
                put("baseline", encodeCore(baseline))
            }
        }
        .put("localChangedAt", JSONArray().apply {
            localChangedAt.entries.sortedBy { it.key }.forEach { (start, changedAt) ->
                put(JSONArray().put(start).put(changedAt))
            }
        })

    /** Keeps the newest entries when the journal would grow past its bound. */
    fun withChanges(starts: Set<Long>, changedAt: Long): WorkoutCloudSyncState {
        if (starts.isEmpty()) return this
        val journal = localChangedAt.toMutableMap()
        starts.forEach { journal[it] = changedAt }
        val overflow = journal.size - MAX_JOURNAL_ENTRIES
        if (overflow > 0) {
            journal.entries.sortedBy { it.value }.take(overflow).map { it.key }.forEach(journal::remove)
        }
        return copy(localChangedAt = journal)
    }

    companion object {
        const val VERSION = 1
        const val MAX_JOURNAL_ENTRIES = 10_000

        fun fromJson(json: JSONObject): WorkoutCloudSyncState {
            require(json.optInt("version", -1) == VERSION) { "Unsupported workout sync state." }
            val baselineJson = json.optJSONObject("baseline")
            val journalJson = json.optJSONArray("localChangedAt") ?: JSONArray()
            val journal = mutableMapOf<Long, Long>()
            repeat(journalJson.length()) { index ->
                val entry = journalJson.getJSONArray(index)
                require(entry.length() == 2)
                journal[entry.getLong(0)] = entry.getLong(1)
            }
            return WorkoutCloudSyncState(
                ownerUserId = json.getString("ownerUserId"),
                baselineDigest = if (baselineJson == null) null else json.getString("baselineDigest"),
                baseline = baselineJson?.let(::decodeCore),
                localChangedAt = journal
            )
        }

        fun encodeCore(core: WorkoutMergeCore): JSONObject = JSONObject()
            .put("exercises", JSONArray().apply {
                core.exercises.forEach { exercise ->
                    put(JSONObject().put("name", exercise.name).putOpt("catalogKey", exercise.catalogKey))
                }
            })
            .put("sessions", JSONArray().apply {
                core.sessions.forEach { session ->
                    put(
                        JSONObject()
                            .put("date", session.date)
                            .putOpt("note", session.note)
                            .put("exercises", JSONArray().apply {
                                session.blocks.forEach { block ->
                                    put(
                                        JSONObject()
                                            .put("name", block.name)
                                            .putOpt("catalogKey", block.catalogKey)
                                            .put("sets", JSONArray().apply {
                                                block.sets.forEach { set ->
                                                    put(JSONObject().put("weight", set.weight).put("reps", set.reps))
                                                }
                                            })
                                    )
                                }
                            })
                    )
                }
            })

        fun decodeCore(json: JSONObject): WorkoutMergeCore {
            val exercises = json.getJSONArray("exercises")
            val sessions = json.getJSONArray("sessions")
            return WorkoutMergeCore(
                exercises = List(exercises.length()) { index ->
                    val exercise = exercises.getJSONObject(index)
                    WorkoutMergeExercise(exercise.getString("name"), exercise.optStringOrNull("catalogKey"))
                },
                sessions = List(sessions.length()) { index ->
                    val session = sessions.getJSONObject(index)
                    val blocks = session.getJSONArray("exercises")
                    WorkoutMergeSession(
                        date = session.getLong("date"),
                        note = session.optStringOrNull("note"),
                        blocks = List(blocks.length()) { blockIndex ->
                            val block = blocks.getJSONObject(blockIndex)
                            val sets = block.getJSONArray("sets")
                            WorkoutMergeBlock(
                                name = block.getString("name"),
                                catalogKey = block.optStringOrNull("catalogKey"),
                                sets = List(sets.length()) { setIndex ->
                                    val set = sets.getJSONObject(setIndex)
                                    WorkoutMergeSet(
                                        weight = canonicalWeight(set.getDouble("weight")),
                                        reps = set.getInt("reps")
                                    )
                                }
                            )
                        }
                    )
                }
            )
        }

        /** 0.0 and -0.0 are the same weight; data class equality would tell them apart. */
        fun canonicalWeight(weight: Double): Double = if (weight == 0.0) 0.0 else weight

        private fun JSONObject.optStringOrNull(key: String): String? =
            if (has(key) && !isNull(key)) getString(key) else null
    }
}
