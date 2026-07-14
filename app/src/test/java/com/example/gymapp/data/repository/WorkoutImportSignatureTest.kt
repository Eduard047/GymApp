package com.example.gymapp.data.repository

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class WorkoutImportSignatureTest {
    @Test
    fun attackerControlledNoteCannotImitateStructuredExerciseFields() {
        val date = 1_750_000_000_000L
        val firstExerciseId = 41L
        val secondExerciseId = 42L

        fun legacyDelimiterSignature(
            note: String,
            exercises: List<WorkoutExerciseDraft>
        ): String = buildString {
            append(date).append('|').append(note)
            exercises.forEach { exercise ->
                append('|').append(exercise.exerciseId)
                exercise.sets.forEach { set ->
                    append(':').append(set.weight).append('x').append(set.reps)
                }
            }
        }

        val noteInjectedDraft = listOf(
            WorkoutExerciseDraft(
                exerciseId = secondExerciseId,
                sets = listOf(WorkoutSetDraft(weight = 2.0, reps = 2))
            )
        )
        val genuineDraft = listOf(
            WorkoutExerciseDraft(
                exerciseId = firstExerciseId,
                sets = listOf(WorkoutSetDraft(weight = 1.0, reps = 1))
            ),
            WorkoutExerciseDraft(
                exerciseId = secondExerciseId,
                sets = listOf(WorkoutSetDraft(weight = 2.0, reps = 2))
            )
        )
        assertEquals(
            legacyDelimiterSignature("x|$firstExerciseId:1.0x1", noteInjectedDraft),
            legacyDelimiterSignature("x", genuineDraft)
        )

        val noteInjected = workoutImportSignature(
            date = date,
            note = "x|$firstExerciseId:1.0x1",
            workoutExercises = noteInjectedDraft
        )
        val genuineTwoExerciseWorkout = workoutImportSignature(
            date = date,
            note = "x",
            workoutExercises = genuineDraft
        )

        assertNotEquals(noteInjected, genuineTwoExerciseWorkout)
    }

    @Test
    fun signatureUsesTheSameNoteAndZeroCanonicalizationAsPersistence() {
        val workout = listOf(
            WorkoutExerciseDraft(
                exerciseId = 1L,
                sets = listOf(WorkoutSetDraft(weight = 0.0, reps = 1))
            )
        )

        assertEquals(
            workoutImportSignature(1_750_000_000_000L, null, workout),
            workoutImportSignature(1_750_000_000_000L, " \t\n", workout)
        )
        assertEquals(
            workoutImportSignature(1_750_000_000_000L, "saved note", workout),
            workoutImportSignature(1_750_000_000_000L, "  saved note  ", workout)
        )
        assertEquals(
            workoutImportSignature(1_750_000_000_000L, null, workout),
            workoutImportSignature(
                1_750_000_000_000L,
                null,
                listOf(
                    WorkoutExerciseDraft(
                        exerciseId = 1L,
                        sets = listOf(WorkoutSetDraft(weight = -0.0, reps = 1))
                    )
                )
            )
        )
    }
}
