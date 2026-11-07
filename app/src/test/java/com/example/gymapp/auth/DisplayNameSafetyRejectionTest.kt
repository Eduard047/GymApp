package com.example.gymapp.auth

import com.example.gymapp.R
import com.example.gymapp.navigation.cloudAutoRetryDelayMillis
import com.example.gymapp.sync.CloudSyncPhase
import com.example.gymapp.sync.cloudSyncUiStatus
import com.example.gymapp.util.LocalizedText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DisplayNameSafetyRejectionTest {
    private val serverMessage = "Display name violates the leaderboard safety policy."

    @Test
    fun serverTriggerRejectionIsDetected() {
        assertTrue(isDisplayNameSafetyRejection("23514", serverMessage))
    }

    @Test
    fun otherFailuresAreNotDetected() {
        assertFalse(isDisplayNameSafetyRejection("23514", "new row violates check constraint"))
        assertFalse(isDisplayNameSafetyRejection("23505", serverMessage))
        assertFalse(isDisplayNameSafetyRejection(null, serverMessage))
        assertFalse(isDisplayNameSafetyRejection("23514", null))
        assertFalse(isDisplayNameSafetyRejection("PGRST301", "JWT expired"))
    }

    @Test
    fun rejectionMapsToTheRulesMessageAndIsNotAutoRetried() {
        val text = authErrorText(
            IllegalStateException(SIGN_UP_DISPLAY_NAME_RULES_ERROR),
            R.string.cloud_sync_save_failed
        )
        assertEquals(R.string.auth_error_display_name_rules, text.resourceId)
        for (attempt in 0..4) {
            assertNull(cloudAutoRetryDelayMillis(text, attempt, networkFailure = false))
        }
    }

    @Test
    fun syncCardKeepsTheRulesReason() {
        val reason = LocalizedText(R.string.auth_error_display_name_rules)
        val status = cloudSyncUiStatus(CloudSyncPhase.Error, null, reason)
        assertEquals(R.string.auth_error_display_name_rules, status.message?.resourceId)
    }
}
