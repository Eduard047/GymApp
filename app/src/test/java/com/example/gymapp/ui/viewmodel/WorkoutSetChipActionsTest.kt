package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Test

class WorkoutSetChipActionsTest {
    private val sets = listOf(
        SetInputState("60", "8"),
        SetInputState("", "10"),
        SetInputState("70", "6")
    )

    @Test
    fun lastWeightOverwritesOnlyTheChosenSet() {
        val result = sets.withLastWeightAt(2, 62.5)
        assertEquals(listOf("60", "", "62.5"), result?.map { it.weight })
        assertEquals(listOf("8", "10", "6"), result?.map { it.reps })
    }

    @Test
    fun lastWeightIsUnavailableWithoutHistoryOrForBadIndex() {
        assertNull(sets.withLastWeightAt(0, null))
        assertNull(sets.withLastWeightAt(5, 50.0))
        assertNull(sets.withLastWeightAt(0, 60.0))
    }

    @Test
    fun previousCopiesWeightAndRepsButNotForTheFirstSet() {
        val result = sets.withPreviousSetCopiedAt(1)
        assertEquals(SetInputState("60", "8"), result?.get(1))
        assertEquals(sets[0], result?.get(0))
        assertEquals(sets[2], result?.get(2))
        assertNull(sets.withPreviousSetCopiedAt(0))
        assertNull(sets.withPreviousSetCopiedAt(9))
    }

    @Test
    fun plusTwoPointFiveAddsToTheChosenSetOnly() {
        val result = sets.withWeightAddedAt(0)
        assertEquals(listOf("62.5", "", "70"), result?.map { it.weight })
        assertEquals("2.5", sets.withWeightAddedAt(1)?.get(1)?.weight)
        assertEquals("72.5", sets.withWeightAddedAt(2)?.get(2)?.weight)
        assertEquals("62", listOf(SetInputState("59,5", "5")).withWeightAddedAt(0)?.first()?.weight)
    }

    @Test
    fun plusTwoPointFiveRejectsInvalidWeightsAndOverflow() {
        assertNull(listOf(SetInputState("abc", "5")).withWeightAddedAt(0))
        assertNull(listOf(SetInputState("1000000", "5")).withWeightAddedAt(0))
        assertNull(sets.withWeightAddedAt(3))
    }

    @Test
    fun duplicateInsertsACopyRightAfterTheSet() {
        val result = sets.withSetDuplicatedAfter(0)
        assertEquals(4, result?.size)
        assertEquals(sets[0], result?.get(1))
        assertEquals(sets[1], result?.get(2))
        assertEquals(sets[2], result?.get(3))
    }

    @Test
    fun duplicateProducesAnIndependentCopy() {
        val original = listOf(SetInputState("60", "8"), SetInputState("70", "6"))
        val duplicated = checkNotNull(original.withSetDuplicatedAfter(0))

        assertEquals(2, original.size)
        assertEquals(3, duplicated.size)
        assertEquals(duplicated[0], duplicated[1])
        assertNotSame(duplicated, original)
        assertNotSame(duplicated[0], duplicated[1])

        // Editing the copy through the pure chip actions must leave the source set untouched.
        val edited = checkNotNull(duplicated.withWeightAddedAt(1))
        assertEquals("60", edited[0].weight)
        assertEquals("62.5", edited[1].weight)
        assertEquals("70", edited[2].weight)
        assertEquals("60", original[0].weight)
        assertEquals("60", duplicated[0].weight)
    }

    @Test
    fun duplicateInTheMiddleKeepsPositionsAndDoesNotTouchNeighbours() {
        val original = listOf(SetInputState("1", "1"), SetInputState("2", "2"), SetInputState("3", "3"))
        val duplicated = checkNotNull(original.withSetDuplicatedAfter(1))

        assertEquals(listOf("1", "2", "2", "3"), duplicated.map { it.weight })
        assertEquals(listOf("1", "2", "3"), original.map { it.weight })
    }

    @Test
    fun duplicateStopsAtTheSetCap() {
        assertNull(sets.withSetDuplicatedAfter(0, maxSets = 3))
        assertNull(sets.withSetDuplicatedAfter(7))
    }
}
