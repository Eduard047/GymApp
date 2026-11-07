package com.example.gymapp.ui.components

import com.example.gymapp.ui.viewmodel.ExerciseTrendChartPointUiModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TrendChartDescriptionTest {
    private fun point(weight: Double, volume: Double) = ExerciseTrendChartPointUiModel(
        sessionId = 1,
        label = "",
        shortLabel = "",
        maxWeight = weight,
        totalVolume = volume,
        totalReps = 0,
        weightLabel = "",
        volumeLabel = "",
        repsLabel = "",
        weightRatio = 0f,
        volumeRatio = 0f
    )

    @Test
    fun rangeIsFirstLatestAndBest() {
        val points = listOf(point(60.0, 100.0), point(72.5, 300.0), point(70.0, 200.0))
        assertEquals(TrendChartRange(60.0, 70.0, 72.5), trendChartRange(points, ExerciseTrendChartPointUiModel::maxWeight))
        assertEquals(TrendChartRange(100.0, 200.0, 300.0), trendChartRange(points, ExerciseTrendChartPointUiModel::totalVolume))
    }

    @Test
    fun rangeIsNullWithoutPoints() {
        assertNull(trendChartRange(emptyList(), ExerciseTrendChartPointUiModel::maxWeight))
    }

    @Test
    fun descriptionJoinsTitleTrendAndRange() {
        assertEquals(
            "Max Weight Trend. +10 kg vs first session. First 60, latest 70, best 72.5",
            trendChartDescription("Max Weight Trend", "+10 kg vs first session", "First 60, latest 70, best 72.5")
        )
    }

    @Test
    fun descriptionSkipsBlankParts() {
        assertEquals("Volume by Session", trendChartDescription("Volume by Session", "  ", null))
        assertEquals("Volume by Session. Holding steady", trendChartDescription(" Volume by Session ", "Holding steady", ""))
    }
}
