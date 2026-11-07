package com.example.gymapp.util

import android.content.Context
import android.content.SharedPreferences
import java.security.MessageDigest

/** Longest cue, counted in Unicode code points (shared/exercise-cue-v1.json). */
internal const val EXERCISE_CUE_MAX_CODE_POINTS = 80

/** Most cues one account keeps; a new cue past this is refused, an existing one can still be edited. */
internal const val EXERCISE_CUE_MAX_ENTRIES = 1_000

private const val EXERCISE_CUE_MAX_KEY_CHARS = 512

/**
 * The text a cue is stored as, or null when it is empty (the cue is removed). Line breaks become
 * single spaces, the text is trimmed, cut to [EXERCISE_CUE_MAX_CODE_POINTS] code points and trimmed again.
 */
internal fun normalizeExerciseCue(raw: String?): String? {
    if (raw == null) return null
    val singleLine = raw
        .replace("\r\n", " ")
        .replace('\r', ' ')
        .replace('\n', ' ')
        .replace('\u0085', ' ')
        .replace('\u2028', ' ')
        .replace('\u2029', ' ')
        .trim()
    val cut = if (singleLine.codePointCount(0, singleLine.length) > EXERCISE_CUE_MAX_CODE_POINTS) {
        singleLine.substring(0, singleLine.offsetByCodePoints(0, EXERCISE_CUE_MAX_CODE_POINTS)).trim()
    } else {
        singleLine
    }
    return cut.ifEmpty { null }
}

/** The one private preferences file all accounts' cues live in (excluded from backup and device transfer). */
internal const val EXERCISE_CUE_PREFERENCES_NAME = "gym_exercise_cues_v1"

private const val EXERCISE_CUE_CUSTOM_PREFIX = "custom:"

/** Hides the account's database name in the shared cue file's keys; null for an unusable name. */
internal fun exerciseCueAccountHash(databaseName: String): String? {
    if (databaseName.isEmpty() || databaseName.length > 512 || databaseName.any(Char::isISOControl)) {
        return null
    }
    val digest = MessageDigest.getInstance("SHA-256")
        .digest("GymAppExerciseCueAccountV1:$databaseName".toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
    return digest.take(32)
}

/** False for a blank key, an oversized or control-character key, and a `custom:` key with no name. */
internal fun isUsableExerciseCueKey(key: String): Boolean =
    key.isNotBlank() &&
        key.length <= EXERCISE_CUE_MAX_KEY_CHARS &&
        key.none(Char::isISOControl) &&
        !(key.startsWith(EXERCISE_CUE_CUSTOM_PREFIX) && key.removePrefix(EXERCISE_CUE_CUSTOM_PREFIX).isBlank())

/** What [ExerciseCueStore.setCue] did. */
internal enum class ExerciseCueSaveResult {
    /** The normalized text is stored. */
    STORED,

    /** The text was empty, so the cue is gone. */
    REMOVED,

    /** A new cue was refused because the account already keeps [EXERCISE_CUE_MAX_ENTRIES]. */
    TOO_MANY,

    /** Unusable account or key, or the write failed. */
    FAILED
}

internal interface ExerciseCueStorage {
    fun get(key: String): String?
    fun put(key: String, value: String): Boolean
    fun remove(key: String): Boolean

    /** Every stored key with its text. */
    fun all(): Map<String, String>
    fun removeAll(keys: Collection<String>): Boolean
}

internal class SharedPreferencesExerciseCueStorage(
    private val preferences: SharedPreferences
) : ExerciseCueStorage {
    override fun get(key: String): String? = runCatching { preferences.getString(key, null) }.getOrNull()
    override fun put(key: String, value: String): Boolean =
        runCatching { preferences.edit().putString(key, value).commit() }.getOrDefault(false)
    override fun remove(key: String): Boolean =
        runCatching { preferences.edit().remove(key).commit() }.getOrDefault(false)
    override fun all(): Map<String, String> = runCatching {
        preferences.all.mapNotNull { (key, value) -> (value as? String)?.let { key to it } }.toMap()
    }.getOrDefault(emptyMap())
    override fun removeAll(keys: Collection<String>): Boolean = runCatching {
        val editor = preferences.edit()
        keys.forEach { editor.remove(it) }
        editor.commit()
    }.getOrDefault(false)
}

/**
 * Device-local cues per account and exercise identity (the friend-ghost key: catalog key, else the
 * normalized name). Never synced. All accounts share one preferences file
 * ([EXERCISE_CUE_PREFERENCES_NAME]), which backup_rules.xml and data_extraction_rules.xml exclude by
 * name (they have no wildcards); a key is `<[exerciseCueAccountHash]>|<identity key>`. [clearAccount]
 * removes only that account's keys on account deletion. Reads and writes do disk I/O: call them off
 * the main thread.
 */
internal class ExerciseCueStore(
    private val openStorage: () -> ExerciseCueStorage?
) {
    fun cue(databaseName: String, identityKey: String): String? {
        val prefix = prefixFor(databaseName) ?: return null
        if (!isUsableExerciseCueKey(identityKey)) return null
        val storage = openStorage() ?: return null
        return normalizeExerciseCue(storage.get(prefix + identityKey))
    }

    /** Every cue of the account by identity key. */
    fun cues(databaseName: String): Map<String, String> {
        val prefix = prefixFor(databaseName) ?: return emptyMap()
        val storage = openStorage() ?: return emptyMap()
        val result = linkedMapOf<String, String>()
        for ((key, value) in storage.all()) {
            if (!key.startsWith(prefix)) continue
            val identityKey = key.substring(prefix.length)
            val cue = normalizeExerciseCue(value)
            if (cue != null && isUsableExerciseCueKey(identityKey)) result[identityKey] = cue
        }
        return result
    }

    /** Stores the normalized [raw] (an empty result removes the cue). */
    fun setCue(databaseName: String, identityKey: String, raw: String?): ExerciseCueSaveResult {
        val prefix = prefixFor(databaseName) ?: return ExerciseCueSaveResult.FAILED
        if (!isUsableExerciseCueKey(identityKey)) return ExerciseCueSaveResult.FAILED
        val storage = openStorage() ?: return ExerciseCueSaveResult.FAILED
        val key = prefix + identityKey
        val normalized = normalizeExerciseCue(raw)
        if (normalized == null) {
            return if (storage.remove(key)) ExerciseCueSaveResult.REMOVED else ExerciseCueSaveResult.FAILED
        }
        val stored = storage.all().keys
        if (key !in stored && stored.count { it.startsWith(prefix) } >= EXERCISE_CUE_MAX_ENTRIES) {
            return ExerciseCueSaveResult.TOO_MANY
        }
        return if (storage.put(key, normalized)) ExerciseCueSaveResult.STORED else ExerciseCueSaveResult.FAILED
    }

    fun clearAccount(databaseName: String): Boolean {
        val prefix = prefixFor(databaseName) ?: return false
        val storage = openStorage() ?: return false
        val keys = storage.all().keys.filter { it.startsWith(prefix) }
        return keys.isEmpty() || storage.removeAll(keys)
    }

    private fun prefixFor(databaseName: String): String? =
        exerciseCueAccountHash(databaseName)?.let { "$it|" }

    companion object {
        fun forContext(context: Context): ExerciseCueStore {
            val appContext = context.applicationContext
            return ExerciseCueStore {
                runCatching {
                    SharedPreferencesExerciseCueStorage(
                        appContext.getSharedPreferences(EXERCISE_CUE_PREFERENCES_NAME, Context.MODE_PRIVATE)
                    )
                }.getOrNull()
            }
        }
    }
}
