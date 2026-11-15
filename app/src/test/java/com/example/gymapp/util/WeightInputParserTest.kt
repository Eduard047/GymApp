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

    @Test
    fun leadingZerosBeforeADigitAreStripped() {
        assertEquals("6", normalizeWeightInput("006"))
        assertEquals("60", normalizeWeightInput("0060"))
        assertEquals("60", normalizeWeightInput("060"))
        assertEquals("0.5", normalizeWeightInput("00.5"))
        assertEquals("0,5", normalizeWeightInput("00,5"))
        assertEquals("100", normalizeWeightInput("0100"))
    }

    @Test
    fun zeroAndDecimalsAreKept() {
        assertEquals("0", normalizeWeightInput("0"))
        assertEquals("0", normalizeWeightInput("00"))
        assertEquals("", normalizeWeightInput(""))
        assertEquals("0.5", normalizeWeightInput("0.5"))
        assertEquals("0,5", normalizeWeightInput("0,5"))
        assertEquals("60", normalizeWeightInput("60"))
        assertEquals("100.5", normalizeWeightInput("100.5"))
        assertEquals("60.", normalizeWeightInput("60."))
    }

    @Test
    fun typingOverASelectedZeroGivesTheTypedValue() {
        // "0" fully selected, then "6" then "0": the field never shows "006".
        assertEquals(NormalizedWeightEdit("6", 1, 1), normalizeWeightEdit("6", 1, 1))
        assertEquals(NormalizedWeightEdit("60", 2, 2), normalizeWeightEdit("60", 2, 2))
    }

    @Test
    fun typingAtTheEndOfAZeroWithoutSelectionDropsTheZeros() {
        // Caret after "0", the user types "60": "060" then caret moves with the dropped zero.
        assertEquals(NormalizedWeightEdit("60", 2, 2), normalizeWeightEdit("060", 3, 3))
        assertEquals(NormalizedWeightEdit("6", 1, 1), normalizeWeightEdit("006", 3, 3))
        assertEquals(NormalizedWeightEdit("0.5", 3, 3), normalizeWeightEdit("00.5", 4, 4))
    }

    @Test
    fun selectionNeverEscapesTheNormalizedText() {
        assertEquals(NormalizedWeightEdit("6", 0, 1), normalizeWeightEdit("006", 0, 3))
        assertEquals(NormalizedWeightEdit("5", 0, 0), normalizeWeightEdit("005", 1, 1))
    }
}
