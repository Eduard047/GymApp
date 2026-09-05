package com.example.gymapp.data.repository

/** Small, deterministic editing rules shared by the three training clients. */
object TrainingTools {
    fun stepWeight(weight: Double, direction: Int, allowed: List<Double> = emptyList()): Double {
        require(weight.isFinite() && weight in 0.0..1_000_000.0 && direction in listOf(-1, 1))
        require(allowed.size <= 128 && allowed.all { it.isFinite() && it in 0.0..1_000_000.0 } &&
            allowed.zipWithNext().all { (a, b) -> a < b })
        if (allowed.isNotEmpty()) return if (direction > 0) {
            allowed.firstOrNull { it > weight } ?: weight
        } else {
            allowed.lastOrNull { it < weight } ?: weight
        }
        return (weight + direction * 2.5).coerceIn(0.0, 1_000_000.0)
    }
}
