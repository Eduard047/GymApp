package com.example.gymapp.ui.screens

import com.example.gymapp.R
import com.example.gymapp.data.repository.DuplicateExerciseNameException
import org.junit.Assert.assertEquals
import org.junit.Test

class RenameExerciseErrorTest {
    @Test
    fun duplicateRenameShowsTheNameAlreadyExistsMessage() {
        val kind = newExerciseErrorFor(DuplicateExerciseNameException())
        assertEquals(NewExerciseError.Duplicate, kind)
        assertEquals(
            R.string.exercise_picker_create_error_duplicate,
            renameExerciseErrorMessageRes(kind)
        )
    }

    @Test
    fun otherRenameFailuresKeepTheGenericMessage() {
        val kind = newExerciseErrorFor(IllegalArgumentException("Exercise name is outside the supported length."))
        assertEquals(NewExerciseError.Invalid, kind)
        assertEquals(R.string.message_exercise_error, renameExerciseErrorMessageRes(kind))
        assertEquals(R.string.message_exercise_error, renameExerciseErrorMessageRes(null))
    }
}
