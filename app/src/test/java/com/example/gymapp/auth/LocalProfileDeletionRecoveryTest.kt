package com.example.gymapp.auth

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalProfileDeletionRecoveryTest {
    private val record = PendingLocalProfileDeletion(
        profileId = UUID.randomUUID().toString(),
        displayName = "Synthetic",
        logicalDatabaseName = "local_v2_${"a".repeat(64)}",
        physicalDatabaseName = "local_v2_${"a".repeat(64)}"
    )

    @Test
    fun failedCleanupRetainsIdentityAndJournalForRetry() {
        val calls = mutableListOf<String>()
        val recovered = recoverPendingLocalProfileDeletion(
            record = record,
            clearLiveSidecar = { calls += "sidecar"; true },
            clearDatabase = { calls += "database"; true },
            clearTrainingProfile = { calls += "profile"; true },
            clearTrainingGuidance = { calls += "guidance"; true },
            clearCustomMedia = { calls += "media"; false },
            clearBackupShares = { calls += "shares"; true },
            clearRestTimers = { calls += "timers"; true },
            finalizeIdentity = { calls += "finalize"; true }
        )

        assertFalse(recovered)
        assertFalse("finalize" in calls)
        assertEquals(
            listOf("sidecar", "database", "profile", "guidance", "media", "shares", "timers"),
            calls
        )
    }

    @Test
    fun sidecarFailureHasNoFurtherCleanupSideEffects() {
        val calls = mutableListOf<String>()
        val recovered = recoverPendingLocalProfileDeletion(
            record = record,
            clearLiveSidecar = { calls += "sidecar"; false },
            clearDatabase = { calls += "database"; true },
            clearTrainingProfile = { calls += "profile"; true },
            clearTrainingGuidance = { calls += "guidance"; true },
            clearCustomMedia = { calls += "media"; true },
            clearBackupShares = { calls += "shares"; true },
            clearRestTimers = { calls += "timers"; true },
            finalizeIdentity = { calls += "finalize"; true }
        )

        assertFalse(recovered)
        assertEquals(listOf("sidecar"), calls)
    }

    @Test
    fun completeRetryReclaimsIdentityOnlyAfterEveryOwnedStoreClears() {
        var finalized = false
        val recovered = recoverPendingLocalProfileDeletion(
            record = record,
            clearLiveSidecar = { true },
            clearDatabase = { it == record },
            clearTrainingProfile = { it == record.logicalDatabaseName },
            clearTrainingGuidance = { it == record.logicalDatabaseName },
            clearCustomMedia = { it == record.logicalDatabaseName },
            clearBackupShares = { it == record.logicalDatabaseName },
            clearRestTimers = { it == record.logicalDatabaseName },
            finalizeIdentity = {
                finalized = it == record
                finalized
            }
        )

        assertTrue(recovered)
        assertTrue(finalized)
    }
}
