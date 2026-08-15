package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutPlanEditorTest {
    @Test
    fun selectedLiveFriendReplacesSoloPrimaryAction() {
        assertEquals(
            WorkoutPlanPrimaryAction.StartSolo,
            workoutPlanPrimaryAction(hasLiveInviteTarget = false)
        )
        assertEquals(
            WorkoutPlanPrimaryAction.SendLiveInvite,
            workoutPlanPrimaryAction(hasLiveInviteTarget = true)
        )
    }

    @Test
    fun partiallyRestoredLiveTargetNeverFallsBackToSolo() {
        assertEquals(
            WorkoutPlanPrimaryAction.SendLiveInvite,
            workoutPlanPrimaryAction(hasLiveInviteTarget = true)
        )
    }

    @Test
    fun liveBoundEditorCannotOpenGenericSharePicker() {
        assertTrue(workoutPlanAllowsGenericShare(hasLiveInviteTarget = false))
        assertFalse(workoutPlanAllowsGenericShare(hasLiveInviteTarget = true))
    }

    @Test
    fun directLiveValidationAndSendLockEveryEditorInteraction() {
        assertFalse(workoutPlanEditorInteractionsLocked(isLiveInviteSending = false))
        assertTrue(workoutPlanEditorInteractionsLocked(isLiveInviteSending = true))
    }
}
