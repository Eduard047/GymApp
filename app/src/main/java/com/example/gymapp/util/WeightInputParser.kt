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

/**
 * Drops leading zeros that sit in front of another digit while a weight is typed: "006" -> "6",
 * "0060" -> "60", "00.5" -> "0.5". A lone "0", "0.5", "0,5", blank text and anything without a
 * leading zero are returned unchanged; the decimal-separator rules stay with [parseWeightInputOrNull].
 */
fun normalizeWeightInput(input: String): String = LEADING_ZEROS.replaceFirst(input, "")

/** [normalizeWeightInput] applied to an edit, with the selection moved by the zeros that were dropped. */
data class NormalizedWeightEdit(val text: String, val selectionStart: Int, val selectionEnd: Int)

fun normalizeWeightEdit(text: String, selectionStart: Int, selectionEnd: Int): NormalizedWeightEdit {
    val normalized = normalizeWeightInput(text)
    val removed = text.length - normalized.length
    return NormalizedWeightEdit(
        text = normalized,
        selectionStart = (selectionStart - removed).coerceIn(0, normalized.length),
        selectionEnd = (selectionEnd - removed).coerceIn(0, normalized.length)
    )
}

private val LEADING_ZEROS = Regex("^0+(?=[0-9])")

private const val MAX_WEIGHT_INPUT_LENGTH = 64
