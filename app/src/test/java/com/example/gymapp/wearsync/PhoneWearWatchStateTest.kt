package com.example.gymapp.wearsync

import com.example.gymapp.ui.viewmodel.wearWatchUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Card state built from the pin, the connected nodes, the stored name and the link proof. */
class PhoneWearWatchStateTest {
    @Test
    fun offlineLinkedWatchKeepsItsLastSeenName() {
        val online = wearWatchUiState(true, "watch-1", mapOf("watch-1" to "Pixel Watch 3"), storedName = "Old name")
        assertTrue(online.connected)
        assertEquals("Pixel Watch 3", online.displayName)

        val offline = wearWatchUiState(true, "watch-1", emptyMap(), storedName = " Pixel\u0007 Watch 3 ")
        assertTrue(offline.linked)
        assertFalse(offline.connected)
        assertEquals("Pixel Watch 3", offline.displayName)

        // Nothing stored yet: the caller falls back to the generic name.
        assertNull(wearWatchUiState(true, "watch-1", emptyMap()).displayName)
    }

    @Test
    fun linkedMeansPinnedAndConfirmedMeansTheWatchFollowsThisPhone() {
        val pinnedOnly = wearWatchUiState(true, "watch-1", mapOf("watch-1" to "Watch"))
        assertTrue(pinnedOnly.linked)
        assertFalse(pinnedOnly.linkConfirmed)
        assertNull(pinnedOnly.lastSeenAtMillis)

        val confirmed = wearWatchUiState(true, "watch-1", emptyMap(), linkProofAtMillis = 1_750_000_000_000L)
        assertTrue(confirmed.linkConfirmed)
        assertEquals(1_750_000_000_000L, confirmed.lastSeenAtMillis)

        // No pin: neither a stored name nor a proof makes the card "linked".
        val unlinked = wearWatchUiState(true, null, emptyMap(), storedName = "Watch", linkProofAtMillis = 5L)
        assertFalse(unlinked.linked)
        assertFalse(unlinked.linkConfirmed)
        assertNull(unlinked.displayName)
    }
}
