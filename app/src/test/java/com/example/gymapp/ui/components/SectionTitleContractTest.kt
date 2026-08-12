package com.example.gymapp.ui.components

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SectionTitleContractTest {
    @Test
    fun blankEyebrowDoesNotReserveDecorativeCopySpace() {
        assertFalse(sectionTitleShowsEyebrow(""))
        assertFalse(sectionTitleShowsEyebrow("  "))
        assertTrue(sectionTitleShowsEyebrow("Plan"))
    }
}
