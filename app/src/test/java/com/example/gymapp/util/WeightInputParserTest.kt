package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WeightInputParserTest {
    @Test
    fun parserAcceptsLocalizedFiniteWeights() {
        assertEquals(0.0, parseWeightInputOrNull(""))
        assertEquals(82.5, parseWeightInputOrNull(" 82,5 "))
    }

    @Test
    fun parserRejectsNonFiniteNumbers() {
        assertNull(parseWeightInputOrNull("NaN"))
        assertNull(parseWeightInputOrNull("Infinity"))
        assertNull(parseWeightInputOrNull("-Infinity"))
        assertNull(parseWeightInputOrNull("1".repeat(65)))
    }
}
