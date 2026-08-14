package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LiveLobbyContractTest {
    @Test
    fun onlyAuthoritativeActiveRoomHasAVisiblePrimaryAction() {
        assertNull(liveLobbyPrimaryAction("waiting"))
        assertNull(liveLobbyPrimaryAction("ready"))
        assertEquals(
            LiveLobbyPrimaryAction.OpenActiveWorkout,
            liveLobbyPrimaryAction("active")
        )
    }
}
