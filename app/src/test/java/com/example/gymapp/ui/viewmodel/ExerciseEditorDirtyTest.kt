package com.example.gymapp.ui.viewmodel

import com.example.gymapp.data.repository.ExerciseLoadDirection
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExerciseEditorDirtyTest {
    @Test
    fun renameIsCleanForSameOrPaddedName() {
        assertFalse(isRenameExerciseDirty("Bench Press", "Bench Press"))
        assertFalse(isRenameExerciseDirty("Bench Press", "  Bench Press "))
    }

    @Test
    fun renameIsDirtyWhenTextChanges() {
        assertTrue(isRenameExerciseDirty("Bench Press", "Incline Bench Press"))
        assertTrue(isRenameExerciseDirty("Bench Press", ""))
    }

    @Test
    fun loadProfileIsCleanWhenNothingChanged() {
        assertFalse(
            isLoadProfileEditorDirty(
                ExerciseLoadDirection.HigherIsHarder, "10\n20", ExerciseLoadDirection.HigherIsHarder, "10\n20\n"
            )
        )
    }

    @Test
    fun loadProfileIsDirtyOnWeightsOrDirectionChange() {
        assertTrue(
            isLoadProfileEditorDirty(
                ExerciseLoadDirection.HigherIsHarder, "10\n20", ExerciseLoadDirection.HigherIsHarder, "10\n25"
            )
        )
        assertTrue(
            isLoadProfileEditorDirty(
                ExerciseLoadDirection.HigherIsHarder, "", ExerciseLoadDirection.LowerIsHarder, ""
            )
        )
    }
}
