package com.example.gymapp.garmin

import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.MessageDigest

internal const val GARMIN_PLAN_SUBMISSION_STORAGE_PREFIX = "plan_submission_v1"
private const val GARMIN_PLAN_SUBMISSION_VERSION = 1
private const val MAX_GARMIN_PLAN_SUBMISSION_CHARS = 512

/**
 * Exact, bounded inputs that make one editor plan submission safe to replay.
 *
 * The raw values are never persisted by this codec. Only a SHA-256 fingerprint plus the random
 * request ID and monotonic revision are stored in the already backup-excluded Garmin preferences.
 */
internal data class GarminPlanSubmissionKey(
    val accountBinding: String,
    val authTransitionKey: String,
    val deviceBinding: String,
    val pairingGeneration: String,
    val includePairingGeneration: Boolean,
    val languageTag: String,
    val orderedPlan: List<NamedWorkoutSetDraft>
)

internal data class GarminPlanSubmissionEnvelope(
    val fingerprint: String,
    val requestId: String,
    val revision: Long
)

internal data class GarminPreparedPlanSubmission(
    val envelope: GarminPlanSubmissionEnvelope,
    val encodedEnvelope: String,
    val reused: Boolean
)

/** Coalesces rapid taps without letting a cancelled caller cancel the shared transport operation. */
internal class GarminPlanSubmissionCoalescer(
    private val scope: CoroutineScope
) {
    private val mutex = Mutex()
    private val inFlight = mutableMapOf<String, Deferred<Boolean>>()

    suspend fun submit(
        callFingerprint: String,
        operation: suspend () -> Boolean
    ): Boolean {
        require(callFingerprint.length == 64 && callFingerprint.all(::isLowerHex))
        val deferred = mutex.withLock {
            inFlight[callFingerprint] ?: scope.async {
                operation()
            }.also { created ->
                inFlight[callFingerprint] = created
                // Cleanup belongs to the manager scope and the transport completion, never to a
                // particular UI waiter. Cancelling the first or a joining tap therefore cannot
                // expose a still-running operation as absent and launch a duplicate send.
                created.invokeOnCompletion {
                    scope.launch {
                        mutex.withLock {
                            if (inFlight[callFingerprint] === created) {
                                inFlight.remove(callFingerprint)
                            }
                        }
                    }
                }
            }
        }
        return deferred.await()
    }
}

internal fun garminPlanRequestFingerprint(
    accountBinding: String,
    authTransitionKey: String,
    trustedDeviceBinding: String?,
    languageTag: String,
    orderedPlan: List<NamedWorkoutSetDraft>
): String? {
    if (!isValidGarminAccountBinding(accountBinding)) return null
    if (!isValidGarminAccountBinding(authTransitionKey)) return null
    if (trustedDeviceBinding != null && !isValidGarminTransportDeviceBinding(trustedDeviceBinding)) {
        return null
    }
    if (languageTag.length !in 2..16 || languageTag.any(Char::isISOControl)) return null
    val plan = validatedGarminPlanOrNull(orderedPlan)?.takeIf { it.isNotEmpty() } ?: return null
    return digestGarminPlanSubmission {
        updateString("gymapp-garmin-plan-call/v1")
        updateString(accountBinding)
        updateString(authTransitionKey)
        updateString(trustedDeviceBinding ?: "unpaired")
        updateString(languageTag)
        updatePlan(plan)
    }
}

internal fun garminPlanSubmissionFingerprint(key: GarminPlanSubmissionKey): String? {
    if (!isValidGarminAccountBinding(key.accountBinding)) return null
    if (!isValidGarminAccountBinding(key.authTransitionKey)) return null
    if (!isValidGarminTransportDeviceBinding(key.deviceBinding)) return null
    if (!isValidGarminPairingGeneration(key.pairingGeneration)) return null
    if (key.languageTag.length !in 2..16 || key.languageTag.any(Char::isISOControl)) return null
    val plan = validatedGarminPlanOrNull(key.orderedPlan)?.takeIf { it.isNotEmpty() }
        ?: return null
    return digestGarminPlanSubmission {
        updateString("gymapp-garmin-plan-submission/v1")
        updateString(key.accountBinding)
        updateString(key.authTransitionKey)
        updateString(key.deviceBinding)
        updateString(key.pairingGeneration)
        updateBoolean(key.includePairingGeneration)
        updateString(key.languageTag)
        updatePlan(plan)
    }
}

internal fun prepareGarminPlanSubmission(
    key: GarminPlanSubmissionKey,
    encodedExisting: String?,
    lastGlobalRevision: Long?,
    nowMillis: Long,
    newRequestId: () -> String
): GarminPreparedPlanSubmission? {
    val fingerprint = garminPlanSubmissionFingerprint(key) ?: return null
    val existing = decodeGarminPlanSubmissionEnvelope(encodedExisting)
    if (
        existing != null &&
        existing.fingerprint == fingerprint &&
        existing.revision == lastGlobalRevision
    ) {
        return GarminPreparedPlanSubmission(
            envelope = existing,
            encodedEnvelope = encodeGarminPlanSubmissionEnvelope(existing),
            reused = true
        )
    }

    val revision = nextGarminSyncRevision(lastGlobalRevision, nowMillis) ?: return null
    val requestId = newRequestId()
    if (!isValidGarminMessageId(requestId, MAX_GARMIN_REQUEST_ID_LENGTH)) return null
    val envelope = GarminPlanSubmissionEnvelope(
        fingerprint = fingerprint,
        requestId = requestId,
        revision = revision
    )
    return GarminPreparedPlanSubmission(
        envelope = envelope,
        encodedEnvelope = encodeGarminPlanSubmissionEnvelope(envelope),
        reused = false
    )
}

internal fun materializeGarminPlanSubmissionPayload(
    key: GarminPlanSubmissionKey,
    envelope: GarminPlanSubmissionEnvelope
): Map<String, Any>? {
    val fingerprint = garminPlanSubmissionFingerprint(key) ?: return null
    if (envelope.fingerprint != fingerprint) return null
    if (!isValidGarminMessageId(envelope.requestId, MAX_GARMIN_REQUEST_ID_LENGTH)) return null
    if (envelope.revision !in 1L..MAX_GARMIN_SYNC_REVISION) return null
    val plan = validatedGarminPlanOrNull(key.orderedPlan)?.takeIf { it.isNotEmpty() }
        ?: return null
    val basePayload = mapOf<String, Any>(
        "type" to "sync",
        "resetWorkout" to false,
        "language" to key.languageTag,
        "planNames" to plan.map { it.exerciseName },
        "planWeights" to plan.map { it.weight },
        "planReps" to plan.map { it.reps },
        "syncId" to envelope.requestId,
        "requestId" to envelope.requestId
    )
    return boundGarminSyncPayload(
        payload = basePayload,
        binding = GarminBinding(
            account = key.accountBinding,
            device = key.deviceBinding,
            pairingGeneration = key.pairingGeneration
        ),
        syncRevision = envelope.revision,
        includePairingGeneration = key.includePairingGeneration
    )
}

internal fun decodeGarminPlanSubmissionEnvelope(raw: String?): GarminPlanSubmissionEnvelope? {
    if (raw == null || raw.length !in 1..MAX_GARMIN_PLAN_SUBMISSION_CHARS) return null
    return runCatching {
        val json = JSONObject(raw)
        require(json.length() == 4)
        val version = json.get("version") as? Number
            ?: error("Submission version is not numeric.")
        require(version !is Float && version !is Double)
        require(version.toLong() == GARMIN_PLAN_SUBMISSION_VERSION.toLong())
        val fingerprint = json.get("fingerprint") as? String
            ?: error("Submission fingerprint is not a string.")
        val requestId = json.get("requestId") as? String
            ?: error("Submission request ID is not a string.")
        val rawRevision = json.get("revision") as? Number
            ?: error("Submission revision is not numeric.")
        require(rawRevision !is Float && rawRevision !is Double)
        val revision = rawRevision.toLong()
        require(fingerprint.length == 64 && fingerprint.all(::isLowerHex))
        require(isValidGarminMessageId(requestId, MAX_GARMIN_REQUEST_ID_LENGTH))
        require(revision in 1L..MAX_GARMIN_SYNC_REVISION)
        GarminPlanSubmissionEnvelope(fingerprint, requestId, revision)
    }.getOrNull()
}

private fun encodeGarminPlanSubmissionEnvelope(
    envelope: GarminPlanSubmissionEnvelope
): String = JSONObject()
    .put("version", GARMIN_PLAN_SUBMISSION_VERSION)
    .put("fingerprint", envelope.fingerprint)
    .put("requestId", envelope.requestId)
    .put("revision", envelope.revision)
    .toString()

private fun isLowerHex(value: Char): Boolean = value in '0'..'9' || value in 'a'..'f'

private class GarminPlanDigestBuilder(
    private val digest: MessageDigest
) {
    fun updateBoolean(value: Boolean) {
        digest.update(if (value) 1.toByte() else 0.toByte())
    }

    fun updateLong(value: Long) {
        digest.update(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(value).array())
    }

    fun updateString(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        updateLong(bytes.size.toLong())
        digest.update(bytes)
    }

    fun updatePlan(plan: List<NamedWorkoutSetDraft>) {
        updateLong(plan.size.toLong())
        plan.forEach { set ->
            updateString(set.exerciseName)
            val canonicalWeight = if (set.weight == 0.0) 0.0 else set.weight
            updateLong(java.lang.Double.doubleToLongBits(canonicalWeight))
            updateLong(set.reps.toLong())
        }
    }
}

private fun digestGarminPlanSubmission(
    update: GarminPlanDigestBuilder.() -> Unit
): String {
    val digest = MessageDigest.getInstance("SHA-256")
    GarminPlanDigestBuilder(digest).update()
    return digest.digest().joinToString(separator = "") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }
}
