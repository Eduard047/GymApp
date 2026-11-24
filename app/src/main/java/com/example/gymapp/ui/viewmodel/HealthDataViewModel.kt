package com.example.gymapp.ui.viewmodel

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.health.connect.client.HealthConnectClient
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.example.gymapp.data.repository.GymRepository
import com.example.gymapp.health.HealthConnectAvailability
import com.example.gymapp.health.HealthConnectImporter
import com.example.gymapp.health.HealthImportStatus
import com.example.gymapp.health.HealthImportTrigger
import com.example.gymapp.util.AppLanguage
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * State holder of the Health data card. Bound to one account: [repository] comes from
 * `repositoryFor(session)` and [isAccountActive] reports whether that account is still active.
 *
 * Nothing here asks for permissions on its own: the card launches the Health Connect permission
 * screen from a button and calls [onPermissionRequestFinished] with the outcome.
 */
class HealthDataViewModel(
    context: Context,
    private val repository: GymRepository,
    language: () -> AppLanguage,
    isAccountActive: () -> Boolean
) : ViewModel() {
    private val appContext = context.applicationContext
    private val importer = HealthConnectImporter(appContext, repository, language, isAccountActive)

    private val _state = MutableStateFlow(
        HealthDataUiState(availability = HealthConnectImporter.availability(appContext))
    )
    val state: StateFlow<HealthDataUiState> = _state.asStateFlow()

    /** Re-reads availability, permission and the last import time (card shown, app resumed). */
    fun refresh() {
        viewModelScope.launch { refreshNow() }
    }

    /** The permission screen closed: when access was granted, remember it and import now. */
    fun onPermissionRequestFinished() {
        viewModelScope.launch {
            val granted = attempt { HealthConnectImporter.hasExercisePermission(appContext) } == true
            // The per-account opt-in lives in the importer; auto-import runs only once it is set.
            if (granted) attempt { importer.setEnabled(true) }
            refreshNow()
            // Declined, or Health Connect no longer shows its screen (after two declines it returns at
            // once): say so and let the card offer the Health Connect settings.
            if (!granted) _state.update { it.copy(notice = HealthImportNotice.ACCESS_DENIED) }
            if (granted) runImport(HealthImportTrigger.MANUAL)
        }
    }

    fun importNow() {
        viewModelScope.launch { runImport(HealthImportTrigger.MANUAL) }
    }

    /** App came to the foreground: imports only when connected; the importer throttles itself. */
    fun importOnForeground() {
        viewModelScope.launch {
            if (_state.value.running) return@launch
            refreshNow()
            if (shouldRunAutoImport(_state.value)) runImport(HealthImportTrigger.AUTOMATIC)
        }
    }

    /** Stops auto-import and revokes the Health Connect permissions this app holds. */
    fun disconnect() {
        // Shown and gated first: even if the revoke is slow or fails, auto-import is already off.
        _state.update { it.copy(connected = false, notice = HealthImportNotice.NONE) }
        viewModelScope.launch {
            attempt { importer.setEnabled(false) }
            // Health Connect exists from API 26; below it there is nothing to revoke.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                _state.value.availability == HealthConnectAvailability.AVAILABLE
            ) {
                attempt { revokeAllPermissions() }
            }
            refreshNow()
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private suspend fun revokeAllPermissions() {
        HealthConnectClient.getOrCreate(appContext).permissionController.revokeAllPermissions()
    }

    private suspend fun refreshNow() {
        val availability = HealthConnectImporter.availability(appContext)
        val permitted = availability == HealthConnectAvailability.AVAILABLE &&
            attempt { HealthConnectImporter.hasExercisePermission(appContext) } == true
        val connected = permitted && attempt { importer.isEnabled() } == true
        val last = attempt { repository.healthImportLastImportAt() }
        // A failed read leaves the count out; the card then shows the shorter "Last import" line.
        val total = attempt { importer.importedCount() }
        _state.update {
            it.copy(
                availability = availability,
                connected = connected,
                notice = if (connected && it.notice == HealthImportNotice.ACCESS_DENIED) {
                    HealthImportNotice.NONE
                } else {
                    it.notice
                },
                lastImportAtMillis = last,
                importedTotal = total
            )
        }
    }

    private suspend fun runImport(trigger: HealthImportTrigger) {
        if (_state.value.running) return
        val manual = trigger == HealthImportTrigger.MANUAL
        _state.update {
            it.copy(running = true, notice = if (manual) HealthImportNotice.NONE else it.notice)
        }
        var failed = false
        var completed = false
        var imported = 0
        var disconnected = false
        try {
            val summary = importer.run(trigger)
            disconnected = healthImportStatusMeansDisconnected(summary.status)
            completed = summary.status == HealthImportStatus.COMPLETED
            imported = summary.imported
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (error: Exception) {
            failed = true
            // Class name only: messages can carry workout data.
            Log.w(TAG, "Health import failed: ${error.javaClass.simpleName}")
        } finally {
            _state.update { it.copy(running = false) }
        }
        refreshNow()
        _state.update {
            it.copy(
                // Opt-in off or permission gone: show "not connected", never prompt for access.
                connected = it.connected && !disconnected,
                notice = healthImportNotice(manual, failed, completed, imported)
            )
        }
    }

    private suspend fun <T> attempt(block: suspend () -> T): T? = try {
        block()
    } catch (cancellation: CancellationException) {
        throw cancellation
    } catch (_: Exception) {
        null
    }

    companion object {
        private const val TAG = "HealthDataViewModel"

        fun factory(
            context: Context,
            repository: GymRepository,
            language: () -> AppLanguage,
            isAccountActive: () -> Boolean
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                HealthDataViewModel(context.applicationContext, repository, language, isAccountActive)
            }
        }
    }
}
