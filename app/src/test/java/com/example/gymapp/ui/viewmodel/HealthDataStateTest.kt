package com.example.gymapp.ui.viewmodel

import com.example.gymapp.health.HealthConnectAvailability
import com.example.gymapp.health.HealthImportStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HealthDataStateTest {
    private fun state(
        availability: HealthConnectAvailability = HealthConnectAvailability.AVAILABLE,
        connected: Boolean = false,
        running: Boolean = false
    ) = HealthDataUiState(availability = availability, connected = connected, running = running)

    @Test
    fun unavailableStatesNeverOfferConnect() {
        assertEquals(
            HealthDataCardMode.UNAVAILABLE,
            healthDataCardMode(state(HealthConnectAvailability.UNAVAILABLE, connected = true))
        )
        assertEquals(
            HealthDataCardMode.UNAVAILABLE,
            healthDataCardMode(state(HealthConnectAvailability.UNSUPPORTED_OS))
        )
        assertEquals(
            HealthDataCardMode.INSTALL_REQUIRED,
            healthDataCardMode(state(HealthConnectAvailability.PROVIDER_UPDATE_REQUIRED))
        )
    }

    @Test
    fun availableStatesFollowConnectionAndRunning() {
        assertEquals(HealthDataCardMode.NOT_CONNECTED, healthDataCardMode(state()))
        assertEquals(HealthDataCardMode.CONNECTED, healthDataCardMode(state(connected = true)))
        assertEquals(
            HealthDataCardMode.IMPORTING,
            healthDataCardMode(state(connected = true, running = true))
        )
        assertEquals(HealthDataCardMode.IMPORTING, healthDataCardMode(state(running = true)))
    }

    @Test
    fun autoImportNeedsAvailableConnectedAndIdle() {
        assertTrue(shouldRunAutoImport(state(connected = true)))
        assertFalse(shouldRunAutoImport(state(connected = false)))
        assertFalse(shouldRunAutoImport(state(connected = true, running = true)))
        assertFalse(
            shouldRunAutoImport(state(HealthConnectAvailability.UNAVAILABLE, connected = true))
        )
        assertFalse(
            shouldRunAutoImport(
                state(HealthConnectAvailability.PROVIDER_UPDATE_REQUIRED, connected = true)
            )
        )
    }

    @Test
    fun noticeIsShownOnlyAfterManualRuns() {
        assertEquals(
            HealthImportNotice.EMPTY,
            healthImportNotice(manual = true, failed = false, completed = true, imported = 0)
        )
        assertEquals(
            HealthImportNotice.NONE,
            healthImportNotice(manual = true, failed = false, completed = true, imported = 3)
        )
        assertEquals(
            HealthImportNotice.FAILED,
            healthImportNotice(manual = true, failed = true, completed = false, imported = 0)
        )
        assertEquals(
            HealthImportNotice.NONE,
            healthImportNotice(manual = true, failed = false, completed = false, imported = 0)
        )
        assertEquals(
            HealthImportNotice.NONE,
            healthImportNotice(manual = false, failed = true, completed = true, imported = 0)
        )
    }

    @Test
    fun notEnabledAndNoPermissionRunsReadAsNotConnected() {
        assertTrue(healthImportStatusMeansDisconnected(HealthImportStatus.NOT_ENABLED))
        assertTrue(healthImportStatusMeansDisconnected(HealthImportStatus.NO_PERMISSION))
        assertFalse(healthImportStatusMeansDisconnected(HealthImportStatus.COMPLETED))
        assertFalse(healthImportStatusMeansDisconnected(HealthImportStatus.THROTTLED))
        // A manual run that stopped as NOT_ENABLED shows no notice and no error.
        assertEquals(
            HealthImportNotice.NONE,
            healthImportNotice(manual = true, failed = false, completed = false, imported = 0)
        )
    }
}
