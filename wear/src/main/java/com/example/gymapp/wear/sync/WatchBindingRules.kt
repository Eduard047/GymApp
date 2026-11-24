package com.example.gymapp.wear.sync

/** Whether the workout kept on the watch may be sent under the current binding. */
enum class HeldWorkState {
    /** Nothing is stored. */
    None,

    /** The work belongs to the owner the watch is bound to right now: it may be sent. */
    Ready,

    /** The phone is signed out (or the watch is not linked): keep, do not send. */
    HeldUnbound,

    /** Another account is active on the phone: keep, never send to it. */
    HeldForeign
}

sealed interface FullSyncDecision {
    data object Reject : FullSyncDecision

    /** The same revision again: nothing to apply. */
    data object Duplicate : FullSyncDecision

    /**
     * [resetAccountData]: plan, history and catalog of the previous binding are cleared first.
     * [rebased]: a new phone authority (new install epoch or a new phone node); its counters start
     * over, so the stored revisions and the crash stage of the old authority do not apply.
     */
    data class Accept(val resetAccountData: Boolean, val rebased: Boolean) : FullSyncDecision
}

enum class BindingStateDecision { Reject, Unbind, Unlink }

/**
 * Pure decisions of the watch binding model. No Android types, so every rule runs in JVM tests.
 * The phone is the only authority for the owner; the watch only decides whether a message of the
 * pinned phone is newer than what it already holds.
 */
object WatchBindingRules {
    /** The cap only keeps a stale marker from living forever. */
    const val DELETED_OWNER_MARKER_TTL_MS = 30L * 24 * 60 * 60 * 1000

    /**
     * The workout in memory was recorded for an owner the phone has since deleted: it has nowhere
     * to go and is dropped. The same owner id can come back (a local profile re-created under the
     * same name), so only work started before the deletion is dropped; work started later belongs
     * to the new binding and is kept.
     */
    fun shouldDropForDeletedOwner(
        markerOwnerId: String?,
        markerDeletedAtMs: Long,
        workOwnerId: String?,
        workStartedAtMs: Long?,
        nowMs: Long
    ): Boolean =
        markerOwnerId != null &&
            workOwnerId != null &&
            markerOwnerId == workOwnerId &&
            markerDeletedAtMs > 0L &&
            workStartedAtMs != null &&
            workStartedAtMs <= markerDeletedAtMs &&
            nowMs - markerDeletedAtMs <= DELETED_OWNER_MARKER_TTL_MS

    /**
     * A new binding for the deleted owner id (the unlink cleared the old one, so any binding
     * established now is a re-link) ends the marker: that owner exists again.
     */
    fun deletedOwnerMarkerSuperseded(markerOwnerId: String?, newBindingOwnerId: String?): Boolean =
        markerOwnerId != null && markerOwnerId == newBindingOwnerId

    fun heldWorkState(bindingOwnerId: String?, workOwnerId: String?, hasWork: Boolean): HeldWorkState = when {
        !hasWork -> HeldWorkState.None
        bindingOwnerId == null -> HeldWorkState.HeldUnbound
        workOwnerId != null && workOwnerId == bindingOwnerId -> HeldWorkState.Ready
        else -> HeldWorkState.HeldForeign
    }

    fun decideFullSync(
        binding: WatchSyncBinding?,
        sourceNodeId: String,
        envelope: WatchSyncEnvelope,
        relinkCandidateNodeId: String?,
        heldOwnerId: String?
    ): FullSyncDecision {
        binding ?: return FullSyncDecision.Reject
        if (binding.sourceNodeId != sourceNodeId) {
            // Another phone node. Only one this watch asked itself (the pinned phone was absent)
            // can take over, and never while work is held for a different account.
            if (relinkCandidateNodeId == null || relinkCandidateNodeId != sourceNodeId) {
                return FullSyncDecision.Reject
            }
            val sameOwner = binding.ownerId != null && binding.ownerId == envelope.ownerId
            val holdAllows = heldOwnerId == null || heldOwnerId == envelope.ownerId
            return if (sameOwner || holdAllows) {
                FullSyncDecision.Accept(resetAccountData = true, rebased = true)
            } else {
                FullSyncDecision.Reject
            }
        }
        if (binding.authorityEpoch != envelope.authorityEpoch) {
            // First message after the pin, or the phone app was reinstalled / its data cleared.
            // A delayed message of the previous install is older than the last accepted one.
            if (envelope.sentAt < binding.lastAcceptedSentAt) return FullSyncDecision.Reject
            // Once an authority is known, an equal timestamp is not newer either.
            if (!newerAuthorityMessage(binding, envelope.sentAt)) return FullSyncDecision.Reject
            return FullSyncDecision.Accept(resetAccountData = true, rebased = true)
        }

        val unbound = binding.ownerId == null
        val ownerChanged = !unbound && binding.ownerId != envelope.ownerId
        if (ownerChanged && envelope.accountGeneration <= binding.accountGeneration) {
            return FullSyncDecision.Reject
        }
        // Unbound keeps the generation of the sign-out, so an older owner cannot come back.
        if (unbound && envelope.accountGeneration <= binding.accountGeneration) {
            return FullSyncDecision.Reject
        }
        if (!ownerChanged && !unbound && envelope.accountGeneration < binding.accountGeneration) {
            return FullSyncDecision.Reject
        }
        val generationChanged = !ownerChanged && !unbound &&
            envelope.accountGeneration > binding.accountGeneration
        val previousRevision = if (!ownerChanged && !unbound && !generationChanged) {
            binding.fullSyncRevision
        } else {
            0L
        }
        if (envelope.revision < previousRevision) return FullSyncDecision.Reject
        if (envelope.revision == previousRevision) return FullSyncDecision.Duplicate
        return FullSyncDecision.Accept(
            resetAccountData = ownerChanged || unbound || generationChanged,
            rebased = false
        )
    }

    /** A plan is applied only for exactly the authority, owner and generation the watch holds. */
    fun planAllowed(binding: WatchSyncBinding?, sourceNodeId: String, envelope: WatchSyncEnvelope): Boolean {
        return binding != null &&
            binding.sourceNodeId == sourceNodeId &&
            binding.ownerId != null &&
            binding.ownerId == envelope.ownerId &&
            binding.authorityEpoch == envelope.authorityEpoch &&
            binding.accountGeneration == envelope.accountGeneration &&
            envelope.revision >= binding.planRevision
    }

    fun decideBindingState(
        binding: WatchSyncBinding?,
        sourceNodeId: String,
        state: ParsedBindingState
    ): BindingStateDecision {
        binding ?: return BindingStateDecision.Reject
        // Only the pinned phone can unbind or unlink; a relink candidate cannot.
        if (binding.sourceNodeId != sourceNodeId) return BindingStateDecision.Reject
        val sameEpoch = binding.authorityEpoch == state.authorityEpoch
        return when (state.kind) {
            BindingStateKind.Unlinked ->
                if (state.sentAt >= binding.lastAcceptedSentAt) BindingStateDecision.Unlink
                else BindingStateDecision.Reject

            BindingStateKind.Unbound -> when {
                !sameEpoch ->
                    if (newerAuthorityMessage(binding, state.sentAt)) BindingStateDecision.Unbind
                    else BindingStateDecision.Reject
                // Signing out always takes a new generation on the phone.
                binding.ownerId != null && state.accountGeneration > binding.accountGeneration ->
                    BindingStateDecision.Unbind
                binding.ownerId == null && state.accountGeneration > binding.accountGeneration ->
                    BindingStateDecision.Unbind
                else -> BindingStateDecision.Reject
            }
        }
    }

    /**
     * A message of another epoch replaces a known authority only when it is strictly later than
     * the last accepted message; an equal timestamp is not newer. A fresh pin (no epoch yet)
     * accepts its first message whatever its time.
     */
    private fun newerAuthorityMessage(binding: WatchSyncBinding, sentAt: Long): Boolean {
        return if (binding.authorityEpoch == null) {
            sentAt >= binding.lastAcceptedSentAt
        } else {
            sentAt > binding.lastAcceptedSentAt
        }
    }

    /**
     * A capability event of the phone app. The waiting workout is flushed only when the node that
     * is reachable is the pinned phone and an owner is bound; any other node (a second phone, a
     * relink candidate) never triggers a send.
     */
    fun pinnedPhoneReachable(
        binding: WatchSyncBinding?,
        capabilityName: String,
        reachableNodeIds: Set<String>
    ): Boolean {
        return capabilityName == SyncPaths.PHONE_CAPABILITY &&
            binding?.ownerId != null &&
            binding.sourceNodeId in reachableNodeIds
    }

    /** Node, owner and generation are the identity a send was prepared for; revisions may move. */
    fun sameSendIdentity(expected: WatchSyncBinding, current: WatchSyncBinding?): Boolean {
        return current != null &&
            current.sourceNodeId == expected.sourceNodeId &&
            current.ownerId == expected.ownerId &&
            current.accountGeneration == expected.accountGeneration
    }
}
