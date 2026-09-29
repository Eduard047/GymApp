package com.example.gymapp.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WordShrinkTextTest {
    @Test
    fun singleWordLabelsShrinkInsteadOfBreaking() {
        assertTrue(isSingleWordLabel("Упражнения"))
        assertTrue(isSingleWordLabel(" Тренировки "))
        assertFalse(isSingleWordLabel("Серия недель"))
        assertFalse(isSingleWordLabel("   "))
    }

    @Test
    fun shrinkScaleStopsAtTheFloor() {
        var scale = 1f
        repeat(20) { scale = nextWordShrinkScale(scale) }
        assertEquals(WORD_SHRINK_MIN_SCALE, scale, 0.0001f)
        assertTrue(nextWordShrinkScale(1f) < 1f)
    }
}
