package com.example.gymapp.wearsync

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.AppLanguage
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import java.util.UUID
import kotlin.math.floor
import org.json.JSONArray
import org.json.JSONObject

internal object PhoneWearPaths {
    const val PROTOCOL_VERSION = 1
    const val MAX_MESSAGE_BYTES = 100 * 1024
    const val MAX_WORKOUT_SETS = 100
    const val MAX_SYNC_SESSIONS = 500
    const val MAX_SYNC_TOTAL_SETS = 5_000
    const val MAX_EXERCISE_CATALOG = 1_000
    const val MAX_EXERCISE_NAME_LENGTH = 120
    const val MAX_NOTE_LENGTH = 2_000
    const val MAX_REPS = 10_000
    const val MAX_WEIGHT = 1_000_000.0
    const val MAX_PROTOCOL_COUNTER = 9_007_199_254_740_991L

    const val REQUEST_FULL_SYNC = "/gym/sync/request_full"
    const val CREATE_WORKOUT = "/gym/sync/create_workout"
    const val UPDATE_SET = "/gym/sync/update_set"
    const val DELETE_SET = "/gym/sync/delete_set"
    const val MUTATION_ACK = "/gym/sync/mutation_ack"
    const val PUSH_WORKOUT_PLAN = "/gym/sync/push_workout_plan"
    const val MAX_PLAN_SETS = 60
    const val PLAN_LIFETIME_MS = 14L * 24 * 60 * 60 * 1_000
    const val FULL_SYNC_PAYLOAD = "/gym/sync/full_payload"
    /** Phone -> watch: signed out ("unbound") or unlinked by the user ("unlinked"). No owner id. */
    const val BINDING_STATE = "/gym/sync/binding_state"

    /**
     * Capability the watch app declares (its res/values/wear.xml). The manifest filter of
     * PhoneWearSyncListenerService names the same value; a change resends what waits for the watch.
     */
    const val WATCH_CAPABILITY = "gymapp_watch_sync"

    val inboundPaths = setOf(REQUEST_FULL_SYNC, CREATE_WORKOUT, UPDATE_SET, DELETE_SET)
}

internal data class PhoneWearCommandEnvelope(
    val operationId: String,
    val sentAt: Long,
    val ownerId: String?,
    val accountGeneration: Long?
)

internal sealed interface PhoneWearCommand {
    val envelope: PhoneWearCommandEnvelope

    data class RequestFull(
        override val envelope: PhoneWearCommandEnvelope,
        /** The watch user tapped "Link to phone": may pin a watch that was unlinked here. */
        val linkIntent: Boolean = false
    ) : PhoneWearCommand

    data class CreateWorkout(
        override val envelope: PhoneWearCommandEnvelope,
        val startedAt: Long,
        val note: String?,
        val sets: List<PhoneWearNamedSet>,
        val durationSeconds: Long? = null,
        /** Optional (builds that predate heart rate omit them); 25..240, max >= avg when both. */
        val averageHeartRate: Int? = null,
        val maxHeartRate: Int? = null
    ) : PhoneWearCommand

    data class UpdateSet(
        override val envelope: PhoneWearCommandEnvelope,
        val setId: Long,
        val weight: Double,
        val reps: Int
    ) : PhoneWearCommand

    data class DeleteSet(
        override val envelope: PhoneWearCommandEnvelope,
        val setId: Long
    ) : PhoneWearCommand
}

internal data class PhoneWearNamedSet(
    val exerciseName: String,
    val weight: Double,
    val reps: Int
)

internal data class PhoneWearOutboundSet(
    val id: Long,
    val sessionId: Long,
    val exerciseName: String,
    val weight: Double,
    val reps: Int,
    val orderIndex: Int
)

internal data class PhoneWearOutboundSession(
    val id: Long,
    val startedAt: Long,
    val note: String?,
    val sets: List<PhoneWearOutboundSet>
)

internal sealed interface PhoneWearParseResult {
    data class Valid(val command: PhoneWearCommand, val canonicalPayloadDigest: String) : PhoneWearParseResult
    data class Invalid(val reason: String) : PhoneWearParseResult
}

/**
 * Strict, bounded wire-format boundary for messages received from Wear OS.
 *
 * The watch is not an authority for account identity. Parsed owner/generation values are only
 * claims which the listener compares with a binding derived from the phone's active session.
 */
/** Plain-text view of the user's training profile, as the watch shows it (no raw account data). */
internal data class PhoneWearPlanProfile(
    val split: String,
    val workoutsPerWeek: Int,
    val goal: String,
    val calorieMode: String
)

internal object PhoneWearProtocol {
    private const val MIN_TIMESTAMP_MS = 946_684_800_000L // 2000-01-01
    private const val MAX_CLOCK_SKEW_MS = 5 * 60 * 1_000L
    private const val MAX_MESSAGE_AGE_MS = 7L * 24 * 60 * 60 * 1_000
    private const val MAX_WORKOUT_DURATION_SECONDS = 86_400L
    private const val MIN_HEART_RATE = 25
    private const val MAX_HEART_RATE = 240
    private const val MAX_IDENTIFIER_LENGTH = 128
    private const val MAX_JSON_NESTING = 32
    private const val MAX_JSON_STRING_BYTES = 64 * 1024
    private val ownerIdPattern = Regex("^[0-9a-f]{64}$")
    private val operationIdPattern = Regex(
        "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    )

    fun parse(
        path: String,
        payload: ByteArray,
        now: Long = System.currentTimeMillis()
    ): PhoneWearParseResult {
        return try {
            require(path in PhoneWearPaths.inboundPaths) { "Unsupported sync path" }
            require(payload.isNotEmpty() && payload.size <= PhoneWearPaths.MAX_MESSAGE_BYTES) {
                "Sync payload has an invalid size"
            }
            val raw = decodeStrictUtf8(payload)
            BoundedJsonPreflight(
                raw = raw,
                maxDepth = MAX_JSON_NESTING,
                maxStringBytes = MAX_JSON_STRING_BYTES
            ).validate()
            val root = JSONObject(raw)
            val command = when (path) {
                PhoneWearPaths.REQUEST_FULL_SYNC -> parseFullSyncRequest(root, now)
                PhoneWearPaths.CREATE_WORKOUT -> parseCreateWorkout(root, now)
                PhoneWearPaths.UPDATE_SET -> parseUpdateSet(root, now)
                PhoneWearPaths.DELETE_SET -> parseDeleteSet(root, now)
                else -> error("Unsupported sync path")
            }
            PhoneWearParseResult.Valid(
                command = command,
                canonicalPayloadDigest = canonicalCommandDigest(path, command)
            )
        } catch (error: Exception) {
            PhoneWearParseResult.Invalid(error.message ?: "Invalid sync payload")
        }
    }

    /**
     * Builds the phone-to-watch workout plan message. Names stay real Unicode (the watch has no
     * Latin-only constraint, unlike Connect IQ). Invalid plans throw instead of being truncated;
     * only the optional exercise picker catalog is trimmed to the largest prefix that fits.
     */
    fun buildWorkoutPlan(
        binding: PhoneWearAccountBinding,
        revision: Long,
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>,
        profile: PhoneWearPlanProfile?,
        planSource: String,
        now: Long = System.currentTimeMillis(),
        messageId: String = UUID.randomUUID().toString()
    ): ByteArray {
        requireValidBinding(binding)
        require(!binding.signedOut) { "Signed-out accounts have no plan" }
        require(revision in 1L..PhoneWearPaths.MAX_PROTOCOL_COUNTER)
        requireValidOperationId(messageId)
        require(sets.size in 1..PhoneWearPaths.MAX_PLAN_SETS) { "Invalid plan set count" }
        require(planSource.length in 1..32 && planSource.none(Char::isISOControl))
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
        val seenNames = hashSetOf<String>()
        val encodedCatalog = exerciseCatalog.asSequence()
            .map(String::trim)
            .filter(::isValidExerciseName)
            .filter { seenNames.add(it.lowercase()) }
            .take(PhoneWearPaths.MAX_EXERCISE_CATALOG)
            .toList()
        val profileJson = profile?.let {
            require(it.workoutsPerWeek in 1..14)
            JSONObject()
                .put("split", it.split.take(64))
                .put("workoutsPerWeek", it.workoutsPerWeek)
                .put("goal", it.goal.take(64))
                .put("calorieMode", it.calorieMode.take(64))
        }

        fun buildRoot(catalogCount: Int): JSONObject {
            val root = JSONObject()
                .put("protocolVersion", PhoneWearPaths.PROTOCOL_VERSION)
                .put("ownerId", binding.ownerId)
                .put("accountGeneration", binding.accountGeneration)
                .put("authorityEpoch", binding.authorityEpoch)
                .put("revision", revision)
                .put("messageId", messageId)
                .put("sentAt", now)
                .put("expiresAt", now + PhoneWearPaths.PLAN_LIFETIME_MS)
                .put("planSource", planSource)
                .put("sets", setsJson)
                .put("exerciseCatalog", JSONArray(encodedCatalog.take(catalogCount)))
            if (profileJson != null) root.put("trainingProfile", profileJson)
            return root
        }

        var low = 0
        var high = encodedCatalog.size
        while (low < high) {
            val candidate = (low + high + 1) / 2
            val size = buildRoot(candidate).toString().toByteArray(Charsets.UTF_8).size
            if (size <= PhoneWearPaths.MAX_MESSAGE_BYTES) low = candidate else high = candidate - 1
        }
        return encodeBounded(buildRoot(low))
    }

    fun buildMutationAck(
        binding: PhoneWearAccountBinding,
        operationId: String,
        accepted: Boolean,
        now: Long = System.currentTimeMillis()
    ): ByteArray {
        requireValidBinding(binding)
        requireValidOperationId(operationId)
        val root = JSONObject()
            .put("protocolVersion", PhoneWearPaths.PROTOCOL_VERSION)
            .put("ownerId", binding.ownerId)
            .put("accountGeneration", binding.accountGeneration)
            .put("authorityEpoch", binding.authorityEpoch)
            .put("operationId", operationId)
            .put("status", if (accepted) "accepted" else "rejected")
            .put("sentAt", now)
        return encodeBounded(root)
    }

    /**
     * Tells the pinned watch that this phone has no account for it right now. "unbound": signed
     * out; the watch drops plan, history and catalog and keeps its own unsent work on hold.
     * "unlinked": the user unlinked the watch; it also forgets this phone. The message carries no
     * owner id on purpose: a signed-out phone has no account to name.
     */
    fun buildBindingState(
        binding: PhoneWearAccountBinding,
        unlinked: Boolean,
        now: Long = System.currentTimeMillis(),
        messageId: String = UUID.randomUUID().toString()
    ): ByteArray {
        requireValidBinding(binding)
        requireValidOperationId(messageId)
        val root = JSONObject()
            .put("protocolVersion", PhoneWearPaths.PROTOCOL_VERSION)
            .put("state", if (unlinked) "unlinked" else "unbound")
            .put("authorityEpoch", binding.authorityEpoch)
            .put("accountGeneration", binding.accountGeneration)
            .put("messageId", messageId)
            .put("sentAt", now)
        return encodeBounded(root)
    }

    /**
     * Builds the largest deterministic prefix that remains valid for the watch protocol. Invalid
     * local rows are omitted as whole sessions; values are never truncated or reinterpreted.
     */
    fun buildBoundedFullSync(
        binding: PhoneWearAccountBinding,
        revision: Long,
        sessions: List<PhoneWearOutboundSession>,
        exerciseCatalog: List<String>,
        now: Long = System.currentTimeMillis(),
        messageId: String = UUID.randomUUID().toString()
    ): ByteArray {
        requireValidBinding(binding)
        require(revision in 1L..PhoneWearPaths.MAX_PROTOCOL_COUNTER)
        requireValidOperationId(messageId)

        val seenSessionIds = hashSetOf<Long>()
        val seenSetIds = hashSetOf<Long>()
        var totalSets = 0
        val encodedSessions = buildList {
            sessions.asSequence()
                .take(PhoneWearPaths.MAX_SYNC_SESSIONS)
                .forEach { session ->
                val encoded = encodeSessionOrNull(session, now, seenSessionIds, seenSetIds)
                    ?: return@forEach
                if (totalSets + session.sets.size > PhoneWearPaths.MAX_SYNC_TOTAL_SETS) {
                    return@forEach
                }
                add(encoded)
                totalSets += session.sets.size
            }
        }

        val seenNames = hashSetOf<String>()
        val encodedCatalog = exerciseCatalog.asSequence()
            .map(String::trim)
            .filter(::isValidExerciseName)
            .filter { seenNames.add(it.lowercase()) }
            .take(PhoneWearPaths.MAX_EXERCISE_CATALOG)
            .toList()

        fun buildRoot(sessionCount: Int, catalogCount: Int): JSONObject {
            return JSONObject()
                .put("protocolVersion", PhoneWearPaths.PROTOCOL_VERSION)
                .put("ownerId", binding.ownerId)
                .put("accountGeneration", binding.accountGeneration)
                .put("authorityEpoch", binding.authorityEpoch)
                .put("revision", revision)
                .put("messageId", messageId)
                .put("sentAt", now)
                .put("sessions", JSONArray(encodedSessions.take(sessionCount)))
                .put("exerciseCatalog", JSONArray(encodedCatalog.take(catalogCount)))
        }

        fun largestFittingPrefix(maximum: Int, rootForCount: (Int) -> JSONObject): Int {
            var low = 0
            var high = maximum
            while (low < high) {
                val candidate = (low + high + 1) / 2
                val size = rootForCount(candidate).toString().toByteArray(Charsets.UTF_8).size
                if (size <= PhoneWearPaths.MAX_MESSAGE_BYTES) low = candidate else high = candidate - 1
            }
            return low
        }

        val sessionCount = largestFittingPrefix(encodedSessions.size) { count ->
            buildRoot(sessionCount = count, catalogCount = 0)
        }
        val catalogCount = largestFittingPrefix(encodedCatalog.size) { count ->
            buildRoot(sessionCount = sessionCount, catalogCount = count)
        }

        return encodeBounded(buildRoot(sessionCount, catalogCount))
    }

    private fun parseFullSyncRequest(root: JSONObject, now: Long): PhoneWearCommand.RequestFull {
        val required = setOf("type", "protocolVersion", "operationId", "sentAt")
        val optional = setOf("ownerId", "accountGeneration", "link")
        root.requireKnownKeys(required, optional)
        require(root.requiredString("type", 32) == "request_full_sync")
        requireProtocolVersion(root)
        val ownerPresent = root.has("ownerId")
        val generationPresent = root.has("accountGeneration")
        require(ownerPresent == generationPresent) { "Incomplete account binding" }
        val ownerId = if (ownerPresent) root.requiredOwnerId("ownerId") else null
        val generation = if (generationPresent) root.requiredProtocolCounter("accountGeneration") else null
        return PhoneWearCommand.RequestFull(
            PhoneWearCommandEnvelope(
                operationId = root.requiredOperationId("operationId"),
                sentAt = root.requiredFreshTimestamp("sentAt", now),
                ownerId = ownerId,
                accountGeneration = generation
            ),
            linkIntent = if (root.has("link")) {
                val value = root.get("link")
                require(value is Boolean) { "link must be a boolean" }
                value
            } else {
                false
            }
        )
    }

    private fun parseCreateWorkout(root: JSONObject, now: Long): PhoneWearCommand.CreateWorkout {
        val required = setOf(
            "type", "protocolVersion", "operationId", "sentAt", "ownerId",
            "accountGeneration", "startedAt", "sets"
        )
        root.requireKnownKeys(required, optional = setOf("note", "durationSeconds", "avgHeartRate", "maxHeartRate"))
        require(root.requiredString("type", 32) == "create_workout")
        val envelope = root.requiredBoundMutationEnvelope(now)
        val startedAt = root.requiredLong("startedAt")
        require(startedAt in MIN_TIMESTAMP_MS..(now + MAX_CLOCK_SKEW_MS)) {
            "Invalid workout timestamp"
        }
        val note = root.optionalBoundedNote("note")
        // Optional so builds that predate the field keep working.
        val durationSeconds = if (root.has("durationSeconds")) {
            root.requiredLong("durationSeconds").also {
                require(it in 0L..MAX_WORKOUT_DURATION_SECONDS) { "Invalid workout duration" }
            }
        } else {
            null
        }
        val averageHeartRate = root.optionalHeartRate("avgHeartRate")
        val maxHeartRate = root.optionalHeartRate("maxHeartRate")
        require(averageHeartRate == null || maxHeartRate == null || maxHeartRate >= averageHeartRate) {
            "Average heart rate exceeds the maximum"
        }
        val array = root.requiredArray("sets")
        require(array.length() in 1..PhoneWearPaths.MAX_WORKOUT_SETS) { "Invalid set count" }
        val sets = buildList(array.length()) {
            for (index in 0 until array.length()) {
                val item = array.requiredObject(index)
                item.requireKnownKeys(setOf("exerciseName", "weight", "reps"))
                val name = item.requiredString(
                    "exerciseName",
                    PhoneWearPaths.MAX_EXERCISE_NAME_LENGTH
                ).trim()
                val weight = item.requiredFiniteDouble("weight")
                val reps = item.requiredInt("reps")
                requireValidSet(name, weight, reps)
                add(PhoneWearNamedSet(name, weight, reps))
            }
        }
        return PhoneWearCommand.CreateWorkout(
            envelope, startedAt, note, sets, durationSeconds, averageHeartRate, maxHeartRate
        )
    }

    private fun parseUpdateSet(root: JSONObject, now: Long): PhoneWearCommand.UpdateSet {
        root.requireKnownKeys(
            setOf(
                "type", "protocolVersion", "operationId", "sentAt", "ownerId",
                "accountGeneration", "setId", "weight", "reps"
            )
        )
        require(root.requiredString("type", 32) == "update_set")
        val setId = root.requiredProtocolCounter("setId")
        val weight = root.requiredFiniteDouble("weight")
        val reps = root.requiredInt("reps")
        requireValidWeightAndReps(weight, reps)
        return PhoneWearCommand.UpdateSet(root.requiredBoundMutationEnvelope(now), setId, weight, reps)
    }

    private fun parseDeleteSet(root: JSONObject, now: Long): PhoneWearCommand.DeleteSet {
        root.requireKnownKeys(
            setOf(
                "type", "protocolVersion", "operationId", "sentAt", "ownerId",
                "accountGeneration", "setId"
            )
        )
        require(root.requiredString("type", 32) == "delete_set")
        return PhoneWearCommand.DeleteSet(
            envelope = root.requiredBoundMutationEnvelope(now),
            setId = root.requiredProtocolCounter("setId")
        )
    }

    private fun JSONObject.requiredBoundMutationEnvelope(now: Long): PhoneWearCommandEnvelope {
        requireProtocolVersion(this)
        return PhoneWearCommandEnvelope(
            operationId = requiredOperationId("operationId"),
            sentAt = requiredFreshTimestamp("sentAt", now),
            ownerId = requiredOwnerId("ownerId"),
            accountGeneration = requiredProtocolCounter("accountGeneration")
        )
    }

    private fun requireProtocolVersion(root: JSONObject) {
        require(root.requiredInt("protocolVersion") == PhoneWearPaths.PROTOCOL_VERSION) {
            "Unsupported protocol version"
        }
    }

    private fun encodeSessionOrNull(
        session: PhoneWearOutboundSession,
        now: Long,
        seenSessionIds: MutableSet<Long>,
        seenSetIds: MutableSet<Long>
    ): JSONObject? {
        if (
            session.id !in 1L..PhoneWearPaths.MAX_PROTOCOL_COUNTER ||
            !seenSessionIds.add(session.id) ||
            session.startedAt !in MIN_TIMESTAMP_MS..(now + MAX_CLOCK_SKEW_MS) ||
            !isValidNote(session.note) ||
            session.sets.size !in 1..PhoneWearPaths.MAX_WORKOUT_SETS
        ) {
            return null
        }
        val localSetIds = hashSetOf<Long>()
        val sets = JSONArray()
        session.sets.forEachIndexed { index, set ->
            if (
                set.id !in 1L..PhoneWearPaths.MAX_PROTOCOL_COUNTER ||
                set.sessionId != session.id ||
                !localSetIds.add(set.id) ||
                !isValidExerciseName(set.exerciseName) ||
                !isValidWeightAndReps(set.weight, set.reps)
            ) {
                seenSessionIds.remove(session.id)
                return null
            }
            sets.put(
                JSONObject()
                    .put("id", set.id)
                    .put("sessionId", session.id)
                    .put("exerciseName", set.exerciseName.trim())
                    .put("weight", set.weight)
                    .put("reps", set.reps)
                    .put("orderIndex", index)
            )
        }
        if (localSetIds.any { it in seenSetIds }) {
            seenSessionIds.remove(session.id)
            return null
        }
        seenSetIds += localSetIds
        return JSONObject()
            .put("id", session.id)
            .put("startedAt", session.startedAt)
            .put("note", session.note ?: JSONObject.NULL)
            .put("sets", sets)
    }

    private fun requireValidBinding(binding: PhoneWearAccountBinding) {
        require(ownerIdPattern.matches(binding.ownerId))
        require(binding.accountGeneration in 1L..PhoneWearPaths.MAX_PROTOCOL_COUNTER)
        require(authorityEpochPattern.matches(binding.authorityEpoch)) { "Invalid authority epoch" }
    }

    private val authorityEpochPattern =
        Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
    private const val MAX_OBJECT_KEYS = 32
    private const val MAX_KEY_LENGTH = 64

    private fun requireValidOperationId(value: String) {
        require(value.length <= MAX_IDENTIFIER_LENGTH && operationIdPattern.matches(value)) {
            "Invalid operation identifier"
        }
    }

    private fun JSONObject.requiredOperationId(key: String): String {
        return requiredString(key, MAX_IDENTIFIER_LENGTH).also(::requireValidOperationId)
    }

    private fun JSONObject.requiredOwnerId(key: String): String {
        return requiredString(key, 64).also {
            require(ownerIdPattern.matches(it)) { "Invalid account owner" }
        }
    }

    private fun JSONObject.requiredProtocolCounter(key: String): Long {
        return requiredLong(key).also {
            require(it in 1L..PhoneWearPaths.MAX_PROTOCOL_COUNTER) { "$key is out of range" }
        }
    }

    private fun JSONObject.requiredFreshTimestamp(key: String, now: Long): Long {
        return requiredLong(key).also {
            require(it in (now - MAX_MESSAGE_AGE_MS)..(now + MAX_CLOCK_SKEW_MS)) {
                "Stale sync message"
            }
        }
    }

    private fun JSONObject.optionalBoundedNote(key: String): String? {
        if (!has(key) || isNull(key)) return null
        val value = requiredString(key, PhoneWearPaths.MAX_NOTE_LENGTH)
        require(isValidNote(value)) { "Invalid workout note" }
        return value.trim().ifBlank { null }
    }

    private fun requireValidSet(name: String, weight: Double, reps: Int) {
        require(isValidExerciseName(name)) { "Invalid exercise name" }
        requireValidWeightAndReps(weight, reps)
    }

    private fun requireValidWeightAndReps(weight: Double, reps: Int) {
        require(isValidWeightAndReps(weight, reps)) { "Invalid set values" }
    }

    private fun isValidWeightAndReps(weight: Double, reps: Int): Boolean {
        return weight.isFinite() && weight in 0.0..PhoneWearPaths.MAX_WEIGHT &&
            reps in 1..PhoneWearPaths.MAX_REPS
    }

    private fun isValidExerciseName(value: String): Boolean {
        val trimmed = value.trim()
        return trimmed.isNotEmpty() &&
            trimmed.length <= PhoneWearPaths.MAX_EXERCISE_NAME_LENGTH &&
            trimmed.toByteArray(Charsets.UTF_8).size <= PhoneWearPaths.MAX_EXERCISE_NAME_LENGTH * 4 &&
            trimmed.none(Char::isISOControl)
    }

    private fun JSONObject.optionalHeartRate(key: String): Int? {
        if (!has(key)) return null
        return requiredInt(key).also {
            require(it in MIN_HEART_RATE..MAX_HEART_RATE) { "Invalid heart rate" }
        }
    }

    private fun isValidNote(value: String?): Boolean {
        if (value == null) return true
        return value.length <= PhoneWearPaths.MAX_NOTE_LENGTH && value.all { character ->
            !character.isISOControl() || character == '\n' || character == '\r' || character == '\t'
        }
    }

    private fun JSONObject.requireKnownKeys(
        required: Set<String>,
        optional: Set<String> = emptySet()
    ) {
        // Unknown keys are ignored, not rejected: a watch build that adds an optional field must
        // not have its workout silently dropped. The payload stays untrusted input: the object is
        // bounded in key count and key length (bytes, depth and strings are bounded before this),
        // every required key must be present, and only keys named in [required]/[optional] are
        // ever read. The command digest is computed from the parsed values, never the raw text.
        val actual = keys().asSequence().toSet()
        require(actual.size <= maxOf(MAX_OBJECT_KEYS, required.size + optional.size)) {
            "Too many JSON fields"
        }
        require(actual.all { it.length <= MAX_KEY_LENGTH }) { "JSON field name is too long" }
        require(actual.containsAll(required)) { "Missing JSON field" }
    }

    private fun JSONObject.requiredArray(key: String): JSONArray {
        val value = get(key)
        require(value is JSONArray) { "$key must be an array" }
        return value
    }

    private fun JSONObject.requiredString(key: String, maxLength: Int): String {
        val value = get(key)
        require(value is String && value.length <= maxLength) { "$key must be a bounded string" }
        return value
    }

    private fun JSONObject.requiredLong(key: String): Long {
        val value = get(key)
        require(value is Number) { "$key must be a number" }
        val doubleValue = value.toDouble()
        require(doubleValue.isFinite() && floor(doubleValue) == doubleValue) { "$key must be an integer" }
        val result = value.toLong()
        require(result.toDouble() == doubleValue) { "$key is out of range" }
        return result
    }

    private fun JSONObject.requiredInt(key: String): Int {
        val value = requiredLong(key)
        require(value in Int.MIN_VALUE..Int.MAX_VALUE) { "$key is out of range" }
        return value.toInt()
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

    private fun encodeBounded(root: JSONObject): ByteArray {
        return root.toString().toByteArray(Charsets.UTF_8).also {
            require(it.size <= PhoneWearPaths.MAX_MESSAGE_BYTES) { "Sync payload is too large" }
        }
    }

    private fun decodeStrictUtf8(payload: ByteArray): String {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return decoder.decode(ByteBuffer.wrap(payload)).toString()
    }

    private fun canonicalCommandDigest(path: String, command: PhoneWearCommand): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val number = ByteBuffer.allocate(Long.SIZE_BYTES)

        fun addLong(value: Long) {
            number.clear()
            number.putLong(value)
            digest.update(number.array())
        }

        fun addString(value: String?) {
            if (value == null) {
                digest.update(0.toByte())
                return
            }
            digest.update(1.toByte())
            val bytes = value.toByteArray(Charsets.UTF_8)
            addLong(bytes.size.toLong())
            digest.update(bytes)
        }

        val envelope = command.envelope
        addString("GymAppPhoneWearCommandV1")
        addString(path)
        addString(envelope.ownerId)
        // The account generation is deliberately NOT part of the digest: after a same-owner
        // re-login the watch re-stamps an unacknowledged create with the new generation, and the
        // same operation id must still be recognised as the identical, already-applied command.
        addString(envelope.operationId)
        when (command) {
            is PhoneWearCommand.RequestFull -> addString("request_full_sync")
            is PhoneWearCommand.CreateWorkout -> {
                addString("create_workout")
                addLong(command.startedAt)
                addString(command.note)
                command.durationSeconds?.let { addString("duration"); addLong(it) }
                // Only present when the watch sent them, so a digest from an older build stays valid.
                command.averageHeartRate?.let { addString("avgHeartRate"); addLong(it.toLong()) }
                command.maxHeartRate?.let { addString("maxHeartRate"); addLong(it.toLong()) }
                addLong(command.sets.size.toLong())
                command.sets.forEach { set ->
                    addString(set.exerciseName)
                    val stableWeight = if (set.weight == 0.0) 0.0 else set.weight
                    addLong(java.lang.Double.doubleToLongBits(stableWeight))
                    addLong(set.reps.toLong())
                }
            }
            is PhoneWearCommand.UpdateSet -> {
                addString("update_set")
                addLong(command.setId)
                val stableWeight = if (command.weight == 0.0) 0.0 else command.weight
                addLong(java.lang.Double.doubleToLongBits(stableWeight))
                addLong(command.reps.toLong())
            }
            is PhoneWearCommand.DeleteSet -> {
                addString("delete_set")
                addLong(command.setId)
            }
        }
        return digest.digest().joinToString(separator = "") { byte -> "%02x".format(byte) }
    }

    /** Small recursive preflight that rejects duplicate keys and resource-heavy JSON before DOM parsing. */
    private class BoundedJsonPreflight(
        private val raw: String,
        private val maxDepth: Int,
        private val maxStringBytes: Int
    ) {
        private var index = 0

        fun validate() {
            skipWhitespace()
            parseValue(depth = 0)
            skipWhitespace()
            require(index == raw.length) { "Trailing JSON content" }
        }

        private fun parseValue(depth: Int) {
            require(index < raw.length) { "Unexpected end of JSON" }
            when (raw[index]) {
                '{' -> parseObject(depth + 1)
                '[' -> parseArray(depth + 1)
                '"' -> parseString()
                't' -> consumeLiteral("true")
                'f' -> consumeLiteral("false")
                'n' -> consumeLiteral("null")
                '-', in '0'..'9' -> parseNumber()
                else -> error("Invalid JSON value")
            }
        }

        private fun parseObject(depth: Int) {
            require(depth <= maxDepth) { "JSON nesting is too deep" }
            index += 1
            skipWhitespace()
            if (consumeIf('}')) return
            val keys = hashSetOf<String>()
            while (true) {
                require(index < raw.length && raw[index] == '"') { "Object key must be a string" }
                val key = parseString()
                require(keys.add(key)) { "Duplicate JSON field" }
                skipWhitespace()
                require(consumeIf(':')) { "Missing object separator" }
                skipWhitespace()
                parseValue(depth)
                skipWhitespace()
                if (consumeIf('}')) return
                require(consumeIf(',')) { "Missing object delimiter" }
                skipWhitespace()
            }
        }

        private fun parseArray(depth: Int) {
            require(depth <= maxDepth) { "JSON nesting is too deep" }
            index += 1
            skipWhitespace()
            if (consumeIf(']')) return
            while (true) {
                parseValue(depth)
                skipWhitespace()
                if (consumeIf(']')) return
                require(consumeIf(',')) { "Missing array delimiter" }
                skipWhitespace()
            }
        }

        private fun parseString(): String {
            require(consumeIf('"')) { "Expected JSON string" }
            val decoded = StringBuilder()
            while (index < raw.length) {
                val character = raw[index++]
                when {
                    character == '"' -> {
                        val value = decoded.toString()
                        require(value.toByteArray(Charsets.UTF_8).size <= maxStringBytes) {
                            "JSON string is too large"
                        }
                        require(hasValidSurrogates(value)) { "Invalid Unicode surrogate" }
                        return value
                    }
                    character == '\\' -> decoded.append(parseEscape())
                    character.code < 0x20 -> error("Unescaped control character")
                    else -> decoded.append(character)
                }
                require(decoded.length <= maxStringBytes) { "JSON string is too large" }
            }
            error("Unterminated JSON string")
        }

        private fun parseEscape(): Char {
            require(index < raw.length) { "Invalid JSON escape" }
            return when (val escaped = raw[index++]) {
                '"', '\\', '/' -> escaped
                'b' -> '\b'
                'f' -> '\u000C'
                'n' -> '\n'
                'r' -> '\r'
                't' -> '\t'
                'u' -> {
                    require(index + 4 <= raw.length) { "Invalid Unicode escape" }
                    val hex = raw.substring(index, index + 4)
                    require(hex.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
                        "Invalid Unicode escape"
                    }
                    index += 4
                    hex.toInt(16).toChar()
                }
                else -> error("Invalid JSON escape")
            }
        }

        private fun parseNumber() {
            if (consumeIf('-')) require(index < raw.length) { "Invalid JSON number" }
            if (consumeIf('0')) {
                require(index >= raw.length || raw[index] !in '0'..'9') { "Invalid leading zero" }
            } else {
                require(index < raw.length && raw[index] in '1'..'9') { "Invalid JSON number" }
                while (index < raw.length && raw[index] in '0'..'9') index += 1
            }
            if (consumeIf('.')) {
                require(index < raw.length && raw[index] in '0'..'9') { "Invalid fraction" }
                while (index < raw.length && raw[index] in '0'..'9') index += 1
            }
            if (index < raw.length && raw[index].lowercaseChar() == 'e') {
                index += 1
                if (index < raw.length && (raw[index] == '+' || raw[index] == '-')) index += 1
                require(index < raw.length && raw[index] in '0'..'9') { "Invalid exponent" }
                while (index < raw.length && raw[index] in '0'..'9') index += 1
            }
        }

        private fun consumeLiteral(value: String) {
            require(raw.regionMatches(index, value, 0, value.length)) { "Invalid JSON literal" }
            index += value.length
        }

        private fun skipWhitespace() {
            while (index < raw.length && raw[index] in setOf(' ', '\n', '\r', '\t')) index += 1
        }

        private fun consumeIf(expected: Char): Boolean {
            if (index >= raw.length || raw[index] != expected) return false
            index += 1
            return true
        }

        private fun hasValidSurrogates(value: String): Boolean {
            var cursor = 0
            while (cursor < value.length) {
                val character = value[cursor]
                when {
                    character.isHighSurrogate() -> {
                        if (cursor + 1 >= value.length || !value[cursor + 1].isLowSurrogate()) return false
                        cursor += 2
                    }
                    character.isLowSurrogate() -> return false
                    else -> cursor += 1
                }
            }
            return true
        }
    }
}


/**
 * Note stored with a watch workout: the watch's own note (if any) plus the heart-rate summary,
 * worded like the Health import note segments ("Avg HR n", "Max HR n"; uk "Середній пульс n",
 * "Макс. пульс n") so the numbers stay
 * readable and parseable in the same way. Returns [watchNote] unchanged when there is no heart
 * rate or when the combined text would exceed the portable note bounds (512 code points,
 * 2048 UTF-8 bytes).
 */
internal fun wearWorkoutNote(
    watchNote: String?,
    averageHeartRate: Int?,
    maxHeartRate: Int?,
    language: AppLanguage
): String? {
    val details = mutableListOf<String>()
    averageHeartRate?.let {
        details += when (language) {
            AppLanguage.UK -> "Середній пульс $it"
            AppLanguage.RU -> "Средний пульс $it"
            else -> "Avg HR $it"
        }
    }
    maxHeartRate?.let {
        details += when (language) {
            AppLanguage.UK -> "Макс. пульс $it"
            AppLanguage.RU -> "Макс. пульс $it"
            else -> "Max HR $it"
        }
    }
    if (details.isEmpty()) return watchNote
    val combined = (listOfNotNull(watchNote?.takeIf { it.isNotBlank() }) + "Wear OS" + details)
        .joinToString(separator = " · ")
    val withinBounds = combined.codePointCount(0, combined.length) <= WEAR_NOTE_MAX_CODE_POINTS &&
        combined.toByteArray(Charsets.UTF_8).size <= WEAR_NOTE_MAX_BYTES
    return if (withinBounds && WorkoutDataLimits.isValidNote(combined)) combined else watchNote
}

private const val WEAR_NOTE_MAX_CODE_POINTS = 512
private const val WEAR_NOTE_MAX_BYTES = 2048
