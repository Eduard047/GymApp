package com.example.gymapp.auth

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CloudAuthLogoutPersistenceTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @After
    fun cleanUp() {
        preferences.edit().clear().commit()
    }

    @Test
    fun credentialDeletionIsCommittedBeforeLogoutCanComplete() {
        assertTrue(
            preferences.edit()
                .putString("mode", "cloud")
                .putString("cloud", "access-token refresh-token")
                .commit()
        )

        assertTrue(clearAuthPreferencesSynchronously(preferences))

        val reopened = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        assertFalse(reopened.contains("mode"))
        assertFalse(reopened.contains("cloud"))
        assertTrue(reopened.all.isEmpty())
    }

    private companion object {
        const val PREFS_NAME = "gym_cloud_auth_logout_persistence_test"
    }
}
