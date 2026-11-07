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
    private val setFinishedExercise: (exerciseName: String?) -> Unit = {}
) {
    constructor(appContext: Context) : this(
        ExerciseRestTimerLedger(SharedPreferencesExerciseRestTimerPersistence(appContext)),
        ActiveWorkoutTimerLedger(SharedPreferencesActiveWorkoutTimerPersistence(appContext)),
        { seconds -> RestTimerService.start(appContext, seconds) },
        { RestTimerService.stop(appContext) },
        { exerciseName -> RestTimerService.setFinishedExercise(appContext, exerciseName) }
    )

    private val accountSwitchTracker = RestTimerAccountSwitchTracker()
    val remainingSeconds: StateFlow<Int> = RestTimerState.remainingSeconds
    internal val exerciseRestDeadlineMillis = exerciseTimers.deadlines
    internal val activeWorkoutTimerSnapshot = activeWorkoutTimer.snapshot

    internal fun switchAccount(session: com.example.gymapp.auth.AccountSession?) {
        val accountKey = restTimerAccountKey(session)
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
        return exerciseCleared && activeWorkoutCleared && foregroundCleared
    }

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
        return exerciseCleared && activeWorkoutCleared && foregroundCleared
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
