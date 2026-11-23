package com.example.gymapp.wear.health

import com.example.gymapp.wear.sync.SyncPaths
import kotlin.math.roundToInt

/** Average and peak heart rate of one workout, both already within the protocol bounds. */
data class HeartRateSummary(val average: Int, val max: Int)

/**
 * Running current/average/max over a workout's heart-rate samples. Samples outside the
 * plausible 25..240 bpm range (sensor noise, lost contact) are ignored.
 */
class HeartRateAccumulator {
    private var sum = 0L
    private var count = 0

    var current: Int? = null
        private set
    var max: Int? = null
        private set

    val sampleCount: Int get() = count

    /** Returns true when the sample was plausible and has been counted. */
    fun add(bpm: Double): Boolean {
        if (!bpm.isFinite()) return false
        val rounded = bpm.roundToInt()
        if (rounded !in SyncPaths.MIN_HEART_RATE..SyncPaths.MAX_HEART_RATE) return false
        sum += rounded
        count += 1
        current = rounded
        if (max == null || rounded > max!!) max = rounded
        return true
    }

    val average: Int?
        get() = if (count == 0) null else (sum.toDouble() / count).roundToInt()

    /** Null until at least one valid sample arrived. The average never exceeds the max. */
    fun summary(): HeartRateSummary? {
        val avg = average ?: return null
        val peak = max ?: return null
        return HeartRateSummary(average = avg.coerceAtMost(peak), max = peak)
    }
}
