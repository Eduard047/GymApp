package com.example.gymapp.util

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class TrainingSplit {
    UpperLower,
    FullBody,
    PushPullLegs,
    Custom
}

enum class TrainingGoal {
    AestheticFatLoss,
    MuscleGain,
    Strength,
    Balanced
}

enum class CalorieMode {
    Deficit,
    Maintenance,
    Surplus
}

data class TrainingProfile(
    val split: TrainingSplit = TrainingSplit.UpperLower,
    val workoutsPerWeek: Int = 4,
    val goal: TrainingGoal = TrainingGoal.AestheticFatLoss,
    val calorieMode: CalorieMode = CalorieMode.Deficit
)

class TrainingProfileManager(
    context: Context
) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val _profile = MutableStateFlow(readProfile())
    val profile: StateFlow<TrainingProfile> = _profile.asStateFlow()

    fun updateSplit(split: TrainingSplit) {
        updateProfile(_profile.value.copy(split = split))
    }

    fun updateWorkoutsPerWeek(value: Int) {
        updateProfile(_profile.value.copy(workoutsPerWeek = value.coerceIn(2, 6)))
    }

    fun updateGoal(goal: TrainingGoal) {
        updateProfile(_profile.value.copy(goal = goal))
    }

    fun updateCalorieMode(mode: CalorieMode) {
        updateProfile(_profile.value.copy(calorieMode = mode))
    }

    private fun updateProfile(profile: TrainingProfile) {
        preferences.edit()
            .putString(KEY_SPLIT, profile.split.name)
            .putInt(KEY_WORKOUTS_PER_WEEK, profile.workoutsPerWeek)
            .putString(KEY_GOAL, profile.goal.name)
            .putString(KEY_CALORIE_MODE, profile.calorieMode.name)
            .apply()
        _profile.value = profile
    }

    private fun readProfile(): TrainingProfile {
        return TrainingProfile(
            split = preferences.enumValue(KEY_SPLIT, TrainingSplit.UpperLower),
            workoutsPerWeek = preferences.getInt(KEY_WORKOUTS_PER_WEEK, 4).coerceIn(2, 6),
            goal = preferences.enumValue(KEY_GOAL, TrainingGoal.AestheticFatLoss),
            calorieMode = preferences.enumValue(KEY_CALORIE_MODE, CalorieMode.Deficit)
        )
    }

    private inline fun <reified T : Enum<T>> android.content.SharedPreferences.enumValue(
        key: String,
        fallback: T
    ): T {
        val rawValue = getString(key, null) ?: return fallback
        return enumValues<T>().firstOrNull { it.name == rawValue } ?: fallback
    }

    private companion object {
        const val PREFS_NAME = "gym_training_profile"
        const val KEY_SPLIT = "split"
        const val KEY_WORKOUTS_PER_WEEK = "workouts_per_week"
        const val KEY_GOAL = "goal"
        const val KEY_CALORIE_MODE = "calorie_mode"
    }
}
