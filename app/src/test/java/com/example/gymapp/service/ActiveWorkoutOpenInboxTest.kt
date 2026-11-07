package com.example.gymapp.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutOpenInboxTest {
    @Test
    fun onlyTheExactNotificationActionOpensTheActiveWorkout() {
        assertTrue(isOpenActiveWorkoutAction(ACTION_OPEN_ACTIVE_WORKOUT))
        assertFalse(isOpenActiveWorkoutAction(null))
        assertFalse(isOpenActiveWorkoutAction(""))
        assertFalse(isOpenActiveWorkoutAction("android.intent.action.MAIN"))
        assertFalse(isOpenActiveWorkoutAction(ACTION_OPEN_ACTIVE_WORKOUT + "x"))
    }

    @Test
    fun requestsAreConsumedOnlyByTheirOwnId() {
        val inbox = ActiveWorkoutOpenInbox()
        assertNull(inbox.pending.value)
        inbox.request()
        val first = inbox.pending.value
        assertEquals(1L, first)
        inbox.request()
        val second = inbox.pending.value
        assertNotEquals(first, second)
        inbox.consume(first!!)
        assertEquals(second, inbox.pending.value)
        inbox.consume(second!!)
        assertNull(inbox.pending.value)
    }

    @Test
    fun clearDropsAPendingRequest() {
        val inbox = ActiveWorkoutOpenInbox()
        inbox.request()
        inbox.clear()
        assertNull(inbox.pending.value)
    }
}
