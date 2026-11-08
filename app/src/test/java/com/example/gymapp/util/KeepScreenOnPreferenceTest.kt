package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class MemoryKeepScreenOnStorage(var value: Boolean? = null) : KeepScreenOnStorage {
    override fun read(): Boolean? = value
    override fun write(enabled: Boolean) {
        value = enabled
    }
}

class KeepScreenOnPreferenceTest {
    @Test
    fun keepScreenOnIsOnByDefault() {
        val storage = MemoryKeepScreenOnStorage()
        assertTrue(KeepScreenOnPreference.DEFAULT_ENABLED)
        assertTrue(KeepScreenOnPreference(storage).enabled.value)
        assertNull("reading the default must not write it", storage.value)
    }

    @Test
    fun switchingOffPersistsAndSurvivesARestart() {
        val storage = MemoryKeepScreenOnStorage()
        val preference = KeepScreenOnPreference(storage)
        preference.setEnabled(false)
        assertFalse(preference.enabled.value)
        assertEquals(false, storage.value)
        assertFalse(KeepScreenOnPreference(storage).enabled.value)
        preference.setEnabled(true)
        assertTrue(KeepScreenOnPreference(storage).enabled.value)
    }

    @Test
    fun theSwitchIsDeviceLocalAndSeparateFromHaptics() {
        assertEquals("keep_screen_on_during_workouts", KeepScreenOnPreference.KEY_ENABLED)
        assertEquals(HapticsPreference.PREFS_NAME, KeepScreenOnPreference.PREFS_NAME)
        assertTrue(KeepScreenOnPreference.KEY_ENABLED != HapticsPreference.KEY_ENABLED)
    }
}
