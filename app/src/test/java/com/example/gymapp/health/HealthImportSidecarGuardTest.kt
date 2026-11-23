package com.example.gymapp.health

import com.example.gymapp.data.repository.ActivityOnlyWorkoutItem
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class HealthImportSidecarGuardTest {
    private fun item(start: Long) = ActivityOnlyWorkoutItem(
        workoutStartedAt = start,
        durationSeconds = 1_800,
        gymCalories = 0.0,
        note = "n"
    )

    /** In-memory stand-in for the repository: the same guard protocol around a plain list. */
    private class FakeStore(private val guard: HealthImportSidecarGuard) {
        val stored = mutableListOf<ActivityOnlyWorkoutItem>()

        suspend fun read(): List<ActivityOnlyWorkoutItem> =
            guard.readSnapshot { stored.sortedBy { it.workoutStartedAt } }

        suspend fun import(item: ActivityOnlyWorkoutItem) {
            guard.importWorkout(item.workoutStartedAt) {
                stored += item
                HealthImportPersistResult.IMPORTED
            }
        }

        suspend fun reconcile(target: List<ActivityOnlyWorkoutItem>): List<ActivityOnlyWorkoutItem> =
            guard.reconcile {
                val effective = guard.protect(target, stored.toList())
                stored.clear()
                stored += effective
                stored.sortedBy { it.workoutStartedAt }
            }
    }

    @Test
    fun importCommittingBetweenSnapshotReadAndReconcileSurvives() = runBlocking {
        val store = FakeStore(HealthImportSidecarGuard())
        val old = item(1_000)
        store.import(old)
        val snapshot = store.read() // the sync merged this with a cloud that has nothing else
        store.import(item(9_000_000)) // lands after the read, before the reconcile

        // The cloud deleted `old`; the merged target is empty.
        val result = store.reconcile(emptyList())

        assertEquals(listOf(item(9_000_000)), result)
        assertEquals(listOf(old), snapshot)
    }

    @Test
    fun withoutAnInterleavedImportTheReconcileKeepsDeleting() = runBlocking {
        val store = FakeStore(HealthImportSidecarGuard())
        store.import(item(1_000))
        store.read()

        assertEquals(emptyList<ActivityOnlyWorkoutItem>(), store.reconcile(emptyList()))
    }

    @Test
    fun importMemoryIsClearedByTheNextRead() = runBlocking {
        val store = FakeStore(HealthImportSidecarGuard())
        store.import(item(1_000))
        store.read() // the import is now part of the synced snapshot

        // A remote deletion of that imported workout is honoured.
        assertEquals(emptyList<ActivityOnlyWorkoutItem>(), store.reconcile(emptyList()))
    }

    @Test
    fun targetWinsOverProtectedItemWithTheSameStart() = runBlocking {
        val store = FakeStore(HealthImportSidecarGuard())
        store.read()
        store.import(item(1_000))
        val edited = item(1_000).copy(note = "edited")

        assertEquals(listOf(edited), store.reconcile(listOf(edited)))
    }

    @Test
    fun importWaitsForARunningReconcileAndIsKeptAfterwards() = runBlocking {
        val guard = HealthImportSidecarGuard()
        val store = FakeStore(guard)
        store.read()
        val inside = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()

        val reconcile = async {
            guard.reconcile {
                inside.complete(Unit)
                release.await()
                store.stored.clear()
            }
        }
        inside.await()
        val import = async { store.import(item(5_000)) }
        // The import cannot run while the reconcile holds the guard.
        kotlinx.coroutines.yield()
        assertEquals(0, store.stored.size)
        release.complete(Unit)
        reconcile.await()
        import.await()

        assertEquals(listOf(item(5_000)), store.stored)
        assertEquals(listOf(item(5_000)), store.read())
    }
}
