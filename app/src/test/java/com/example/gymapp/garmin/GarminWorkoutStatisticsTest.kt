package com.example.gymapp.garmin

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class GarminWorkoutStatisticsTest {
    @Test
    fun parserKeepsLegacyNotesAndNamesTheFinalZoneHonestly() {
        val current = parseGarminWorkoutMetrics(
            "Garmin · Duration 62:03 · Gym kcal 240 · Garmin kcal 215 · " +
                "Avg HR 132 · Max HR 168 · Ending HR zone Z3"
        )
        val legacy = parseGarminWorkoutMetrics(
            "Garmin Fenix 8 · Длительность 1:02:03 · Средний пульс 131 · " +
                "Макс. пульс 165 · Зона пульса Z2"
        )

        assertNotNull(current)
        assertEquals(3_723L, current?.durationSeconds)
        assertEquals(240, current?.gymCalories)
        assertEquals(215, current?.garminCalories)
        assertEquals(132, current?.averageHeartRate)
        assertEquals(168, current?.maximumHeartRate)
        assertEquals(3, current?.endingHeartRateZone)
        assertEquals(3_723L, legacy?.durationSeconds)
        assertEquals(2, legacy?.endingHeartRateZone)
    }

    @Test
    fun parserDropsUnavailableOrOutOfRangeScalarsInsteadOfInventingValues() {
        val parsed = parseGarminWorkoutMetrics(
            "Garmin · Duration 1:234 · Gym kcal 1000000 · Garmin kcal 0 · " +
                "Avg HR 3000 · Max HR 0 · Ending HR zone Z30"
        )

        assertNotNull(parsed)
        assertNull(parsed?.durationSeconds)
        assertNull(parsed?.gymCalories)
        assertNull(parsed?.garminCalories)
        assertNull(parsed?.averageHeartRate)
        assertNull(parsed?.maximumHeartRate)
        assertNull(parsed?.endingHeartRateZone)
        assertNull(parseGarminWorkoutMetrics("Manual workout · Avg HR 120"))

        val contradictory = parseGarminWorkoutMetrics("Garmin · Avg HR 180 · Max HR 120")
        assertNull(contradictory?.averageHeartRate)
        assertNull(contradictory?.maximumHeartRate)
    }

    @Test
    fun garminPresentationRequiresLocalReceiptProvenance() {
        val userControlledNote =
            "Garmin · Duration 45:00 · Garmin kcal 250 · Avg HR 140 · Max HR 175"

        assertNull(
            parseTrustedGarminWorkoutMetrics(
                note = userControlledNote,
                hasGarminReceipt = false
            )
        )
        val trusted = parseTrustedGarminWorkoutMetrics(
            note = userControlledNote,
            hasGarminReceipt = true
        )
        assertNotNull(trusted)
        assertEquals(250, trusted?.garminCalories)
    }

    @Test
    fun comparableSelectionUsesDateAndIdAndNeverChoosesFutureData() {
        val current = snapshot(
            sessionId = 20,
            sessionDate = 2_000,
            sets = 5,
            reps = 50,
            volume = 1_200.0,
            metrics = GarminWorkoutMetrics(
                durationSeconds = 900,
                garminCalories = 180,
                averageHeartRate = 135,
                maximumHeartRate = 170
            )
        )
        val latestEarlier = snapshot(
            sessionId = 19,
            sessionDate = 2_000,
            sets = 4,
            reps = 44,
            volume = 1_000.0,
            metrics = GarminWorkoutMetrics(
                durationSeconds = 840,
                averageHeartRate = 130,
                maximumHeartRate = 165
            )
        )
        val older = snapshot(sessionId = 18, sessionDate = 1_900, sets = 3, reps = 30, volume = 700.0)
        val sameTimeButFutureId = snapshot(
            sessionId = 21,
            sessionDate = 2_000,
            sets = 99,
            reps = 999,
            volume = 99_000.0
        )
        val futureDate = snapshot(
            sessionId = 1,
            sessionDate = 2_100,
            sets = 88,
            reps = 888,
            volume = 88_000.0
        )

        val comparison = findPreviousComparableWorkout(
            current = current,
            candidates = listOf(older, sameTimeButFutureId, futureDate, latestEarlier)
        )

        assertEquals(19L, comparison?.previousSessionId)
        assertEquals(1.0, comparison?.setCount?.delta ?: Double.NaN, 0.0)
        assertEquals(6.0, comparison?.totalReps?.delta ?: Double.NaN, 0.0)
        assertEquals(200.0, comparison?.totalVolume?.delta ?: Double.NaN, 0.0)
        assertEquals(60.0, comparison?.durationSeconds?.delta ?: Double.NaN, 0.0)
        assertEquals(5.0, comparison?.averageHeartRate?.delta ?: Double.NaN, 0.0)
        assertNull(comparison?.garminCalories)
    }

    @Test
    fun comparisonRequiresTheExactCanonicalExerciseSignature() {
        val current = comparableWorkoutSnapshotOrNull(
            sessionId = 3,
            sessionDate = 3_000,
            note = null,
            entries = listOf(entry(3, 3_000, 1, "Bench Press"))
        )
        val translatedAlias = comparableWorkoutSnapshotOrNull(
            sessionId = 2,
            sessionDate = 2_000,
            note = null,
            entries = listOf(entry(2, 2_000, 2, "Жим штанги лежачи"))
        )
        val differentExercise = snapshot(
            sessionId = 1,
            sessionDate = 1_000,
            sets = 10,
            reps = 100,
            volume = 10_000.0,
            signature = listOf("catalog:squat")
        )

        assertNotNull(current)
        assertEquals(current?.exerciseSignature, translatedAlias?.exerciseSignature)
        val comparison = findPreviousComparableWorkout(
            current = requireNotNull(current),
            candidates = listOf(differentExercise, requireNotNull(translatedAlias))
        )
        assertEquals(2L, comparison?.previousSessionId)
    }

    @Test
    fun corruptedSetValuesAreExcludedFromComparison() {
        val invalid = comparableWorkoutSnapshotOrNull(
            sessionId = 1,
            sessionDate = 1_000,
            note = null,
            entries = listOf(entry(1, 1_000, 1, "Bench Press", weight = Double.NaN))
        )

        assertNull(invalid)
    }

    private fun snapshot(
        sessionId: Long,
        sessionDate: Long,
        sets: Int,
        reps: Long,
        volume: Double,
        metrics: GarminWorkoutMetrics? = null,
        signature: List<String> = listOf("catalog:bench_press")
    ) = ComparableWorkoutSnapshot(
        sessionId = sessionId,
        sessionDate = sessionDate,
        exerciseSignature = signature,
        setCount = sets,
        totalReps = reps,
        totalVolume = volume,
        garminMetrics = metrics
    )

    private fun entry(
        sessionId: Long,
        sessionDate: Long,
        setId: Long,
        exerciseName: String,
        weight: Double = 100.0
    ) = ExerciseHistoryEntry(
        setId = setId,
        sessionId = sessionId,
        sessionDate = sessionDate,
        exerciseId = setId,
        exerciseName = exerciseName,
        weight = weight,
        reps = 10,
        setOrderIndex = 0
    )
}
