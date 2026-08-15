package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

class VisibleDateFormatterTest {
    private val zoneId = ZoneId.of("UTC")
    private val timestamp = LocalDate.of(2026, 8, 13)
        .atStartOfDay(zoneId)
        .toInstant()
        .toEpochMilli()

    @Test
    fun compactDateIncludesLocalizedWeekday() {
        assertEquals("Thu, 13 Aug 2026", DateTimeUtils.formatDate(timestamp, Locale.ENGLISH, zoneId))
        assertEquals("чт, 13 авг. 2026", DateTimeUtils.formatDate(timestamp, Locale("ru"), zoneId))
        assertEquals("чт, 13 серп. 2026", DateTimeUtils.formatDate(timestamp, Locale("uk"), zoneId))
    }

    @Test
    fun expandedDateIncludesLocalizedWideWeekday() {
        assertEquals(
            "четверг, 13 августа 2026",
            DateTimeUtils.formatLongDate(timestamp, Locale("ru"), zoneId)
        )
        val saturday = LocalDate.of(2026, 8, 15)
            .atStartOfDay(zoneId)
            .toInstant()
            .toEpochMilli()
        assertEquals(
            "субота, 15 серпня 2026",
            DateTimeUtils.formatLongDate(saturday, Locale("uk"), zoneId)
        )
    }
}
