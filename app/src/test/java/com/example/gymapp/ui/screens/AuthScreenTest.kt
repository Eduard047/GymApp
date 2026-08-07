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
                password = "legacy1"
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
            "Password must contain at least 12 characters and fit within 72 UTF-8 bytes.",
            validateSignUpInput(
                email = "ed@example.com",
                emailConfirm = "ed@example.com",
                password = "Pass1",
                passwordConfirm = "Pass1",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Password must include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol.",
            validateSignUpInput(
                email = "ed@example.com",
                emailConfirm = "ed@example.com",
                password = "PasswordOnly",
                passwordConfirm = "PasswordOnly",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Passwords do not match.",
            validateSignUpInput(
                email = "ed@example.com",
                emailConfirm = "ed@example.com",
                password = "SecurePass9!",
                passwordConfirm = "SecurePass8!",
                displayName = "Ed"
            )
        )
        assertEquals(
            "Email does not match.",
            validateSignUpInput(
                email = "ed@example.com",
                emailConfirm = "other@example.com",
                password = "SecurePass9!",
                passwordConfirm = "SecurePass9!",
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
                password = "SecurePass9!",
                passwordConfirm = "SecurePass9!",
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
    fun localProfileValidationAllowsTheDefaultAndRejectsUnsafeNames() {
        assertNull(validateLocalAccountInput(""))
        assertNull(validateLocalAccountInput("Local Athlete"))
        assertEquals(
            "Local profile name is invalid or too long.",
            validateLocalAccountInput("bad\u0000name")
        )
    }

    @Test
    fun passwordUpdateValidationRequiresMatchingStrongPasswords() {
        assertEquals(
            "Enter a new password.",
            validatePasswordUpdateInput("", "")
        )
        assertEquals(
            "Password must contain at least 12 characters and fit within 72 UTF-8 bytes.",
            validatePasswordUpdateInput("Pass1", "Pass1")
        )
        assertEquals(
            "Password must include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol.",
            validatePasswordUpdateInput("PasswordOnly", "PasswordOnly")
        )
        assertEquals(
            "Passwords do not match.",
            validatePasswordUpdateInput("SecurePass9!", "SecurePass8!")
        )
        assertNull(validatePasswordUpdateInput("SecurePass9!", "SecurePass9!"))
    }


    @Test
    fun signedInPasswordChangeRequiresCurrentAndDifferentNewPassword() {
        assertEquals(
            "Enter your current password.",
            validateSignedInPasswordChange("", "SecurePass9!", "SecurePass9!")
        )
        assertEquals(
            "Choose a new password that differs from the current password.",
            validateSignedInPasswordChange(
                "SecurePass9!",
                "SecurePass9!",
                "SecurePass9!"
            )
        )
        assertNull(
            validateSignedInPasswordChange(
                "CurrentPass8!",
                "NewSecurePass9!",
                "NewSecurePass9!"
            )
        )
        assertEquals(
            "Enter the verification code sent to your email.",
            validateSignedInPasswordChange(
                currentPassword = "CurrentPass8!",
                newPassword = "NewSecurePass9!",
                repeatedPassword = "NewSecurePass9!",
                nonce = "12345",
                nonceRequired = true
            )
        )
        assertNull(
            validateSignedInPasswordChange(
                currentPassword = "CurrentPass8!",
                newPassword = "NewSecurePass9!",
                repeatedPassword = "NewSecurePass9!",
                nonce = "123456",
                nonceRequired = true
            )
        )
    }
}
