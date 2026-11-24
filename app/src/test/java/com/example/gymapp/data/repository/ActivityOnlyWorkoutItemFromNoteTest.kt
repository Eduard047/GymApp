package com.example.gymapp.data.repository

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * An activity-only workout without a stored sidecar row (after a backup restore) is rebuilt
 * from its note like iOS `ActivityOnlyWorkoutCloudItem.localItems`: Garmin note metrics when
 * present, otherwise Gym calories 0 and no other metrics. Cases follow the iOS
 * `GarminWorkoutNoteParser` tests in CoreParityTests.
 */
class ActivityOnlyWorkoutItemFromNoteTest {
    private val startedAt = 1_750_000_000_000L
    private val duration = 754L

    private fun item(note: String?) = activityOnlyWorkoutItemFromNote(
        workoutStartedAt = startedAt,
        durationSeconds = duration,
        note = note
    )

    @Test
    fun garminNoteFillsEveryMetricLikeIos() {
        val note = "Garmin · Duration 12:34 · Gym kcal 40 · Garmin kcal 38 · " +
            "Avg HR 130 · Max HR 165 · Ending HR zone Z3 · " +
            "S1 42s R90s HR118/154/136 ↓18 C92% I0-42s K4.5/5 Z0/0/12/20/10/0s"

        val result = item(note)

        assertEquals(
            ActivityOnlyWorkoutItem(
                workoutStartedAt = startedAt,
                durationSeconds = duration,
                gymCalories = 40.0,
                garminCalories = 38,
                averageHeartRate = 130,
                maximumHeartRate = 165,
                endingHeartRateZone = 3,
                note = note
            ),
            result
        )
        requireValidActivityOnlyWorkoutItem(result)
    }

    @Test
    fun localizedGarminNoteFillsMetrics() {
        val note = "Garmin Fenix 8 · Длительность 12:34 · Gym ккал 40 · Garmin ккал 38 · " +
            "Средний пульс 130 · Макс пульс 165 · Конечная зона пульса Z3"

        val result = item(note)

        assertEquals(40.0, result.gymCalories, 0.0)
        assertEquals(38, result.garminCalories)
        assertEquals(130, result.averageHeartRate)
        assertEquals(165, result.maximumHeartRate)
        assertEquals(3, result.endingHeartRateZone)
    }

    @Test
    fun garminNoteWithoutMetricsKeepsZeroGymCaloriesAndNoOtherMetrics() {
        val note = "Garmin · Duration 12:34"

        assertEquals(
            ActivityOnlyWorkoutItem(
                workoutStartedAt = startedAt,
                durationSeconds = duration,
                gymCalories = 0.0,
                note = note
            ),
            item(note)
        )
    }

    @Test
    fun nonGarminOrMissingNoteFallsBackToZeroGymCalories() {
        listOf(null, "", "Manual workout · Avg HR 120 · Gym kcal 40").forEach { note ->
            assertEquals(
                ActivityOnlyWorkoutItem(
                    workoutStartedAt = startedAt,
                    durationSeconds = duration,
                    gymCalories = 0.0,
                    note = note
                ),
                item(note)
            )
        }
    }

    @Test
    fun heartRateAboveSidecarBoundDropsSummaryLikeIos() {
        // iOS GarminWorkoutNoteParser caps heart rate at 240 and rejects the whole note above it.
        val note = "Garmin · Gym kcal 40 · Avg HR 120 · Max HR 260"

        val result = item(note)

        assertEquals(0.0, result.gymCalories, 0.0)
        assertEquals(null, result.averageHeartRate)
        assertEquals(null, result.maximumHeartRate)
        requireValidActivityOnlyWorkoutItem(result)
    }

    @Test
    fun contradictoryHeartRateNeverYieldsInvalidItem() {
        val result = item("Garmin · Avg HR 180 · Max HR 150")

        assertEquals(null, result.averageHeartRate)
        assertEquals(null, result.maximumHeartRate)
        requireValidActivityOnlyWorkoutItem(result)
    }
}
