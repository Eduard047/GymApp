package com.example.gymapp.ui.viewmodel

import com.example.gymapp.garmin.GarminDeviceUiState
import com.example.gymapp.health.HealthConnectAvailability

/** A watch source the Watches screen can show as connected. Order is the display order. */
enum class WatchSource { GARMIN, WEAR_OS, HEALTH_DATA }

/**
 * Sources that are connected right now: Garmin when a watch is paired for the active account, Wear OS
 * when a watch is linked and the Wearable API is available (the card is shown), Health data when
 * Health Connect is usable and the user connected the import. A null [health] (no signed-in profile
 * to hold the import) or a null [wear] (not looked up yet) never counts.
 */
fun connectedWatchSources(
    garmin: GarminDeviceUiState,
    health: HealthDataUiState?,
    wear: WearWatchUiState? = null
): List<WatchSource> = buildList {
    if (garmin.devices.any { it.trustedForActiveAccount }) add(WatchSource.GARMIN)
    if (wearWatchCardMode(wear) == WearWatchCardMode.LINKED) add(WatchSource.WEAR_OS)
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
