package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

class WorkoutDateSelectionTest {
    private val zoneId = ZoneId.of("Europe/Kyiv")
    private val now = ZonedDateTime.of(2026, 8, 4, 14, 30, 0, 0, zoneId)

    @Test
    fun `yesterday keeps the workout time without a timezone day shift`() {
        val resolved = resolveWorkoutDateSelection(
            currentTimestamp = now.toInstant().toEpochMilli(),
            selectedEpochDay = LocalDate.of(2026, 8, 3).toEpochDay(),
            nowMillis = now.toInstant().toEpochMilli(),
            zoneId = zoneId
        )

        val local = ZonedDateTime.ofInstant(
            java.time.Instant.ofEpochMilli(requireNotNull(resolved)),
            zoneId
        )
        assertEquals(LocalDate.of(2026, 8, 3), local.toLocalDate())
        assertEquals(LocalTime.of(14, 30), local.toLocalTime())
    }

    @Test
    fun `future day and invalid epoch day are rejected`() {
        assertNull(
            resolveWorkoutDateSelection(
                currentTimestamp = now.toInstant().toEpochMilli(),
                selectedEpochDay = LocalDate.of(2026, 8, 5).toEpochDay(),
                nowMillis = now.toInstant().toEpochMilli(),
                zoneId = zoneId
            )
        )
        assertNull(
            resolveWorkoutDateSelection(
                currentTimestamp = now.toInstant().toEpochMilli(),
                selectedEpochDay = Long.MAX_VALUE,
                nowMillis = now.toInstant().toEpochMilli(),
                zoneId = zoneId
            )
        )
    }

    @Test
    fun `today is allowed but cannot resolve beyond now`() {
        val oneHourLater = now.plusHours(1).toInstant().toEpochMilli()
        val resolved = resolveWorkoutDateSelection(
            currentTimestamp = oneHourLater,
            selectedEpochDay = now.toLocalDate().toEpochDay(),
            nowMillis = now.toInstant().toEpochMilli(),
            zoneId = zoneId
        )

        assertEquals(now.toInstant().toEpochMilli(), resolved)
        assertTrue(
            isSelectableWorkoutTimestamp(
                timestamp = now.toInstant().toEpochMilli(),
                nowMillis = now.toInstant().toEpochMilli(),
                zoneId = zoneId
            )
        )
        assertFalse(
            isSelectableWorkoutTimestamp(
                timestamp = now.plusDays(1).toInstant().toEpochMilli(),
                nowMillis = now.toInstant().toEpochMilli(),
                zoneId = zoneId
            )
        )
    }
}
