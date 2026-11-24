package com.example.gymapp.garmin

/** What the explicit "Connect" tap sends to the watch that was tapped. */
internal enum class GarminPairingSyncMode {
    /** The active account has a cached plan: pair with the same plan sync as "Sync plan to Garmin". */
    CachedPlan,

    /**
     * No plan to send, or a free-workout-only watch: pair with a binding-only sync (empty plan
     * columns, `resetWorkout = false`), the message lite watches already receive.
     */
    BindingOnly
}

internal enum class GarminWatchPairingRefusal {
    /** The tapped identifier cannot be a Connect IQ device binding. */
    InvalidDevice,

    /** An auth-transition reset is pending; only the existing reset flow may clear it. */
    ResetPending,

    /** No signed-in account is ready (sign-in or account transition still in progress). */
    AccountNotReady,

    /** The stored trusted-device state is contradictory; fail closed. */
    TrustConflict,

    /** A different watch is already pinned for this phone; the pin is never replaced silently. */
    AnotherWatchPinned,

    /** The tapped watch is not connected through Garmin Connect right now. */
    NotConnected
}

internal sealed interface GarminWatchPairingDecision {
    data class Pair(
        val deviceBinding: String,
        val mode: GarminPairingSyncMode
    ) : GarminWatchPairingDecision

    data class Refuse(val reason: GarminWatchPairingRefusal) : GarminWatchPairingDecision
}

/**
 * Decides what an explicit Connect tap on [tappedBinding] may do. The tap is the choice, so any
 * number of connected watches is fine; only the tapped watch can be pinned. Never pairs a watch
 * that is not connected, never replaces an existing pin with another watch, and never bypasses a
 * pending auth-transition reset.
 */
internal fun decideGarminWatchPairing(
    tappedBinding: String,
    connectedBindings: List<String>,
    trustedState: GarminTrustedDeviceState,
    trustedBinding: String?,
    resetPending: Boolean,
    accountReady: Boolean,
    hasCachedPlan: Boolean,
    isLiteWatch: Boolean
): GarminWatchPairingDecision {
    if (!isValidGarminTransportDeviceBinding(tappedBinding)) {
        return GarminWatchPairingDecision.Refuse(GarminWatchPairingRefusal.InvalidDevice)
    }
    if (resetPending) {
        return GarminWatchPairingDecision.Refuse(GarminWatchPairingRefusal.ResetPending)
    }
    if (!accountReady) {
        return GarminWatchPairingDecision.Refuse(GarminWatchPairingRefusal.AccountNotReady)
    }
    when (trustedState) {
        GarminTrustedDeviceState.Conflict ->
            return GarminWatchPairingDecision.Refuse(GarminWatchPairingRefusal.TrustConflict)
        GarminTrustedDeviceState.Pinned ->
            if (trustedBinding != tappedBinding) {
                return GarminWatchPairingDecision.Refuse(
                    GarminWatchPairingRefusal.AnotherWatchPinned
                )
            }
        GarminTrustedDeviceState.Unpaired -> Unit
    }
    if (tappedBinding !in connectedBindings) {
        return GarminWatchPairingDecision.Refuse(GarminWatchPairingRefusal.NotConnected)
    }
    val mode = if (hasCachedPlan && !isLiteWatch) {
        GarminPairingSyncMode.CachedPlan
    } else {
        GarminPairingSyncMode.BindingOnly
    }
    return GarminWatchPairingDecision.Pair(tappedBinding, mode)
}

/**
 * Whether Profile shows a Connect button for [device]: the watch is connected now, no watch is
 * paired (pinned and acknowledged) for the active account yet, pairing is currently allowed, and
 * no other watch holds the phone's pin. A watch that is pinned but never acknowledged the pairing
 * keeps offering Connect, so a failed or interrupted first Connect can always be retried.
 */
internal fun garminDeviceOffersConnect(
    state: GarminDeviceUiState,
    device: GarminDeviceSummary
): Boolean = state.sdkReady &&
    state.canPair &&
    !state.pairingResetPending &&
    device.connected &&
    !device.trustedForActiveAccount &&
    state.devices.none { it.trustedForActiveAccount } &&
    (!state.hasPinnedWatch || device.pinned)

/**
 * "Paired" means the watch acknowledged the pairing for this account, not only that the phone
 * pinned it (mirrors iPhone's `isBindingConfirmed`). [storedAcknowledgedBinding] is the binding the
 * watch acknowledged for the account. Pins saved before the flag existed count as acknowledged when
 * [legacyAcknowledgementEvidence] shows an earlier bound exchange with that watch (the generation
 * capability is stored only after a confirmed sync or a bound watch workout); otherwise Connect is
 * offered again, which re-pairs the same pinned watch without locking the user out.
 */
internal fun garminPairingAcknowledged(
    pinnedBinding: String?,
    storedAcknowledgedBinding: String?,
    legacyAcknowledgementEvidence: Boolean
): Boolean = pinnedBinding != null &&
    (storedAcknowledgedBinding == pinnedBinding || legacyAcknowledgementEvidence)

/**
 * After a Connect attempt: a pin created by this attempt is released again unless the watch
 * acknowledged the pairing. A pin that existed before the attempt (a retry) is kept.
 */
internal fun garminPairingRollbackNeeded(
    pinnedBeforeAttempt: Boolean,
    paired: Boolean,
    acknowledged: Boolean
): Boolean = !pinnedBeforeAttempt && !paired && !acknowledged

/**
 * The secure pairing reset releases only the phone's local pin (no destructive message to the
 * watch) when the pinned watch never acknowledged the pairing or is not connected. The watch keeps
 * its own account binding and still refuses any other account, so this cannot expose its data.
 */
internal fun garminResetReleasesLocalPinOnly(
    pinnedWatchConnected: Boolean,
    acknowledged: Boolean
): Boolean = !pinnedWatchConnected || !acknowledged
