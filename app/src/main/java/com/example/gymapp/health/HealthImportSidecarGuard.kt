package com.example.gymapp.health

import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Keeps a Health Connect import from being lost to the activity-only sidecar sync.
 *
 * The sync reads the local snapshot, merges it with the cloud, and later reconciles the local
 * store to the merged result, which deletes visible mirrors that are not in that result. An import
 * that commits between the read and the reconcile is not in the merged result, so the reconcile
 * would delete the new workout while its durable receipt stays, and it would never come back.
 *
 * One mutex serialises the three steps (snapshot read, import write, reconcile). Imports that
 * commit after the latest snapshot read are remembered, and the reconcile re-adds those that are
 * still stored locally but missing from its target, so the next sync uploads them instead.
 * Reads clear the memory: only the sync reads snapshots, and a read always precedes its reconcile.
 */
internal class HealthImportSidecarGuard {
    private val mutex = Mutex()
    private val importedSinceRead = HashSet<Long>()

    /** Runs [read] (the sidecar snapshot read) and forgets the imports it now contains. */
    suspend fun <T> readSnapshot(read: suspend () -> T): T = mutex.withLock {
        importedSinceRead.clear()
        read()
    }

    /** Runs [write] (one transactional import) and remembers a committed one. */
    suspend fun importWorkout(
        startedAt: Long,
        write: suspend () -> HealthImportPersistResult
    ): HealthImportPersistResult = mutex.withLock {
        write().also { if (it == HealthImportPersistResult.IMPORTED) importedSinceRead += startedAt }
    }

    /**
     * Runs [block] (the sidecar replacement). Inside it, call [protect] with the target and the
     * store's current items to get the target that must actually be written.
     */
    suspend fun <T> reconcile(block: suspend () -> T): T = mutex.withLock {
        block().also { importedSinceRead.clear() }
    }

    /** [target] plus the current items imported since the last snapshot read that it lacks. */
    fun protect(
        target: List<ActivityOnlyWorkoutItem>,
        current: List<ActivityOnlyWorkoutItem>
    ): List<ActivityOnlyWorkoutItem> {
        if (importedSinceRead.isEmpty()) return target
        val targeted = target.mapTo(HashSet()) { it.workoutStartedAt }
        val kept = current.filter { it.workoutStartedAt in importedSinceRead && it.workoutStartedAt !in targeted }
        if (kept.isEmpty()) return target
        return (target + kept).sortedBy { it.workoutStartedAt }
    }
}
