package com.example.gymapp.ui.media

import org.junit.Assert.assertEquals
import org.junit.Test

class ExerciseMediaStoreTest {
    @Test
    fun calculateInSampleSizeUsesLargestSafePowerOfTwo() {
        assertEquals(4, ExerciseMediaStore.calculateInSampleSize(4_096, 3_072, 800, 600))
        assertEquals(2, ExerciseMediaStore.calculateInSampleSize(1_024, 768, 320, 240))
    }

    @Test
    fun calculateInSampleSizeKeepsSmallOrInvalidImagesAtFullResolution() {
        assertEquals(1, ExerciseMediaStore.calculateInSampleSize(480, 320, 800, 600))
        assertEquals(1, ExerciseMediaStore.calculateInSampleSize(0, 320, 800, 600))
        assertEquals(1, ExerciseMediaStore.calculateInSampleSize(480, 320, 0, 600))
    }
}
