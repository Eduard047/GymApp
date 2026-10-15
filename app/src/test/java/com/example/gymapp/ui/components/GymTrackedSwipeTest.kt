package com.example.gymapp.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GymTrackedSwipeTest {
    private val width = 400f
    private val density = 2f

    private fun result(offset: Float, velocity: Float = 0f, previous: Boolean = true, next: Boolean = true) =
        trackedSwipeResult(offset, velocity, width, previous, next, density)

    @Test
    fun shortSlowDragStays() {
        assertEquals(TrackedSwipeResult.Stay, result(offset = 100f))
        assertEquals(TrackedSwipeResult.Stay, result(offset = -100f))
    }

    @Test
    fun dragPastFortyPercentCommitsInTheDragDirection() {
        assertEquals(TrackedSwipeResult.Previous, result(offset = 161f))
        assertEquals(TrackedSwipeResult.Next, result(offset = -161f))
    }

    @Test
    fun fastReleaseCommitsEvenWhenShort() {
        // 500 dp/s at density 2 is 1000 px/s.
        assertEquals(TrackedSwipeResult.Previous, result(offset = 40f, velocity = 1_000f))
        assertEquals(TrackedSwipeResult.Next, result(offset = -40f, velocity = -1_000f))
        assertEquals(TrackedSwipeResult.Stay, result(offset = 40f, velocity = 999f))
    }

    @Test
    fun flingAgainstTheDragDoesNotCommit() {
        assertEquals(TrackedSwipeResult.Stay, result(offset = 40f, velocity = -2_000f))
    }

    @Test
    fun blockedDirectionNeverCommits() {
        assertEquals(TrackedSwipeResult.Stay, result(offset = -300f, velocity = -3_000f, next = false))
        assertEquals(TrackedSwipeResult.Stay, result(offset = 300f, previous = false))
    }

    @Test
    fun noTravelOrNoWidthStays() {
        assertEquals(TrackedSwipeResult.Stay, result(offset = 0f, velocity = 5_000f))
        assertEquals(TrackedSwipeResult.Stay, trackedSwipeResult(100f, 5_000f, 0f, true, true, density))
    }

    @Test
    fun rubberBandResistsAndNeverPassesItsLimit() {
        val limit = 100f
        val small = trackedSwipeRubberBand(50f, limit)
        val large = trackedSwipeRubberBand(5_000f, limit)
        assertTrue(small in 0f..50f)
        assertTrue(large < limit)
        assertTrue(large > small)
        assertEquals(-small, trackedSwipeRubberBand(-50f, limit), 0.0001f)
        assertEquals(0f, trackedSwipeRubberBand(0f, limit), 0f)
    }

    @Test
    fun displayOffsetFollowsTheFingerOnlyWhereTheSwipeCanCommit() {
        assertEquals(120f, trackedSwipeDisplayOffset(120f, width, canPrevious = true, canNext = false), 0f)
        val resisted = trackedSwipeDisplayOffset(-120f, width, canPrevious = true, canNext = false)
        assertTrue(resisted > -120f && resisted < 0f)
        assertEquals(width, trackedSwipeDisplayOffset(900f, width, canPrevious = true, canNext = true), 0f)
    }
}
