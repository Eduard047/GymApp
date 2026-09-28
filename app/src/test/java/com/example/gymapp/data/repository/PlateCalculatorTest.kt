package com.example.gymapp.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlateCalculatorTest {
    @Test
    fun loadsTheHeaviestPlatesFirstOnEachSide() {
        assertEquals(PlateLoad(PlateLoad.Status.Loaded, listOf(25.0, 5.0, 1.25), 0.0), PlateCalculator.load(82.5))
    }

    @Test
    fun commonTotals() {
        assertEquals(listOf(25.0, 15.0), PlateCalculator.load(100.0).platesPerSide)
        assertEquals(listOf(25.0, 25.0, 10.0), PlateCalculator.load(140.0).platesPerSide)
        assertEquals(listOf(1.25), PlateCalculator.load(22.5).platesPerSide)
        assertEquals(listOf(2.5), PlateCalculator.load(25.0).platesPerSide)
    }

    @Test
    fun emptyBarAndLighterTotals() {
        assertEquals(PlateLoad(PlateLoad.Status.BarOnly, emptyList(), 0.0), PlateCalculator.load(20.0))
        assertEquals(PlateLoad.Status.BelowBar, PlateCalculator.load(15.0).status)
        assertEquals(PlateLoad.Status.BelowBar, PlateCalculator.load(0.0).status)
        assertEquals(PlateLoad.Status.BelowBar, PlateCalculator.load(Double.NaN).status)
    }

    @Test
    fun reportsWhatThePlatesCannotMakeUp() {
        val load = PlateCalculator.load(83.0)
        assertEquals(listOf(25.0, 5.0, 1.25), load.platesPerSide)
        assertEquals(0.25, load.remainderPerSide, 1e-9)

        val tooSmall = PlateCalculator.load(21.0)
        assertEquals(PlateLoad.Status.Loaded, tooSmall.status)
        assertEquals(emptyList<Double>(), tooSmall.platesPerSide)
        assertEquals(0.5, tooSmall.remainderPerSide, 1e-9)
    }

    @Test
    fun onlyBarbellExercisesUseTheCalculator() {
        assertTrue(PlateCalculator.applies("bench_press"))
        assertTrue(PlateCalculator.applies("squat"))
        assertFalse(PlateCalculator.applies("dumbbell_bench_press"))
        assertFalse(PlateCalculator.applies("push_up"))
        assertFalse(PlateCalculator.applies(null))
    }
}
