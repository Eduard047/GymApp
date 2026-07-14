package com.example.gymapp.auth

import com.example.gymapp.data.repository.WorkoutDataLimits
import java.security.MessageDigest
import java.text.Normalizer
import java.util.Locale

private const val LOCAL_DATABASE_V2_PREFIX = "local_v2_"
private const val MAX_LOCAL_DISPLAY_NAME_UTF8_BYTES =
    WorkoutDataLimits.MAX_ACCOUNT_IDENTIFIER_LENGTH * 4

internal fun validatedLocalDisplayNameOrNull(value: String): String? {
    if (value.length > WorkoutDataLimits.MAX_ACCOUNT_IDENTIFIER_LENGTH * 2) return null
    val trimmed = value.trim()
    val normalized = Normalizer.normalize(trimmed, Normalizer.Form.NFC)
    if (normalized.isEmpty() || normalized.any(Char::isISOControl)) return null
    if (
        normalized.codePointCount(0, normalized.length) !in
        1..WorkoutDataLimits.MAX_ACCOUNT_IDENTIFIER_LENGTH
    ) {
        return null
    }
    if (
        WorkoutDataLimits.utf8ByteLengthAtMost(
            normalized,
            MAX_LOCAL_DISPLAY_NAME_UTF8_BYTES
        ) == null
    ) {
        return null
    }
    return trimmed
}

internal fun normalizedLocalDisplayNameOrNull(value: String): String? =
    validatedLocalDisplayNameOrNull(value)
        ?.let { Normalizer.normalize(it, Normalizer.Form.NFC) }

internal fun localDatabaseLogicalName(displayName: String): String? {
    val normalized = normalizedLocalDisplayNameOrNull(displayName)
        ?.lowercase(Locale.ROOT)
        ?: return null
    return LOCAL_DATABASE_V2_PREFIX + localIdentityDigest(
        "GymAppLocalDatabaseV2\u0000$normalized"
    )
}

/** Exact historical filename algorithm, retained only for safe legacy aliasing. */
internal fun legacyLocalDatabaseName(displayName: String): String? {
    val validated = validatedLocalDisplayNameOrNull(displayName) ?: return null
    val raw = "local_${validated.lowercase().trim()}"
    return raw.replace(Regex("[^A-Za-z0-9_.-]"), "_")
        .ifBlank { "local_default" }
}

internal fun isLocalDatabaseLogicalName(value: String): Boolean =
    value.length == LOCAL_DATABASE_V2_PREFIX.length + 64 &&
        value.startsWith(LOCAL_DATABASE_V2_PREFIX) &&
        value.drop(LOCAL_DATABASE_V2_PREFIX.length).all {
            it in '0'..'9' || it in 'a'..'f'
        }

internal fun localIdentityDigest(value: String): String = MessageDigest.getInstance("SHA-256")
    .digest(value.toByteArray(Charsets.UTF_8))
    .joinToString(separator = "") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }
