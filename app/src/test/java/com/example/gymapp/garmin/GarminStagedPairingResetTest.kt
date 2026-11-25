package com.example.gymapp.garmin

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GarminStagedPairingResetTest {
    private val device = "123456789"
    private val pending = "2".repeat(64)
    private val staged = GarminStagedPairingReset(
        authTransitionKey = "transition-key",
        binding = GarminBinding(account = "a".repeat(64), device = device, pairingGeneration = pending),
        syncId = "staged-reset-sync-0001",
        revision = 42L
    )
    private val request = mapOf<Any?, Any?>(
        "type" to "request_sync",
        "requestId" to "watch-request-0001",
        "bindingVersion" to GARMIN_BINDING_VERSION,
        "accountBinding" to staged.binding.account,
        "deviceBinding" to device,
        "pairingGeneration" to pending
    )

    private fun decide(
        command: Map<Any?, Any?> = request,
        reset: GarminStagedPairingReset? = staged,
        transitionKey: String = "transition-key",
        trusted: String? = device,
        source: String = device,
        pendingGeneration: String? = pending
    ) = garminSyncRequestResendsStagedReset(
        command = command,
        staged = reset,
        authTransitionKey = transitionKey,
        trustedDeviceBinding = trusted,
        sourceDeviceBinding = source,
        pendingGeneration = pendingGeneration
    )

    @Test
    fun pinnedWatchPresentingTheStagedGenerationGetsTheExactResetAgain() {
        assertTrue(decide())
    }

    @Test
    fun nothingStagedOrNoPendingResetNeverResends() {
        assertFalse(decide(reset = null))
        assertFalse(decide(pendingGeneration = null))
        // The pending generation moved on (a newer reset was staged): never resend the old one.
        assertFalse(decide(pendingGeneration = "3".repeat(64)))
    }

    @Test
    fun otherAccountWatchOrTransitionNeverResends() {
        assertFalse(decide(transitionKey = "other-transition"))
        assertFalse(decide(trusted = null))
        assertFalse(decide(source = "987654321", trusted = "987654321"))
        assertFalse(decide(source = "987654321"))
        assertFalse(decide(command = request + ("accountBinding" to "b".repeat(64))))
        assertFalse(decide(command = request + ("deviceBinding" to "987654321")))
    }

    @Test
    fun requestMustExplicitlyClaimTheStagedGeneration() {
        assertFalse(decide(command = request - "pairingGeneration"))
        // The old active generation is handled by the normal sync path, not by a resend.
        assertFalse(decide(command = request + ("pairingGeneration" to "1".repeat(64))))
        assertFalse(decide(command = request + ("pairingGeneration" to "malformed")))
        assertFalse(decide(command = request + ("bindingVersion" to 1)))
    }

    @Test
    fun invalidStagedRevisionNeverResends() {
        assertFalse(decide(reset = staged.copy(revision = 0L)))
    }
}
