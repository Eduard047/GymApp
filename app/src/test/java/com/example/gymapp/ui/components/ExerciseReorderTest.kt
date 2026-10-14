package com.example.gymapp.ui.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ExerciseReorderTest {
    private val order = listOf("a", "b", "c", "d")

    // Four 100px cards with 16px gaps: tops 0, 116, 232, 348.
    private val bounds = mapOf(
        "a" to ReorderBounds(0f, 100f),
        "b" to ReorderBounds(116f, 100f),
        "c" to ReorderBounds(232f, 100f),
        "d" to ReorderBounds(348f, 100f)
    )

    @Test
    fun reorderedKeysMovesUpAndDownByAnyDistance() {
        assertEquals(listOf("b", "c", "d", "a"), reorderedKeys(order, "a", 3))
        assertEquals(listOf("d", "a", "b", "c"), reorderedKeys(order, "d", 0))
        assertEquals(listOf("a", "c", "b", "d"), reorderedKeys(order, "b", 2))
    }

    @Test
    fun reorderedKeysIgnoresSameSlotOutOfRangeAndUnknownKeys() {
        assertEquals(order, reorderedKeys(order, "b", 1))
        assertEquals(order, reorderedKeys(order, "b", -1))
        assertEquals(order, reorderedKeys(order, "b", 4))
        assertEquals(order, reorderedKeys(order, "zzz", 0))
    }

    @Test
    fun draggedCardSwapsOnlyAfterItsCentreCrossesTheNeighboursMidpoint() {
        val boundsOf = { key: String -> bounds[key] }
        // "b" centre 166; next neighbour "c" midpoint is 282, previous "a" midpoint is 50.
        assertNull(dragSlotTarget(order, "b", 166f, boundsOf))
        assertNull(dragSlotTarget(order, "b", 282f, boundsOf))
        assertEquals(2, dragSlotTarget(order, "b", 283f, boundsOf))
        assertNull(dragSlotTarget(order, "b", 50f, boundsOf))
        assertEquals(0, dragSlotTarget(order, "b", 49f, boundsOf))
    }

    @Test
    fun edgeCardsOnlyLookInTheDirectionThatExists() {
        val boundsOf = { key: String -> bounds[key] }
        assertNull(dragSlotTarget(order, "a", -500f, boundsOf))
        assertNull(dragSlotTarget(order, "d", 5000f, boundsOf))
        assertEquals(1, dragSlotTarget(order, "a", 170f, boundsOf))
        assertEquals(2, dragSlotTarget(order, "d", 100f, boundsOf))
    }

    @Test
    fun notLaidOutNeighboursAndUnknownKeysNeverSwap() {
        assertNull(dragSlotTarget(order, "b", 9999f) { null })
        assertNull(dragSlotTarget(order, "zzz", 100f) { bounds[it] })
    }

    @Test
    fun autoScrollIsZeroInTheMiddleAndGrowsTowardTheEdgesUpToTheCap() {
        val top = 100f
        val bottom = 900f
        assertEquals(0f, autoScrollStep(500f, top, bottom, 64f, 12f), 0f)
        assertEquals(0f, autoScrollStep(164f, top, bottom, 64f, 12f), 0f)
        assertEquals(-6f, autoScrollStep(132f, top, bottom, 64f, 12f), 0.001f)
        assertEquals(-12f, autoScrollStep(100f, top, bottom, 64f, 12f), 0.001f)
        assertEquals(-12f, autoScrollStep(-50f, top, bottom, 64f, 12f), 0.001f)
        assertEquals(6f, autoScrollStep(868f, top, bottom, 64f, 12f), 0.001f)
        assertEquals(12f, autoScrollStep(2000f, top, bottom, 64f, 12f), 0.001f)
    }

    @Test
    fun autoScrollIgnoresAnEmptyViewportOrBand() {
        assertEquals(0f, autoScrollStep(10f, 100f, 100f, 64f, 12f), 0f)
        assertEquals(0f, autoScrollStep(10f, 0f, 500f, 0f, 12f), 0f)
    }
}
