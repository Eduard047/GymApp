package com.example.gymapp.util

import com.example.gymapp.data.repository.WorkoutDataLimits

/**
 * Parses weight input allowing both comma and dot as decimal separators.
 * Returns null for blank or invalid values. Bodyweight/no-added-load sets use the explicit text
 * value `0`, so clearing the field cannot silently change a workout.
 */
fun parseWeightInputOrNull(input: String): Double? {
    val normalized = input
        .trim()
        .replace(',', '.')

    if (normalized.isBlank()) return null
    if (normalized.length > MAX_WEIGHT_INPUT_LENGTH) {
        return null
    }

    return normalized.toDoubleOrNull()?.takeIf(WorkoutDataLimits::isValidWeight)
}

private const val MAX_WEIGHT_INPUT_LENGTH = 64
