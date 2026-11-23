package com.example.gymapp.ui.viewmodel

import com.example.gymapp.garmin.GarminDeviceSummary
import com.example.gymapp.garmin.GarminDeviceUiState
import com.example.gymapp.health.HealthConnectAvailability
import org.junit.Assert.assertEquals
import org.junit.Test

class WatchesStateTest {
    private val labels = { source: WatchSource ->
        when (source) {
            WatchSource.GARMIN -> "Garmin"
            WatchSource.WEAR_OS -> "Wear OS"
            WatchSource.HEALTH_DATA -> "Health data"
        }
    }

    private fun garmin(paired: Boolean, connected: Boolean = true) = GarminDeviceUiState(
        sdkReady = true,
        devices = listOf(
            GarminDeviceSummary(
                name = "Forerunner",
                connected = connected,
                trustedForActiveAccount = paired
            )
        )
    )

    private fun health(
        availability: HealthConnectAvailability = HealthConnectAvailability.AVAILABLE,
        connected: Boolean = true
    ) = HealthDataUiState(availability = availability, connected = connected)

    @Test
    fun noSourcesReadsAsNotConnected() {
        assertEquals(emptyList<WatchSource>(), connectedWatchSources(GarminDeviceUiState(), null))
        assertEquals("Not connected", watchesStatusLine(emptyList(), labels, "Not connected"))
    }

    @Test
    fun garminCountsOnlyWhenPairedForTheActiveAccount() {
        assertEquals(listOf(WatchSource.GARMIN), connectedWatchSources(garmin(paired = true), null))
        // A watch that is visible but not paired for this account is not a connected source.
        assertEquals(emptyList<WatchSource>(), connectedWatchSources(garmin(paired = false), null))
        // A paired watch that is currently offline still counts as paired.
        assertEquals(
            listOf(WatchSource.GARMIN),
            connectedWatchSources(garmin(paired = true, connected = false), null)
        )
    }

    @Test
    fun healthDataNeedsAvailableProviderAndConnectedImport() {
        val none = GarminDeviceUiState()
        assertEquals(listOf(WatchSource.HEALTH_DATA), connectedWatchSources(none, health()))
        assertEquals(emptyList<WatchSource>(), connectedWatchSources(none, health(connected = false)))
        assertEquals(
            emptyList<WatchSource>(),
            connectedWatchSources(none, health(HealthConnectAvailability.UNAVAILABLE))
        )
        assertEquals(
            emptyList<WatchSource>(),
            connectedWatchSources(none, health(HealthConnectAvailability.PROVIDER_UPDATE_REQUIRED))
        )
    }

    @Test
    fun statusJoinsSourcesInDisplayOrder() {
        val both = connectedWatchSources(garmin(paired = true), health())
        assertEquals(listOf(WatchSource.GARMIN, WatchSource.HEALTH_DATA), both)
        assertEquals("Garmin · Health data", watchesStatusLine(both, labels, "Not connected"))
        assertEquals("Garmin", watchesStatusLine(listOf(WatchSource.GARMIN), labels, "Not connected"))
        assertEquals(
            "Health data",
            watchesStatusLine(listOf(WatchSource.HEALTH_DATA), labels, "Not connected")
        )
    }

    private val linkedWear = WearWatchUiState(apiAvailable = true, linked = true)

    @Test
    fun wearOsCountsOnlyWhenLinkedAndTheWearableApiIsAvailable() {
        val none = GarminDeviceUiState()
        assertEquals(listOf(WatchSource.WEAR_OS), connectedWatchSources(none, null, linkedWear))
        // Not looked up yet, API missing (card hidden) or no watch linked: not a connected source.
        assertEquals(emptyList<WatchSource>(), connectedWatchSources(none, null, null))
        assertEquals(
            emptyList<WatchSource>(),
            connectedWatchSources(none, null, WearWatchUiState(apiAvailable = false, linked = true))
        )
        assertEquals(
            emptyList<WatchSource>(),
            connectedWatchSources(none, null, WearWatchUiState(apiAvailable = true))
        )
        // A linked watch that is offline right now still counts as linked.
        assertEquals(
            listOf(WatchSource.WEAR_OS),
            connectedWatchSources(none, null, linkedWear.copy(connected = false))
        )
    }

    @Test
    fun statusOrderIsGarminWearOsHealthData() {
        val all = connectedWatchSources(garmin(paired = true), health(), linkedWear)
        assertEquals(listOf(WatchSource.GARMIN, WatchSource.WEAR_OS, WatchSource.HEALTH_DATA), all)
        assertEquals("Garmin · Wear OS · Health data", watchesStatusLine(all, labels, "Not connected"))
        assertEquals(
            "Wear OS · Health data",
            watchesStatusLine(connectedWatchSources(GarminDeviceUiState(), health(), linkedWear), labels, "-")
        )
    }
}
