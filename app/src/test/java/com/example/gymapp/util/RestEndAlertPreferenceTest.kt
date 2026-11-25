package com.example.gymapp.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RestEndAlertPreferenceTest {
    private class MemoryStorage(var value: Boolean? = null) : RestEndAlertStorage {
        override fun read(): Boolean? = value
        override fun write(enabled: Boolean) {
            value = enabled
        }
    }

    @Test
    fun defaultsOnWhenNothingIsStored() {
        assertTrue(RestEndAlertPreference.DEFAULT_ENABLED)
        assertTrue(RestEndAlertPreference(MemoryStorage()).enabled.value)
    }

    @Test
    fun offIsStoredAndReadBack() {
        val storage = MemoryStorage()
        val preference = RestEndAlertPreference(storage)
        preference.setEnabled(false)
        assertFalse(preference.enabled.value)
        assertFalse(RestEndAlertPreference(storage).enabled.value)
        preference.setEnabled(true)
        assertTrue(RestEndAlertPreference(storage).enabled.value)
    }

    @Test
    fun isADeviceSettingNextToHapticsWithItsOwnKey() {
        assertEquals("rest_end_alert_enabled", RestEndAlertPreference.KEY_ENABLED)
        assertEquals(HapticsPreference.PREFS_NAME, RestEndAlertPreference.PREFS_NAME)
        assertTrue(RestEndAlertPreference.KEY_ENABLED != HapticsPreference.KEY_ENABLED)
        assertTrue(RestEndAlertPreference.KEY_ENABLED != KeepScreenOnPreference.KEY_ENABLED)
    }

    @Test
    fun alertGateFollowsTheSwitch() {
        assertTrue(restEndAlertAllowed(true))
        assertFalse(restEndAlertAllowed(false))
    }
}
