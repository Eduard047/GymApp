package com.example.gymapp.wearsync

import android.content.Context
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.databaseName
import java.security.MessageDigest
import java.util.UUID

internal data class PhoneWearAccountBinding(
    val ownerId: String,
    val accountGeneration: Long,
    val signedOut: Boolean
)

internal data class PhoneWearTrustedSource(
    val nodeId: String,
    val ownerId: String
)

/**
 * Device-local authority for the Wear peer and account generation.
 *
 * Raw account identifiers are never placed on the wire or in this preference file. Account
 * generations are global and monotonically increasing so a watch cannot replay a binding after
 * logout, account switching, or a new cloud login generation.
 */
internal class PhoneWearBindingManager(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val lock = Any()

    fun synchronizeSession(session: AccountSession?): PhoneWearAccountBinding = synchronized(lock) {
        val identity = identityFor(session)
        val ownerId = ownerIdFor(session)
        val fingerprint = sha256Hex(identity.toByteArray(Charsets.UTF_8))
        val storedFingerprint = prefs.getString(KEY_ACTIVE_FINGERPRINT, null)
        if (storedFingerprint != fingerprint) {
            val lastGeneration = prefs.getLong(KEY_LAST_GENERATION, 0L)
            check(lastGeneration in 0L until PhoneWearPaths.MAX_PROTOCOL_COUNTER) {
                "Wear account generation is exhausted or corrupted"
            }
            val nextGeneration = lastGeneration + 1L
            check(
                prefs.edit()
                    .putString(KEY_ACTIVE_FINGERPRINT, fingerprint)
                    .putString(KEY_ACTIVE_OWNER_ID, ownerId)
                    .putLong(KEY_ACTIVE_GENERATION, nextGeneration)
                    .putLong(KEY_LAST_GENERATION, nextGeneration)
                    .putLong(KEY_FULL_SYNC_REVISION, 0L)
                    .commit()
            ) { "Could not persist Wear account binding" }
        }
        val storedOwner = prefs.getString(KEY_ACTIVE_OWNER_ID, null)
        val generation = prefs.getLong(KEY_ACTIVE_GENERATION, 0L)
        check(storedOwner == ownerId && generation in 1L..PhoneWearPaths.MAX_PROTOCOL_COUNTER) {
            "Wear account binding is inconsistent"
        }
        PhoneWearAccountBinding(
            ownerId = ownerId,
            accountGeneration = generation,
            signedOut = session == null
        )
    }

    fun isCurrent(binding: PhoneWearAccountBinding, session: AccountSession?): Boolean {
        return runCatching { synchronizeSession(session) == binding }.getOrDefault(false)
    }

    fun nextFullSyncRevision(expected: PhoneWearAccountBinding): Long = synchronized(lock) {
        val ownerId = prefs.getString(KEY_ACTIVE_OWNER_ID, null)
        val generation = prefs.getLong(KEY_ACTIVE_GENERATION, 0L)
        check(ownerId == expected.ownerId && generation == expected.accountGeneration) {
            "Wear account changed during sync"
        }
        val currentRevision = prefs.getLong(KEY_FULL_SYNC_REVISION, 0L)
        check(currentRevision in 0L until PhoneWearPaths.MAX_PROTOCOL_COUNTER) {
            "Wear sync revision is exhausted or corrupted"
        }
        val nextRevision = currentRevision + 1L
        check(prefs.edit().putLong(KEY_FULL_SYNC_REVISION, nextRevision).commit()) {
            "Could not persist Wear sync revision"
        }
        nextRevision
    }

    /**
     * Pins the first peer only when Google Play Services reports exactly one connected node.
     * Once pinned, an unexpected node always fails closed; replacement needs an explicit future
     * re-pair flow instead of silently trusting whichever device speaks next.
     */
    fun authorizeSource(
        sourceNodeId: String,
        connectedNodeIds: Set<String>,
        currentBinding: PhoneWearAccountBinding
    ): Boolean = synchronized(lock) {
        if (!isValidNodeId(sourceNodeId)) return false
        if (
            connectedNodeIds.isEmpty() ||
            connectedNodeIds.size > MAX_CONNECTED_NODES ||
            connectedNodeIds.any { !isValidNodeId(it) } ||
            sourceNodeId !in connectedNodeIds
        ) {
            return false
        }
        val stored = prefs.getString(KEY_SOURCE_NODE_ID, null)
        if (stored != null) {
            return isValidNodeId(stored) && stored == sourceNodeId
        }
        if (connectedNodeIds.size != 1 || currentBinding.signedOut) return false
        return prefs.edit()
            .putString(KEY_SOURCE_NODE_ID, sourceNodeId)
            .putString(KEY_SOURCE_OWNER_ID, currentBinding.ownerId)
            .commit()
    }

    fun pinnedSource(): PhoneWearTrustedSource? = synchronized(lock) {
        val nodeId = prefs.getString(KEY_SOURCE_NODE_ID, null)?.takeIf(::isValidNodeId) ?: return null
        val ownerId = prefs.getString(KEY_SOURCE_OWNER_ID, null)
            ?.takeIf { it.matches(Regex("^[0-9a-f]{64}$")) }
            ?: return null
        PhoneWearTrustedSource(nodeId, ownerId)
    }

    fun pinnedSourceNodeId(): String? = synchronized(lock) {
        prefs.getString(KEY_SOURCE_NODE_ID, null)?.takeIf(::isValidNodeId)
    }

    fun fastSourceMayBeTrusted(sourceNodeId: String): Boolean = synchronized(lock) {
        if (!isValidNodeId(sourceNodeId)) return false
        val pinned = prefs.getString(KEY_SOURCE_NODE_ID, null)
        pinned == null || (isValidNodeId(pinned) && pinned == sourceNodeId)
    }

    fun isPinnedToOwner(sourceNodeId: String, ownerId: String): Boolean = synchronized(lock) {
        val source = pinnedSource() ?: return false
        source.nodeId == sourceNodeId && source.ownerId == ownerId
    }

    private fun identityFor(session: AccountSession?): String {
        return when (session) {
            null -> SIGNED_OUT_IDENTITY
            is AccountSession.Cloud -> "cloud:${session.userId}:${session.sessionGeneration}"
            is AccountSession.Local -> {
                val stableIdentity = session.databaseName()
                "local:$stableIdentity:${stableLocalAccountId(stableIdentity)}"
            }
        }
    }

    private fun ownerIdFor(session: AccountSession?): String {
        val ownerIdentity = when (session) {
            null -> SIGNED_OUT_OWNER
            is AccountSession.Cloud -> "cloud:${session.userId}"
            is AccountSession.Local -> "local:${session.databaseName()}"
        }
        return sha256Hex(ownerIdentity.toByteArray(Charsets.UTF_8))
    }

    private fun stableLocalAccountId(normalizedName: String): String {
        val key = KEY_LOCAL_ACCOUNT_ID_PREFIX + sha256Hex(normalizedName.toByteArray(Charsets.UTF_8))
        prefs.getString(key, null)?.takeIf { stored ->
            runCatching { UUID.fromString(stored).toString() == stored }.getOrDefault(false)
        }?.let { return it }
        val created = UUID.randomUUID().toString()
        check(prefs.edit().putString(key, created).commit()) {
            "Could not persist local Wear account identity"
        }
        return created
    }

    private fun isValidNodeId(value: String): Boolean {
        return value.isNotBlank() && value.length <= MAX_NODE_ID_LENGTH && value.none(Char::isISOControl)
    }

    private fun sha256Hex(value: ByteArray): String {
        return MessageDigest.getInstance("SHA-256")
            .digest(value)
            .joinToString(separator = "") { byte -> "%02x".format(byte) }
    }

    private companion object {
        const val PREFS_NAME = "phone_wear_sync"
        const val KEY_SOURCE_NODE_ID = "source_node_id"
        const val KEY_SOURCE_OWNER_ID = "source_owner_id"
        const val KEY_ACTIVE_FINGERPRINT = "active_fingerprint"
        const val KEY_ACTIVE_OWNER_ID = "active_owner_id"
        const val KEY_ACTIVE_GENERATION = "active_generation"
        const val KEY_LAST_GENERATION = "last_generation"
        const val KEY_FULL_SYNC_REVISION = "full_sync_revision"
        const val KEY_LOCAL_ACCOUNT_ID_PREFIX = "local_account_id_"
        const val MAX_NODE_ID_LENGTH = 256
        const val MAX_CONNECTED_NODES = 8
        const val SIGNED_OUT_IDENTITY = "GymAppPhoneWearSignedOutSessionV1"
        const val SIGNED_OUT_OWNER = "GymAppPhoneWearSignedOutOwnerV1"
    }
}
