package com.example.gymapp.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PasswordPolicyTest {
    @Test
    fun acceptsPasswordsFromSixCharactersUpToSeventyTwoBytes() {
        assertTrue(isValidNewPassword("abcdef"))
        assertTrue(isValidNewPassword("a".repeat(72)))
        assertTrue(isValidNewPassword("x".repeat(12) + "\uD83D\uDE42".repeat(15)))
    }

    @Test
    fun rejectsPasswordsOutsideLengthBounds() {
        assertFalse(isValidNewPassword(""))
        assertFalse(isValidNewPassword("abcde"))
        assertFalse(isValidNewPassword("a".repeat(73)))
        assertFalse(isValidNewPassword("x".repeat(12) + "\uD83D\uDE42".repeat(16)))
    }

    @Test
    fun countsCodePointsForTheMinimumAndUtf8BytesForTheMaximum() {
        assertTrue(isValidNewPassword("\uD83D\uDE42".repeat(6)))
        assertFalse(isValidNewPassword("\uD83D\uDE42".repeat(5)))
        assertTrue(isValidNewPassword("ж".repeat(36)))
        assertFalse(isValidNewPassword("ж".repeat(37)))
    }

    @Test
    fun hasNoCharacterClassRequirements() {
        assertTrue(isValidNewPassword("abcdef"))
        assertTrue(isValidNewPassword("ABCDEF"))
        assertTrue(isValidNewPassword("123456"))
        assertTrue(isValidNewPassword("!!!!!!"))
        assertTrue(isValidNewPassword("пароль"))
        assertTrue(isValidNewPassword("with space"))
    }

    @Test
    fun detectsServerWeakPasswordRejections() {
        assertTrue(isWeakPasswordError("weak_password", null))
        assertTrue(isWeakPasswordError("WEAK_PASSWORD", "anything"))
        assertTrue(isWeakPasswordError(null, "Weak password: should contain letters"))
        assertTrue(isWeakPasswordError("validation_failed", "weak password"))
        assertFalse(isWeakPasswordError("same_password", "New password should be different"))
        assertFalse(isWeakPasswordError(null, null))
    }

    @Test
    fun policyErrorTextMatchesTheSixCharacterRule() {
        assertEquals(
            "Password must contain at least 6 characters and fit within 72 UTF-8 bytes.",
            NEW_PASSWORD_POLICY_ERROR
        )
    }
}
