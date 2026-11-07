package com.example.gymapp.ui.components

import androidx.compose.ui.graphics.Color
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SheetValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalMaterial3Api::class)
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

    @Test
    fun dirtySheetNeverHidesButStillExpandsAndCleanSheetHides() {
        assertFalse(sheetHideAllowed(SheetValue.Hidden, hasUnsavedChanges = true))
        assertTrue(sheetHideAllowed(SheetValue.Expanded, hasUnsavedChanges = true))
        assertTrue(sheetHideAllowed(SheetValue.PartiallyExpanded, hasUnsavedChanges = true))
        assertTrue(sheetHideAllowed(SheetValue.Hidden, hasUnsavedChanges = false))
    }
}
