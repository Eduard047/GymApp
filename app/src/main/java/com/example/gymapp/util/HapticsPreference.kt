package com.example.gymapp.util

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The in-app Haptics switch (Profile > Settings). A device preference: default on, kept in this device's
 * app preferences, never synced and never part of an account. Every app-generated haptic goes through
 * `GymHaptics`, which asks [HapticsGate] before it fires, so one stored value gates them all.
 */
class HapticsPreference(context: Context) {
    private val preferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val _enabled = MutableStateFlow(preferences.getBoolean(KEY_ENABLED, DEFAULT_ENABLED))
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    init {
        HapticsGate.enabled = _enabled.value
    }

    fun setEnabled(enabled: Boolean) {
        preferences.edit().putBoolean(KEY_ENABLED, enabled).apply()
        _enabled.value = enabled
        HapticsGate.enabled = enabled
    }

    companion object {
        const val PREFS_NAME = "gym_ui_preferences"
        const val KEY_ENABLED = "haptics_enabled"
        const val DEFAULT_ENABLED = true
    }
}

/** The process-wide on/off state read by `GymHaptics`; written only by [HapticsPreference]. */
object HapticsGate {
    @Volatile
    var enabled: Boolean = HapticsPreference.DEFAULT_ENABLED
}

/** Whether a haptic may fire: the in-app switch must be on. (The OS touch-feedback setting is applied by the View.) */
internal fun gymHapticAllowed(inAppEnabled: Boolean): Boolean = inAppEnabled

@Composable
internal fun rememberHapticsPreference(): HapticsPreference {
    val app = LocalContext.current.applicationContext as com.example.gymapp.GymApplication
    return app.hapticsPreference
}
