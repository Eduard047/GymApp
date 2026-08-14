package com.example.gymapp.ui.viewmodel

import com.example.gymapp.R
import com.example.gymapp.util.LocalizedText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveAcceptRestorationStateTest {
    @Test
    fun confirmedMutationRefreshFailureIsRestoringNotMutationFailure() {
        val state = LiveWorkoutUiState(
            actionsInFlight = setOf("respond-lr_test"),
            error = LocalizedText(R.string.live_workout_action_failed)
        )

        val restoring = confirmedLiveAcceptRestoringState(state, "lr_test")

        assertNull(restoring.error)
        assertEquals(
            R.string.live_workout_confirmed_restoring,
            restoring.notice?.resourceId
        )
        assertEquals(state.actionsInFlight, restoring.actionsInFlight)
        assertEquals("lr_test", restoring.confirmedRestoringRoomId)
    }

    @Test
    fun legacyReadyResponseCannotCompleteRestorationWithoutAuthoritativeActiveState() {
        assertFalse(
            isConfirmedLiveAcceptAuthoritativelyRestored(
                expectedRoomId = "lr_room",
                snapshotRoomId = "lr_room",
                snapshotStatus = "ready",
                boundRoomId = "lr_room",
                hasLocalActiveWorkout = true
            )
        )
        assertFalse(
            isConfirmedLiveAcceptAuthoritativelyRestored(
                expectedRoomId = "lr_room",
                snapshotRoomId = "lr_room",
                snapshotStatus = "active",
                boundRoomId = null,
                hasLocalActiveWorkout = false
            )
        )
        assertTrue(
            isConfirmedLiveAcceptAuthoritativelyRestored(
                expectedRoomId = "lr_room",
                snapshotRoomId = "lr_room",
                snapshotStatus = "active",
                boundRoomId = "lr_room",
                hasLocalActiveWorkout = true
            )
        )
    }
}
