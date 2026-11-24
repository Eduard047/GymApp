package com.example.gymapp.health

import org.junit.Assert.assertEquals
import org.junit.Test

class LateWatchArrivalTest {

    private val start = 1_800_000_000_000L
    private val minute = 60 * 1_000L
    private val tolerance = HealthImportRules.OVERLAP_TOLERANCE_MILLIS

    private val phoneSets = listOf(
        LateWatchSet("Bench Press", 60.0, 10),
        LateWatchSet("Bench Press", 62.5, 8),
        LateWatchSet("Squat", 100.0, 5)
    )

    private fun stored(
        startMillis: Long = start,
        durationSeconds: Long? = 45 * 60L,
        sets: List<LateWatchSet> = phoneSets
    ) = LateWatchStoredWorkout(startMillis, durationSeconds, sets)

    private fun decide(
        arrivalStart: Long = start,
        arrivalDurationSeconds: Long? = 45 * 60L,
        arrivalSets: List<LateWatchSet> = emptyList(),
        candidates: List<LateWatchStoredWorkout>
    ) = LateWatchArrivalRule.decide(arrivalStart, arrivalDurationSeconds, arrivalSets, candidates)

    @Test
    fun activityOnlyArrivalOverlappingWorkoutWithSetsIsSkipped() {
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(arrivalStart = start + 2 * minute, candidates = listOf(stored()))
        )
    }

    @Test
    fun activityOnlyArrivalWithoutOverlapIsStored() {
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(arrivalStart = start + 3 * 60 * minute, candidates = listOf(stored()))
        )
        assertEquals(LateWatchArrivalDecision.Store, decide(candidates = emptyList()))
    }

    @Test
    fun activityOnlyArrivalOverlappingWorkoutWithoutSetsIsStored() {
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(candidates = listOf(stored(sets = emptyList())))
        )
    }

    @Test
    fun identicalSetsAreSkipped() {
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(arrivalSets = phoneSets, candidates = listOf(stored()))
        )
    }

    @Test
    fun identicalSetsIgnoreNameCaseAndWhitespace() {
        val arrival = listOf(
            LateWatchSet("  bench press ", 60.0, 10),
            LateWatchSet("BENCH PRESS", 62.5, 8),
            LateWatchSet("squat", 100.0, 5)
        )
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(arrivalSets = arrival, candidates = listOf(stored()))
        )
    }

    @Test
    fun interleavedArrivalMatchesTheGroupedStoredOrder() {
        // The phone stores a watch workout's sets grouped per exercise in first-seen order.
        val arrival = listOf(
            LateWatchSet("Bench Press", 60.0, 10),
            LateWatchSet("Squat", 100.0, 5),
            LateWatchSet("Bench Press", 62.5, 8)
        )
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(arrivalSets = arrival, candidates = listOf(stored()))
        )
    }

    @Test
    fun differentRepsWeightNameCountOrOrderAreStored() {
        val variants = listOf(
            phoneSets.mapIndexed { i, s -> if (i == 1) s.copy(reps = 9) else s },
            phoneSets.mapIndexed { i, s -> if (i == 2) s.copy(weight = 102.5) else s },
            phoneSets.mapIndexed { i, s -> if (i == 2) s.copy(exerciseName = "Front Squat") else s },
            phoneSets.dropLast(1),
            phoneSets + LateWatchSet("Squat", 100.0, 5),
            listOf(phoneSets[1], phoneSets[0], phoneSets[2]),
            listOf(phoneSets[2], phoneSets[0], phoneSets[1])
        )
        variants.forEach { arrival ->
            assertEquals(
                arrival.toString(),
                LateWatchArrivalDecision.Store,
                decide(arrivalSets = arrival, candidates = listOf(stored()))
            )
        }
    }

    @Test
    fun identicalSetsWithoutOverlapAreStored() {
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(
                arrivalStart = start + 3 * 60 * minute,
                arrivalSets = phoneSets,
                candidates = listOf(stored())
            )
        )
    }

    @Test
    fun anyOverlappingCandidateWithIdenticalSetsSkips() {
        val other = stored(startMillis = start + minute, sets = listOf(LateWatchSet("Row", 50.0, 12)))
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(arrivalSets = phoneSets, candidates = listOf(other, stored()))
        )
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(arrivalSets = phoneSets, candidates = listOf(other))
        )
    }

    @Test
    fun toleranceEdgeAfterStoredEnd() {
        val storedEnd = start + 45 * minute
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(arrivalStart = storedEnd + tolerance, candidates = listOf(stored()))
        )
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(arrivalStart = storedEnd + tolerance + 1, candidates = listOf(stored()))
        )
    }

    @Test
    fun toleranceEdgeBeforeStoredStart() {
        // Arrival ends exactly tolerance before the stored start: still overlapping; 1 ms earlier: not.
        val duration = 30 * 60L
        val arrivalEndAtEdge = start - tolerance
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(
                arrivalStart = arrivalEndAtEdge - duration * 1_000L,
                arrivalDurationSeconds = duration,
                candidates = listOf(stored())
            )
        )
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(
                arrivalStart = arrivalEndAtEdge - duration * 1_000L - 1,
                arrivalDurationSeconds = duration,
                candidates = listOf(stored())
            )
        )
    }

    @Test
    fun storedWorkoutWithoutDurationUsesItsStartOnly() {
        val candidate = stored(durationSeconds = null)
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(arrivalStart = start + tolerance, arrivalDurationSeconds = null, candidates = listOf(candidate))
        )
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(arrivalStart = start + tolerance + 1, arrivalDurationSeconds = null, candidates = listOf(candidate))
        )
    }

    @Test
    fun invalidArrivalStartIsStored() {
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(arrivalStart = 0L, candidates = listOf(stored(startMillis = 0L)))
        )
    }
}
