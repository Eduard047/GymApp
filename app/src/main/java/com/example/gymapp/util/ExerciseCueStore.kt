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

/** The private preferences file of one account's cues; the name hides the account's database name. */
internal fun exerciseCueStorageName(databaseName: String): String? {
    if (databaseName.isEmpty() || databaseName.length > 512 || databaseName.any(Char::isISOControl)) {
        return null
    }
    val digest = MessageDigest.getInstance("SHA-256")
        .digest("GymAppExerciseCueAccountV1:$databaseName".toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
    return "exercise_cues_v1_${digest.take(32)}"
}

internal interface ExerciseCueStorage {
    fun get(key: String): String?
    fun put(key: String, value: String): Boolean
    fun remove(key: String): Boolean
    fun count(): Int
    fun clear(): Boolean
}

internal class SharedPreferencesExerciseCueStorage(
    private val preferences: SharedPreferences
) : ExerciseCueStorage {
    override fun get(key: String): String? = runCatching { preferences.getString(key, null) }.getOrNull()
    override fun put(key: String, value: String): Boolean =
        runCatching { preferences.edit().putString(key, value).commit() }.getOrDefault(false)
    override fun remove(key: String): Boolean =
        runCatching { preferences.edit().remove(key).commit() }.getOrDefault(false)
    override fun count(): Int = runCatching { preferences.all.size }.getOrDefault(0)
    override fun clear(): Boolean =
        runCatching { preferences.edit().clear().commit() }.getOrDefault(false)
}

/**
 * Device-local cues per account and exercise identity (the friend-ghost key: catalog key, else the
 * normalized name). Never synced, never part of a backup. Every account has its own storage, found by
 * [exerciseCueStorageName] of its database name, and [clearAccount] wipes it on account deletion.
 */
internal class ExerciseCueStore(
    private val openStorage: (storageName: String) -> ExerciseCueStorage?
) {
    fun cue(databaseName: String, identityKey: String): String? {
        val storage = storageFor(databaseName) ?: return null
        if (!validKey(identityKey)) return null
        return normalizeExerciseCue(storage.get(identityKey))
    }

    /** Stores the normalized [raw] (an empty result removes the cue) and returns what is now stored. */
    fun setCue(databaseName: String, identityKey: String, raw: String?): String? {
        val storage = storageFor(databaseName) ?: return null
        if (!validKey(identityKey)) return null
        val normalized = normalizeExerciseCue(raw)
        if (normalized == null) {
            storage.remove(identityKey)
            return null
        }
        if (storage.get(identityKey) == null && storage.count() >= EXERCISE_CUE_MAX_ENTRIES) return null
        return if (storage.put(identityKey, normalized)) normalized else cue(databaseName, identityKey)
    }

    fun clearAccount(databaseName: String): Boolean {
        val storage = storageFor(databaseName) ?: return false
        return storage.clear()
    }

    private fun storageFor(databaseName: String): ExerciseCueStorage? {
        val name = exerciseCueStorageName(databaseName) ?: return null
        return openStorage(name)
    }

    private fun validKey(key: String) =
        key.isNotBlank() && key.length <= EXERCISE_CUE_MAX_KEY_CHARS && key.none(Char::isISOControl)

    companion object {
        fun forContext(context: Context): ExerciseCueStore {
            val appContext = context.applicationContext
            return ExerciseCueStore { name ->
                runCatching {
                    SharedPreferencesExerciseCueStorage(
                        appContext.getSharedPreferences(name, Context.MODE_PRIVATE)
                    )
                }.getOrNull()
            }
        }
    }
}
