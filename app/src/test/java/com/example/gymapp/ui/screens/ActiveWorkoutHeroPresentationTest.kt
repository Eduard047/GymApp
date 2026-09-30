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
    fun heroIsOneBrandPanelWithRingAndSingleAccessibilityElement() {
        val source = Files.readString(
            appFile("src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt")
        )
        val hero = source.substringAfter("private fun ActiveWorkoutHero")
            .substringBefore("private fun LivePeerWorkoutHero")

        assertTrue(hero.contains("BrandHeroPanel("))
        assertTrue(hero.contains("R.string.active_workout_status_in_progress"))
        assertTrue(hero.contains("ACTIVE_WORKOUT_ELAPSED_METRIC_TAG"))
        assertTrue(hero.contains("R.string.active_workout_now"))
        assertTrue(hero.contains("R.string.active_workout_sets_caption"))
        assertTrue(hero.contains("Canvas("))
        assertTrue(hero.contains("StrokeCap.Round"))
        assertTrue(hero.contains("startAngle = -90f"))
        assertTrue(hero.contains(".clearAndSetSemantics { contentDescription = summary }"))
        assertTrue(hero.contains("R.plurals.active_workout_hero_sets_done"))
        assertTrue(hero.contains("R.string.active_workout_hero_summary_now"))
        assertFalse(hero.contains("MetricTile"))
        assertFalse(hero.contains("LinearProgressIndicator"))
        assertFalse(hero.contains("active_workout_started_at"))
        assertFalse(hero.contains("DateTimeUtils.formatDate"))
    }

    @Test
    fun toolbarOwnsAdaptAndDiscardAndTheBodyKeepsNeitherPanel() {
        val source = Files.readString(
            appFile("src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt")
        )
        val overflow = source.substringAfter("fun ActiveWorkoutOverflowMenu")
            .substringBefore("private enum class LiveParticipantTab")

        assertTrue(overflow.contains("R.string.active_workout_more_options"))
        assertTrue(overflow.contains("R.string.training_adapt_workout"))
        assertTrue(overflow.contains("R.string.active_workout_discard_short"))
        assertTrue(overflow.contains("state.discardRequested = true"))
        assertFalse(source.contains("showMoreWorkoutOptions"))
        assertFalse(source.contains("showAdaptationOptions"))
    }

    @Test
    fun exerciseHeaderShowsSetSubtitleAndCollapsedProgressWithoutEyebrowOrEditButton() {
        val source = Files.readString(
            appFile("src/main/java/com/example/gymapp/ui/screens/ActiveWorkoutScreen.kt")
        )
        val card = source.substringAfter("private fun ActiveWorkoutExerciseCard")
            .substringBefore("private fun ActiveWorkoutSetRow")

        assertTrue(card.contains("R.string.active_workout_exercise_set_subtitle"))
        assertTrue(card.contains("R.plurals.active_workout_exercise_up_next_sets"))
        assertTrue(card.contains("R.string.active_workout_exercise_done"))
        assertTrue(card.contains("\"\$completedCount / \$totalCount\""))
        assertTrue(card.contains("rememberSaveable(exercise.id, screenEntryToken)"))
        assertFalse(card.contains("active_workout_exercise_number"))
        assertFalse(card.contains("active_workout_edit_exercise"))
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
