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

class RestTimerController(
    private val appContext: Context
) {
    private val exerciseTimers = ExerciseRestTimerLedger(
        SharedPreferencesExerciseRestTimerPersistence(appContext)
    )
    private val activeWorkoutTimer = ActiveWorkoutTimerLedger(
        SharedPreferencesActiveWorkoutTimerPersistence(appContext)
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
            RestTimerService.stop(appContext)
        }
        exerciseTimers.switchAccount(accountKey)
        activeWorkoutTimer.switchAccount(accountKey)
    }

    fun start(seconds: Int) {
        RestTimerService.start(appContext, seconds)
    }

    fun stop() {
        RestTimerService.stop(appContext)
    }

    internal fun ensureActiveWorkoutTimer(
        accountKey: String,
        sessionStartedAt: Long
    ): Boolean = activeWorkoutTimer.ensureSession(accountKey, sessionStartedAt)

    internal fun startActiveWorkoutRest(
        accountKey: String,
        sessionStartedAt: Long,
        seconds: Int
    ): Boolean {
        if (!activeWorkoutTimer.startRest(accountKey, sessionStartedAt, seconds)) return false
        return runCatching {
            RestTimerService.start(appContext, seconds)
            true
        }.getOrDefault(false)
    }

    internal fun stopActiveWorkoutRest(
        accountKey: String,
        sessionStartedAt: Long
    ): Boolean {
        if (!activeWorkoutTimer.resume(accountKey, sessionStartedAt)) return false
        return runCatching {
            RestTimerService.stop(appContext)
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
        return runCatching {
            if (remaining > 0) RestTimerService.start(appContext, remaining)
            else RestTimerService.stop(appContext)
            remaining
        }.getOrNull()
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
            runCatching { RestTimerService.stop(appContext) }.isSuccess
        } else {
            true
        }
        return exerciseCleared && activeWorkoutCleared && foregroundCleared
    }

    internal fun clearAccount(session: com.example.gymapp.auth.AccountSession.Cloud): Boolean =
        clearAccount(session.databaseName(), session.sessionGeneration)

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
