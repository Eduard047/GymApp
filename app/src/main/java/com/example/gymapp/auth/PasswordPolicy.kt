package com.example.gymapp.auth

internal const val NEW_PASSWORD_POLICY_ERROR =
    "Password must contain at least 12 characters, fit within 72 UTF-8 bytes, and include a lowercase Latin letter, an uppercase Latin letter, a number, and a supported symbol."

private const val SUPABASE_PASSWORD_SYMBOLS = "!@#\$%^&*()_+-=[]{};'\\:\"|<>?,./`~"

internal fun newPasswordLengthIsValid(password: String): Boolean {
    val characterCount = password.codePointCount(0, password.length)
    return characterCount >= 12 && password.toByteArray(Charsets.UTF_8).size <= 72
}

internal fun newPasswordCharacterGroupsAreValid(password: String): Boolean {
    return password.any { it in 'a'..'z' } &&
        password.any { it in 'A'..'Z' } &&
        password.any { it in '0'..'9' } &&
        password.any { it in SUPABASE_PASSWORD_SYMBOLS }
}

internal fun isValidNewPassword(password: String): Boolean {
    return newPasswordLengthIsValid(password) && newPasswordCharacterGroupsAreValid(password)
}
