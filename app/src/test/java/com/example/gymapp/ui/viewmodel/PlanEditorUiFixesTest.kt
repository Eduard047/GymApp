package com.example.gymapp.ui.viewmodel

import com.example.gymapp.ui.screens.activeWorkoutFinishNeedsConfirmation
import com.example.gymapp.ui.screens.retainedDraftSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PlanEditorUiFixesTest {
    private fun draft(id: Long, exerciseId: Long?, vararg sets: Pair<String, String>) =
        ExerciseInputState(
            draftId = id,
            exerciseId = exerciseId,
            sets = sets.map { SetInputState(it.first, it.second) }
        )

    @Test
    fun appendWithExerciseCreatesSelectedCardAtTheEnd() {
        val result = appendExerciseDraft(listOf(draft(1, 5, "50" to "8")), 2L, exerciseId = 9L)
        assertEquals(listOf(1L, 2L), result.map { it.draftId })
        assertEquals(9L, result.last().exerciseId)
    }

    @Test
    fun initialWeightIsSeededOnlyIntoUntouchedFirstSet() {
        val fresh = listOf(draft(1, 5, "" to ""))
        assertEquals("62.5", withInitialWeightIfBlank(fresh, 1L, 62.5).single().sets.single().weight)
        assertEquals("60", withInitialWeightIfBlank(fresh, 1L, 60.0).single().sets.single().weight)
        val typed = listOf(draft(1, 5, "70" to ""))
        assertEquals(typed, withInitialWeightIfBlank(typed, 1L, 60.0))
        assertEquals(fresh, withInitialWeightIfBlank(fresh, 2L, 60.0))
    }

    @Test
    fun invalidStartFieldsMarkOnlyBadFieldsOfSelectedExercises() {
        val drafts = listOf(
            draft(1, 5, "50" to "8"),
            draft(2, 6, "" to "10", "40" to "0"),
            draft(3, null, "" to "")
        )
        val invalid = invalidStartFields(drafts)
        assertEquals(
            setOf(
                SetFieldKey(2, 0, SetInputField.Weight),
                SetFieldKey(2, 1, SetInputField.Reps)
            ),
            invalid
        )
        assertEquals(2L, firstInvalidStartDraftId(drafts, invalid))
    }

    @Test
    fun firstInvalidDraftFallsBackToFirstCardWhenNothingIsSelected() {
        val drafts = listOf(draft(4, null, "" to ""), draft(5, null, "" to ""))
        assertEquals(4L, firstInvalidStartDraftId(drafts, emptySet()))
        assertNull(firstInvalidStartDraftId(listOf(draft(1, 5, "50" to "8")), emptySet()))
    }

    @Test
    fun retainedDraftSummaryReflectsCurrentSelectedCardsAndSets() {
        val drafts = listOf(
            draft(1, 5, "50" to "8", "50" to "8", "50" to "8"),
            draft(2, 6, "20" to "10"),
            draft(3, null, "" to "")
        )
        val summary = retainedDraftSummary(drafts)!!
        assertEquals(2, summary.exerciseCount)
        assertEquals(4, summary.setCount)
        assertNull(retainedDraftSummary(listOf(draft(3, null, "" to ""))))
    }

    @Test
    fun finishAsksOnlyWhenSomePlannedSetIsNotDone() {
        assertTrue(activeWorkoutFinishNeedsConfirmation(completedSetCount = 3, totalSetCount = 12))
        assertFalse(activeWorkoutFinishNeedsConfirmation(completedSetCount = 12, totalSetCount = 12))
        assertFalse(activeWorkoutFinishNeedsConfirmation(completedSetCount = 0, totalSetCount = 0))
    }
}
