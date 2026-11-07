package com.example.gymapp.service

import androidx.annotation.StringRes
import com.example.gymapp.R

private const val MAX_EXERCISE_LABEL_CHARS = 80

/** The exercise name for the finished alert, or null when the alert should stay generic. */
internal fun restFinishedExerciseLabel(rawName: String?, displayName: (String) -> String): String? {
    val raw = rawName?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    val label = displayName(raw).trim().takeIf { it.isNotEmpty() } ?: return null
    return label.take(MAX_EXERCISE_LABEL_CHARS)
}

/** The body text for the finished alert: names the exercise when there is one. */
@StringRes
internal fun restFinishedBodyResource(exerciseLabel: String?): Int =
    if (exerciseLabel == null) R.string.timer_notification_finished_text
    else R.string.timer_notification_finished_body_exercise
