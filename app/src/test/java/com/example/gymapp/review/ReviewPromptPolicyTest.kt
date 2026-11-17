package com.example.gymapp.review

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReviewPromptPolicyTest {
    private val day = 24L * 60L * 60L * 1000L
    private val now = 1_800_000_000_000L

    private fun eligible(
        savedWorkoutCount: Int = 1,
        loggedSets: Int = 1,
        last: Long? = null,
        count: Int = 0,
        isDemo: Boolean = false
    ) = ReviewPromptPolicy.isEligible(
        savedWorkoutCount = savedWorkoutCount,
        loggedSetsInWorkout = loggedSets,
        lastRequestAtMillis = last,
        requestCount = count,
        nowMillis = now,
        isDemo = isDemo
    )

    @Test
    fun constantsMatchApprovedRule() {
        assertEquals(90, ReviewPromptPolicy.MIN_DAYS_BETWEEN_REQUESTS)
        assertEquals(3, ReviewPromptPolicy.MAX_REQUESTS)
        assertEquals(1, ReviewPromptPolicy.MIN_LOGGED_SETS)
    }

    @Test
    fun firstWorkoutIsEligible() = assertTrue(eligible())

    @Test
    fun zeroLoggedSetsIsNotEligible() = assertFalse(eligible(loggedSets = 0))

    @Test
    fun zeroSavedWorkoutsIsNotEligible() = assertFalse(eligible(savedWorkoutCount = 0))

    @Test
    fun eightyNineDaysAfterLastRequestIsNotEligible() =
        assertFalse(eligible(last = now - 89 * day, count = 1))

    @Test
    fun ninetyDaysAfterLastRequestIsEligible() =
        assertTrue(eligible(last = now - 90 * day, count = 1))

    @Test
    fun thirdRequestWasTheLastAllowed() {
        assertTrue(eligible(last = now - 200 * day, count = 2))
        assertFalse(eligible(last = now - 200 * day, count = 3))
    }

    @Test
    fun demoIsNotEligible() = assertFalse(eligible(isDemo = true))

    @Test
    fun clockMovedBackwardsIsNotEligible() =
        assertFalse(eligible(last = now + day, count = 1))
}
