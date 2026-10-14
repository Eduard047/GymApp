package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    @Test
    fun movingADraftSwapsItWithItsNeighbourAndKeepsTheOthers() {
        val drafts = (1L..4L).map { ExerciseInputState(draftId = it) }
        assertEquals(listOf(1L, 3L, 2L, 4L), movedExerciseDraft(drafts, 2L, 1)!!.map { it.draftId })
        assertEquals(listOf(2L, 1L, 3L, 4L), movedExerciseDraft(drafts, 2L, -1)!!.map { it.draftId })
        assertEquals(drafts[2], movedExerciseDraft(drafts, 3L, -1)!![1])
    }

    @Test
    fun movingPastAnEdgeOrAnUnknownDraftChangesNothing() {
        val drafts = (1L..3L).map { ExerciseInputState(draftId = it) }
        assertNull(movedExerciseDraft(drafts, 1L, -1))
        assertNull(movedExerciseDraft(drafts, 3L, 1))
        assertNull(movedExerciseDraft(drafts, 99L, 1))
        assertNull(movedExerciseDraft(drafts, 2L, 0))
        assertNull(movedExerciseDraft(emptyList(), 1L, 1))
    }

    @Test
    fun movingADraftToAnAbsoluteSlotShiftsTheOthersInBothDirections() {
        val drafts = (1L..5L).map { ExerciseInputState(draftId = it) }
        assertEquals(listOf(2L, 3L, 4L, 1L, 5L), movedExerciseDraftTo(drafts, 1L, 3)!!.map { it.draftId })
        assertEquals(listOf(4L, 1L, 2L, 3L, 5L), movedExerciseDraftTo(drafts, 4L, 0)!!.map { it.draftId })
        assertEquals(listOf(1L, 2L, 3L, 5L, 4L), movedExerciseDraftTo(drafts, 4L, 4)!!.map { it.draftId })
        assertEquals(drafts[2], movedExerciseDraftTo(drafts, 3L, 0)!![0])
    }

    @Test
    fun movingADraftToItsOwnSlotOutOfRangeOrUnknownChangesNothing() {
        val drafts = (1L..3L).map { ExerciseInputState(draftId = it) }
        assertNull(movedExerciseDraftTo(drafts, 2L, 1))
        assertNull(movedExerciseDraftTo(drafts, 2L, -1))
        assertNull(movedExerciseDraftTo(drafts, 2L, 3))
        assertNull(movedExerciseDraftTo(drafts, 99L, 0))
        assertNull(movedExerciseDraftTo(emptyList(), 1L, 0))
    }
}
