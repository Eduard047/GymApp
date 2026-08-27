package com.example.gymapp.ui.screens

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveWorkoutHeroPresentationTest {
    @Test
    fun timerAndStartedAtUseUnambiguousClockFormats() {
        assertEquals("00:00", formatActiveWorkoutTime(-1, Locale.US))
        assertEquals("59:59", formatActiveWorkoutTime(3_599, Locale.US))
        assertEquals("01:00:00", formatActiveWorkoutTime(3_600, Locale.US))
        assertEquals(
            "14:05",
            formatActiveWorkoutStartedAt(
                timestamp = Instant.parse("2026-08-24T14:05:59Z").toEpochMilli(),
                locale = Locale.US,
                zoneId = ZoneOffset.UTC,
                is24Hour = true
            )
        )
        assertEquals(
            "2:05 PM",
            formatActiveWorkoutStartedAt(
                timestamp = Instant.parse("2026-08-24T14:05:59Z").toEpochMilli(),
                locale = Locale.US,
                zoneId = ZoneOffset.UTC,
                is24Hour = false
            )
        )
    }

    @Test
    fun heroUsesBalancedExplicitMetricsAndDedicatedProgressSemantics() {
        val source = Files.readString(
            appFile("src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt")
        )
        val hero = source.substringAfter("private fun ActiveWorkoutHero")
            .substringBefore("private fun LivePeerWorkoutHero")

        assertTrue(hero.contains("R.string.active_workout_elapsed_label"))
        assertTrue(hero.contains("R.string.active_workout_completed_label"))
        assertTrue(hero.contains("R.string.active_workout_completed_value"))
        assertTrue(hero.contains("R.string.active_workout_started_at"))
        assertTrue(hero.contains("AndroidDateFormat.is24HourFormat(context)"))
        assertTrue(hero.contains("LinearProgressIndicator"))
        assertTrue(hero.contains("progressBarRangeInfo = ProgressBarRangeInfo"))
        assertTrue(hero.contains("contentDescription = progressAccessibilityLabel"))
        assertFalse(hero.contains("InfoPill"))
        assertFalse(hero.contains("active_workout_total_time"))
        assertFalse(hero.contains("DateTimeUtils.formatDate"))
    }

    private fun appFile(relativePath: String): Path {
        val workingDirectory = Paths.get("").toAbsolutePath().normalize()
        return generateSequence(workingDirectory) { it.parent }
            .flatMap { directory ->
                sequenceOf(
                    directory.resolve(relativePath),
                    directory.resolve("app").resolve(relativePath)
                )
            }
            .distinct()
            .firstOrNull(Files::isRegularFile)
            ?: error("Could not locate app/$relativePath")
    }
}
