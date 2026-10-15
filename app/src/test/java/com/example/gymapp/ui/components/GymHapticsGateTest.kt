package com.example.gymapp.ui.components

import com.example.gymapp.util.HapticsGate
import com.example.gymapp.util.HapticsPreference
import com.example.gymapp.util.gymHapticAllowed
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GymHapticsGateTest {
    @Test
    fun hapticsAreOnByDefault() {
        assertTrue(HapticsPreference.DEFAULT_ENABLED)
        assertTrue(HapticsGate.enabled)
    }

    @Test
    fun theInAppSwitchGatesEveryHaptic() {
        assertTrue(gymHapticAllowed(true))
        assertFalse(gymHapticAllowed(false))
    }

    @Test
    fun menuAndRecordEventsUseTheCentralConstants() {
        GymHapticEvent.entries.forEach { event ->
            // Every event resolves to a platform constant on every API level the app supports.
            gymHapticConstant(event, 26)
            gymHapticConstant(event, 34)
        }
    }
}
