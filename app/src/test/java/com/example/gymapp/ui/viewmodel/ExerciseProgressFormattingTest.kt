package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.MuscleContribution
import com.example.gymapp.data.repository.defaultContributionsForExercise
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class ExerciseProgressFormattingTest {
    @Test
    fun manualMappingOverridesDefaultMuscles() {
        val name = "Bench Press"
        val default = progressMuscleIntensities(name, emptyMap())
        assertEquals(
            defaultContributionsForExercise(name).associate { it.muscleId to it.weight.toFloat() },
            default
        )

        val defaultIds = default.keys
        val customId = listOf("biceps", "calves", "abs", "glutes").first { it !in defaultIds }
        val manual = mapOf(
            "bench press" to listOf(MuscleContribution(muscleId = customId, weight = 0.4))
        )
        val result = progressMuscleIntensities(name, manual)
        assertEquals(mapOf(customId to 0.4f), result)
        assertNotEquals(default, result)
    }

    @Test
    fun emptyManualMappingFallsBackToDefaultAndNoExerciseIsEmpty() {
        val name = "Bench Press"
        val default = progressMuscleIntensities(name, emptyMap())
        assertTrue(default.isNotEmpty())
        assertEquals(default, progressMuscleIntensities(name, mapOf("bench press" to emptyList())))
        assertTrue(progressMuscleIntensities(null, emptyMap()).isEmpty())
    }

    @Test
    fun weightLabelTrimsTrailingZeroAndKeepsOneFractionDigit() {
        assertEquals("100 kg", formatProgressWeightLabel(100.0, Locale.US, "kg"))
        assertEquals("102.5 kg", formatProgressWeightLabel(102.5, Locale.US, "kg"))
        assertEquals("102,5 кг", formatProgressWeightLabel(102.5, Locale("uk"), "кг"))
    }

    @Test
    fun nextMonthNeverGoesPastTheCurrentMonth() {
        assertEquals(0, nextProgressMonthOffset(0))
        assertEquals(0, nextProgressMonthOffset(-1))
        assertEquals(-2, nextProgressMonthOffset(-3))
    }
}
