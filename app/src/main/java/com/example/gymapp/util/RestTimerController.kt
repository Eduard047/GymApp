package com.example.gymapp.util

import android.content.Context
import com.example.gymapp.auth.databaseName
import com.example.gymapp.service.RestTimerService
import kotlinx.coroutines.flow.StateFlow

internal class RestTimerAccountSwitchTracker {
    private var initialized = false
    private var accountKey: String? = null

    fun bind(nextAccountKey: String?): Boolean {
        val changed = initialized && accountKey != nextAccountKey
        initialized = true
        accountKey = nextAccountKey
        return changed
    }

    fun isBoundTo(expectedAccountKey: String): Boolean =
        initialized && accountKey == expectedAccountKey
}

class RestTimerController internal constructor(
    private val exerciseTimers: ExerciseRestTimerLedger,
    private val activeWorkoutTimer: ActiveWorkoutTimerLedger,
    private val startService: (seconds: Int) -> Unit,
    private val stopService: () -> Unit,
    private val setFinishedExercise: (exerciseName: String?) -> Unit = {},
    /** Wipes the account's device-local exercise cues (by database name) when the account is deleted. */
    private val clearExerciseCues: (databaseName: String) -> Boolean = { true },
    /** Wipes the account's device-local custom exercise rest times (by database name) when the account is deleted. */
    private val clearExerciseRestTimes: (databaseName: String) -> Boolean = { true },
    /** Reads one custom rest (disk I/O: call off the main thread). */
    private val readExerciseRestSeconds: (databaseName: String, identityKey: String) -> Int? = { _, _ -> null }
) {
    constructor(appContext: Context) : this(
        ExerciseRestTimerLedger(SharedPreferencesExerciseRestTimerPersistence(appContext)),
        ActiveWorkoutTimerLedger(SharedPreferencesActiveWorkoutTimerPersistence(appContext)),
        { seconds -> RestTimerService.start(appContext, seconds) },
        { RestTimerService.stop(appContext) },
        { exerciseName -> RestTimerService.setFinishedExercise(appContext, exerciseName) },
        ExerciseCueStore.forContext(appContext)::clearAccount,
        ExerciseRestTimeStore.forContext(appContext)::clearAccount,
        ExerciseRestTimeStore.forContext(appContext)::restSeconds
    )

    private val accountSwitchTracker = RestTimerAccountSwitchTracker()
    /** The bound account key and its database name, swapped together so readers never see a mixed pair. */
    @Volatile private var boundAccount: Pair<String, String>? = null
    val remainingSeconds: StateFlow<Int> = RestTimerState.remainingSeconds
    internal val exerciseRestDeadlineMillis = exerciseTimers.deadlines
    internal val activeWorkoutTimerSnapshot = activeWorkoutTimer.snapshot

    internal fun switchAccount(session: com.example.gymapp.auth.AccountSession?) {
        val accountKey = restTimerAccountKey(session)
        val databaseName = session?.databaseName()
        boundAccount = if (accountKey != null && databaseName != null) accountKey to databaseName else null
        if (accountSwitchTracker.bind(accountKey)) {
            // The foreground countdown is process-global. Clear it synchronously before
            // exposing the next account so stale timer state cannot cross that boundary.
            RestTimerState.update(0)
            stopService()
        }
        exerciseTimers.switchAccount(accountKey)
        activeWorkoutTimer.switchAccount(accountKey)
    }

    fun start(seconds: Int) {
        runCatching { setFinishedExercise(null) }
        startService(seconds)
    }

    fun stop() {
        stopService()
    }

    internal fun ensureActiveWorkoutTimer(
        accountKey: String,
        sessionStartedAt: Long
    ): Boolean = activeWorkoutTimer.ensureSession(accountKey, sessionStartedAt)

    internal fun startActiveWorkoutRest(
        accountKey: String,
        sessionStartedAt: Long,
        seconds: Int,
        exerciseName: String? = null
    ): Boolean {
        if (!activeWorkoutTimer.startRest(accountKey, sessionStartedAt, seconds)) return false
        // Stored before the service starts so the finished alert can name the exercise even if
        // the process dies mid-rest. Raw catalog name; the alert localizes it when it is posted.
        runCatching { setFinishedExercise(exerciseName) }
        // The ledger already holds the deadline, so the rest started even if the service did not.
        runCatching { startService(seconds) }
        return true
    }

    internal fun stopActiveWorkoutRest(
        accountKey: String,
        sessionStartedAt: Long
    ): Boolean {
        if (!activeWorkoutTimer.resume(accountKey, sessionStartedAt)) return false
        return runCatching {
            stopService()
            true
        }.getOrDefault(false)
    }

    internal fun adjustActiveWorkoutRest(
        accountKey: String,
        sessionStartedAt: Long,
        deltaSeconds: Int
    ): Int? {
        val remaining = activeWorkoutTimer.adjustRest(
            accountKey,
            sessionStartedAt,
            deltaSeconds
        ) ?: return null
        // The ledger already holds the new deadline; a service failure must not report a failed save.
        runCatching {
            if (remaining > 0) startService(remaining) else stopService()
        }
        return remaining
    }

    internal fun resumeActiveWorkoutRestIfExpired(
        accountKey: String,
        sessionStartedAt: Long
    ): Boolean = activeWorkoutTimer.resumeIfExpired(accountKey, sessionStartedAt)

    internal fun clearActiveWorkoutTimer(
        accountKey: String,
        sessionStartedAt: Long
    ): Boolean = activeWorkoutTimer.clear(accountKey, sessionStartedAt)

    internal fun clearAccount(
        databaseName: String,
        sessionGeneration: String
    ): Boolean {
        val expectedAccountKey = restTimerAccountKey(databaseName, sessionGeneration)
            ?: return false
        val exerciseCleared = runCatching {
            exerciseTimers.clearAccount(expectedAccountKey)
        }.getOrDefault(false)
        val activeWorkoutCleared = runCatching {
            activeWorkoutTimer.clearAccount(expectedAccountKey)
        }.getOrDefault(false)
        val foregroundCleared = if (accountSwitchTracker.isBoundTo(expectedAccountKey)) {
            RestTimerState.update(0)
            runCatching { stopService() }.isSuccess
        } else {
            true
        }
        val cuesCleared = runCatching { clearExerciseCues(databaseName) }.getOrDefault(false)
        val restTimesCleared = runCatching { clearExerciseRestTimes(databaseName) }.getOrDefault(false)
        return exerciseCleared && activeWorkoutCleared && foregroundCleared && cuesCleared && restTimesCleared
    }

    /**
     * The exercise's custom rest for the account bound as [accountKey], or null (no custom rest, another
     * account, or an unusable key). Disk I/O: call off the main thread.
     */
    internal fun customRestSeconds(accountKey: String, identityKey: String): Int? {
        val bound = boundAccount ?: return null
        if (bound.first != accountKey || !accountSwitchTracker.isBoundTo(accountKey)) return null
        val databaseName = bound.second
        return runCatching { readExerciseRestSeconds(databaseName, identityKey) }.getOrNull()
    }

    /** Same as above for a caller that already holds the account's [databaseName]. Disk I/O. */
    internal fun customRestSecondsFor(databaseName: String, identityKey: String): Int? =
        runCatching { readExerciseRestSeconds(databaseName, identityKey) }.getOrNull()

    internal fun clearAccount(session: com.example.gymapp.auth.AccountSession.Cloud): Boolean =
        clearAccount(session.databaseName(), session.sessionGeneration)

    internal fun clearLocalAccount(databaseName: String): Boolean {
        val expectedAccountKey = restTimerAccountKey(databaseName, null) ?: return false
        val exerciseCleared = runCatching {
            exerciseTimers.clearAccount(expectedAccountKey)
        }.getOrDefault(false)
        val activeWorkoutCleared = runCatching {
            activeWorkoutTimer.clearAccount(expectedAccountKey)
        }.getOrDefault(false)
        val foregroundCleared = if (accountSwitchTracker.isBoundTo(expectedAccountKey)) {
            RestTimerState.update(0)
            runCatching { stopService() }.isSuccess
        } else {
            true
        }
        val cuesCleared = runCatching { clearExerciseCues(databaseName) }.getOrDefault(false)
        val restTimesCleared = runCatching { clearExerciseRestTimes(databaseName) }.getOrDefault(false)
        return exerciseCleared && activeWorkoutCleared && foregroundCleared && cuesCleared && restTimesCleared
    }

    internal fun startExercise(
        accountKey: String,
        sessionId: Long,
        workoutExerciseId: Long,
        seconds: Int
    ): Boolean = exerciseTimers.start(accountKey, sessionId, workoutExerciseId, seconds)

    internal fun stopExercise(
        accountKey: String,
        sessionId: Long,
        workoutExerciseId: Long
    ): Boolean = exerciseTimers.stop(accountKey, sessionId, workoutExerciseId)
}
