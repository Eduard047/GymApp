package com.example.gymapp.data.catalog

import java.text.Normalizer
import java.util.Locale

/**
 * Portable exercise identity normalization shared with iOS cloud/backup handling.
 *
 * This is intentionally narrower than a search normalizer: accents and character width remain
 * significant so an untrusted label cannot silently become a built-in exercise or another custom
 * exercise. Only compatibility rules already used by GymApp identities are applied.
 */
internal fun normalizeExerciseIdentityName(value: String): String {
    val collapsedWhitespace = buildString(value.length) {
        var pendingSpace = false
        var index = 0
        while (index < value.length) {
            val codePoint = Character.codePointAt(value, index)
            if (
                Character.isWhitespace(codePoint) ||
                Character.isSpaceChar(codePoint) ||
                codePoint == 0x0085
            ) {
                if (isNotEmpty()) pendingSpace = true
            } else {
                if (pendingSpace) {
                    append(' ')
                    pendingSpace = false
                }
                appendCodePoint(codePoint)
            }
            index += Character.charCount(codePoint)
        }
    }
    return Normalizer.normalize(collapsedWhitespace, Normalizer.Form.NFC)
        .lowercase(Locale.ROOT)
        .replace('ʼ', '\'')
        .replace('’', '\'')
        .replace('ё', 'е')
}
