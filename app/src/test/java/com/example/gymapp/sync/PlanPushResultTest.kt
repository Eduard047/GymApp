package com.example.gymapp.sync

import com.example.gymapp.R
import com.example.gymapp.garmin.GARMIN_PLAN_QUEUED_STATUS
import com.example.gymapp.ui.viewmodel.planSyncErrorText
import com.example.gymapp.ui.viewmodel.planSyncSuccessNotice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class PlanPushResultTest {
    @Test
    fun deliveredPlanIsPlainSuccessWithNoNotice() {
        val result = planPushResult(delivered = true, status = "ACK")
        assertEquals(PlanPushResult.Delivered, result)
        assertNull(planSyncSuccessNotice(result))
    }

    @Test
    fun savedPlanWhileSdkIsNotReadyIsQueuedNotAnError() {
        val result = planPushResult(delivered = false, status = GARMIN_PLAN_QUEUED_STATUS)
        assertEquals(PlanPushResult.Queued, result)
        assertEquals(R.string.message_plan_sync_queued, planSyncSuccessNotice(result)?.resourceId)
    }

    @Test
    fun invalidPlanStaysAnError() {
        val statuses = mapOf(
            "Workout plan is outside Garmin limits" to R.string.message_plan_outside_garmin_limits,
            "Garmin plan exceeds the 30-set limit" to R.string.message_garmin_plan_set_limit,
            "Workout plan is empty" to R.string.message_workout_plan_empty
        )
        statuses.forEach { (status, resource) ->
            val error = assertThrows(IllegalStateException::class.java) {
                planPushResult(delivered = false, status = status)
            }
            assertEquals(resource, planSyncErrorText(error).resourceId)
        }
    }

    @Test
    fun realTransferFailureStaysAnError() {
        val error = assertThrows(IllegalStateException::class.java) {
            planPushResult(delivered = false, status = "Send timeout")
        }
        assertEquals(R.string.message_garmin_send_failed, planSyncErrorText(error).resourceId)
    }
}
