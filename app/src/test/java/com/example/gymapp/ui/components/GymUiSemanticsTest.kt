package com.example.gymapp.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test
import androidx.compose.ui.unit.dp

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

    @Test
    fun adaptivePaddingKeepsPhoneMarginsAndCentersWideContent() {
        assertEquals(16.dp, adaptiveHorizontalPadding(windowWidth = 360.dp))
        assertEquals(132.dp, adaptiveHorizontalPadding(windowWidth = 1_024.dp))
    }
}
