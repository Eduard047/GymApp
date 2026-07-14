package com.example.gymapp.util

/**
 * Parses weight input allowing both comma and dot as decimal separators.
 * Returns 0.0 for blank values (optional weight), null for invalid numbers.
 */
fun parseWeightInputOrNull(input: String): Double? {
    val normalized = input
        .trim()
        .replace(',', '.')

    if (normalized.isBlank()) {
        return 0.0
    }
    if (normalized.length > MAX_WEIGHT_INPUT_LENGTH) {
        return null
    }

    return normalized.toDoubleOrNull()?.takeIf(Double::isFinite)
}

private const val MAX_WEIGHT_INPUT_LENGTH = 64
