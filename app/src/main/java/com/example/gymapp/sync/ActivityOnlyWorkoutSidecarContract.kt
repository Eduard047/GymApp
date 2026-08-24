package com.example.gymapp.sync

import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import com.example.gymapp.data.repository.ActivityOnlyWorkoutLocalSnapshot
import com.example.gymapp.data.repository.ActivityOnlyWorkoutSyncBaselineRecord
import com.example.gymapp.data.repository.ActivityOnlyWorkoutSyncJournalRecord
import com.example.gymapp.data.repository.MAX_ACTIVITY_ONLY_REVISION
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.activityOnlyWorkoutDigest
import com.example.gymapp.data.repository.requireValidActivityOnlyWorkoutItem
import com.example.gymapp.data.repository.requireValidActivityOnlyWorkoutItems
import com.example.gymapp.data.repository.threeWayMergeActivityOnlyWorkoutItems
import java.math.BigDecimal
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

private const val MAX_ACTIVITY_ONLY_RESPONSE_BYTES = 1_048_576
private const val MAX_ACTIVITY_ONLY_SYNC_CHANGED_COUNT = 10_000
private const val MAX_ACTIVITY_ONLY_RETRY_AFTER_SECONDS = 600

internal data class ActivityOnlyWorkoutRemoteSnapshot(
    val revision: Long,
    val items: List<ActivityOnlyWorkoutItem>
) {
    val digest: String = activityOnlyWorkoutDigest(items)
}

internal sealed interface ActivityOnlyWorkoutReadResult {
    data class Available(
        val snapshot: ActivityOnlyWorkoutRemoteSnapshot
    ) : ActivityOnlyWorkoutReadResult

    data object Unavailable : ActivityOnlyWorkoutReadResult
}

internal data class ActivityOnlyWorkoutCloudBaseline(
    val ownerUserId: String,
    val revision: Long,
    val items: List<ActivityOnlyWorkoutItem>
) {
    val digest: String = activityOnlyWorkoutDigest(items)

    init {
        require(isCanonicalUuid(ownerUserId))
        require(revision in 0L..MAX_ACTIVITY_ONLY_REVISION)
        requireValidActivityOnlyWorkoutItems(items)
    }

    fun toRecord(): ActivityOnlyWorkoutSyncBaselineRecord =
        ActivityOnlyWorkoutSyncBaselineRecord(
            ownerUserId = ownerUserId,
            revision = revision,
            itemsJson = activityOnlyWorkoutItemsJson(items).toString(),
            itemsDigest = digest
        )

    companion object {
        fun fromRecord(record: ActivityOnlyWorkoutSyncBaselineRecord): ActivityOnlyWorkoutCloudBaseline {
            require(isCanonicalUuid(record.ownerUserId) &&
                record.revision in 0L..MAX_ACTIVITY_ONLY_REVISION &&
                record.itemsDigest.matches(Regex("^[0-9a-f]{64}$"))) {
                "Activity-only workout baseline is invalid."
            }
            val items = parseActivityOnlyWorkoutItemsJson(record.itemsJson)
            require(activityOnlyWorkoutDigest(items) == record.itemsDigest) {
                "Activity-only workout baseline digest is invalid."
            }
            return ActivityOnlyWorkoutCloudBaseline(
                ownerUserId = record.ownerUserId,
                revision = record.revision,
                items = items
            )
        }
    }
}

internal sealed interface ActivityOnlyWorkoutSyncResponse {
    data class Synced(
        val revision: Long,
        val syncedCount: Int,
        val changedCount: Int,
        val replayed: Boolean
    ) : ActivityOnlyWorkoutSyncResponse

    data class Conflict(val revision: Long) : ActivityOnlyWorkoutSyncResponse
    data class RequestConflict(val revision: Long) : ActivityOnlyWorkoutSyncResponse
    data class RevisionExhausted(val revision: Long) : ActivityOnlyWorkoutSyncResponse
    data class RateLimited(val retryAfterSeconds: Int) : ActivityOnlyWorkoutSyncResponse
    data object InvalidPayload : ActivityOnlyWorkoutSyncResponse
}

internal fun parseActivityOnlyWorkoutReadResponse(
    rawResponse: String
): ActivityOnlyWorkoutRemoteSnapshot {
    WorkoutDataLimits.requireSafeJsonEnvelope(rawResponse, MAX_ACTIVITY_ONLY_RESPONSE_BYTES)
    val root = JSONObject(rawResponse)
    root.requireExactKeys(setOf("version", "revision", "items"))
    require(root.requiredExactLong("version") == 1L) {
        "Activity-only workout response version is invalid."
    }
    val revision = root.requiredExactLong("revision")
    require(revision in 0L..MAX_ACTIVITY_ONLY_REVISION) {
        "Activity-only workout revision is invalid."
    }
    val rawItems = root.opt("items") as? JSONArray
        ?: throw IllegalArgumentException("Activity-only workout items are invalid.")
    val items = List(rawItems.length()) { index ->
        val rawItem = rawItems.opt(index) as? JSONObject
            ?: throw IllegalArgumentException("Activity-only workout item is invalid.")
        parseActivityOnlyWorkoutItem(rawItem)
    }
    requireValidActivityOnlyWorkoutItems(items)
    return ActivityOnlyWorkoutRemoteSnapshot(revision = revision, items = items)
}

internal fun activityOnlyWorkoutSyncRequestJson(
    expectedRevision: Long,
    requestId: String,
    items: List<ActivityOnlyWorkoutItem>
): JSONObject {
    require(expectedRevision in 0L..MAX_ACTIVITY_ONLY_REVISION) {
        "Activity-only workout revision is invalid."
    }
    require(isCanonicalUuid(requestId)) { "Activity-only workout request ID is invalid." }
    requireValidActivityOnlyWorkoutItems(items)
    return JSONObject()
        .put("p_expected_revision", expectedRevision)
        .put("p_request_id", requestId)
        .put("p_items", activityOnlyWorkoutItemsJson(items))
        .also { request ->
            WorkoutDataLimits.requireSafeJsonEnvelope(
                request.toString(),
                MAX_ACTIVITY_ONLY_RESPONSE_BYTES
            )
        }
}

internal fun activityOnlyWorkoutItemsJson(items: List<ActivityOnlyWorkoutItem>): JSONArray {
    requireValidActivityOnlyWorkoutItems(items)
    return JSONArray().apply {
        items.forEach { item -> put(activityOnlyWorkoutItemJson(item)) }
    }
}

internal fun parseActivityOnlyWorkoutItemsJson(rawItems: String): List<ActivityOnlyWorkoutItem> {
    WorkoutDataLimits.requireSafeJsonEnvelope(rawItems, MAX_ACTIVITY_ONLY_RESPONSE_BYTES)
    val array = JSONArray(rawItems)
    val items = List(array.length()) { index ->
        val item = array.opt(index) as? JSONObject
            ?: throw IllegalArgumentException("Activity-only workout item is invalid.")
        parseActivityOnlyWorkoutItem(item)
    }
    requireValidActivityOnlyWorkoutItems(items)
    return items
}

internal fun parseActivityOnlyWorkoutSyncResponse(
    rawResponse: String
): ActivityOnlyWorkoutSyncResponse {
    WorkoutDataLimits.requireSafeJsonEnvelope(rawResponse, MAX_ACTIVITY_ONLY_RESPONSE_BYTES)
    val root = JSONObject(rawResponse)
    require(root.opt("version") is Number && root.requiredExactLong("version") == 1L) {
        "Activity-only workout sync version is invalid."
    }
    val status = root.opt("status") as? String
        ?: throw IllegalArgumentException("Activity-only workout sync status is invalid.")
    return when (status) {
        "synced" -> {
            root.requireExactKeys(
                setOf(
                    "version",
                    "status",
                    "revision",
                    "syncedCount",
                    "changedCount",
                    "replayed"
                )
            )
            val revision = root.requiredRevision()
            val syncedCount = root.requiredExactInt("syncedCount", 0..5_000)
            val changedCount = root.requiredExactInt(
                "changedCount",
                0..MAX_ACTIVITY_ONLY_SYNC_CHANGED_COUNT
            )
            val replayed = root.opt("replayed") as? Boolean
                ?: throw IllegalArgumentException(
                    "Activity-only workout replay marker is invalid."
                )
            ActivityOnlyWorkoutSyncResponse.Synced(
                revision = revision,
                syncedCount = syncedCount,
                changedCount = changedCount,
                replayed = replayed
            )
        }

        "conflict" -> {
            root.requireExactKeys(setOf("version", "status", "revision"))
            ActivityOnlyWorkoutSyncResponse.Conflict(root.requiredRevision())
        }

        "request_conflict" -> {
            root.requireExactKeys(setOf("version", "status", "revision"))
            ActivityOnlyWorkoutSyncResponse.RequestConflict(root.requiredRevision())
        }

        "revision_exhausted" -> {
            root.requireExactKeys(setOf("version", "status", "revision"))
            ActivityOnlyWorkoutSyncResponse.RevisionExhausted(root.requiredRevision())
        }

        "rate_limited" -> {
            root.requireExactKeys(setOf("version", "status", "retryAfter"))
            ActivityOnlyWorkoutSyncResponse.RateLimited(
                root.requiredExactInt(
                    "retryAfter",
                    1..MAX_ACTIVITY_ONLY_RETRY_AFTER_SECONDS
                )
            )
        }

        "invalid_payload" -> {
            root.requireExactKeys(setOf("version", "status"))
            ActivityOnlyWorkoutSyncResponse.InvalidPayload
        }

        else -> throw IllegalArgumentException("Activity-only workout sync status is unknown.")
    }
}

/**
 * Synchronizes exact owner-private full snapshots against a durable canonical baseline. A pending
 * outcome-unknown request is always replayed before any remote read or local reconciliation. Every
 * remote race is resolved with a true three-way merge; ambiguous delete/edit and divergent-edit
 * races fail closed rather than resurrecting or overwriting an activity.
 */
internal suspend fun syncActivityOnlyWorkoutSidecar(
    ownerUserId: String,
    baseline: ActivityOnlyWorkoutCloudBaseline?,
    readLocal: suspend () -> ActivityOnlyWorkoutLocalSnapshot,
    reconcileLocal: suspend (List<ActivityOnlyWorkoutItem>) -> ActivityOnlyWorkoutLocalSnapshot,
    readRemote: suspend () -> ActivityOnlyWorkoutRemoteSnapshot,
    writeRemote: suspend (
        expectedRevision: Long,
        requestId: String,
        items: List<ActivityOnlyWorkoutItem>
    ) -> ActivityOnlyWorkoutSyncResponse,
    readJournal: suspend () -> ActivityOnlyWorkoutSyncJournalRecord?,
    persistJournal: suspend (ActivityOnlyWorkoutSyncJournalRecord) -> Unit,
    clearJournal: suspend (ActivityOnlyWorkoutSyncJournalRecord) -> Boolean,
    persistBaseline: suspend (ActivityOnlyWorkoutCloudBaseline) -> Unit,
    forceRemoteRead: Boolean = false,
    requestIdFactory: () -> String = { UUID.randomUUID().toString() }
): ActivityOnlyWorkoutCloudBaseline {
    require(isCanonicalUuid(ownerUserId)) { "Activity-only workout owner is invalid." }
    require(baseline == null || baseline.ownerUserId == ownerUserId) {
        "Activity-only workout baseline belongs to another account."
    }

    suspend fun newJournal(
        expectedRevision: Long,
        items: List<ActivityOnlyWorkoutItem>,
        excludedRequestId: String? = null
    ): ActivityOnlyWorkoutSyncJournalRecord {
        val requestId = requestIdFactory().also {
            require(isCanonicalUuid(it) && it != excludedRequestId) {
                "Activity-only workout request ID is invalid."
            }
        }
        val record = ActivityOnlyWorkoutSyncJournalRecord(
            ownerUserId = ownerUserId,
            expectedRevision = expectedRevision,
            requestId = requestId,
            itemsJson = activityOnlyWorkoutItemsJson(items).toString(),
            itemsDigest = activityOnlyWorkoutDigest(items)
        )
        persistJournal(record)
        return record
    }

    fun journalItems(record: ActivityOnlyWorkoutSyncJournalRecord): List<ActivityOnlyWorkoutItem> {
        require(record.ownerUserId == ownerUserId &&
            record.expectedRevision in 0L..MAX_ACTIVITY_ONLY_REVISION &&
            isCanonicalUuid(record.requestId) &&
            record.itemsDigest.matches(Regex("^[0-9a-f]{64}$"))) {
            "Activity-only workout sync journal is invalid."
        }
        return parseActivityOnlyWorkoutItemsJson(record.itemsJson).also { items ->
            require(activityOnlyWorkoutDigest(items) == record.itemsDigest) {
                "Activity-only workout sync journal digest is invalid."
            }
        }
    }

    suspend fun rememberConfirmed(
        confirmed: ActivityOnlyWorkoutCloudBaseline
    ): ActivityOnlyWorkoutCloudBaseline {
        persistBaseline(confirmed)
        return confirmed
    }

    suspend fun sendOnce(
        record: ActivityOnlyWorkoutSyncJournalRecord,
        items: List<ActivityOnlyWorkoutItem>,
        currentBaseline: ActivityOnlyWorkoutCloudBaseline?
    ): ActivityOnlyWorkoutCloudBaseline = when (val response = writeRemote(
        record.expectedRevision,
        record.requestId,
        items
    )) {
        is ActivityOnlyWorkoutSyncResponse.Synced -> {
            require(response.syncedCount == items.size) {
                "Activity-only workout sync count is invalid."
            }
            check(clearJournal(record)) {
                "Activity-only workout committed journal could not be cleared."
            }
            rememberConfirmed(
                ActivityOnlyWorkoutCloudBaseline(
                    ownerUserId = ownerUserId,
                    revision = response.revision,
                    items = items
                )
            )
        }

        is ActivityOnlyWorkoutSyncResponse.Conflict -> {
            val exactBase = checkNotNull(currentBaseline) {
                "Activity-only workout conflict has no exact durable baseline."
            }
            require(exactBase.ownerUserId == record.ownerUserId &&
                exactBase.revision == record.expectedRevision) {
                "Activity-only workout journal does not match its exact durable baseline."
            }
            val remote = readRemote()
            require(remote.revision == response.revision) {
                "Activity-only workout conflict revision changed while reading."
            }
            val resolvedAttempt = threeWayMergeActivityOnlyWorkoutItems(
                base = exactBase.items,
                local = items,
                remote = remote.items
            )
            check(clearJournal(record)) {
                "Activity-only workout conflict journal could not be cleared."
            }
            val remoteBaseline = rememberConfirmed(
                ActivityOnlyWorkoutCloudBaseline(
                    ownerUserId = ownerUserId,
                    revision = remote.revision,
                    items = remote.items
                )
            )
            val currentLocal = readLocal()
            val resolvedWithNewerLocal = threeWayMergeActivityOnlyWorkoutItems(
                base = items,
                local = currentLocal.items,
                remote = resolvedAttempt
            )
            val canonical = reconcileLocal(resolvedWithNewerLocal)
            if (canonical.digest == remoteBaseline.digest) {
                remoteBaseline
            } else {
                val retryJournal = newJournal(
                    expectedRevision = remoteBaseline.revision,
                    items = canonical.items,
                    excludedRequestId = record.requestId
                )
                when (val retry = writeRemote(
                    retryJournal.expectedRevision,
                    retryJournal.requestId,
                    canonical.items
                )) {
                    is ActivityOnlyWorkoutSyncResponse.Synced -> {
                        require(retry.syncedCount == canonical.items.size) {
                            "Activity-only workout sync count is invalid."
                        }
                        check(clearJournal(retryJournal)) {
                            "Activity-only workout committed journal could not be cleared."
                        }
                        rememberConfirmed(
                            ActivityOnlyWorkoutCloudBaseline(
                                ownerUserId = ownerUserId,
                                revision = retry.revision,
                                items = canonical.items
                            )
                        )
                    }

                    is ActivityOnlyWorkoutSyncResponse.Conflict -> {
                        check(clearJournal(retryJournal)) {
                            "Activity-only workout retry journal could not be cleared."
                        }
                        error("Activity-only workout conflict retry raced another writer.")
                    }

                    else -> error("Activity-only workout conflict retry did not commit.")
                }
            }
        }

        else -> error("Activity-only workout synchronization was rejected.")
    }

    var currentBaseline = baseline
    readJournal()?.let { pending ->
        currentBaseline = sendOnce(
            record = pending,
            items = journalItems(pending),
            currentBaseline = currentBaseline
        )
    }

    if (forceRemoteRead || currentBaseline == null) {
        val remote = readRemote()
        val local = readLocal()
        val mergedItems = threeWayMergeActivityOnlyWorkoutItems(
            base = currentBaseline?.items.orEmpty(),
            local = local.items,
            remote = remote.items
        )
        val canonical = reconcileLocal(mergedItems)
        currentBaseline = rememberConfirmed(
            ActivityOnlyWorkoutCloudBaseline(
                ownerUserId = ownerUserId,
                revision = remote.revision,
                items = remote.items
            )
        )
        if (canonical.digest == currentBaseline.digest) return currentBaseline
    }

    val local = readLocal()
    if (local.digest == currentBaseline.digest) return currentBaseline
    val journal = newJournal(currentBaseline.revision, local.items)
    return sendOnce(journal, local.items, currentBaseline)
}

private fun parseActivityOnlyWorkoutItem(root: JSONObject): ActivityOnlyWorkoutItem {
    root.requireExactKeys(
        required = setOf("workoutStartedAt", "durationSeconds", "gymCalories"),
        optional = setOf(
            "garminCalories",
            "averageHeartRate",
            "maximumHeartRate",
            "endingHeartRateZone",
            "note"
        )
    )
    val item = ActivityOnlyWorkoutItem(
        workoutStartedAt = root.requiredExactLong("workoutStartedAt"),
        durationSeconds = root.requiredExactLong("durationSeconds"),
        gymCalories = root.requiredExactDouble("gymCalories").let { value ->
            if (value == 0.0) 0.0 else value
        },
        garminCalories = root.optionalExactInt("garminCalories"),
        averageHeartRate = root.optionalExactInt("averageHeartRate"),
        maximumHeartRate = root.optionalExactInt("maximumHeartRate"),
        endingHeartRateZone = root.optionalExactInt("endingHeartRateZone"),
        note = root.optionalStrictString("note")
    )
    requireValidActivityOnlyWorkoutItem(item)
    return item
}

private fun activityOnlyWorkoutItemJson(item: ActivityOnlyWorkoutItem): JSONObject {
    requireValidActivityOnlyWorkoutItem(item)
    return JSONObject()
        .put("workoutStartedAt", item.workoutStartedAt)
        .put("durationSeconds", item.durationSeconds)
        .put("gymCalories", if (item.gymCalories == 0.0) 0.0 else item.gymCalories)
        .apply {
            item.garminCalories?.let { put("garminCalories", it) }
            item.averageHeartRate?.let { put("averageHeartRate", it) }
            item.maximumHeartRate?.let { put("maximumHeartRate", it) }
            item.endingHeartRateZone?.let { put("endingHeartRateZone", it) }
            item.note?.let { put("note", it) }
        }
}

private fun JSONObject.requireExactKeys(
    required: Set<String>,
    optional: Set<String> = emptySet()
) {
    val actual = keys().asSequence().toSet()
    require(actual.containsAll(required) && actual.all { it in required || it in optional }) {
        "Activity-only workout response fields are invalid."
    }
}

private fun JSONObject.requiredExactLong(key: String): Long {
    val raw = opt(key)
    require(raw is Number) { "Activity-only workout number is invalid." }
    return runCatching { BigDecimal(raw.toString()).longValueExact() }
        .getOrElse { throw IllegalArgumentException("Activity-only workout integer is invalid.") }
}

private fun JSONObject.requiredExactDouble(key: String): Double {
    val raw = opt(key)
    require(raw is Number) { "Activity-only workout number is invalid." }
    return runCatching { BigDecimal(raw.toString()).toDouble() }
        .getOrElse { throw IllegalArgumentException("Activity-only workout number is invalid.") }
        .also { require(it.isFinite()) { "Activity-only workout number is invalid." } }
}

private fun JSONObject.requiredExactInt(key: String, range: IntRange): Int {
    val value = requiredExactLong(key)
    require(value in range.first.toLong()..range.last.toLong()) {
        "Activity-only workout integer is outside its range."
    }
    return value.toInt()
}

private fun JSONObject.optionalExactInt(key: String): Int? {
    if (!has(key)) return null
    require(!isNull(key)) { "Activity-only workout optional number is invalid." }
    val value = requiredExactLong(key)
    require(value in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong())
    return value.toInt()
}

private fun JSONObject.optionalStrictString(key: String): String? {
    if (!has(key)) return null
    require(!isNull(key)) { "Activity-only workout optional text is invalid." }
    return opt(key) as? String
        ?: throw IllegalArgumentException("Activity-only workout optional text is invalid.")
}

private fun JSONObject.requiredRevision(): Long = requiredExactLong("revision").also { revision ->
    require(revision in 0L..MAX_ACTIVITY_ONLY_REVISION) {
        "Activity-only workout revision is invalid."
    }
}

private fun isCanonicalUuid(value: String): Boolean =
    runCatching { UUID.fromString(value).toString() == value }.getOrDefault(false)
