package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

class WorkoutDetailPresentationTest {
    @Test
    fun completedWorkoutStartsWithNoExpandedExerciseAndUsesAccordionToggling() {
        var expandedExerciseId: Long? = null

        expandedExerciseId = nextExpandedWorkoutExerciseId(expandedExerciseId, 10L)
        assertEquals(10L, expandedExerciseId)

        expandedExerciseId = nextExpandedWorkoutExerciseId(expandedExerciseId, 20L)
        assertEquals(20L, expandedExerciseId)

        expandedExerciseId = nextExpandedWorkoutExerciseId(expandedExerciseId, 20L)
        assertNull(expandedExerciseId)
    }

    @Test
    fun readModeHasNoMutationOrTimerControls() {
        val controls = workoutDetailControlVisibility(isEditingWorkout = false)

        assertFalse(controls.showAddExercise)
        assertFalse(controls.showEditDetails)
        assertFalse(controls.showRemoveExercise)
        assertFalse(controls.showAddSet)
        assertFalse(controls.showSetActions)
        assertFalse(controls.showDeleteWorkout)
        assertFalse(controls.showRestTimer)
        assertFalse(controls.showLogSetAndRest)
    }

    @Test
    fun editModeAllowsCorrectionsButNeverRestTimerActions() {
        val controls = workoutDetailControlVisibility(isEditingWorkout = true)

        assertTrue(controls.showAddExercise)
        assertTrue(controls.showEditDetails)
        assertTrue(controls.showRemoveExercise)
        assertTrue(controls.showAddSet)
        assertTrue(controls.showSetActions)
        assertTrue(controls.showDeleteWorkout)
        assertFalse(controls.showRestTimer)
        assertFalse(controls.showLogSetAndRest)
    }

    @Test
    fun lastExerciseOfAWorkoutCannotBeRemoved() {
        assertFalse(canRemoveWorkoutExercise(0))
        assertFalse(canRemoveWorkoutExercise(1))
        assertTrue(canRemoveWorkoutExercise(2))
    }

    @Test
    fun pickedDayKeepsTheWorkoutTimeOfDay() {
        val zone = ZoneId.of("Europe/Kyiv")
        val existing = LocalDateTime.of(2026, 3, 10, 18, 45).atZone(zone).toInstant().toEpochMilli()
        val pickedUtc = LocalDate.of(2026, 3, 14).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

        val updated = workoutDateWithPickedDay(existing, pickedUtc, zone)

        assertEquals(
            LocalDateTime.of(2026, 3, 14, 18, 45),
            Instant.ofEpochMilli(updated).atZone(zone).toLocalDateTime()
        )
    }

    @Test
    fun pickerPreselectsTheLocalDayEvenLateInTheEvening() {
        val zone = ZoneId.of("America/Los_Angeles")
        val existing = LocalDateTime.of(2026, 3, 10, 23, 30).atZone(zone).toInstant().toEpochMilli()

        val utcMillis = datePickerUtcMillisForWorkout(existing, zone)

        assertEquals(
            LocalDate.of(2026, 3, 10),
            Instant.ofEpochMilli(utcMillis).atZone(ZoneOffset.UTC).toLocalDate()
        )
        assertEquals(existing, workoutDateWithPickedDay(existing, utcMillis, zone))
    }
}
