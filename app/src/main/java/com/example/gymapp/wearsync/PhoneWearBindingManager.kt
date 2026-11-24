package com.example.gymapp.wearsync

import android.content.Context
import android.content.SharedPreferences
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.databaseName
import java.security.MessageDigest
import java.util.UUID

internal data class PhoneWearAccountBinding(
    val ownerId: String,
    val accountGeneration: Long,
    val signedOut: Boolean,
    /**
     * Random id of this phone install, carried in every phone-to-watch envelope. Generations and
     * revisions restart after a reinstall or "Clear storage"; a new epoch tells the watch that the
     * counters belong to a new authority instead of being a replay of the old one.
     */
    val authorityEpoch: String
)

internal data class PhoneWearTrustedSource(
    val nodeId: String,
    val ownerId: String
)

/**
 * Whether a watch's own "unlink" message may release the binding: it must come from the pinned
 * node and name exactly the phone's current account (owner and generation), or no account at all
 * while the phone is signed out. Anything else is stale or foreign and is ignored.
 */
internal fun phoneWearWatchUnlinkAccepted(
    pinnedNode: Boolean,
    envelopeOwnerId: String?,
    envelopeAccountGeneration: Long?,
    binding: PhoneWearAccountBinding
): Boolean {
    if (!pinnedNode) return false
    if (binding.signedOut) return envelopeOwnerId == null && envelopeAccountGeneration == null
    return envelopeOwnerId == binding.ownerId &&
        envelopeAccountGeneration == binding.accountGeneration
}

/**
 * Device-local authority for the Wear peer and account generation.
 *
 * Raw account identifiers are never placed on the wire or in this preference file. Account
 * generations are global and monotonically increasing so a watch cannot replay a binding after
 * logout, account switching, or a new cloud login generation.
 */
internal class PhoneWearBindingManager(private val prefs: SharedPreferences) {
    constructor(context: Context) : this(
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    )

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
            signedOut = session == null,
            authorityEpoch = authorityEpochLocked()
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
        currentBinding: PhoneWearAccountBinding,
        linkIntent: Boolean = false
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
            if (!isValidNodeId(stored) || stored != sourceNodeId) return false
            // The pin is the watch NODE; the owner is whatever account is active on the phone. After
            // an account switch the watch rebinds to the new owner, so the stored owner follows it.
            if (!currentBinding.signedOut) {
                val storedOwner = prefs.getString(KEY_SOURCE_OWNER_ID, null)
                if (storedOwner != currentBinding.ownerId) {
                    return prefs.edit()
                        .putString(KEY_SOURCE_OWNER_ID, currentBinding.ownerId)
                        .commit()
                }
            }
            return true
        }
        if (connectedNodeIds.size != 1 || currentBinding.signedOut) return false
        // A watch the user unlinked here is pinned again only by its own explicit link request
        // ("Link to phone" on the watch), never by simply opening its app.
        if (prefs.getString(KEY_UNLINKED_NODE_ID, null) == sourceNodeId && !linkIntent) return false
        return prefs.edit()
            .putString(KEY_SOURCE_NODE_ID, sourceNodeId)
            .putString(KEY_SOURCE_OWNER_ID, currentBinding.ownerId)
            .remove(KEY_UNLINKED_NODE_ID)
            .commit()
    }

    fun pinnedSource(): PhoneWearTrustedSource? = synchronized(lock) {
        val nodeId = prefs.getString(KEY_SOURCE_NODE_ID, null)?.takeIf(::isValidNodeId) ?: return null
        val ownerId = prefs.getString(KEY_SOURCE_OWNER_ID, null)
            ?.takeIf { it.matches(Regex("^[0-9a-f]{64}$")) }
            ?: return null
        PhoneWearTrustedSource(nodeId, ownerId)
    }

    /**
     * The user's "Unlink watch": forgets the pinned watch node, its owner, its name, the link
     * proof and the plans cached for it, and remembers the node as unlinked by the user so that it
     * is not pinned again without an explicit link request. Account generations, sync revisions,
     * workouts and receipts stay untouched.
     */
    fun clearPinnedSource(): Boolean = synchronized(lock) {
        val pinned = prefs.getString(KEY_SOURCE_NODE_ID, null)?.takeIf(::isValidNodeId)
        val editor = prefs.edit()
            .remove(KEY_SOURCE_NODE_ID)
            .remove(KEY_SOURCE_OWNER_ID)
            .remove(KEY_WATCH_NAME)
            .remove(KEY_LINK_PROOF_AT)
            .remove(KEY_LINK_PROOF_OWNER_ID)
            .remove(KEY_LINK_PROOF_GENERATION)
        prefs.all.keys
            .filter { it.startsWith(KEY_PLAN_CACHE_PREFIX) }
            .forEach { editor.remove(it) }
        if (pinned != null) editor.putString(KEY_UNLINKED_NODE_ID, pinned)
        editor.commit()
    }

    /** True for the watch node the user unlinked and that has not asked to link again. */
    fun isUnlinkedNode(sourceNodeId: String): Boolean = synchronized(lock) {
        isValidNodeId(sourceNodeId) && prefs.getString(KEY_UNLINKED_NODE_ID, null) == sourceNodeId
    }

    /** Remembers the Data Layer name of the pinned watch so the card can show it while offline. */
    fun rememberWatchName(sourceNodeId: String, displayName: String?): Boolean = synchronized(lock) {
        if (prefs.getString(KEY_SOURCE_NODE_ID, null) != sourceNodeId) return false
        val name = displayName
            ?.filterNot(Char::isISOControl)
            ?.trim()
            ?.take(MAX_WATCH_NAME_LENGTH)
            ?.takeIf { it.isNotEmpty() }
            ?: return false
        if (prefs.getString(KEY_WATCH_NAME, null) == name) return true
        prefs.edit().putString(KEY_WATCH_NAME, name).commit()
    }

    fun pinnedWatchName(): String? = synchronized(lock) {
        if (prefs.getString(KEY_SOURCE_NODE_ID, null) == null) return null
        prefs.getString(KEY_WATCH_NAME, null)?.takeIf { it.isNotBlank() && it.length <= MAX_WATCH_NAME_LENGTH }
    }

    /**
     * Records that the pinned watch just presented exactly this phone's current owner and
     * generation, i.e. it follows this phone. The value is a display hint only; it never
     * authorizes anything.
     */
    fun recordLinkProof(sourceNodeId: String, binding: PhoneWearAccountBinding, now: Long): Boolean =
        synchronized(lock) {
            if (binding.signedOut || prefs.getString(KEY_SOURCE_NODE_ID, null) != sourceNodeId) return false
            prefs.edit()
                .putLong(KEY_LINK_PROOF_AT, now)
                .putString(KEY_LINK_PROOF_OWNER_ID, binding.ownerId)
                .putLong(KEY_LINK_PROOF_GENERATION, binding.accountGeneration)
                .commit()
        }

    /** When the pinned watch last proved it follows [binding]; null when it never did. */
    fun linkProofAt(binding: PhoneWearAccountBinding): Long? = synchronized(lock) {
        if (binding.signedOut || prefs.getString(KEY_SOURCE_NODE_ID, null) == null) return null
        if (
            prefs.getString(KEY_LINK_PROOF_OWNER_ID, null) != binding.ownerId ||
            prefs.getLong(KEY_LINK_PROOF_GENERATION, 0L) != binding.accountGeneration
        ) {
            return null
        }
        prefs.getLong(KEY_LINK_PROOF_AT, 0L).takeIf { it > 0L }
    }

    /** Keeps the last plan of [ownerId] for the pinned watch; false when nothing is pinned. */
    fun cachePlan(ownerId: String, plan: PhoneWearCachedPlan): Boolean = synchronized(lock) {
        if (!ownerIdPattern.matches(ownerId) || prefs.getString(KEY_SOURCE_NODE_ID, null) == null) {
            return false
        }
        val raw = PhoneWearPlanCacheCodec.encode(plan) ?: return false
        prefs.edit().putString(KEY_PLAN_CACHE_PREFIX + ownerId, raw).commit()
    }

    fun cachedPlan(ownerId: String, now: Long): PhoneWearCachedPlan? = synchronized(lock) {
        if (!ownerIdPattern.matches(ownerId)) return null
        val key = KEY_PLAN_CACHE_PREFIX + ownerId
        val raw = prefs.getString(key, null) ?: return null
        val plan = PhoneWearPlanCacheCodec.decode(raw, now)
        if (plan == null) prefs.edit().remove(key).commit()
        plan
    }

    /** Called after a successful send: the plan is on the watch and is not sent again. */
    fun removeCachedPlan(ownerId: String, planId: String): Boolean = synchronized(lock) {
        if (!ownerIdPattern.matches(ownerId)) return false
        val key = KEY_PLAN_CACHE_PREFIX + ownerId
        val raw = prefs.getString(key, null) ?: return false
        // An unreadable entry is removed too; only another plan id (a newer plan) is kept.
        val storedPlanId = runCatching { org.json.JSONObject(raw).getString("planId") }.getOrNull()
        if (storedPlanId != null && storedPlanId != planId) return false
        prefs.edit().remove(key).commit()
    }

    private fun authorityEpochLocked(): String {
        prefs.getString(KEY_AUTHORITY_EPOCH, null)?.takeIf { stored ->
            runCatching { UUID.fromString(stored).toString() == stored }.getOrDefault(false)
        }?.let { return it }
        val created = UUID.randomUUID().toString()
        check(prefs.edit().putString(KEY_AUTHORITY_EPOCH, created).commit()) {
            "Could not persist Wear authority epoch"
        }
        return created
    }

    fun pinnedSourceNodeId(): String? = synchronized(lock) {
        prefs.getString(KEY_SOURCE_NODE_ID, null)?.takeIf(::isValidNodeId)
    }

    fun fastSourceMayBeTrusted(sourceNodeId: String): Boolean = synchronized(lock) {
        if (!isValidNodeId(sourceNodeId)) return false
        val pinned = prefs.getString(KEY_SOURCE_NODE_ID, null)
        pinned == null || (isValidNodeId(pinned) && pinned == sourceNodeId)
    }

    /** True when [sourceNodeId] is exactly the pinned watch node; the account is checked separately. */
    fun isPinnedNode(sourceNodeId: String): Boolean = synchronized(lock) {
        val pinned = prefs.getString(KEY_SOURCE_NODE_ID, null)
        pinned != null && isValidNodeId(pinned) && pinned == sourceNodeId
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
        const val KEY_AUTHORITY_EPOCH = "authority_epoch"
        const val KEY_UNLINKED_NODE_ID = "unlinked_node_id"
        const val KEY_WATCH_NAME = "source_display_name"
        const val KEY_LINK_PROOF_AT = "link_proof_at"
        const val KEY_LINK_PROOF_OWNER_ID = "link_proof_owner_id"
        const val KEY_LINK_PROOF_GENERATION = "link_proof_generation"
        const val KEY_PLAN_CACHE_PREFIX = "plan_cache_"
        const val MAX_WATCH_NAME_LENGTH = 64
        val ownerIdPattern = Regex("^[0-9a-f]{64}$")
        const val KEY_LOCAL_ACCOUNT_ID_PREFIX = "local_account_id_"
        const val MAX_NODE_ID_LENGTH = 256
        const val MAX_CONNECTED_NODES = 8
        const val SIGNED_OUT_IDENTITY = "GymAppPhoneWearSignedOutSessionV1"
        const val SIGNED_OUT_OWNER = "GymAppPhoneWearSignedOutOwnerV1"
    }
}
