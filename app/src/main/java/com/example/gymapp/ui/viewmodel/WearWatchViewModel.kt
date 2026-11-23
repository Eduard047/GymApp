package com.example.gymapp.ui.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.GymApplication
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * State holder of the Wear OS card. The link itself (one pinned Data Layer node) is owned by
 * `PhoneWearBindingManager`; this only reads it, looks up the watch through Google Play services
 * off the main thread, and runs the user's "Unlink watch". Any Play services error degrades to
 * "not linked" (or a hidden card when the Wearable API is missing), never to a crash.
 */
internal class WearWatchViewModel(
    private val application: GymApplication
) : ViewModel() {
    private val _state = MutableStateFlow(WearWatchUiState())
    val state: StateFlow<WearWatchUiState> = _state.asStateFlow()

    // Serializes lookups and the unlink so a slow lookup cannot resurrect a just-unlinked watch.
    private val mutex = Mutex()

    /** Re-reads the link and the watch connection (Watches screen or Profile opened). */
    fun refresh() {
        viewModelScope.launch { mutex.withLock { _state.value = lookup() } }
    }

    /** Forgets the linked watch. Workouts not yet sent from the watch stay on the watch. */
    fun unlink() {
        _state.update { it.copy(linked = false, connected = false, displayName = null) }
        viewModelScope.launch {
            mutex.withLock {
                withContext(Dispatchers.IO) {
                    attempt { application.phoneWearSyncManager.unlinkWatch() }
                }
                _state.value = lookup()
            }
        }
    }

    private suspend fun lookup(): WearWatchUiState = withContext(Dispatchers.IO) {
        val nodeClient = attempt { Wearable.getNodeClient(application) }
            ?: return@withContext WearWatchUiState()
        val available = attempt {
            GoogleApiAvailability.getInstance().checkApiAvailability(nodeClient).await()
            true
        } == true
        if (!available) return@withContext wearWatchUiState(false, null, emptyMap())
        val pinned = attempt { application.phoneWearSyncManager.pinnedWatchNodeId() }
        val nodes = if (pinned == null) {
            emptyMap()
        } else {
            attempt {
                nodeClient.connectedNodes.await().associate { node -> node.id to node.displayName }
            } ?: emptyMap()
        }
        wearWatchUiState(apiAvailable = true, pinnedNodeId = pinned, connectedNodes = nodes)
    }

    private suspend fun <T> attempt(block: suspend () -> T): T? = try {
        withTimeoutOrNull(LOOKUP_TIMEOUT_MS) { block() }
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        Log.w(TAG, "Wear OS lookup failed: ${error.javaClass.simpleName}")
        null
    }

    companion object {
        private const val TAG = "WearWatchViewModel"
        private const val LOOKUP_TIMEOUT_MS = 5_000L

        fun factory(application: GymApplication): ViewModelProvider.Factory = viewModelFactory {
            initializer { WearWatchViewModel(application) }
        }
    }
}
