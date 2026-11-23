package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WearWatchStateTest {
    @Test
    fun cardIsHiddenUntilTheWearableApiIsKnownToBeAvailable() {
        assertEquals(WearWatchCardMode.HIDDEN, wearWatchCardMode(null))
        assertEquals(WearWatchCardMode.HIDDEN, wearWatchCardMode(WearWatchUiState()))
        // A stale pin never shows the card when Play services cannot reach the Wearable API.
        assertEquals(
            WearWatchCardMode.HIDDEN,
            wearWatchCardMode(wearWatchUiState(false, "node-1", mapOf("node-1" to "Pixel Watch")))
        )
    }

    @Test
    fun noPinReadsAsNotLinked() {
        val state = wearWatchUiState(true, null, mapOf("node-1" to "Pixel Watch"))
        assertEquals(WearWatchCardMode.NOT_LINKED, wearWatchCardMode(state))
        assertFalse(state.linked)
        assertFalse(state.connected)
        assertEquals(WearWatchCardMode.NOT_LINKED, wearWatchCardMode(wearWatchUiState(true, " ", emptyMap())))
    }

    @Test
    fun linkedWatchUsesItsNodeNameWhileConnected() {
        val state = wearWatchUiState(true, "node-1", mapOf("node-1" to "Galaxy Watch7", "node-2" to "Other"))
        assertEquals(WearWatchCardMode.LINKED, wearWatchCardMode(state))
        assertTrue(state.connected)
        assertEquals("Galaxy Watch7", wearWatchDisplayName(state, "Wear OS watch"))
    }

    @Test
    fun linkedButDisconnectedWatchFallsBackToTheGenericName() {
        // Another watch being connected must not lend its name or its connection to the pinned one.
        val state = wearWatchUiState(true, "node-1", mapOf("node-2" to "Other"))
        assertEquals(WearWatchCardMode.LINKED, wearWatchCardMode(state))
        assertFalse(state.connected)
        assertNull(state.displayName)
        assertEquals("Wear OS watch", wearWatchDisplayName(state, "Wear OS watch"))
    }

    @Test
    fun nodeNamesAreSanitized() {
        assertEquals("Wear OS watch", wearWatchDisplayName(
            wearWatchUiState(true, "n", mapOf("n" to "  \n ")), "Wear OS watch"
        ))
        assertEquals("Pixel Watch", sanitizeWearWatchName("Pixel\u0000 Watch\n".replace("\u0000 ", " ")))
        assertEquals("AB", sanitizeWearWatchName("A\u0007B"))
        assertEquals(64, sanitizeWearWatchName("x".repeat(500))!!.length)
        assertNull(sanitizeWearWatchName(null))
    }
}
