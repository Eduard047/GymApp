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

    return normalized.toDoubleOrNull()
}
