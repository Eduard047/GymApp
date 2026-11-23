package com.example.gymapp.ui.viewmodel

import com.example.gymapp.garmin.GarminDeviceUiState
import com.example.gymapp.health.HealthConnectAvailability

/** A watch source the Watches screen can show as connected. Order is the display order. */
enum class WatchSource { GARMIN, HEALTH_DATA }

/**
 * Sources that are connected right now: Garmin when a watch is paired for the active account, Health
 * data when Health Connect is usable and the user connected the import. A null [health] (no signed-in
 * profile to hold the import) never counts.
 */
fun connectedWatchSources(
    garmin: GarminDeviceUiState,
    health: HealthDataUiState?
): List<WatchSource> = buildList {
    if (garmin.devices.any { it.trustedForActiveAccount }) add(WatchSource.GARMIN)
    if (health != null && health.availability == HealthConnectAvailability.AVAILABLE && health.connected) {
        add(WatchSource.HEALTH_DATA)
    }
}

/** The Profile row status: connected sources joined by " · ", or [none] when nothing is connected. */
fun watchesStatusLine(
    sources: List<WatchSource>,
    label: (WatchSource) -> String,
    none: String
): String = if (sources.isEmpty()) none else sources.joinToString(" · ") { label(it) }
