package com.example.gymapp.sync

import android.content.Context
import com.example.gymapp.garmin.GARMIN_PLAN_QUEUED_STATUS
import com.example.gymapp.gymApplication
import com.example.gymapp.data.repository.NamedWorkoutSetDraft
import com.example.gymapp.util.TrainingProfile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** Outcome of a plan push that did not fail: sent to the watch, or saved and waiting for it. */
enum class PlanPushResult { Delivered, Queued }

/** Maps the Garmin manager result to a non-error outcome, or throws the manager status. */
internal fun planPushResult(delivered: Boolean, status: String): PlanPushResult = when {
    delivered -> PlanPushResult.Delivered
    status == GARMIN_PLAN_QUEUED_STATUS -> PlanPushResult.Queued
    else -> throw IllegalStateException(status)
}

/** Garmin statuses meaning "no Garmin watch is attached", which is not a delivery failure. */
private val GARMIN_ABSENT_STATUSES = setOf(
    GARMIN_PLAN_QUEUED_STATUS,
    "Trusted Garmin watch is not paired"
)

/**
 * Combines the Wear OS and Garmin outcomes. Delivered only when every connected target succeeded:
 * a failed Garmin send is never masked by a delivered Wear plan, and a failed Wear send is never
 * masked by a delivered Garmin plan.
 */
internal fun combinedPlanPushResult(
    wearDelivered: Boolean,
    wearFailed: Boolean,
    garminDelivered: Boolean,
    garminStatus: String
): PlanPushResult {
    // A real Garmin failure is reported first (it throws), whatever Wear did.
    if (!garminDelivered && garminStatus !in GARMIN_ABSENT_STATUSES) {
        return planPushResult(false, garminStatus)
    }
    if (wearFailed) throw IllegalStateException("Wear OS watch plan send failed")
    if (garminDelivered || wearDelivered) return PlanPushResult.Delivered
    return planPushResult(false, garminStatus)
}

class PhoneSyncClient(
    context: Context
) {
    private val appContext = context.applicationContext

    suspend fun pushWorkoutPlan(
        sets: List<NamedWorkoutSetDraft>,
        exerciseCatalog: List<String>,
        trainingProfile: TrainingProfile
    ): PlanPushResult {
        if (sets.isEmpty()) {
            throw IllegalArgumentException("Workout plan is empty")
        }

        val application = appContext.gymApplication
        val garminSyncManager = application.garminSyncManager
        // The Wear send (up to its message timeout) runs concurrently so it never delays Garmin.
        return coroutineScope {
            // Wear OS watch: only the paired, currently connected node receives the plan; with none
            // connected this is a silent no-op, so a Garmin-only user sees no change.
            val wear = async {
                try {
                    application.phoneWearSyncManager.pushWorkoutPlan(
                        sets = sets,
                        exerciseCatalog = exerciseCatalog,
                        trainingProfile = trainingProfile
                    ) to false
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    false to true
                }
            }
            val garmin = async {
                try {
                    garminSyncManager.cacheAndPushPlan(
                        sets = sets,
                        exerciseCatalog = exerciseCatalog
                    )
                } catch (error: CancellationException) {
                    throw error
                } catch (_: Exception) {
                    false
                }
            }
            val (wearDelivered, wearFailed) = wear.await()
            val garminDelivered = garmin.await()
            combinedPlanPushResult(
                wearDelivered = wearDelivered,
                wearFailed = wearFailed,
                garminDelivered = garminDelivered,
                garminStatus = garminSyncManager.lastPlanSyncStatus
            )
        }
    }
}
