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
        val otherYear = LocalDate.of(2027, 1, 5).atStartOfDay(zoneId).toInstant().toEpochMilli()
        assertEquals("Thu, Aug 13, 2026", DateTimeUtils.formatDate(timestamp, Locale.ENGLISH, zoneId, otherYear))
        assertEquals("Чт, 13 авг. 2026 г.", DateTimeUtils.formatDate(timestamp, Locale("ru"), zoneId, otherYear))
        assertEquals("чт, 13 серп. 2026 р.", DateTimeUtils.formatDate(timestamp, Locale("uk"), zoneId, otherYear))
        assertEquals("Thu, Aug 13", DateTimeUtils.formatDate(timestamp, Locale.ENGLISH, zoneId, timestamp))
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
    fun longDateWithoutYearUsesGenitiveMonthForRussianAndUkrainian() {
        val sunday = LocalDate.of(2026, 10, 11)
        assertEquals("воскресенье, 11 октября", DateTimeUtils.formatLongDateWithoutYear(sunday, Locale("ru")))
        assertEquals("неділя, 11 жовтня", DateTimeUtils.formatLongDateWithoutYear(sunday, Locale("uk")))
        assertEquals("Sunday, 11 October", DateTimeUtils.formatLongDateWithoutYear(sunday, Locale.UK))
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
    fun dateRangeMatchesWebAndIosWeekFormat() {
        val now = LocalDate.of(2026, 10, 16)
        fun range(start: LocalDate, end: LocalDate, tag: String) =
            DateTimeUtils.formatDateRange(start, end, Locale(tag), now)
        val sameMonth = LocalDate.of(2026, 10, 12) to LocalDate.of(2026, 10, 18)
        val crossMonth = LocalDate.of(2026, 9, 28) to LocalDate.of(2026, 10, 4)
        val otherYear = LocalDate.of(2025, 9, 22) to LocalDate.of(2025, 9, 28)
        val crossYear = LocalDate.of(2025, 12, 29) to LocalDate.of(2026, 1, 4)

        assertEquals("Oct 12 \u2013 Oct 18", range(sameMonth.first, sameMonth.second, "en"))
        assertEquals("12 жовт. \u2013 18 жовт.", range(sameMonth.first, sameMonth.second, "uk"))
        assertEquals("12 окт. \u2013 18 окт.", range(sameMonth.first, sameMonth.second, "ru"))
        assertEquals("Sep 28 \u2013 Oct 4", range(crossMonth.first, crossMonth.second, "en"))
        assertEquals("28 вер. \u2013 4 жовт.", range(crossMonth.first, crossMonth.second, "uk"))
        assertEquals("28 сент. \u2013 4 окт.", range(crossMonth.first, crossMonth.second, "ru"))

        // The year goes on both ends when either end is outside the current year.
        assertEquals("Sep 22, 2025 \u2013 Sep 28, 2025", range(otherYear.first, otherYear.second, "en"))
        assertEquals("22 вер. 2025 р. \u2013 28 вер. 2025 р.", range(otherYear.first, otherYear.second, "uk"))
        assertEquals("22 сент. 2025 г. \u2013 28 сент. 2025 г.", range(otherYear.first, otherYear.second, "ru"))
        assertEquals("Dec 29, 2025 \u2013 Jan 4, 2026", range(crossYear.first, crossYear.second, "en"))
        assertEquals("29 груд. 2025 р. \u2013 4 січ. 2026 р.", range(crossYear.first, crossYear.second, "uk"))
        assertEquals("29 дек. 2025 г. \u2013 4 янв. 2026 г.", range(crossYear.first, crossYear.second, "ru"))
    }

    @Test
    fun spokenDateRangeUsesFromTo() {
        val now = LocalDate.of(2026, 10, 16)
        val start = LocalDate.of(2026, 10, 12)
        val end = LocalDate.of(2026, 10, 18)
        assertEquals("from Oct 12 to Oct 18", DateTimeUtils.formatDateRangeSpoken(start, end, Locale.ENGLISH, now))
        assertEquals("з 12 жовт. по 18 жовт.", DateTimeUtils.formatDateRangeSpoken(start, end, Locale("uk"), now))
        assertEquals("с 12 окт. по 18 окт.", DateTimeUtils.formatDateRangeSpoken(start, end, Locale("ru"), now))
    }
}
