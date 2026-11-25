package com.example.gymapp.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RestEndedNotificationRefreshTest {
    private val account = "a".repeat(64)
    private val otherAccount = "b".repeat(64)
    private val now = 100_000L
    private val startedAt = 1_000L

    private fun decide(
        currentAccountKey: String? = account,
        timerAccountKey: String? = account,
        timerSessionStartedAt: Long? = startedAt,
        timerRestEndsAt: Long? = now - 500L,
        activeWorkoutStartedAt: Long? = startedAt,
        endedRestDeadline: Long? = null
    ) = restEndedNotificationRefresh(
        currentAccountKey = currentAccountKey,
        timerAccountKey = timerAccountKey,
        timerSessionStartedAt = timerSessionStartedAt,
        timerRestEndsAt = timerRestEndsAt,
        activeWorkoutStartedAt = activeWorkoutStartedAt,
        nowMillis = now,
        endedRestDeadline = endedRestDeadline
    )

    private fun content(restEndsAt: Long?) = activeWorkoutNotificationContent(
        sessionStartedAt = startedAt,
        revision = 3L,
        exercises = listOf(
            WorkoutNotificationExercise(
                "Squat",
                listOf(
                    WorkoutNotificationSet("s1", 100.0, 5, completed = true),
                    WorkoutNotificationSet("s2", 100.0, 5, completed = false)
                )
            )
        ),
        restEndsAt = restEndsAt,
        nowMillis = now,
        isLiveWorkout = false
    )

    @Test
    fun endedRestRepostsTheNextSetWithoutACountdown() {
        assertEquals(RestEndedNotificationRefresh.Post(null), decide())
    }

    @Test
    fun deadlineOnlyAMomentAheadCountsAsEnded() {
        assertEquals(RestEndedNotificationRefresh.Post(null), decide(timerRestEndsAt = now + 800L))
    }

    @Test
    fun newerRestStillRunningKeepsItsCountdown() {
        assertEquals(RestEndedNotificationRefresh.Post(now + 60_000L), decide(timerRestEndsAt = now + 60_000L))
    }

    @Test
    fun restEndedByTheAlarmAfterTheClockMovedBackShowsTheNextSet() {
        // A 90 s rest scheduled before the clock moved back 1 h: the elapsed-realtime alarm fires
        // on time, while the stored wall-clock deadline still looks ~59 min ahead.
        val oneHour = 60L * 60L * 1_000L
        val scheduledDeadline = now + oneHour - 500L
        val refresh = decide(timerRestEndsAt = scheduledDeadline, endedRestDeadline = scheduledDeadline)
        assertEquals(RestEndedNotificationRefresh.Post(null), refresh)
        val posted = content((refresh as RestEndedNotificationRefresh.Post).restEndsAt)
        assertNull(posted.restEndsAt)
        assertEquals("s2", posted.nextSetId)
    }

    @Test
    fun serviceDeadlineAMomentOffTheWorkoutDeadlineIsTheSameRest() {
        val deadline = now + 3_600_000L
        assertEquals(
            RestEndedNotificationRefresh.Post(null),
            decide(timerRestEndsAt = deadline, endedRestDeadline = deadline - 1_200L)
        )
        assertEquals(
            RestEndedNotificationRefresh.Post(null),
            decide(timerRestEndsAt = deadline, endedRestDeadline = deadline + REST_ENDED_SAME_REST_TOLERANCE_MILLIS)
        )
    }

    @Test
    fun newerRestStartedAfterTheEndedOneKeepsItsCountdown() {
        assertEquals(
            RestEndedNotificationRefresh.Post(now + 60_000L),
            decide(timerRestEndsAt = now + 60_000L, endedRestDeadline = now - 200L)
        )
    }

    @Test
    fun normalRestEndWithItsDeadlineIsUnchanged() {
        assertEquals(RestEndedNotificationRefresh.Post(null), decide(endedRestDeadline = now - 500L))
        val posted = content(null)
        assertNull(posted.restEndsAt)
        assertEquals("s2", posted.nextSetId)
        val resting = content(now + 60_000L)
        assertEquals(now + 60_000L, resting.restEndsAt)
    }

    @Test
    fun restOfAnotherWorkoutIsNotShown() {
        assertEquals(
            RestEndedNotificationRefresh.Post(null),
            decide(timerSessionStartedAt = 2_000L, timerRestEndsAt = now + 60_000L)
        )
    }

    @Test
    fun noTimerStillRepostsTheWorkout() {
        assertEquals(
            RestEndedNotificationRefresh.Post(null),
            decide(timerAccountKey = null, timerSessionStartedAt = null, timerRestEndsAt = null)
        )
    }

    @Test
    fun noActiveWorkoutCancelsTheNotification() {
        assertEquals(RestEndedNotificationRefresh.Cancel, decide(activeWorkoutStartedAt = null))
        assertEquals(
            RestEndedNotificationRefresh.Cancel,
            decide(timerAccountKey = null, timerSessionStartedAt = null, timerRestEndsAt = null, activeWorkoutStartedAt = null)
        )
    }

    @Test
    fun signedOutOrSwitchedAccountDoesNothing() {
        assertEquals(RestEndedNotificationRefresh.Skip, decide(currentAccountKey = null))
        assertEquals(RestEndedNotificationRefresh.Skip, decide(timerAccountKey = otherAccount))
        assertEquals(RestEndedNotificationRefresh.Skip, decide(timerAccountKey = otherAccount, activeWorkoutStartedAt = null))
    }

    @Test
    fun repostedContentNeverCarriesAPastDeadline() {
        val content = activeWorkoutNotificationContent(
            sessionStartedAt = startedAt,
            revision = 3L,
            exercises = listOf(
                WorkoutNotificationExercise(
                    "Squat",
                    listOf(
                        WorkoutNotificationSet("s1", 100.0, 5, completed = true),
                        WorkoutNotificationSet("s2", 100.0, 5, completed = false)
                    )
                )
            ),
            restEndsAt = now - 1L,
            nowMillis = now,
            isLiveWorkout = false
        )
        assertNull(content.restEndsAt)
        assertEquals("s2", content.nextSetId)
    }
}
