package com.example.gymapp.wear.sync

import com.example.gymapp.wear.data.WearWorkoutSetDraft
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.floor

data class SyncedSetPayload(
    val id: Long,
    val sessionId: Long,
    val exerciseName: String,
    val weight: Double,
    val reps: Int,
    val orderIndex: Int
)

data class SyncedSessionPayload(
    val id: Long,
    val startedAt: Long,
    val note: String?,
    val sets: List<SyncedSetPayload>
)

data class SyncedWorkoutPlanMeta(
    val planSource: String,
    val split: String?,
    val workoutsPerWeek: Int?,
    val goal: String?,
    val calorieMode: String?
)

data class WatchSyncEnvelope(
    val ownerId: String,
    val accountGeneration: Long,
    val revision: Long,
    val messageId: String,
    val sentAt: Long
)

data class ParsedFullSyncPayload(
    val envelope: WatchSyncEnvelope,
    val sessions: List<SyncedSessionPayload>,
    val exerciseCatalog: List<String>
)

data class ParsedWorkoutPlanPayload(
    val envelope: WatchSyncEnvelope,
    val expiresAt: Long,
    val sets: List<WearWorkoutSetDraft>,
    val exerciseCatalog: List<String>,
    val meta: SyncedWorkoutPlanMeta
)

data class ParsedMutationAck(
    val ownerId: String,
    val accountGeneration: Long,
    val operationId: String,
    val accepted: Boolean,
    val sentAt: Long
)

sealed interface WatchSyncParseResult<out T> {
    data class Valid<T>(val value: T) : WatchSyncParseResult<T>
    data class Invalid(val reason: String) : WatchSyncParseResult<Nothing>
}

object WatchSyncJson {
    private const val MIN_TIMESTAMP_MS = 946_684_800_000L // 2000-01-01
    private const val MAX_CLOCK_SKEW_MS = 5 * 60 * 1_000L
    private const val MAX_MESSAGE_AGE_MS = 7 * 24 * 60 * 60 * 1_000L
    private const val MAX_PLAN_LIFETIME_MS = 30L * 24 * 60 * 60 * 1_000
    private const val MAX_IDENTIFIER_LENGTH = 128
    private const val MAX_PROFILE_VALUE_LENGTH = 64
    private const val MAX_JSON_NESTING = 32
    private const val MAX_JSON_STRING_BYTES = 64 * 1024

    fun buildFullSyncRequestPayload(
        operationId: String,
        binding: WatchSyncBinding?
    ): String = commandEnvelope("request_full_sync", operationId, binding).toString()

    fun buildCreateWorkoutPayload(
        operationId: String,
        binding: WatchSyncBinding,
        startedAt: Long,
        note: String?,
        sets: List<WearWorkoutSetDraft>
    ): String {
        require(binding.ownerId != null) { "Account binding required" }
        require(startedAt in MIN_TIMESTAMP_MS..(System.currentTimeMillis() + MAX_CLOCK_SKEW_MS))
        require(note == null || note.length <= SyncPaths.MAX_NOTE_LENGTH)
        require(sets.isNotEmpty() && sets.size <= SyncPaths.MAX_WORKOUT_SETS)

        val setsJson = JSONArray()
        sets.forEach { set ->
            requireValidSet(set.exerciseName, set.weight, set.reps)
            setsJson.put(
                JSONObject()
                    .put("exerciseName", set.exerciseName.trim())
                    .put("weight", set.weight)
                    .put("reps", set.reps)
            )
        }

        return commandEnvelope("create_workout", operationId, binding)
            .put("startedAt", startedAt)
            .put("note", note)
            .put("sets", setsJson)
            .toString()
    }

    fun buildUpdateSetPayload(
        operationId: String,
        binding: WatchSyncBinding,
        setId: Long,
        weight: Double,
        reps: Int
    ): String {
        require(binding.ownerId != null) { "Account binding required" }
        require(setId > 0)
        requireValidWeightAndReps(weight, reps)
        return commandEnvelope("update_set", operationId, binding)
            .put("setId", setId)
            .put("weight", weight)
            .put("reps", reps)
            .toString()
    }

    fun buildDeleteSetPayload(
        operationId: String,
        binding: WatchSyncBinding,
        setId: Long
    ): String {
        require(binding.ownerId != null) { "Account binding required" }
        require(setId > 0)
        return commandEnvelope("delete_set", operationId, binding)
            .put("setId", setId)
            .toString()
    }

    fun parseWorkoutPlanPayload(raw: String): WatchSyncParseResult<ParsedWorkoutPlanPayload> {
        return parseCatching {
            requirePayloadSize(raw)
            val now = System.currentTimeMillis()
            val root = JSONObject(raw)
            val envelope = parseEnvelope(root, now)
            val expiresAt = root.requiredLong("expiresAt")
            require(expiresAt > now && expiresAt <= envelope.sentAt + MAX_PLAN_LIFETIME_MS) {
                "Plan is expired or has an invalid lifetime"
            }

            val setsArray = root.requiredArray("sets")
            require(setsArray.length() in 1..SyncPaths.MAX_PLAN_SETS) { "Invalid plan set count" }
            val sets = buildList(setsArray.length()) {
                for (index in 0 until setsArray.length()) {
                    val item = setsArray.requiredObject(index)
                    val exerciseName = item.requiredString(
                        key = "exerciseName",
                        maxLength = SyncPaths.MAX_EXERCISE_NAME_LENGTH
                    ).trim()
                    val weight = item.requiredFiniteDouble("weight")
                    val reps = item.requiredInt("reps")
                    requireValidSet(exerciseName, weight, reps)
                    add(WearWorkoutSetDraft(exerciseName, weight, reps))
                }
            }

            val profile = root.optionalObject("trainingProfile")
            val meta = SyncedWorkoutPlanMeta(
                planSource = root.optionalBoundedString("planSource", 32) ?: "manual",
                split = profile?.optionalBoundedString("split", MAX_PROFILE_VALUE_LENGTH),
                workoutsPerWeek = profile?.optionalInt("workoutsPerWeek")?.also {
                    require(it in 1..14) { "Invalid workoutsPerWeek" }
                },
                goal = profile?.optionalBoundedString("goal", MAX_PROFILE_VALUE_LENGTH),
                calorieMode = profile?.optionalBoundedString("calorieMode", MAX_PROFILE_VALUE_LENGTH)
            )
            ParsedWorkoutPlanPayload(
                envelope = envelope,
                expiresAt = expiresAt,
                sets = sets,
                exerciseCatalog = parseExerciseCatalog(root),
                meta = meta
            )
        }
    }

    fun parseFullSyncPayload(raw: String): WatchSyncParseResult<ParsedFullSyncPayload> {
        return parseCatching {
            requirePayloadSize(raw)
            val now = System.currentTimeMillis()
            val root = JSONObject(raw)
            val envelope = parseEnvelope(root, now)
            val sessionsJson = root.requiredArray("sessions")
            require(sessionsJson.length() <= SyncPaths.MAX_SYNC_SESSIONS) { "Too many sessions" }

            var totalSets = 0
            val sessionIds = hashSetOf<Long>()
            val setIds = hashSetOf<Long>()
            val sessions = buildList(sessionsJson.length()) {
                for (sessionIndex in 0 until sessionsJson.length()) {
                    val session = sessionsJson.requiredObject(sessionIndex)
                    val sessionId = session.requiredLong("id")
                    require(sessionId > 0 && sessionIds.add(sessionId)) { "Invalid or duplicate session id" }
                    val startedAt = session.requiredLong("startedAt")
                    require(startedAt in MIN_TIMESTAMP_MS..(now + MAX_CLOCK_SKEW_MS)) {
                        "Invalid session timestamp"
                    }
                    val note = session.optionalBoundedString("note", SyncPaths.MAX_NOTE_LENGTH)
                    val setsJson = session.requiredArray("sets")
                    require(setsJson.length() <= SyncPaths.MAX_WORKOUT_SETS) { "Too many sets in session" }
                    totalSets += setsJson.length()
                    require(totalSets <= SyncPaths.MAX_SYNC_TOTAL_SETS) { "Too many total sets" }

                    val orderIndexes = hashSetOf<Int>()
                    val sets = buildList(setsJson.length()) {
                        for (setIndex in 0 until setsJson.length()) {
                            val set = setsJson.requiredObject(setIndex)
                            val setId = set.requiredLong("id")
                            val payloadSessionId = set.requiredLong("sessionId")
                            val exerciseName = set.requiredString(
                                key = "exerciseName",
                                maxLength = SyncPaths.MAX_EXERCISE_NAME_LENGTH
                            ).trim()
                            val weight = set.requiredFiniteDouble("weight")
                            val reps = set.requiredInt("reps")
                            val orderIndex = set.requiredInt("orderIndex")
                            require(setId > 0 && setIds.add(setId)) { "Invalid or duplicate set id" }
                            require(payloadSessionId == sessionId) { "Set belongs to another session" }
                            require(orderIndex in 0 until SyncPaths.MAX_WORKOUT_SETS && orderIndexes.add(orderIndex)) {
                                "Invalid or duplicate set order"
                            }
                            requireValidSet(exerciseName, weight, reps)
                            add(
                                SyncedSetPayload(
                                    id = setId,
                                    sessionId = payloadSessionId,
                                    exerciseName = exerciseName,
                                    weight = weight,
                                    reps = reps,
                                    orderIndex = orderIndex
                                )
                            )
                        }
                    }
                    add(
                        SyncedSessionPayload(
                            id = sessionId,
                            startedAt = startedAt,
                            note = note,
                            sets = sets.sortedBy { it.orderIndex }
                        )
                    )
                }
            }

            ParsedFullSyncPayload(
                envelope = envelope,
                sessions = sessions,
                exerciseCatalog = parseExerciseCatalog(root)
            )
        }
    }

    fun parseMutationAck(raw: String): WatchSyncParseResult<ParsedMutationAck> {
        return parseCatching {
            requirePayloadSize(raw)
            val now = System.currentTimeMillis()
            val root = JSONObject(raw)
            require(root.requiredInt("protocolVersion") == SyncPaths.PROTOCOL_VERSION)
            val ownerId = root.requiredString("ownerId", MAX_IDENTIFIER_LENGTH).trim()
            val accountGeneration = root.requiredLong("accountGeneration")
            val operationId = root.requiredString("operationId", MAX_IDENTIFIER_LENGTH).trim()
            val status = root.requiredString("status", 16)
            val sentAt = root.requiredLong("sentAt")
            require(
                ownerId.isNotEmpty() &&
                    accountGeneration in 1L..SyncPaths.MAX_PROTOCOL_COUNTER &&
                    operationId.isNotEmpty()
            )
            require(status == "accepted" || status == "rejected")
            require(sentAt in (now - MAX_MESSAGE_AGE_MS)..(now + MAX_CLOCK_SKEW_MS))
            ParsedMutationAck(
                ownerId = ownerId,
                accountGeneration = accountGeneration,
                operationId = operationId,
                accepted = status == "accepted",
                sentAt = sentAt
            )
        }
    }

    private fun parseEnvelope(root: JSONObject, now: Long): WatchSyncEnvelope {
        require(root.requiredInt("protocolVersion") == SyncPaths.PROTOCOL_VERSION) {
            "Unsupported protocol version"
        }
        val ownerId = root.requiredString("ownerId", MAX_IDENTIFIER_LENGTH).trim()
        val accountGeneration = root.requiredLong("accountGeneration")
        val revision = root.requiredLong("revision")
        val messageId = root.requiredString("messageId", MAX_IDENTIFIER_LENGTH).trim()
        val sentAt = root.requiredLong("sentAt")
        require(ownerId.isNotEmpty() && messageId.isNotEmpty()) { "Missing sync binding" }
        require(
            accountGeneration in 1L..SyncPaths.MAX_PROTOCOL_COUNTER &&
                revision in 1L..SyncPaths.MAX_PROTOCOL_COUNTER
        ) { "Invalid sync revision" }
        require(sentAt in (now - MAX_MESSAGE_AGE_MS)..(now + MAX_CLOCK_SKEW_MS)) { "Stale sync message" }
        return WatchSyncEnvelope(ownerId, accountGeneration, revision, messageId, sentAt)
    }

    private fun parseExerciseCatalog(root: JSONObject): List<String> {
        if (!root.has("exerciseCatalog") || root.isNull("exerciseCatalog")) return emptyList()
        val catalog = root.requiredArray("exerciseCatalog")
        require(catalog.length() <= SyncPaths.MAX_EXERCISE_CATALOG) { "Exercise catalog is too large" }
        val unique = linkedSetOf<String>()
        for (index in 0 until catalog.length()) {
            val item = catalog.requiredString(index, SyncPaths.MAX_EXERCISE_NAME_LENGTH).trim()
            require(item.isNotEmpty()) { "Blank exercise catalog entry" }
            unique += item
        }
        return unique.toList()
    }

    private fun commandEnvelope(
        type: String,
        operationId: String,
        binding: WatchSyncBinding?
    ): JSONObject {
        require(operationId.isNotBlank() && operationId.length <= MAX_IDENTIFIER_LENGTH)
        return JSONObject()
            .put("type", type)
            .put("protocolVersion", SyncPaths.PROTOCOL_VERSION)
            .put("operationId", operationId)
            .put("sentAt", System.currentTimeMillis())
            .apply {
                if (binding?.ownerId != null) {
                    put("ownerId", binding.ownerId)
                    put("accountGeneration", binding.accountGeneration)
                }
            }
    }

    private fun requirePayloadSize(raw: String) {
        require(raw.toByteArray(Charsets.UTF_8).size <= SyncPaths.MAX_MESSAGE_BYTES) {
            "Sync payload is too large"
        }
        requireJsonStructureBounds(raw)
    }

    private fun requireJsonStructureBounds(raw: String) {
        var depth = 0
        var inString = false
        var escaped = false
        var stringBytes = 0

        raw.forEach { character ->
            if (inString) {
                if (escaped) {
                    escaped = false
                    stringBytes += character.toString().toByteArray(Charsets.UTF_8).size
                } else {
                    when (character) {
                        '\\' -> escaped = true
                        '"' -> {
                            inString = false
                            stringBytes = 0
                        }
                        else -> stringBytes += character.toString().toByteArray(Charsets.UTF_8).size
                    }
                }
                require(stringBytes <= MAX_JSON_STRING_BYTES) { "JSON string is too large" }
            } else {
                when (character) {
                    '"' -> {
                        inString = true
                        stringBytes = 0
                    }
                    '{', '[' -> {
                        depth += 1
                        require(depth <= MAX_JSON_NESTING) { "JSON nesting is too deep" }
                    }
                    '}', ']' -> {
                        depth -= 1
                        require(depth >= 0) { "JSON structure is malformed" }
                    }
                }
            }
        }
        require(!inString && !escaped && depth == 0) { "JSON structure is malformed" }
    }

    private fun requireValidSet(exerciseName: String, weight: Double, reps: Int) {
        require(exerciseName.isNotBlank() && exerciseName.length <= SyncPaths.MAX_EXERCISE_NAME_LENGTH)
        requireValidWeightAndReps(weight, reps)
    }

    private fun requireValidWeightAndReps(weight: Double, reps: Int) {
        require(weight.isFinite() && weight in 0.0..SyncPaths.MAX_WEIGHT)
        require(reps in 1..SyncPaths.MAX_REPS)
    }

    private inline fun <T> parseCatching(block: () -> T): WatchSyncParseResult<T> {
        return try {
            WatchSyncParseResult.Valid(block())
        } catch (error: Exception) {
            WatchSyncParseResult.Invalid(error.message ?: "Invalid sync payload")
        }
    }

    private fun JSONObject.requiredArray(key: String): JSONArray {
        val value = get(key)
        require(value is JSONArray) { "$key must be an array" }
        return value
    }

    private fun JSONObject.optionalObject(key: String): JSONObject? {
        if (!has(key) || isNull(key)) return null
        val value = get(key)
        require(value is JSONObject) { "$key must be an object" }
        return value
    }

    private fun JSONObject.requiredString(key: String, maxLength: Int): String {
        val value = get(key)
        require(value is String && value.length <= maxLength) { "$key must be a bounded string" }
        return value
    }

    private fun JSONObject.optionalBoundedString(key: String, maxLength: Int): String? {
        if (!has(key) || isNull(key)) return null
        val value = requiredString(key, maxLength).trim()
        return value.takeIf { it.isNotEmpty() }
    }

    private fun JSONObject.requiredLong(key: String): Long {
        val value = get(key)
        require(value is Number) { "$key must be a number" }
        val doubleValue = value.toDouble()
        require(doubleValue.isFinite() && floor(doubleValue) == doubleValue) { "$key must be an integer" }
        val longValue = value.toLong()
        require(longValue.toDouble() == doubleValue) { "$key is out of range" }
        return longValue
    }

    private fun JSONObject.requiredInt(key: String): Int {
        val longValue = requiredLong(key)
        require(longValue in Int.MIN_VALUE..Int.MAX_VALUE) { "$key is out of range" }
        return longValue.toInt()
    }

    private fun JSONObject.optionalInt(key: String): Int? {
        if (!has(key) || isNull(key)) return null
        return requiredInt(key)
    }

    private fun JSONObject.requiredFiniteDouble(key: String): Double {
        val value = get(key)
        require(value is Number) { "$key must be a number" }
        return value.toDouble().also { require(it.isFinite()) { "$key must be finite" } }
    }

    private fun JSONArray.requiredObject(index: Int): JSONObject {
        val value = get(index)
        require(value is JSONObject) { "Array item must be an object" }
        return value
    }

    private fun JSONArray.requiredString(index: Int, maxLength: Int): String {
        val value = get(index)
        require(value is String && value.length <= maxLength) { "Array item must be a bounded string" }
        return value
    }
}
