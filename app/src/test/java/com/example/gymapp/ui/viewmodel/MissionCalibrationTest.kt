package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class MissionCalibrationTest {
    @Test
    fun `uses a typical recent value instead of the highest outlier`() {
        assertEquals(10, realisticMissionBaseline(listOf(8, 10, 12, 80), fallback = 10))
    }

    @Test
    fun `sparse history always uses the fallback`() {
        assertEquals(10, realisticMissionBaseline(listOf(80), fallback = 10))
        assertEquals(10, realisticMissionBaseline(listOf(8), fallback = 10))
        assertEquals(10, realisticMissionBaseline(emptyList(), fallback = 10))
    }

    @Test
    fun `ignores empty periods once enough positive history exists`() {
        assertEquals(8, realisticMissionBaseline(listOf(0, 8, 40), fallback = 10))
    }

    @Test
    fun `calendar windows exclude stale sessions and incomplete week and month`() {
        val windows = missionCalendarWindows(LocalDate.of(2026, 8, 9))

        assertEquals(LocalDate.of(2026, 6, 28), windows.dayStartInclusive)
        assertEquals(LocalDate.of(2026, 8, 8), windows.dayEndInclusive)
        assertTrue(windows.containsRecentDay(LocalDate.of(2026, 6, 28)))
        assertFalse(windows.containsRecentDay(LocalDate.of(2026, 6, 27)))
        assertFalse(windows.containsRecentDay(LocalDate.of(2026, 8, 9)))

        assertTrue(windows.containsCompletedWeek(LocalDate.of(2026, 7, 27)))
        assertFalse(windows.containsCompletedWeek(LocalDate.of(2026, 8, 3)))
        assertFalse(windows.containsCompletedWeek(LocalDate.of(2026, 6, 1)))

        assertTrue(windows.containsCompletedMonth(YearMonth.of(2026, 7)))
        assertFalse(windows.containsCompletedMonth(YearMonth.of(2026, 8)))
        assertFalse(windows.containsCompletedMonth(YearMonth.of(2026, 1)))

        assertTrue(windows.containsRecentSession(LocalDate.of(2026, 2, 1)))
        assertFalse(windows.containsRecentSession(LocalDate.of(2026, 1, 31)))
        assertFalse(windows.containsRecentSession(LocalDate.of(2026, 8, 9)))
    }

    @Test
    fun `current day outlier does not calibrate its own mission target`() {
        val today = LocalDate.of(2026, 8, 9)
        val windows = missionCalendarWindows(today)
        val setCountsByDay = listOf(
            LocalDate.of(2026, 8, 7) to 10,
            LocalDate.of(2026, 8, 8) to 12,
            today to 500
        )
        val completedSetCounts = setCountsByDay
            .filter { (day, _) -> windows.containsRecentDay(day) }
            .map { (_, setCount) -> setCount }

        assertEquals(10, realisticMissionBaseline(completedSetCounts, fallback = 8))
    }

    @Test
    fun `groups equivalent mission variants so the board stays varied`() {
        assertEquals("sets", missionSelectionMetric("sets"))
        assertEquals("sets", missionSelectionMetric("max-session-sets"))
        assertEquals("sets", missionSelectionMetric("days-10-sets"))
        assertEquals("workouts", missionSelectionMetric("active-days"))
        assertEquals("volume", missionSelectionMetric("days-1000-volume"))
    }
}
