package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ExerciseHistoryEntry
import org.junit.Assert.assertEquals
import org.junit.Test

class LivePersonalRecordsTest {
    private val bench = 1L
    private val squat = 2L

    private fun history(exerciseId: Long, weights: List<Double>, reps: List<Int>): List<ExerciseHistoryEntry> =
        weights.indices.map { index ->
            ExerciseHistoryEntry(
                setId = exerciseId * 100 + index,
                sessionId = exerciseId,
                sessionDate = 1_780_000_000_000L,
                exerciseId = exerciseId,
                exerciseName = "Exercise $exerciseId",
                weight = weights[index],
                reps = reps[index],
                setOrderIndex = index
            )
        }

    /** Sets completed in order; a null weight marks a set that is not completed. */
    private fun records(
        exercises: List<Pair<Long, List<Pair<Double, Int>?>>>,
        history: List<ExerciseHistoryEntry>
    ): List<Boolean> {
        val completed = mutableListOf<LiveCompletedSet>()
        val ids = mutableListOf<String?>()
        var clock = 1_000L
        exercises.forEachIndexed { exerciseIndex, (exerciseId, sets) ->
            sets.forEachIndexed { setIndex, set ->
                if (set == null) {
                    ids += null
                } else {
                    val id = "$exerciseIndex-$setIndex"
                    ids += id
                    completed += LiveCompletedSet(exerciseId, id, set.first, set.second, clock++, exerciseIndex, setIndex)
                }
            }
        }
        val records = LivePersonalRecords.recordSetIds(completed, LivePersonalRecords.baselines(history))
        return ids.map { it != null && it in records }
    }

    @Test
    fun heavierWeightOrBetterEstimateIsARecord() {
        val past = history(bench, listOf(80.0, 80.0), listOf(8, 8))
        // 85 kg beats the weight best; 80×10 beats the 80×8 estimate; 80×8 equals it.
        assertEquals(
            listOf(true, true, false),
            records(listOf(bench to listOf(85.0 to 3, 80.0 to 10, 80.0 to 8)), past)
        )
    }

    @Test
    fun equalToTheBestIsNotARecord() {
        assertEquals(listOf(false), records(listOf(bench to listOf(100.0 to 5)), history(bench, listOf(100.0), listOf(5))))
    }

    @Test
    fun firstSessionOfAnExerciseNeverSetsARecord() {
        assertEquals(listOf(false, false), records(listOf(bench to listOf(60.0 to 8, 70.0 to 8)), emptyList()))
    }

    @Test
    fun zeroKilogramSetIsNeverARecord() {
        assertEquals(
            listOf(false, true),
            records(listOf(bench to listOf(0.0 to 20, 5.0 to 8)), history(bench, listOf(0.0), listOf(8)))
        )
    }

    @Test
    fun laterSetsCompareAgainstTheBestSoFarInThisWorkout() {
        assertEquals(
            listOf(true, false, true, false),
            records(
                listOf(bench to listOf(90.0 to 5, 85.0 to 5, 95.0 to 5, 95.0 to 5)),
                history(bench, listOf(80.0), listOf(5))
            )
        )
    }

    @Test
    fun incompleteSetsAndOtherExercisesDoNotInterfere() {
        val past = history(bench, listOf(80.0), listOf(5)) + history(squat, listOf(140.0), listOf(5))
        assertEquals(
            listOf(false, true, false),
            records(listOf(bench to listOf(null, 82.5 to 5), squat to listOf(100.0 to 5)), past)
        )
    }

    @Test
    fun completionOrderDecidesWhichSetHoldsTheRecord() {
        val baselines = LivePersonalRecords.baselines(history(bench, listOf(80.0), listOf(5)))
        val first = LiveCompletedSet(bench, "first", 90.0, 5, completedAt = 2_000L, exerciseIndex = 0, setIndex = 0)
        val second = LiveCompletedSet(bench, "second", 90.0, 5, completedAt = 1_000L, exerciseIndex = 0, setIndex = 1)

        assertEquals(setOf("second"), LivePersonalRecords.recordSetIds(listOf(first, second), baselines))
    }

    @Test
    fun baselinesUseHistoryBestsAndTheSharedEstimate() {
        val baseline = LivePersonalRecords.baselines(history(bench, listOf(100.0, 80.0), listOf(1, 10))).getValue(bench)

        assertEquals(100.0, baseline.bestWeight, 0.0)
        assertEquals(80.0 * (1.0 + 10.0 / 30.0), baseline.bestEstimatedOneRepMax, 1e-9)
    }
}
