package com.example.gymapp.ui.viewmodel

import com.example.gymapp.auth.LiveRealtimeEvent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveWorkoutPollingPolicyTest {
    @Test
    fun canonicalRefreshWaitsForPrivateChannelReadiness() {
        assertTrue(
            shouldCanonicalRefreshLiveWorkout(LiveRealtimeEvent.ChannelReady)
        )
        assertFalse(
            shouldCanonicalRefreshLiveWorkout(LiveRealtimeEvent.Connection(connected = true))
        )
        assertFalse(
            shouldCanonicalRefreshLiveWorkout(LiveRealtimeEvent.Connection(connected = false))
        )
    }

    @Test
    fun healthyRealtimeIdleAccountUsesBoundedCatchUpPolling() {
        assertFalse(
            shouldPollLiveWorkout(
                realtimeConnected = true,
                state = LiveWorkoutUiState(isCloudAccount = true),
                idleRealtimeCycles = 1
            )
        )
        assertFalse(
            shouldPollLiveWorkout(
                realtimeConnected = true,
                state = LiveWorkoutUiState(isCloudAccount = true),
                idleRealtimeCycles = LIVE_WORKOUT_IDLE_REALTIME_CATCH_UP_CYCLES - 1
            )
        )
        assertTrue(
            shouldPollLiveWorkout(
                realtimeConnected = true,
                state = LiveWorkoutUiState(isCloudAccount = true),
                idleRealtimeCycles = LIVE_WORKOUT_IDLE_REALTIME_CATCH_UP_CYCLES
            )
        )
    }

    @Test
    fun pollingRemainsEnabledForFallbackAndRecoveryStates() {
        assertTrue(
            shouldPollLiveWorkout(
                realtimeConnected = false,
                state = LiveWorkoutUiState(isCloudAccount = true),
                idleRealtimeCycles = 1
            )
        )
        assertTrue(
            shouldPollLiveWorkout(
                realtimeConnected = true,
                state = LiveWorkoutUiState(activeRoomId = "room-a"),
                idleRealtimeCycles = 1
            )
        )
        assertTrue(
            shouldPollLiveWorkout(
                realtimeConnected = true,
                state = LiveWorkoutUiState(pendingOperationCount = 1),
                idleRealtimeCycles = 1
            )
        )
        assertTrue(
            shouldPollLiveWorkout(
                realtimeConnected = true,
                state = LiveWorkoutUiState(confirmedRestoringRoomId = "room-a"),
                idleRealtimeCycles = 1
            )
        )
    }
}
