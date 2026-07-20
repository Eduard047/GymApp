package com.example.gymapp.ui.viewmodel

import com.example.gymapp.R
import org.junit.Assert.assertEquals
import org.junit.Test

class PlanSyncErrorTextTest {
    @Test
    fun knownGarminFailuresMapToStableLocalizedResources() {
        val cases = listOf(
            "Workout plan is empty" to R.string.message_workout_plan_empty,
            "Workout plan is outside Garmin limits" to R.string.message_plan_outside_garmin_limits,
            "Garmin SDK not ready" to R.string.message_garmin_sdk_not_ready,
            "Sign in before Garmin sync" to R.string.message_garmin_sign_in_required,
            "Garmin account changed during sync" to R.string.message_garmin_account_changed,
            "Garmin account transition is incomplete" to
                R.string.message_garmin_reconnect_account_cleanup,
            "Cannot persist trusted-device state" to R.string.message_garmin_storage_failed,
            "Pair exactly one Garmin watch" to R.string.message_garmin_pair_one_watch,
            "No trusted Garmin watch is paired" to R.string.message_no_trusted_garmin_watch,
            "sync_ack was not received" to R.string.message_garmin_ack_missing,
            "Send status failed" to R.string.message_garmin_send_failed,
            "Send timeout" to R.string.message_garmin_send_failed
        )

        cases.forEach { (message, expectedResource) ->
            assertEquals(
                message,
                expectedResource,
                planSyncErrorText(IllegalStateException(message)).resourceId
            )
        }
    }

    @Test
    fun unknownOrMissingGarminFailuresUseGenericFallback() {
        assertEquals(
            R.string.message_plan_sync_failed,
            planSyncErrorText(IllegalStateException("device-private diagnostic")).resourceId
        )
        assertEquals(
            R.string.message_plan_sync_failed,
            planSyncErrorText(IllegalStateException()).resourceId
        )
    }
}
