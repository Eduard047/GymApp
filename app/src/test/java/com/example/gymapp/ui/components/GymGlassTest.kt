package com.example.gymapp.ui.components

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GymGlassTest {
    @Test
    fun blurNeedsApi31AndTransparencyNotReduced() {
        assertFalse(gymGlassBlurEnabled(sdkInt = 24, reduceTransparency = false))
        assertFalse(gymGlassBlurEnabled(sdkInt = 30, reduceTransparency = false))
        assertTrue(gymGlassBlurEnabled(sdkInt = 31, reduceTransparency = false))
        assertTrue(gymGlassBlurEnabled(sdkInt = 36, reduceTransparency = false))
        assertFalse(gymGlassBlurEnabled(sdkInt = 31, reduceTransparency = true))
        assertFalse(gymGlassBlurEnabled(sdkInt = 36, reduceTransparency = true))
    }

    @Test
    fun materialsMatchDesignTokens() {
        val barLight = gymGlassSpec(GymGlassMaterial.Bar, isDark = false)
        assertEquals(20f, barLight.blurRadius.value, 0f)
        assertEquals(0.80f, barLight.fillAlpha, 0f)
        assertTrue(barLight.fillFromBackground)

        val barDark = gymGlassSpec(GymGlassMaterial.Bar, isDark = true)
        assertEquals(0.78f, barDark.fillAlpha, 0f)
        assertFalse(barDark.fillFromBackground)

        val sheetLight = gymGlassSpec(GymGlassMaterial.Sheet, isDark = false)
        val sheetDark = gymGlassSpec(GymGlassMaterial.Sheet, isDark = true)
        assertEquals(28f, sheetLight.blurRadius.value, 0f)
        assertEquals(0.86f, sheetLight.fillAlpha, 0f)
        assertEquals(0.84f, sheetDark.fillAlpha, 0f)
        assertFalse(sheetLight.fillFromBackground)

        val chipLight = gymGlassSpec(GymGlassMaterial.Chip, isDark = false)
        val chipDark = gymGlassSpec(GymGlassMaterial.Chip, isDark = true)
        assertEquals(14f, chipLight.blurRadius.value, 0f)
        assertEquals(0.70f, chipLight.fillAlpha, 0f)
        assertEquals(0.66f, chipDark.fillAlpha, 0f)
        assertFalse(chipLight.fillFromBackground)
    }

    @Test
    fun fillBaseFollowsTheMaterial() {
        val background = Color(0xFFF4F7FB)
        val surface = Color(0xFFFFFFFF)
        assertEquals(
            background,
            gymGlassFillBase(gymGlassSpec(GymGlassMaterial.Bar, isDark = false), background, surface)
        )
        assertEquals(
            surface,
            gymGlassFillBase(gymGlassSpec(GymGlassMaterial.Chip, isDark = false), background, surface)
        )
        assertEquals(
            surface,
            gymGlassFillBase(gymGlassSpec(GymGlassMaterial.Bar, isDark = true), background, surface)
        )
    }
}
