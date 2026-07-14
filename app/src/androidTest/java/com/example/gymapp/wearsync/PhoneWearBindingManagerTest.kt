package com.example.gymapp.wearsync

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.gymapp.auth.AccountSession
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PhoneWearBindingManagerTest {
    @Test
    fun localIdentitySurvivesManagerRecreationAndLogoutAdvancesGeneration() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("phone_wear_sync", 0).edit().clear().commit()
        val manager = PhoneWearBindingManager(context)

        val signedOut = manager.synchronizeSession(null)
        val firstLocalSession = AccountSession.Local("Owner")
        val firstLocal = manager.synchronizeSession(firstLocalSession)
        val unchanged = manager.synchronizeSession(firstLocalSession)
        val recreatedManager = PhoneWearBindingManager(context)
        val sameAccountAfterRecreation = recreatedManager.synchronizeSession(AccountSession.Local("Owner"))
        val signedOutAgain = manager.synchronizeSession(null)
        val localAfterLogout = manager.synchronizeSession(AccountSession.Local("Owner"))

        assertTrue(signedOut.signedOut)
        assertFalse(firstLocal.signedOut)
        assertEquals(firstLocal, unchanged)
        assertEquals(firstLocal, sameAccountAfterRecreation)
        assertTrue(signedOutAgain.accountGeneration > firstLocal.accountGeneration)
        assertEquals(firstLocal.ownerId, localAfterLogout.ownerId)
        assertTrue(localAfterLogout.accountGeneration > signedOutAgain.accountGeneration)
        assertEquals(signedOut.ownerId, signedOutAgain.ownerId)
        assertNotEquals(firstLocal.ownerId, signedOut.ownerId)
    }

    @Test
    fun sourcePinsOnlyFromSingleConnectedNodeAndNeverSilentlyReplacesIt() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("phone_wear_sync", 0).edit().clear().commit()
        val manager = PhoneWearBindingManager(context)
        val binding = manager.synchronizeSession(AccountSession.Local("Owner"))

        assertFalse(manager.authorizeSource("watch-a", setOf("watch-a", "watch-b"), binding))
        assertTrue(manager.authorizeSource("watch-a", setOf("watch-a"), binding))
        assertTrue(manager.authorizeSource("watch-a", setOf("watch-a", "watch-b"), binding))
        assertFalse(manager.authorizeSource("watch-b", setOf("watch-a", "watch-b"), binding))
        assertEquals("watch-a", manager.pinnedSource()!!.nodeId)
        assertTrue(manager.isPinnedToOwner("watch-a", binding.ownerId))

        val otherAccount = manager.synchronizeSession(AccountSession.Local("Other"))
        assertFalse(manager.isPinnedToOwner("watch-a", otherAccount.ownerId))
        assertTrue(manager.authorizeSource("watch-a", setOf("watch-a"), otherAccount))
        assertFalse(manager.isPinnedToOwner("watch-a", otherAccount.ownerId))
        assertFalse(manager.authorizeSource("watch-b", setOf("watch-a", "watch-b"), otherAccount))
    }

    @Test
    fun fullSyncRevisionIsMonotonicAndAccountScoped() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        context.getSharedPreferences("phone_wear_sync", 0).edit().clear().commit()
        val manager = PhoneWearBindingManager(context)
        val first = manager.synchronizeSession(AccountSession.Local("One"))

        assertEquals(1L, manager.nextFullSyncRevision(first))
        assertEquals(2L, manager.nextFullSyncRevision(first))

        val second = manager.synchronizeSession(AccountSession.Local("Two"))
        assertTrue(second.accountGeneration > first.accountGeneration)
        assertEquals(1L, manager.nextFullSyncRevision(second))
    }
}
