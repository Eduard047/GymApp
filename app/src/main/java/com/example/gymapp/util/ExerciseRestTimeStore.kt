package com.example.gymapp.util

import android.content.Context
import android.content.SharedPreferences
import java.security.MessageDigest

/** The shortest and longest custom rest, and the picker step (shared/exercise-rest-v1.json). */
internal const val EXERCISE_REST_MIN_SECONDS = 15
internal const val EXERCISE_REST_MAX_SECONDS = 600
internal const val EXERCISE_REST_STEP_SECONDS = 15

/** Most custom rests one account keeps; a new one past this is refused, an existing one can still be edited. */
internal const val EXERCISE_REST_MAX_ENTRIES = 1_000

/** The one private preferences file all accounts' custom rests live in (excluded from backup and device transfer). */
internal const val EXERCISE_REST_PREFERENCES_NAME = "gym_exercise_rest_v1"

/** The custom rest kept for [raw], or null when there is none: non-positive means none, anything else is clamped. */
internal fun normalizeExerciseRestSeconds(raw: Int?): Int? {
    if (raw == null || raw <= 0) return null
    return raw.coerceIn(EXERCISE_REST_MIN_SECONDS, EXERCISE_REST_MAX_SECONDS)
}

/** The rest to start after a set: the normalized [stored] custom value, else the unchanged [defaultSeconds]. */
internal fun effectiveExerciseRestSeconds(stored: Int?, defaultSeconds: Int): Int =
    normalizeExerciseRestSeconds(stored) ?: defaultSeconds

/** Hides the account's database name in the shared file's keys; null for an unusable name. */
internal fun exerciseRestAccountHash(databaseName: String): String? {
    if (databaseName.isEmpty() || databaseName.length > 512 || databaseName.any(Char::isISOControl)) {
        return null
    }
    val digest = MessageDigest.getInstance("SHA-256")
        .digest("GymAppExerciseRestAccountV1:$databaseName".toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
    return digest.take(32)
}

/** What [ExerciseRestTimeStore.setRestSeconds] did. */
internal enum class ExerciseRestSaveResult {
    /** The normalized seconds are stored. */
    STORED,

    /** No custom rest was given, so the exercise uses its default again. */
    REMOVED,

    /** A new custom rest was refused because the account already keeps [EXERCISE_REST_MAX_ENTRIES]. */
    TOO_MANY,

    /** Unusable account or key, or the write failed. */
    FAILED
}

internal interface ExerciseRestStorage {
    fun get(key: String): String?
    fun put(key: String, value: String): Boolean
    fun remove(key: String): Boolean

    /** Every stored key with its value. */
    fun all(): Map<String, String>
    fun removeAll(keys: Collection<String>): Boolean
}

internal class SharedPreferencesExerciseRestStorage(
    private val preferences: SharedPreferences
) : ExerciseRestStorage {
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
 * Device-local custom rest per account and exercise identity (the friend-ghost key, like cues). Never
 * synced. All accounts share one preferences file ([EXERCISE_REST_PREFERENCES_NAME]), which
 * backup_rules.xml and data_extraction_rules.xml exclude by name; a key is
 * `<[exerciseRestAccountHash]>|<identity key>`. [clearAccount] removes only that account's keys on
 * account deletion. Reads and writes do disk I/O: call them off the main thread.
 */
internal class ExerciseRestTimeStore(
    private val openStorage: () -> ExerciseRestStorage?
) {
    fun restSeconds(databaseName: String, identityKey: String): Int? {
        val prefix = prefixFor(databaseName) ?: return null
        if (!isUsableExerciseCueKey(identityKey)) return null
        val storage = openStorage() ?: return null
        return parse(storage.get(prefix + identityKey))
    }

    /** Every custom rest of the account by identity key. */
    fun restTimes(databaseName: String): Map<String, Int> {
        val prefix = prefixFor(databaseName) ?: return emptyMap()
        val storage = openStorage() ?: return emptyMap()
        val result = linkedMapOf<String, Int>()
        for ((key, value) in storage.all()) {
            if (!key.startsWith(prefix)) continue
            val identityKey = key.substring(prefix.length)
            val seconds = parse(value)
            if (seconds != null && isUsableExerciseCueKey(identityKey)) result[identityKey] = seconds
        }
        return result
    }

    /** Stores the normalized [seconds]; null (or a non-positive value) removes the custom rest. */
    fun setRestSeconds(databaseName: String, identityKey: String, seconds: Int?): ExerciseRestSaveResult {
        val prefix = prefixFor(databaseName) ?: return ExerciseRestSaveResult.FAILED
        if (!isUsableExerciseCueKey(identityKey)) return ExerciseRestSaveResult.FAILED
        val storage = openStorage() ?: return ExerciseRestSaveResult.FAILED
        val key = prefix + identityKey
        val normalized = normalizeExerciseRestSeconds(seconds)
        if (normalized == null) {
            return if (storage.remove(key)) ExerciseRestSaveResult.REMOVED else ExerciseRestSaveResult.FAILED
        }
        val stored = storage.all().keys
        if (key !in stored && stored.count { it.startsWith(prefix) } >= EXERCISE_REST_MAX_ENTRIES) {
            return ExerciseRestSaveResult.TOO_MANY
        }
        return if (storage.put(key, normalized.toString())) ExerciseRestSaveResult.STORED else ExerciseRestSaveResult.FAILED
    }

    fun clearAccount(databaseName: String): Boolean {
        val prefix = prefixFor(databaseName) ?: return false
        val storage = openStorage() ?: return false
        val keys = storage.all().keys.filter { it.startsWith(prefix) }
        return keys.isEmpty() || storage.removeAll(keys)
    }

    private fun parse(value: String?): Int? = normalizeExerciseRestSeconds(value?.trim()?.toIntOrNull())

    private fun prefixFor(databaseName: String): String? =
        exerciseRestAccountHash(databaseName)?.let { "$it|" }

    companion object {
        fun forContext(context: Context): ExerciseRestTimeStore {
            val appContext = context.applicationContext
            return ExerciseRestTimeStore {
                runCatching {
                    SharedPreferencesExerciseRestStorage(
                        appContext.getSharedPreferences(EXERCISE_REST_PREFERENCES_NAME, Context.MODE_PRIVATE)
                    )
                }.getOrNull()
            }
        }
    }
}
