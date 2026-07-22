package com.example.gymapp.auth

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PasswordPolicyTest {
    @Test
    fun acceptsBoundedPasswordsWithEveryRequiredCharacterGroup() {
        assertTrue(isValidNewPassword("SecurePass9!"))
        assertTrue(isValidNewPassword("Aa1!" + "x".repeat(68)))
        assertTrue(isValidNewPassword("Aa1!" + "x".repeat(8) + "🙂".repeat(15)))
    }

    @Test
    fun rejectsPasswordsOutsideLengthBounds() {
        assertFalse(isValidNewPassword("Short1!Aa"))
        assertFalse(isValidNewPassword("Aa1!" + "x".repeat(69)))
        assertFalse(isValidNewPassword("Aa1!" + "x".repeat(8) + "🙂".repeat(16)))
    }

    @Test
    fun requiresAsciiLowercaseUppercaseDigitAndSupabaseSymbol() {
        assertFalse(isValidNewPassword("SECUREPASS9!"))
        assertFalse(isValidNewPassword("securepass9!"))
        assertFalse(isValidNewPassword("SecurePass!!"))
        assertFalse(isValidNewPassword("SecurePass9🙂"))
        assertFalse(isValidNewPassword("ПарольSecure9🙂"))
    }

    @Test
    fun acceptsEverySymbolSupportedBySupabasePasswordSettings() {
        val supportedSymbols = "!@#\$%^&*()_+-=[]{};'\\:\"|<>?,./`~"
        supportedSymbols.forEach { symbol ->
            assertTrue("Expected '$symbol' to be supported", isValidNewPassword("SecurePass9$symbol"))
        }
    }
}
