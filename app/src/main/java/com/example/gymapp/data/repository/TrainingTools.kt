package com.example.gymapp.data.repository

/** Small, deterministic editing rules shared by the three training clients. */
object TrainingTools {
    fun stepWeight(weight: Double, direction: Int, allowed: List<Double> = emptyList()): Double {
        // Invalid input leaves the weight unchanged, like iPhone, instead of throwing.
        if (!(weight.isFinite() && weight in 0.0..1_000_000.0 && direction in listOf(-1, 1) &&
                allowed.size <= 128 && allowed.all { it.isFinite() && it in 0.0..1_000_000.0 } &&
                allowed.zipWithNext().all { (a, b) -> a < b })) return weight
        if (allowed.isNotEmpty()) return if (direction > 0) {
            allowed.firstOrNull { it > weight } ?: weight
        } else {
            allowed.lastOrNull { it < weight } ?: weight
        }
        return (weight + direction * 2.5).coerceIn(0.0, 1_000_000.0)
    }
}
