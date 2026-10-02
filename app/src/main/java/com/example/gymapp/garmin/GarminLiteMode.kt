package com.example.gymapp.garmin

import java.util.concurrent.ConcurrentHashMap

/**
 * Watches on the 96 KiB memory tier record free workouts only and cannot hold a plan. Their
 * contract is `shared/garmin-lite-mode-v1.json`: they mark `request_sync.watchVersion` with a
 * `-lite` suffix and add `lite: 1` to every `sync_ack`.
 */
internal const val GARMIN_LITE_VERSION_SUFFIX = "-lite"
internal const val MAX_GARMIN_WATCH_VERSION_CHARS = 32

/** Status text surfaced to the UI layer when a plan is requested for a free-workout-only watch. */
internal const val GARMIN_LITE_PLAN_UNSUPPORTED_STATUS =
    "Garmin lite watch supports free workouts only"

/** Returns the bounded, printable-ASCII `watchVersion`, or null when absent or malformed. */
internal fun garminWatchVersionOrNull(command: Map<Any?, Any?>): String? {
    val raw = command["watchVersion"] as? String ?: return null
    if (raw.isEmpty() || raw.length > MAX_GARMIN_WATCH_VERSION_CHARS) return null
    val printable = raw.all { char ->
        char in 'a'..'z' || char in 'A'..'Z' || char in '0'..'9' ||
            char == '.' || char == '-' || char == '_' || char == '+'
    }
    return raw.takeIf { printable }
}

internal fun garminWatchVersionIsLite(version: String?): Boolean =
    version != null &&
        version.length > GARMIN_LITE_VERSION_SUFFIX.length &&
        version.endsWith(GARMIN_LITE_VERSION_SUFFIX)

/**
 * Lite verdict carried by a `request_sync`: true or false when a valid `watchVersion` is present,
 * null when the request carries no usable version and must not change what is already known.
 */
internal fun garminRequestSyncLiteVerdict(command: Map<Any?, Any?>): Boolean? =
    garminWatchVersionOrNull(command)?.let(::garminWatchVersionIsLite)

/** True only for the exact additive integer marker `lite: 1` on a `sync_ack`. */
internal fun garminSyncAckIsLite(command: Map<Any?, Any?>): Boolean {
    if (command["type"] != "sync_ack") return false
    return when (val raw = command["lite"]) {
        is Int -> raw == 1
        is Long -> raw == 1L
        else -> false
    }
}

/**
 * A lite watch refused the sync (bad binding, stale revision, workout in progress, save failure).
 * Repeating the identical message cannot change that, so the sender stops retrying. Correlation
 * and binding checks are the caller's, exactly as for an applied acknowledgement.
 */
internal fun garminLiteSyncAckRefused(
    command: Map<Any?, Any?>,
    expectedSyncId: String,
    expectedRevision: Long
): Boolean {
    if (command.size > MAX_GARMIN_COMMAND_ENTRIES) return false
    if (!isValidGarminMessageId(expectedSyncId, MAX_GARMIN_SYNC_ID_LENGTH)) return false
    if (expectedRevision !in 1L..MAX_GARMIN_SYNC_REVISION) return false
    if (!garminSyncAckIsLite(command)) return false
    if (command["syncId"] != expectedSyncId || command["requestId"] != expectedSyncId) {
        return false
    }
    if (command["syncRevision"] !is Long || command["syncRevision"] != expectedRevision) {
        return false
    }
    return command["applied"] == false
}

/**
 * Binding-only sync for a lite watch: the regular `sync` shape (binding and security fields are
 * added later by [boundGarminSyncPayload]) with empty plan arrays and no exercise catalog, so the
 * message stays tiny and the watch never deserializes a plan it cannot hold.
 */
internal fun garminBindingOnlySyncPayload(
    language: String,
    syncId: String?,
    resetWorkout: Boolean = false,
    repairPairing: Boolean = false
): Map<String, Any> {
    val payload = mutableMapOf<String, Any>(
        "type" to "sync",
        "resetWorkout" to resetWorkout,
        "language" to language,
        "planNames" to emptyList<String>(),
        "planWeights" to emptyList<Double>(),
        "planReps" to emptyList<Int>()
    )
    if (!syncId.isNullOrBlank()) {
        payload["syncId"] = syncId
        payload["requestId"] = syncId
    }
    if (repairPairing) {
        payload["repairPairing"] = true
    }
    return payload
}

/** Durable per-device lite flag. The flag is a hardware tier, not account data. */
internal interface GarminLiteFlagStore {
    fun read(deviceBinding: String): Boolean?
    fun write(deviceBinding: String, lite: Boolean)
}

/**
 * Remembers which watches are lite. A request_sync with a valid `watchVersion` decides both ways
 * (a later non-lite build clears the flag); a `sync_ack` with `lite: 1` can only set it.
 */
internal class GarminLiteWatchTracker(
    private val store: GarminLiteFlagStore
) {
    private val cache = ConcurrentHashMap<String, Boolean>()

    fun isLite(deviceBinding: String): Boolean {
        if (!isValidGarminTransportDeviceBinding(deviceBinding)) return false
        cache[deviceBinding]?.let { return it }
        val stored = runCatching { store.read(deviceBinding) }.getOrNull() ?: return false
        cache.putIfAbsent(deviceBinding, stored)
        return stored
    }

    /** Returns true when the remembered verdict for the device changed. */
    fun recordRequestSync(deviceBinding: String, command: Map<Any?, Any?>): Boolean {
        val verdict = garminRequestSyncLiteVerdict(command) ?: return false
        return set(deviceBinding, verdict)
    }

    /** Returns true when the remembered verdict for the device changed. */
    fun recordSyncAck(deviceBinding: String, command: Map<Any?, Any?>): Boolean =
        garminSyncAckIsLite(command) && set(deviceBinding, true)

    private fun set(deviceBinding: String, lite: Boolean): Boolean {
        if (!isValidGarminTransportDeviceBinding(deviceBinding)) return false
        val previous = isLite(deviceBinding)
        cache[deviceBinding] = lite
        val stored = runCatching { store.read(deviceBinding) }.getOrNull()
        if (stored != lite) {
            runCatching { store.write(deviceBinding, lite) }
        }
        return previous != lite
    }
}
