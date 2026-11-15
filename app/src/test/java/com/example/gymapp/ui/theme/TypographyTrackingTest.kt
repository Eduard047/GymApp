package com.example.gymapp.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Apple-like scale on the system face: size / line / weight / tracking per Material slot. */
class TypographyTrackingTest {
    private fun tracking(style: TextStyle) = style.letterSpacing.value

    private fun assertScale(style: TextStyle, size: Float, line: Float, weight: FontWeight) {
        assertEquals(size, style.fontSize.value, 0f)
        assertEquals(line, style.lineHeight.value, 0f)
        assertEquals(weight, style.fontWeight)
    }

    @Test
    fun scaleMatchesAppleRoles() {
        assertScale(Typography.displayLarge, 34f, 41f, FontWeight.Bold)
        assertScale(Typography.headlineLarge, 34f, 41f, FontWeight.Bold)
        assertScale(Typography.headlineMedium, 22f, 28f, FontWeight.SemiBold)
        assertScale(Typography.titleLarge, 22f, 28f, FontWeight.SemiBold)
        assertScale(Typography.titleMedium, 17f, 22f, FontWeight.SemiBold)
        assertScale(Typography.bodyLarge, 17f, 22f, FontWeight.Normal)
        assertScale(Typography.bodyMedium, 15f, 20f, FontWeight.Normal)
        assertScale(Typography.bodySmall, 13f, 18f, FontWeight.Normal)
        assertScale(Typography.labelMedium, 13f, 18f, FontWeight.Medium)
        assertScale(Typography.labelSmall, 12f, 16f, FontWeight.Medium)
    }

    @Test
    fun noRoleIsSmallerThanTwelve() {
        val all = with(Typography) {
            listOf(
                displayLarge, displayMedium, displaySmall, headlineLarge, headlineMedium, headlineSmall,
                titleLarge, titleMedium, titleSmall, bodyLarge, bodyMedium, bodySmall,
                labelLarge, labelMedium, labelSmall
            )
        }
        assertTrue(all.all { it.fontSize.value >= 12f })
    }

    @Test
    fun onlyLargeTitlesTighten() {
        assertEquals(-0.68f, tracking(Typography.displayLarge), 0f)
        assertEquals(-0.68f, tracking(Typography.headlineLarge), 0f)
        assertEquals(-0.22f, tracking(Typography.headlineMedium), 0f)
        assertEquals(-0.22f, tracking(Typography.titleLarge), 0f)
    }

    @Test
    fun zeroFromThirteenToTwentySp() {
        assertEquals(0f, tracking(Typography.headlineSmall), 0f)
        assertEquals(0f, tracking(Typography.titleMedium), 0f)
        assertEquals(0f, tracking(Typography.titleSmall), 0f)
        assertEquals(0f, tracking(Typography.bodyLarge), 0f)
        assertEquals(0f, tracking(Typography.bodyMedium), 0f)
        assertEquals(0f, tracking(Typography.bodySmall), 0f)
        assertEquals(0f, tracking(Typography.labelLarge), 0f)
        assertEquals(0f, tracking(Typography.labelMedium), 0f)
        assertEquals(0f, tracking(GymDataTypography), 0f)
    }

    @Test
    fun captionLoosensSlightly() {
        assertEquals(0.1f, tracking(Typography.labelSmall), 0f)
    }
}
