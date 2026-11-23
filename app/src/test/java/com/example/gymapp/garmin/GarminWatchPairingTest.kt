package com.example.gymapp.garmin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GarminWatchPairingTest {
    private val tapped = "111111111"
    private val other = "222222222"

    private fun decide(
        tappedBinding: String = tapped,
        connected: List<String> = listOf(tapped),
        state: GarminTrustedDeviceState = GarminTrustedDeviceState.Unpaired,
        trusted: String? = null,
        resetPending: Boolean = false,
        accountReady: Boolean = true,
        cachedPlan: Boolean = false,
        lite: Boolean = false
    ) = decideGarminWatchPairing(
        tappedBinding = tappedBinding,
        connectedBindings = connected,
        trustedState = state,
        trustedBinding = trusted,
        resetPending = resetPending,
        accountReady = accountReady,
        hasCachedPlan = cachedPlan,
        isLiteWatch = lite
    )

    private fun refused(decision: GarminWatchPairingDecision) =
        (decision as GarminWatchPairingDecision.Refuse).reason

    @Test
    fun unpairedWatchIsPairedWithBindingOnlySyncWhenNoPlanIsCached() {
        assertEquals(
            GarminWatchPairingDecision.Pair(tapped, GarminPairingSyncMode.BindingOnly),
            decide()
        )
    }

    @Test
    fun cachedPlanIsPushedAsThePairingSync() {
        assertEquals(
            GarminWatchPairingDecision.Pair(tapped, GarminPairingSyncMode.CachedPlan),
            decide(cachedPlan = true)
        )
    }

    @Test
    fun liteWatchNeverReceivesThePlanEvenWhenOneIsCached() {
        assertEquals(
            GarminWatchPairingDecision.Pair(tapped, GarminPairingSyncMode.BindingOnly),
            decide(cachedPlan = true, lite = true)
        )
    }

    @Test
    fun theTapPicksTheDeviceAmongSeveralConnectedWatches() {
        val decision = decide(
            tappedBinding = other,
            connected = listOf(tapped, other, "333333333")
        )
        assertEquals(
            GarminWatchPairingDecision.Pair(other, GarminPairingSyncMode.BindingOnly),
            decision
        )
    }

    @Test
    fun aWatchThatIsNotConnectedIsNeverPaired() {
        assertEquals(
            GarminWatchPairingRefusal.NotConnected,
            refused(decide(connected = listOf(other)))
        )
        assertEquals(GarminWatchPairingRefusal.NotConnected, refused(decide(connected = emptyList())))
    }

    @Test
    fun pendingAuthTransitionResetBlocksPairingBeforeAnythingElse() {
        assertEquals(
            GarminWatchPairingRefusal.ResetPending,
            refused(decide(resetPending = true, cachedPlan = true))
        )
        assertEquals(
            GarminWatchPairingRefusal.ResetPending,
            refused(
                decide(
                    resetPending = true,
                    accountReady = false,
                    state = GarminTrustedDeviceState.Pinned,
                    trusted = tapped
                )
            )
        )
    }

    @Test
    fun anAccountThatIsNotReadyCannotPair() {
        assertEquals(
            GarminWatchPairingRefusal.AccountNotReady,
            refused(decide(accountReady = false))
        )
    }

    @Test
    fun anotherPinnedWatchIsNeverReplacedSilently() {
        assertEquals(
            GarminWatchPairingRefusal.AnotherWatchPinned,
            refused(
                decide(
                    connected = listOf(tapped, other),
                    state = GarminTrustedDeviceState.Pinned,
                    trusted = other
                )
            )
        )
    }

    @Test
    fun retryOnTheAlreadyPinnedWatchIsAllowed() {
        assertEquals(
            GarminWatchPairingDecision.Pair(tapped, GarminPairingSyncMode.CachedPlan),
            decide(
                state = GarminTrustedDeviceState.Pinned,
                trusted = tapped,
                cachedPlan = true
            )
        )
    }

    @Test
    fun contradictoryTrustStateFailsClosed() {
        assertEquals(
            GarminWatchPairingRefusal.TrustConflict,
            refused(decide(state = GarminTrustedDeviceState.Conflict))
        )
    }

    @Test
    fun malformedDeviceBindingIsRefused() {
        assertEquals(
            GarminWatchPairingRefusal.InvalidDevice,
            refused(decide(tappedBinding = "not-a-device", connected = listOf("not-a-device")))
        )
    }

    private fun watch(
        id: Long,
        connected: Boolean = true,
        trusted: Boolean = false
    ) = GarminDeviceSummary(
        name = "Watch $id",
        connected = connected,
        trustedForActiveAccount = trusted,
        deviceId = id
    )

    private fun state(
        vararg devices: GarminDeviceSummary,
        canPair: Boolean = true,
        resetPending: Boolean = false,
        sdkReady: Boolean = true
    ) = GarminDeviceUiState(
        sdkReady = sdkReady,
        devices = devices.toList(),
        canPair = canPair,
        pairingResetPending = resetPending
    )

    @Test
    fun connectIsOfferedOnlyForConnectedUnpairedWatches() {
        val a = watch(1)
        val b = watch(2, connected = false)
        val s = state(a, b)
        assertTrue(garminDeviceOffersConnect(s, a))
        assertFalse(garminDeviceOffersConnect(s, b))
    }

    @Test
    fun connectIsOfferedOnEveryConnectedWatchWhenSeveralAreConnected() {
        val a = watch(1)
        val b = watch(2)
        val s = state(a, b)
        assertTrue(garminDeviceOffersConnect(s, a))
        assertTrue(garminDeviceOffersConnect(s, b))
    }

    @Test
    fun pairedWatchKeepsItsTagAndHidesConnectEverywhere() {
        val paired = watch(1, trusted = true)
        val other = watch(2)
        val s = state(paired, other)
        assertFalse(garminDeviceOffersConnect(s, paired))
        assertFalse(garminDeviceOffersConnect(s, other))
    }

    @Test
    fun connectFollowsThePendingResetRule() {
        val a = watch(1)
        assertFalse(garminDeviceOffersConnect(state(a, resetPending = true), a))
        assertFalse(garminDeviceOffersConnect(state(a, canPair = false), a))
        assertFalse(garminDeviceOffersConnect(state(a, sdkReady = false), a))
    }
}
