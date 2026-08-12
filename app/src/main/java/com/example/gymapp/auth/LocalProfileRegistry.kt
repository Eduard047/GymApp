package com.example.gymapp.auth

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.Normalizer
import java.util.Locale
import java.util.UUID

internal const val LOCAL_PROFILE_REGISTRY_PREFERENCES = "gym_local_profile_registry_v1"

data class SavedLocalProfile(
    val id: String,
    val displayName: String
)

internal data class LocalProfileRegistrySnapshot(val encodedProfiles: String?)

internal open class LocalProfileRegistry(context: Context) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences(
        LOCAL_PROFILE_REGISTRY_PREFERENCES,
        Context.MODE_PRIVATE
    )
    private val lock = Any()

    open fun list(): List<SavedLocalProfile> = synchronized(lock) {
        readLockedOrNull()
            ?.filter { hasRecoverableIdentity(it.displayName) }
            ?.take(MAX_LOCAL_PROFILES)
            .orEmpty()
    }

    open fun contains(displayName: String): Boolean = synchronized(lock) {
        val normalized = normalizedLocalDisplayNameOrNull(displayName) ?: return@synchronized false
        val key = profileNameKey(normalized)
        readLockedOrNull()?.any { profileNameKey(it.displayName) == key } ?: false
    }

    open fun findById(profileId: String): SavedLocalProfile? = synchronized(lock) {
        canonicalProfileIdOrNull(profileId)?.let { canonical ->
            readLockedOrNull()?.firstOrNull { it.id == canonical }
        }
    }

    open fun ensurePresent(displayName: String, profileId: String? = null): Boolean = synchronized(lock) {
        val normalized = normalizedLocalDisplayNameOrNull(displayName) ?: return@synchronized false
        val current = readLockedOrNull() ?: return@synchronized false
        val key = profileNameKey(normalized)
        val existing = current.firstOrNull { profileNameKey(it.displayName) == key }
        if (existing != null) {
            return@synchronized profileId == null || existing.id == canonicalProfileIdOrNull(profileId)
        }
        if (current.size >= MAX_LOCAL_PROFILES) return@synchronized false
        val id = if (profileId == null) {
            UUID.randomUUID().toString()
        } else {
            canonicalProfileIdOrNull(profileId) ?: return@synchronized false
        }
        if (current.any { it.id == id }) return@synchronized false
        val encoded = encode(current + SavedLocalProfile(id, normalized))
        if (encoded.toByteArray(Charsets.UTF_8).size > MAX_REGISTRY_BYTES) return@synchronized false
        preferences.edit().putString(KEY_PROFILES, encoded).commit()
    }

    open fun canAdd(displayName: String): Boolean = synchronized(lock) {
        val normalized = normalizedLocalDisplayNameOrNull(displayName) ?: return@synchronized false
        val current = readLockedOrNull() ?: return@synchronized false
        val key = profileNameKey(normalized)
        current.size < MAX_LOCAL_PROFILES && current.none { profileNameKey(it.displayName) == key }
    }

    open fun remove(profileId: String): Boolean = synchronized(lock) {
        val canonicalId = canonicalProfileIdOrNull(profileId) ?: return@synchronized false
        val current = readLockedOrNull() ?: return@synchronized false
        val next = current.filterNot { it.id == canonicalId }
        if (next.size == current.size) return@synchronized true
        preferences.edit().putString(KEY_PROFILES, encode(next)).commit()
    }

    open fun snapshot(): LocalProfileRegistrySnapshot = synchronized(lock) {
        LocalProfileRegistrySnapshot(preferences.all[KEY_PROFILES] as? String)
    }

    open fun restore(snapshot: LocalProfileRegistrySnapshot): Boolean = synchronized(lock) {
        val editor = preferences.edit()
        if (snapshot.encodedProfiles == null) editor.remove(KEY_PROFILES)
        else editor.putString(KEY_PROFILES, snapshot.encodedProfiles)
        editor.commit()
    }

    private fun readLockedOrNull(): List<SavedLocalProfile>? {
        if (!preferences.contains(KEY_PROFILES)) return emptyList()
        val raw = preferences.all[KEY_PROFILES] as? String ?: return null
        if (raw.toByteArray(Charsets.UTF_8).size > MAX_REGISTRY_BYTES) return null
        return runCatching {
            val array = JSONArray(raw)
            require(array.length() <= MAX_LOCAL_PROFILES)
            buildList<SavedLocalProfile> {
                repeat(array.length()) { index ->
                    val item = array.opt(index)
                    val profile = when (item) {
                        is JSONObject -> {
                            require(item.length() == 2)
                            val id = canonicalProfileIdOrNull(item.optString(KEY_ID))
                                ?: error("Invalid local profile ID")
                            val name = normalizedLocalDisplayNameOrNull(item.optString(KEY_NAME))
                                ?: error("Invalid local profile name")
                            SavedLocalProfile(id, name)
                        }
                        is String -> {
                            // A short-lived pre-index Android build stored names only.
                            // Derive a stable opaque migration ID without renaming its DB.
                            val name = normalizedLocalDisplayNameOrNull(item)
                                ?: error("Invalid legacy local profile")
                            SavedLocalProfile(legacyMigrationId(name), name)
                        }
                        else -> error("Invalid local profile")
                    }
                    require(none { it.id == profile.id })
                    require(none { profileNameKey(it.displayName) == profileNameKey(profile.displayName) })
                    add(profile)
                }
            }
        }.getOrNull()
    }

    private fun encode(values: List<SavedLocalProfile>): String = JSONArray().apply {
        values.forEach { profile ->
            put(JSONObject().put(KEY_ID, profile.id).put(KEY_NAME, profile.displayName))
        }
    }.toString()

    private fun hasRecoverableIdentity(displayName: String): Boolean {
        val normalized = normalizedLocalDisplayNameOrNull(displayName) ?: return false
        return LocalDatabaseBindingStore(appContext).hasRecoverableIdentity(
            AccountSession.Local(normalized)
        )
    }

    private companion object {
        const val KEY_PROFILES = "profiles"
        const val KEY_ID = "id"
        const val KEY_NAME = "name"
        const val MAX_LOCAL_PROFILES = 32
        const val MAX_REGISTRY_BYTES = 16 * 1_024
    }
}

private fun canonicalProfileIdOrNull(value: String): String? = runCatching {
    UUID.fromString(value).toString().lowercase(Locale.ROOT)
}.getOrNull()?.takeIf { it == value.lowercase(Locale.ROOT) }

private fun legacyMigrationId(displayName: String): String = UUID.nameUUIDFromBytes(
    "GymAppLocalProfileLegacy\u0000${profileNameKey(displayName)}".toByteArray(Charsets.UTF_8)
).toString()

private fun profileNameKey(displayName: String): String = Normalizer.normalize(
    displayName.trim(),
    Normalizer.Form.NFD
).filterNot { Character.getType(it) in setOf(
    Character.NON_SPACING_MARK.toInt(),
    Character.COMBINING_SPACING_MARK.toInt(),
    Character.ENCLOSING_MARK.toInt()
) }.lowercase(Locale.ROOT)
