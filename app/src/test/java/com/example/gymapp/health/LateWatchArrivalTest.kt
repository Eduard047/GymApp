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
    fun identicalSetsToleranceEdgeAfterStoredEnd() {
        val storedEnd = start + 45 * minute
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(arrivalStart = storedEnd + tolerance, arrivalSets = phoneSets, candidates = listOf(stored()))
        )
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(arrivalStart = storedEnd + tolerance + 1, arrivalSets = phoneSets, candidates = listOf(stored()))
        )
    }

    @Test
    fun identicalSetsToleranceEdgeBeforeStoredStart() {
        // Arrival ends exactly tolerance before the stored start: still overlapping; 1 ms earlier: not.
        val duration = 30 * 60L
        val arrivalEndAtEdge = start - tolerance
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(
                arrivalStart = arrivalEndAtEdge - duration * 1_000L,
                arrivalDurationSeconds = duration,
                arrivalSets = phoneSets,
                candidates = listOf(stored())
            )
        )
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(
                arrivalStart = arrivalEndAtEdge - duration * 1_000L - 1,
                arrivalDurationSeconds = duration,
                arrivalSets = phoneSets,
                candidates = listOf(stored())
            )
        )
    }

    @Test
    fun identicalSetsAgainstStoredWorkoutWithoutDurationUseItsStartOnly() {
        val candidate = stored(durationSeconds = null)
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(
                arrivalStart = start + tolerance,
                arrivalDurationSeconds = null,
                arrivalSets = phoneSets,
                candidates = listOf(candidate)
            )
        )
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(
                arrivalStart = start + tolerance + 1,
                arrivalDurationSeconds = null,
                arrivalSets = phoneSets,
                candidates = listOf(candidate)
            )
        )
    }

    @Test
    fun backToBackActivityOnlyArrivalIsStored() {
        // Phone strength 10:00-11:00, watch run 11:01-11:31: a separate session, inside the tolerance.
        val phone = stored(durationSeconds = 60 * 60L)
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(
                arrivalStart = start + 61 * minute,
                arrivalDurationSeconds = 30 * 60L,
                candidates = listOf(phone)
            )
        )
        // Touching end to start (no gap) is still a separate session.
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(
                arrivalStart = start + 60 * minute,
                arrivalDurationSeconds = 30 * 60L,
                candidates = listOf(phone)
            )
        )
    }

    @Test
    fun activityOnlyArrivalCoveredByHalfIsSkipped() {
        // Arrival 30 min; stored 45 min ends 15 min into it -> exactly 50 % covered: skip.
        val phone = stored(durationSeconds = 45 * 60L)
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(
                arrivalStart = start + 30 * minute,
                arrivalDurationSeconds = 30 * 60L,
                candidates = listOf(phone)
            )
        )
        // One millisecond less than half covered: store.
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(
                arrivalStart = start + 30 * minute + 1,
                arrivalDurationSeconds = 30 * 60L,
                candidates = listOf(phone)
            )
        )
    }

    @Test
    fun activityOnlyArrivalNestedInStoredWorkoutIsSkipped() {
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(
                arrivalStart = start + 10 * minute,
                arrivalDurationSeconds = 20 * 60L,
                candidates = listOf(stored(durationSeconds = 60 * 60L))
            )
        )
        // A zero-length arrival inside the stored workout is covered too.
        assertEquals(
            LateWatchArrivalDecision.Skip,
            decide(
                arrivalStart = start + 10 * minute,
                arrivalDurationSeconds = null,
                candidates = listOf(stored(durationSeconds = 60 * 60L))
            )
        )
    }

    @Test
    fun activityOnlyArrivalAgainstStoredWorkoutWithoutDurationIsStored() {
        listOf<Long?>(null, 0L).forEach { storedDuration ->
            val candidate = stored(durationSeconds = storedDuration)
            assertEquals(
                LateWatchArrivalDecision.Store,
                decide(arrivalStart = start - 10 * minute, candidates = listOf(candidate))
            )
            assertEquals(
                LateWatchArrivalDecision.Store,
                decide(arrivalStart = start, arrivalDurationSeconds = null, candidates = listOf(candidate))
            )
        }
    }

    @Test
    fun invalidArrivalStartIsStored() {
        assertEquals(
            LateWatchArrivalDecision.Store,
            decide(arrivalStart = 0L, candidates = listOf(stored(startMillis = 0L)))
        )
    }
}
