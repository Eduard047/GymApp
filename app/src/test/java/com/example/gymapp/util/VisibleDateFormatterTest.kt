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
    fun longDateForLocalDateUsesGenitiveMonthWithoutTrailingPeriod() {
        val firstOfSeptember = LocalDate.of(2026, 9, 1)
        assertEquals("вторник, 1 сентября 2026", DateTimeUtils.formatLongDate(firstOfSeptember, Locale("ru")))
        assertEquals("вівторок, 1 вересня 2026", DateTimeUtils.formatLongDate(firstOfSeptember, Locale("uk")))
        assertEquals("Tuesday, 1 September 2026", DateTimeUtils.formatLongDate(firstOfSeptember, Locale.UK))
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

    @Test
    fun chartAxisDateIsDayAndShortMonthWithoutWeekdayInitial() {
        // 2026-08-11 is a Tuesday: the old "EEEEE d" pattern rendered "T 11" in English.
        fun at(month: Int, day: Int) =
            LocalDate.of(2026, month, day).atStartOfDay(zoneId).toInstant().toEpochMilli()

        assertEquals("Aug 11", DateTimeUtils.formatChartAxisDate(at(8, 11), Locale.ENGLISH, zoneId))
        assertEquals("Sep 8", DateTimeUtils.formatChartAxisDate(at(9, 8), Locale.ENGLISH, zoneId))
        assertEquals("8 вер.", DateTimeUtils.formatChartAxisDate(at(9, 8), Locale("uk"), zoneId))
        assertEquals("11 серп.", DateTimeUtils.formatChartAxisDate(at(8, 11), Locale("uk"), zoneId))
        assertEquals("8 сент.", DateTimeUtils.formatChartAxisDate(at(9, 8), Locale("ru"), zoneId))
        assertEquals("11 авг.", DateTimeUtils.formatChartAxisDate(at(8, 11), Locale("ru"), zoneId))
    }

    @Test
    fun dateRangeMatchesSharedIosOutput() {
        val now = LocalDate.of(2026, 9, 29)
        fun range(start: LocalDate, end: LocalDate, tag: String) =
            DateTimeUtils.formatDateRange(start, end, Locale(tag), now)
        val sameMonth = LocalDate.of(2026, 9, 21) to LocalDate.of(2026, 9, 27)
        val crossMonth = LocalDate.of(2026, 9, 28) to LocalDate.of(2026, 10, 4)
        val otherYear = LocalDate.of(2025, 9, 22) to LocalDate.of(2025, 9, 28)
        val crossYear = LocalDate.of(2025, 12, 29) to LocalDate.of(2026, 1, 4)

        assertEquals("Sep 21\u2009\u2013\u200927", range(sameMonth.first, sameMonth.second, "en"))
        assertEquals("Sep 28\u2009\u2013\u2009Oct 4", range(crossMonth.first, crossMonth.second, "en"))
        assertEquals("Sep 22\u2009\u2013\u200928, 2025", range(otherYear.first, otherYear.second, "en"))
        assertEquals(
            "Dec 29, 2025\u2009\u2013\u2009Jan 4, 2026",
            range(crossYear.first, crossYear.second, "en")
        )

        assertEquals("21\u201327 вер.", range(sameMonth.first, sameMonth.second, "uk"))
        assertEquals("28 вер. \u2013 4 жовт.", range(crossMonth.first, crossMonth.second, "uk"))
        assertEquals("22\u201328 вер. 2025\u202Fр.", range(otherYear.first, otherYear.second, "uk"))
        assertEquals(
            "29 груд. 2025 \u2013 4 січ. 2026\u202Fрр.",
            range(crossYear.first, crossYear.second, "uk")
        )

        assertEquals("21\u201427 сент.", range(sameMonth.first, sameMonth.second, "ru"))
        assertEquals("28 сент.\u2009\u2014\u20094 окт.", range(crossMonth.first, crossMonth.second, "ru"))
        assertEquals("22\u201428 сент. 2025\u202Fг.", range(otherYear.first, otherYear.second, "ru"))
        assertEquals(
            "29 дек. 2025\u2009\u2014\u20094 янв. 2026\u202Fг.",
            range(crossYear.first, crossYear.second, "ru")
        )
    }
}
