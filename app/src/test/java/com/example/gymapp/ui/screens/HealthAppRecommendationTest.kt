package com.example.gymapp.ui.screens

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class HealthAppRecommendationTest {
    @Test
    fun androidPackageAndStoreUrlsAreExact() {
        assertEquals("com.eduard.healthapp", HEALTH_APP_ANDROID_PACKAGE)
        assertEquals("market://details?id=com.eduard.healthapp", HEALTH_APP_MARKET_URL)
        assertEquals(
            "https://play.google.com/store/apps/details?id=com.eduard.healthapp",
            HEALTH_APP_GOOGLE_PLAY_URL
        )
    }

    @Test
    fun storeTargetsTryThePlayAppThenTheWebListing() {
        assertEquals(
            listOf(
                HealthAppStoreTarget(HEALTH_APP_MARKET_URL, "com.android.vending"),
                HealthAppStoreTarget(HEALTH_APP_GOOGLE_PLAY_URL, null)
            ),
            HEALTH_APP_STORE_TARGETS
        )
    }

    @Test
    fun rowStaysHiddenUntilThePlayListingIsPublic() {
        // Flip HEALTH_APP_PLAY_LISTING_PUBLIC (and this assertion) together when the listing goes live.
        assertFalse(HEALTH_APP_PLAY_LISTING_PUBLIC)
    }
}
