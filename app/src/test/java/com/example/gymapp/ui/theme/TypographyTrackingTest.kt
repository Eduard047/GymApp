package com.example.gymapp.ui.theme

import org.junit.Assert.assertEquals
import org.junit.Test

/** DESIGN.md `type` tracking per role, in sp. */
class TypographyTrackingTest {
    private fun tracking(style: androidx.compose.ui.text.TextStyle) = style.letterSpacing.value

    @Test
    fun negativeAtDisplayHeadlineAndTitles() {
        assertEquals(-0.6f, tracking(Typography.headlineLarge), 0f)
        assertEquals(-0.4f, tracking(Typography.headlineMedium), 0f)
        assertEquals(-0.2f, tracking(Typography.titleLarge), 0f)
        assertEquals(-0.1f, tracking(Typography.titleMedium), 0f)
    }

    @Test
    fun zeroForBodyAndData() {
        assertEquals(0f, tracking(Typography.titleSmall), 0f)
        assertEquals(0f, tracking(Typography.bodyLarge), 0f)
        assertEquals(0f, tracking(Typography.bodyMedium), 0f)
        assertEquals(0f, tracking(Typography.bodySmall), 0f)
        assertEquals(0f, tracking(GymDataTypography), 0f)
    }

    @Test
    fun slightlyPositiveAtLabelsAndSmallSizes() {
        assertEquals(0.1f, tracking(Typography.labelLarge), 0f)
        assertEquals(0.2f, tracking(Typography.labelMedium), 0f)
        assertEquals(0.3f, tracking(Typography.labelSmall), 0f)
    }
}
