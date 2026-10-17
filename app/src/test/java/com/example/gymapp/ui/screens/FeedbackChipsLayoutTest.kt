package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FeedbackChipsLayoutTest {
    // Card widths of a 360dp and a 412dp phone: screen width minus the 16dp gutters.
    private val card360 = 360f - 32f
    private val card412 = 412f - 32f
    private val space = 4.5f

    // Word widths (dp at 1.0 font scale, titleSmall semibold): RU "Легко", "В самый раз", "Тяжело", ...
    private val ru = listOf(listOf(46f), listOf(10f, 46f, 26f), listOf(54f))
    private val uk = listOf(listOf(46f), listOf(34f, 24f), listOf(46f))
    private val en = listOf(listOf(36f), listOf(30f, 38f), listOf(38f))

    private fun scaled(labels: List<List<Float>>, scale: Float) = labels.map { words -> words.map { it * scale } }

    @Test
    fun labelWidthSubtractsPaddingAndBorderOfEveryChip() {
        // (328 - 2*14 - 2*8) / 3 - 2*8 - 2*1
        assertEquals((328f - 28f - 16f) / 3f - 18f, FeedbackChipsLayout.labelWidthDp(card360), 0.001f)
    }

    @Test
    fun aLabelNeedsTheBestTwoLineSplit() {
        // "В самый раз": best split is "В самый" / "раз" or "В" / "самый раз"; both are narrower than one line.
        val oneLine = 10f + space + 46f + space + 26f
        val best = FeedbackChipsLayout.minTwoLineWidthDp(listOf(10f, 46f, 26f), space)
        assertTrue(best < oneLine)
        assertEquals(minOf(maxOf(10f + space + 46f, 26f), maxOf(10f, 46f + space + 26f)), best, 0.001f)
        assertEquals(46f, FeedbackChipsLayout.minTwoLineWidthDp(listOf(46f), space), 0.001f)
    }

    @Test
    fun threeChipsShareARowAtTheDefaultFontScaleInEveryLanguage() {
        for (card in listOf(card360, card412)) {
            for (labels in listOf(ru, uk, en)) {
                assertFalse(FeedbackChipsLayout.stacks(card, scaled(labels, 1f), space))
            }
        }
    }

    @Test
    fun theChipsStackOnceALabelNoLongerFitsInTwoLines() {
        // At 1.3x the RU label is wider than the 360dp phone's chip but still fits the 412dp phone's.
        assertTrue(FeedbackChipsLayout.stacks(card360, scaled(ru, 1.3f), space))
        assertFalse(FeedbackChipsLayout.stacks(card412, scaled(ru, 1.3f), space))
        assertTrue(FeedbackChipsLayout.stacks(card412, scaled(ru, 1.8f), space))
    }

    @Test
    fun aLabelExactlyAsWideAsTheChipFits() {
        val width = FeedbackChipsLayout.labelWidthDp(card360)
        assertFalse(FeedbackChipsLayout.stacks(card360, listOf(listOf(width)), space))
        assertTrue(FeedbackChipsLayout.stacks(card360, listOf(listOf(width + 0.01f)), space))
    }
}
