package com.example.gymapp.util

import android.content.Context
import android.content.SharedPreferences
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.databaseName
import com.example.gymapp.data.repository.WorkoutDataLimits
import java.security.MessageDigest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal const val MAX_EXERCISE_REST_SECONDS = 24 * 60 * 60
private const val EXERCISE_REST_TIMER_PREFS = "gym_exercise_rest_timers"
private const val OWNER_KEY = "owner"
private const val DEADLINES_KEY = "deadlines"
private val ACCOUNT_KEY_PATTERN = Regex("^[a-f0-9]{64}$")

internal data class ExerciseRestTimerKey(
    val accountKey: String,
    val sessionId: Long,
    val workoutExerciseId: Long
)

internal data class ExerciseRestTimerSnapshot(
    val accountKey: String?,
    val deadlines: Map<ExerciseRestTimerKey, Long>
)

internal interface ExerciseRestTimerPersistence {
    fun load(): ExerciseRestTimerSnapshot
    fun save(snapshot: ExerciseRestTimerSnapshot): Boolean
}

internal fun restTimerAccountKey(session: AccountSession?): String? {
    val stableIdentity = when (session) {
        null -> return null
        is AccountSession.Cloud -> "${session.databaseName()}:${session.sessionGeneration}"
        is AccountSession.Local -> session.databaseName()
    }
    return MessageDigest.getInstance("SHA-256")
        .digest("GymAppExerciseRestTimerAccountV1:$stableIdentity".toByteArray(Charsets.UTF_8))
        .joinToString(separator = "") { byte -> "%02x".format(byte) }
}

internal class ExerciseRestTimerLedger(
    private val persistence: ExerciseRestTimerPersistence,
    private val nowMillis: () -> Long = System::currentTimeMillis
) {
    private val lock = Any()
    private var activeAccountKey: String? = null
    private val _deadlines = MutableStateFlow<Map<ExerciseRestTimerKey, Long>>(emptyMap())
    val deadlines: StateFlow<Map<ExerciseRestTimerKey, Long>> = _deadlines.asStateFlow()

    fun switchAccount(nextAccountKey: String?) {
        require(nextAccountKey == null || ACCOUNT_KEY_PATTERN.matches(nextAccountKey))
        synchronized(lock) {
            if (activeAccountKey == nextAccountKey) return
            if (activeAccountKey == null && nextAccountKey == null) {
                _deadlines.value = emptyMap()
                return
            }

            val now = nowMillis()
            val restored = if (activeAccountKey == null && nextAccountKey != null) {
                val snapshot = persistence.load()
                if (snapshot.accountKey == nextAccountKey) {
                    sanitizedDeadlines(snapshot.deadlines, nextAccountKey, now)
                } else {
                    emptyMap()
                }
            } else {
                emptyMap()
            }
            activeAccountKey = nextAccountKey
            val snapshot = ExerciseRestTimerSnapshot(nextAccountKey, restored)
            if (!persistence.save(snapshot)) {
                _deadlines.value = emptyMap()
                return
            }
            _deadlines.value = restored
        }
    }

    fun start(
        expectedAccountKey: String,
        sessionId: Long,
        workoutExerciseId: Long,
        seconds: Int
    ): Boolean = synchronized(lock) {
        if (activeAccountKey != expectedAccountKey ||
            !ACCOUNT_KEY_PATTERN.matches(expectedAccountKey) ||
            sessionId <= 0L || workoutExerciseId <= 0L ||
            seconds !in 1..MAX_EXERCISE_REST_SECONDS
        ) {
            return@synchronized false
        }
        val now = nowMillis()
        val durationMillis = seconds.toLong() * 1_000L
        if (now < 0L || now > Long.MAX_VALUE - durationMillis) return@synchronized false

        val next = sanitizedDeadlines(_deadlines.value, expectedAccountKey, now).toMutableMap()
        val key = ExerciseRestTimerKey(expectedAccountKey, sessionId, workoutExerciseId)
        if (key !in next && next.size >= WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
            return@synchronized false
        }
        next[key] = now + durationMillis
        val immutable = next.toMap()
        if (!persistence.save(ExerciseRestTimerSnapshot(expectedAccountKey, immutable))) {
            return@synchronized false
        }
        _deadlines.value = immutable
        true
    }

    fun stop(
        expectedAccountKey: String,
        sessionId: Long,
        workoutExerciseId: Long
    ): Boolean = synchronized(lock) {
        if (activeAccountKey != expectedAccountKey) return@synchronized false
        val key = ExerciseRestTimerKey(expectedAccountKey, sessionId, workoutExerciseId)
        if (key !in _deadlines.value) return@synchronized true
        val next = _deadlines.value - key
        if (!persistence.save(ExerciseRestTimerSnapshot(expectedAccountKey, next))) {
            return@synchronized false
        }
        _deadlines.value = next
        true
    }

    private fun sanitizedDeadlines(
        deadlines: Map<ExerciseRestTimerKey, Long>,
        accountKey: String,
        now: Long
    ): Map<ExerciseRestTimerKey, Long> {
        val maximumDurationMillis = MAX_EXERCISE_REST_SECONDS.toLong() * 1_000L
        if (now < 0L || now > Long.MAX_VALUE - maximumDurationMillis) return emptyMap()
        val maximumDeadline = now + maximumDurationMillis
        return deadlines.entries
            .asSequence()
            .filter { (key, deadline) ->
                key.accountKey == accountKey &&
                    key.sessionId > 0L && key.workoutExerciseId > 0L &&
                    deadline in (now + 1)..maximumDeadline
            }
            .sortedWith(
                compareBy<Map.Entry<ExerciseRestTimerKey, Long>>(
                    { it.key.sessionId },
                    { it.key.workoutExerciseId }
                )
            )
            .take(WorkoutDataLimits.MAX_EXERCISES_PER_SESSION)
            .associate { it.toPair() }
    }
}

internal class SharedPreferencesExerciseRestTimerPersistence(
    context: Context
) : ExerciseRestTimerPersistence {
    private val preferences = context.applicationContext.getSharedPreferences(
        EXERCISE_REST_TIMER_PREFS,
        Context.MODE_PRIVATE
    )

    override fun load(): ExerciseRestTimerSnapshot = runCatching {
        val accountKey = preferences.getString(OWNER_KEY, null)
            ?.takeIf(ACCOUNT_KEY_PATTERN::matches)
            ?: return@runCatching ExerciseRestTimerSnapshot(null, emptyMap())
        val encoded = preferences.getStringSet(DEADLINES_KEY, emptySet()).orEmpty()
        if (encoded.size > WorkoutDataLimits.MAX_EXERCISES_PER_SESSION) {
            return@runCatching ExerciseRestTimerSnapshot(accountKey, emptyMap())
        }
        val deadlines = encoded.mapNotNull { value ->
            val parts = value.split(':')
            if (parts.size != 3) return@mapNotNull null
            val sessionId = parts[0].toLongOrNull()?.takeIf { it > 0L }
                ?: return@mapNotNull null
            val workoutExerciseId = parts[1].toLongOrNull()?.takeIf { it > 0L }
                ?: return@mapNotNull null
            val deadline = parts[2].toLongOrNull()?.takeIf { it > 0L }
                ?: return@mapNotNull null
            ExerciseRestTimerKey(accountKey, sessionId, workoutExerciseId) to deadline
        }.toMap()
        ExerciseRestTimerSnapshot(accountKey, deadlines)
    }.getOrElse { ExerciseRestTimerSnapshot(null, emptyMap()) }

    override fun save(snapshot: ExerciseRestTimerSnapshot): Boolean {
        val accountKey = snapshot.accountKey
        if (accountKey == null) return preferences.edit().clear().commit()
        if (!ACCOUNT_KEY_PATTERN.matches(accountKey) ||
            snapshot.deadlines.size > WorkoutDataLimits.MAX_EXERCISES_PER_SESSION ||
            snapshot.deadlines.keys.any { key ->
                key.accountKey != accountKey || key.sessionId <= 0L || key.workoutExerciseId <= 0L
            }
        ) {
            return false
        }
        val encoded = snapshot.deadlines.mapTo(linkedSetOf()) { (key, deadline) ->
            "${key.sessionId}:${key.workoutExerciseId}:$deadline"
        }
        return preferences.edit()
            .putString(OWNER_KEY, accountKey)
            .putStringSet(DEADLINES_KEY, encoded)
            .commit()
    }
}
