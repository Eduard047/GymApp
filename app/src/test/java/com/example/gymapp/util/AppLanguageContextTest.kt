package com.example.gymapp.util

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppLanguageContextTest {
    @Test
    fun appCompatLocaleWinsOverSavedChoice() {
        val locale = resolveAppLocale(Locale.forLanguageTag("uk"), "ru", sdkInt = 30)
        assertEquals("uk", locale?.language)
    }

    @Test
    fun savedChoiceIsUsedBelowApi33WhenAppCompatHasNone() {
        assertEquals("ru", resolveAppLocale(null, "ru", sdkInt = 30)?.language)
        assertEquals("uk", resolveAppLocale(null, "uk", sdkInt = 32)?.language)
    }

    @Test
    fun api33AndAboveTrustTheSystemPerAppLocale() {
        assertNull(resolveAppLocale(null, "ru", sdkInt = 33))
    }

    @Test
    fun unknownOrMissingSavedChoiceLeavesContextAlone() {
        assertNull(resolveAppLocale(null, null, sdkInt = 30))
        assertNull(resolveAppLocale(null, "de", sdkInt = 30))
    }

    @Test
    fun sameLanguageNeedsNoNewContext() {
        assertTrue(isSameLanguage(Locale.forLanguageTag("uk-UA"), Locale.forLanguageTag("uk")))
        assertFalse(isSameLanguage(Locale.ENGLISH, Locale.forLanguageTag("uk")))
        assertFalse(isSameLanguage(null, Locale.ENGLISH))
    }
}
