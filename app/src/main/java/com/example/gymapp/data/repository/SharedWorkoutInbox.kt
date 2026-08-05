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
internal class SharedWorkoutInbox {
    private val nextId = AtomicLong(0L)
    private val mutablePending = MutableStateFlow<PendingSharedWorkout?>(null)

    val pending: StateFlow<PendingSharedWorkout?> = mutablePending.asStateFlow()

    fun offer(plan: SharedWorkoutPlan): PendingSharedWorkout {
        val normalized = SharedWorkoutLink.normalize(plan.exercises)
        val item = PendingSharedWorkout(
            id = nextId.incrementAndGet(),
            plan = normalized
        )
        mutablePending.value = item
        return item
    }

    fun consume(expectedId: Long): Boolean {
        while (true) {
            val current = mutablePending.value ?: return false
            if (current.id != expectedId) return false
            if (mutablePending.compareAndSet(current, null)) return true
        }
    }
}
