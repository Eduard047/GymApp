package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AuthScreenTest {
    @Test
    fun loginValidationRejectsMissingInput() {
        assertEquals(
            "Enter your email.",
            validateLoginInput(
                email = "",
                password = "Password1"
            )
        )
        assertEquals(
            "Enter a valid email address.",
            validateLoginInput(
                email = "not-email",
                password = "Password1"
            )
        )
        assertEquals(
            "Enter your password.",
            validateLoginInput(
                email = "ed@example.com",
                password = ""
            )
        )
    }

    @Test
    fun loginValidationAcceptsNormalInput() {
        assertNull(
            validateLoginInput(
                email = "ed@example.com",
                password = "Password1"
            )
        )
    }

    @Test
    fun signUpValidationRejectsInvalidInput() {
        assertEquals(
            "Enter your email.",
            validateSignUpInput(
                email = "",
                emailConfirm = "",
                password = "Password1",
                passwordConfirm = "Password1",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Enter a valid email address.",
            validateSignUpInput(
                email = "not-email",
                emailConfirm = "not-email",
                password = "Password1",
                passwordConfirm = "Password1",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Password must be at least 8 characters.",
            validateSignUpInput(
                email = "ed@example.com",
                emailConfirm = "ed@example.com",
                password = "Pass1",
                passwordConfirm = "Pass1",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Password must include letters and numbers.",
            validateSignUpInput(
                email = "ed@example.com",
                emailConfirm = "ed@example.com",
                password = "Password",
                passwordConfirm = "Password",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Passwords do not match.",
            validateSignUpInput(
                email = "ed@example.com",
                emailConfirm = "ed@example.com",
                password = "Password1",
                passwordConfirm = "Password2",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Email does not match.",
            validateSignUpInput(
                email = "ed@example.com",
                emailConfirm = "other@example.com",
                password = "Password1",
                passwordConfirm = "Password1",
                displayName = "Ed"
            )
        )
    }

    @Test
    fun signUpValidationAcceptsNormalAccount() {
        assertNull(
            validateSignUpInput(
                email = " Ed@Example.COM ",
                emailConfirm = "ed@example.com",
                password = "Password1",
                passwordConfirm = "Password1",
                displayName = "Ed"
            )
        )
    }

    @Test
    fun resendConfirmationValidationRequiresValidEmail() {
        assertEquals(
            "Enter your email.",
            validateConfirmationEmailInput("")
        )
        assertEquals(
            "Enter a valid email address.",
            validateConfirmationEmailInput("not-email")
        )
        assertNull(validateConfirmationEmailInput(" Ed@Example.COM "))
    }

    @Test
    fun recoveryValidationRequiresValidEmail() {
        assertEquals("Enter your email.", validateRecoveryEmailInput(""))
        assertEquals("Enter a valid email address.", validateRecoveryEmailInput("not-email"))
        assertNull(validateRecoveryEmailInput(" Ed@Example.COM "))
    }

    @Test
    fun passwordUpdateValidationRequiresMatchingStrongPasswords() {
        assertEquals(
            "Enter a new password.",
            validatePasswordUpdateInput("", "")
        )
        assertEquals(
            "Password must be 8-72 characters.",
            validatePasswordUpdateInput("Pass1", "Pass1")
        )
        assertEquals(
            "Password must include letters and numbers.",
            validatePasswordUpdateInput("Password", "Password")
        )
        assertEquals(
            "Passwords do not match.",
            validatePasswordUpdateInput("Password1", "Password2")
        )
        assertNull(validatePasswordUpdateInput("Password1", "Password1"))
    }
}
