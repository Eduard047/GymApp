package com.example.gymapp.util

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Where [RestEndAlertPreference] keeps its one boolean; the app uses SharedPreferences, tests use memory. */
interface RestEndAlertStorage {
    fun read(): Boolean?
    fun write(enabled: Boolean)
}

/**
 * The in-app "Rest end alert" switch (Profile > Settings). A device preference: default on, kept in this
 * device's app preferences (same file as the Haptics switch), never synced and never part of an account,
 * so it survives account switches. When off, the end of a rest posts no "rest finished" notification and
 * plays no sound, vibration or haptic; the countdown and the ongoing workout notification still update.
 * The phone also sends it to a paired Wear OS watch with the plan sync.
 */
class RestEndAlertPreference internal constructor(private val storage: RestEndAlertStorage) {
    constructor(context: Context) : this(SharedPreferencesRestEndAlertStorage(context.applicationContext))

    private val _enabled = MutableStateFlow(storage.read() ?: DEFAULT_ENABLED)
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    fun setEnabled(enabled: Boolean) {
        storage.write(enabled)
        _enabled.value = enabled
    }

    companion object {
        const val PREFS_NAME = HapticsPreference.PREFS_NAME
        const val KEY_ENABLED = "rest_end_alert_enabled"
        const val DEFAULT_ENABLED = true

        /**
         * Reads the stored value without the app object, for the rest timer service and its backstop
         * alarm receiver, which can run in a freshly started process.
         */
        fun isEnabled(context: Context): Boolean =
            SharedPreferencesRestEndAlertStorage(context.applicationContext).read() ?: DEFAULT_ENABLED
    }
}

private class SharedPreferencesRestEndAlertStorage(context: Context) : RestEndAlertStorage {
    private val preferences =
        context.getSharedPreferences(RestEndAlertPreference.PREFS_NAME, Context.MODE_PRIVATE)

    override fun read(): Boolean? =
        if (preferences.contains(RestEndAlertPreference.KEY_ENABLED)) {
            preferences.getBoolean(RestEndAlertPreference.KEY_ENABLED, RestEndAlertPreference.DEFAULT_ENABLED)
        } else {
            null
        }

    override fun write(enabled: Boolean) {
        preferences.edit().putBoolean(RestEndAlertPreference.KEY_ENABLED, enabled).apply()
    }
}

/**
 * Whether the end of a rest may alert (notification, sound, vibration, haptic). Pure so the gate is
 * unit-testable; the ongoing workout notification refresh never depends on it.
 */
internal fun restEndAlertAllowed(settingEnabled: Boolean): Boolean = settingEnabled

@Composable
internal fun rememberRestEndAlertPreference(): RestEndAlertPreference {
    val app = LocalContext.current.applicationContext as com.example.gymapp.GymApplication
    return app.restEndAlertPreference
}
