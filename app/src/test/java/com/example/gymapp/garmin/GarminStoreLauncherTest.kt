package com.example.gymapp.garmin

import org.junit.Assert.assertEquals
import org.junit.Test

class GarminStoreLauncherTest {
    @Test
    fun `Garmin store launch opens our listing then falls back to Google Play`() {
        assertEquals(
            listOf(
                GarminStoreLaunchTarget(
                    uri = "https://apps.garmin.com/apps/fe82a300-4d9f-4588-8b10-365d75280b8f",
                    packageName = "com.garmin.connectiq"
                ),
                GarminStoreLaunchTarget(
                    uri = "market://details?id=com.garmin.connectiq",
                    packageName = "com.android.vending"
                ),
                GarminStoreLaunchTarget(
                    uri = "https://play.google.com/store/apps/details?id=com.garmin.connectiq",
                    packageName = null
                )
            ),
            GARMIN_STORE_LAUNCH_TARGETS
        )
    }
}
