package com.example.gymapp.ui.components

import com.example.gymapp.util.DateTimeUtils
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

class AchievementGalleryTest {
    @Test
    fun gridUsesThreeColumnsAndTwoAtLargeFontScales() {
        assertEquals(3, achievementGridColumns(1.0f))
        assertEquals(3, achievementGridColumns(1.3f))
        assertEquals(2, achievementGridColumns(1.4f))
        assertEquals(2, achievementGridColumns(2.0f))
    }

    @Test
    fun categoryShowsOnlyWhenItDiffersFromTheName() {
        assertFalse(achievementShowsCategory("First Workout", "first workout"))
        assertFalse(achievementShowsCategory("First Workout", ""))
        assertTrue(achievementShowsCategory("Two-Week Rhythm", "Consistency"))
    }

    @Test
    fun unlockedDateUsesTheSharedShortFormat() {
        val zone = ZoneId.of("UTC")
        val now = LocalDate.of(2026, 9, 29).atStartOfDay(zone).toInstant().toEpochMilli()
        val epochDay = LocalDate.of(2026, 9, 26).toEpochDay()
        assertEquals("Sat, Sep 26", DateTimeUtils.formatEpochDayShort(epochDay, Locale.ENGLISH, zone, now))
        assertEquals("сб, 26 вер.", DateTimeUtils.formatEpochDayShort(epochDay, Locale("uk"), zone, now))
        assertEquals("Сб, 26 сент.", DateTimeUtils.formatEpochDayShort(epochDay, Locale("ru"), zone, now))
    }
}
