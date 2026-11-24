package com.example.gymapp.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Per-device Connect state and the last pairing reset outcome of the Garmin card. */
internal data class GarminConnectUiState(
    val connectingDeviceId: Long? = null,
    val failedDeviceId: Long? = null,
    val resetRunning: Boolean = false,
    /** Outcome of the last reset: null until one finishes. */
    val resetSucceeded: Boolean? = null
)

/**
 * Runs the Garmin card's Connect and reset actions in the ViewModel scope, so rotation, leaving the
 * Watches screen or Back never cancels a pairing after the phone pinned the watch. Scoped to the
 * activity by the screen, so the connecting/failed state survives those too.
 */
internal class GarminConnectViewModel : ViewModel() {
    private val _state = MutableStateFlow(GarminConnectUiState())
    val state: StateFlow<GarminConnectUiState> = _state.asStateFlow()

    fun connect(deviceId: Long, pair: suspend (Long) -> Boolean) {
        var started = false
        _state.update {
            if (it.connectingDeviceId != null) {
                it
            } else {
                started = true
                it.copy(connectingDeviceId = deviceId, failedDeviceId = null)
            }
        }
        if (!started) return
        viewModelScope.launch {
            var paired = false
            try {
                paired = pair(deviceId)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                paired = false
            } finally {
                _state.update {
                    it.copy(connectingDeviceId = null, failedDeviceId = if (paired) null else deviceId)
                }
            }
        }
    }

    fun reset(run: suspend () -> Boolean) {
        var started = false
        _state.update {
            if (it.resetRunning) {
                it
            } else {
                started = true
                it.copy(resetRunning = true, resetSucceeded = null)
            }
        }
        if (!started) return
        viewModelScope.launch {
            var succeeded = false
            try {
                succeeded = run()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                succeeded = false
            } finally {
                _state.update { it.copy(resetRunning = false, resetSucceeded = succeeded) }
            }
        }
    }
}
