package com.example.gymapp.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class GymUiSemanticsTest {
    @Test
    fun spotterLaneKeepsExactNonContiguousPerSetStateForTalkBack() {
        assertEquals(
            listOf(
                SpotterSetSemanticState(ordinal = 1, isCompleted = true),
                SpotterSetSemanticState(ordinal = 2, isCompleted = false),
                SpotterSetSemanticState(ordinal = 3, isCompleted = true),
                SpotterSetSemanticState(ordinal = 4, isCompleted = false)
            ),
            spotterSetSemanticStates(listOf(true, false, true, false))
        )
    }

    @Test
    fun emptyLaneDoesNotInventASetForAccessibility() {
        assertEquals(emptyList<SpotterSetSemanticState>(), spotterSetSemanticStates(emptyList()))
    }
}
