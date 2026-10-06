package com.example.gymapp.ui.screens

import com.example.gymapp.data.repository.TrainingTools
import com.example.gymapp.data.repository.WorkoutDataLimits
import com.example.gymapp.util.parseWeightInputOrNull
import java.util.Locale
import kotlin.math.abs

/** Catalog keys whose 0 kg history is meaningful ("previous × 8"); same list as the iPhone client. */
internal val BODYWEIGHT_CATALOG_KEYS: Set<String> = setOf(
    "push_up",
    "dips",
    "pull_up",
    "plank",
    "hanging_leg_raise",
    "band_assisted_pull_up"
)

internal fun isBodyweightCatalogKey(catalogKey: String?): Boolean =
    catalogKey != null && catalogKey in BODYWEIGHT_CATALOG_KEYS

/** The tappable "previous 60 × 8" caption in the current set's header. */
internal data class PreviousCaption(val weight: Double, val reps: Int, val showsWeight: Boolean)

/**
 * A 0 kg "previous" only means something for a bodyweight exercise ("previous × 8"); for
 * everything else it is noise from an unrecorded/zeroed set and stays hidden.
 */
internal fun previousCaption(
    previousWeight: Double?,
    previousReps: Int?,
    isBodyweight: Boolean
): PreviousCaption? {
    if (previousWeight == null || previousReps == null) return null
    if (!(previousWeight > 0.0 || isBodyweight)) return null
    return PreviousCaption(
        weight = previousWeight,
        reps = previousReps,
        showsWeight = !(isBodyweight && previousWeight == 0.0)
    )
}

internal const val DEFAULT_WEIGHT_STEP = 2.5

/**
 * The step shown on a capsule side even when that direction is blocked: the smallest gap between
 * a machine's allowed weights, otherwise the default 2.5 kg.
 */
internal fun nominalWeightStep(allowedWeights: List<Double>): Double {
    if (allowedWeights.size < 2) return DEFAULT_WEIGHT_STEP
    val smallestGap = allowedWeights.zipWithNext { low, high -> high - low }.minOrNull()
    return smallestGap?.takeIf { it.isFinite() && it > 0.0 } ?: DEFAULT_WEIGHT_STEP
}

internal data class WeightStepSide(val target: Double, val delta: Double, val canMove: Boolean)

internal data class WeightStepPlan(val minus: WeightStepSide, val plus: WeightStepSide)

/** Blank input steps from 0 like the record path treats it; unparseable input cannot step. */
internal fun weightForStepping(weightInput: String): Double? =
    if (weightInput.isBlank()) 0.0 else parseWeightInputOrNull(weightInput)

/**
 * Real delta when the direction can move, the nominal step otherwise (blocked at 0 kg or at a
 * machine's lowest/highest stop). [weight] null (unparseable input) blocks both directions.
 */
internal fun weightStepPlan(weight: Double?, allowedWeights: List<Double>): WeightStepPlan {
    val nominal = nominalWeightStep(allowedWeights)
    fun side(direction: Int): WeightStepSide {
        if (weight == null) return WeightStepSide(0.0, nominal, canMove = false)
        val target = try {
            TrainingTools.stepWeight(weight, direction, allowedWeights)
        } catch (_: IllegalArgumentException) {
            weight
        }
        val canMove = target != weight
        val delta = if (canMove) abs(target - weight).roundedToThousandths() else nominal
        return WeightStepSide(target, delta, canMove)
    }
    return WeightStepPlan(minus = side(-1), plus = side(1))
}

private fun Double.roundedToThousandths(): Double = Math.round(this * 1_000.0) / 1_000.0

internal fun steppedReps(current: Int?, direction: Int): Int =
    ((current ?: 0) + direction).coerceIn(1, WorkoutDataLimits.MAX_REPS)

internal fun canStepReps(current: Int?, direction: Int): Boolean =
    if (direction < 0) (current ?: 0) > 1 else (current ?: 0) < WorkoutDataLimits.MAX_REPS

/** "3:00" for the Log button suffix; null when no rest applies. */
internal fun restClockLabel(restSeconds: Int): String? =
    if (restSeconds > 0) String.format(Locale.ROOT, "%d:%02d", restSeconds / 60, restSeconds % 60) else null

/**
 * The one confirmation banner for a just-recorded set. [message] is the visible line ("Recorded:
 * 40 kg × 10", no rest suffix: the compact rest row shows the live countdown); [announcement] is
 * the fuller text read out to a screen reader, which keeps the rest duration.
 */
internal data class RecordedConfirmation(val message: String, val announcement: String, val setId: String)

/**
 * The announcement for [message]: the message alone when no rest applies, otherwise
 * [withRest] applied to the "m:ss" rest label ("Recorded: 40 kg × 10 · rest 3:00").
 */
internal fun recordedSetAnnouncement(
    message: String,
    restSeconds: Int,
    withRest: (message: String, restClock: String) -> String
): String {
    val clock = restClockLabel(restSeconds) ?: return message
    return withRest(message, clock)
}

internal enum class RecordedConfirmationStep {
    /** The set has not started recording yet (or the record was rejected before it began). */
    Waiting,
    /** The set is being recorded or is the latest completed set: the banner stays. */
    Showing,
    /** The set is no longer the latest completed one (undone, superseded) or failed: hide it. */
    Clear
}

/**
 * Decides what the banner for [setId] does with the current workout state. [wasShowing] is true once
 * the set has been seen in flight or as the latest completed set, so the banner is only cleared
 * after it has really been active (the recording state arrives a frame after the tap).
 */
internal fun recordedConfirmationStep(
    setId: String,
    latestCompletedSetId: String?,
    setRecordingsInFlight: Set<String>,
    wasShowing: Boolean,
    hasFailureForSet: Boolean
): RecordedConfirmationStep = when {
    setId == latestCompletedSetId || setId in setRecordingsInFlight -> RecordedConfirmationStep.Showing
    wasShowing || hasFailureForSet -> RecordedConfirmationStep.Clear
    else -> RecordedConfirmationStep.Waiting
}

/** Status messages that report success rather than a problem (shown in the info tone). */
internal fun activeWorkoutMessageIsSuccess(messageResourceId: Int): Boolean =
    messageResourceId == com.example.gymapp.R.string.active_workout_exercise_saved ||
        messageResourceId == com.example.gymapp.R.string.active_workout_remaining_sets_skipped ||
        messageResourceId == com.example.gymapp.R.string.active_workout_all_sets_saved
