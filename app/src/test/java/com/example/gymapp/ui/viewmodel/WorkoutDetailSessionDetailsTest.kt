package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.data.repository.normalizedWorkoutNote
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutDetailSessionDetailsTest {
    @Test
    fun noteIsTrimmedAndBlankBecomesNull() {
        assertEquals("Felt strong", normalizedWorkoutNote("  Felt strong \n"))
        assertNull(normalizedWorkoutNote("   \n\t"))
        assertNull(normalizedWorkoutNote(""))
        assertNull(normalizedWorkoutNote(null))
    }

    @Test
    fun acceptsRegularDateAndNote() {
        assertTrue(isValidWorkoutDetailsInput(1_788_685_200_000, "Leg day"))
        assertTrue(isValidWorkoutDetailsInput(1_788_685_200_000, ""))
        assertTrue(isValidWorkoutDetailsInput(1_788_685_200_000, "Line one\nLine two"))
    }

    @Test
    fun rejectsDateOutsideTheSupportedRange() {
        assertFalse(isValidWorkoutDetailsInput(WorkoutDataLimits.MIN_TIMESTAMP_MILLIS - 1, "x"))
        assertFalse(isValidWorkoutDetailsInput(WorkoutDataLimits.MAX_TIMESTAMP_MILLIS + 1, "x"))
    }

    @Test
    fun rejectsOverlongOrControlCharacterNotes() {
        assertTrue(isValidWorkoutDetailsInput(0L, "a".repeat(WorkoutDataLimits.MAX_NOTE_LENGTH)))
        assertFalse(isValidWorkoutDetailsInput(0L, "a".repeat(WorkoutDataLimits.MAX_NOTE_LENGTH + 1)))
        assertFalse(isValidWorkoutDetailsInput(0L, "bad\u0000note"))
    }
}
