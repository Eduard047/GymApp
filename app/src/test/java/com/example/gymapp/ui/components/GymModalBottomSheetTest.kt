package com.example.gymapp.ui.components

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Test

class GymModalBottomSheetTest {
    @Test
    fun scrimMatchesDesignTokensPerTheme() {
        assertEquals(Color(0f, 0f, 0f, 0.56f), gymSheetScrimColor(isDark = true))
        assertEquals(Color(7 / 255f, 19 / 255f, 33 / 255f, 0.40f), gymSheetScrimColor(isDark = false))
    }

    @Test
    fun handleMatchesContract() {
        assertEquals(36f, GymSheetHandleWidth.value, 0f)
        assertEquals(5f, GymSheetHandleHeight.value, 0f)
        assertEquals(8f, GymSheetHandleTopPadding.value, 0f)
    }
}
