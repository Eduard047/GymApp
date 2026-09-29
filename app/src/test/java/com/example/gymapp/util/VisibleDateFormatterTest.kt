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

    @Test
    fun shortDateMatchesSharedIosOutputForSameAndOtherYear() {
        val now = LocalDate.of(2026, 9, 29).atStartOfDay(zoneId).toInstant().toEpochMilli()
        fun at(year: Int, month: Int, day: Int) =
            LocalDate.of(year, month, day).atStartOfDay(zoneId).toInstant().toEpochMilli()

        assertEquals("Sat, Sep 26", DateTimeUtils.formatShortDate(at(2026, 9, 26), Locale.ENGLISH, zoneId, now))
        assertEquals("Thu, Aug 14, 2025", DateTimeUtils.formatShortDate(at(2025, 8, 14), Locale.ENGLISH, zoneId, now))
        assertEquals("сб, 26 вер.", DateTimeUtils.formatShortDate(at(2026, 9, 26), Locale("uk"), zoneId, now))
        assertEquals("чт, 14 серп. 2025 р.", DateTimeUtils.formatShortDate(at(2025, 8, 14), Locale("uk"), zoneId, now))
        assertEquals("Сб, 26 сент.", DateTimeUtils.formatShortDate(at(2026, 9, 26), Locale("ru"), zoneId, now))
        assertEquals("Чт, 14 авг. 2025 г.", DateTimeUtils.formatShortDate(at(2025, 8, 14), Locale("ru"), zoneId, now))
    }
}
