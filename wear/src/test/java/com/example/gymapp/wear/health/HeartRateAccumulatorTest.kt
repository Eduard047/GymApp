package com.example.gymapp.wear.health

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeartRateAccumulatorTest {
    @Test
    fun tracksCurrentAverageAndMax() {
        val hr = HeartRateAccumulator()
        assertNull(hr.summary())
        listOf(100.0, 120.0, 140.0).forEach { assertTrue(hr.add(it)) }
        assertEquals(140, hr.current)
        assertEquals(HeartRateSummary(average = 120, max = 140), hr.summary())
        hr.add(110.0)
        assertEquals(110, hr.current)
        assertEquals(140, hr.max)
        assertEquals(118, hr.average) // 470 / 4 = 117.5, rounded
    }

    @Test
    fun ignoresImplausibleOrNonFiniteSamples() {
        val hr = HeartRateAccumulator()
        listOf(0.0, 24.4, 240.6, 300.0, -5.0, Double.NaN, Double.POSITIVE_INFINITY).forEach {
            assertFalse("$it", hr.add(it))
        }
        assertNull(hr.summary())
        assertNull(hr.current)
        assertTrue(hr.add(25.0))
        assertTrue(hr.add(240.0))
        assertEquals(2, hr.sampleCount)
        assertEquals(HeartRateSummary(average = 133, max = 240), hr.summary())
    }

    @Test
    fun averageNeverExceedsMax() {
        val hr = HeartRateAccumulator()
        repeat(7) { hr.add(99.6) }
        val summary = hr.summary()!!
        assertTrue(summary.average <= summary.max)
    }
}
