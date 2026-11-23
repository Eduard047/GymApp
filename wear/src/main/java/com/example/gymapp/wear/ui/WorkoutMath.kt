package com.example.gymapp.wear.ui

import com.example.gymapp.wear.data.WearWorkoutSetDraft
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

/** Weight + reps pair shown as the dashboard hero and used to prefill the set pickers. */
data class SetTarget(val weight: Double, val reps: Int)

/** "Set k of n" (n is null in a free workout or for an exercise that is not in the plan). */
data class SetProgress(val setNumber: Int, val setCount: Int?)

/** One row of the plan section in the exercise picker. */
data class PlanExerciseProgress(val exerciseName: String, val done: Int, val total: Int) {
    val hasRemaining: Boolean get() = done < total
}

/** The numbers on the summary screen. HR/kcal are null when no heart-rate data was recorded. */
data class WorkoutSummaryNumbers(
    val durationSeconds: Long,
    val setCount: Int,
    val volumeKg: Double,
    val averageHeartRate: Int?,
    val maxHeartRate: Int?,
    val caloriesKcal: Int?
)

/**
 * Pure, JVM-testable rules behind the watch UI: heart-rate zones, set numbering, plan targets,
 * picker options, volume and formatting. No Android types here.
 */
object WorkoutMath {
    /** v1 has no age on the watch, so zones come from a fixed max HR (owner decision). */
    const val DEFAULT_MAX_HEART_RATE = 190
    const val MAX_WEIGHT_OPTION_KG = 500.0
    const val MIN_REPS = 1
    const val MAX_REPS_OPTION = 100
    const val DEFAULT_REPS = 10
    val WEIGHT_STEPS_KG = listOf(1.0, 2.5, 5.0)
    const val DEFAULT_WEIGHT_STEP_KG = 2.5

    /** Zone 1..5 by % of max HR: <60, 60–70, 70–80, 80–90, ≥90. Null without a reading. */
    fun heartRateZone(bpm: Int?, maxHeartRate: Int = DEFAULT_MAX_HEART_RATE): Int? {
        if (bpm == null || bpm <= 0 || maxHeartRate <= 0) return null
        val percent = bpm * 100.0 / maxHeartRate
        return when {
            percent < 60.0 -> 1
            percent < 70.0 -> 2
            percent < 80.0 -> 3
            percent < 90.0 -> 4
            else -> 5
        }
    }

    fun nextWeightStep(current: Double): Double {
        val index = WEIGHT_STEPS_KG.indexOfFirst { abs(it - current) < 0.001 }
        return WEIGHT_STEPS_KG[(index + 1).mod(WEIGHT_STEPS_KG.size)]
    }

    fun normalizeWeightStep(value: Double): Double =
        WEIGHT_STEPS_KG.firstOrNull { abs(it - value) < 0.001 } ?: DEFAULT_WEIGHT_STEP_KG

    fun volumeKg(sets: List<WearWorkoutSetDraft>): Double = sets.sumOf { it.weight * it.reps }

    /** Plan exercises in plan order with logged/planned counts. */
    fun planProgress(
        planTargets: List<WearWorkoutSetDraft>,
        loggedSets: List<WearWorkoutSetDraft>
    ): List<PlanExerciseProgress> {
        val totals = LinkedHashMap<String, Int>()
        planTargets.forEach { totals[it.exerciseName] = (totals[it.exerciseName] ?: 0) + 1 }
        return totals.map { (name, total) ->
            PlanExerciseProgress(name, loggedSets.count { it.exerciseName == name }, total)
        }
    }

    /**
     * The exercise the dashboard shows: the explicit choice, else the first plan exercise with
     * sets remaining, else the last logged exercise, else the first plan exercise.
     */
    fun currentExercise(
        selected: String?,
        planTargets: List<WearWorkoutSetDraft>,
        loggedSets: List<WearWorkoutSetDraft>
    ): String? {
        if (!selected.isNullOrBlank()) return selected
        val progress = planProgress(planTargets, loggedSets)
        return progress.firstOrNull { it.hasRemaining }?.exerciseName
            ?: loggedSets.lastOrNull()?.exerciseName
            ?: progress.firstOrNull()?.exerciseName
    }

    /** Set k of n. k stays at n once the plan for this exercise is done (extra sets allowed). */
    fun setProgress(
        exercise: String?,
        planTargets: List<WearWorkoutSetDraft>,
        loggedSets: List<WearWorkoutSetDraft>
    ): SetProgress {
        if (exercise == null) return SetProgress(loggedSets.size + 1, null)
        val done = loggedSets.count { it.exerciseName == exercise }
        val total = planTargets.count { it.exerciseName == exercise }
        return if (total > 0) {
            SetProgress((done + 1).coerceAtMost(total), total)
        } else {
            SetProgress(done + 1, null)
        }
    }

    /**
     * Prefill: plan target for this exercise's next set, else the last logged values for this
     * exercise, else the last values of the plan for it, else null (caller shows 0 × 10).
     */
    fun nextTarget(
        exercise: String?,
        planTargets: List<WearWorkoutSetDraft>,
        loggedSets: List<WearWorkoutSetDraft>
    ): SetTarget? {
        if (exercise == null) return loggedSets.lastOrNull()?.let { SetTarget(it.weight, it.reps) }
        val done = loggedSets.count { it.exerciseName == exercise }
        val planned = planTargets.filter { it.exerciseName == exercise }
        planned.getOrNull(done)?.let { return SetTarget(it.weight, it.reps) }
        loggedSets.lastOrNull { it.exerciseName == exercise }?.let { return SetTarget(it.weight, it.reps) }
        return planned.lastOrNull()?.let { SetTarget(it.weight, it.reps) }
    }

    /** 0..500 by [stepKg], plus [extra] (an off-grid planned weight), sorted, no duplicates. */
    fun weightOptions(stepKg: Double, extra: Double? = null): List<Double> {
        val step = normalizeWeightStep(stepKg)
        val count = (MAX_WEIGHT_OPTION_KG / step).toInt()
        val options = (0..count).map { roundKg(it * step) }.toMutableList()
        if (extra != null && extra.isFinite() && extra in 0.0..MAX_WEIGHT_OPTION_KG &&
            options.none { abs(it - extra) < 0.001 }
        ) {
            options += roundKg(extra)
            options.sort()
        }
        return options
    }

    fun closestIndex(options: List<Double>, value: Double): Int {
        if (options.isEmpty()) return 0
        return options.indices.minByOrNull { abs(options[it] - value) } ?: 0
    }

    val repOptions: List<Int> = (MIN_REPS..MAX_REPS_OPTION).toList()

    fun repIndex(reps: Int): Int = (reps.coerceIn(MIN_REPS, MAX_REPS_OPTION) - MIN_REPS)

    /** Decimals only when needed, locale separator: 60 / 62,5 / 1,25. */
    fun formatWeight(weight: Double, locale: Locale): String {
        val format = DecimalFormat("0.##", DecimalFormatSymbols.getInstance(locale))
        return format.format(roundKg(weight))
    }

    /** Volume with grouping: 5 240. */
    fun formatVolume(volumeKg: Double, locale: Locale): String {
        val format = DecimalFormat("#,##0", DecimalFormatSymbols.getInstance(locale))
        return format.format(volumeKg.roundToLong())
    }

    /** m:ss under an hour, h:mm:ss after. */
    fun formatDuration(totalSeconds: Long): String {
        val seconds = totalSeconds.coerceAtLeast(0L)
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) String.format(Locale.ROOT, "%d:%02d:%02d", h, m, s)
        else String.format(Locale.ROOT, "%d:%02d", m, s)
    }

    fun summary(
        durationSeconds: Long,
        loggedSets: List<WearWorkoutSetDraft>,
        averageHeartRate: Int?,
        maxHeartRate: Int?,
        caloriesKcal: Int?
    ): WorkoutSummaryNumbers = WorkoutSummaryNumbers(
        durationSeconds = durationSeconds.coerceAtLeast(0L),
        setCount = loggedSets.size,
        volumeKg = volumeKg(loggedSets),
        averageHeartRate = averageHeartRate?.takeIf { it > 0 },
        maxHeartRate = maxHeartRate?.takeIf { it > 0 },
        caloriesKcal = caloriesKcal?.takeIf { it >= 0 }
    )

    private fun roundKg(value: Double): Double = (value * 1000.0).roundToLong() / 1000.0
}

/**
 * 5-second undo window after a set is saved. Monotonic clock is passed in so it survives a slow
 * ticker and stays unit-testable.
 */
class UndoWindow(private val durationMs: Long = DURATION_MS) {
    var setId: Long? = null
        private set
    private var untilMs: Long = 0L

    fun open(setId: Long, nowMs: Long) {
        this.setId = setId
        untilMs = nowMs + durationMs
    }

    fun isOpen(nowMs: Long): Boolean = setId != null && nowMs < untilMs

    /** Closes the window when it has run out; returns true if it just closed. */
    fun expireIfDue(nowMs: Long): Boolean {
        if (setId != null && nowMs >= untilMs) {
            setId = null
            return true
        }
        return false
    }

    /** Takes the set id to undo if the window is still open; closes the window either way. */
    fun consume(nowMs: Long): Long? {
        val id = setId.takeIf { isOpen(nowMs) }
        setId = null
        return id
    }

    fun close() {
        setId = null
    }

    companion object {
        const val DURATION_MS = 5_000L
    }
}
