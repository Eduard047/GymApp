package com.example.gymapp.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WorkoutComparisonCardTest {
    @Test
    fun deltaRangeCoversTheSignedDeltaAtTheEndOfTheLine() {
        val line = "Previous 3 · +2"
        val range = comparisonDeltaRange(line, "+2")
        assertEquals("+2", line.substring(range!!.first, range.last + 1))
    }

    @Test
    fun deltaRangeFindsTheLastMatchWhenThePreviousValueRepeatsIt() {
        val line = "Раніше 850 кг · +850 кг"
        val range = comparisonDeltaRange(line, "+850 кг")
        assertEquals(line.length - 7, range!!.first)
        assertEquals(line.length - 1, range.last)
    }

    @Test
    fun deltaRangeCoversTheNoChangeWordAndMinusSign() {
        val noChange = "Previous 3 · no change"
        assertEquals(
            "no change",
            comparisonDeltaRange(noChange, "no change")!!.let { noChange.substring(it.first, it.last + 1) }
        )
        val drop = "Previous 5 · −2"
        assertEquals(
            "−2",
            comparisonDeltaRange(drop, "−2")!!.let { drop.substring(it.first, it.last + 1) }
        )
    }

    @Test
    fun deltaRangeIsNullWhenTheDeltaIsMissing() {
        assertNull(comparisonDeltaRange("Previous 3", "+2"))
        assertNull(comparisonDeltaRange("Previous 3", ""))
    }
}
