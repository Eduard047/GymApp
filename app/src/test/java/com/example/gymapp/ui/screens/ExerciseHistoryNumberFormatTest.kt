package com.example.gymapp.ui.screens

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class ExerciseHistoryNumberFormatTest {
    private val en = Locale.forLanguageTag("en")
    private val uk = Locale.forLanguageTag("uk")

    @Test
    fun setWeightKeepsTwoFractionDigitsInAppLocale() {
        assertEquals("22.25", formatProgressWeight(22.25, en))
        assertEquals("22,25", formatProgressWeight(22.25, uk))
        assertEquals("80", formatProgressWeight(80.0, en))
    }

    @Test
    fun volumeKeepsOneFractionDigitInAppLocale() {
        assertEquals("1,234.5", formatHistoryVolume(1234.5, en))
        assertEquals("1000", formatHistoryVolume(1000.0, en).replace(",", ""))
        val ukText = formatHistoryVolume(1234.5, uk)
        assertEquals("1,234.5".length, ukText.length)
        assertEquals(true, ukText.endsWith(",5"))
        assertEquals(true, ukText.startsWith("1") && ukText.contains("234"))
    }
}
