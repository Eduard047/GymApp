package com.example.gymapp.garmin

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.data.repository.WorkoutDataLimits
import kotlinx.coroutines.channels.Channel
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

internal const val MAX_GARMIN_BINDING_LENGTH = 128
internal const val GARMIN_BINDING_VERSION = 2
internal const val MAX_GARMIN_REQUEST_ID_LENGTH = 128
internal const val MAX_GARMIN_SYNC_ID_LENGTH = 128
internal const val MAX_GARMIN_WORKOUT_SETS = 60
internal const val MAX_GARMIN_EXERCISE_NAME_LENGTH = 160
internal const val MAX_GARMIN_TOTAL_NAME_BYTES = 12_000
internal const val MAX_GARMIN_COMMAND_ENTRIES = 32
internal const val MAX_GARMIN_SET_ENTRIES = 8
internal const val MAX_GARMIN_EVENT_BATCH = 8
internal const val MAX_GARMIN_PENDING_WORK_COMMANDS = 16
internal const val MAX_GARMIN_PENDING_ACK_COMMANDS = 8
internal const val MAX_GARMIN_SYNC_REVISION = 9_007_199_254_740_991L
internal const val MAX_GARMIN_DURATION_SECONDS = 7 * 24 * 60 * 60L
internal const val MAX_GARMIN_CALORIES = 100_000.0
internal const val MAX_GARMIN_HEART_RATE = 300
internal const val MAX_GARMIN_HEART_RATE_ZONE = 5
internal const val MIN_GARMIN_STARTED_AT_SECONDS = 946_684_800L // 2000-01-01 UTC
internal const val MAX_GARMIN_FUTURE_SKEW_SECONDS = 24 * 60 * 60L

internal data class GarminBinding(
    val account: String,
    val device: String
)

internal enum class GarminInboundCommandKind {
    Work,
    Acknowledgement
}

internal data class GarminInboundCommandEnvelope(
    val kind: GarminInboundCommandKind,
    val command: Map<Any?, Any?>
)

internal enum class GarminBindingDecision {
    Bound,
    Rejected
}

internal data class GarminWorkoutCommand(
    val requestId: String,
    val startedAtMillis: Long,
    val sets: List<NamedWorkoutSetDraft>,
    val durationSeconds: Long?,
    val gymCalories: Double?,
    val garminCalories: Int?,
    val averageHeartRate: Int?,
    val maximumHeartRate: Int?,
    val heartRateZone: Int?
)

internal fun canonicalGarminWorkoutPayloadDigest(command: GarminWorkoutCommand): String {
    val digest = MessageDigest.getInstance("SHA-256")

    fun updateLong(value: Long) {
        digest.update(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(value).array())
    }

    fun updateInt(value: Int) = updateLong(value.toLong())

    fun updateString(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        updateInt(bytes.size)
        digest.update(bytes)
    }

    fun updateOptionalLong(value: Long?) {
        digest.update(if (value == null) 0.toByte() else 1.toByte())
        value?.let(::updateLong)
    }

    fun updateOptionalInt(value: Int?) = updateOptionalLong(value?.toLong())

    fun updateDouble(value: Double) {
        val canonical = if (value == 0.0) 0.0 else value
        updateLong(java.lang.Double.doubleToLongBits(canonical))
    }

    fun updateOptionalDouble(value: Double?) {
        digest.update(if (value == null) 0.toByte() else 1.toByte())
        value?.let(::updateDouble)
    }

    updateString("gymapp-garmin-workout/v1")
    updateString(command.requestId)
    updateLong(command.startedAtMillis)
    updateInt(command.sets.size)
    command.sets.forEach { set ->
        updateString(set.exerciseName)
        updateDouble(set.weight)
        updateInt(set.reps)
    }
    updateOptionalLong(command.durationSeconds)
    updateOptionalDouble(command.gymCalories)
    updateOptionalInt(command.garminCalories)
    updateOptionalInt(command.averageHeartRate)
    updateOptionalInt(command.maximumHeartRate)
    updateOptionalInt(command.heartRateZone)

    return digest.digest().joinToString(separator = "") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }
}

internal fun garminBindingDecision(
    command: Map<Any?, Any?>,
    expected: GarminBinding
): GarminBindingDecision {
    if (!hasCurrentGarminBindingVersion(command)) return GarminBindingDecision.Rejected
    val rawAccount = command["accountBinding"]
    val rawDevice = command["deviceBinding"]
    val account = rawAccount as? String
    val device = rawDevice as? String

    if (rawAccount != null && account == null) return GarminBindingDecision.Rejected
    if (rawDevice != null && device == null) return GarminBindingDecision.Rejected
    if (account == null || device == null) return GarminBindingDecision.Rejected
    if (device != expected.device) return GarminBindingDecision.Rejected
    if (!isValidGarminAccountBinding(account) || account != expected.account) {
        return GarminBindingDecision.Rejected
    }
    return GarminBindingDecision.Bound
}

internal fun hasCurrentGarminBindingVersion(command: Map<Any?, Any?>): Boolean {
    val rawVersion = command["bindingVersion"] as? Number ?: return false
    val version = rawVersion.toDouble()
    return version.isFinite() && version % 1.0 == 0.0 && version == GARMIN_BINDING_VERSION.toDouble()
}

internal fun boundGarminPayload(
    payload: Map<String, Any>,
    binding: GarminBinding
): Map<String, Any> = payload.toMutableMap().apply {
    put("bindingVersion", GARMIN_BINDING_VERSION)
    put("accountBinding", binding.account)
    put("deviceBinding", binding.device)
}

internal fun boundGarminSyncPayload(
    payload: Map<String, Any>,
    binding: GarminBinding,
    syncRevision: Long
): Map<String, Any>? {
    if (payload["type"] != "sync" || syncRevision !in 1L..MAX_GARMIN_SYNC_REVISION) return null
    return boundGarminPayload(payload, binding).toMutableMap().apply {
        // Keep this a Long. A floating-point revision would lose exactness and
        // could acknowledge a different sync after the IEEE-754 integer limit.
        put("syncRevision", syncRevision)
    }
}

internal fun nextGarminSyncRevision(
    lastRevision: Long?,
    nowMillis: Long
): Long? {
    if (
        nowMillis !in 1L..MAX_GARMIN_SYNC_REVISION ||
        (lastRevision != null && lastRevision !in 1L..MAX_GARMIN_SYNC_REVISION)
    ) {
        return null
    }
    if (lastRevision == null) return nowMillis
    if (lastRevision == MAX_GARMIN_SYNC_REVISION) return null
    return maxOf(nowMillis, lastRevision + 1L)
}

internal fun garminSyncAckMatches(
    command: Map<Any?, Any?>,
    expectedSyncId: String,
    expectedRevision: Long
): Boolean {
    if (command.size > MAX_GARMIN_COMMAND_ENTRIES) return false
    if (!isValidGarminMessageId(expectedSyncId, MAX_GARMIN_SYNC_ID_LENGTH)) return false
    if (expectedRevision !in 1L..MAX_GARMIN_SYNC_REVISION) return false
    if (command["type"] != "sync_ack") return false
    if (command["syncId"] != expectedSyncId || command["requestId"] != expectedSyncId) {
        return false
    }
    if (command["syncRevision"] !is Long || command["syncRevision"] != expectedRevision) {
        return false
    }
    return command["applied"] == true
}

internal fun boundedGarminInboundEnvelopes(
    messages: List<*>
): List<GarminInboundCommandEnvelope> {
    val inspectedCount = minOf(messages.size, MAX_GARMIN_EVENT_BATCH)
    return buildList(inspectedCount) {
        for (index in 0 until inspectedCount) {
            @Suppress("UNCHECKED_CAST")
            val command = messages[index] as? Map<Any?, Any?> ?: continue
            if (command.size !in 1..MAX_GARMIN_COMMAND_ENTRIES) continue
            val type = command["type"] as? String ?: continue
            val kind = when (type) {
                "request_sync", "create_workout" -> {
                    val requestId = command["requestId"] as? String ?: continue
                    if (!isValidGarminMessageId(requestId, MAX_GARMIN_REQUEST_ID_LENGTH)) continue
                    GarminInboundCommandKind.Work
                }
                "sync_ack" -> {
                    val syncId = command["syncId"] as? String ?: continue
                    val requestId = command["requestId"] as? String ?: continue
                    if (
                        !isValidGarminMessageId(syncId, MAX_GARMIN_SYNC_ID_LENGTH) ||
                        requestId != syncId ||
                        command["syncRevision"] !is Long ||
                        (command["syncRevision"] as Long) !in 1L..MAX_GARMIN_SYNC_REVISION
                    ) {
                        continue
                    }
                    GarminInboundCommandKind.Acknowledgement
                }
                else -> continue
            }
            // The SDK owns these deserialized maps. Make a bounded shallow copy
            // so callback-owned containers cannot change while queued.
            add(GarminInboundCommandEnvelope(kind, LinkedHashMap(command)))
        }
    }
}

internal fun <T> newBoundedGarminInboundChannel(capacity: Int): Channel<T> {
    require(capacity in 1..MAX_GARMIN_PENDING_WORK_COMMANDS)
    return Channel(capacity = capacity)
}

internal fun isValidGarminAccountBinding(value: String): Boolean {
    return value.length == 64 && value.all { it in '0'..'9' || it in 'a'..'f' }
}

internal fun isValidGarminMessageId(value: String, maxLength: Int): Boolean {
    return value.length in 16..maxLength &&
        value.all { it.isLetterOrDigit() || it == '-' || it == '_' || it == '.' || it == ':' }
}

internal fun parseGarminWorkoutCommand(
    command: Map<Any?, Any?>,
    nowMillis: Long
): GarminWorkoutCommand? = runCatching {
    require(command.size <= MAX_GARMIN_COMMAND_ENTRIES)

    val requestId = requiredGarminString(command, "requestId", MAX_GARMIN_REQUEST_ID_LENGTH)
    require(isValidGarminMessageId(requestId, MAX_GARMIN_REQUEST_ID_LENGTH))

    val rawSets = command["sets"] as? List<*> ?: error("Garmin workout sets are missing.")
    require(rawSets.size in 1..MAX_GARMIN_WORKOUT_SETS)
    val sets = rawSets.map { raw ->
        @Suppress("UNCHECKED_CAST")
        val item = raw as? Map<Any?, Any?> ?: error("Garmin workout set is malformed.")
        require(item.size <= MAX_GARMIN_SET_ENTRIES)
        val exerciseName = requiredGarminString(
            item,
            "exerciseName",
            WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2
        ).trim()
        require(
            WorkoutDataLimits.isValidExerciseName(exerciseName) &&
                exerciseName.codePointCount(0, exerciseName.length) <= MAX_GARMIN_EXERCISE_NAME_LENGTH
        )
        val weight = requiredFiniteDouble(item, "weight")
        val reps = requiredBoundedInt(item, "reps", 1, WorkoutDataLimits.MAX_REPS)
        require(WorkoutDataLimits.isValidWeight(weight))
        NamedWorkoutSetDraft(exerciseName = exerciseName, weight = weight, reps = reps)
    }

    val nowSeconds = nowMillis / 1_000L
    val startedAtSeconds = optionalBoundedLong(
        command,
        "startedAtSeconds",
        MIN_GARMIN_STARTED_AT_SECONDS,
        nowSeconds + MAX_GARMIN_FUTURE_SKEW_SECONDS
    ) ?: nowSeconds
    val startedAtMillis = Math.multiplyExact(startedAtSeconds, 1_000L)
    require(WorkoutDataLimits.isValidTimestamp(startedAtMillis))

    GarminWorkoutCommand(
        requestId = requestId,
        startedAtMillis = startedAtMillis,
        sets = sets,
        durationSeconds = optionalBoundedLong(
            command,
            "durationSeconds",
            0L,
            MAX_GARMIN_DURATION_SECONDS
        ),
        gymCalories = optionalFiniteDouble(command, "gymCalories", 0.0, MAX_GARMIN_CALORIES),
        garminCalories = optionalBoundedInt(command, "garminCalories", 0, MAX_GARMIN_CALORIES.toInt()),
        averageHeartRate = optionalBoundedInt(command, "avgHeartRate", 0, MAX_GARMIN_HEART_RATE),
        maximumHeartRate = optionalBoundedInt(command, "maxHeartRate", 0, MAX_GARMIN_HEART_RATE),
        heartRateZone = optionalBoundedInt(command, "heartRateZone", 0, MAX_GARMIN_HEART_RATE_ZONE)
    )
}.getOrNull()

internal fun validatedGarminPlanOrNull(
    sets: List<NamedWorkoutSetDraft>
): List<NamedWorkoutSetDraft>? = runCatching {
    require(sets.size <= MAX_GARMIN_WORKOUT_SETS)
    var totalNameBytes = 0
    sets.map { set ->
        require(set.exerciseName.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2)
        val name = set.exerciseName.trim()
        require(
            WorkoutDataLimits.isValidExerciseName(name) &&
                name.codePointCount(0, name.length) <= MAX_GARMIN_EXERCISE_NAME_LENGTH
        )
        totalNameBytes = Math.addExact(totalNameBytes, name.toByteArray(Charsets.UTF_8).size)
        require(totalNameBytes <= MAX_GARMIN_TOTAL_NAME_BYTES)
        require(WorkoutDataLimits.isValidWeight(set.weight))
        require(WorkoutDataLimits.isValidReps(set.reps))
        set.copy(exerciseName = name)
    }
}.getOrNull()

internal fun validatedGarminExerciseCatalog(
    exercises: List<String>,
    maximumCount: Int
): List<String>? = runCatching {
    require(exercises.size <= maximumCount)
    val normalized = exercises.map { rawName ->
        require(rawName.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2)
        rawName.trim().also { name ->
            require(
                WorkoutDataLimits.isValidExerciseName(name) &&
                    name.codePointCount(0, name.length) <= MAX_GARMIN_EXERCISE_NAME_LENGTH
            )
        }
    }
    val compact = normalized.distinct()
    val totalNameBytes = compact.fold(0) { total, name ->
        Math.addExact(total, name.toByteArray(Charsets.UTF_8).size)
    }
    require(totalNameBytes <= MAX_GARMIN_TOTAL_NAME_BYTES)
    compact
}.getOrNull()

internal fun isValidGarminTransportDeviceBinding(value: String): Boolean {
    if (value.length !in 1..20) return false
    val digits = if (value.startsWith('-')) value.drop(1) else value
    return digits.isNotEmpty() && digits.all(Char::isDigit) && value.toLongOrNull() != null
}

internal enum class GarminDeviceTargetSource {
    Connected,
    KnownPinned
}

internal data class GarminDeviceTarget(
    val binding: String,
    val source: GarminDeviceTargetSource
)

internal enum class GarminTrustedDeviceState {
    Unpaired,
    Pinned,
    Conflict
}

internal data class GarminTrustedDeviceResolution(
    val state: GarminTrustedDeviceState,
    val binding: String? = null
)

/**
 * Resolves the single physical watch pin while migrating account-scoped legacy pins.
 * Any malformed or contradictory value fails closed instead of selecting a device.
 */
internal fun resolveGlobalGarminDeviceBinding(
    explicitBinding: String?,
    legacyBindings: List<String>
): GarminTrustedDeviceResolution {
    if (explicitBinding != null && !isValidGarminTransportDeviceBinding(explicitBinding)) {
        return GarminTrustedDeviceResolution(GarminTrustedDeviceState.Conflict)
    }
    if (legacyBindings.any { !isValidGarminTransportDeviceBinding(it) }) {
        return GarminTrustedDeviceResolution(GarminTrustedDeviceState.Conflict)
    }
    val candidates = buildSet {
        explicitBinding?.let(::add)
        addAll(legacyBindings)
    }
    return when (candidates.size) {
        0 -> GarminTrustedDeviceResolution(GarminTrustedDeviceState.Unpaired)
        1 -> GarminTrustedDeviceResolution(
            state = GarminTrustedDeviceState.Pinned,
            binding = candidates.single()
        )
        else -> GarminTrustedDeviceResolution(GarminTrustedDeviceState.Conflict)
    }
}

internal data class GarminAuthTransitionTarget(
    val key: String,
    val accountBinding: String
)

/**
 * Produces an opaque epoch for a signed-in session, or a protocol-compatible
 * signed-out owner. A fresh cloud login generation therefore forces a reset,
 * while an access-token refresh in the same generation does not.
 */
internal fun garminAuthTransitionTarget(
    accountBinding: String?,
    sessionGeneration: String?
): GarminAuthTransitionTarget? {
    if (accountBinding == null && sessionGeneration != null) return null
    if (accountBinding != null && !isValidGarminAccountBinding(accountBinding)) return null
    if (
        sessionGeneration != null &&
        (sessionGeneration.length !in 1..128 || sessionGeneration.any(Char::isISOControl))
    ) {
        return null
    }
    val binding = accountBinding
        ?: sha256Hex("gymapp-garmin-signed-out-owner/v1")
    val epoch = sessionGeneration ?: if (accountBinding == null) "signed-out" else "stable"
    return GarminAuthTransitionTarget(
        key = sha256Hex("gymapp-garmin-auth-transition/v1\u0000$binding\u0000$epoch"),
        accountBinding = binding
    )
}

internal fun garminAuthTransitionNeedsReset(
    targetKey: String,
    lastReadyKey: String?,
    trustedDeviceState: GarminTrustedDeviceState
): Boolean {
    if (!isValidGarminAccountBinding(targetKey)) return true
    return when (trustedDeviceState) {
        GarminTrustedDeviceState.Unpaired -> false
        GarminTrustedDeviceState.Pinned -> lastReadyKey != targetKey
        GarminTrustedDeviceState.Conflict -> true
    }
}

internal fun selectGarminDeviceTarget(
    connectedBindings: List<String>,
    knownBindings: List<String>,
    trustedBinding: String?
): GarminDeviceTarget? {
    val connected = connectedBindings
        .filter(::isValidGarminTransportDeviceBinding)
        .distinct()
    if (trustedBinding == null) {
        return connected.singleOrNull()?.let {
            GarminDeviceTarget(it, GarminDeviceTargetSource.Connected)
        }
    }
    if (!isValidGarminTransportDeviceBinding(trustedBinding)) return null
    if (trustedBinding in connected) {
        return GarminDeviceTarget(trustedBinding, GarminDeviceTargetSource.Connected)
    }
    val known = knownBindings
        .filter(::isValidGarminTransportDeviceBinding)
        .distinct()
    return trustedBinding.takeIf { it in known }?.let {
        GarminDeviceTarget(it, GarminDeviceTargetSource.KnownPinned)
    }
}

internal fun garminStorageKey(prefix: String, vararg scopeParts: String): String {
    val digest = sha256Hex(scopeParts.joinToString(separator = "\u0000"))
    return "${prefix}_$digest"
}

internal fun globalGarminSyncRevisionStorageKey(deviceBinding: String): String? {
    if (!isValidGarminTransportDeviceBinding(deviceBinding)) return null
    return garminStorageKey("sync_revision_global_v2", deviceBinding)
}

internal fun canonicalCloudGarminAccountBinding(userId: String): String? {
    if (userId.length !in 36..64) return null
    val normalized = userId.trim().lowercase(Locale.ROOT)
    val canonicalUuid = runCatching { UUID.fromString(normalized).toString() }.getOrNull()
    if (canonicalUuid != normalized) return null
    return sha256Hex(normalized)
}

internal fun newLocalGarminAccountBinding(randomId: String = UUID.randomUUID().toString()): String =
    sha256Hex("gymapp-local-account-binding/v1\u0000$randomId")

private fun sha256Hex(value: String): String = MessageDigest.getInstance("SHA-256")
    .digest(value.toByteArray(Charsets.UTF_8))
    .joinToString(separator = "") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }

private fun requiredGarminString(
    map: Map<Any?, Any?>,
    key: String,
    maxLength: Int
): String {
    val value = map[key] as? String ?: error("Garmin field '$key' is missing.")
    require(value.length in 1..maxLength && value.isNotBlank())
    return value
}

private fun requiredFiniteDouble(map: Map<Any?, Any?>, key: String): Double {
    val value = map[key] as? Number ?: error("Garmin field '$key' is missing.")
    return value.toDouble().also { require(it.isFinite()) }
}

private fun optionalFiniteDouble(
    map: Map<Any?, Any?>,
    key: String,
    minimum: Double,
    maximum: Double
): Double? {
    if (!map.containsKey(key)) return null
    val value = map[key] as? Number ?: error("Garmin field '$key' is malformed.")
    return value.toDouble().also { require(it.isFinite() && it in minimum..maximum) }
}

private fun requiredBoundedInt(
    map: Map<Any?, Any?>,
    key: String,
    minimum: Int,
    maximum: Int
): Int {
    return optionalBoundedInt(map, key, minimum, maximum)
        ?: error("Garmin field '$key' is missing.")
}

private fun optionalBoundedInt(
    map: Map<Any?, Any?>,
    key: String,
    minimum: Int,
    maximum: Int
): Int? {
    if (!map.containsKey(key)) return null
    val value = map[key] as? Number ?: error("Garmin field '$key' is malformed.")
    val doubleValue = value.toDouble()
    require(doubleValue.isFinite() && doubleValue % 1.0 == 0.0)
    require(doubleValue >= minimum.toDouble() && doubleValue <= maximum.toDouble())
    return doubleValue.toInt()
}

private fun optionalBoundedLong(
    map: Map<Any?, Any?>,
    key: String,
    minimum: Long,
    maximum: Long
): Long? {
    if (!map.containsKey(key)) return null
    val value = map[key] as? Number ?: error("Garmin field '$key' is malformed.")
    val doubleValue = value.toDouble()
    require(doubleValue.isFinite() && doubleValue % 1.0 == 0.0)
    require(doubleValue >= minimum.toDouble() && doubleValue <= maximum.toDouble())
    return value.toLong().also { require(it in minimum..maximum) }
}
