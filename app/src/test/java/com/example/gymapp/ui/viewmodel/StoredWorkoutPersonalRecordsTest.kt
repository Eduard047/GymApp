package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.entity.ExerciseEntity
import com.example.gymapp.data.entity.ExerciseHistoryEntry
import com.example.gymapp.data.entity.SetEntryEntity
import com.example.gymapp.data.entity.WorkoutExerciseEntity
import com.example.gymapp.data.entity.WorkoutExerciseWithDetails
import com.example.gymapp.data.entity.WorkoutSessionDetails
import com.example.gymapp.data.entity.WorkoutSessionEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StoredWorkoutPersonalRecordsTest {
    private val sessionId = 10L
    private val sessionDate = 1_000L

    private fun details(vararg sets: Pair<Double, Int>): WorkoutSessionDetails {
        val workoutExercise = WorkoutExerciseEntity(
            id = 100L,
            sessionId = sessionId,
            exerciseId = 1L,
            orderIndex = 0
        )
        return WorkoutSessionDetails(
            session = WorkoutSessionEntity(id = sessionId, date = sessionDate, note = null),
            workoutExercises = listOf(
                WorkoutExerciseWithDetails(
                    workoutExercise = workoutExercise,
                    exercise = ExerciseEntity(id = 1L, name = "Bench Press"),
                    sets = sets.mapIndexed { index, (weight, reps) ->
                        SetEntryEntity(
                            id = 1_000L + index,
                            workoutExerciseId = 100L,
                            weight = weight,
                            reps = reps,
                            orderIndex = index
                        )
                    }
                )
            )
        )
    }

    private fun prior(setId: Long, session: Long, date: Long, weight: Double, reps: Int) =
        ExerciseHistoryEntry(
            setId = setId,
            sessionId = session,
            sessionDate = date,
            exerciseId = 1L,
            exerciseName = "Bench Press",
            weight = weight,
            reps = reps,
            setOrderIndex = 0
        )

    @Test
    fun firstSessionOfAnExerciseHasNoRecords() {
        val detail = details(60.0 to 8, 80.0 to 5)

        assertEquals(emptySet<Long>(), storedWorkoutPersonalRecordSetIds(detail, emptyList()))
        assertFalse(storedWorkoutPersonalRecordFlags(detail, emptyList()).getValue(100L))
    }

    @Test
    fun laterWorkoutsAndTheWorkoutItselfAreNotBaseline() {
        val history = listOf(
            prior(1, session = 11, date = 2_000L, weight = 200.0, reps = 5), // later workout
            prior(2, session = sessionId, date = sessionDate, weight = 90.0, reps = 5) // itself
        )

        assertTrue(storedWorkoutPersonalRecordSetIds(details(90.0 to 5), history).isEmpty())
    }

    @Test
    fun weightRecordMustBeStrictlyHeavierAndRunningBestIsUsed() {
        val history = listOf(prior(1, session = 5, date = 500L, weight = 60.0, reps = 5))
        // 60 x5 ties the best weight and its estimate; 70 x5 beats it; 70 x5 again only matches.
        val detail = details(60.0 to 5, 70.0 to 5, 70.0 to 5)

        assertEquals(setOf(1_001L), storedWorkoutPersonalRecordSetIds(detail, history))
        assertTrue(storedWorkoutPersonalRecordFlags(detail, history).getValue(100L))
    }

    @Test
    fun estimatedOneRepMaxRecordWithoutHeavierWeightCounts() {
        val history = listOf(prior(1, session = 5, date = 500L, weight = 60.0, reps = 5))

        assertEquals(
            setOf(1_000L),
            storedWorkoutPersonalRecordSetIds(details(60.0 to 10), history)
        )
    }

    @Test
    fun zeroKilogramSetsNeverCountAsRecords() {
        val history = listOf(prior(1, session = 5, date = 500L, weight = 0.0, reps = 5))

        assertTrue(storedWorkoutPersonalRecordSetIds(details(0.0 to 30), history).isEmpty())
    }
}
