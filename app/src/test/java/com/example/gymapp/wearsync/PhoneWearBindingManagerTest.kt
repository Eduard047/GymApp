package com.example.gymapp.wearsync

import android.content.SharedPreferences
import com.example.gymapp.auth.AccountSession
import com.example.gymapp.auth.databaseName
import org.junit.Assert.assertEquals
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneWearBindingManagerTest {
    @Test
    fun unlinkForgetsOnlyThePinnedWatchAndAllowsALaterRepin() {
        val prefs = InMemoryPreferences()
        val manager = PhoneWearBindingManager(prefs)
        // A signed-out phone never pins; use a bound (non-signed-out) binding.
        val binding = binding()
        prefs.edit().putLong("active_generation", 7L).putLong("full_sync_revision", 3L)
            .putString("receipt_marker", "kept").commit()

        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), binding))
        assertEquals("watch-1", manager.pinnedSourceNodeId())
        assertEquals("watch-1", manager.pinnedSource()?.nodeId)
        // While pinned, another watch is refused.
        assertFalse(manager.authorizeSource("watch-2", setOf("watch-2"), binding))

        assertTrue(manager.clearPinnedSource())
        assertNull(manager.pinnedSourceNodeId())
        assertNull(manager.pinnedSource())
        assertFalse(manager.isPinnedNode("watch-1"))
        // Nothing but the pin is touched: generations, revisions and other stored data stay.
        assertEquals(7L, prefs.getLong("active_generation", 0L))
        assertEquals(3L, prefs.getLong("full_sync_revision", 0L))
        assertEquals("kept", prefs.getString("receipt_marker", null))

        // A later valid request from a single connected watch may pin again (any watch).
        assertTrue(manager.authorizeSource("watch-2", setOf("watch-2"), binding))
        assertEquals("watch-2", manager.pinnedSourceNodeId())
    }

    @Test
    fun unlinkWithoutAPinIsHarmless() {
        val manager = PhoneWearBindingManager(InMemoryPreferences())
        assertTrue(manager.clearPinnedSource())
        assertNull(manager.pinnedSourceNodeId())
    }

    @Test
    fun unlinkedWatchIsNotPinnedAgainWithoutAnExplicitLinkRequest() {
        val manager = PhoneWearBindingManager(InMemoryPreferences())
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), binding()))
        assertTrue(manager.clearPinnedSource())
        assertTrue(manager.isUnlinkedNode("watch-1"))
        // Opening the watch app (a plain sync request) must not relink silently.
        assertFalse(manager.authorizeSource("watch-1", setOf("watch-1"), binding()))
        assertNull(manager.pinnedSourceNodeId())
        // The explicit link request is the normal first-link path again.
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), binding(), linkIntent = true))
        assertEquals("watch-1", manager.pinnedSourceNodeId())
        assertFalse(manager.isUnlinkedNode("watch-1"))
    }

    @Test
    fun linkIntentNeverWeakensThePinRules() {
        val manager = PhoneWearBindingManager(InMemoryPreferences())
        // Signed out: nothing is pinned, with or without a link request.
        assertFalse(
            manager.authorizeSource("watch-1", setOf("watch-1"), binding().copy(signedOut = true), linkIntent = true)
        )
        // More than one connected node: no pin.
        assertFalse(manager.authorizeSource("watch-1", setOf("watch-1", "watch-2"), binding(), linkIntent = true))
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), binding()))
        // Another watch cannot take over an existing pin by asking to link.
        assertFalse(manager.authorizeSource("watch-2", setOf("watch-2"), binding(), linkIntent = true))
        assertEquals("watch-1", manager.pinnedSourceNodeId())
    }

    @Test
    fun aReinstalledPhoneRestartsCountersButPresentsANewAuthorityEpoch() {
        val firstInstall = PhoneWearBindingManager(InMemoryPreferences())
        val reinstalled = PhoneWearBindingManager(InMemoryPreferences())
        val first = firstInstall.synchronizeSession(null)
        val again = firstInstall.synchronizeSession(null)
        val fresh = reinstalled.synchronizeSession(null)
        // Stable within one install, so replay protection by generation/revision keeps working.
        assertEquals(first, again)
        // The counters restart after a reinstall; the epoch is what tells the installs apart.
        assertEquals(first.accountGeneration, fresh.accountGeneration)
        assertNotEquals(first.authorityEpoch, fresh.authorityEpoch)
        assertEquals(1L, firstInstall.nextFullSyncRevision(first))
        assertEquals(1L, reinstalled.nextFullSyncRevision(fresh))
    }

    @Test
    fun watchNameAndLinkProofArePersistedWithThePinAndClearedOnUnlink() {
        val manager = PhoneWearBindingManager(InMemoryPreferences())
        val binding = binding()
        // Nothing is stored for a watch that is not pinned.
        assertFalse(manager.rememberWatchName("watch-1", "Pixel Watch"))
        assertFalse(manager.recordLinkProof("watch-1", binding, 1_000L))
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), binding))
        assertNull(manager.pinnedWatchName())
        assertNull(manager.linkProofAt(binding))

        assertFalse(manager.rememberWatchName("watch-2", "Other"))
        assertTrue(manager.rememberWatchName("watch-1", " Pixel\u0007 Watch "))
        assertEquals("Pixel Watch", manager.pinnedWatchName())
        assertFalse(manager.recordLinkProof("watch-2", binding, 2_000L))
        assertTrue(manager.recordLinkProof("watch-1", binding, 1_000L))
        assertEquals(1_000L, manager.linkProofAt(binding))
        // A proof for one account/generation is not a proof for another one.
        assertNull(manager.linkProofAt(binding.copy(accountGeneration = 2L)))
        assertNull(manager.linkProofAt(binding.copy(ownerId = "b".repeat(64))))
        assertNull(manager.linkProofAt(binding.copy(signedOut = true)))

        assertTrue(manager.clearPinnedSource())
        assertNull(manager.pinnedWatchName())
        assertNull(manager.linkProofAt(binding))
    }

    @Test
    fun lastPlanIsCachedPerOwnerForThePinnedWatchUntilDeliveredOrUnlinked() {
        val manager = PhoneWearBindingManager(InMemoryPreferences())
        val ownerA = "a".repeat(64)
        val ownerB = "b".repeat(64)
        val plan = PhoneWearCachedPlan(
            planId = "plan-1",
            createdAt = 1_000L,
            sets = listOf(NamedWorkoutSetDraft(exerciseName = "Присед", weight = 100.0, reps = 5)),
            exerciseCatalog = listOf("Присед"),
            profile = PhoneWearPlanProfile("FULL_BODY", 3, "STRENGTH", "MAINTAIN"),
            planSource = "smart_coach"
        )
        // No pinned watch: nothing is kept.
        assertFalse(manager.cachePlan(ownerA, plan))
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), binding()))
        assertTrue(manager.cachePlan(ownerA, plan))

        val cached = manager.cachedPlan(ownerA, now = 2_000L)
        assertEquals("plan-1", cached?.planId)
        assertEquals("Присед", cached?.sets?.single()?.exerciseName)
        assertEquals(5, cached?.sets?.single()?.reps)
        assertEquals(3, cached?.profile?.workoutsPerWeek)
        // Another account on this phone never gets it.
        assertNull(manager.cachedPlan(ownerB, now = 2_000L))
        // The delivery report of an older plan does not remove a newer one.
        assertFalse(manager.removeCachedPlan(ownerA, "older-plan"))
        assertEquals("plan-1", manager.cachedPlan(ownerA, now = 2_000L)?.planId)
        // Delivered: not sent again.
        assertTrue(manager.removeCachedPlan(ownerA, "plan-1"))
        assertNull(manager.cachedPlan(ownerA, now = 2_000L))

        // Too old to resend.
        assertTrue(manager.cachePlan(ownerA, plan))
        assertNull(manager.cachedPlan(ownerA, now = 1_000L + PhoneWearPlanCacheCodec.MAX_AGE_MS + 1L))
        // Unlink removes every cached plan.
        assertTrue(manager.cachePlan(ownerA, plan))
        assertTrue(manager.clearPinnedSource())
        assertNull(manager.cachedPlan(ownerA, now = 2_000L))
    }

    @Test
    fun invalidOrOversizedCachedPlansAreNotStored() {
        val manager = PhoneWearBindingManager(InMemoryPreferences())
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), binding()))
        fun plan(reps: Int, sets: Int = 1) = PhoneWearCachedPlan(
            planId = "plan-1",
            createdAt = 1_000L,
            sets = List(sets) { NamedWorkoutSetDraft(exerciseName = "Squat", weight = 100.0, reps = reps) },
            exerciseCatalog = emptyList(),
            profile = null,
            planSource = "smart_coach"
        )
        assertFalse(manager.cachePlan("a".repeat(64), plan(reps = 0)))
        assertFalse(manager.cachePlan("a".repeat(64), plan(reps = 5, sets = PhoneWearPaths.MAX_PLAN_SETS + 1)))
        assertFalse(manager.cachePlan("not-an-owner", plan(reps = 5)))
        assertNull(PhoneWearPlanCacheCodec.decode("{\"planId\":\"x\"}", now = 2_000L))
    }

    @Test
    fun watchUnlinkIsAcceptedOnlyFromThePinnedNodeForTheCurrentAccount() {
        val current = binding()
        fun accepted(
            pinned: Boolean = true,
            owner: String? = current.ownerId,
            generation: Long? = current.accountGeneration,
            binding: PhoneWearAccountBinding = current
        ) = phoneWearWatchUnlinkAccepted(pinned, owner, generation, binding)

        assertTrue(accepted())
        assertFalse(accepted(pinned = false))
        assertFalse(accepted(owner = "b".repeat(64)))
        assertFalse(accepted(generation = current.accountGeneration + 1))
        assertFalse(accepted(owner = null, generation = null))

        val signedOut = current.copy(ownerId = "c".repeat(64), signedOut = true)
        assertTrue(accepted(owner = null, generation = null, binding = signedOut))
        assertFalse(accepted(binding = signedOut))
        assertFalse(accepted(pinned = false, owner = null, generation = null, binding = signedOut))
    }

    @Test
    fun deletedLocalProfileReCreatedUnderTheSameNameInheritsNoWatchState() {
        val prefs = InMemoryPreferences()
        val manager = PhoneWearBindingManager(prefs)
        val anna = AccountSession.Local("Synthetic Anna")
        val databaseName = anna.databaseName()
        val ownerId = PhoneWearBindingManager.localOwnerId(databaseName)
        val first = manager.synchronizeSession(anna)
        assertEquals(ownerId, first.ownerId)
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), first))
        assertTrue(manager.recordLinkProof("watch-1", first, 1_000L))
        assertTrue(manager.cachePlan(ownerId, cachedPlan()))
        val localIdKeys = prefs.all.keys.filter { it.startsWith("local_account_id_") }
        assertEquals(1, localIdKeys.size)

        // Deletion signs the profile out first, then clears its watch state.
        manager.synchronizeSession(null)
        val cleanup = manager.clearOwner(ownerId, databaseName)

        assertTrue(cleanup.committed)
        assertEquals("watch-1", cleanup.releasedNodeId)
        assertNull(manager.pinnedSource())
        assertTrue(manager.isUnlinkedNode("watch-1"))
        assertFalse(prefs.contains("plan_cache_$ownerId"))
        assertFalse(prefs.contains(localIdKeys.single()))

        // Same name again: same owner id (watch compatibility), but a new generation, no pin,
        // no link proof and no cached plan; opening the watch app does not re-pin it.
        val second = manager.synchronizeSession(AccountSession.Local("Synthetic Anna"))
        assertEquals(ownerId, second.ownerId)
        assertTrue(second.accountGeneration > first.accountGeneration)
        assertNull(manager.linkProofAt(second))
        assertNull(manager.cachedPlan(ownerId, 2_000L))
        assertFalse(manager.authorizeSource("watch-1", setOf("watch-1"), second))
        assertNull(manager.pinnedSourceNodeId())
    }

    @Test
    fun clearOwnerKeepsAWatchPinnedToAnotherOwner() {
        val prefs = InMemoryPreferences()
        val manager = PhoneWearBindingManager(prefs)
        val deletedOwner = PhoneWearBindingManager.cloudOwnerId("00000000-0000-4000-8000-000000000001")
        val other = binding()
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), other))
        assertTrue(manager.recordLinkProof("watch-1", other, 1_000L))
        assertTrue(manager.cachePlan(other.ownerId, cachedPlan()))
        assertTrue(manager.cachePlan(deletedOwner, cachedPlan()))

        val cleanup = manager.clearOwner(deletedOwner)

        assertTrue(cleanup.committed)
        assertNull(cleanup.releasedNodeId)
        assertEquals("watch-1", manager.pinnedSourceNodeId())
        assertEquals(1_000L, manager.linkProofAt(other))
        assertTrue(prefs.contains("plan_cache_${other.ownerId}"))
        assertFalse(prefs.contains("plan_cache_$deletedOwner"))
        // A malformed owner id touches nothing.
        assertFalse(manager.clearOwner("not-an-owner").committed)
        assertEquals("watch-1", manager.pinnedSourceNodeId())
    }

    @Test
    fun releasedWatchKeepsThePendingDeletedOwnerUntilToldOrExpired() {
        val prefs = InMemoryPreferences()
        val manager = PhoneWearBindingManager(prefs)
        val owner = binding()
        val day = 24L * 60 * 60 * 1000
        val deletedAt = 50L * day
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), owner))
        // Not pinned to that owner: nothing pending.
        assertTrue(manager.clearOwner("d".repeat(64), now = deletedAt).committed)
        assertNull(manager.pendingDeletedOwnerId("watch-1", deletedAt))

        val cleanup = manager.clearOwner(owner.ownerId, now = deletedAt)
        assertEquals("watch-1", cleanup.releasedNodeId)
        assertTrue(manager.isUnlinkedNode("watch-1"))
        assertEquals(owner.ownerId, manager.pendingDeletedOwnerId("watch-1", deletedAt + day))
        // Only for the released watch.
        assertNull(manager.pendingDeletedOwnerId("watch-2", deletedAt + day))
        // Told: gone.
        assertFalse(manager.clearPendingDeletedOwner("d".repeat(64)))
        assertTrue(manager.clearPendingDeletedOwner(owner.ownerId))
        assertNull(manager.pendingDeletedOwnerId("watch-1", deletedAt + day))

        // Expires after 30 days.
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), owner, linkIntent = true))
        manager.clearOwner(owner.ownerId, now = deletedAt)
        assertEquals(owner.ownerId, manager.pendingDeletedOwnerId("watch-1", deletedAt + 30L * day))
        assertNull(manager.pendingDeletedOwnerId("watch-1", deletedAt + 30L * day + 1L))
        assertFalse(prefs.contains(PhoneWearBindingManager.KEY_PENDING_DELETED_OWNER_ID))

        // A re-link or a plain "Unlink watch" ends it as well.
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), owner, linkIntent = true))
        manager.clearOwner(owner.ownerId, now = deletedAt)
        assertTrue(manager.authorizeSource("watch-1", setOf("watch-1"), owner, linkIntent = true))
        assertFalse(prefs.contains(PhoneWearBindingManager.KEY_PENDING_DELETED_OWNER_ID))
        manager.clearOwner(owner.ownerId, now = deletedAt)
        assertTrue(manager.clearPinnedSource())
        assertFalse(prefs.contains(PhoneWearBindingManager.KEY_PENDING_DELETED_OWNER_ID))
    }

    private fun cachedPlan() = PhoneWearCachedPlan(
        planId = "11111111-2222-4333-8444-555555555555",
        createdAt = System.currentTimeMillis(),
        sets = listOf(NamedWorkoutSetDraft(exerciseName = "Squat", weight = 50.0, reps = 5)),
        exerciseCatalog = listOf("Squat"),
        profile = PhoneWearPlanProfile(
            split = "FULL_BODY",
            workoutsPerWeek = 3,
            goal = "STRENGTH",
            calorieMode = "MAINTAIN"
        ),
        planSource = "smart_coach"
    )

    private fun binding() = PhoneWearAccountBinding(
        ownerId = "a".repeat(64),
        accountGeneration = 1,
        signedOut = false,
        authorityEpoch = "11111111-2222-4333-8444-555555555555"
    )

    /** Minimal in-memory SharedPreferences for JVM tests. */
    private class InMemoryPreferences : SharedPreferences {
        val values = linkedMapOf<String, Any?>()

        override fun getAll(): MutableMap<String, *> = values.toMutableMap()
        override fun getString(key: String, defValue: String?): String? = values[key] as? String ?: defValue
        override fun getStringSet(key: String, defValues: MutableSet<String>?): MutableSet<String>? =
            @Suppress("UNCHECKED_CAST") (values[key] as? MutableSet<String>) ?: defValues
        override fun getInt(key: String, defValue: Int): Int = values[key] as? Int ?: defValue
        override fun getLong(key: String, defValue: Long): Long = values[key] as? Long ?: defValue
        override fun getFloat(key: String, defValue: Float): Float = values[key] as? Float ?: defValue
        override fun getBoolean(key: String, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue
        override fun contains(key: String): Boolean = key in values
        override fun edit(): SharedPreferences.Editor = Editor()
        override fun registerOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) = Unit
        override fun unregisterOnSharedPreferenceChangeListener(
            listener: SharedPreferences.OnSharedPreferenceChangeListener?
        ) = Unit

        private inner class Editor : SharedPreferences.Editor {
            private val puts = linkedMapOf<String, Any?>()
            private val removes = mutableSetOf<String>()
            private var clear = false

            override fun putString(key: String, value: String?) = apply { puts[key] = value }
            override fun putStringSet(key: String, values: MutableSet<String>?) = apply { puts[key] = values }
            override fun putInt(key: String, value: Int) = apply { puts[key] = value }
            override fun putLong(key: String, value: Long) = apply { puts[key] = value }
            override fun putFloat(key: String, value: Float) = apply { puts[key] = value }
            override fun putBoolean(key: String, value: Boolean) = apply { puts[key] = value }
            override fun remove(key: String) = apply { removes += key }
            override fun clear() = apply { clear = true }
            override fun commit(): Boolean {
                if (clear) values.clear()
                removes.forEach(values::remove)
                values.putAll(puts)
                return true
            }
            override fun apply() {
                commit()
            }
        }
    }
}
