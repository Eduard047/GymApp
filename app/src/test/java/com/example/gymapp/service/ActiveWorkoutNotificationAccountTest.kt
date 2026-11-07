package com.example.gymapp.service

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutNotificationAccountTest {
    @Test
    fun signOutClearsNotification() {
        assertTrue(shouldClearActiveWorkoutNotification("a", true, null))
        assertTrue(shouldClearActiveWorkoutNotification(null, false, null))
    }

    @Test
    fun switchingAccountClearsNotification() {
        assertTrue(shouldClearActiveWorkoutNotification("a", true, "b"))
        assertTrue(shouldClearActiveWorkoutNotification(null, true, "b"))
    }

    @Test
    fun firstAccountAfterProcessStartKeepsNotification() {
        assertFalse(shouldClearActiveWorkoutNotification(null, false, "a"))
    }

    @Test
    fun sameAccountKeepsNotification() {
        assertFalse(shouldClearActiveWorkoutNotification("a", true, "a"))
    }
}
