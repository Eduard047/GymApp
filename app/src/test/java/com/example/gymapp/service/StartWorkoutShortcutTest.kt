package com.example.gymapp.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StartWorkoutShortcutTest {
    @Test
    fun onlyTheExactShortcutActionIsRecognised() {
        assertTrue(isStartWorkoutShortcutAction(ACTION_START_WORKOUT_SHORTCUT))
        assertFalse(isStartWorkoutShortcutAction(ACTION_OPEN_ACTIVE_WORKOUT))
        assertFalse(isStartWorkoutShortcutAction(ACTION_START_WORKOUT_SHORTCUT + "x"))
        assertFalse(isStartWorkoutShortcutAction(null))
    }

    @Test
    fun recreatedInstancesDoNotReplayTheShortcut() {
        assertTrue(shouldRequestStartWorkoutShortcut(ACTION_START_WORKOUT_SHORTCUT, restoredInstance = false))
        assertFalse(shouldRequestStartWorkoutShortcut(ACTION_START_WORKOUT_SHORTCUT, restoredInstance = true))
        assertFalse(shouldRequestStartWorkoutShortcut(null, restoredInstance = false))
    }

    @Test
    fun routingDecisionTable() {
        assertEquals(StartWorkoutShortcutRoute.OpenApp, startWorkoutShortcutRoute(hasSession = false, hasActiveWorkout = false))
        assertEquals(StartWorkoutShortcutRoute.OpenApp, startWorkoutShortcutRoute(hasSession = false, hasActiveWorkout = true))
        assertEquals(StartWorkoutShortcutRoute.OpenActiveWorkout, startWorkoutShortcutRoute(hasSession = true, hasActiveWorkout = true))
        assertEquals(StartWorkoutShortcutRoute.OpenWorkoutEditor, startWorkoutShortcutRoute(hasSession = true, hasActiveWorkout = false))
    }

    @Test
    fun shortcutInboxIsIndependentOfNotificationInbox() {
        val inbox = ActiveWorkoutOpenInbox()
        inbox.requestStartShortcut()
        assertNull(inbox.pending.value)
        val first = inbox.startShortcutPending.value!!
        inbox.requestStartShortcut()
        val second = inbox.startShortcutPending.value!!
        inbox.consumeStartShortcut(first)
        assertEquals(second, inbox.startShortcutPending.value)
        inbox.consumeStartShortcut(second)
        assertNull(inbox.startShortcutPending.value)
    }
}
