package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppendExerciseDraftTest {
    @Test
    fun firstDraftIntoEmptyListBecomesTheOnlyEntry() {
        val result = appendExerciseDraft(emptyList(), draftId = 1L)
        assertEquals(listOf(1L), result.map { it.draftId })
        assertTrue(result.single().exerciseId == null)
    }

    @Test
    fun newDraftsAreAppendedSoInsertionOrderIsKept() {
        var drafts = emptyList<ExerciseInputState>()
        for (id in 1L..4L) {
            drafts = appendExerciseDraft(drafts, id)
        }
        assertEquals(listOf(1L, 2L, 3L, 4L), drafts.map { it.draftId })
    }

    @Test
    fun appendingDoesNotReorderOrReplaceExistingDrafts() {
        val existing = appendExerciseDraft(appendExerciseDraft(emptyList(), 7L), 3L)
        val result = appendExerciseDraft(existing, 9L)
        assertEquals(listOf(7L, 3L, 9L), result.map { it.draftId })
        assertEquals(existing, result.take(existing.size))
    }
}
