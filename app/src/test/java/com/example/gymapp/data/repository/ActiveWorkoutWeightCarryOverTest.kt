package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ActiveWorkoutSetEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ActiveWorkoutWeightCarryOverTest {
    private fun set(id: String, order: Int, weight: Double = 0.0, completedAt: Long? = null) =
        ActiveWorkoutSetEntity(
            id = id,
            activeWorkoutExerciseId = "ex",
            weight = weight,
            reps = 8,
            orderIndex = order,
            completedAt = completedAt
        )

    @Test
    fun nextPendingUnplannedSetInheritsRecordedWeight() {
        val sets = listOf(set("a", 0), set("b", 1), set("c", 2))

        assertEquals("b", ActiveWorkoutWeightCarryOver.target(sets, "a", 60.0)?.id)
    }

    @Test
    fun skipsCompletedSetsAndUsesOrderNotListPosition() {
        val sets = listOf(
            set("c", 2),
            set("a", 0),
            set("b", 1, weight = 55.0, completedAt = 10L)
        )

        assertEquals("c", ActiveWorkoutWeightCarryOver.target(sets, "a", 60.0)?.id)
    }

    @Test
    fun plannedNonZeroWeightIsNeverOverwritten() {
        val sets = listOf(set("a", 0), set("b", 1, weight = 50.0), set("c", 2))

        assertNull(ActiveWorkoutWeightCarryOver.target(sets, "a", 60.0))
    }

    @Test
    fun zeroRecordedWeightCarriesNothing() {
        assertNull(ActiveWorkoutWeightCarryOver.target(listOf(set("a", 0), set("b", 1)), "a", 0.0))
    }

    @Test
    fun lastSetOrUnknownSetHasNoTarget() {
        val sets = listOf(set("a", 0), set("b", 1))

        assertNull(ActiveWorkoutWeightCarryOver.target(sets, "b", 60.0))
        assertNull(ActiveWorkoutWeightCarryOver.target(sets, "missing", 60.0))
    }
}
