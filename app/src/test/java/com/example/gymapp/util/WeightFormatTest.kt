package com.example.gymapp.util

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class WeightFormatTest {
    private val en = Locale.forLanguageTag("en")
    private val uk = Locale.forLanguageTag("uk")

    @Test
    fun volumeKeepsOneFractionDigit() {
        assertEquals("112.5", formatVolumeTotal(112.5, en))
        assertEquals("1,000", formatVolumeTotal(1000.0, en))
        assertEquals("0", formatVolumeTotal(0.0, en))
        assertEquals("112,5", formatVolumeTotal(112.5, uk))
    }

    @Test
    fun weightInputKeepsTwoDecimalsWithDotSeparator() {
        assertEquals("21.25", formatWeightInput(21.25))
        assertEquals("1.25", formatWeightInput(1.25))
        assertEquals("62.5", formatWeightInput(62.5))
        assertEquals("60", formatWeightInput(60.0))
        assertEquals("0", formatWeightInput(-0.0))
        assertEquals("1500.5", formatWeightInput(1500.5))
    }

    @Test
    fun weightDisplayUsesLocaleSeparator() {
        assertEquals("21,25", formatWeightDisplay(21.25, uk))
        assertEquals("21.25", formatWeightDisplay(21.25, en))
        assertEquals("160", formatWeightDisplay(160.0, en))
    }
}
