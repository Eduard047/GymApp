package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

class CompactDurationTest {
    private val uk = Locale("uk")
    private val ru = Locale("ru")

    @Test
    fun englishUsesAbbreviatedUnitsWithoutSpaceBeforeUnit() {
        assertEquals("4h 31m", DateTimeUtils.formatCompactDuration(16271, Locale.ENGLISH))
        assertEquals("1h", DateTimeUtils.formatCompactDuration(3600, Locale.ENGLISH))
        assertEquals("45m", DateTimeUtils.formatCompactDuration(2700, Locale.ENGLISH))
        assertEquals("2h 1m", DateTimeUtils.formatCompactDuration(7260, Locale.ENGLISH))
    }

    @Test
    fun ukrainianSeparatesNumberAndUnitWithNarrowNoBreakSpace() {
        assertEquals("4 г 31 хв", DateTimeUtils.formatCompactDuration(16271, uk))
        assertEquals("1 г", DateTimeUtils.formatCompactDuration(3600, uk))
        assertEquals("45 хв", DateTimeUtils.formatCompactDuration(2700, uk))
        assertEquals("2 г 1 хв", DateTimeUtils.formatCompactDuration(7260, uk))
    }

    @Test
    fun russianSeparatesNumberAndUnitWithPlainSpace() {
        assertEquals("4 ч 31 мин", DateTimeUtils.formatCompactDuration(16271, ru))
        assertEquals("1 ч", DateTimeUtils.formatCompactDuration(3600, ru))
        assertEquals("45 мин", DateTimeUtils.formatCompactDuration(2700, ru))
        assertEquals("2 ч 1 мин", DateTimeUtils.formatCompactDuration(7260, ru))
    }

    @Test
    fun nonPositiveDurationIsEmpty() {
        assertEquals("", DateTimeUtils.formatCompactDuration(0, Locale.ENGLISH))
        assertEquals("", DateTimeUtils.formatCompactDuration(-5, ru))
    }
}
