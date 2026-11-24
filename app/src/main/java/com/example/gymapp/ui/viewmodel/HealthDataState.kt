package com.example.gymapp.ui.viewmodel

import com.example.gymapp.health.HealthConnectAvailability
import com.example.gymapp.health.HealthImportStatus

/** What the Health data card shows. Chosen only by [healthDataCardMode]. */
enum class HealthDataCardMode {
    /** Health Connect cannot be used on this phone and nothing can fix that from the app. */
    UNAVAILABLE,

    /** The Health Connect app is missing or outdated; the card offers the Play Store page. */
    INSTALL_REQUIRED,

    NOT_CONNECTED,
    CONNECTED,

    /** An import (manual or after granting access) is in progress. */
    IMPORTING
}

/** Message shown under the card's status line after a manual import. */
enum class HealthImportNotice { NONE, EMPTY, FAILED, ACCESS_DENIED }

data class HealthDataUiState(
    val availability: HealthConnectAvailability = HealthConnectAvailability.UNAVAILABLE,
    /** Exercise permission granted and the user connected the import from this card. */
    val connected: Boolean = false,
    val running: Boolean = false,
    val lastImportAtMillis: Long? = null,
    /** Workouts imported so far; null while the app cannot tell, and the summary then omits it. */
    val importedTotal: Int? = null,
    val notice: HealthImportNotice = HealthImportNotice.NONE
)

fun healthDataCardMode(state: HealthDataUiState): HealthDataCardMode = when {
    state.availability == HealthConnectAvailability.PROVIDER_UPDATE_REQUIRED ->
        HealthDataCardMode.INSTALL_REQUIRED
    state.availability != HealthConnectAvailability.AVAILABLE -> HealthDataCardMode.UNAVAILABLE
    state.running -> HealthDataCardMode.IMPORTING
    state.connected -> HealthDataCardMode.CONNECTED
    else -> HealthDataCardMode.NOT_CONNECTED
}

/**
 * Foreground auto-import runs only for an account that connected Health Connect from the card,
 * and never while another import is running. It never asks for permissions.
 */
fun shouldRunAutoImport(state: HealthDataUiState): Boolean =
    state.availability == HealthConnectAvailability.AVAILABLE &&
        state.connected &&
        !state.running

/**
 * The notice after a manual import: failure when the run threw, "nothing new" when it completed
 * without importing, otherwise none. Automatic runs are silent.
 */
fun healthImportNotice(
    manual: Boolean,
    failed: Boolean,
    completed: Boolean,
    imported: Int
): HealthImportNotice = when {
    !manual -> HealthImportNotice.NONE
    failed -> HealthImportNotice.FAILED
    completed && imported <= 0 -> HealthImportNotice.EMPTY
    else -> HealthImportNotice.NONE
}

/**
 * A run that reports the import is switched off or lacks permission means the card must read as
 * not connected. The card never reacts by opening a permission prompt.
 */
internal fun healthImportStatusMeansDisconnected(status: HealthImportStatus): Boolean =
    status == HealthImportStatus.NOT_ENABLED || status == HealthImportStatus.NO_PERMISSION
