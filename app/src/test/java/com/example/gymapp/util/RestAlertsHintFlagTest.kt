package com.example.gymapp.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestAlertsHintFlagTest {
    private class MemoryStorage(var seen: Boolean = false) : RestAlertsHintStorage {
        override fun isSeen() = seen
        override fun markSeen() { seen = true }
    }

    @Test
    fun showsWhileMutedAndNotYetBurned() {
        val flag = RestAlertsHintFlag(MemoryStorage())
        assertTrue(flag.mayShow(alertsMuted = true))
        assertTrue(flag.mayShow(alertsMuted = true))
    }

    @Test
    fun neverShownAgainOnceBurned() {
        val storage = MemoryStorage()
        val flag = RestAlertsHintFlag(storage)
        flag.burn()
        assertFalse(flag.mayShow(alertsMuted = true))
        assertFalse(RestAlertsHintFlag(storage).mayShow(alertsMuted = true))
    }

    @Test
    fun enabledNotificationsBurnTheNote() {
        val storage = MemoryStorage()
        val flag = RestAlertsHintFlag(storage)
        assertFalse(flag.mayShow(alertsMuted = false))
        assertTrue(storage.seen)
        assertFalse(flag.mayShow(alertsMuted = true))
    }
}
