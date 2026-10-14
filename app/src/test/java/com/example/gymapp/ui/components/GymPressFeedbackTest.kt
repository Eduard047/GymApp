package com.example.gymapp.ui.components

import android.view.HapticFeedbackConstants
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GymPressFeedbackTest {
    @Test
    fun holdRepeatFirstStepComesAfterThe350MsDelay() {
        assertEquals(350.0, StepperHoldRepeat.nextStepAtMs(null), 0.0)
        assertTrue(StepperHoldRepeat.stepTimesMs(349.0).isEmpty())
        assertEquals(listOf(350.0), StepperHoldRepeat.stepTimesMs(350.0))
        assertEquals(listOf(350.0), StepperHoldRepeat.stepTimesMs(474.0))
    }

    @Test
    fun holdRepeatRunsAtEightStepsPerSecondUntilTheAccelerationPoint() {
        val times = StepperHoldRepeat.stepTimesMs(1500.0)

        assertEquals(10, times.size)
        assertEquals(350.0, times.first(), 0.0)
        assertEquals(1475.0, times.last(), 0.0)
        times.zipWithNext().forEach { (a, b) -> assertEquals(125.0, b - a, 0.0) }
    }

    @Test
    fun holdRepeatAcceleratesToSixteenStepsPerSecondAfterOneAndAHalfSeconds() {
        val times = StepperHoldRepeat.stepTimesMs(2500.0)
        val afterAcceleration = times.filter { it > 1500.0 }

        assertEquals(1537.5, afterAcceleration.first(), 0.0)
        afterAcceleration.zipWithNext().forEach { (a, b) -> assertEquals(62.5, b - a, 0.0) }
        // One second at 16 steps per second.
        assertEquals(16, times.count { it > 1500.0 && it <= 2500.0 })
    }

    @Test
    fun holdRepeatStepsNeverComeFasterThanSixteenPerSecond() {
        StepperHoldRepeat.stepTimesMs(10_000.0).zipWithNext().forEach { (a, b) ->
            assertTrue(b - a >= StepperHoldRepeat.FAST_INTERVAL_MS)
        }
    }

    @Test
    fun stepperThrottleAllowsAtMostTenTicksPerSecond() {
        val throttle = HapticThrottle()

        assertTrue(throttle.tryAcquire(1_000L))
        assertFalse(throttle.tryAcquire(1_099L))
        assertTrue(throttle.tryAcquire(1_100L))
        // 16 steps per second (every 62.5 ms for one second) get at most 10 ticks.
        val throttled = HapticThrottle()
        val ticks = (0 until 16).count { throttled.tryAcquire((it * 62.5).toLong()) }
        assertTrue(ticks <= 10)
    }

    @Test
    fun hapticConstantsFollowTheDesignSpecPerApiLevel() {
        assertEquals(HapticFeedbackConstants.CONFIRM, gymHapticConstant(GymHapticEvent.RecordSet, 30))
        assertEquals(HapticFeedbackConstants.VIRTUAL_KEY, gymHapticConstant(GymHapticEvent.RecordSet, 29))
        assertEquals(HapticFeedbackConstants.CONTEXT_CLICK, gymHapticConstant(GymHapticEvent.Undo, 24))
        assertEquals(HapticFeedbackConstants.SEGMENT_TICK, gymHapticConstant(GymHapticEvent.StepperTick, 34))
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, gymHapticConstant(GymHapticEvent.StepperTick, 33))
        assertEquals(HapticFeedbackConstants.SEGMENT_FREQUENT_TICK, gymHapticConstant(GymHapticEvent.StepperRepeatTick, 34))
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, gymHapticConstant(GymHapticEvent.StepperRepeatTick, 33))
        assertEquals(HapticFeedbackConstants.SEGMENT_TICK, gymHapticConstant(GymHapticEvent.Reorder, 34))
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, gymHapticConstant(GymHapticEvent.Reorder, 33))
        assertEquals(HapticFeedbackConstants.LONG_PRESS, gymHapticConstant(GymHapticEvent.DestructiveConfirm, 36))
        assertEquals(HapticFeedbackConstants.REJECT, gymHapticConstant(GymHapticEvent.Error, 30))
        assertEquals(HapticFeedbackConstants.LONG_PRESS, gymHapticConstant(GymHapticEvent.Error, 29))
        assertEquals(HapticFeedbackConstants.CONFIRM, gymHapticConstant(GymHapticEvent.RestEnd, 30))
        assertEquals(HapticFeedbackConstants.LONG_PRESS, gymHapticConstant(GymHapticEvent.RestEnd, 29))
    }
}
