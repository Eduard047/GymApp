package com.example.gymapp.auth

import android.content.Context
import android.content.SharedPreferences

private const val CLOUD_ACCOUNT_DELETION_JOURNAL_PREFERENCES =
    "gym_cloud_account_deletion_journal"
private const val CLOUD_ACCOUNT_DELETION_JOURNAL_KEY = "pending_owner_v1"
private const val CLOUD_ACCOUNT_DELETION_JOURNAL_PREFIX = "v2:"
private const val MAX_PENDING_CLOUD_ACCOUNT_DELETIONS = 16
private const val CLOUD_ACCOUNT_DELETION_RECORD_LENGTH = 76
private val CLOUD_ACCOUNT_DELETION_USER_ID_PATTERN = Regex(
    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
)
private val cloudAccountDeletionJournalLock = Any()

internal class PendingCloudAccountDeletion private constructor(
    val userId: String,
    val sessionGeneration: String
) {
    val databaseName: String = "cloud_$userId"

    val encoded: String =
        "$CLOUD_ACCOUNT_DELETION_JOURNAL_PREFIX$userId:$sessionGeneration"

    override fun equals(other: Any?): Boolean =
        other is PendingCloudAccountDeletion &&
            other.userId == userId &&
            other.sessionGeneration == sessionGeneration

    override fun hashCode(): Int = 31 * userId.hashCode() + sessionGeneration.hashCode()

    companion object {
        fun fromSession(session: AccountSession.Cloud): PendingCloudAccountDeletion? =
            fromOwner(session.userId, session.sessionGeneration)

        fun fromOwner(
            userId: String,
            sessionGeneration: String
        ): PendingCloudAccountDeletion? {
            if (!CLOUD_ACCOUNT_DELETION_USER_ID_PATTERN.matches(userId) ||
                !CLOUD_ACCOUNT_DELETION_USER_ID_PATTERN.matches(sessionGeneration)
            ) {
                return null
            }
            // Preserve the exact identifier spelling because older local database names were
            // derived from it verbatim. UUID comparison remains case-insensitive at owner checks.
            return PendingCloudAccountDeletion(userId, sessionGeneration)
        }

        fun decode(raw: String?): PendingCloudAccountDeletion? {
            if (raw == null || !raw.startsWith(CLOUD_ACCOUNT_DELETION_JOURNAL_PREFIX)) {
                return null
            }
            val parts = raw.removePrefix(CLOUD_ACCOUNT_DELETION_JOURNAL_PREFIX).split(':')
            if (parts.size != 2) return null
            return fromOwner(parts[0], parts[1])
                ?.takeIf { it.encoded == raw }
        }
    }
}

internal interface CloudAccountDeletionJournalStorage {
    fun read(): String?
    fun write(value: String): Boolean
    fun clear(): Boolean
}

internal data class CloudAccountDeletionJournalSnapshot(
    val records: List<PendingCloudAccountDeletion>,
    val unreadable: Boolean
)

private class SharedPreferencesCloudAccountDeletionJournalStorage(
    private val preferences: SharedPreferences
) : CloudAccountDeletionJournalStorage {
    override fun read(): String? = preferences.getString(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY, null)

    override fun write(value: String): Boolean = preferences.edit()
        .putString(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY, value)
        .commit()

    override fun clear(): Boolean = preferences.edit()
        .remove(CLOUD_ACCOUNT_DELETION_JOURNAL_KEY)
        .commit()
}

/**
 * Records the owner immediately before the confirmed delete request may cross the network. The
 * record intentionally contains only the owner UUID and the opaque local session generation needed
 * to address owner-bound timer/pairing state. It contains no token, email, display name, workout
 * content, or device ID.
 */
internal class CloudAccountDeletionJournal(
    private val storage: CloudAccountDeletionJournalStorage
) {
    constructor(context: Context) : this(
        SharedPreferencesCloudAccountDeletionJournalStorage(
            context.applicationContext.getSharedPreferences(
                CLOUD_ACCOUNT_DELETION_JOURNAL_PREFERENCES,
                Context.MODE_PRIVATE
            )
        )
    )

    fun snapshot(): CloudAccountDeletionJournalSnapshot = synchronized(
        cloudAccountDeletionJournalLock
    ) {
        val raw = storage.read()
        val records = decodeRecords(raw)
        CloudAccountDeletionJournalSnapshot(
            records = records.orEmpty(),
            unreadable = raw != null && records == null
        )
    }

    fun pending(): List<PendingCloudAccountDeletion> = snapshot().records

    fun markPending(session: AccountSession.Cloud): Boolean {
        val record = PendingCloudAccountDeletion.fromSession(session) ?: return false
        return synchronized(cloudAccountDeletionJournalLock) {
            val raw = storage.read()
            val records = decodeRecords(raw) ?: return@synchronized false
            if (records.any { it.userId.equals(record.userId, ignoreCase = true) }) {
                return@synchronized true
            }
            if (records.size >= MAX_PENDING_CLOUD_ACCOUNT_DELETIONS) {
                return@synchronized false
            }
            storage.write((records + record).joinToString("\n", transform = { it.encoded }))
        }
    }

    fun clear(expected: PendingCloudAccountDeletion): Boolean = synchronized(
        cloudAccountDeletionJournalLock
    ) {
        val raw = storage.read()
        val records = decodeRecords(raw) ?: return@synchronized false
        if (records.none { it.userId.equals(expected.userId, ignoreCase = true) }) {
            return@synchronized true
        }
        val remaining = records.filterNot {
            it.userId.equals(expected.userId, ignoreCase = true)
        }
        if (remaining.isEmpty()) storage.clear()
        else storage.write(remaining.joinToString("\n", transform = { it.encoded }))
    }

    private fun decodeRecords(raw: String?): List<PendingCloudAccountDeletion>? {
        if (raw == null) return emptyList()
        if (raw.isEmpty() ||
            raw.length > MAX_PENDING_CLOUD_ACCOUNT_DELETIONS *
            (CLOUD_ACCOUNT_DELETION_RECORD_LENGTH + 1)
        ) {
            return null
        }
        val encodedRecords = raw.split('\n')
        if (encodedRecords.size !in 1..MAX_PENDING_CLOUD_ACCOUNT_DELETIONS) return null
        val records = encodedRecords.map { encoded ->
            PendingCloudAccountDeletion.decode(encoded) ?: return null
        }
        return records.takeIf { values ->
            values.distinctBy { it.userId.lowercase() }.size == values.size
        }
    }
}

internal fun shouldSuppressRestoredCloudSession(
    journal: CloudAccountDeletionJournalSnapshot,
    restoredUserId: String
): Boolean = journal.unreadable || journal.records.any { pending ->
    pending.userId.equals(restoredUserId, ignoreCase = true)
}

internal suspend fun recoverPendingCloudAccountDeletion(
    record: PendingCloudAccountDeletion,
    clearRoom: suspend () -> Unit,
    clearBaseline: () -> Boolean,
    clearTrainingProfile: () -> Boolean,
    clearSyncStatus: () -> Boolean,
    clearCustomMedia: () -> Boolean,
    clearBackupShares: () -> Boolean,
    clearRestTimers: () -> Boolean,
    clearLiveState: () -> Boolean,
    clearGarminState: () -> Boolean,
    clearJournal: (PendingCloudAccountDeletion) -> Boolean
): Int {
    var failures = 0
    if (runCatching { clearRoom() }.isFailure) failures += 1
    if (runCatching { check(clearBaseline()) }.isFailure) failures += 1
    if (runCatching { check(clearTrainingProfile()) }.isFailure) failures += 1
    if (runCatching { check(clearSyncStatus()) }.isFailure) failures += 1
    if (runCatching { check(clearCustomMedia()) }.isFailure) failures += 1
    if (runCatching { check(clearBackupShares()) }.isFailure) failures += 1
    if (runCatching { check(clearRestTimers()) }.isFailure) failures += 1
    if (runCatching { check(clearLiveState()) }.isFailure) failures += 1
    if (runCatching { check(clearGarminState()) }.isFailure) failures += 1
    if (failures == 0 && runCatching { check(clearJournal(record)) }.isFailure) {
        failures += 1
    }
    return failures
}
