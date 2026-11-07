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

/**
 * Text a weight field should show once editing ends. Blank or unparseable text reverts to the
 * last valid text (like iPhone's number field), so clearing the field never silently writes 0 kg;
 * an explicit "0" is valid and stays. With no earlier valid text the input is kept unchanged.
 */
fun resolveWeightFieldCommit(text: String, lastValid: String?): String =
    if (parseWeightInputOrNull(text) != null) text else lastValid ?: text

private const val MAX_WEIGHT_INPUT_LENGTH = 64
