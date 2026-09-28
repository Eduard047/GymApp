package com.example.gymapp.data.repository

import kotlin.math.roundToLong

/** How a barbell total splits into plates on each side of the bar. */
internal data class PlateLoad(
    val status: Status,
    /** Heaviest first, one side of the bar. */
    val platesPerSide: List<Double>,
    /** Weight per side the available plates cannot make up. */
    val remainderPerSide: Double
) {
    enum class Status {
        /** The total is lighter than the empty bar. */
        BelowBar,
        /** The total is exactly the empty bar. */
        BarOnly,
        /** Plates are needed on each side. */
        Loaded
    }
}

/**
 * Splits a barbell total into standard plates per side (20 kg bar; 25, 20, 15, 10, 5, 2.5, and
 * 1.25 kg plates), matching iOS. Every plate is a multiple of the smallest one, so filling
 * greedily from the heaviest leaves the smallest remainder.
 */
internal object PlateCalculator {
    const val BAR_WEIGHT = 20.0
    val PLATES: List<Double> = listOf(25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25)

    /** Built-in barbell exercises, the same set iOS uses. */
    private val barbellCatalogKeys = setOf(
        "bench_press", "incline_bench_press", "barbell_row", "squat", "romanian_deadlift",
        "deadlift", "hip_thrust", "barbell_curl", "upright_row", "french_press"
    )

    fun load(total: Double, bar: Double = BAR_WEIGHT, plates: List<Double> = PLATES): PlateLoad {
        // Work in hundredths of a kilogram so 2.5 and 1.25 add up exactly.
        val totalUnits = if (total.isFinite()) (total * 100).roundToLong() else 0L
        val barUnits = (bar * 100).roundToLong()
        if (totalUnits < barUnits) {
            return PlateLoad(PlateLoad.Status.BelowBar, emptyList(), 0.0)
        }
        // An odd hundredth cannot be split evenly; the leftover half stays in the remainder.
        var remainingUnits = (totalUnits - barUnits) / 2
        if (remainingUnits <= 0L) {
            return PlateLoad(PlateLoad.Status.BarOnly, emptyList(), 0.0)
        }
        val perSide = mutableListOf<Double>()
        for (plate in plates.sortedDescending()) {
            val plateUnits = (plate * 100).roundToLong()
            if (plateUnits <= 0L) continue
            while (remainingUnits >= plateUnits) {
                perSide += plate
                remainingUnits -= plateUnits
            }
        }
        return PlateLoad(PlateLoad.Status.Loaded, perSide, remainingUnits / 100.0)
    }

    /** Plate math applies only to built-in barbell exercises. */
    fun applies(catalogKey: String?): Boolean = catalogKey != null && catalogKey in barbellCatalogKeys
}
