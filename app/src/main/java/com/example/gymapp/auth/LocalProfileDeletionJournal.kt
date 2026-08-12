package com.example.gymapp.auth

import android.content.Context
import org.json.JSONObject
import java.util.UUID

internal const val LOCAL_PROFILE_DELETION_JOURNAL_PREFERENCES =
    "gym_local_profile_deletion_journal_v1"

internal data class PendingLocalProfileDeletion(
    val profileId: String,
    val displayName: String,
    val logicalDatabaseName: String,
    val physicalDatabaseName: String
) {
    companion object {
        fun create(
            profile: SavedLocalProfile,
            physicalDatabaseName: String
        ): PendingLocalProfileDeletion? {
            val id = runCatching { UUID.fromString(profile.id).toString() }.getOrNull()
                ?: return null
            val name = normalizedLocalDisplayNameOrNull(profile.displayName) ?: return null
            val logical = localDatabaseLogicalName(name) ?: return null
            val legacy = legacyLocalDatabaseName(name) ?: return null
            if (physicalDatabaseName != logical && physicalDatabaseName != legacy) return null
            return PendingLocalProfileDeletion(id, name, logical, physicalDatabaseName)
        }

        fun decode(raw: String?): PendingLocalProfileDeletion? {
            if (raw == null || raw.toByteArray(Charsets.UTF_8).size > MAX_RECORD_BYTES) return null
            return runCatching {
                val value = JSONObject(raw)
                require(value.length() == 4)
                create(
                    profile = SavedLocalProfile(
                        id = value.getString(KEY_PROFILE_ID),
                        displayName = value.getString(KEY_DISPLAY_NAME)
                    ),
                    physicalDatabaseName = value.getString(KEY_PHYSICAL_DATABASE)
                )?.takeIf { record ->
                    record.logicalDatabaseName == value.getString(KEY_LOGICAL_DATABASE) &&
                        record.encode() == raw
                }
            }.getOrNull()
        }
    }

    fun encode(): String = JSONObject()
        .put(KEY_PROFILE_ID, profileId)
        .put(KEY_DISPLAY_NAME, displayName)
        .put(KEY_LOGICAL_DATABASE, logicalDatabaseName)
        .put(KEY_PHYSICAL_DATABASE, physicalDatabaseName)
        .toString()
}

internal data class LocalProfileDeletionJournalSnapshot(
    val record: PendingLocalProfileDeletion?,
    val unreadable: Boolean
)

internal open class LocalProfileDeletionJournal(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        LOCAL_PROFILE_DELETION_JOURNAL_PREFERENCES,
        Context.MODE_PRIVATE
    )

    open fun snapshot(): LocalProfileDeletionJournalSnapshot = synchronized(LOCK) {
        val present = preferences.contains(KEY_PENDING)
        val raw = preferences.all[KEY_PENDING] as? String
        val record = PendingLocalProfileDeletion.decode(raw)
        LocalProfileDeletionJournalSnapshot(record, present && record == null)
    }

    open fun pending(): PendingLocalProfileDeletion? = snapshot().record

    open fun mark(record: PendingLocalProfileDeletion): Boolean = synchronized(LOCK) {
        val snapshot = snapshot()
        if (snapshot.unreadable) return@synchronized false
        if (snapshot.record != null) return@synchronized snapshot.record == record
        val encoded = record.encode()
        encoded.toByteArray(Charsets.UTF_8).size <= MAX_RECORD_BYTES &&
            preferences.edit().putString(KEY_PENDING, encoded).commit()
    }

    open fun clear(expected: PendingLocalProfileDeletion): Boolean = synchronized(LOCK) {
        val snapshot = snapshot()
        if (snapshot.unreadable) return@synchronized false
        if (snapshot.record == null) return@synchronized true
        if (snapshot.record != expected) return@synchronized false
        preferences.edit().remove(KEY_PENDING).commit()
    }

    private companion object {
        val LOCK = Any()
    }
}

internal fun recoverPendingLocalProfileDeletion(
    record: PendingLocalProfileDeletion,
    clearLiveSidecar: () -> Boolean,
    clearDatabase: (PendingLocalProfileDeletion) -> Boolean,
    clearTrainingProfile: (String) -> Boolean,
    clearTrainingGuidance: (String) -> Boolean,
    clearCustomMedia: (String) -> Boolean,
    clearBackupShares: (String) -> Boolean,
    clearRestTimers: (String) -> Boolean,
    finalizeIdentity: (PendingLocalProfileDeletion) -> Boolean
): Boolean {
    if (!clearLiveSidecar()) return false
    val cleanupSucceeded = listOf(
        clearDatabase(record),
        clearTrainingProfile(record.logicalDatabaseName),
        clearTrainingGuidance(record.logicalDatabaseName),
        clearCustomMedia(record.logicalDatabaseName),
        clearBackupShares(record.logicalDatabaseName),
        clearRestTimers(record.logicalDatabaseName)
    ).all { it }
    return cleanupSucceeded && finalizeIdentity(record)
}

private const val KEY_PENDING = "pending_v1"
private const val KEY_PROFILE_ID = "profileId"
private const val KEY_DISPLAY_NAME = "displayName"
private const val KEY_LOGICAL_DATABASE = "logicalDatabaseName"
private const val KEY_PHYSICAL_DATABASE = "physicalDatabaseName"
private const val MAX_RECORD_BYTES = 2 * 1_024
