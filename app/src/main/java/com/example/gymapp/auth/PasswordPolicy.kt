package com.example.gymapp.auth

internal const val NEW_PASSWORD_MIN_CODE_POINTS = 6
internal const val NEW_PASSWORD_MAX_UTF8_BYTES = 72

internal const val NEW_PASSWORD_POLICY_ERROR =
    "Password must contain at least 6 characters and fit within 72 UTF-8 bytes."

internal const val WEAK_PASSWORD_SERVER_ERROR =
    "The new password does not meet the server password policy."

internal fun newPasswordLengthIsValid(password: String): Boolean {
    val characterCount = password.codePointCount(0, password.length)
    return characterCount >= NEW_PASSWORD_MIN_CODE_POINTS &&
        password.toByteArray(Charsets.UTF_8).size <= NEW_PASSWORD_MAX_UTF8_BYTES
}

internal fun isValidNewPassword(password: String): Boolean = newPasswordLengthIsValid(password)

/** True when the auth provider rejected a new password against its own server-side policy. */
internal fun isWeakPasswordError(errorCode: String?, providerMessage: String?): Boolean =
    errorCode.equals("weak_password", ignoreCase = true) ||
        providerMessage?.contains("weak password", ignoreCase = true) == true
