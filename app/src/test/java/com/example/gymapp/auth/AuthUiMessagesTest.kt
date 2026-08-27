package com.example.gymapp.auth

import com.example.gymapp.R
import org.junit.Assert.assertEquals
import org.junit.Test

class AuthUiMessagesTest {
    @Test
    fun boundedAuthAndCloudErrorsMapToStableLocalizedResources() {
        val cases = listOf(
            "Too many authentication emails were requested. Try again later, or contact support if the newest email never arrives." to
                R.string.auth_error_too_many_emails,
            "An account with this email already exists. Log in instead." to
                R.string.auth_error_account_exists,
            "Email or password is incorrect." to R.string.auth_error_invalid_credentials,
            "Email confirmation may be required before login." to
                R.string.auth_error_email_unconfirmed,
            "Confirm your email first, then log in." to R.string.auth_error_email_unconfirmed,
            "Cloud login is temporarily unavailable. Try again later." to
                R.string.auth_error_cloud_unavailable,
            "Cloud request failed. Check your connection and try again." to
                R.string.auth_error_connection,
            NEW_PASSWORD_POLICY_ERROR to
                R.string.auth_error_password_policy,
            "Password is too long." to
                R.string.auth_error_password_too_long,
            "Display name can use letters, numbers, spaces, dot, dash and underscore." to
                R.string.auth_error_display_name_characters,
            "Enter a valid email address." to R.string.auth_error_email_invalid,
            "Authentication rejected an unsafe or malformed callback. Request a new email." to
                R.string.auth_error_callback_invalid,
            "This authentication request was not started on this device or has expired. Request a new email." to
                R.string.auth_error_callback_expired,
            "Authentication link did not contain a valid authorization code. Request a new email." to
                R.string.auth_error_callback_code_invalid,
            "Authentication returned a different account. Request a new email." to
                R.string.auth_error_callback_account_mismatch,
            "Authentication returned an invalid session. Request a new email." to
                R.string.auth_error_invalid_session,
            "Password recovery session is no longer available. Request a new reset email." to
                R.string.auth_error_recovery_session_unavailable,
            "This cloud session is no longer active. Sign in again before syncing." to
                R.string.auth_error_session_inactive,
            "Cloud data changed on another device. Reload it before syncing again." to
                R.string.cloud_sync_conflict,
            "Cloud account changed while confirming the sync baseline." to
                R.string.cloud_sync_account_changed,
            "Could not persist the cloud sync baseline. Automatic upload is paused." to
                R.string.cloud_sync_baseline_failed,
            "Cloud state did not round-trip safely. Automatic upload is paused." to
                R.string.cloud_sync_round_trip_failed
        )

        cases.forEach { (message, expectedResource) ->
            assertEquals(
                message,
                expectedResource,
                authErrorText(IllegalStateException(message), R.string.auth_message_login_failed)
                    .resourceId
            )
        }
    }

    @Test
    fun unknownOrMissingProviderMessagesUseTheCallerFallback() {
        val fallback = R.string.auth_message_callback_failed

        assertEquals(
            fallback,
            authErrorText(IllegalStateException("provider-specific private detail"), fallback).resourceId
        )
        assertEquals(fallback, authErrorText(IllegalStateException(), fallback).resourceId)
    }

    @Test
    fun emailConfirmationRequirementIsSeparatedFromActualLoginErrors() {
        assertEquals(
            true,
            requiresEmailConfirmation(
                IllegalStateException("Confirm your email first, then log in.")
            )
        )
        assertEquals(
            true,
            requiresEmailConfirmation(
                IllegalStateException("Email confirmation may be required before login.")
            )
        )
        assertEquals(
            false,
            requiresEmailConfirmation(IllegalStateException("Email or password is incorrect."))
        )
    }
}
