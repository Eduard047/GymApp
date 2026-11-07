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
