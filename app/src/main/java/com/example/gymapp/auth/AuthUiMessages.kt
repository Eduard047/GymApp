package com.example.gymapp.auth

import androidx.annotation.StringRes
import com.example.gymapp.R
import com.example.gymapp.util.LocalizedText

internal fun requiresEmailConfirmation(error: Throwable): Boolean {
    return error.message in setOf(
        "Email confirmation may be required before login.",
        "Confirm your email first, then log in."
    )
}

/** Converts bounded internal/auth provider failures into safe localized UI copy. */
internal fun authErrorText(
    error: Throwable,
    @StringRes fallbackResource: Int
): LocalizedText {
    val message = error.message.orEmpty()
    val resource = when {
        message == "Too many authentication emails were requested. Try again later, or contact support if the newest email never arrives." ->
            R.string.auth_error_too_many_emails
        message == "An account with this email already exists. Log in instead." ->
            R.string.auth_error_account_exists
        message == "Email or password is incorrect." -> R.string.auth_error_invalid_credentials
        message == "Email confirmation may be required before login." ->
            R.string.auth_error_email_unconfirmed
        message == "Confirm your email first, then log in." -> R.string.auth_error_email_unconfirmed
        message == "Cloud login is temporarily unavailable. Try again later." ->
            R.string.auth_error_cloud_unavailable
        message == "Cloud request failed. Check your connection and try again." ->
            R.string.auth_error_connection
        message == "Password must be 8-72 characters and include letters and numbers." ->
            R.string.auth_error_password_policy
        message == "Display name can use letters, numbers, spaces, dot, dash and underscore." ->
            R.string.auth_error_display_name_characters
        message == "Enter a valid email address." -> R.string.auth_error_email_invalid
        message == "Authentication rejected an unsafe or malformed callback. Request a new email." ->
            R.string.auth_error_callback_invalid
        message == "This authentication request was not started on this device or has expired. Request a new email." ->
            R.string.auth_error_callback_expired
        message == "Authentication link did not contain a valid authorization code. Request a new email." ->
            R.string.auth_error_callback_code_invalid
        message == "Authentication returned a different account. Request a new email." ->
            R.string.auth_error_callback_account_mismatch
        message == "Authentication returned an invalid session. Request a new email." ->
            R.string.auth_error_invalid_session
        message == "Password recovery session is no longer available. Request a new reset email." ->
            R.string.auth_error_recovery_session_unavailable
        message == "This cloud session is no longer active. Sign in again before syncing." ->
            R.string.auth_error_session_inactive
        message == "Cloud data changed on another device. Reload it before syncing again." ->
            R.string.cloud_sync_conflict
        message == "Cloud account changed while confirming the sync baseline." ->
            R.string.cloud_sync_account_changed
        message == "Could not persist the cloud sync baseline. Automatic upload is paused." ->
            R.string.cloud_sync_baseline_failed
        message == "Cloud state did not round-trip safely. Automatic upload is paused." ->
            R.string.cloud_sync_round_trip_failed
        else -> fallbackResource
    }
    return LocalizedText(resource)
}
