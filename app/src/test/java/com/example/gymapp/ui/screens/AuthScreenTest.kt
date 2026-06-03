package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AuthScreenTest {
    @Test
    fun signUpValidationRejectsInvalidInput() {
        assertEquals(
            "Enter your email.",
            validateSignUpInput(
                email = "",
                password = "Password1",
                passwordConfirm = "Password1",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Password must be at least 8 characters.",
            validateSignUpInput(
                email = "ed@example.com",
                password = "Pass1",
                passwordConfirm = "Pass1",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Password must include letters and numbers.",
            validateSignUpInput(
                email = "ed@example.com",
                password = "Password",
                passwordConfirm = "Password",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Passwords do not match.",
            validateSignUpInput(
                email = "ed@example.com",
                password = "Password1",
                passwordConfirm = "Password2",
                displayName = "Ed"
            )
        )
    }

    @Test
    fun signUpValidationAcceptsNormalAccount() {
        assertNull(
            validateSignUpInput(
                email = "ed@example.com",
                password = "Password1",
                passwordConfirm = "Password1",
                displayName = "Ed"
            )
        )
    }
}
