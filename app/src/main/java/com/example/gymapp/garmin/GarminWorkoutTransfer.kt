package com.example.gymapp.garmin

import org.json.JSONArray
import org.json.JSONObject

/** Pure, bounded staging. The caller must durably store [state] before sending nextOffset. */
internal data class GarminTransferStep(
    val state: String,
    val nextOffset: Int,
    val attemptId: String,
    val completeMessage: Map<Any?, Any?>?
)

internal object GarminWorkoutTransfer {
    private const val MAX_FRAME_BYTES = 4096
    private const val MAX_STATE_BYTES = 65536
    private const val MAX_AGE_MILLIS = 86_400_000L
    private val frameKeys = setOf(
        "type", "transferVersion", "offset", "totalSets", "attemptId", "metadata", "set", "interval", "metrics"
    )
    private val metadataKeys = setOf(
        "type", "bindingVersion", "workoutMode", "requestId", "accountBinding", "deviceBinding",
        "pairingGeneration", "startedAtSeconds", "durationSeconds", "gymCalories", "garminCalories",
        "avgHeartRate", "maxHeartRate", "lastHeartRate", "heartRateZone", "plannedSetCount",
        "plannedTargetSetCount", "completedPlannedSetCount"
    )
    private val setKeys = setOf("exerciseName", "weight", "reps")

    fun stagedAccount(text: String): String? = runCatching {
        val metadata = decode(text)["metadata"] as? Map<*, *> ?: return null
        (metadata["accountBinding"] as? String)?.takeIf(::isValidGarminAccountBinding)
    }.getOrNull()

    fun copyFrame(raw: Map<Any?, Any?>): Map<Any?, Any?>? = runCatching {
        require(raw.keys.all { it in frameKeys } && bounded(raw, 0))
        val text = json(raw)
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_FRAME_BYTES)
        decode(text).mapKeys { it.key as Any? }
    }.getOrNull()

    fun accept(
        previous: String?, raw: Map<Any?, Any?>, binding: GarminBinding, nowMillis: Long
    ): GarminTransferStep? = runCatching {
        require(raw.keys.all { it in frameKeys } && bounded(raw, 0))
        require(json(raw).toByteArray(Charsets.UTF_8).size <= MAX_FRAME_BYTES)
        require(raw["type"] == "workout_part" && integer(raw["transferVersion"], 1, 1) == 1)
        val attemptId = raw["attemptId"] as? String ?: error("Attempt")
        require(isValidGarminMessageId(attemptId, MAX_GARMIN_REQUEST_ID_LENGTH))
        val total = integer(raw["totalSets"], 0, 60)
        val offset = integer(raw["offset"], 0, if (total == 0) 0 else total - 1)
        @Suppress("UNCHECKED_CAST")
        val metadata = raw["metadata"] as? Map<Any?, Any?> ?: error("Metadata")
        require(metadata.keys.all { it in metadataKeys })
        require(metadata["type"] == "create_workout" &&
            garminBindingDecision(metadata, binding) == GarminBindingDecision.Bound)
        val free = metadata["workoutMode"] == "free"
        require((total == 0) == free)
        val row = raw["set"]
        if (free) {
            require(!raw.containsKey("set") && !raw.containsKey("interval") && !raw.containsKey("metrics"))
        } else {
            require(row is Map<*, *> && row.keys == setKeys)
        }
        // Reuse the released parser for every scalar and row. Plan completion is
        // checked against the declared total; full interval consistency is checked
        // again against the actual assembled rows before exposing a workout.
        val scalarCheck = metadata.toMutableMap()
        scalarCheck["sets"] = if (free) emptyList<Any>() else List(total) { mapOf("exerciseName" to "X", "weight" to 0.0, "reps" to 1) }
        require(parseGarminWorkoutCommand(scalarCheck, nowMillis) != null)
        val rowCheck = metadata.toMutableMap()
        rowCheck.remove("plannedSetCount")
        rowCheck.remove("plannedTargetSetCount")
        rowCheck.remove("completedPlannedSetCount")
        rowCheck["sets"] = if (free) emptyList<Any>() else listOf(row)
        if (raw.containsKey("interval")) rowCheck["setIntervals"] = listOf(raw["interval"])
        if (raw.containsKey("metrics")) rowCheck["setMetrics"] = listOf(raw["metrics"])
        require(parseGarminWorkoutCommand(rowCheck, nowMillis) != null)

        val old = previous?.let { decode(it) }
        val state = if (old != null) {
            require(old.keys.all { it in setOf("version", "createdAt", "totalSets", "metadata", "sets", "intervals", "metrics") })
            val clock = old["createdAt"] as? Number ?: error("Clock")
            require(clock.toDouble().isFinite() && clock.toDouble() % 1.0 == 0.0)
            val created = clock.toLong()
            require(created >= 0 && created <= nowMillis)
            @Suppress("UNCHECKED_CAST")
            val oldMetadata = old["metadata"] as? Map<Any?, Any?> ?: error("Metadata")
            if (nowMillis - created > MAX_AGE_MILLIS ||
                garminBindingDecision(oldMetadata, binding) != GarminBindingDecision.Bound) null else old
        } else null
        val sets: MutableList<Any?>
        val intervals: MutableList<Any?>?
        val metrics: MutableList<Any?>?
        val created: Long
        if (state == null) {
            require(offset == 0)
            sets = mutableListOf()
            intervals = if (raw.containsKey("interval")) mutableListOf() else null
            metrics = if (raw.containsKey("metrics")) mutableListOf() else null
            created = nowMillis
        } else {
            require(state["version"] == 1 && state["totalSets"] == total)
            require(json(state["metadata"]) == json(metadata))
            @Suppress("UNCHECKED_CAST")
            sets = (state["sets"] as? List<Any?>)?.toMutableList() ?: error("Sets")
            @Suppress("UNCHECKED_CAST")
            intervals = (state["intervals"] as? List<Any?>)?.toMutableList()
            @Suppress("UNCHECKED_CAST")
            metrics = (state["metrics"] as? List<Any?>)?.toMutableList()
            require(sets.size <= total && (intervals == null || intervals.size == sets.size) &&
                (metrics == null || metrics.size == sets.size))
            require((intervals != null) == raw.containsKey("interval") &&
                (metrics != null) == raw.containsKey("metrics"))
            created = (state["createdAt"] as Number).toLong()
        }
        require(offset <= sets.size)
        if (!free) {
            if (offset == sets.size) {
                sets.add(row)
                intervals?.add(raw["interval"])
                metrics?.add(raw["metrics"])
            } else {
                require(json(sets[offset]) == json(row))
                require(intervals == null || json(intervals[offset]) == json(raw["interval"]))
                require(metrics == null || json(metrics[offset]) == json(raw["metrics"]))
            }
        }
        // Stored state is untrusted too. Validate the entire retained prefix before
        // acknowledging any of it, including after process restart.
        if (sets.isNotEmpty()) {
            val prefix = metadata.toMutableMap()
            prefix.remove("plannedSetCount")
            prefix.remove("plannedTargetSetCount")
            prefix.remove("completedPlannedSetCount")
            prefix["sets"] = sets
            if (intervals != null) prefix["setIntervals"] = intervals
            if (metrics != null) prefix["setMetrics"] = metrics
            require(parseGarminWorkoutCommand(prefix, nowMillis) != null)
        }
        val next = linkedMapOf<String, Any>(
            "version" to 1, "createdAt" to created, "totalSets" to total,
            "metadata" to metadata, "sets" to sets
        )
        if (intervals != null) next["intervals"] = intervals
        if (metrics != null) next["metrics"] = metrics
        val encoded = json(next)
        require(encoded.toByteArray(Charsets.UTF_8).size <= MAX_STATE_BYTES)
        val complete = if (sets.size == total) {
            val message = metadata.toMutableMap()
            message["sets"] = sets
            if (intervals != null) message["setIntervals"] = intervals
            if (metrics != null) message["setMetrics"] = metrics
            require(parseGarminWorkoutCommand(message, nowMillis) != null)
            message
        } else null
        GarminTransferStep(encoded, sets.size, attemptId, complete)
    }.getOrNull()

    private fun integer(value: Any?, minimum: Int, maximum: Int): Int {
        require(value is Number)
        val number = value.toDouble()
        require(number.isFinite() && number % 1.0 == 0.0 && number in minimum.toDouble()..maximum.toDouble())
        return number.toInt()
    }

    private fun bounded(value: Any?, depth: Int): Boolean {
        if (depth > 4) return false
        return when (value) {
            null, JSONObject.NULL -> true
            is String -> value.length <= 640 && value.toByteArray(Charsets.UTF_8).size <= 640
            is Boolean -> true
            is Number -> value.toDouble().isFinite()
            is List<*> -> value.size <= 60 && value.all { bounded(it, depth + 1) }
            is Map<*, *> -> value.size <= 20 && value.all { (key, item) ->
                key is String && key.length <= 32 && bounded(item, depth + 1)
            }
            else -> false
        }
    }

    private fun json(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is Map<*, *> -> value.keys.map { it as String }.sorted().joinToString(",", "{", "}") {
            JSONObject.quote(it) + ":" + json(value[it])
        }
        is List<*> -> value.joinToString(",", "[", "]") { json(it) }
        is String -> JSONObject.quote(value)
        is Number -> JSONObject.numberToString(value)
        is Boolean -> value.toString()
        else -> error("JSON type")
    }

    private fun decode(text: String): Map<String, Any?> {
        require(text.length <= MAX_STATE_BYTES && text.toByteArray(Charsets.UTF_8).size <= MAX_STATE_BYTES)
        // Validate nesting before the platform JSON parser allocates nested state.
        var depth = 0
        var quoted = false
        var escaped = false
        text.forEach { c ->
            if (quoted) {
                if (escaped) escaped = false else if (c == '\\') escaped = true else if (c == '"') quoted = false
            } else when (c) {
                '"' -> quoted = true
                '[', '{' -> { depth++; require(depth <= 5) }
                ']', '}' -> { depth--; require(depth >= 0) }
            }
        }
        require(depth == 0 && !quoted)
        fun unpack(value: Any?): Any? = when (value) {
            JSONObject.NULL, null -> null
            is JSONObject -> value.keys().asSequence().associateWith { unpack(value.get(it)) }
            is JSONArray -> List(value.length()) { unpack(value.get(it)) }
            else -> value
        }
        @Suppress("UNCHECKED_CAST")
        return unpack(JSONObject(text)) as Map<String, Any?>
    }
}
