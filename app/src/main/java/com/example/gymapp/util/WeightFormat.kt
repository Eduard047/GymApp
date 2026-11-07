package com.example.gymapp.util

import java.text.NumberFormat
import java.util.Locale

/**
 * Weight for an input field: up to 2 decimals, trailing zeros trimmed, no grouping and always
 * a '.' separator ("21.25", "60"), like iPhone. The weight field parser accepts '.' and ','.
 */
fun formatWeightInput(weight: Double): String =
    NumberFormat.getNumberInstance(Locale.US).apply {
        isGroupingUsed = false
        minimumFractionDigits = 0
        maximumFractionDigits = 2
    }.format(weight + 0.0)

/** Weight for display text: up to 2 decimals, no grouping, the given locale's separator ("21,25"). */
fun formatWeightDisplay(weight: Double, locale: Locale = Locale.getDefault()): String =
    NumberFormat.getNumberInstance(locale).apply {
        isGroupingUsed = false
        minimumFractionDigits = 0
        maximumFractionDigits = 2
    }.format(weight + 0.0)

/** Volume total: at most 1 fraction digit with locale grouping ("112.5", "1,000"), like iPhone. */
fun formatVolumeTotal(volume: Double, locale: Locale = Locale.getDefault()): String =
    NumberFormat.getNumberInstance(locale).apply {
        isGroupingUsed = true
        minimumFractionDigits = 0
        maximumFractionDigits = 1
    }.format(volume + 0.0)

/** Whole-kilogram session volume with locale grouping ("10,570", "10 570"), like the post-workout summary. */
fun formatSessionVolume(volume: Double, locale: Locale = Locale.getDefault()): String =
    NumberFormat.getIntegerInstance(locale).format(if (volume.isFinite() && volume > 0.0) volume else 0.0)

private val numberUnitGap = Regex("(?<=\\d) (?=\\p{L})")

/**
 * Replaces the plain space between a digit and a following letter with U+00A0 so a value never
 * wraps away from its unit ("10,570 kg", "1 h 5 min" -> "10,570\u00A0kg", "1\u00A0h 5\u00A0min").
 * Other spaces stay breakable.
 */
fun keepNumberWithUnit(text: String): String = numberUnitGap.replace(text, "\u00A0")
