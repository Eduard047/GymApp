package com.example.gymapp.util

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Where [KeepScreenOnPreference] keeps its one boolean; the app uses SharedPreferences, tests use memory. */
interface KeepScreenOnStorage {
    fun read(): Boolean?
    fun write(enabled: Boolean)
}

/**
 * The in-app "Keep screen on during workouts" switch (Profile > Settings). A device preference: default
 * on, kept in this device's app preferences (same file as the Haptics switch), never synced and never
 * part of an account. The active workout screen reads it to hold the screen awake while it is visible.
 */
class KeepScreenOnPreference internal constructor(private val storage: KeepScreenOnStorage) {
    constructor(context: Context) : this(SharedPreferencesKeepScreenOnStorage(context.applicationContext))

    private val _enabled = MutableStateFlow(storage.read() ?: DEFAULT_ENABLED)
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    fun setEnabled(enabled: Boolean) {
        storage.write(enabled)
        _enabled.value = enabled
    }

    companion object {
        const val PREFS_NAME = HapticsPreference.PREFS_NAME
        const val KEY_ENABLED = "keep_screen_on_during_workouts"
        const val DEFAULT_ENABLED = true
    }
}

private class SharedPreferencesKeepScreenOnStorage(context: Context) : KeepScreenOnStorage {
    private val preferences =
        context.getSharedPreferences(KeepScreenOnPreference.PREFS_NAME, Context.MODE_PRIVATE)

    override fun read(): Boolean? =
        if (preferences.contains(KeepScreenOnPreference.KEY_ENABLED)) {
            preferences.getBoolean(KeepScreenOnPreference.KEY_ENABLED, KeepScreenOnPreference.DEFAULT_ENABLED)
        } else {
            null
        }

    override fun write(enabled: Boolean) {
        preferences.edit().putBoolean(KeepScreenOnPreference.KEY_ENABLED, enabled).apply()
    }
}

@Composable
internal fun rememberKeepScreenOnPreference(): KeepScreenOnPreference {
    val app = LocalContext.current.applicationContext as com.example.gymapp.GymApplication
    return app.keepScreenOnPreference
}
