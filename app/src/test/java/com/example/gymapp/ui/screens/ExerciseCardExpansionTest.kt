package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ExerciseCardExpansionTest {
    private fun update(
        entering: Boolean,
        fully: Boolean,
        latest: Boolean,
        wasFully: Boolean = false,
        wasLatest: Boolean = false,
        initiallyExpanded: Boolean = false
    ) = exerciseCardExpansionUpdate(entering, fully, latest, wasFully, wasLatest, initiallyExpanded)

    @Test
    fun enteringKeepsOnlyTheCurrentAndLatestSetExercisesOpen() {
        assertEquals(true, update(entering = true, fully = false, latest = false, initiallyExpanded = true))
        assertEquals(true, update(entering = true, fully = true, latest = true))
        assertEquals(true, update(entering = true, fully = false, latest = true))
        assertEquals(false, update(entering = true, fully = true, latest = false))
        assertEquals(false, update(entering = true, fully = false, latest = false))
    }

    @Test
    fun recordingTheLastSetKeepsTheCardOpenForConfirmationAndUndo() {
        assertEquals(true, update(entering = false, fully = true, latest = true, wasFully = false, wasLatest = true))
    }

    @Test
    fun aFullyRecordedCardCollapsesWhenALaterSetBecomesTheLatestOne() {
        assertEquals(false, update(entering = false, fully = true, latest = false, wasFully = true, wasLatest = true))
    }

    @Test
    fun unchangedStateKeepsWhatTheUserToggled() {
        assertNull(update(entering = false, fully = true, latest = false, wasFully = true, wasLatest = false))
        assertNull(update(entering = false, fully = true, latest = true, wasFully = true, wasLatest = true))
        assertNull(update(entering = false, fully = false, latest = true, wasLatest = true))
    }

    @Test
    fun recordingASetInAnUnfinishedCardExpandsIt() {
        assertEquals(true, update(entering = false, fully = false, latest = true, wasLatest = false))
    }
}
