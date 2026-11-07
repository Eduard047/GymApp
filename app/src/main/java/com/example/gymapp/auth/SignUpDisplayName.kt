package com.example.gymapp.auth

internal const val SIGN_UP_DISPLAY_NAME_MIN_CODE_POINTS = 2
internal const val SIGN_UP_DISPLAY_NAME_MAX_CODE_POINTS = 32

internal const val SIGN_UP_DISPLAY_NAME_LENGTH_ERROR = "Display name must be 2-32 characters."
internal const val SIGN_UP_DISPLAY_NAME_CHARACTERS_ERROR =
    "Display name can use letters, numbers, spaces, dot, dash and underscore."
internal const val SIGN_UP_DISPLAY_NAME_RULES_ERROR =
    "Name can't contain links or long numbers and needs a letter or digit."

internal enum class SignUpDisplayNameRejection { LENGTH, CHARACTERS, SERVER_RULES }

internal sealed interface SignUpDisplayNameCheck {
    data class Valid(val name: String) : SignUpDisplayNameCheck
    data class Rejected(val reason: SignUpDisplayNameRejection) : SignUpDisplayNameCheck
}

internal fun SignUpDisplayNameRejection.message(): String = when (this) {
    SignUpDisplayNameRejection.LENGTH -> SIGN_UP_DISPLAY_NAME_LENGTH_ERROR
    SignUpDisplayNameRejection.CHARACTERS -> SIGN_UP_DISPLAY_NAME_CHARACTERS_ERROR
    SignUpDisplayNameRejection.SERVER_RULES -> SIGN_UP_DISPLAY_NAME_RULES_ERROR
}

/**
 * True when the profile upsert was refused by the server's display-name trigger
 * (enforce_profile_public_fields -> safe_leaderboard_display_name raises SQLSTATE 23514
 * "Display name violates the leaderboard safety policy."). The failure is deterministic: a
 * retry with the same name is refused again, so callers surface [SIGN_UP_DISPLAY_NAME_RULES_ERROR].
 */
internal fun isDisplayNameSafetyRejection(errorCode: String?, providerMessage: String?): Boolean =
    errorCode == "23514" &&
        providerMessage?.contains("leaderboard safety policy", ignoreCase = true) == true &&
        providerMessage.contains("display name", ignoreCase = true)

// Static rules of public.safe_leaderboard_display_name (supabase/migrations/
// 20260711084556_create_leaderboard_public.sql), applied to the already trimmed and
// collapsed name. The dynamic leaderboard_blocked_terms table cannot be mirrored.
private val SERVER_LINK_PATTERN = Regex(
    "(https?://|www[.]|discord[.]gg|t[.]me/|[\\p{L}\\p{Nd}_-]+[.](com|net|org|io|gg)(/|\\z))",
    RegexOption.IGNORE_CASE
)
private const val SERVER_MAX_ASCII_DIGITS = 6

private fun isSignUpNameSpace(codePoint: Int): Boolean =
    Character.isWhitespace(codePoint) || Character.isSpaceChar(codePoint)

private fun isSignUpNameLetterOrDigit(codePoint: Int): Boolean =
    Character.isLetter(codePoint) || Character.getType(codePoint) == Character.DECIMAL_DIGIT_NUMBER.toInt()

private inline fun String.forEachSignUpCodePoint(action: (Int) -> Unit) {
    var index = 0
    while (index < length) {
        val codePoint = codePointAt(index)
        index += Character.charCount(codePoint)
        action(codePoint)
    }
}

/** Trims and collapses every whitespace run to one space, like the server does. */
internal fun normalizeSignUpDisplayName(value: String): String {
    val result = StringBuilder(value.length)
    var previousWasSpace = false
    value.forEachSignUpCodePoint { codePoint ->
        if (isSignUpNameSpace(codePoint)) {
            if (!previousWasSpace) result.append(' ')
            previousWasSpace = true
        } else {
            result.appendCodePoint(codePoint)
            previousWasSpace = false
        }
    }
    return result.toString().trim(' ')
}

/**
 * Local validation of a sign-up display name: the client alphabet and the stricter
 * 32 code point cap, plus the static server rules so the profile upsert trigger
 * cannot reject an accepted name. Shared vectors: shared/display-name-v1.json.
 */
internal fun checkSignUpDisplayName(raw: String): SignUpDisplayNameCheck {
    var hasControl = false
    raw.forEachSignUpCodePoint { codePoint ->
        if (Character.getType(codePoint) == Character.CONTROL.toInt()) hasControl = true
    }
    val name = normalizeSignUpDisplayName(raw)
    val length = name.codePointCount(0, name.length)
    if (length !in SIGN_UP_DISPLAY_NAME_MIN_CODE_POINTS..SIGN_UP_DISPLAY_NAME_MAX_CODE_POINTS) {
        return SignUpDisplayNameCheck.Rejected(SignUpDisplayNameRejection.LENGTH)
    }
    var onlyAllowed = !hasControl
    var hasLetterOrDigit = false
    var asciiDigits = 0
    name.forEachSignUpCodePoint { codePoint ->
        val letterOrDigit = isSignUpNameLetterOrDigit(codePoint)
        if (letterOrDigit) hasLetterOrDigit = true
        if (codePoint in '0'.code..'9'.code) asciiDigits += 1
        if (!(letterOrDigit || codePoint == ' '.code || codePoint == '.'.code ||
                codePoint == '-'.code || codePoint == '_'.code)
        ) {
            onlyAllowed = false
        }
    }
    if (!onlyAllowed) {
        return SignUpDisplayNameCheck.Rejected(SignUpDisplayNameRejection.CHARACTERS)
    }
    if (!hasLetterOrDigit ||
        name.indexOf('@') >= 0 ||
        asciiDigits > SERVER_MAX_ASCII_DIGITS ||
        SERVER_LINK_PATTERN.containsMatchIn(name)
    ) {
        return SignUpDisplayNameCheck.Rejected(SignUpDisplayNameRejection.SERVER_RULES)
    }
    return SignUpDisplayNameCheck.Valid(name)
}
