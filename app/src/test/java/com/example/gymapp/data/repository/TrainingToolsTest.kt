package com.example.gymapp.data.repository

import org.junit.Assert.assertEquals
import org.junit.Test

class TrainingToolsTest {
    @Test
    fun stepWeightUsesConfiguredMachineStackAndStopsAtEdges() {
        val stack = listOf(5.0, 7.5, 10.0)
        assertEquals(7.5, TrainingTools.stepWeight(5.0, 1, stack), 0.0)
        assertEquals(7.5, TrainingTools.stepWeight(10.0, -1, stack), 0.0)
        assertEquals(10.0, TrainingTools.stepWeight(10.0, 1, stack), 0.0)
    }

    @Test
    fun stepWeightReturnsInputUnchangedForInvalidArguments() {
        assertEquals(20.0, TrainingTools.stepWeight(20.0, 0), 0.0)
        assertEquals(20.0, TrainingTools.stepWeight(20.0, 2), 0.0)
        assertEquals(-1.0, TrainingTools.stepWeight(-1.0, 1), 0.0)
        assertEquals(2_000_000.0, TrainingTools.stepWeight(2_000_000.0, -1), 0.0)
        assertEquals(true, TrainingTools.stepWeight(Double.NaN, 1).isNaN())
        assertEquals(20.0, TrainingTools.stepWeight(20.0, 1, listOf(10.0, 5.0)), 0.0)
        assertEquals(20.0, TrainingTools.stepWeight(20.0, 1, listOf(5.0, Double.NaN)), 0.0)
        assertEquals(20.0, TrainingTools.stepWeight(20.0, 1, List(129) { it.toDouble() }), 0.0)
    }

    @Test
    fun stepWeightUsesSafeDefaultIncrement() {
        assertEquals(22.5, TrainingTools.stepWeight(20.0, 1), 0.0)
        assertEquals(0.0, TrainingTools.stepWeight(0.0, -1), 0.0)
    }
}
