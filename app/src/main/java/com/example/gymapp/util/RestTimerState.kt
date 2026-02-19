package com.example.gymapp.util

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object RestTimerState {
    private val _remainingSeconds = MutableStateFlow(0)
    val remainingSeconds: StateFlow<Int> = _remainingSeconds.asStateFlow()

    fun update(remainingSeconds: Int) {
        _remainingSeconds.value = remainingSeconds.coerceAtLeast(0)
    }
}
