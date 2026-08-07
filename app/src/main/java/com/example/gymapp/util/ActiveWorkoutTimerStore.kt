package com.example.gymapp.util

import android.content.Context
import com.example.gymapp.data.repository.WorkoutDataLimits
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal const val MAX_ACTIVE_WORKOUT_REST_SECONDS = 300
internal const val MAX_ACTIVE_WORKOUT_TIMER_MILLIS = 365L * 24L * 60L * 60L * 1_000L
private const val ACTIVE_WORKOUT_TIMER_PREFS = "gym_active_workout_timer"
private const val TIMER_OWNER_KEY = "owner"
private const val TIMER_SESSION_STARTED_AT_KEY = "session_started_at"
private const val TIMER_ACCUMULATED_ACTIVE_KEY = "accumulated_active"
private const val TIMER_ACTIVE_SEGMENT_STARTED_AT_KEY = "active_segment_started_at"
private const val TIMER_REST_ENDS_AT_KEY = "rest_ends_at"
private val ACTIVE_TIMER_ACCOUNT_KEY_PATTERN = Regex("^[a-f0-9]{64}$")

internal data class ActiveWorkoutTimerSnapshot(
    val accountKey: String,
    val sessionStartedAt: Long,
    val accumulatedActiveMillis: Long,
    val activeSegmentStartedAt: Long?,
    val restEndsAt: Long?
)

internal interface ActiveWorkoutTimerPersistence {
    fun load(): ActiveWorkoutTimerSnapshot?
    fun save(snapshot: ActiveWorkoutTimerSnapshot?): Boolean
}

internal fun activeWorkoutElapsedMillis(
    snapshot: ActiveWorkoutTimerSnapshot?,
    nowMillis: Long
): Long {
    snapshot ?: return 0L
    val runningSince = when {
        snapshot.activeSegmentStartedAt != null -> snapshot.activeSegmentStartedAt
        snapshot.restEndsAt != null && nowMillis > snapshot.restEndsAt -> snapshot.restEndsAt
        else -> null
    }
    val runningDelta = runningSince
        ?.let { start -> (nowMillis - start).coerceAtLeast(0L) }
        ?: 0L
    return safeActiveTimerAdd(snapshot.accumulatedActiveMillis, runningDelta)
}

internal fun activeWorkoutRestSecondsRemaining(
    snapshot: ActiveWorkoutTimerSnapshot?,
    nowMillis: Long
): Int {
    val deadline = snapshot?.restEndsAt ?: return 0
    val remainingMillis = (deadline - nowMillis).coerceAtLeast(0L)
    return ((remainingMillis + 999L) / 1_000L)
        .coerceAtMost(MAX_ACTIVE_WORKOUT_REST_SECONDS.toLong())
        .toInt()
}

/**
 * Account/session-bound durable clock for the local active workout.
 *
 * Only state transitions are persisted: active time is derived from wall-clock timestamps, while
 * rest intervals pause it. Expired rest resumes at its deadline, so reopening the process cannot
 * count the same rest twice. The single persisted snapshot is never exposed after an account
 * switch unless its hashed owner binding matches the active account.
 */
internal class ActiveWorkoutTimerLedger(
    private val persistence: ActiveWorkoutTimerPersistence,
    private val nowMillis: () -> Long = System::currentTimeMillis
) {
    private val lock = Any()
    private var activeAccountKey: String? = null
    private val _snapshot = MutableStateFlow<ActiveWorkoutTimerSnapshot?>(null)
    val snapshot: StateFlow<ActiveWorkoutTimerSnapshot?> = _snapshot.asStateFlow()

    fun switchAccount(nextAccountKey: String?) {
        require(nextAccountKey == null || ACTIVE_TIMER_ACCOUNT_KEY_PATTERN.matches(nextAccountKey))
        synchronized(lock) {
            if (activeAccountKey == nextAccountKey) return
            val restored = if (activeAccountKey == null && nextAccountKey != null) {
                val candidate = persistence.load()
                    ?.takeIf { stored -> stored.accountKey == nextAccountKey }
                    ?.let { stored -> sanitize(stored, nowMillis()) }
                if (candidate == null) persistence.save(null)
                candidate
            } else {
                persistence.save(null)
                null
            }
            activeAccountKey = nextAccountKey
            _snapshot.value = restored
        }
    }

    fun ensureSession(expectedAccountKey: String, sessionStartedAt: Long): Boolean =
        synchronized(lock) {
            if (!matchesActiveAccount(expectedAccountKey) ||
                !WorkoutDataLimits.isValidTimestamp(sessionStartedAt)
            ) {
                return@synchronized false
            }
            val current = _snapshot.value
            if (current?.accountKey == expectedAccountKey &&
                current.sessionStartedAt == sessionStartedAt
            ) {
                return@synchronized true
            }
            val now = nowMillis()
            if (!WorkoutDataLimits.isValidTimestamp(now)) return@synchronized false
            val initialized = ActiveWorkoutTimerSnapshot(
                accountKey = expectedAccountKey,
                sessionStartedAt = sessionStartedAt,
                accumulatedActiveMillis = 0L,
                activeSegmentStartedAt = sessionStartedAt.coerceAtMost(now),
                restEndsAt = null
            )
            persistAndPublish(initialized)
        }

    fun startRest(
        expectedAccountKey: String,
        sessionStartedAt: Long,
        seconds: Int
    ): Boolean = synchronized(lock) {
        val current = matchingSession(expectedAccountKey, sessionStartedAt)
            ?: return@synchronized false
        if (seconds !in 1..MAX_ACTIVE_WORKOUT_REST_SECONDS) return@synchronized false
        val now = nowMillis()
        val durationMillis = seconds.toLong() * 1_000L
        if (!WorkoutDataLimits.isValidTimestamp(now) ||
            now > WorkoutDataLimits.MAX_TIMESTAMP_MILLIS - durationMillis
        ) {
            return@synchronized false
        }
        persistAndPublish(
            current.copy(
                accumulatedActiveMillis = activeWorkoutElapsedMillis(current, now),
                activeSegmentStartedAt = null,
                restEndsAt = now + durationMillis
            )
        )
    }

    fun resume(
        expectedAccountKey: String,
        sessionStartedAt: Long
    ): Boolean = synchronized(lock) {
        val current = matchingSession(expectedAccountKey, sessionStartedAt)
            ?: return@synchronized false
        val restEndsAt = current.restEndsAt ?: return@synchronized true
        val now = nowMillis()
        if (!WorkoutDataLimits.isValidTimestamp(now)) return@synchronized false
        val resumedAt = if (now >= restEndsAt) restEndsAt else now
        persistAndPublish(
            current.copy(
                activeSegmentStartedAt = resumedAt,
                restEndsAt = null
            )
        )
    }

    fun adjustRest(
        expectedAccountKey: String,
        sessionStartedAt: Long,
        deltaSeconds: Int
    ): Int? = synchronized(lock) {
        val current = matchingSession(expectedAccountKey, sessionStartedAt)
            ?: return@synchronized null
        val deadline = current.restEndsAt ?: return@synchronized 0
        if (deltaSeconds !in -15..15 || deltaSeconds == 0) return@synchronized null
        val now = nowMillis()
        if (!WorkoutDataLimits.isValidTimestamp(now)) return@synchronized null
        if (now >= deadline) {
            val resumed = current.copy(activeSegmentStartedAt = deadline, restEndsAt = null)
            return@synchronized if (persistAndPublish(resumed)) 0 else null
        }
        val currentRemaining = activeWorkoutRestSecondsRemaining(current, now)
        val nextRemaining = (currentRemaining + deltaSeconds)
            .coerceAtMost(MAX_ACTIVE_WORKOUT_REST_SECONDS)
        if (nextRemaining <= 0) {
            val resumed = current.copy(activeSegmentStartedAt = now, restEndsAt = null)
            return@synchronized if (persistAndPublish(resumed)) 0 else null
        }
        val durationMillis = nextRemaining.toLong() * 1_000L
        if (now > WorkoutDataLimits.MAX_TIMESTAMP_MILLIS - durationMillis) {
            return@synchronized null
        }
        val adjusted = current.copy(restEndsAt = now + durationMillis)
        if (persistAndPublish(adjusted)) nextRemaining else null
    }

    fun resumeIfExpired(
        expectedAccountKey: String,
        sessionStartedAt: Long
    ): Boolean = synchronized(lock) {
        val current = matchingSession(expectedAccountKey, sessionStartedAt)
            ?: return@synchronized false
        val deadline = current.restEndsAt ?: return@synchronized true
        val now = nowMillis()
        if (now < deadline) return@synchronized true
        persistAndPublish(current.copy(activeSegmentStartedAt = deadline, restEndsAt = null))
    }

    fun clear(expectedAccountKey: String, sessionStartedAt: Long): Boolean = synchronized(lock) {
        matchingSession(expectedAccountKey, sessionStartedAt) ?: return@synchronized false
        if (!persistence.save(null)) return@synchronized false
        _snapshot.value = null
        true
    }

    fun clearAccount(expectedAccountKey: String): Boolean = synchronized(lock) {
        if (!ACTIVE_TIMER_ACCOUNT_KEY_PATTERN.matches(expectedAccountKey)) {
            return@synchronized false
        }
        if (activeAccountKey == expectedAccountKey) {
            if (!persistence.save(null)) return@synchronized false
            _snapshot.value = null
            return@synchronized true
        }
        val stored = persistence.load()
        if (stored?.accountKey != expectedAccountKey) return@synchronized true
        persistence.save(null)
    }

    private fun matchingSession(
        expectedAccountKey: String,
        sessionStartedAt: Long
    ): ActiveWorkoutTimerSnapshot? = _snapshot.value?.takeIf { current ->
        matchesActiveAccount(expectedAccountKey) &&
            current.accountKey == expectedAccountKey &&
            current.sessionStartedAt == sessionStartedAt
    }

    private fun matchesActiveAccount(expectedAccountKey: String): Boolean =
        activeAccountKey == expectedAccountKey &&
            ACTIVE_TIMER_ACCOUNT_KEY_PATTERN.matches(expectedAccountKey)

    private fun persistAndPublish(next: ActiveWorkoutTimerSnapshot): Boolean {
        val sanitized = sanitize(next, nowMillis()) ?: return false
        if (!persistence.save(sanitized)) return false
        _snapshot.value = sanitized
        return true
    }

    private fun sanitize(
        candidate: ActiveWorkoutTimerSnapshot,
        now: Long
    ): ActiveWorkoutTimerSnapshot? {
        if (!WorkoutDataLimits.isValidTimestamp(now) ||
            !ACTIVE_TIMER_ACCOUNT_KEY_PATTERN.matches(candidate.accountKey) ||
            !WorkoutDataLimits.isValidTimestamp(candidate.sessionStartedAt) ||
            candidate.accumulatedActiveMillis !in 0L..MAX_ACTIVE_WORKOUT_TIMER_MILLIS ||
            (candidate.activeSegmentStartedAt == null) == (candidate.restEndsAt == null)
        ) {
            return null
        }
        candidate.activeSegmentStartedAt?.let { startedAt ->
            if (!WorkoutDataLimits.isValidTimestamp(startedAt) ||
                startedAt < candidate.sessionStartedAt || startedAt > now
            ) return null
        }
        candidate.restEndsAt?.let { deadline ->
            if (!WorkoutDataLimits.isValidTimestamp(deadline) ||
                deadline < candidate.sessionStartedAt
            ) return null
            val maximumFutureDeadline = now +
                MAX_ACTIVE_WORKOUT_REST_SECONDS.toLong() * 1_000L
            if (now <= WorkoutDataLimits.MAX_TIMESTAMP_MILLIS -
                MAX_ACTIVE_WORKOUT_REST_SECONDS.toLong() * 1_000L &&
                deadline > maximumFutureDeadline
            ) return null
        }
        return candidate
    }
}

internal class SharedPreferencesActiveWorkoutTimerPersistence(
    context: Context
) : ActiveWorkoutTimerPersistence {
    private val preferences = context.applicationContext.getSharedPreferences(
        ACTIVE_WORKOUT_TIMER_PREFS,
        Context.MODE_PRIVATE
    )

    override fun load(): ActiveWorkoutTimerSnapshot? = runCatching {
        val owner = preferences.getString(TIMER_OWNER_KEY, null)
            ?.takeIf(ACTIVE_TIMER_ACCOUNT_KEY_PATTERN::matches)
            ?: return@runCatching null
        val sessionStartedAt = preferences.getLong(TIMER_SESSION_STARTED_AT_KEY, Long.MIN_VALUE)
        val accumulated = preferences.getLong(TIMER_ACCUMULATED_ACTIVE_KEY, -1L)
        val activeStartedAt = preferences.getLong(
            TIMER_ACTIVE_SEGMENT_STARTED_AT_KEY,
            Long.MIN_VALUE
        ).takeUnless { it == Long.MIN_VALUE }
        val restEndsAt = preferences.getLong(TIMER_REST_ENDS_AT_KEY, Long.MIN_VALUE)
            .takeUnless { it == Long.MIN_VALUE }
        ActiveWorkoutTimerSnapshot(
            accountKey = owner,
            sessionStartedAt = sessionStartedAt,
            accumulatedActiveMillis = accumulated,
            activeSegmentStartedAt = activeStartedAt,
            restEndsAt = restEndsAt
        )
    }.getOrNull()

    override fun save(snapshot: ActiveWorkoutTimerSnapshot?): Boolean {
        if (snapshot == null) return preferences.edit().clear().commit()
        if (!ACTIVE_TIMER_ACCOUNT_KEY_PATTERN.matches(snapshot.accountKey)) return false
        return preferences.edit()
            .clear()
            .putString(TIMER_OWNER_KEY, snapshot.accountKey)
            .putLong(TIMER_SESSION_STARTED_AT_KEY, snapshot.sessionStartedAt)
            .putLong(TIMER_ACCUMULATED_ACTIVE_KEY, snapshot.accumulatedActiveMillis)
            .apply {
                snapshot.activeSegmentStartedAt?.let {
                    putLong(TIMER_ACTIVE_SEGMENT_STARTED_AT_KEY, it)
                }
                snapshot.restEndsAt?.let { putLong(TIMER_REST_ENDS_AT_KEY, it) }
            }
            .commit()
    }
}

private fun safeActiveTimerAdd(left: Long, right: Long): Long {
    if (left !in 0L..MAX_ACTIVE_WORKOUT_TIMER_MILLIS || right < 0L) return 0L
    return if (right >= MAX_ACTIVE_WORKOUT_TIMER_MILLIS - left) {
        MAX_ACTIVE_WORKOUT_TIMER_MILLIS
    } else {
        left + right
    }
}
