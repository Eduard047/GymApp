package com.example.gymapp.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestTimerControllerTest {
    @Test
    fun timerResetsOnlyWhenTheBoundAccountActuallyChanges() {
        val tracker = RestTimerAccountSwitchTracker()
        val accountA = "a".repeat(64)
        val accountB = "b".repeat(64)

        assertFalse(tracker.bind(accountA))
        assertFalse(tracker.bind(accountA))
        assertTrue(tracker.bind(accountB))
        assertFalse(tracker.bind(accountB))
        assertTrue(tracker.bind(null))
        assertFalse(tracker.bind(null))
        assertTrue(tracker.bind(accountA))
    }
}
