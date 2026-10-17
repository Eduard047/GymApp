package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MetricTilesLayoutTest {
    // Row widths inside the card of a 360dp and a 412dp phone: screen width minus 2*16 gutters and 2*14 card padding.
    private val row360 = 360f - 32f - 28f
    private val row412 = 412f - 32f - 28f

    @Test
    fun contentWidthSubtractsGapPaddingAndBorderOfEveryTile() {
        // (300 - 10) / 2 - 2*12 - 2*1
        assertEquals((300f - 10f) / 2f - 26f, MetricTilesLayout.contentWidthDp(row360), 0.001f)
    }

    @Test
    fun tilesShareARowWhileTheWidestTextFits() {
        // RU "Квадрицепсы" is about 105dp wide at the default font scale, "Главная мышца" about 62dp.
        assertTrue(MetricTilesLayout.sideBySide(row360, listOf(60f, 105f)))
        assertTrue(MetricTilesLayout.sideBySide(row412, listOf(60f, 105f)))
    }

    @Test
    fun tilesStackOnceATextNoLongerFitsHalfTheCard() {
        // At 1.5x the same text is 158dp wide: too wide for the 360dp phone's 119dp, and for the 412dp phone's 135dp.
        assertFalse(MetricTilesLayout.sideBySide(row360, listOf(90f, 158f)))
        assertFalse(MetricTilesLayout.sideBySide(row412, listOf(90f, 158f)))
        // At 1.2x (126dp) it still fits the 412dp phone but not the 360dp one.
        assertFalse(MetricTilesLayout.sideBySide(row360, listOf(72f, 126f)))
        assertTrue(MetricTilesLayout.sideBySide(row412, listOf(72f, 126f)))
    }
}
