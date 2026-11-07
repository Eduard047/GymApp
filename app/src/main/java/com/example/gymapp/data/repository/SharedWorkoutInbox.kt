package com.example.gymapp.data.repository

import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

internal data class PendingSharedWorkout(
    val id: Long,
    val plan: SharedWorkoutPlan
)

/**
 * Process-local hand-off from an external URL to the currently active account UI.
 *
 * Shared plans contain no account or health data and are never persisted automatically. The UI
 * must show a preview and explicitly consume the matching generation before mutating a draft.
 */
internal enum class SharedWorkoutOfferResult { Accepted, Duplicate, Busy }

internal class SharedWorkoutInbox {
    private val nextId = AtomicLong(0L)
    private val mutablePending = MutableStateFlow<PendingSharedWorkout?>(null)

    val pending: StateFlow<PendingSharedWorkout?> = mutablePending.asStateFlow()

    /**
     * Stages [plan] for preview. A preview that is already pending is never replaced: an identical
     * plan is a [SharedWorkoutOfferResult.Duplicate] no-op, a different one is
     * [SharedWorkoutOfferResult.Busy] and the pending preview is kept.
     */
    fun offer(plan: SharedWorkoutPlan): SharedWorkoutOfferResult {
        val normalized = SharedWorkoutLink.normalize(plan.exercises)
        while (true) {
            val current = mutablePending.value
            if (current != null) {
                return if (current.plan == normalized) {
                    SharedWorkoutOfferResult.Duplicate
                } else {
                    SharedWorkoutOfferResult.Busy
                }
            }
            val item = PendingSharedWorkout(id = nextId.incrementAndGet(), plan = normalized)
            if (mutablePending.compareAndSet(null, item)) return SharedWorkoutOfferResult.Accepted
        }
    }

    /** Drops any pending preview, e.g. when the signed-in account it was opened for goes away. */
    fun clear() {
        mutablePending.value = null
    }

    fun consume(expectedId: Long): Boolean {
        while (true) {
            val current = mutablePending.value ?: return false
            if (current.id != expectedId) return false
            if (mutablePending.compareAndSet(current, null)) return true
        }
    }
}
