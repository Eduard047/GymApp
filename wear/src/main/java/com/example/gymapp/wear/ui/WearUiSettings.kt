package com.example.gymapp.wear.ui

import android.content.Context

/** Watch-only UI preferences (not synced, not account-scoped). */
object WearUiSettings {
    private const val PREFS_NAME = "watch_ui_settings"
    private const val KEY_WEIGHT_STEP_KG = "weight_step_kg"

    fun weightStepKg(context: Context): Double =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getFloat(KEY_WEIGHT_STEP_KG, WorkoutMath.DEFAULT_WEIGHT_STEP_KG.toFloat())
            .toDouble()

    fun setWeightStepKg(context: Context, stepKg: Double) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_WEIGHT_STEP_KG, WorkoutMath.normalizeWeightStep(stepKg).toFloat())
            .apply()
    }
}
