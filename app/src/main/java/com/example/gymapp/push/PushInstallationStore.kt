package com.example.gymapp.push

import android.content.Context
import android.content.SharedPreferences
import com.example.gymapp.auth.AccountSession
import java.security.MessageDigest
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal data class PushInstallationBinding(
    val installationId: String,
    val userId: String,
    val sessionGeneration: String,
    val bindingId: String,
    val registrationRevision: Int,
    val providerTokenDigest: String,
    val registeredAtMillis: Long
)

internal data class PushRegistrationAttempt(
    val installationId: String,
    val userId: String,
    val sessionGeneration: String,
    val providerToken: String,
    val epoch: Long
)

internal data class PushPendingRevocation(
    val installationId: String,
    val userId: String,
    val sessionGeneration: String,
    val deleteProviderToken: Boolean
)

internal fun PushInstallationBinding.matches(
    session: AccountSession.Cloud,
    currentInstallationId: String,
    incomingBindingId: String
): Boolean =
    installationId == currentInstallationId &&
        userId == session.userId &&
        sessionGeneration == session.sessionGeneration &&
        bindingId == incomingBindingId &&
        registrationRevision > 0

internal fun canCommitPushRegistration(
    attempt: PushRegistrationAttempt,
    activeSession: AccountSession?,
    currentInstallationId: String,
    currentProviderToken: String?,
    currentEpoch: Long,
    enabled: Boolean
): Boolean {
    val cloud = activeSession as? AccountSession.Cloud ?: return false
    return enabled &&
        attempt.epoch == currentEpoch &&
        attempt.installationId == currentInstallationId &&
        attempt.userId == cloud.userId &&
        attempt.sessionGeneration == cloud.sessionGeneration &&
        attempt.providerToken == currentProviderToken
}

internal fun canClearSupersededPendingRevocation(
    persistedReplacement: PushInstallationBinding?,
    expectedReplacement: PushInstallationBinding,
    currentPending: PushPendingRevocation?,
    expectedPending: PushPendingRevocation?
): Boolean = persistedReplacement == expectedReplacement &&
    currentPending == expectedPending &&
    (currentPending == null ||
        currentPending.installationId == expectedReplacement.installationId)

internal class PushInstallationStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )
    private val lock = Any()

    fun isEnabled(): Boolean = synchronized(lock) {
        preferences.getBoolean(KEY_ENABLED, false)
    }

    fun setEnabled(enabled: Boolean): Boolean = synchronized(lock) {
        preferences.edit().putBoolean(KEY_ENABLED, enabled).commit()
    }

    fun installationId(): String = synchronized(lock) {
        existingInstallationIdLocked()?.let { return@synchronized it }
        val installationId = UUID.randomUUID().toString()
        check(isCanonicalV4Uuid(installationId)) { "Push installation ID generation failed." }
        val editor = preferences.edit()
            .putString(KEY_INSTALLATION_ID, installationId)
        removeBinding(editor)
        check(editor.commit()) { "Push installation identity could not be stored." }
        installationId
    }

    fun existingInstallationIdOrNull(): String? = synchronized(lock) {
        existingInstallationIdLocked()
    }

    fun binding(): PushInstallationBinding? = synchronized(lock) {
        bindingLocked()
    }

    fun saveBinding(binding: PushInstallationBinding): Boolean = synchronized(lock) {
        require(isValidBinding(binding)) { "Push binding is invalid." }
        require(binding.installationId == existingInstallationIdLocked()) {
            "Push installation changed before binding could be stored."
        }
        val deliveryScopeChanged = !displayScopeMatchesLocked(binding)
        val editor = preferences.edit()
            .putString(KEY_USER_ID, binding.userId)
            .putString(KEY_SESSION_GENERATION, binding.sessionGeneration)
            .putString(KEY_BINDING_ID, binding.bindingId)
            .putInt(KEY_REGISTRATION_REVISION, binding.registrationRevision)
            .putString(KEY_PROVIDER_TOKEN_DIGEST, binding.providerTokenDigest)
            .putLong(KEY_REGISTERED_AT_MILLIS, binding.registeredAtMillis)
        if (deliveryScopeChanged) removeDisplayHistory(editor)
        editor.commit()
    }

    fun clearBinding(preserveDeliveryState: Boolean = false): Boolean = synchronized(lock) {
        removeBinding(preferences.edit(), preserveDeliveryState).commit()
    }

    fun savePendingRevocation(pending: PushPendingRevocation): Boolean = synchronized(lock) {
        require(isValidPendingRevocation(pending)) { "Push revocation marker is invalid." }
        require(pending.installationId == existingInstallationIdLocked()) {
            "Push installation changed before revocation could be stored."
        }
        preferences.edit()
            .putString(KEY_PENDING_INSTALLATION_ID, pending.installationId)
            .putString(KEY_PENDING_USER_ID, pending.userId)
            .putString(KEY_PENDING_SESSION_GENERATION, pending.sessionGeneration)
            .putBoolean(KEY_PENDING_DELETE_TOKEN, pending.deleteProviderToken)
            .commit()
    }

    fun pendingRevocation(): PushPendingRevocation? = synchronized(lock) {
        if (!preferences.contains(KEY_PENDING_INSTALLATION_ID)) return@synchronized null
        val pending = PushPendingRevocation(
            installationId = preferences.getString(KEY_PENDING_INSTALLATION_ID, null).orEmpty(),
            userId = preferences.getString(KEY_PENDING_USER_ID, null).orEmpty(),
            sessionGeneration = preferences.getString(
                KEY_PENDING_SESSION_GENERATION,
                null
            ).orEmpty(),
            deleteProviderToken = preferences.getBoolean(KEY_PENDING_DELETE_TOKEN, false)
        )
        if (!isValidPendingRevocation(pending) ||
            pending.installationId != existingInstallationIdLocked()
        ) {
            removePendingRevocation(preferences.edit()).commit()
            null
        } else {
            pending
        }
    }

    fun clearPendingRevocation(expectedInstallationId: String): Boolean = synchronized(lock) {
        val storedInstallationId = preferences.getString(KEY_PENDING_INSTALLATION_ID, null)
            ?: return@synchronized true
        if (storedInstallationId != expectedInstallationId) return@synchronized false
        removePendingRevocation(preferences.edit()).commit()
    }

    /**
     * The registration RPC atomically scrubs an older account owner before replacing it. A
     * previous owner's retry marker is superseded only after the replacement binding is durable.
     */
    fun clearPendingRevocationSupersededBy(
        replacement: PushInstallationBinding,
        expectedPending: PushPendingRevocation?
    ): Boolean = synchronized(lock) {
        val currentPending = pendingRevocation()
        if (!canClearSupersededPendingRevocation(
                persistedReplacement = bindingLocked(),
                expectedReplacement = replacement,
                currentPending = currentPending,
                expectedPending = expectedPending
            )
        ) {
            return@synchronized false
        }
        if (currentPending == null) return@synchronized true
        removePendingRevocation(preferences.edit()).commit()
    }

    fun canDisplay(
        payload: PushPayload,
        session: AccountSession.Cloud,
        currentInstallationId: String
    ): Boolean = synchronized(lock) {
        val binding = bindingLocked() ?: return@synchronized false
        if (!binding.matches(session, currentInstallationId, payload.bindingId)) {
            return@synchronized false
        }
        val highWater = readDisplayHighWaterLocked(binding) ?: return@synchronized false
        val currentRevision = highWater[pushDisplayObjectKey(payload)]
        currentRevision == null || payload.objectRevision > currentRevision
    }

    fun commitDisplayed(
        payload: PushPayload,
        session: AccountSession.Cloud,
        currentInstallationId: String
    ): Boolean = synchronized(lock) {
        val binding = bindingLocked() ?: return@synchronized false
        if (!binding.matches(session, currentInstallationId, payload.bindingId)) {
            return@synchronized false
        }
        val highWater = readDisplayHighWaterLocked(binding) ?: return@synchronized false
        val key = pushDisplayObjectKey(payload)
        val currentRevision = highWater[key]
        if (currentRevision != null && payload.objectRevision <= currentRevision) {
            return@synchronized false
        }
        highWater.remove(key)
        highWater[key] = payload.objectRevision
        while (highWater.size > MAX_DISPLAY_HIGH_WATER_ENTRIES) {
            highWater.remove(highWater.keys.first())
        }
        saveDisplayHighWaterLocked(binding, highWater)
    }

    fun isCurrentDisplayedPayload(
        payload: PushPayload,
        session: AccountSession.Cloud,
        currentInstallationId: String
    ): Boolean = synchronized(lock) {
        val binding = bindingLocked() ?: return@synchronized false
        if (!binding.matches(session, currentInstallationId, payload.bindingId)) {
            return@synchronized false
        }
        readDisplayHighWaterLocked(binding)?.get(pushDisplayObjectKey(payload)) ==
            payload.objectRevision
    }

    private fun bindingLocked(): PushInstallationBinding? {
        val installationId = existingInstallationIdLocked() ?: return null
        val bindingKeysPresent = listOf(
            KEY_USER_ID,
            KEY_SESSION_GENERATION,
            KEY_BINDING_ID,
            KEY_REGISTRATION_REVISION,
            KEY_PROVIDER_TOKEN_DIGEST,
            KEY_REGISTERED_AT_MILLIS
        ).count(preferences::contains)
        if (bindingKeysPresent == 0) return null
        val userId = preferences.getString(KEY_USER_ID, null).orEmpty()
        val sessionGeneration = preferences.getString(KEY_SESSION_GENERATION, null).orEmpty()
        val bindingId = preferences.getString(KEY_BINDING_ID, null).orEmpty()
        val revision = preferences.getInt(KEY_REGISTRATION_REVISION, 0)
        val providerTokenDigest = preferences.getString(KEY_PROVIDER_TOKEN_DIGEST, null).orEmpty()
        val registeredAtMillis = preferences.getLong(KEY_REGISTERED_AT_MILLIS, 0L)
        val binding = PushInstallationBinding(
            installationId = installationId,
            userId = userId,
            sessionGeneration = sessionGeneration,
            bindingId = bindingId,
            registrationRevision = revision,
            providerTokenDigest = providerTokenDigest,
            registeredAtMillis = registeredAtMillis
        )
        return if (!isValidBinding(binding)) {
            removeBinding(preferences.edit()).commit()
            null
        } else {
            binding
        }
    }

    private fun existingInstallationIdLocked(): String? =
        preferences.getString(KEY_INSTALLATION_ID, null)?.takeIf(::isCanonicalV4Uuid)

    private fun isValidBinding(binding: PushInstallationBinding): Boolean =
        isCanonicalV4Uuid(binding.installationId) &&
            isCanonicalUuid(binding.userId) &&
            isCanonicalV4Uuid(binding.sessionGeneration) &&
            isCanonicalV4Uuid(binding.bindingId) &&
            binding.registrationRevision > 0 &&
            TOKEN_DIGEST_PATTERN.matches(binding.providerTokenDigest) &&
            binding.registeredAtMillis > 0

    private fun isValidPendingRevocation(pending: PushPendingRevocation): Boolean =
        isCanonicalV4Uuid(pending.installationId) &&
            isCanonicalUuid(pending.userId) &&
            isCanonicalV4Uuid(pending.sessionGeneration)

    private fun readDisplayHighWaterLocked(
        binding: PushInstallationBinding
    ): LinkedHashMap<String, Int>? {
        if (!displayScopeMatchesLocked(binding)) {
            removeDisplayHistory(preferences.edit()).commit()
            return linkedMapOf()
        }
        val raw = preferences.getString(KEY_DISPLAY_HIGH_WATER, null)
            ?: return linkedMapOf()
        if (raw.length > MAX_DISPLAY_HIGH_WATER_JSON_CHARS) {
            removeDisplayHistory(preferences.edit()).commit()
            return null
        }
        return runCatching {
            val array = JSONArray(raw)
            require(array.length() <= MAX_DISPLAY_HIGH_WATER_ENTRIES)
            val result = linkedMapOf<String, Int>()
            repeat(array.length()) { index ->
                val item = array.get(index) as? JSONObject ?: error("Invalid push history.")
                require(item.keys().asSequence().toSet() == DISPLAY_RECORD_KEYS)
                val key = item.opt("key") as? String ?: error("Invalid push history.")
                require(DISPLAY_OBJECT_KEY_PATTERN.matches(key))
                val rawRevision = item.opt("revision")
                require(rawRevision is Int || rawRevision is Long)
                val revision = (rawRevision as Number).toLong()
                require(revision in 0..Int.MAX_VALUE.toLong())
                require(result.put(key, revision.toInt()) == null)
            }
            result
        }.getOrElse {
            removeDisplayHistory(preferences.edit()).commit()
            null
        }
    }

    private fun displayScopeMatchesLocked(binding: PushInstallationBinding): Boolean =
        preferences.getString(KEY_DISPLAY_USER_ID, null) == binding.userId &&
            preferences.getString(KEY_DISPLAY_SESSION_GENERATION, null) ==
            binding.sessionGeneration &&
            preferences.getString(KEY_DISPLAY_INSTALLATION_ID, null) == binding.installationId &&
            preferences.getString(KEY_DISPLAY_BINDING_ID, null) == binding.bindingId

    private fun saveDisplayHighWaterLocked(
        binding: PushInstallationBinding,
        highWater: LinkedHashMap<String, Int>
    ): Boolean {
        val array = JSONArray()
        highWater.forEach { (key, revision) ->
            array.put(JSONObject().put("key", key).put("revision", revision))
        }
        return preferences.edit()
            .putString(KEY_DISPLAY_USER_ID, binding.userId)
            .putString(KEY_DISPLAY_SESSION_GENERATION, binding.sessionGeneration)
            .putString(KEY_DISPLAY_INSTALLATION_ID, binding.installationId)
            .putString(KEY_DISPLAY_BINDING_ID, binding.bindingId)
            .putString(KEY_DISPLAY_HIGH_WATER, array.toString())
            .commit()
    }

    private fun removeBinding(
        editor: SharedPreferences.Editor,
        preserveDeliveryState: Boolean = false
    ): SharedPreferences.Editor = editor
        .remove(KEY_USER_ID)
        .remove(KEY_SESSION_GENERATION)
        .remove(KEY_BINDING_ID)
        .remove(KEY_REGISTRATION_REVISION)
        .remove(KEY_PROVIDER_TOKEN_DIGEST)
        .remove(KEY_REGISTERED_AT_MILLIS)
        .let { bindingEditor ->
            if (preserveDeliveryState) bindingEditor else removeDisplayHistory(bindingEditor)
        }

    private fun removePendingRevocation(
        editor: SharedPreferences.Editor
    ): SharedPreferences.Editor = editor
        .remove(KEY_PENDING_INSTALLATION_ID)
        .remove(KEY_PENDING_USER_ID)
        .remove(KEY_PENDING_SESSION_GENERATION)
        .remove(KEY_PENDING_DELETE_TOKEN)

    private fun removeDisplayHistory(
        editor: SharedPreferences.Editor
    ): SharedPreferences.Editor = editor
        .remove(KEY_DISPLAY_USER_ID)
        .remove(KEY_DISPLAY_SESSION_GENERATION)
        .remove(KEY_DISPLAY_INSTALLATION_ID)
        .remove(KEY_DISPLAY_BINDING_ID)
        .remove(KEY_DISPLAY_HIGH_WATER)

    companion object {
        const val PREFERENCES_NAME = "gym_push_installation"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_INSTALLATION_ID = "installation_id"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_SESSION_GENERATION = "session_generation"
        private const val KEY_BINDING_ID = "binding_id"
        private const val KEY_REGISTRATION_REVISION = "registration_revision"
        private const val KEY_PROVIDER_TOKEN_DIGEST = "provider_token_digest"
        private const val KEY_REGISTERED_AT_MILLIS = "registered_at_millis"
        private const val KEY_PENDING_INSTALLATION_ID = "pending_installation_id"
        private const val KEY_PENDING_USER_ID = "pending_user_id"
        private const val KEY_PENDING_SESSION_GENERATION = "pending_session_generation"
        private const val KEY_PENDING_DELETE_TOKEN = "pending_delete_provider_token"
        private const val KEY_DISPLAY_USER_ID = "display_user_id"
        private const val KEY_DISPLAY_SESSION_GENERATION = "display_session_generation"
        private const val KEY_DISPLAY_INSTALLATION_ID = "display_installation_id"
        private const val KEY_DISPLAY_BINDING_ID = "display_binding_id"
        private const val KEY_DISPLAY_HIGH_WATER = "display_high_water"
        private const val MAX_DISPLAY_HIGH_WATER_ENTRIES = 128
        private const val MAX_DISPLAY_HIGH_WATER_JSON_CHARS = 32 * 1_024
        private val TOKEN_DIGEST_PATTERN = Regex("^[0-9a-f]{64}$")
        private val DISPLAY_OBJECT_KEY_PATTERN = Regex(
            "^(?:social:(?:f|wi)_[0-9a-f]{32}|live:lr_[0-9a-f]{32})$"
        )
        private val DISPLAY_RECORD_KEYS = setOf("key", "revision")
    }
}

internal fun pushDisplayObjectKey(payload: PushPayload): String = when (payload) {
    is PushPayload.Social -> "social:${payload.objectId}"
    is PushPayload.Live -> "live:${payload.roomId}"
}

internal fun providerTokenDigest(providerToken: String): String =
    MessageDigest.getInstance("SHA-256")
        .digest(providerToken.toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
