package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Test

class AccountSettingsSheetTest {
    @Test
    fun shortIdentifiersAreShownInFull() {
        assertEquals("user-1", middleTruncatedIdentifier("user-1"))
        assertEquals("0123456789abcdef0", middleTruncatedIdentifier("0123456789abcdef0"))
    }

    @Test
    fun longIdentifiersKeepBothEnds() {
        assertEquals(
            "3f2a9c1e…5f6a7b8c",
            middleTruncatedIdentifier("3f2a9c1e-7d44-4b2e-9a10-0c5e5f6a7b8c")
        )
        assertEquals("abc…xyz", middleTruncatedIdentifier("abcdefghijklmnopqrstuvwxyz", 3))
    }
}
