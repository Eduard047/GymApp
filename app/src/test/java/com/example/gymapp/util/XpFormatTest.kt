package com.example.gymapp.util

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class XpFormatTest {
    @Test
    fun englishUsesCommaGrouping() {
        assertEquals("1,422", formatXp(1422, Locale.forLanguageTag("en")))
        assertEquals("950", formatXp(950, Locale.forLanguageTag("en")))
    }

    @Test
    fun ukrainianAndRussianUseSpaceGrouping() {
        // Locale data uses a no-break space (U+00A0 or U+202F) as the group separator.
        val groupSeparator = Regex("[\\u00A0\\u202F ]")
        assertEquals(listOf("1", "422"), formatXp(1422, Locale.forLanguageTag("uk")).split(groupSeparator))
        assertEquals(listOf("1", "422"), formatXp(1422, Locale.forLanguageTag("ru")).split(groupSeparator))
        assertEquals("950", formatXp(950, Locale.forLanguageTag("ru")))
    }
}
