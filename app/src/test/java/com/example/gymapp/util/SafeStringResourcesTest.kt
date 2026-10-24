package com.example.gymapp.util

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class SafeStringResourcesTest {
    private val english = Locale.ENGLISH

    @Test
    fun validLocalizedTemplateIsFormattedAndDefaultIsNotLoaded() {
        val result = formatWithFallback("Сегодня: %1\$s", english, arrayOf("План")) {
            error("default template must not be loaded")
        }

        assertEquals("Сегодня: План", result)
    }

    @Test
    fun brokenConversionFallsBackToDefaultTemplate() {
        // A machine translation turned %1$s into %1$d: formatting a String with it throws.
        val result = formatWithFallback("Лог %1\$d", english, arrayOf("5 x 80")) { "Log %1\$s" }

        assertEquals("Log 5 x 80", result)
    }

    @Test
    fun missingArgumentFallsBackToDefaultTemplate() {
        val result = formatWithFallback("%1\$s и %2\$s", english, arrayOf("one")) { "%1\$s" }

        assertEquals("one", result)
    }

    @Test
    fun unknownConversionFallsBackToDefaultTemplate() {
        val result = formatWithFallback("Прогресс 100%", english, arrayOf(3)) { "%1\$d done" }

        assertEquals("3 done", result)
    }

    @Test
    fun brokenDefaultTemplateReturnsUnformattedLocalizedTemplate() {
        val result = formatWithFallback("Лог %1\$d", english, arrayOf("x")) { "Log %1\$d" }

        assertEquals("Лог %1\$d", result)
    }

    @Test
    fun unavailableDefaultTemplateReturnsUnformattedLocalizedTemplate() {
        val result = formatWithFallback("Лог %1\$d", english, arrayOf("x")) { null }
        val thrown = formatWithFallback("Лог %1\$d", english, arrayOf("x")) { error("no resources") }

        assertEquals("Лог %1\$d", result)
        assertEquals("Лог %1\$d", thrown)
    }

    @Test
    fun fallbackFormatsNumbersWithTheCurrentLocale() {
        val result = formatWithFallback("%1\$d", Locale.GERMANY, arrayOf(1234.5)) { "%1\$,.1f" }

        assertEquals("1.234,5", result)
    }
}
