package com.example.gymapp.util

import android.content.Context
import com.example.gymapp.service.RestTimerService
import kotlinx.coroutines.flow.StateFlow

class RestTimerController(
    private val appContext: Context
) {
    private val exerciseTimers = ExerciseRestTimerLedger(
        SharedPreferencesExerciseRestTimerPersistence(appContext)
    )
    val remainingSeconds: StateFlow<Int> = RestTimerState.remainingSeconds
    internal val exerciseRestDeadlineMillis = exerciseTimers.deadlines

    internal fun switchAccount(session: com.example.gymapp.auth.AccountSession?) {
        exerciseTimers.switchAccount(restTimerAccountKey(session))
    }

    fun start(seconds: Int) {
        RestTimerService.start(appContext, seconds)
    }

    fun stop() {
        RestTimerService.stop(appContext)
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
