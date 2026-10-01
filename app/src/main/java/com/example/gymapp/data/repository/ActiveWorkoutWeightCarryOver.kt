package com.example.gymapp.data.repository

import com.example.gymapp.data.entity.ActiveWorkoutSetEntity

/**
 * Weight carry-over for a running workout: when a set is recorded with a real weight, the next
 * pending set of the same exercise that has no planned weight (0 kg) inherits it. Reps and any
 * non-zero planned weight are left untouched.
 */
internal object ActiveWorkoutWeightCarryOver {
    /**
     * @param exerciseSets every set of the recorded set's exercise (any order).
     * @return the set that should receive [recordedWeight], or null when nothing carries over.
     */
    fun target(
        exerciseSets: List<ActiveWorkoutSetEntity>,
        recordedSetId: String,
        recordedWeight: Double
    ): ActiveWorkoutSetEntity? {
        if (recordedWeight <= 0.0) return null
        val recorded = exerciseSets.firstOrNull { it.id == recordedSetId } ?: return null
        val next = exerciseSets
            .filter { it.id != recordedSetId && it.completedAt == null && it.orderIndex > recorded.orderIndex }
            .minByOrNull { it.orderIndex }
            ?: return null
        return next.takeIf { it.weight == 0.0 }
    }
}
