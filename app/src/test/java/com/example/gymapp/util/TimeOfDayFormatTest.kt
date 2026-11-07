package com.example.gymapp.util

import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TimeOfDayFormatTest {
    private val afternoon = Instant.parse("2026-08-24T14:05:09Z").toEpochMilli()
    private val locales = listOf(Locale.forLanguageTag("en"), Locale.forLanguageTag("uk"), Locale.forLanguageTag("ru"))

    private fun clean(text: String) = text.replace(' ', ' ').replace(' ', ' ')

    @Test
    fun twentyFourHourFlagWinsInEveryAppLanguage() {
        locales.forEach { locale ->
            assertEquals(
                locale.toString(),
                "14:05",
                TimeOfDayFormat.formatTime(afternoon, locale, true, ZoneOffset.UTC)
            )
        }
        assertEquals(
            "14:05:09",
            TimeOfDayFormat.formatTime(afternoon, locales[0], true, ZoneOffset.UTC, withSeconds = true)
        )
    }

    @Test
    fun twelveHourFlagWinsInEveryAppLanguage() {
        locales.forEach { locale ->
            val text = clean(TimeOfDayFormat.formatTime(afternoon, locale, false, ZoneOffset.UTC))
            assertTrue("$locale: $text", text.startsWith("2:05 "))
            assertFalse("$locale: $text", text.contains("14"))
        }
        assertEquals(
            "2:05 PM",
            clean(TimeOfDayFormat.formatTime(afternoon, locales[0], false, ZoneOffset.UTC))
        )
    }

    @Test
    fun dateTimeUsesAppLocaleWordsAndSystemClock() {
        val en = clean(TimeOfDayFormat.formatDateTime(afternoon, locales[0], true, ZoneOffset.UTC))
        assertTrue(en, en.contains("Aug") && en.endsWith(", 14:05"))
        val uk = clean(TimeOfDayFormat.formatDateTime(afternoon, locales[1], false, ZoneOffset.UTC))
        assertTrue(uk, uk.contains("серп") && uk.contains(", 2:05 "))
    }
}
