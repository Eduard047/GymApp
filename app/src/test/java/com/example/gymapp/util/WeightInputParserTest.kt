package com.example.gymapp.util

import com.example.gymapp.data.repository.WorkoutDataLimits
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WeightInputParserTest {
    @Test
    fun parserAcceptsLocalizedFiniteWeights() {
        assertEquals(0.0, parseWeightInputOrNull("0"))
        assertEquals(82.5, parseWeightInputOrNull(" 82,5 "))
    }

    @Test
    fun parserRejectsNonFiniteNumbers() {
        assertNull(parseWeightInputOrNull(""))
        assertNull(parseWeightInputOrNull("   "))
        assertNull(parseWeightInputOrNull("NaN"))
        assertNull(parseWeightInputOrNull("Infinity"))
        assertNull(parseWeightInputOrNull("-Infinity"))
        assertNull(parseWeightInputOrNull("-0.01"))
        assertNull(parseWeightInputOrNull((WorkoutDataLimits.MAX_WEIGHT + 0.01).toString()))
        assertNull(parseWeightInputOrNull("1".repeat(65)))
    }

    @Test
    fun blankOrInvalidFieldRevertsToPreviousValue() {
        assertEquals("80", resolveWeightFieldCommit("", "80"))
        assertEquals("80", resolveWeightFieldCommit("   ", "80"))
        assertEquals("80", resolveWeightFieldCommit("2.5.0", "80"))
        assertEquals("", resolveWeightFieldCommit("", null))
    }

    @Test
    fun explicitZeroAndDecimalsAreKept() {
        assertEquals("0", resolveWeightFieldCommit("0", "80"))
        assertEquals("12,5", resolveWeightFieldCommit("12,5", "80"))
        assertEquals(0.0, parseWeightInputOrNull(resolveWeightFieldCommit("0", "80")))
        assertEquals(12.5, parseWeightInputOrNull(resolveWeightFieldCommit("12,5", "80")))
    }
}
