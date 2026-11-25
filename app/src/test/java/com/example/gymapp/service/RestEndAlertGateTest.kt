package com.example.gymapp.service

import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestEndAlertGateTest {
    @Test
    fun switchOnPostsTheFinishedAlertOncePerRest() {
        val posted = AtomicBoolean(false)
        assertTrue(RestTimerService.shouldPostFinishedAlert(posted, alertEnabled = true))
        // The backstop alarm (or the countdown) arriving second never posts it again.
        assertFalse(RestTimerService.shouldPostFinishedAlert(posted, alertEnabled = true))
    }

    @Test
    fun switchOffPostsNothingButStillClaimsTheRestEnd() {
        val posted = AtomicBoolean(false)
        assertFalse(RestTimerService.shouldPostFinishedAlert(posted, alertEnabled = false))
        // Claimed: the countdown stops at the alarm, and a late caller cannot post it either.
        assertTrue(posted.get())
        assertFalse(RestTimerService.shouldPostFinishedAlert(posted, alertEnabled = true))
    }

    @Test
    fun ongoingWorkoutNotificationRefreshDoesNotDependOnTheAlertSwitch() {
        // The refresh after a rest is decided only by account/session/deadline; the switch is not an input.
        val account = "a".repeat(64)
        val refresh = restEndedNotificationRefresh(
            currentAccountKey = account,
            timerAccountKey = account,
            timerSessionStartedAt = 1_000L,
            timerRestEndsAt = 99_500L,
            activeWorkoutStartedAt = 1_000L,
            nowMillis = 100_000L,
            endedRestDeadline = null
        )
        assertTrue(refresh != RestEndedNotificationRefresh.Skip)
        assertTrue(refresh != RestEndedNotificationRefresh.Cancel)
    }
}
