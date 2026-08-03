package com.example.gymapp.data.repository

enum class ExerciseLoadDirection(val wireValue: String) {
    HigherIsHarder("higherIsHarder"),
    LowerIsHarder("lowerIsHarder");

    companion object {
        fun fromWireValue(value: String?): ExerciseLoadDirection? =
            entries.firstOrNull { it.wireValue == value }
    }
}

data class ExerciseLoadProfile(
    val direction: ExerciseLoadDirection,
    val allowedWeightsKg: List<Double>
) {
    init {
        require(isValid(direction, allowedWeightsKg)) { "Exercise load profile is invalid." }
    }

    companion object {
        const val MAX_WEIGHT_OPTIONS = 128

        fun isValid(
            direction: ExerciseLoadDirection?,
            allowedWeightsKg: List<Double>
        ): Boolean {
            if (direction == null || allowedWeightsKg.isEmpty() ||
                allowedWeightsKg.size > MAX_WEIGHT_OPTIONS
            ) {
                return false
            }
            return allowedWeightsKg.withIndex().all { (index, weight) ->
                WorkoutDataLimits.isValidWeight(weight) &&
                    (index == 0 || weight > allowedWeightsKg[index - 1])
            }
        }
    }
}
