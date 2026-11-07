package com.example.gymapp.sync

import com.example.gymapp.R
import com.example.gymapp.util.LocalizedText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CloudSyncUiStatusTest {
    @Test
    fun errorPhaseKeepsKnownLocalizedReason() {
        val reason = LocalizedText(R.string.cloud_sync_load_failed)
        val status = cloudSyncUiStatus(CloudSyncPhase.Error, lastSuccessAt = 42L, errorReason = reason)
        assertEquals(CloudSyncPhase.Error, status.phase)
        assertEquals(42L, status.lastSuccessAt)
        assertEquals(reason, status.message)
    }

    @Test
    fun everyKnownSyncReasonIsKept() {
        listOf(
            R.string.auth_error_connection,
            R.string.cloud_sync_load_failed,
            R.string.cloud_sync_save_failed,
            R.string.cloud_sync_resolution_failed
        ).forEach { id ->
            val status = cloudSyncUiStatus(CloudSyncPhase.Error, null, LocalizedText(id))
            assertEquals(id, status.message?.resourceId)
        }
    }

    @Test
    fun nextAttemptOrSuccessClearsReason() {
        val reason = LocalizedText(R.string.cloud_sync_save_failed)
        listOf(
            CloudSyncPhase.Checking,
            CloudSyncPhase.Pending,
            CloudSyncPhase.Synced,
            CloudSyncPhase.Conflict
        ).forEach { phase ->
            assertNull(cloudSyncUiStatus(phase, 1L, reason).message)
        }
        assertNull(cloudSyncUiStatus(CloudSyncPhase.Error, 1L, null).message)
        assertNull(CloudSyncUiStatus(CloudSyncPhase.Synced, 1L).message)
    }

    @Test
    fun unknownOrParameterizedTextIsNotKept() {
        assertNull(
            cloudSyncUiStatus(
                CloudSyncPhase.Error,
                null,
                LocalizedText(R.string.backup_export_failed)
            ).message
        )
        assertNull(
            cloudSyncUiStatus(
                CloudSyncPhase.Error,
                null,
                LocalizedText(R.string.cloud_sync_load_failed, "server said: boom")
            ).message
        )
    }
}
