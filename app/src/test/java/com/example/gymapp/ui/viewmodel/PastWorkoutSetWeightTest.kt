package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Test

class PastWorkoutSetWeightTest {
    @Test
    fun noBlockSetAndNoHistoryStartsAtZero() {
        assertEquals(0.0, pastWorkoutSetWeight(templateWeight = null, historicalWeight = null), 0.0)
    }

    @Test
    fun historyWeightIsUsedWhenTheBlockHasNoSets() {
        assertEquals(62.5, pastWorkoutSetWeight(templateWeight = null, historicalWeight = 62.5), 0.0)
    }

    @Test
    fun addingToANonEmptyBlockCopiesTheLastSetEvenWithHistory() {
        assertEquals(40.0, pastWorkoutSetWeight(templateWeight = 40.0, historicalWeight = 62.5), 0.0)
        assertEquals(0.0, pastWorkoutSetWeight(templateWeight = 0.0, historicalWeight = 62.5), 0.0)
    }
}
