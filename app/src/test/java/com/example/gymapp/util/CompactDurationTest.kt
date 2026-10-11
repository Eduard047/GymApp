package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Locale

class CompactDurationTest {
    private val uk = Locale("uk")
    private val ru = Locale("ru")

    @Test
    fun englishUsesHourAndMinuteWords() {
        assertEquals("4 h 31 min", DateTimeUtils.formatCompactDuration(16271, Locale.ENGLISH))
        assertEquals("1 h", DateTimeUtils.formatCompactDuration(3600, Locale.ENGLISH))
        assertEquals("45 min", DateTimeUtils.formatCompactDuration(2700, Locale.ENGLISH))
        assertEquals("2 h 1 min", DateTimeUtils.formatCompactDuration(7260, Locale.ENGLISH))
    }

    @Test
    fun ukrainianUsesHourAndMinuteWords() {
        assertEquals("4 год 31 хв", DateTimeUtils.formatCompactDuration(16271, uk))
        assertEquals("1 год", DateTimeUtils.formatCompactDuration(3600, uk))
        assertEquals("45 хв", DateTimeUtils.formatCompactDuration(2700, uk))
        assertEquals("2 год 1 хв", DateTimeUtils.formatCompactDuration(7260, uk))
    }

    @Test
    fun russianSeparatesNumberAndUnitWithPlainSpace() {
        assertEquals("4 ч 31 мин", DateTimeUtils.formatCompactDuration(16271, ru))
        assertEquals("1 ч", DateTimeUtils.formatCompactDuration(3600, ru))
        assertEquals("45 мин", DateTimeUtils.formatCompactDuration(2700, ru))
        assertEquals("2 ч 1 мин", DateTimeUtils.formatCompactDuration(7260, ru))
    }

    @Test
    fun positiveSubMinuteDurationFloorsToOneMinute() {
        assertEquals("1 min", DateTimeUtils.formatCompactDuration(30, Locale.ENGLISH))
        assertEquals("1 хв", DateTimeUtils.formatCompactDuration(1, uk))
        assertEquals("1 мин", DateTimeUtils.formatCompactDuration(59, ru))
        assertEquals("1 h", DateTimeUtils.formatCompactDuration(3630, Locale.ENGLISH))
    }

    @Test
    fun nonPositiveDurationIsEmpty() {
        assertEquals("", DateTimeUtils.formatCompactDuration(0, Locale.ENGLISH))
        assertEquals("", DateTimeUtils.formatCompactDuration(-5, ru))
    }
}
