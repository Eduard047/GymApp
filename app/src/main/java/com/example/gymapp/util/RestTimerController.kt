package com.example.gymapp.util

import android.content.Context
import com.example.gymapp.service.RestTimerService
import kotlinx.coroutines.flow.StateFlow

class RestTimerController(
    private val appContext: Context
) {
    val remainingSeconds: StateFlow<Int> = RestTimerState.remainingSeconds

    fun start(seconds: Int) {
        RestTimerService.start(appContext, seconds)
    }

    fun stop() {
        RestTimerService.stop(appContext)
    }
}
