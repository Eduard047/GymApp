package com.example.gymapp.util

import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

class CurrentDayTrackerTest {
    private val kyiv = ZoneId.of("Europe/Kyiv")
    private val tokyo = ZoneId.of("Asia/Tokyo")

    @Test
    fun refreshEmitsTheNewDayAfterMidnight() {
        var instant = ZonedDateTime.of(2026, 11, 7, 23, 59, 0, 0, kyiv).toInstant()
        val tracker = CurrentDayTracker(
            zoneProvider = { kyiv },
            dateProvider = { zone -> LocalDate.ofInstant(instant, zone) }
        )
        assertEquals(LocalDate.of(2026, 11, 7), tracker.state.value.date)

        instant = ZonedDateTime.of(2026, 11, 8, 0, 1, 0, 0, kyiv).toInstant()
        tracker.refresh()

        assertEquals(CurrentDay(LocalDate.of(2026, 11, 8), kyiv), tracker.state.value)
    }

    @Test
    fun refreshWithinTheSameDayKeepsTheSameValue() {
        val instant = ZonedDateTime.of(2026, 11, 7, 10, 0, 0, 0, kyiv).toInstant()
        val tracker = CurrentDayTracker(
            zoneProvider = { kyiv },
            dateProvider = { zone -> LocalDate.ofInstant(instant, zone) }
        )
        val before = tracker.state.value
        tracker.refresh()
        assertEquals(before, tracker.state.value)
    }

    @Test
    fun timezoneChangeEmitsEvenWhenTheDateIsTheSame() {
        var zone = kyiv
        val instant = ZonedDateTime.of(2026, 11, 7, 12, 0, 0, 0, kyiv).toInstant()
        val tracker = CurrentDayTracker(
            zoneProvider = { zone },
            dateProvider = { z -> LocalDate.ofInstant(instant, z) }
        )
        assertEquals(CurrentDay(LocalDate.of(2026, 11, 7), kyiv), tracker.state.value)

        zone = tokyo
        tracker.refresh()

        assertEquals(CurrentDay(LocalDate.of(2026, 11, 7), tokyo), tracker.state.value)
    }

    @Test
    fun timezoneChangeAcrossTheDateLineMovesTheDay() {
        var zone = ZoneId.of("Pacific/Honolulu")
        val instant = ZonedDateTime.of(2026, 11, 7, 20, 0, 0, 0, zone).toInstant()
        val tracker = CurrentDayTracker(
            zoneProvider = { zone },
            dateProvider = { z -> LocalDate.ofInstant(instant, z) }
        )
        assertEquals(LocalDate.of(2026, 11, 7), tracker.state.value.date)

        zone = tokyo
        tracker.refresh()

        assertEquals(LocalDate.of(2026, 11, 8), tracker.state.value.date)
    }
}
