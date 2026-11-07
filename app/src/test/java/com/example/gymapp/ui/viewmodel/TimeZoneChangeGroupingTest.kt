package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.WorkoutSessionEntity
import com.example.gymapp.data.entity.WorkoutSessionSummary
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * View models read the zone through a provider on every use (like iOS Calendar.current), so a
 * device timezone change while the process is alive regroups days on the next emission.
 */
class TimeZoneChangeGroupingTest {
    private val instant = Instant.parse("2026-11-08T01:00:00Z")

    private fun summary(date: Long) = WorkoutSessionSummary(
        session = WorkoutSessionEntity(id = 1, date = date, note = null),
        exerciseCount = 1,
        setCount = 3,
        totalVolume = 300.0
    )

    @Test
    fun sameInstantFallsOnDifferentDaysAcrossZones() {
        var current = ZoneId.of("Europe/Kyiv")
        val provider: () -> ZoneId = { current }

        assertEquals(LocalDate.of(2026, 11, 8), instant.atZone(provider()).toLocalDate())
        current = ZoneId.of("America/New_York")
        assertEquals(LocalDate.of(2026, 11, 7), instant.atZone(provider()).toLocalDate())
    }

    @Test
    fun todayGroupingFollowsProviderWithoutRebuildingCaller() {
        var current = ZoneId.of("Europe/Kyiv")
        val provider: () -> ZoneId = { current }
        val sessions = listOf(summary(instant.toEpochMilli()))
        val now = Instant.parse("2026-11-08T14:00:00Z").toEpochMilli()

        // Kyiv: workout Nov 8 03:00, now Nov 8 16:00 -> same day.
        assertTrue(hasCompletedWorkoutToday(sessions, now, provider()))
        // Travel to New York: workout Nov 7 20:00, now Nov 8 09:00 -> different days.
        current = ZoneId.of("America/New_York")
        assertFalse(hasCompletedWorkoutToday(sessions, now, provider()))
    }
}
