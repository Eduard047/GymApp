package com.example.gymapp.garmin

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.data.repository.WorkoutDataLimits
import kotlinx.coroutines.channels.Channel
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

internal const val MAX_GARMIN_BINDING_LENGTH = 128
internal const val GARMIN_BINDING_VERSION = 2
internal const val MAX_GARMIN_REQUEST_ID_LENGTH = 128
internal const val MAX_GARMIN_SYNC_ID_LENGTH = 128

internal enum class GarminPendingResetTrigger {
    ExplicitUserAction,
    AuthenticationChange,
    SdkReady,
    DeviceStatusChange
}

internal fun shouldAttemptPendingGarminReset(trigger: GarminPendingResetTrigger): Boolean =
    trigger == GarminPendingResetTrigger.ExplicitUserAction

internal class GarminDeviceRegistrationTracker {
    private val registered = ConcurrentHashMap.newKeySet<Long>()

    fun claim(deviceIdentifier: Long): Boolean = registered.add(deviceIdentifier)

    fun release(deviceIdentifier: Long) {
        registered.remove(deviceIdentifier)
    }

    fun clear() {
        registered.clear()
    }
}

internal const val MAX_GARMIN_WORKOUT_SETS = 60
internal const val MAX_GARMIN_EXERCISE_NAME_LENGTH = 160
internal const val MAX_GARMIN_TOTAL_NAME_BYTES = 12_000
internal const val MAX_GARMIN_SYNC_PAYLOAD_BYTES = 16_384
internal const val MAX_GARMIN_PROJECTED_STORE_BYTES = 24_000
internal const val MAX_GARMIN_COMMAND_ENTRIES = 32
internal const val MAX_GARMIN_SET_ENTRIES = 8
internal const val MAX_GARMIN_EVENT_BATCH = 8
internal const val MAX_GARMIN_PENDING_WORK_COMMANDS = 16
internal const val MAX_GARMIN_PENDING_SYNC_REQUESTS = 1
internal const val MAX_GARMIN_PENDING_ACK_COMMANDS = 8
internal const val MAX_GARMIN_SYNC_REVISION = 9_007_199_254_740_991L
internal const val MAX_GARMIN_DURATION_SECONDS = 7 * 24 * 60 * 60L
internal const val MAX_GARMIN_CALORIES = 100_000.0
internal const val MAX_GARMIN_HEART_RATE = 300
internal const val MAX_GARMIN_HEART_RATE_ZONE = 5
internal const val MAX_GARMIN_SET_INTERVAL_OFFSET_SECONDS = 7 * 24 * 60 * 60L
internal const val MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS = 7_200L
internal const val MAX_GARMIN_SET_INTERVAL_CALORIES = MAX_GARMIN_CALORIES
internal const val GARMIN_SET_INTERVAL_CALORIE_ROUNDING_TOLERANCE = 0.1
internal const val MIN_GARMIN_STARTED_AT_SECONDS = 946_684_800L // 2000-01-01 UTC
internal const val MAX_GARMIN_FUTURE_SKEW_SECONDS = 24 * 60 * 60L
internal const val LEGACY_GARMIN_FALLBACK_GENERATION =
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

internal data class GarminBinding(
    val account: String,
    val device: String,
    val pairingGeneration: String
)

internal enum class GarminInboundCommandKind {
    Workout,
    SyncRequest,
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

internal enum class GarminSyncRequestBindingMismatch {
    None,
    BindingVersion,
    Account,
    Device,
    PairingGeneration
}

internal enum class GarminInboundPairingGenerationMatch {
    Active,
    Pending,
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
    val endingHeartRateZone: Int?,
    val setStatistics: List<GarminSetStatistics?> = emptyList(),
    val setIntervals: List<GarminSetInterval?> = emptyList(),
    val plannedSetCount: Int? = null,
    val plannedTargetSetCount: Int? = null,
    val completedPlannedSetCount: Int? = null
)

internal data class GarminSetStatistics(
    val activeSeconds: Long?,
    val restBeforeSeconds: Long?,
    val startHeartRate: Int?,
    val peakHeartRate: Int?,
    val endHeartRate: Int?,
    val recoveryHeartRateDrop: Int?,
    val detectionConfidence: Int?
)

/**
 * A compact, per-set slice of the workout-wide Garmin metrics.
 *
 * These values are trusted only after the containing bound-device command is accepted. They are
 * intentionally retained in the workout note instead of Room columns so older backups and cloud
 * clients can continue to round-trip the workout without a schema migration.
 */
internal data class GarminSetInterval(
    val startOffsetSeconds: Long,
    val endOffsetSeconds: Long,
    val gymCalories: Double,
    val garminCalories: Int?,
    val heartRateZoneSeconds: List<Int>
)

internal enum class GarminWorkoutParseIssue {
    Envelope,
    RequestId,
    Sets,
    SetShape,
    SetName,
    SetValues,
    SetMetrics,
    SetMetricsShape,
    SetMetricsActiveSeconds,
    SetMetricsRestBeforeSeconds,
    SetMetricsStartHeartRate,
    SetMetricsPeakHeartRate,
    SetMetricsEndHeartRate,
    SetMetricsRecoveryHeartRateDrop,
    SetMetricsDetectionConfidence,
    SetIntervals,
    SetIntervalsShape,
    SetIntervalsOffsets,
    SetIntervalsGymCalories,
    SetIntervalsGarminCalories,
    SetIntervalsHeartRateZones,
    PlannedSetCount,
    PlannedTargetSetCount,
    CompletedPlannedSetCount,
    StartedAt,
    HeartRate,
    Duration,
    Calories,
    HeartRateZone
}

internal data class GarminWorkoutParseResult(
    val command: GarminWorkoutCommand?,
    val issue: GarminWorkoutParseIssue?
)

internal fun canonicalGarminWorkoutPayloadDigest(command: GarminWorkoutCommand): String =
    garminWorkoutPayloadDigest(command, includeExtendedReceiptFields = true)

/**
 * Returns the digest emitted by releases that persisted interval/progress payloads before those
 * fields were covered by the receipt hash. It is accepted only to upgrade an already-committed
 * receipt; it must never authorize a new workout write.
 */
internal fun legacyGarminWorkoutPayloadDigestForUpgrade(
    command: GarminWorkoutCommand
): String? = if (hasGarminExtendedReceiptFields(command)) {
    garminWorkoutPayloadDigest(command, includeExtendedReceiptFields = false)
} else {
    null
}

private fun hasGarminExtendedReceiptFields(command: GarminWorkoutCommand): Boolean =
    command.setIntervals.any { it != null } ||
        command.plannedSetCount != null ||
        command.plannedTargetSetCount != null ||
        command.completedPlannedSetCount != null

private fun garminWorkoutPayloadDigest(
    command: GarminWorkoutCommand,
    includeExtendedReceiptFields: Boolean
): String {
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

    fun updateSetStatistics(statistics: GarminSetStatistics?) {
        digest.update(if (statistics == null) 0.toByte() else 1.toByte())
        statistics?.let {
            updateOptionalLong(it.activeSeconds)
            updateOptionalLong(it.restBeforeSeconds)
            updateOptionalInt(it.startHeartRate)
            updateOptionalInt(it.peakHeartRate)
            updateOptionalInt(it.endHeartRate)
            updateOptionalInt(it.recoveryHeartRateDrop)
            updateOptionalInt(it.detectionConfidence)
        }
    }

    val hasSetStatistics = command.setStatistics.any { it != null }
    val hasExtendedReceiptFields =
        includeExtendedReceiptFields && hasGarminExtendedReceiptFields(command)
    updateString(
        when {
            hasExtendedReceiptFields -> "gymapp-garmin-workout/v3"
            hasSetStatistics -> "gymapp-garmin-workout/v2"
            else -> "gymapp-garmin-workout/v1"
        }
    )
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
    // Keep the v1 digest slot and wire meaning stable. Garmin sends the zone for
    // the final accepted heart-rate reading; it is not a peak or dominant zone.
    updateOptionalInt(command.endingHeartRateZone)
    if (hasExtendedReceiptFields) {
        updateInt(command.setStatistics.size)
        command.setStatistics.forEach(::updateSetStatistics)
        updateInt(command.setIntervals.size)
        command.setIntervals.forEach { interval ->
            digest.update(if (interval == null) 0.toByte() else 1.toByte())
            interval?.let {
                updateLong(it.startOffsetSeconds)
                updateLong(it.endOffsetSeconds)
                updateDouble(it.gymCalories)
                updateOptionalInt(it.garminCalories)
                updateInt(it.heartRateZoneSeconds.size)
                it.heartRateZoneSeconds.forEach(::updateInt)
            }
        }
        updateOptionalInt(command.plannedSetCount)
        updateOptionalInt(command.plannedTargetSetCount)
        updateOptionalInt(command.completedPlannedSetCount)
    } else if (hasSetStatistics) {
        // Preserve the v2 digest for legacy receipts that predate interval/progress fields.
        command.setStatistics.forEach(::updateSetStatistics)
    }

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
    val rawPairingGeneration = command["pairingGeneration"]
    val account = rawAccount as? String
    val device = rawDevice as? String
    val pairingGeneration = rawPairingGeneration as? String

    if (rawAccount != null && account == null) return GarminBindingDecision.Rejected
    if (rawDevice != null && device == null) return GarminBindingDecision.Rejected
    if (rawPairingGeneration != null && pairingGeneration == null) {
        return GarminBindingDecision.Rejected
    }
    if (account == null || device == null) {
        return GarminBindingDecision.Rejected
    }
    if (device != expected.device) return GarminBindingDecision.Rejected
    if (!isValidGarminAccountBinding(account) || account != expected.account) {
        return GarminBindingDecision.Rejected
    }
    if (pairingGeneration == null) {
        return if (expected.pairingGeneration == LEGACY_GARMIN_FALLBACK_GENERATION) {
            GarminBindingDecision.Bound
        } else {
            GarminBindingDecision.Rejected
        }
    }
    if (!isValidGarminPairingGeneration(pairingGeneration) ||
        pairingGeneration != expected.pairingGeneration) {
        return GarminBindingDecision.Rejected
    }
    return GarminBindingDecision.Bound
}

/**
 * A trusted watch with pre-generation state may request a read-only sync once. Workout creation
 * always uses [garminBindingDecision] and therefore never receives this compatibility allowance.
 */
internal fun garminSyncRequestBindingDecision(
    command: Map<Any?, Any?>,
    expected: GarminBinding
): GarminBindingDecision = if (
    garminSyncRequestBindingMismatch(command, expected) ==
        GarminSyncRequestBindingMismatch.None
) GarminBindingDecision.Bound else GarminBindingDecision.Rejected

internal fun garminSyncRequestBindingMismatch(
    command: Map<Any?, Any?>,
    expected: GarminBinding
): GarminSyncRequestBindingMismatch {
    if (!hasCurrentGarminBindingVersion(command)) {
        return GarminSyncRequestBindingMismatch.BindingVersion
    }
    val account = command["accountBinding"] as? String
        ?: return GarminSyncRequestBindingMismatch.Account
    if (!isValidGarminAccountBinding(account) || account != expected.account) {
        return GarminSyncRequestBindingMismatch.Account
    }
    val device = command["deviceBinding"] as? String
        ?: return GarminSyncRequestBindingMismatch.Device
    if (device != expected.device) return GarminSyncRequestBindingMismatch.Device
    val generation = command["pairingGeneration"]
        ?: return GarminSyncRequestBindingMismatch.None
    if (
        generation !is String ||
        !isValidGarminPairingGeneration(generation) ||
        generation != expected.pairingGeneration
    ) {
        return GarminSyncRequestBindingMismatch.PairingGeneration
    }
    return GarminSyncRequestBindingMismatch.None
}

internal fun garminSyncRequestCanRepairPairing(
    command: Map<Any?, Any?>,
    expected: GarminBinding
): Boolean {
    if (
        garminSyncRequestBindingMismatch(command, expected) !=
        GarminSyncRequestBindingMismatch.PairingGeneration
    ) {
        return false
    }
    val watchGeneration = command["pairingGeneration"] as? String ?: return false
    return isValidGarminPairingGeneration(watchGeneration)
}

internal fun hasCurrentGarminBindingVersion(command: Map<Any?, Any?>): Boolean {
    val rawVersion = command["bindingVersion"] as? Number ?: return false
    val version = rawVersion.toDouble()
    return version.isFinite() && version % 1.0 == 0.0 && version == GARMIN_BINDING_VERSION.toDouble()
}

internal fun boundGarminPayload(
    payload: Map<String, Any>,
    binding: GarminBinding,
    includePairingGeneration: Boolean = true
): Map<String, Any> = payload.toMutableMap().apply {
    put("bindingVersion", GARMIN_BINDING_VERSION)
    put("accountBinding", binding.account)
    put("deviceBinding", binding.device)
    if (includePairingGeneration) {
        put("pairingGeneration", binding.pairingGeneration)
    }
}

internal fun boundGarminSyncPayload(
    payload: Map<String, Any>,
    binding: GarminBinding,
    syncRevision: Long,
    includePairingGeneration: Boolean = true
): Map<String, Any>? {
    if (payload["type"] != "sync" || syncRevision !in 1L..MAX_GARMIN_SYNC_REVISION) return null
    val bound = boundGarminPayload(
        payload,
        binding,
        includePairingGeneration = includePairingGeneration
    ).toMutableMap().apply {
        // Keep this a Long. A floating-point revision would lose exactness and
        // could acknowledge a different sync after the IEEE-754 integer limit.
        put("syncRevision", syncRevision)
    }
    return bound.takeIf(::isWithinGarminSyncPayloadBudget)
}

/**
 * Bounds the complete outbound message after bindings and both plan/catalog arrays are present.
 *
 * Connect IQ does not send JSON. Its companion SDK writes a deduplicated UTF-8 string block plus
 * a typed data block: containers and string references use five bytes, an Int uses five, a Long
 * or Double uses nine, a Boolean uses two, and null uses one. Keep the traversal bounded before
 * allocating either block so a future malformed internal caller cannot turn this gate into an
 * unbounded graph walk. Focused tests cross-check this estimate against SDK Serializer output.
 */
internal fun estimatedGarminConnectIqWireBytes(payload: Map<String, Any>): Int? = runCatching {
    val estimate = GarminConnectIqWireEstimate()
    estimate.add(payload, depth = 0)
    Math.addExact(
        if (estimate.hasStrings) GARMIN_CIQ_STRING_AND_DATA_HEADERS_BYTES
        else GARMIN_CIQ_DATA_HEADER_BYTES,
        Math.addExact(estimate.dataBytes, estimate.stringBytes)
    )
}.getOrNull()

internal fun isWithinGarminSyncPayloadBudget(payload: Map<String, Any>): Boolean =
    estimatedGarminConnectIqWireBytes(payload)?.let { it <= MAX_GARMIN_SYNC_PAYLOAD_BYTES } == true

private const val GARMIN_CIQ_DATA_HEADER_BYTES = 8
private const val GARMIN_CIQ_STRING_AND_DATA_HEADERS_BYTES = 16
private const val GARMIN_CIQ_CONTAINER_OR_STRING_REFERENCE_BYTES = 5
private const val MAX_GARMIN_CIQ_WIRE_DEPTH = 8
private const val MAX_GARMIN_CIQ_WIRE_NODES = 512
private const val MAX_GARMIN_CIQ_STRING_CODE_UNITS = MAX_GARMIN_SYNC_PAYLOAD_BYTES

private class GarminConnectIqWireEstimate {
    private val strings = HashSet<String>()
    var dataBytes: Int = 0
        private set
    var stringBytes: Int = 0
        private set
    var hasStrings: Boolean = false
        private set
    private var nodes: Int = 0

    fun add(value: Any?, depth: Int) {
        require(depth <= MAX_GARMIN_CIQ_WIRE_DEPTH)
        nodes = Math.addExact(nodes, 1)
        require(nodes <= MAX_GARMIN_CIQ_WIRE_NODES)
        when (value) {
            null -> addDataBytes(1)
            is Boolean -> addDataBytes(2)
            is Int -> addDataBytes(5)
            is Long -> addDataBytes(if (value in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) 5 else 9)
            is Float -> {
                require(value.isFinite())
                addDataBytes(5)
            }
            is Double -> {
                require(value.isFinite())
                val compact = value.toFloat()
                addDataBytes(
                    if (compact.isFinite() && kotlin.math.abs(compact.toDouble() - value) < 1.0e-5) {
                        5
                    } else {
                        9
                    }
                )
            }
            is String -> addString(value)
            is List<*> -> {
                require(value.size <= MAX_GARMIN_CIQ_WIRE_NODES)
                addDataBytes(GARMIN_CIQ_CONTAINER_OR_STRING_REFERENCE_BYTES)
                value.forEach { child -> add(child, depth + 1) }
            }
            is Map<*, *> -> {
                require(value.size <= MAX_GARMIN_CIQ_WIRE_NODES)
                addDataBytes(GARMIN_CIQ_CONTAINER_OR_STRING_REFERENCE_BYTES)
                value.forEach { (rawKey, child) ->
                    val key = rawKey as? String ?: error("Connect IQ payload keys must be strings.")
                    add(key, depth + 1)
                    add(child, depth + 1)
                }
            }
            else -> error("Unsupported Connect IQ payload value.")
        }
    }

    private fun addString(value: String) {
        require(value.length <= MAX_GARMIN_CIQ_STRING_CODE_UNITS)
        addDataBytes(GARMIN_CIQ_CONTAINER_OR_STRING_REFERENCE_BYTES)
        hasStrings = true
        if (strings.add(value)) {
            val utf8Bytes = value.toByteArray(Charsets.UTF_8).size
            // The SDK prefixes each string (including its trailing NUL) with an unsigned-short
            // length. This also keeps a single string allocation below the total message budget.
            require(utf8Bytes + 1 <= 0xffff)
            stringBytes = Math.addExact(stringBytes, Math.addExact(3, utf8Bytes))
            require(stringBytes <= MAX_GARMIN_SYNC_PAYLOAD_BYTES)
        }
    }

    private fun addDataBytes(bytes: Int) {
        dataBytes = Math.addExact(dataBytes, bytes)
        require(dataBytes <= MAX_GARMIN_SYNC_PAYLOAD_BYTES)
    }
}

/**
 * Builds the only sync payload allowed to rotate a live secure pairing generation.
 *
 * A rollover preserves the watch's active workout and durable pending queue. Keep
 * these checks separate from the generic sync builder so a future caller cannot
 * accidentally turn receipt maintenance into a destructive workout reset.
 */
internal fun boundGarminPairingRolloverPayload(
    payload: Map<String, Any>,
    previousBinding: GarminBinding,
    nextPairingGeneration: String,
    syncRevision: Long
): Map<String, Any>? {
    if (
        payload["type"] != "sync" ||
        payload["repairPairing"] != true ||
        payload["resetWorkout"] != false ||
        !isValidGarminAccountBinding(previousBinding.account) ||
        !isValidGarminTransportDeviceBinding(previousBinding.device) ||
        !isValidGarminPairingGeneration(previousBinding.pairingGeneration) ||
        previousBinding.pairingGeneration == LEGACY_GARMIN_FALLBACK_GENERATION ||
        !isValidGarminPairingGeneration(nextPairingGeneration) ||
        nextPairingGeneration == LEGACY_GARMIN_FALLBACK_GENERATION ||
        nextPairingGeneration == previousBinding.pairingGeneration
    ) {
        return null
    }
    return boundGarminSyncPayload(
        payload = payload,
        binding = previousBinding.copy(pairingGeneration = nextPairingGeneration),
        syncRevision = syncRevision,
        includePairingGeneration = true
    )
}

internal fun garminCommandAdvertisesPairingGeneration(command: Map<Any?, Any?>): Boolean =
    command["pairingGenerationSupported"] == true

internal fun shouldCommitGarminPairingGenerationCapability(
    capabilityProofPending: Boolean,
    syncConfirmed: Boolean
): Boolean = capabilityProofPending && syncConfirmed

internal fun prioritizedGarminProfileDeviceIds(
    deviceIdentifiers: Collection<Long>,
    trustedDeviceBinding: String?,
    maximumCount: Int
): List<Long> {
    if (maximumCount <= 0) return emptyList()
    val trustedDeviceId = trustedDeviceBinding
        ?.takeIf(::isValidGarminTransportDeviceBinding)
        ?.toLongOrNull()
    return deviceIdentifiers
        .distinct()
        .sortedWith(
            compareByDescending<Long> { trustedDeviceId != null && it == trustedDeviceId }
                .thenBy { it }
        )
        .take(maximumCount)
}

internal fun garminInboundPairingGenerationMatch(
    claimedGeneration: String,
    activeGeneration: String,
    pendingGeneration: String?
): GarminInboundPairingGenerationMatch {
    if (
        !isValidGarminPairingGeneration(claimedGeneration) ||
        !isValidGarminPairingGeneration(activeGeneration) ||
        (pendingGeneration != null &&
            (!isValidGarminPairingGeneration(pendingGeneration) ||
                pendingGeneration == activeGeneration))
    ) {
        return GarminInboundPairingGenerationMatch.Rejected
    }
    return when (claimedGeneration) {
        activeGeneration -> GarminInboundPairingGenerationMatch.Active
        pendingGeneration -> GarminInboundPairingGenerationMatch.Pending
        else -> GarminInboundPairingGenerationMatch.Rejected
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
                    if (type == "create_workout") {
                        GarminInboundCommandKind.Workout
                    } else {
                        GarminInboundCommandKind.SyncRequest
                    }
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

internal fun isValidGarminPairingGeneration(value: String): Boolean =
    isValidGarminAccountBinding(value)

internal fun isValidGarminMessageId(value: String, maxLength: Int): Boolean {
    return value.length in 16..maxLength &&
        value.all { it.isLetterOrDigit() || it == '-' || it == '_' || it == '.' || it == ':' }
}

internal fun parseGarminWorkoutCommand(
    command: Map<Any?, Any?>,
    nowMillis: Long
): GarminWorkoutCommand? = parseGarminWorkoutCommandResult(command, nowMillis).command

internal fun parseGarminWorkoutCommandResult(
    command: Map<Any?, Any?>,
    nowMillis: Long
): GarminWorkoutParseResult {
    var issue = GarminWorkoutParseIssue.Envelope
    val parsed = runCatching {
    require(command.size <= MAX_GARMIN_COMMAND_ENTRIES)

    issue = GarminWorkoutParseIssue.RequestId
    val requestId = requiredGarminString(command, "requestId", MAX_GARMIN_REQUEST_ID_LENGTH)
    require(isValidGarminMessageId(requestId, MAX_GARMIN_REQUEST_ID_LENGTH))

    issue = GarminWorkoutParseIssue.Sets
    val rawSets = command["sets"] as? List<*> ?: error("Garmin workout sets are missing.")
    require(rawSets.size in 1..MAX_GARMIN_WORKOUT_SETS)
    val sets = rawSets.map { raw ->
        issue = GarminWorkoutParseIssue.SetShape
        @Suppress("UNCHECKED_CAST")
        val item = raw as? Map<Any?, Any?> ?: error("Garmin workout set is malformed.")
        require(item.size <= MAX_GARMIN_SET_ENTRIES)
        issue = GarminWorkoutParseIssue.SetName
        val exerciseName = requiredGarminString(
            item,
            "exerciseName",
            WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2
        ).trim()
        require(
            WorkoutDataLimits.isValidExerciseName(exerciseName) &&
                exerciseName.codePointCount(0, exerciseName.length) <= MAX_GARMIN_EXERCISE_NAME_LENGTH
        )
        issue = GarminWorkoutParseIssue.SetValues
        val weight = requiredFiniteDouble(item, "weight")
        val reps = requiredBoundedInt(item, "reps", 1, WorkoutDataLimits.MAX_REPS)
        require(WorkoutDataLimits.isValidWeight(weight))
        NamedWorkoutSetDraft(exerciseName = exerciseName, weight = weight, reps = reps)
    }

    issue = GarminWorkoutParseIssue.PlannedSetCount
    val plannedSetCount = optionalBoundedInt(
        command,
        "plannedSetCount",
        1,
        MAX_GARMIN_WORKOUT_SETS
    )
    require(plannedSetCount == null || plannedSetCount >= sets.size)

    issue = GarminWorkoutParseIssue.PlannedTargetSetCount
    val plannedTargetSetCount = optionalBoundedInt(
        command,
        "plannedTargetSetCount",
        1,
        MAX_GARMIN_WORKOUT_SETS
    )

    issue = GarminWorkoutParseIssue.CompletedPlannedSetCount
    val completedPlannedSetCount = optionalBoundedInt(
        command,
        "completedPlannedSetCount",
        0,
        MAX_GARMIN_WORKOUT_SETS
    )
    val hasPlannedTargetSetCount = command.containsKey("plannedTargetSetCount")
    val hasCompletedPlannedSetCount = command.containsKey("completedPlannedSetCount")
    require(hasPlannedTargetSetCount == hasCompletedPlannedSetCount)
    if (hasPlannedTargetSetCount) {
        require(
            plannedSetCount != null && plannedTargetSetCount != null &&
                completedPlannedSetCount != null
        )
        require(plannedSetCount >= plannedTargetSetCount)
        require(completedPlannedSetCount <= minOf(plannedTargetSetCount, sets.size))
    }

    issue = GarminWorkoutParseIssue.SetMetrics
    val rawSetMetrics = command["setMetrics"]
    val setStatistics = if (rawSetMetrics == null) {
        List(sets.size) { null }
    } else {
        val metrics = rawSetMetrics as? List<*> ?: error("Garmin set metrics are malformed.")
        require(metrics.size == sets.size)
        metrics.map { raw ->
            issue = GarminWorkoutParseIssue.SetMetricsShape
            val values = raw as? List<*> ?: error("Garmin set metrics are malformed.")
            val metricResult = parseGarminSetStatistics(values)
            metricResult.issue?.let { metricIssue ->
                issue = metricIssue
                error("Garmin set metrics are outside supported limits.")
            }
            metricResult.statistics
        }
    }


    issue = GarminWorkoutParseIssue.SetIntervals
    val rawSetIntervals = command["setIntervals"]
    val setIntervals = if (rawSetIntervals == null) {
        List(sets.size) { null }
    } else {
        val intervals = rawSetIntervals as? List<*>
            ?: error("Garmin set intervals are malformed.")
        require(intervals.size == sets.size)
        intervals.map { raw ->
            issue = GarminWorkoutParseIssue.SetIntervalsShape
            val values = raw as? List<*> ?: error("Garmin set interval is malformed.")
            val intervalResult = parseGarminSetInterval(values)
            intervalResult.issue?.let { intervalIssue ->
                issue = intervalIssue
                error("Garmin set interval is outside supported limits.")
            }
            checkNotNull(intervalResult.interval)
        }
    }

    issue = GarminWorkoutParseIssue.StartedAt
    val nowSeconds = nowMillis / 1_000L
    val startedAtSeconds = optionalBoundedLong(
        command,
        "startedAtSeconds",
        MIN_GARMIN_STARTED_AT_SECONDS,
        nowSeconds + MAX_GARMIN_FUTURE_SKEW_SECONDS
    ) ?: nowSeconds
    val startedAtMillis = Math.multiplyExact(startedAtSeconds, 1_000L)
    require(WorkoutDataLimits.isValidTimestamp(startedAtMillis))
    issue = GarminWorkoutParseIssue.HeartRate
    val averageHeartRate = nullableOptionalBoundedInt(
        command,
        "avgHeartRate",
        0,
        MAX_GARMIN_HEART_RATE
    )
    val maximumHeartRate = nullableOptionalBoundedInt(
        command,
        "maxHeartRate",
        0,
        MAX_GARMIN_HEART_RATE
    )
    nullableOptionalBoundedInt(command, "lastHeartRate", 0, MAX_GARMIN_HEART_RATE)
    require(averageHeartRate == null || maximumHeartRate == null || averageHeartRate <= maximumHeartRate)

    issue = GarminWorkoutParseIssue.Duration
    val durationSeconds = nullableOptionalBoundedLong(
        command,
        "durationSeconds",
        0L,
        MAX_GARMIN_DURATION_SECONDS
    )
    issue = GarminWorkoutParseIssue.Calories
    val gymCalories = nullableOptionalFiniteDouble(
        command,
        "gymCalories",
        0.0,
        MAX_GARMIN_CALORIES
    )
    val garminCalories = nullableOptionalBoundedInt(
        command,
        "garminCalories",
        0,
        MAX_GARMIN_CALORIES.toInt()
    )

    if (rawSetIntervals != null) {
        val structuredIntervals = setIntervals.map { checkNotNull(it) }

        issue = GarminWorkoutParseIssue.SetIntervalsOffsets
        structuredIntervals.zipWithNext().forEach { (previous, current) ->
            require(current.startOffsetSeconds >= previous.endOffsetSeconds)
        }
        val totalDurationSeconds = requireNotNull(durationSeconds)
        require(
            structuredIntervals.all { interval ->
                interval.endOffsetSeconds <= totalDurationSeconds
            }
        )

        issue = GarminWorkoutParseIssue.SetIntervalsGymCalories
        val totalGymCalories = requireNotNull(gymCalories)
        val intervalGymCalories = structuredIntervals.sumOf { it.gymCalories }
        require(
            intervalGymCalories <=
                totalGymCalories + GARMIN_SET_INTERVAL_CALORIE_ROUNDING_TOLERANCE
        )

        val intervalGarminCalories = structuredIntervals.mapNotNull { it.garminCalories }
        if (intervalGarminCalories.isNotEmpty()) {
            issue = GarminWorkoutParseIssue.SetIntervalsGarminCalories
            val totalGarminCalories = requireNotNull(garminCalories)
            require(intervalGarminCalories.sum() <= totalGarminCalories)
        }
    }

    issue = GarminWorkoutParseIssue.HeartRateZone
    val endingHeartRateZone = nullableOptionalBoundedInt(
        command,
        "heartRateZone",
        0,
        MAX_GARMIN_HEART_RATE_ZONE
    )

    GarminWorkoutCommand(
        requestId = requestId,
        startedAtMillis = startedAtMillis,
        sets = sets,
        durationSeconds = durationSeconds,
        gymCalories = gymCalories,
        garminCalories = garminCalories,
        averageHeartRate = averageHeartRate,
        maximumHeartRate = maximumHeartRate,
        endingHeartRateZone = endingHeartRateZone,
        setStatistics = setStatistics,
        setIntervals = setIntervals,
        plannedSetCount = plannedSetCount,
        plannedTargetSetCount = plannedTargetSetCount,
        completedPlannedSetCount = completedPlannedSetCount
    )
    }.getOrNull()
    return GarminWorkoutParseResult(
        command = parsed,
        issue = if (parsed == null) issue else null
    )
}

private data class GarminSetIntervalParseResult(
    val interval: GarminSetInterval?,
    val issue: GarminWorkoutParseIssue?
)

private fun parseGarminSetInterval(values: List<*>): GarminSetIntervalParseResult {
    var issue = GarminWorkoutParseIssue.SetIntervalsShape
    return try {
        require(values.size == 10)
        val item = buildMap<Any?, Any?> {
            put("startOffsetSeconds", values[0])
            put("endOffsetSeconds", values[1])
            put("gymCalories", values[2])
            values[3]?.let { put("garminCalories", it) }
            repeat(6) { zone -> put("z$zone", values[zone + 4]) }
        }

        issue = GarminWorkoutParseIssue.SetIntervalsOffsets
        val startOffsetSeconds = requiredBoundedLong(
            item,
            "startOffsetSeconds",
            0L,
            MAX_GARMIN_SET_INTERVAL_OFFSET_SECONDS
        )
        val endOffsetSeconds = requiredBoundedLong(
            item,
            "endOffsetSeconds",
            0L,
            MAX_GARMIN_SET_INTERVAL_OFFSET_SECONDS
        )
        require(endOffsetSeconds >= startOffsetSeconds)
        val intervalDuration = endOffsetSeconds - startOffsetSeconds
        require(intervalDuration <= MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS)

        issue = GarminWorkoutParseIssue.SetIntervalsGymCalories
        val gymCalories = optionalFiniteDouble(
            item,
            "gymCalories",
            0.0,
            MAX_GARMIN_SET_INTERVAL_CALORIES
        ) ?: error("Garmin interval calories are missing.")

        issue = GarminWorkoutParseIssue.SetIntervalsGarminCalories
        val garminCalories = optionalBoundedInt(
            item,
            "garminCalories",
            0,
            MAX_GARMIN_SET_INTERVAL_CALORIES.toInt()
        )

        issue = GarminWorkoutParseIssue.SetIntervalsHeartRateZones
        val zones = List(6) { zone ->
            requiredBoundedInt(
                item,
                "z$zone",
                0,
                MAX_GARMIN_SET_INTERVAL_DURATION_SECONDS.toInt()
            )
        }
        val zoneSeconds = zones.fold(0L) { total, seconds -> Math.addExact(total, seconds.toLong()) }
        require(zoneSeconds <= intervalDuration)

        GarminSetIntervalParseResult(
            interval = GarminSetInterval(
                startOffsetSeconds = startOffsetSeconds,
                endOffsetSeconds = endOffsetSeconds,
                gymCalories = gymCalories,
                garminCalories = garminCalories,
                heartRateZoneSeconds = zones
            ),
            issue = null
        )
    } catch (_: RuntimeException) {
        GarminSetIntervalParseResult(interval = null, issue = issue)
    }
}

private data class GarminSetStatisticsParseResult(
    val statistics: GarminSetStatistics?,
    val issue: GarminWorkoutParseIssue?
)

private fun parseGarminSetStatistics(values: List<*>): GarminSetStatisticsParseResult {
    var issue = GarminWorkoutParseIssue.SetMetricsShape
    return try {
    require(values.size == 7)
    val metricKeys = listOf(
        "activeSeconds",
        "restBeforeSeconds",
        "startHeartRate",
        "peakHeartRate",
        "endHeartRate",
        "recoveryHeartRateDrop",
        "detectionConfidence"
    )
    // Connect IQ uses null in the fixed seven-slot metrics tuple for an
    // unavailable optional reading. Omit those slots before using the generic
    // optional-number validators; non-null values remain strictly bounded.
    val item = buildMap<Any?, Any?> {
        metricKeys.indices.forEach { index ->
            values[index]?.let { value -> put(metricKeys[index], value) }
        }
    }
    issue = GarminWorkoutParseIssue.SetMetricsActiveSeconds
    val activeSeconds = optionalBoundedLong(item, "activeSeconds", 0L, 7_200L)
    issue = GarminWorkoutParseIssue.SetMetricsRestBeforeSeconds
    val restBeforeSeconds = optionalBoundedLong(item, "restBeforeSeconds", 0L, 86_400L)
    issue = GarminWorkoutParseIssue.SetMetricsStartHeartRate
    val startHeartRate = optionalBoundedInt(item, "startHeartRate", 0, 240)
    issue = GarminWorkoutParseIssue.SetMetricsPeakHeartRate
    val reportedPeakHeartRate = optionalBoundedInt(item, "peakHeartRate", 0, 240)
    issue = GarminWorkoutParseIssue.SetMetricsEndHeartRate
    val endHeartRate = optionalBoundedInt(item, "endHeartRate", 0, 240)
    issue = GarminWorkoutParseIssue.SetMetricsRecoveryHeartRateDrop
    val recoveryHeartRateDrop = optionalBoundedInt(item, "recoveryHeartRateDrop", 0, 240)
    issue = GarminWorkoutParseIssue.SetMetricsDetectionConfidence
    val detectionConfidence = optionalBoundedInt(item, "detectionConfidence", 0, 100)
    val parsedValues = listOf(
        activeSeconds,
        restBeforeSeconds,
        startHeartRate,
        reportedPeakHeartRate,
        endHeartRate,
        recoveryHeartRateDrop,
        detectionConfidence
    )
    if (parsedValues.all { it == null }) {
        return GarminSetStatisticsParseResult(statistics = null, issue = null)
    }
    // Older released watch builds could snapshot the end HR after the stored peak,
    // producing start/end > peak even though every scalar was valid. Preserve the
    // workout and canonicalize the derived peak to the maximum observed HR.
    val peakHeartRate = listOfNotNull(
        startHeartRate,
        reportedPeakHeartRate,
        endHeartRate
    ).maxOrNull()
    GarminSetStatisticsParseResult(
        statistics = GarminSetStatistics(
            activeSeconds = activeSeconds,
            restBeforeSeconds = restBeforeSeconds,
            startHeartRate = startHeartRate,
            peakHeartRate = peakHeartRate,
            endHeartRate = endHeartRate,
            recoveryHeartRateDrop = recoveryHeartRateDrop,
            detectionConfidence = detectionConfidence
        ),
        issue = null
    )
    } catch (_: RuntimeException) {
        GarminSetStatisticsParseResult(statistics = null, issue = issue)
    }
}

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

/**
 * Builds the bounded watch picker catalog for free-order workouts.
 *
 * Planned names are retained first so every target remains selectable. Valid catalog extras are
 * then appended in stable order until either the count or UTF-8 message budget is exhausted.
 */
internal fun mergedGarminExerciseCatalogForFreeOrder(
    plan: List<NamedWorkoutSetDraft>,
    exercises: List<String>,
    maximumCount: Int
): List<String>? = runCatching {
    require(maximumCount in 1..MAX_GARMIN_WORKOUT_SETS)
    require(exercises.size <= WorkoutDataLimits.MAX_EXERCISES)
    val safePlan = validatedGarminPlanOrNull(plan)
        ?: error("Garmin plan is outside supported limits.")
    val merged = mutableListOf<String>()
    val seen = mutableSetOf<String>()
    var totalNameBytes = 0

    safePlan.forEach { set ->
        val name = set.exerciseName
        if (seen.add(name)) {
            require(merged.size < maximumCount)
            totalNameBytes = Math.addExact(
                totalNameBytes,
                name.toByteArray(Charsets.UTF_8).size
            )
            require(totalNameBytes <= MAX_GARMIN_TOTAL_NAME_BYTES)
            merged += name
        }
    }
    for (rawName in exercises) {
        if (merged.size >= maximumCount) break
        require(rawName.length <= WorkoutDataLimits.MAX_EXERCISE_NAME_LENGTH * 2)
        val name = rawName.trim()
        require(
            WorkoutDataLimits.isValidExerciseName(name) &&
                name.codePointCount(0, name.length) <= MAX_GARMIN_EXERCISE_NAME_LENGTH
        )
        if (name !in seen) {
            val nameBytes = name.toByteArray(Charsets.UTF_8).size
            if (totalNameBytes + nameBytes <= MAX_GARMIN_TOTAL_NAME_BYTES) {
                seen += name
                merged += name
                totalNameBytes += nameBytes
            }
        }
    }
    merged
}.getOrNull()

internal fun mergedGarminExerciseCatalogWithinDurableBudget(
    plan: List<NamedWorkoutSetDraft>,
    exercises: List<String>,
    accountBinding: String,
    deviceBinding: String,
    pairingGeneration: String,
    maximumCount: Int = MAX_GARMIN_WORKOUT_SETS
): List<String>? = runCatching {
    val catalog = mergedGarminExerciseCatalogForFreeOrder(
        plan = plan,
        exercises = exercises,
        maximumCount = maximumCount
    ) ?: error("Garmin catalog is outside supported limits.")
    if (catalog.isEmpty()) {
        require(plan.isEmpty())
    } else {
        require(
            isWithinProjectedGarminDurableWorkoutBudget(
                plan = plan,
                exerciseCatalog = catalog,
                accountBinding = accountBinding,
                deviceBinding = deviceBinding,
                pairingGeneration = pairingGeneration
            )
        )
    }
    catalog
}.getOrNull()

/**
 * Projects the largest valid 60-set durable active-workout shape for a synced plan/catalog.
 *
 * The watch permits free exercise order and up to sixty sets even when the phone plan is shorter,
 * so the projection deliberately fills all sixty v4 set-index/weight/repetition slots. Every
 * product retains a self-describing rich plan so a separately committed catalog update cannot
 * reinterpret its targets. Full profiles persist optional detector/HR metrics while they fit and
 * atomically fall back to the compact v4 shape near the limit, so the smaller valid projection is
 * the guaranteed cross-device shape. Rejecting here happens before the plan is cached or a replay
 * envelope is persisted, instead of letting a workout hit STORE FULL late in the session.
 */
internal fun projectedGarminDurableWorkoutBytes(
    plan: List<NamedWorkoutSetDraft>,
    exerciseCatalog: List<String>,
    accountBinding: String,
    deviceBinding: String,
    pairingGeneration: String
): Int? = runCatching {
    require(isValidGarminAccountBinding(accountBinding))
    require(isValidGarminTransportDeviceBinding(deviceBinding))
    require(isValidGarminPairingGeneration(pairingGeneration))
    val safePlan = validatedGarminPlanOrNull(plan)
        ?: error("Garmin plan is outside supported limits.")
    val safeCatalog = mergedGarminExerciseCatalogForFreeOrder(
        plan = safePlan,
        exercises = exerciseCatalog,
        maximumCount = MAX_GARMIN_WORKOUT_SETS
    )?.takeIf { it.isNotEmpty() } ?: error("Garmin catalog is outside supported limits.")
    // The last valid index has the widest scalar representation. Maximum editor values likewise
    // reserve more Object Store text than ordinary workout targets.
    val projectedIndices = List(MAX_GARMIN_WORKOUT_SETS) { safeCatalog.lastIndex }
    val projectedWeights = List(MAX_GARMIN_WORKOUT_SETS) { WorkoutDataLimits.MAX_WEIGHT }
    val projectedReps = List(MAX_GARMIN_WORKOUT_SETS) { WorkoutDataLimits.MAX_REPS }
    val projectedMetrics = List(MAX_GARMIN_WORKOUT_SETS) { index ->
        listOf(7_200, if (index == 0) null else 86_400, 240, 240, 240, null, 100)
    }
    val projectedIntervals = List(MAX_GARMIN_WORKOUT_SETS) { index ->
        val started = index * 10_000
        listOf(started, started + 7_200, 100_000.0, 100_000, 1_200, 1_200, 1_200, 1_200, 1_200, 1_200)
    }
    val projectedCheckpoint = listOf(
        604_800,
        10_000_000.0,
        10_000_000,
        145_000_000,
        604_800,
        300,
        300,
        5
    )
    val projectedOrigin = 1_800_000_000
    val fullSnapshot = listOf(
        4,
        accountBinding,
        deviceBinding,
        pairingGeneration,
        projectedOrigin,
        projectedIndices,
        projectedWeights,
        projectedReps,
        projectedMetrics,
        projectedIntervals,
        projectedCheckpoint
    )
    val compactSnapshot = listOf(
        4,
        accountBinding,
        deviceBinding,
        pairingGeneration,
        projectedOrigin,
        projectedIndices,
        projectedWeights,
        projectedReps,
        projectedIntervals,
        projectedCheckpoint
    )
    val storedPlan = safePlan.map { set ->
        linkedMapOf<String, Any>(
            "exerciseName" to set.exerciseName,
            "weight" to set.weight,
            "reps" to set.reps
        )
    }

    minOf(
        projectedGarminStoreBytes(
            exerciseCatalog = safeCatalog,
            snapshot = fullSnapshot,
            storedPlan = storedPlan,
            accountBinding = accountBinding,
            deviceBinding = deviceBinding,
            pairingGeneration = pairingGeneration
        ),
        projectedGarminStoreBytes(
            exerciseCatalog = safeCatalog,
            snapshot = compactSnapshot,
            storedPlan = storedPlan,
            accountBinding = accountBinding,
            deviceBinding = deviceBinding,
            pairingGeneration = pairingGeneration
        )
    )
}.getOrNull()

internal fun isWithinProjectedGarminDurableWorkoutBudget(
    plan: List<NamedWorkoutSetDraft>,
    exerciseCatalog: List<String>,
    accountBinding: String,
    deviceBinding: String,
    pairingGeneration: String
): Boolean = projectedGarminDurableWorkoutBytes(
    plan = plan,
    exerciseCatalog = exerciseCatalog,
    accountBinding = accountBinding,
    deviceBinding = deviceBinding,
    pairingGeneration = pairingGeneration
)?.let { it <= MAX_GARMIN_PROJECTED_STORE_BYTES } == true

private fun projectedGarminStoreBytes(
    exerciseCatalog: List<String>,
    snapshot: List<Any?>,
    storedPlan: List<*>,
    accountBinding: String,
    deviceBinding: String,
    pairingGeneration: String
): Int {
    val estimate = GarminObjectStoreEstimate()
    var total = 4_096 + 2_048
    fun add(value: Any?) {
        total = Math.addExact(total, estimate.bytes(value))
    }

    add(exerciseCatalog)
    add(snapshot)
    add(storedPlan)
    add(emptyList<Any>()) // pending workouts
    add(null) // deferred sync
    add(emptyList<String>()) // processed sync IDs
    add(accountBinding)
    add(deviceBinding)
    add(pairingGeneration)
    add(deviceBinding) // possible cloud-device mirror
    add(null) // prepared workout
    add(null) // last workout sync
    add(emptyList<Any>()) // tutorial history
    return total
}

/** Mirrors GymStore.estimatedValueBytesAtDepth without serializing a whole object graph. */
private class GarminObjectStoreEstimate {
    fun bytes(value: Any?): Int = bytesAtDepth(value, depth = 0)

    private fun bytesAtDepth(value: Any?, depth: Int): Int {
        require(depth <= 8)
        return when (value) {
            null -> 4
            is String -> Math.addExact(2, value.toByteArray(Charsets.UTF_8).size)
            is Boolean -> if (value) 4 else 5
            is Number -> value.toString().length
            is List<*> -> {
                require(value.size <= 512)
                value.foldIndexed(2) { index, total, child ->
                    Math.addExact(
                        Math.addExact(total, if (index == 0) 0 else 1),
                        bytesAtDepth(child, depth + 1)
                    )
                }
            }
            is Map<*, *> -> {
                require(value.size <= 512)
                value.entries.foldIndexed(2) { index, total, (rawKey, child) ->
                    val key = rawKey as? String ?: error("Garmin Object Store keys must be strings.")
                    require(key.length <= 64)
                    val keyBytes = key.toByteArray(Charsets.UTF_8).size
                    val withSeparator = Math.addExact(total, if (index == 0) 0 else 1)
                    val withKey = Math.addExact(withSeparator, Math.addExact(3, keyBytes))
                    Math.addExact(withKey, bytesAtDepth(child, depth + 1))
                }
            }
            else -> error("Unsupported Garmin Object Store value.")
        }
    }
}

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

internal fun newGarminPairingGeneration(randomId: String = UUID.randomUUID().toString()): String =
    sha256Hex("gymapp-garmin-pairing-generation/v1\u0000$randomId")

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

private fun nullableOptionalFiniteDouble(
    map: Map<Any?, Any?>,
    key: String,
    minimum: Double,
    maximum: Double
): Double? {
    if (!map.containsKey(key) || map[key] == null) return null
    return optionalFiniteDouble(map, key, minimum, maximum)
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

private fun requiredBoundedLong(
    map: Map<Any?, Any?>,
    key: String,
    minimum: Long,
    maximum: Long
): Long {
    return optionalBoundedLong(map, key, minimum, maximum)
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

private fun nullableOptionalBoundedInt(
    map: Map<Any?, Any?>,
    key: String,
    minimum: Int,
    maximum: Int
): Int? {
    if (!map.containsKey(key) || map[key] == null) return null
    return optionalBoundedInt(map, key, minimum, maximum)
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

private fun nullableOptionalBoundedLong(
    map: Map<Any?, Any?>,
    key: String,
    minimum: Long,
    maximum: Long
): Long? {
    if (!map.containsKey(key) || map[key] == null) return null
    return optionalBoundedLong(map, key, minimum, maximum)
}
