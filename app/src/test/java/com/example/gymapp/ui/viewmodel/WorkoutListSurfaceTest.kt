package com.example.gymapp.ui.viewmodel

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutListSurfaceTest {
    @Test
    fun todayLoadsOnlyTodayPlanDependencies() {
        val surface = WorkoutListSurface.Today

        assertTrue(surface.needsTodayPlan)
        assertTrue(surface.needsMuscleMappings)
        assertFalse(surface.needsProgressInsights)
        assertFalse(surface.needsMissions)
        assertFalse(surface.needsSoloProgress)
        assertFalse(surface.needsRankLadder)
    }

    @Test
    fun progressIncludesOverviewAndGoalsWithoutBuildingTodayOrRanks() {
        val surface = WorkoutListSurface.Progress

        assertFalse(surface.needsTodayPlan)
        assertTrue(surface.needsProgressInsights)
        assertTrue(surface.needsMissions)
        assertTrue(surface.needsSoloProgress)
        assertTrue(surface.needsMuscleMappings)
        assertFalse(surface.needsRankLadder)
    }
}
