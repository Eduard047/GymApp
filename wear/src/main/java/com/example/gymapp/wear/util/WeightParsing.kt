package com.example.gymapp.wear.util

fun parseWeightInputOrNull(input: String): Double? {
    val normalized = input.trim().replace(',', '.')
    if (normalized.isBlank()) {
        return 0.0
    }
    return normalized.toDoubleOrNull()
}
