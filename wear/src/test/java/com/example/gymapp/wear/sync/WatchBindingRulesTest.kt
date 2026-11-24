package com.example.gymapp.wear.sync

import com.example.gymapp.wear.data.WearWorkoutSetDraft
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchBindingRulesTest {
    private val ownerA = "a".repeat(64)
    private val ownerB = "b".repeat(64)
    private val epoch1 = "11111111-2222-4333-8444-555555555555"
    private val epoch2 = "99999999-2222-4333-8444-555555555555"
    private val accept = FullSyncDecision.Accept(resetAccountData = true, rebased = false)
    private val acceptRebased = FullSyncDecision.Accept(resetAccountData = true, rebased = true)

    private fun binding(
        owner: String? = ownerA,
        generation: Long = 5L,
        revision: Long = 10L,
        epoch: String? = epoch1,
        lastSentAt: Long = 1_000L,
        node: String = "phone-1"
    ) = WatchSyncBinding(node, owner, generation, revision, 0L, epoch, lastSentAt)

    private fun envelope(
        owner: String = ownerA,
        generation: Long = 5L,
        revision: Long = 11L,
        epoch: String = epoch1,
        sentAt: Long = 2_000L
    ) = WatchSyncEnvelope(owner, generation, revision, "message", sentAt, epoch)

    private fun decide(
        binding: WatchSyncBinding?,
        envelope: WatchSyncEnvelope,
        node: String = "phone-1",
        candidate: String? = null,
        held: String? = null
    ) = WatchBindingRules.decideFullSync(binding, node, envelope, candidate, held)

    private fun unbound(generation: Long, sentAt: Long = 2_000L, epoch: String = epoch1) =
        ParsedBindingState(BindingStateKind.Unbound, epoch, generation, "message", sentAt)

    private fun unlinked(sentAt: Long, epoch: String = epoch1) =
        ParsedBindingState(BindingStateKind.Unlinked, epoch, 5L, "message", sentAt)

    @Test
    fun signOutPutsWorkOnHoldAndTheSameOwnerReleasesIt() {
        assertEquals(HeldWorkState.Ready, WatchBindingRules.heldWorkState(ownerA, ownerA, hasWork = true))
        // The phone signs out: a new generation, no owner.
        assertEquals(
            BindingStateDecision.Unbind,
            WatchBindingRules.decideBindingState(binding(), "phone-1", unbound(generation = 6L))
        )
        val signedOut = binding(owner = null, generation = 6L, revision = 0L, lastSentAt = 2_000L)
        assertEquals(HeldWorkState.HeldUnbound, WatchBindingRules.heldWorkState(null, ownerA, hasWork = true))
        // Owner A signs in again (next generation): accepted, and the work is ready to send.
        assertEquals(accept, decide(signedOut, envelope(generation = 7L, revision = 1L, sentAt = 3_000L), held = ownerA))
        assertEquals(HeldWorkState.Ready, WatchBindingRules.heldWorkState(ownerA, ownerA, hasWork = true))
    }

    @Test
    fun anotherOwnerIsAcceptedButNeverReleasesHeldWork() {
        val signedOut = binding(owner = null, generation = 6L, revision = 0L)
        assertEquals(accept, decide(signedOut, envelope(owner = ownerB, generation = 7L, revision = 1L), held = ownerA))
        assertEquals(HeldWorkState.HeldForeign, WatchBindingRules.heldWorkState(ownerB, ownerA, hasWork = true))
        // Work without an owner stamp is never released to whoever happens to be bound.
        assertEquals(HeldWorkState.HeldForeign, WatchBindingRules.heldWorkState(ownerB, null, hasWork = true))
        assertEquals(HeldWorkState.None, WatchBindingRules.heldWorkState(ownerB, ownerA, hasWork = false))
        // A direct A -> B switch on the phone is a higher generation of another owner.
        assertEquals(accept, decide(binding(), envelope(owner = ownerB, generation = 6L, revision = 1L), held = ownerA))
        assertEquals(FullSyncDecision.Reject, decide(binding(), envelope(owner = ownerB, generation = 5L, revision = 99L)))
    }

    @Test
    fun olderOwnerCannotComeBackAfterSignOut() {
        val signedOut = binding(owner = null, generation = 6L, revision = 0L)
        assertEquals(FullSyncDecision.Reject, decide(signedOut, envelope(generation = 5L, revision = 99L)))
        assertEquals(FullSyncDecision.Reject, decide(signedOut, envelope(generation = 6L, revision = 1L)))
    }

    @Test
    fun bindingStateRejectsReplaysForeignNodesAndMissingBinding() {
        assertEquals(BindingStateDecision.Reject, WatchBindingRules.decideBindingState(null, "phone-1", unbound(6L)))
        assertEquals(BindingStateDecision.Reject, WatchBindingRules.decideBindingState(binding(), "phone-2", unbound(6L)))
        // The same or an older generation of the same install is a replay.
        assertEquals(BindingStateDecision.Reject, WatchBindingRules.decideBindingState(binding(), "phone-1", unbound(5L)))
        assertEquals(BindingStateDecision.Reject, WatchBindingRules.decideBindingState(binding(), "phone-1", unbound(4L)))
        // A reinstalled phone that is signed out: newer than the last accepted message.
        assertEquals(
            BindingStateDecision.Unbind,
            WatchBindingRules.decideBindingState(binding(), "phone-1", unbound(1L, sentAt = 2_000L, epoch = epoch2))
        )
        assertEquals(
            BindingStateDecision.Reject,
            WatchBindingRules.decideBindingState(binding(), "phone-1", unbound(1L, sentAt = 999L, epoch = epoch2))
        )
    }

    @Test
    fun unlinkMessageIsHonouredOnlyFromThePinnedPhoneAndNotAsALateReplay() {
        assertEquals(BindingStateDecision.Unlink, WatchBindingRules.decideBindingState(binding(), "phone-1", unlinked(2_000L)))
        assertEquals(BindingStateDecision.Reject, WatchBindingRules.decideBindingState(binding(), "phone-2", unlinked(2_000L)))
        // Unlinked, then linked again (a newer accepted sync): the old unlink must not undo it.
        val relinked = binding(lastSentAt = 3_000L)
        assertEquals(BindingStateDecision.Reject, WatchBindingRules.decideBindingState(relinked, "phone-1", unlinked(2_000L)))
        // After the unlink the watch has no binding: nothing from the phone is applied until the
        // user links again (the first-link request pins the node, then a full sync is accepted).
        assertEquals(FullSyncDecision.Reject, decide(null, envelope()))
        val pinnedAgain = WatchSyncBinding("phone-1", null, 0L, 0L, 0L)
        assertEquals(acceptRebased, decide(pinnedAgain, envelope()))
    }

    @Test
    fun reinstalledPhoneWithRestartedCountersIsANewAuthorityNotAReplay() {
        val linked = binding(generation = 40L, revision = 900L, lastSentAt = 5_000L)
        // Without an epoch change the restarted counters are stale and stay rejected.
        assertEquals(FullSyncDecision.Reject, decide(linked, envelope(generation = 1L, revision = 1L, sentAt = 6_000L)))
        // Same owner, new install: accepted although generation and revision are lower.
        val fresh = envelope(generation = 1L, revision = 1L, epoch = epoch2, sentAt = 6_000L)
        assertEquals(acceptRebased, decide(linked, fresh, held = ownerA))
        // Another owner on the reinstalled phone is accepted too; held work then stays on hold.
        assertEquals(acceptRebased, decide(linked, fresh.copy(ownerId = ownerB), held = ownerA))
        // A late message of the dead install cannot flip the watch back.
        val rebased = binding(generation = 1L, revision = 1L, epoch = epoch2, lastSentAt = 6_000L)
        assertEquals(
            FullSyncDecision.Reject,
            decide(rebased, envelope(generation = 40L, revision = 901L, epoch = epoch1, sentAt = 5_500L))
        )
        // Replay protection inside the new epoch is unchanged.
        assertEquals(FullSyncDecision.Duplicate, decide(rebased, fresh))
        assertEquals(
            FullSyncDecision.Reject,
            decide(rebased.copy(fullSyncRevision = 5L), envelope(generation = 1L, revision = 4L, epoch = epoch2, sentAt = 7_000L))
        )
        assertEquals(
            FullSyncDecision.Accept(resetAccountData = false, rebased = false),
            decide(rebased, envelope(generation = 1L, revision = 2L, epoch = epoch2, sentAt = 7_000L))
        )
    }

    @Test
    fun aNewPhoneNodeTakesOverOnlyWhenAskedAndNeverOverForeignHeldWork() {
        val linked = binding()
        val fromNewPhone = envelope(generation = 1L, revision = 1L, epoch = epoch2)
        // Unsolicited, or solicited from a different node: rejected.
        assertEquals(FullSyncDecision.Reject, decide(linked, fromNewPhone, node = "phone-2"))
        assertEquals(FullSyncDecision.Reject, decide(linked, fromNewPhone, node = "phone-2", candidate = "phone-3"))
        // The watch asked this node and it presents the same owner: relink, held work stays.
        assertEquals(acceptRebased, decide(linked, fromNewPhone, node = "phone-2", candidate = "phone-2", held = ownerA))
        // Another owner with nothing held: relink.
        val foreign = fromNewPhone.copy(ownerId = ownerB)
        assertEquals(acceptRebased, decide(linked, foreign, node = "phone-2", candidate = "phone-2"))
        // Another owner while A's work is held: no automatic relink.
        assertEquals(FullSyncDecision.Reject, decide(linked, foreign, node = "phone-2", candidate = "phone-2", held = ownerA))
        val signedOut = binding(owner = null, generation = 6L)
        assertEquals(FullSyncDecision.Reject, decide(signedOut, foreign, node = "phone-2", candidate = "phone-2", held = ownerA))
        assertEquals(acceptRebased, decide(signedOut, fromNewPhone, node = "phone-2", candidate = "phone-2", held = ownerA))
        // A candidate can never unbind or unlink the watch.
        assertEquals(BindingStateDecision.Reject, WatchBindingRules.decideBindingState(linked, "phone-2", unlinked(9_000L)))
    }

    @Test
    fun planNeedsTheExactAuthorityOwnerAndGeneration() {
        val linked = binding()
        assertTrue(WatchBindingRules.planAllowed(linked, "phone-1", envelope(revision = 1L)))
        assertFalse(WatchBindingRules.planAllowed(linked, "phone-2", envelope(revision = 1L)))
        assertFalse(WatchBindingRules.planAllowed(linked, "phone-1", envelope(owner = ownerB, revision = 1L)))
        assertFalse(WatchBindingRules.planAllowed(linked, "phone-1", envelope(generation = 6L, revision = 1L)))
        assertFalse(WatchBindingRules.planAllowed(linked, "phone-1", envelope(epoch = epoch2, revision = 1L)))
        assertFalse(WatchBindingRules.planAllowed(binding(owner = null), "phone-1", envelope(revision = 1L)))
        assertFalse(WatchBindingRules.planAllowed(null, "phone-1", envelope(revision = 1L)))
    }

    @Test
    fun aSendIsBoundToNodeOwnerAndGenerationNotToRevisions() {
        val prepared = binding()
        assertTrue(WatchBindingRules.sameSendIdentity(prepared, prepared.copy(fullSyncRevision = 99L, planRevision = 7L)))
        assertFalse(WatchBindingRules.sameSendIdentity(prepared, prepared.copy(ownerId = ownerB)))
        assertFalse(WatchBindingRules.sameSendIdentity(prepared, prepared.copy(ownerId = null)))
        assertFalse(WatchBindingRules.sameSendIdentity(prepared, prepared.copy(accountGeneration = 6L)))
        assertFalse(WatchBindingRules.sameSendIdentity(prepared, prepared.copy(sourceNodeId = "phone-2")))
        assertFalse(WatchBindingRules.sameSendIdentity(prepared, null))
    }

    @Test
    fun heldOperationSurvivesSignOutAndAccountSwitchAndIsResentWithTheSameId() {
        val prefs = InMemoryPreferences()
        val sets = listOf(WearWorkoutSetDraft("Squat", 100.0, 5))
        fun create(binding: WatchSyncBinding) = WatchPendingWorkoutStorage.getOrCreate(
            prefs = prefs,
            binding = binding,
            draftId = "draft-1",
            startedAt = 1_700_000_000_000L,
            note = null,
            sets = sets,
            sourcePlanRaw = null,
            durationSeconds = 600L
        )
        val created = create(binding())
        assertEquals(ownerA, WatchPendingWorkoutStorage.heldOwnerId(prefs))

        // Signed out: not offered for sending, not deleted.
        assertNull(WatchPendingWorkoutStorage.load(prefs, binding(owner = null, generation = 6L)))
        assertEquals(ownerA, WatchPendingWorkoutStorage.heldOwnerId(prefs))
        // Another account: never offered to it, still kept.
        assertNull(WatchPendingWorkoutStorage.load(prefs, binding(owner = ownerB, generation = 7L)))
        assertEquals(ownerA, WatchPendingWorkoutStorage.heldOwnerId(prefs))
        assertEquals(
            HeldWorkState.HeldForeign,
            WatchBindingRules.heldWorkState(ownerB, WatchPendingWorkoutStorage.heldOwnerId(prefs), hasWork = true)
        )

        // Owner A again: a new generation, even a reinstalled phone on another node.
        val again = binding(generation = 8L, revision = 1L, epoch = epoch2, node = "phone-2")
        assertEquals(created.operationId, WatchPendingWorkoutStorage.load(prefs, again)?.operationId)
        assertEquals(created.operationId, create(again).operationId)
        assertEquals(600L, WatchPendingWorkoutStorage.load(prefs, again)?.durationSeconds)

        // Only an explicit clear (the user's Discard) removes it.
        WatchPendingWorkoutStorage.clear(prefs)
        assertNull(WatchPendingWorkoutStorage.heldOwnerId(prefs))
        assertNotEquals(created.operationId, create(again).operationId)
    }

    @Test
    fun bindingStateAndEnvelopeParsingAreStrict() {
        val now = System.currentTimeMillis()
        fun state(name: String = "unbound") = JSONObject()
            .put("protocolVersion", SyncPaths.PROTOCOL_VERSION)
            .put("state", name)
            .put("authorityEpoch", epoch1)
            .put("accountGeneration", 6L)
            .put("messageId", "message-1")
            .put("sentAt", now)
        val parsed = WatchSyncJson.parseBindingState(state().toString())
        assertEquals(
            ParsedBindingState(BindingStateKind.Unbound, epoch1, 6L, "message-1", now),
            (parsed as WatchSyncParseResult.Valid).value
        )
        assertEquals(
            BindingStateKind.Unlinked,
            (WatchSyncJson.parseBindingState(state("unlinked").toString()) as WatchSyncParseResult.Valid).value.kind
        )
        // Optional deletion reason: absent -> false; "account_deleted" on an unlink -> true; an
        // unknown reason, or the reason on an unbind, is ignored; a non-string reason is invalid.
        fun reasonOf(raw: JSONObject) =
            (WatchSyncJson.parseBindingState(raw.toString()) as WatchSyncParseResult.Valid).value.accountDeleted
        assertFalse(reasonOf(state("unlinked")))
        assertTrue(reasonOf(state("unlinked").put("reason", "account_deleted")))
        assertFalse(reasonOf(state("unlinked").put("reason", "something_new")))
        assertFalse(reasonOf(state().put("reason", "account_deleted")))
        assertTrue(
            WatchSyncJson.parseBindingState(state("unlinked").put("reason", 1).toString()) is WatchSyncParseResult.Invalid
        )
        assertTrue(
            WatchSyncJson.parseBindingState(state("unlinked").put("reason", "account_deleted").put("extra", 1).toString())
                is WatchSyncParseResult.Invalid
        )
        // A binding state never names an account (Apple Watch contract: "unbound" has no binding).
        assertTrue(WatchSyncJson.parseBindingState(state().put("ownerId", ownerA).toString()) is WatchSyncParseResult.Invalid)
        assertTrue(WatchSyncJson.parseBindingState(state("bound").toString()) is WatchSyncParseResult.Invalid)
        assertTrue(WatchSyncJson.parseBindingState(state().put("authorityEpoch", "x").toString()) is WatchSyncParseResult.Invalid)
        assertTrue(WatchSyncJson.parseBindingState(state().put("accountGeneration", 0L).toString()) is WatchSyncParseResult.Invalid)
        assertTrue(
            WatchSyncJson.parseBindingState(state().put("sentAt", now - 8L * 86_400_000L).toString())
                is WatchSyncParseResult.Invalid
        )

        // Every phone envelope must carry the authority epoch.
        fun fullSync(withEpoch: Boolean) = JSONObject()
            .put("protocolVersion", SyncPaths.PROTOCOL_VERSION)
            .put("ownerId", ownerA)
            .put("accountGeneration", 1L)
            .put("revision", 1L)
            .put("messageId", "message-1")
            .put("sentAt", now)
            .put("sessions", org.json.JSONArray())
            .apply { if (withEpoch) put("authorityEpoch", epoch2) }
            .toString()
        val valid = WatchSyncJson.parseFullSyncPayload(fullSync(withEpoch = true))
        assertEquals(epoch2, (valid as WatchSyncParseResult.Valid).value.envelope.authorityEpoch)
        assertTrue(WatchSyncJson.parseFullSyncPayload(fullSync(withEpoch = false)) is WatchSyncParseResult.Invalid)

        // The explicit link request is the only request that carries "link".
        val plain = JSONObject(WatchSyncJson.buildFullSyncRequestPayload("op-1", null))
        val link = JSONObject(WatchSyncJson.buildFullSyncRequestPayload("op-1", null, linkIntent = true))
        assertFalse(plain.has("link"))
        assertTrue(link.getBoolean("link"))
    }

    @Test
    fun operationIdIsStableWhenThePlanChangedOrWasClearedBetweenRetries() {
        val prefs = InMemoryPreferences()
        val sets = listOf(WearWorkoutSetDraft("Squat", 100.0, 5))
        fun create(plan: String?, workoutSets: List<WearWorkoutSetDraft> = sets) =
            WatchPendingWorkoutStorage.getOrCreate(
                prefs = prefs,
                binding = binding(),
                draftId = "draft-1",
                startedAt = 1_700_000_000_000L,
                note = null,
                sets = workoutSets,
                sourcePlanRaw = plan,
                durationSeconds = 600L
            )
        val first = create(plan = "{\"plan\":1}")
        // A sign-out cleared the plan on the watch, or a newer plan arrived: the same workout
        // keeps its id, and the stored content (what the phone may already hold) is sent again.
        assertEquals(first.operationId, create(plan = null).operationId)
        assertEquals(first.operationId, create(plan = "{\"plan\":2}").operationId)
        assertEquals("{\"plan\":1}", create(plan = null).sourcePlanRaw)
        // Other sets are another workout: a new operation.
        val changed = create(plan = null, workoutSets = sets + WearWorkoutSetDraft("Row", 60.0, 8))
        assertNotEquals(first.operationId, changed.operationId)
    }

    @Test
    fun anotherEpochWithTheSameTimestampIsNotNewer() {
        val linked = binding(lastSentAt = 5_000L)
        val tie = envelope(generation = 1L, revision = 1L, epoch = epoch2, sentAt = 5_000L)
        assertEquals(FullSyncDecision.Reject, decide(linked, tie))
        assertEquals(acceptRebased, decide(linked, tie.copy(sentAt = 5_001L)))
        assertEquals(
            BindingStateDecision.Reject,
            WatchBindingRules.decideBindingState(linked, "phone-1", unbound(1L, sentAt = 5_000L, epoch = epoch2))
        )
        assertEquals(
            BindingStateDecision.Unbind,
            WatchBindingRules.decideBindingState(linked, "phone-1", unbound(1L, sentAt = 5_001L, epoch = epoch2))
        )
        // A fresh pin has no authority yet: its first message is accepted whatever its time.
        assertEquals(acceptRebased, decide(WatchSyncBinding("phone-1", null, 0L, 0L, 0L), envelope(sentAt = 0L)))
    }

    @Test
    fun capabilityEventFlushesOnlyForTheBoundPinnedPhone() {
        val linked = binding()
        val capability = SyncPaths.PHONE_CAPABILITY
        assertTrue(WatchBindingRules.pinnedPhoneReachable(linked, capability, setOf("phone-1", "phone-2")))
        assertFalse(WatchBindingRules.pinnedPhoneReachable(linked, capability, setOf("phone-2")))
        assertFalse(WatchBindingRules.pinnedPhoneReachable(linked, capability, emptySet()))
        assertFalse(WatchBindingRules.pinnedPhoneReachable(linked, "another_capability", setOf("phone-1")))
        assertFalse(WatchBindingRules.pinnedPhoneReachable(binding(owner = null), capability, setOf("phone-1")))
        assertFalse(WatchBindingRules.pinnedPhoneReachable(null, capability, setOf("phone-1")))
    }
}
